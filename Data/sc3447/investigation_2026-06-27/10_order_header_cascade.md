# SC-3447 — Order-Header Automation Cascade Audit (wave-2, read-only, 2026-06-27)

**Closes:** Completeness-critique gap **B1** ("audited only OrderItem automation; never enumerated the Order-header cascade").
**Org:** FortraUAT (00DWC000006eUFF2A2). **Mode:** strictly read-only (Tooling queries + metadata retrieve only).
**Retrieves:** `Data/sc3447/investigation_2026-06-27/order_flows_retrieve/flows/*.flow-meta.xml` (20 Order/Asset/Contract flows),
`order_trigger_retrieve/{triggers,classes}` (OrderValidationTrigger + handler).

---

## 0. BOTTOM LINE (the verdict the critic asked for)

**There is NO hidden synchronous N-scaler in the Order-header cascade.** Every active Order-header automation
that fires inside the synchronous convert transaction is **O(1) per Order-header DML** — none loops over child
OrderItems or creates one child record per OrderItem in-line. The one automation that DOES do per-OrderItem child
creation — `Fortra_Order_to_Billing_Schedule` (one `Billing_Schedule` per OrderItem) — runs on an **AsyncAfterCommit
scheduled path in a SEPARATE transaction**, so it never touches the synchronous convert CPU budget at all. The
same is true of `Fortra_Assetize_Order` (the other async, post-activate N-worker).

**Net contribution to the SC-3447 synchronous CPU blow-up:** a **small FIXED Order-cascade floor** (a handful of
O(1) before/after-save flow interviews + one before-insert Apex trigger), paid **~5–6× per convert** (once per
Order-header DML in the chain) but **independent of Power line quantity N**. P1's `Is_Split_Line__c=false` OrderItem-
flow suppression does not touch this floor (different objects), but the floor is **not** what makes high-qty Power
converts fail — that remains the per-clone OrderItem describe×N + OI-flow re-entrancy×N established in wave-1.

**One real, separate finding (not N-scaling but real CPU the wave-1 model omitted):** `ChecklistValidationService`
runs at least **twice** per convert — once via the `OrderValidationTrigger` before-insert handler, and once as the
flow's first action `Validate_Checklist_Complete`. Cost is O(checklist-items), not O(N), but it is redundant and was
never opened (also a B2 gap). See §4.

---

## 1. Apex triggers on Order (B1 item 1)

Tooling: `SELECT Name,Status,ApiVersion,UsageBefore*/After* FROM ApexTrigger WHERE TableEnumOrId='Order'` →
**exactly ONE trigger**:

| Trigger | Status | API | Before/After | Events | O(?) |
|---|---|---|---|---|---|
| **OrderValidationTrigger** (01qWC000005ZrWQYA0) | Active | 65 | **before insert ONLY** (bI=true, all others false) | insert | **O(1) per convert** |

`OrderValidationTrigger.trigger` (3 lines) → `OrderValidationTriggerHandler.handleBeforeInsert(Trigger.new)`.

`OrderValidationTriggerHandler` (retrieved live, 42 lines): builds a `Set<Id> quoteIds` from `Trigger.new`, then
**`for (Id quoteId : quoteIds) ChecklistValidationService.validateChecklistForQuote(quoteId)`**. During convert
`Trigger.new` is **one Order** (one Quote) → the loop runs **once**. **No per-OrderItem work; not N-scaling.**
Fires **once**, at the `createOrderFromQuote` insert (before-insert only — does NOT re-fire on the mapper update,
reprice updates, or activate update).

Notable: handler exposes `public static Boolean bypassValidation = false` — a ready-made bypass hook (migration
scenarios) that P0/P2 could set on the convert running context to skip the redundant trigger-side checklist
validation (the flow already validates). **No OrderItem Apex trigger exists** (confirms wave-1 file `04`); the only
OrderItem-side automation is the two record-triggered OI flows.

---

## 2. ALL active record-triggered flows on Order (B1 item 2)

Method: `FlowDefinition` (249 defs) → filtered Order/billing/contract/workday/payment names → retrieved each
(`sf project retrieve` returns the **active** version's metadata) → parsed `<start>` (`object`, `triggerType`,
`recordTriggerType`, entry filters, `scheduledPaths`/`AsyncAfterCommit`) + body (`loops`, `recordCreates`,
`recordLookups` object/getFirstRecordOnly, `actionCalls`, `subflows`). Cross-checked against the full 142-row
active-AutoLaunchedFlow list (Tooling) — no Order-triggered active flow was missed.

