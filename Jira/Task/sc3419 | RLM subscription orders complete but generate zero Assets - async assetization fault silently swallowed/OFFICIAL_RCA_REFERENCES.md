# SC-3419 — Official Salesforce / RLM documentation references (the "RCA official document")

Consolidated from three web-research passes (raw, per-claim-flagged writeups at `evidence/W1_rlm_asset_lifecycle.md`, `evidence/W2_optimistic_lock.md`, `evidence/W3_async_flow_faults.md`). Every load-bearing claim about *our* defect maps to an authoritative Salesforce source below.

> **Sourcing caveat (honest):** `help.salesforce.com`, `developer.salesforce.com/docs`, and `architect.salesforce.com` are JavaScript-rendered SPAs that return only an empty shell to automated fetch (some 403). The literal page text was recovered from **Salesforce's own search-index abstracts of those exact canonical pages**, corroborated by renderable Salesforce-authored sources (Trailhead, Salesforce Architects, the SF-PM-maintained UnofficialSF) and the official release notes. Canonical URLs are listed for reviewer verification in a browser. A short list of items I could not render to the literal API value (exact `AssetAction.Type`/`Category` picklist strings; exact `IsAssetizable` semantics) is flagged "re-verify in-org" at the end.

---

## A. RLM Asset Lifecycle & Order-to-Asset (O2A)

1. **Assetize-on-activation is native and overridable.** On Order activation, the standard *"Assetize Orders"* flow auto-creates Assets from the activated order's products. The O2A flow is configured in **Revenue Settings by API name** — keep the packaged flow `revenue_o2aflows__o2aFlow`, or enter a **custom flow API name to override it** ("Save As New Flow"). → This is exactly how Fortra wired `Fortra_Assetize_Order` over `revenue_o2aflows__o2aFlow`.

2. **`createOrUpdateAssetFromOrder`** — standard async invocable action; input = **Order Id**; "creates an asset for each order item; **new assets for a new order, existing assets modified for change orders** (renewal/cancellation)." Matching key = **Account + Product** (one Asset per (Account, Product)). Completion/failure is signaled via the **`CreateAssetOrderEvent`** platform event (per-line: `CreateAssetOrderDtlEvent`). **The platform does not itself stamp the Order or block "Order Complete" — the (override) flow must react to failure.**

3. **Data model:** `OrderItem → AssetActionSource` (provenance of the change) `→ AssetAction` (the change record; available API v50.0+, fields not editable; records Δ qty/amount/MRR) `→ Asset`, time-sliced by `AssetStatePeriod`.
   - **AssetAction.Type** = **Generate** (initial sale) vs **Change** (modify).
   - **AssetAction.Category** = **Initial Sale / Renewals / Amendments / Cancellations** (renewal adds a new state period; cancellation does not).
   - Live data matches: **47× Generate** (present-dated) vs **1× Change** (the future-dated renewal `BESECB` line).

4. **Gating:** `Product2.IsAssetizable` gates whether a line assetizes; assetizable lines (including future-dated) assetize on activation; assets carry lifecycle dates / state periods.

**Maps to SC-3419:** override + async action + event-driven failure signaling is the documented design. The "one Asset per Account+Product, update the matched Asset" key is *why* 32 duplicate same-product lines on an account that already has assets converge on one row and collide. The platform is working as specified; the **single deviation is Fortra's flow swallowing the documented failure** instead of reacting to it.

**Sources:**
- RLM Dev Guide — Asset Lifecycle Overview: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/asset_lifecycle_overview.htm
- RLM Dev Guide — Create or Update Asset From Order: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order.htm
- RLM Dev Guide — AssetAction: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetaction.htm
- RLM Dev Guide — AssetActionSource: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm
- Platform Events — CreateAssetOrderEvent: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_createassetorderevent.htm
- Subscription Mgmt renew guide: https://developer.salesforce.com/docs/revenue/subscription-management/guide/solution-renew.html
- Trailhead — Asset Lifecycle Management with Revenue Cloud: https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations
- Release Note — Control When Order Products Are Converted to Assets: https://help.salesforce.com/s/articleView?id=release-notes.rn_subscription_mgmt_convert_order_products_to_assets.htm&release=246&type=5

