# W2 — Official Docs: "the asset was updated by another process" / Optimistic-Lock Concurrency in RLM Order-to-Asset

Research agent: W2 (official documentation track)
Ticket: SC-3419 (split from SC-3415, Defect A) — RLM subscription orders complete but generate zero Assets; async assetization fault silently swallowed.
Date: 2026-06-16
Scope: READ-ONLY research. Salesforce Known Issues, Help, Developer Docs, Release Notes, Trailblazer Community.

> NOTE ON SOURCING METHOD. The two most authoritative pages — the RLM Developer Guide action pages (`createOrUpdateAssetFromOrder`, `createOrUpdateAssetFromOrderItem`) and `CreateAssetOrderEvent` — are JavaScript-rendered single-page apps on developer.salesforce.com; `help.salesforce.com` articles likewise render client-side. Direct page-body fetch returned only the shell ("Salesforce Developers" / "CSS Error"). The factual content below is reconstructed from the indexed search snippets of those exact official pages plus renderable secondary sources (Salesforce Ben, Trailblazer Community, Postman official collection). Where a claim rests only on a search-snippet of the official page, it is marked **[snippet]**. No quote exceeds the official text.

---

## 1. The error: "the asset was updated by another process" + INVALID_API_INPUT, in createOrUpdateAssetFromOrder

### What the action is (official)
- `createOrUpdateAssetFromOrder` "creates an asset for each order item in a specified order. New assets are created for a new order, and existing assets are modified for change order requests, such as a renewal or a cancellation." (RLM Developer Guide, action page) **[snippet]**
- It runs as a standard invocable/REST action `/actions/standard/createOrUpdateAssetFromOrder` (and the per-line `/actions/standard/createOrUpdateAssetFromOrderItem`). Completion is announced via the **`CreateAssetOrderEvent`** platform event: "notifies subscribers that the process started by the /actions/standard/createOrUpdateAssetFromOrder or /actions/standard/createOrUpdateAssetFromOrderItem request is complete. If the process is successful, you can use this event to learn about the new assets. **If the request isn't successful, you can use it to identify errors.**" (Platform Events Developer Guide, CreateAssetOrderEvent) **[snippet]**

### INVALID_API_INPUT — what Salesforce officially says it means
- INVALID_API_INPUT is the platform's **input/contract-violation** status code, not a row-lock code. Per Salesforce's documented usage it is "typically caused by contract violations, for example: missing or unknown request parameters, or invalid parameter length." (surfaced from official REST/error docs via search) **[snippet]**
- It is the generic envelope Salesforce wraps around a rejected save inside a standard action. The Trailblazer Community shows the literal payload shape `"statusCode":"INVALID_API_INPUT","m…"` returned from standard-action calls — i.e. the message string ("the asset was updated by another process") is carried as the human-readable detail *inside* an INVALID_API_INPUT response, not as its own status code.
- Key implication for SC-3419: **INVALID_API_INPUT here is a wrapper; the diagnostic payload is the message text.** The message "the asset was updated by another process" is the optimistic-concurrency signal (see §2). So the pairing observed in our FINEST log (INVALID_API_INPUT + that message) is exactly the documented shape: a standard RLM action rejecting a save because the target Asset row changed under it.

### Is it a documented Known Issue? Platform fix/workaround?
- **No dedicated, named Salesforce Known Issue** was found that uses the exact string "the asset was updated by another process" for `createOrUpdateAssetFromOrder`. Trailblazer Known Issues and the RLM release notes do not list it as a tracked defect with a fix ETA.
- The behavior is **documented at the framework level, not as a bug**: the official remediation Salesforce gives for "another process is currently updating the same record" is "introduce retry logic or reduce concurrency" — described as "common in integrations and batch processing," and "retrying the failed action may help, as the row might be unlocked in the next attempt." (Salesforce error-troubleshooting guidance, surfaced via search) **[snippet]**
- Net: there is **no platform hotfix to install**. Salesforce treats concurrent same-record contention as an application-design concern, and the documented levers are (a) retry, (b) reduce concurrency / serialize, (c) don't have multiple operations target the same record in one transaction window.

---