### 2a. ACTIVE, fire SYNCHRONOUSLY inside the convert transaction

| # | Flow | TriggerType | RecordTriggerType | Entry condition | Per-OrderItem? | Cost | Fires at which convert DML |
|---|---|---|---|---|---|---|---|
| 1 | **Order_Before_Insert_Update_Sync_Status** | RecordBeforeSave | Create **and** Update | none (decision-only inside) | **No** | O(1) — pure `$Record.*_Sync_Status__c` field assignments, **0 SOQL / 0 DML** | **every** header DML (insert + mapper update + reprice updates + activate) — but trivial |
| 2 | **Fortra_Order_Sync_Address_From_Place** | RecordAfterSave | Update | `ISCHANGED(Bill_To_Place__c) OR ISCHANGED(Ship_To_Place__c)` | **No** | O(1) — up to 3 single-record `Places__c` lookups (getFirstRecordOnly=true) + `$Record` field copies | only the update(s) where a Place field changes (mapper update at most once) |
| 3 | **Fortra_Order_Set_Payment_Terms** | RecordAfterSave | **Create** | none | **No** | O(1) — 1 `PaymentTerm` lookup (getFirstRecordOnly) + 1 Order update | **once**, at the insert only |
| 4 | **Fortra_Order_Workday_Contract_ID** | RecordAfterSave | Create **and** Update | `Workday_Contract_ID__c = '' OR IsNull` | **No** | O(1) — 1 Order update (`Set_ID`) | header DMLs while Workday_Contract_ID__c is blank (insert + early updates) |
| 5 | **Order_Submission_to_Revenue_Orchestrator** | RecordAfterSave | Update | `Status = 'Activated'` **AND** requireRecordChanged=true | **No** (1 `AppUsageAssignment` lookup, header-scoped) | O(1) flow; calls native RLM **`submitOrder(orderId=$Record__Prior.Id)`** — single invocation | **once**, only on the activate transition (Status→Activated) |
| 6 | **Fortra_Order_After_Update_Platform_Event_Workday** | RecordAfterSave | Update | none on `<start>`; **gated by internal decisions** on `Status='Order Complete'` / PO_URL change | **No** | O(1) — evaluates 3 decisions; publishes PE only when `Status='Order Complete'` (NOT during convert, which sets 'Activated') → **no-op during convert** | every header update, but exits cheaply |

**Key:** items 1, 2, 3, 4 fire 1–N_DML times each but are all O(1) header work; items 5, 6 are gated to the
activation/completion transition (5 fires once at activate; 6 is a no-op during convert because Status is
'Activated', not 'Order Complete'). **None loops over OrderItems. None creates a child record per OrderItem.**

### 2b. ACTIVE, but run ASYNC (separate transaction — NOT in the convert CPU budget)

| # | Flow | Trigger | Entry | Async? | Per-OrderItem child work? | Where the N-work lives |
|---|---|---|---|---|---|---|
| 7 | **Fortra_Order_to_Billing_Schedule** | RecordAfterSave / Update | `Status='Activated'` + requireChanged | **YES — `<scheduledPaths><pathType>AsyncAfterCommit`** | **YES (delegated)** — calls managed action **`createBillingSchedulesFromBillingTransaction`** (`revenue_o2bsflows`) which creates one `Billing_Schedule` per OrderItem internally | **async, after commit, own 60s/10k-row txn** |
| 8 | **Fortra_Assetize_Order** | RecordAfterSave / Update | `Status='Activated'` + requireChanged | **YES — AsyncAfterCommit** | **YES (delegated, async)** — spawns `AssetizationAsyncJob` (one Asset per line); SC-3419 race lives here | **async** |

### 2c. NOT active / not Order-triggered (excluded — listed for completeness)

- `Fortra_Order_to_Contract_Field_Mapping` — **object = Contract** (RecordAfterSave/Create on Contract), NOT Order.
  Fires only if a Contract is created in the convert's contract branch; even then it is O(1) header mapping. Not an
  Order-header automation.