---

## B. The optimistic-lock collision — "the asset was updated by another process"

1. **`INVALID_API_INPUT` is a contract/input-violation envelope**, not a row-lock code; "the asset was updated by another process" rides as the human-readable detail inside it (Trailblazer payload shape `"statusCode":"INVALID_API_INPUT"`). **No named Salesforce Known Issue and no platform hotfix** exists for this string on `createOrUpdateAssetFromOrder`.

2. **Optimistic vs pessimistic (decisive):**
   - `UNABLE_TO_LOCK_ROW` = **pessimistic** lock-acquisition timeout (waits ~10s).
   - "updated by another process" = **optimistic** version-check (`SystemModstamp`) rejection — the row changed between read and commit; **instant** rollback, no wait.
   - Our FINEST signature (**ok=0 bad=1, 2 SOQL, CPU 0, no 10s wait**) matches the **optimistic** column and **excludes** `UNABLE_TO_LOCK_ROW`. First writer moves the matched Asset version N→N+1; the next same-product line's stale read → the error. **Deterministic**, as claimed.

3. **Quantity vs duplicate lines (AC5):** the documented asset pattern is explicitly *"bump Quantity on the matched Asset when the product matches; create a new Asset only for a different product."* De-duping makes each Asset the target of exactly one create-or-update → removes the multiple-writers-per-row condition. **AC5's "de-dup via Quantity" is doc-aligned, not a hack.**

4. **⚠️ AC5 count flag:** under the documented Account+Product matching key, *true* duplicates would normally **collapse to one Asset with Quantity rolled up** (→ 4 Assets). The "**expect 32 Assets**" target holds **only if** the 32 lines remain 32 distinct (Account, Product) targets **or** the org configures **per-unit / serialized** asset granularity. The org's existing account assets are Quantity = 1 per row (consistent with per-unit), but **the recovery run is the only way to settle 32-vs-4.** Validate before asserting the count.

5. **Decomposition:** no doc names decomposition as a *cause* of the lock error, but the official "one bundle → many technical rows" model is exactly what multiplies writers per Asset under the matching key — a sound RCA corollary, not a citable Salesforce statement.

**Maps to SC-3419:** docs corroborate the mechanism of both layers and endorse the Quantity remediation, **but there is no Salesforce-acknowledged defect or hotfix** — the fix is application-level. Present Layer 2 as *"documented framework behavior + org-specific data shape,"* not *"Salesforce-confirmed bug."*

**Sources:**
- REST API — Status Codes and Error Responses: https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/errorcodes.htm
- Help 000387767 — Unable to lock row: https://help.salesforce.com/s/articleView?id=000387767&type=1
- Help 000393690 — How Optimistic Locking Works with Persistent Objects: https://help.salesforce.com/s/articleView?id=000393690&type=1
- Salesforce Ben — Record Locking / Concurrency: https://www.salesforceben.com/salesforce-record-locking-tips-for-developers-how-to-avoid-concurrency-issues/
- Trailblazer — INVALID_API_INPUT payload: https://trailhead.salesforce.com/trailblazer-community/feed/0D54S00000DwuuPSAR
- Trailblazer — UNABLE_TO_LOCK_ROW: https://trailhead.salesforce.com/trailblazer-community/feed/0D54V00007T4NoHSAV

---

## C. Async flow path, fault handling & native-flow override

1. **"Run Asynchronously" / `AsyncAfterCommit` scheduled path = separate post-commit transaction.** It does not start until the Run-Immediate paths commit; fires at **Order-of-Execution step 20** (post-commit logic), reads committed state, and runs in a **new transaction with fresh per-transaction governor limits** (100 SOQL / 150 DML / 10,000ms CPU). No completion-timing guarantee; shares the org daily async budget; `$Record__Prior` unavailable. → Matches our FINEST trace (CPU 0, 2 SOQL): a **hard throw in a fresh transaction, not limit exhaustion.**