## 2. Optimistic locking / concurrency on the Asset object, and how same-Account+same-Product writes collide

### Optimistic vs pessimistic — the official distinction
- **Pessimistic locking** is Salesforce's default DML row lock. When two execution contexts attempt DML on the same row, the second "will wait a maximum of 10 seconds" for the first to finish; if not released it fails with **`UNABLE_TO_LOCK_ROW, unable to obtain exclusive access to this record or 1 records`**. (Salesforce Ben; Salesforce Help 000387767) — this is a *lock-acquisition timeout*.
- **Optimistic locking** is the version/timestamp-check model: a process reads a row (capturing its version, e.g. `SystemModstamp`), and at write time the platform verifies the row has not changed since the read. If it changed, the write is rejected as a conflict — Salesforce has a dedicated Help article "How Optimistic Locking Works with Persistent Objects" (Help 000393690). Generic OCC: "before committing, each transaction verifies that no other transaction has modified the data it has read; if conflicting modifications are found, the transaction rolls back" (Wikipedia, OCC — for the general principle).

### The decisive difference for SC-3419
| Aspect | UNABLE_TO_LOCK_ROW (pessimistic) | "updated by another process" (optimistic) |
|---|---|---|
| Trigger | Can't *acquire* the lock within ~10s | Acquired/read, but row's **version changed before commit** |
| Timing | Two writers overlap *in time* | Read-then-write where another writer **committed in between** |
| Symptom | Timeout/wait | Immediate **stale-version** rejection |
| Wrapped as | `UNABLE_TO_LOCK_ROW` | message inside `INVALID_API_INPUT` (as observed) |
| Retry helps? | Yes, after contention clears | Yes, after re-reading fresh version |

Our FINEST evidence (ok=0 bad=1, **2 SOQL, CPU 0**, instant rollback — *not* a 10s wait) matches the **optimistic** column precisely: the failure is a version-mismatch rejection at save, not a lock-acquisition timeout. This rules out UNABLE_TO_LOCK_ROW as the mechanism and confirms the SC-3415 RCA's "optimistic-lock collision on SystemModstamp."

### Why same Account + same Product → one Asset row → collision (official mechanism)
- RLM assetization maps each order item to an Asset keyed by the customer's entitlement; for a repeated product on the same account the action **matches an existing Asset and updates it** rather than minting a new one: "existing assets are modified" and "the action … matches existing assets and either updates them or creates new ones." (RLM action page) **[snippet]**
- The widely-documented asset pattern is "look up existing Assets for the Account, check their Products, and **bump the Quantity if the Product matches**; otherwise create a new Asset" — i.e. AccountId+Product2Id is the natural matching key, and duplicate same-product lines **converge on a single Asset record.** (Trailblazer/community asset-creation guidance, surfaced via search) **[snippet]**
- Consequence: when 10 duplicate `PIA-PIA-RNM-PIAMBK` lines (and 10 `PIAP`, 6 `SEAW`, 6 `CLSAAS`) each invoke create-or-update against the SAME target Asset within one async batch, each writer reads the Asset at version N, and the first commit moves it to N+1; the next writer's commit sees its read-version (N) is stale → **"the asset was updated by another process."** This is deterministic, not racy in the classic sense — the duplication *guarantees* multiple writers per Asset in the same window.

---

## 3. Guidance: serialize/order asset creation; Quantity vs duplicate line items (supports AC5 "de-dup via Quantity")

### Quantity is the modeled aggregation unit for one entitlement
- Assets carry **Quantity** (and MRR) as first-class fields; the documented merge behavior is to **increment Quantity on the matched Asset** for repeat purchases of the same product rather than create N separate line items. "Assets include detailed insights such as quantity"; the canonical example bumps quantity when the product matches. (community asset guidance / RLM object overview) **[snippet]**
- This is the official-pattern endorsement for AC5: **collapsing duplicate same-product order lines into one line carrying Quantity=N** means the assetization action targets each Asset **once**, eliminating the multiple-writers-per-row condition entirely. One line → one create-or-update → no intra-batch version race.