- `Fortra_Order_After_Save_Set_Workday_Contract_Line_Type` — **Obsolete** (the SC-3366 dup-subflow caller; confirms
  wave-1 — no live caller).
- `Fortra_Order_Integration_Check` — **Obsolete** (had a loop+OrderItem ref; dead).
- `Fortra_Order_Set_Workday_and_PO_Fields` — **Obsolete**.
- `Fortra_Order_Reprice` — **Obsolete** (object=None).
- Draft/InvalidDraft (not deployed-active): `Create_Asset_From_Order`, `Fortra_Order_Assetize_Order`,
  `Fortra_Order_Workday_Status`, `Fortra_Order_Places_Primary_Check`, `Order_After_Update_Platform_Events`,
  `Warn_Quote_Order_Currency_Mismatch`.
- `Order_Disallow_delete_for_Globalscape_Integration_User` — before-delete; irrelevant to convert.
- `Fortra_Order_Submission_Check` — a **screen** Flow (processType=Flow), not record-triggered; invoked from UI, not
  the convert header cascade.

---

## 3. Per-DML firing schedule (B1 item 3) — what fires at each of the ~6 Order-header DMLs

The convert chain's Order-header DMLs and the **synchronous** automations each triggers:

| Step | Order-header DML | Sync flows that fire (O(1) each) | Apex trigger |
|---|---|---|---|
| createOrderFromQuote (native RLM) | **INSERT** | #1 Sync_Status (before), #3 Set_Payment_Terms (after/Create), #4 Workday_Contract_ID (if blank), #6 PE_Workday (no-op) | **OrderValidationTrigger** (before insert) → ChecklistValidationService ×1 |
| QuoteToOrderFieldMapper | **UPDATE** (header, L188) | #1 Sync_Status, #2 Sync_Address_From_Place (if place changed), #4 Workday_Contract_ID (if still blank), #6 PE_Workday (no-op) | — |
| OrderRepriceInvocable ×2 | bulk Order/OrderItem **UPDATEs** + clearValidationResult | #1 Sync_Status, #6 PE_Workday (no-op); (#2/#4 only if their fields changed) | — |
| Activate_Order | **UPDATE** Status→'Activated' | #1 Sync_Status, #5 Revenue_Orchestrator `submitOrder` (×1), #6 PE_Workday (no-op). **Triggers the AsyncAfterCommit paths #7 Billing_Schedule + #8 Assetize — but those run AFTER commit in their own txns** | — |

**Quantification:** the cumulative synchronous Order-cascade cost = roughly `(#1 ×6) + (#3 ×1) + (#2 ×≤1) +
(#4 ×~2) + (#5 ×1) + (#6 ×6 no-op)` flow interviews + 1 before-insert trigger. That is a **constant ~15–18 cheap
O(1) flow interviews per convert, independent of N.** It is paid whether the quote has 1 line or a 999,999-qty
Power line. It is a **fixed floor**, not a multiplier.

**Contrast with the real driver (wave-1):** the per-CLONE OrderItem work = `(208 describe + 2 OI flows, one
re-entrant) × (N-1) clones`. At N=456 that is ~94,000 describe calls + ~910 OI-flow interviews — three orders of
magnitude above the ~15-interview Order-header floor. **The Order-header cascade is real but is NOT the cause and
NOT N-scaling.**

---

## 4. The genuinely-new CPU finding the wave-1 model omitted

Not an Order-header N-scaler, but real redundant CPU in the convert transaction:

1. **`ChecklistValidationService` runs TWICE per convert** — once in `OrderValidationTrigger.handleBeforeInsert`
   (per quote, once), and once as the flow's first action `Validate_Checklist_Complete` (file `01`). Both are
   `CurrentTransaction`. Cost is O(number of Operations-Checklist items on the quote), **not** O(OrderItem) — so it
   does not scale with Power qty — but it is **redundant work** never opened by wave-1 (also B2). The handler's
   `bypassValidation` static is the clean lever to suppress the trigger-side copy if the flow already validates.
   The class itself is **not in `force-app`** (B2 confirmed) and its body was not retrieved this wave — flagged for
   the B2 follow-up, but bounded as non-N-scaling here.