2. **A graceful-end fault path SWALLOWS the error (the genuine defect).** Default behavior (no fault path) at least surfaces: red error + full rollback + admin error email. Adding a fault connector transfers ownership of surfacing. A fault path that only assigns `{!$Flow.FaultMessage}` and stops does three things together = silent swallow:
   - suppresses the default unhandled-fault error + email,
   - *"if a flow's error sends it down a fault path, the transaction is not rolled back"* → the Order **stays Activated**,
   - no screen (background flow), no email, no record write.
   This is exactly Defect A. Documented surfacing channels: error email, custom Error-Log object, **platform event** (survives rollback), or **custom error field on the record**. `FlowExecutionErrorEvent` is **screen-flow-only (API 47+)** — unavailable to an autolaunched async flow.

3. **Custom autolaunched flow overrides the managed RLM O2A flow** — explicitly supported ("clone the default flow" / "leverage the provided apex action in a custom flow"). `Fortra_Assetize_Order` overrides `revenue_o2aflows__o2aFlow`, keeping the platform action `createOrUpdateAssetFromOrder`.

**Maps to SC-3419:** for a **screenless, post-commit, un-rolled-back** async override, writing a **custom error field** is the only in-context Salesforce-endorsed surfacing channel (screen message impossible; `FlowExecutionErrorEvent` screen-only). **V14's surface-on-record is platform-correct.** AC3 (never write Status) honors the documented "async can't self-retry" caveat — retry must be an explicit re-trigger (AC5).

**Sources:**
- SF Architects — Record-Triggered Automation Decision Guide: https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered.html
- SF Help — Scheduled Paths: https://help.salesforce.com/s/articleView?id=platform.flow_concepts_trigger_scheduled_path.htm&type=5
- SF Help — Async path release note (Spring '21 / 234): https://help.salesforce.com/s/articleView?id=release-notes.rn_automate_flow_builder_asynchronous_path.htm&release=234&type=5
- SF Help — Per-Transaction Flow Limits: https://help.salesforce.com/s/articleView?id=platform.flow_considerations_limit_transaction.htm&type=5
- SF Help — Customize What Happens When a Flow Fails: https://help.salesforce.com/s/articleView?id=platform.flow_build_logic_fault.htm&type=5
- SF Help — Default Flow Error Handling: https://help.salesforce.com/s/articleView?id=platform.flow_build_logic_fault_default.htm&type=5
- Trailhead — Handle Flow Errors with Fault Paths: https://trailhead.salesforce.com/content/learn/modules/flow-implementation-2/handle-flow-errors-with-fault-paths
- Trailhead — Roll Back Changes After an Error: https://trailhead.salesforce.com/content/learn/modules/flow-implementation-2/roll-back-changes-after-an-error
- Developers — FlowExecutionErrorEvent (screen flows only): https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_flowexecutionerrorevent.htm
- UnofficialSF — Triggering Flows (OoE step 20 post-commit cohort): https://unofficialsf.com/pauple_helpie/triggering-flows/
- SF Architects — Asynchronous Processing (publish-after-commit): https://architect.salesforce.com/decision-guides/async-processing
- SF Architects (Medium) — Automate Revenue Cloud Customer Asset Lifecycle Management: https://medium.com/salesforce-architects/automate-revenue-cloud-customer-asset-lifecycle-management-fa2c0ccee3b5

---

## Re-verify in-org (items not rendered to the literal from docs)
- `sf sobject describe AssetAction` → exact `Type` / `Category` picklist values (Generate/Change; Initial Sale/Renewals/Amendments/Cancellations).
- `Product2.IsAssetizable = true` on the 4 SKUs (already confirmed live: all true).
- Revenue Setting O2A flow API name points at `Fortra_Assetize_Order` (override of `revenue_o2aflows__o2aFlow`).
- Whether this org assetizes **per-unit** (→ AC5 = 32) or **per-Account+Product with Quantity rollup** (→ AC5 = 4) — settle via the AC5 recovery run.