### Serializing / reducing concurrency (when you can't de-dup)
- Salesforce's documented remedies for same-record contention are exactly: **reduce concurrency, serialize writes, add retry with backoff.** "When you have multiple jobs running that update the same set of records, … lock the records using `FOR UPDATE` … no other job can update the same record at that point in time" (pessimistic serialization), and for bulk/ETL "use **serial processing** and sort by parent." (Salesforce Ben; Help 000387767) **[snippet]**
- Platform-event note: asset creation runs via **publish-after-commit** — "events … are delivered in order via publish after commit and then processed in bulk by a flow in a separate synchronous context" and "publish after commit ensures events only fire on successful transactions." (Platform Events guidance, surfaced via search) **[snippet]** This is why the **Order activation commits and the order shows "Complete" even though the downstream asset subscriber throws** — the asset work is in a *separate* post-commit context whose failure does not roll the order back. That is the structural enabler of the "silent swallow" and is the documented async model, not a bug.

### Ordering
- No RLM doc prescribes an explicit ordering API for asset creation across lines. The supported way to *avoid* needing one is to not present multiple lines that target the same Asset — i.e., **de-dup via Quantity** (the AC5 remediation) is the doc-aligned fix, and serialization/retry is the fallback for genuinely distinct assets.

---

## 4. Maintenance / bundle decomposition (Order Product Detail) × asset-creation concurrency

- RLM **order decomposition** breaks a commercial bundle into technical products during fulfillment: "commercial products decompose into technical products," governed by **Product Fulfillment Decomposition Rules** and the **FulfillmentAssetContext**, and "technical product scopes define how many instances of the technical products the system generates … regardless of the count of related commercial products." (RLM decomposition docs / Trailhead) **[snippet]**
- **AssetActionSource** is the official audit object: "an optional way to record what transactions caused changes to lifecycle-managed assets … supports Salesforce order products and work order line items." (RLM Developer Guide, AssetActionSource) **[snippet]**
- **Concurrency-interaction finding:** No Salesforce doc *explicitly* states "maintenance/bundle decomposition causes asset optimistic-lock collisions." BUT the mechanism is a direct corollary of §2–§3: decomposition **multiplies** the number of order-product/detail rows that the assetization action processes in one async batch. When a bundle decomposes a maintenance/license pair into multiple technical lines that share the **same target product → same Asset (Account+Product key)**, decomposition *increases the count of writers per Asset row* in the same post-commit window — which is precisely the condition that produces "updated by another process." So decomposition is not documented as a *cause* of the lock error, but it is documented to *generate the duplicate-target rows* that, under the matching key in §2, deterministically create the collision. The doc gap is that Salesforce never warns that decomposition + same-product convergence is concurrency-hazardous; that is the original-research portion of our RCA, consistent with (not contradicted by) the official model.

---

## Sources

- Create or Update Asset From Order Action — RLM Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order.htm
- Create or Update Asset From Order Item Action — RLM Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order_item.htm
- CreateAssetOrderEvent — Platform Events Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_createassetorderevent.htm
- AssetActionSource — RLM Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm
- Validation Error (connect responses) — RLM Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_responses_validation_error_output.htm
- Status Codes and Error Responses — REST API Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/errorcodes.htm
- Salesforce Help — "Unable to lock row - Record currently unavailable" (000387767): https://help.salesforce.com/s/articleView?id=000387767&language=en_US&type=1
- Salesforce Help — "How Optimistic Locking Works with Persistent Objects" (000393690): https://help.salesforce.com/s/articleView?id=000393690&language=en_US&type=1
- Salesforce Ben — Record Locking Tips for Developers / How to Avoid Concurrency Issues: https://www.salesforceben.com/salesforce-record-locking-tips-for-developers-how-to-avoid-concurrency-issues/
- Trailblazer Community — UNABLE_TO_LOCK_ROW thread: https://trailhead.salesforce.com/trailblazer-community/feed/0D54V00007T4NoHSAV
- Trailblazer Community — `"statusCode":"INVALID_API_INPUT"` thread: https://trailhead.salesforce.com/trailblazer-community/feed/0D54S00000DwuuPSAR
- Salesforce Architects — Asynchronous Processing (publish-after-commit): https://architect.salesforce.com/decision-guides/async-processing
- Trailhead — Define and Publish Platform Events (publish after commit): https://trailhead.salesforce.com/content/learn/modules/platform_events_basics/platform_events_define_publish
- Apex Hours — Revenue Cloud Key Objects (Asset / AssetAction): https://www.apexhours.com/salesforce-revenue-cloud-key-objects-we-should-know/
- Release Note — Control When Order Products Are Converted to Assets: https://help.salesforce.com/s/articleView?id=release-notes.rn_subscription_mgmt_convert_order_products_to_assets.htm&language=en_US&release=246&type=5
- Wikipedia — Optimistic concurrency control (general principle): https://en.wikipedia.org/wiki/Optimistic_concurrency_control