2. **`submitOrder` (native RLM, item #5) and `createBillingSchedulesFromBillingTransaction` (item #7) are
   managed-package actions whose INTERNAL cost is O(line-count).** `submitOrder` runs synchronously at activate
   (one invocation, but it kicks the Revenue Orchestrator over all order lines — managed CPU on the same budget per
   cheatsheet footnote-5). `createBillingSchedules` is async. Neither is hand-rolled and neither is per-CLONE, but
   `submitOrder`'s O(line-count) managed work at activate is a **second O(N) tail alongside reprice** (the B3
   reprice-tail concern) — both run over the *final* N-line order. This reinforces the wave-1/critique conclusion
   that the whole tail (reprice + activate/submit) must move async together (P2), and that even with the split made
   cheap, the activate-time `submitOrder` + reprice over N lines is its own O(N) ceiling.

---

## 5. Suppression / mitigation guidance (B1 item 4)

**No new suppression is required for a hidden synchronous N-scaler — there isn't one.** Specifically:

- **`Fortra_Order_to_Billing_Schedule` is already correctly async** (AsyncAfterCommit) and already entry-gated to
  the single `Status='Activated'` transition with `requireRecordChanged=true`. It does NOT survive into the
  synchronous budget and does NOT need a P1-style `Is_Split_Line__c` guard. (It WILL create one Billing_Schedule per
  OrderItem in its own async txn — so at extreme N it has the **same 10k-DML-row ceiling** as everything else, in
  its own transaction. This is a P2/P3 scaling concern for the async tail, not a synchronous convert blocker.)
- **`Fortra_Assetize_Order`** is likewise async + Status-gated; the SC-3419 race (0 Assets) is the known issue there,
  already tracked; sequencing is a P2 concern (assetize must be the final serialized step), not a CPU contributor to
  the synchronous convert.
- **Fixed-floor reduction (optional, low-value):** if a future fresh CPU measurement shows the ~15-interview
  Order-cascade floor matters at the margin, the cheapest reductions are:
  (a) set `OrderValidationTriggerHandler.bypassValidation=true` for the convert running context (the flow already
  validates the checklist — removes the duplicate `ChecklistValidationService` run + the before-insert trigger);
  (b) the chain does the mapper UPDATE then reprice UPDATEs then activate UPDATE — collapsing redundant Order-header
  updates (e.g. folding QuoteToOrderFieldMapper's header field-set into fewer DMLs) would proportionally cut the
  ×N_DML firing of items #1/#4. **Both are marginal** vs the per-clone work and should only be pursued if a sandbox
  `Limits.getCpuTime()` measurement proves the floor is binding after P1.

**Verdict restated:** there is a **fixed Order-cascade CPU floor (qty-independent, ~15–18 O(1) flow interviews +
1 trigger), and NO hidden Order-header N-scaler in the synchronous path.** The only per-OrderItem Order-header
automations (`Fortra_Order_to_Billing_Schedule`, `Fortra_Assetize_Order`) are async-after-commit and out of the
convert CPU budget. The P1 `Is_Split_Line__c=false` suppression is on the right object (OrderItem); it does not need
an Order-header analogue. The Order-header cascade therefore **does not change P1's sizing materially** — but the
**activate-time `submitOrder` O(line-count) managed work** is a real second O(N) tail (with reprice) that confirms
the tail must move async (P2).

---

## 6. Evidence index
- Order trigger metadata: Tooling `ApexTrigger WHERE TableEnumOrId='Order'` → 1 row (OrderValidationTrigger, before
  insert only).
- Trigger + handler source: `order_trigger_retrieve/triggers/OrderValidationTrigger.trigger`,
  `order_trigger_retrieve/classes/OrderValidationTriggerHandler.cls`.
- 20 Order/Asset/Contract flow metadata: `order_flows_retrieve/flows/*.flow-meta.xml` (active version each).
- Full active-AutoLaunchedFlow list (142 rows) cross-check: Tooling `Flow WHERE Status='Active' AND
  ProcessType='AutoLaunchedFlow'`.
- Billing-Schedule async + per-OrderItem delegation: `Fortra_Order_to_Billing_Schedule.flow-meta.xml` L194-215
  (`<scheduledPaths><pathType>AsyncAfterCommit`), L3-35 (`createBillingSchedulesFromBillingTransaction`).
