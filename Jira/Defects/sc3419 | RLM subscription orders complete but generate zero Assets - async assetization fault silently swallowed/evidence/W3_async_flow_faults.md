# SC-3419 — W3 Research: Async Record-Triggered Flow Paths, Fault Handling, and Native Flow Overrides

**Agent:** W3 (official Salesforce docs research)
**Date:** 2026-06-16
**Ticket:** SC-3419 — "RLM subscription orders complete (Order Complete) but generate zero Assets — async assetization fault silently swallowed" (split from SC-3415, Defect A)
**Scope:** Validate, against authoritative Salesforce documentation, that (a) the async assetize path runs in a separate post-commit transaction; (b) a fault path that only "ends gracefully" swallows the error; (c) custom autolaunched flows override the RLM-managed O2A flow; (d) surfacing the failure on the record (V14's `Order_Integration_Error_Messages__c` write) is the platform-correct remediation, with the caveat that an async path can't easily self-retry.

> NOTE ON SOURCING: Salesforce's first-party docs on `help.salesforce.com` and `developer.salesforce.com` are client-side (JS) rendered and return only a loading/CSS-error shell to automated fetchers (and `architect.salesforce.com` returns HTTP 403). Where the canonical first-party page text could not be machine-read directly, the substantive text was recovered via Salesforce's own search-result snippets and corroborated against Salesforce-authored secondary channels (Salesforce Trailhead modules, the Salesforce Architects publication, and UnofficialSF — a Salesforce-PM-maintained community site). Every load-bearing claim below cites the authoritative first-party URL plus at least one corroborating source. The canonical URLs are listed in **Sources** for the reviewer to open in a browser.

---

## 1. The "Run Asynchronously" path runs in a SEPARATE transaction after commit, with its own governor budget

**Mechanism (official Order of Execution placement).** A record-triggered flow's **Run Asynchronously** path is "fire-and-forget" automation that executes **in a separate transaction after the original record-saving transaction has been successfully committed to the database." It does not begin "until all work on the Run Immediate paths gets completed and those transactions are committed,"** and it slots in at **step 20 of the Apex/Salesforce Order of Execution**: *"After the changes are committed to the database, executes post-commit logic such as sending email and executing enqueued asynchronous Apex jobs, including queueable jobs and future methods."* (UnofficialSF "Triggering Flows," quoting/summarizing the official Order of Execution and Winter '22 async-path behavior.)

This is exactly the `pathType = AsyncAfterCommit` scheduled-path the Fortra flow uses: the metadata models the async path as a scheduled path that fires immediately *after commit* (as opposed to a time-delayed scheduled path). UnofficialSF: Run Asynchronously *"usually executes within a second,"* runs *"with the same 'cohort' as the save,"* and *"any values or queries in the asynchronous path will reflect any changes made on the synchronous path"* — i.e., it reads the **committed** post-save state, which is why our assetize path sees the activated order.

**Own/fresh governor limits.** Because it is a new transaction, the async path is **not** bound by the synchronous save's accumulated limits: *"Asynchronous paths run separately from the initial save transaction … causing Salesforce to put them in a lower priority queue that gets handled separately from the open trigger transaction,"* which *"prevent[s] your automation from hitting strict synchronous governor limits (like CPU time, SOQL queries, or DML statements per transaction)."* (Salesforce Architects *Record-Triggered Automation* decision guide, via SF search snippet; corroborated by Salesforce Ben.) Per-transaction limits that reset for that new transaction include **100 SOQL queries, 150 DML statements, and 10,000 ms CPU time** (Salesforce Ben, *Complete Guide to Salesforce Flow Limits*).

> This corroborates the SC-3415 FINEST trace ("ok=0 bad=1, 2 SOQL, CPU 0"): the failure consumed essentially no budget because it threw immediately inside the fresh async transaction — the collision is a hard platform throw, not a limit exhaustion.