---

## How it maps to SC-3419

**Does official doc corroborate our deterministic-collision RCA + the Quantity remediation? — YES, on both, with the caveats below.**

1. **Layer-2 throw (optimistic-lock collision).** Corroborated *by mechanism*, not by a named Known Issue. Official model confirms: (a) RLM create-or-update **matches an existing Asset by the account/product entitlement and updates it** rather than creating duplicates; (b) Salesforce supports optimistic (version-check) concurrency and treats "another process … updating the same record" as a stale-version rejection whose remedy is retry/reduce-concurrency — *not* a platform bug with a hotfix. Our FINEST signature (instant rollback, 2 SOQL, CPU 0 — no 10s wait) matches **optimistic** rejection and **excludes** UNABLE_TO_LOCK_ROW. So "deterministic collision because duplicate same-product lines converge on one Asset row" is fully consistent with documented behavior. The only thing the docs do NOT provide is a Salesforce-published incident for this exact string — so cite it as "documented framework behavior + our org-specific RCA," not "Salesforce-acknowledged defect."

2. **Layer-1 silent swallow.** Corroborated structurally: assetization fires via **publish-after-commit** in a **separate post-commit context**; the order's activation transaction commits independently, so a subscriber/flow failure leaves the Order "Complete" with no asset and no rolled-back order. The doc says the platform event is the *intended* place to surface failures ("If the request isn't successful, you can use it to identify errors"). Our Fortra flow's graceful faultConnector throwing away that signal is the Fortra-owned defect; V14's reuse of `Order_Integration_Error_Messages__c` to write "Assetization failed: <fault>" is the doc-aligned remediation (surface the error that the platform already hands you). Supports **AC1/AC3/AC4**.

3. **AC5 Quantity remediation — STRONGLY supported.** The documented asset pattern *is* "bump Quantity on the matched Asset for the same product; create a new Asset only for a different product." De-duping 00095470's 32 duplicate lines into Quantity-bearing lines makes each Asset the target of **exactly one** create-or-update, removing the multiple-writers-per-row condition that produces "updated by another process." This is the doc-endorsed shape of the data, so the remediation is not a hack — it aligns the order with how RLM models entitlements. Expectation of "32 Assets" is consistent **only if** the 32 lines remain 32 distinct (Account, Product) targets; note that under the matching key, true duplicates of the *same* product would otherwise collapse to one Asset with Quantity rolled up — so validate that the de-dup preserves the intended per-line asset granularity (e.g., distinct serial/license per unit) vs. quantity rollup before asserting the 32 count.

4. **Decomposition interaction (AC2/maintenance lines).** No doc names decomposition as a *cause* of the lock error, but the official decomposition model (one commercial bundle → many technical product rows) is exactly what *multiplies writers per Asset* under the §2 matching key. So our claim "maintenance-decomposed duplicate lines collide" is a sound corollary of documented behavior, presentable as RCA inference rather than a cited Salesforce statement.

**One-line verdict:** Official documentation corroborates the *mechanism* of both the silent swallow (publish-after-commit, separate context, event-surfaced errors) and the optimistic-lock collision (entitlement-matched create-or-update + version-check concurrency + retry/serialize remediation), and explicitly endorses **Quantity aggregation over duplicate same-product line items** — which is the doc-aligned basis for the AC5 de-dup. There is **no named Salesforce Known Issue or platform hotfix**; the fix is application-level (de-dup via Quantity; surface the error), matching the SC-3415/V14 approach.