**Caveats from the official model.** Async execution carries no completion/timeliness guarantee: *"the covenant about all asynchronous operations is that there's no guarantee and in certain load conditions, the path's execution may be delayed."* It also **shares the org-wide daily async governor limits** with other async flow interviews and is *"not designed for extremely high-volume processing"* (Salesforce Architects decision guide). `$Record__Prior` is not available on the async path.

---

## 2. A fault path that only "ends gracefully" SWALLOWS the error — this is the genuine defect

### 2a. Default behavior (no fault path): roll back + surfaced error
With no fault connector, *"the Flow just fails with a generic 'unhandled exception' and your user gets a nasty red error message,"* and **"the whole flow is rolled back."** For all flow errors, *"Salesforce also sends an email with details about the flow and the error"* to the admin/last-modifier (Salesforce default fault handling; Trailhead *Handle Flow Errors with Fault Paths*; *Roll Back Changes After an Error*). So by default a failure is at least **visible** (red error + email).

### 2b. Adding a fault path that just ends = the error is consumed, no surfaced signal
The instant you draw a fault connector, you take ownership of surfacing. The official Trailhead *Roll Back Changes After an Error* module states the trap precisely:

- **"if a flow's error sends it down a fault path, the transaction is not rolled back."**
- For record-triggered flows specifically: **"if an error sends the flow down a fault path, Salesforce completes the change that triggered the flow, even though the flow failed."**

So a fault path that only assigns `{!$Flow.FaultMessage}` to a variable and **stops** does three things that, combined, equal a silent swallow:
1. It **suppresses** the default unhandled-fault error and the default error email (the fault is now "handled").
2. It does **not** roll back — the triggering change (Order = Activated) **persists**.
3. It produces **no outbound signal** — no screen (record-triggered/async flows have no UI: *"A Record-Triggered Flow or Scheduled Flow runs in the background, so the user won't see a screen"*), no email, no record write.

This is **exactly** the SC-3415 Defect A mechanism: `Fortra_Assetize_Order`'s `faultConnector` ended gracefully on the async path, so the `createOrUpdateAssetFromOrder` throw was caught-and-dropped → the order stayed **Activated / "Order Complete" with zero Assets and no surfaced error.** The swallow is the genuine, Fortra-owned defect; the underlying optimistic-lock throw is the trigger, but the *invisibility* is caused by the graceful-end fault path.

### 2c. Salesforce best practice for surfacing flow errors (the menu V14 chose from)
Official/Salesforce-authored guidance for surfacing handled faults:
- **Error email / Email Alert action** to admins, including the fault message and resource values: *"configure the fault connectors in your flow so that you always receive an email when a flow fails, and include the current values of all your flow's resources."* (Salesforce *Other Examples of Error Handling in Flows*.)
- **Custom Error-Log object record** capturing `{!$Flow.FaultMessage}`: *"log the error to a custom 'Error Log' object."*
- **Platform Event** publish, because *"a Platform Event … stays in the database even if the main transaction rolls back"* (the one channel that survives rollback). The screen-flow-only **`FlowExecutionErrorEvent`** platform event exists for this but **only covers screen flow executions** (API 47.0+) — it does **not** fire for autolaunched/record-triggered/async flows, so it is *not* available to an assetize autolaunched flow.
- **Custom error field on the triggering record** — write the fault to a field on the record so it is visible in context. (This is V14's choice; see §4.)

---

## 3. A custom autolaunched flow OVERRIDES the RLM-managed O2A template flow

**Official capability.** In Revenue Lifecycle Management / Revenue Cloud, asset generation is driven by a **Salesforce-managed Order-to-Asset (O2A) flow** that fires on order activation: *"Upon activation of an order, Salesforce's standard flow automates the creation of assets from the products listed in the activated order."* Salesforce explicitly supports overriding it: *"This automation can be modified or you can leverage the provided apex action in a custom flow to create your assets at the correct moment in your business process,"* and *"By cloning the default flow and adding unique business logic through standard flow elements, companies can tailor the flow."* (Asset Lifecycle, RLM Developer Guide; corroborated by Salesforce Architects, *Automate Revenue Cloud Customer Asset Lifecycle Management*.)

In the Fortra org this override is realized as the custom autolaunched flow **`Fortra_Assetize_Order`** standing in for the managed template **`revenue_o2aflows__o2aFlow`** (the `overriddenFlow` relationship in the O2A configuration). The override keeps the platform Apex action **`createOrUpdateAssetFromOrder`** as the actual asset-creating element; the custom flow only wraps invocation, sequencing, and (in V14) error surfacing around it.

**The Apex action's documented contract (why the collision is deterministic).** The RLM **"Create or Update Asset From Order"** action *"creates an asset for each order item in the specified order. New assets are created for a new order, and existing assets are modified for change order requests."* Completion/failure is reported through **`CreateAssetOrderEvent`**, which *"notifies subscribers when the process is complete, providing information about new assets if successful or error details if the request fails."* (RLM Developer Guide.) Asset identity is keyed on **AccountId + Product2Id**, so **duplicate same-product lines plus maintenance-decomposed lines on an account that already owns that product all resolve onto ONE existing Asset row** and serialize updates against its `SystemModstamp` → the `INVALID_API_INPUT "the asset was updated by another process"` optimistic-lock throw observed in SC-3415. The platform's own surfacing channel for that throw is the event's "error details," which the managed template would route to a fault path — and which our override had been silently dropping.

---

## 4. V14 is the platform-correct remediation — surface on the record; accept that async can't self-retry

**Why "surface on the record" is the correct pattern here.** Given the constraints established above:
- The flow is **async/autolaunched** → no screen, so a Screen-element error message is impossible.
- The triggering change is **already committed** (order Activated) and the async transaction **won't roll it back** anyway → there is nothing to "block"; the only useful action is to *record* the failure.
- `FlowExecutionErrorEvent` is **screen-flow-only** → unavailable.
- The remaining Salesforce-endorsed surfacing channels are **error email**, a **custom error-log object**, a **platform event**, or a **custom error field on the record**. Writing a **custom error field on the Order** is the most in-context, lowest-friction of these and is an explicitly listed best practice.

**V14 implements exactly that, correctly:**
- **AC1 — surface the failure:** fault path writes `Order_Integration_Error_Messages__c = "Assetization failed: <fault>"` instead of leaving a silently asset-less "Order Complete." This converts the swallowed fault into a durable, in-context signal — the platform-correct replacement for the dropped fault path. ✔
- **AC3 — never re-fire:** V14 *"never writes Status,"* so it cannot retrigger the record-triggered/O2A automation. This respects the documented hard caveat that **an async path can't easily self-retry**: the async transaction is post-commit and un-rolled-back, so there is no transactional retry; any retry must be an explicit, separate re-trigger (re-activation or a controlled re-run after de-duping lines via Quantity), never a Status write from inside the surfacing flow. ✔
- **AC4 — clear without clobbering:** success path clears the field **only if it `StartsWith("Assetization failed")`**, so a genuine assetization recovery never erases a Workday/other integration error parked in the same field. This is sound because the field is a shared visibility field; gating the clear on the assetize-owned prefix preserves other writers' messages. ✔
- **AC2 (normal order) / AC5 (recover 00095470):** unchanged `createOrUpdateAssetFromOrder` + de-duplication via **Quantity** (so the 4 SKUs no longer collide on one AccountId+Product2Id Asset) lets the action *"create an asset for each order item,"* including future-dated subscription lines, yielding the expected 32 Assets on recovery. The fix deliberately leaves the platform action untouched — correct, since the action was behaving per its documented contract; the defect was the swallow, not the action.

**Net validation.** The documentation confirms (1) the async path is a separate post-commit transaction with its own budget; (2) a graceful-end fault path provably suppresses the default error + email and persists the triggering change with **no** surfaced signal — the genuine defect; (3) the custom autolaunched flow is a sanctioned override of the managed O2A flow; and (4) surfacing the fault on the record (V14) is among Salesforce's recommended surfacing patterns and is the **only** in-context one available for a screenless async override, with the inherent caveat — also documented — that the async path cannot transactionally retry, which V14 correctly honors by never writing Status. **V14's surface-on-record approach is the platform-correct remediation; the silent swallow was the genuine defect.**

---

## Sources

**Async / Run Asynchronously path (separate post-commit transaction, own governor budget):**
- Salesforce Architects — Record-Triggered Automation Decision Guide (canonical; JS-rendered): https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered.html
- Salesforce Help — Scheduled Paths / async path concept: https://help.salesforce.com/s/articleView?id=platform.flow_concepts_trigger_scheduled_path.htm&type=5
- Salesforce Help — Run Part of a Record-Triggered Flow After the Original Transaction (release note): https://help.salesforce.com/s/articleView?id=release-notes.rn_automate_flow_builder_asynchronous_path.htm&release=234&type=5
- Salesforce Help — Per-Transaction Flow Limits: https://help.salesforce.com/s/articleView?id=platform.flow_considerations_limit_transaction.htm&type=5
- UnofficialSF (Salesforce-PM-maintained) — Triggering Flows (Order-of-Execution step 20, post-commit cohort, "no guarantee … may be delayed"): https://unofficialsf.com/pauple_helpie/triggering-flows/
- Salesforce Ben — Complete Guide to Salesforce Flow Limits (100 SOQL / 150 DML / 10,000ms CPU; new transaction after pause/async): https://www.salesforceben.com/complete-guide-to-salesforce-flow-limits-and-how-to-avoid-them/

**Fault connectors / swallow mechanism / surfacing best practices:**
- Salesforce Help — Customize What Happens When a Flow Fails: https://help.salesforce.com/s/articleView?id=platform.flow_build_logic_fault.htm&type=5
- Salesforce Help — Default Flow Error Handling (rollback + admin error email): https://help.salesforce.com/s/articleView?id=platform.flow_build_logic_fault_default.htm&type=5
- Salesforce Help — Other Examples of Error Handling in Flows (always email on fault, include resource values): https://help.salesforce.com/s/articleView?id=platform.flow_build_logic_fault_examples.htm&type=5
- Trailhead — Handle Flow Errors with Fault Paths: https://trailhead.salesforce.com/content/learn/modules/flow-implementation-2/handle-flow-errors-with-fault-paths
- Trailhead — Roll Back Changes After an Error ("fault path → transaction is not rolled back"; "Salesforce completes the change that triggered the flow, even though the flow failed"): https://trailhead.salesforce.com/content/learn/modules/flow-implementation-2/roll-back-changes-after-an-error
- Salesforce Developers — FlowExecutionErrorEvent (screen flows only, API 47.0+): https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_flowexecutionerrorevent.htm

**RLM O2A flow override + Create/Update Asset From Order action:**
- RLM Developer Guide — Asset Lifecycle Overview (standard flow on activation; clone/override; custom-flow Apex action): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/asset_lifecycle_overview.htm
- RLM Developer Guide — Create or Update Asset From Order action ("creates an asset for each order item"; CreateAssetOrderEvent error details): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order.htm
- RLM Developer Guide — Create or Update Asset From Order Item action: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order_item.htm
- Salesforce Developers — CreateAssetOrderEvent (platform event, success/error notification): https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_createassetorderevent.htm
- Salesforce Architects (Medium) — Automate Revenue Cloud Customer Asset Lifecycle Management: https://medium.com/salesforce-architects/automate-revenue-cloud-customer-asset-lifecycle-management-fa2c0ccee3b5
