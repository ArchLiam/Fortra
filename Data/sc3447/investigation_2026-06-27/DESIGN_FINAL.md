# SC-3447 — FINAL Fix Design (Quote→Order convert CPU blow-up on high-qty Power lines)

**Ticket:** SC-3447 (Blocker) · **Reporter:** Joe Romo · **Assignee:** Liam Jeong · Label CRM-Revenue-Cloud
**Date:** 2026-06-27 · **Author:** finalization lead (read-only; no mutations performed)
**Org:** FortraUAT (00DWC000006eUFF2A2)
**Status:** DESIGN ONLY. Nothing below is deployed. Every UAT deploy/DML needs a fresh explicit
authorization ([[feedback_uat_deploy_authorization]]); prod is separately gated.

**Supersedes:** `DESIGN.md` (wave-1). This document folds in (a) the adversarial feasibility review
`ADVERSARIAL_REVIEW_2026-06-27.md`, (b) the completeness critique `COMPLETENESS_CRITIQUE.md`, and
(c) the three wave-2 gap-closure files: `10_order_header_cascade.md`, `11_checklist_mapper_managedpkg.md`,
`12_workday_quantity_decision.md`. Where this doc and `DESIGN.md` disagree, this doc wins.

**THE HEADLINE CHANGE vs DESIGN.md:** Wave-2 verified (HIGH confidence, 3 independent legs) that the
**Workday contract integration takes ONE contract line with `quantity=N`, NOT one line per seat.** The
per-unit OrderItem explosion therefore has **no downstream consumer that requires it** — and worse, it
*causes* Workday failures (SC-3210/3368 subsplit conflation). **P3 ("don't explode seat/sentinel lines;
keep one qty-N OrderItem") is now the PRIMARY resolution.** The heavy P2 async-split build is **DEMOTED**
to a contingency that is only relevant if a genuine **per-machine** (hardware-driven) split case exists at
scale — and even then the 10k-DML-row ceiling forbids the sentinel population, so P2 is never the answer
for seat/sentinel quantities. P0/P1 remain valid as immediate safety + CPU-reduction layers.

---

## 0. The defect in one paragraph

Converting a quote with a high-quantity `Product2.Solution_Group__c='Power'` line throws
`System.LimitException: Apex CPU time limit exceeded` (surfaced as `FLOW_INTERVIEW_LIMIT_EXCEEDED`) and the
whole order rolls back. The convert screen flow `Fortra_Quote_to_Order_Conversion` (active **V27 /
301WC00000kSRnZYAW**) runs its entire Apex chain (`ChecklistValidationService → createOrderFromQuote →
QuoteToOrderFieldMapper → PowerOrderSplittingService → OrderRepriceInvocable(×2) → Activate`) **all
`flowTransactionModel=CurrentTransaction`** — one synchronous request, one 10,000 ms CPU budget, no async
boundary anywhere. `PowerOrderSplittingService` explodes a qty-N Power line into N qty-1 OrderItem clones in
a `for(i=1;i<qty;i++)` loop (L157); per clone, `createFullClone` calls `getDescribe()` 208× and two
record-triggered OrderItem flows fire (after-save `Set_Workday_Contract_Line_Type` V11 does a `recordUpdate`
on `$Record` that re-fires before-save `Set_Dates` V6). CPU scales 1:1 with quantity. **Power "quantity" is a
seat/user/license count or an "unlimited" sentinel (9,999 / 99,999 / 999,999), NOT a machine count** — and
Workday accepts that quantity verbatim on one line. So one-OrderItem-per-unit is the wrong model, not merely
slow: it is unnecessary AND it breaks the integration it was meant to serve.

---

## 1. What the critics changed (accepted corrections folded in)

| # | Correction (source) | Disposition in this doc |
|---|---|---|
| C1 | SC-3368 reverse-lookup risk is OVERSTATED — live V11 line-type flow uses `$Record.Product2.Is_Subsplit_Product__c` (a product boolean, cross-object on `$Record`, no SOQL); there is NO `Original_Order_Item__c` reverse-lookup in the live flow (adversarial Attack 2; wave-2 file 12 §"line-type flow") | **DOWN-RANKED** to "verify V11 still product-boolean at build (daily churn could reintroduce a reverse-lookup version)." Copy-parent-verbatim still correct and now *also* matches exactly what the flow would stamp (same Product2 → same boolean). |
| C2 | "copy vs derive" resolves to **copy = no-regression**. Freshly-converted FIXED AMOUNT originals are themselves `EndDate=null / PricingTermCount=0` at convert time; copying faithfully propagates that, it does not close it. Closing the 36% null EndDate/PTC gap is **pre-existing SC-3411/3420 scope** (adversarial Attack 4) | **ACCEPTED.** P1#2a is scoped as **copy = clones match what a non-split line would have**. Do **NOT** block SC-3447 on the 36% gap; explicitly defer it to SC-3411/3420. Re-derive is an *optional* enhancement, not required. |
| C3 | P0 cap-check placement is mis-stated: `Database.setSavepoint()` is taken at **L108**, BEFORE `queryOrderItemsToSplit` (L112) and the `isEmpty` check (L115). The cap check (proposed after L113) runs AFTER the savepoint (adversarial "Minor implementation error") | **ACCEPTED.** Cap check **moved ABOVE L108** (compute clone total from a lightweight count query before taking the savepoint), OR wording corrected to "returns before any DML; the no-op savepoint is harmless." This doc moves it above the savepoint (cleaner). |
| C4 | `MAX_SYNC_CLONES` should be a **Custom Metadata value** (kill-switch / admin-tunable), not `private static final 200` (completeness §D1, correction F2) | **ACCEPTED.** New CMDT `SC3447_Split_Config__mdt.Max_Sync_Clones__c` with an Apex default fallback. Enables tune/disable without redeploy. |
| C5 | Add a `faultConnector` to **ALL THREE** unguarded actions — `ChecklistValidationService` (`Validate_Checklist_Complete`) + Mapper + Split — not just two (completeness §F1; wave-2 file 11 §1) | **ACCEPTED.** P0 adds faults to all three. |
| C6 | P1 sizing must include the **reprice tail + Order-header cascade + per-original double-fire**, and must have a **build-time `Limits.getCpuTime()` measurement** before declaring P1 sufficient (completeness §B2/§B3/§F3; wave-2 file 11 §5) | **ACCEPTED.** P1 now explicitly states it does NOT touch the O(L) original floor; a sandbox CPU measurement on a ~50-distinct-line convert is a P1 exit gate. |
| C7 | Add **UAT validate-to-activation-with-Workday-suppressed** path + **manual recovery for stuck 'Pending Split' orders** to P4 (completeness §D3/§D4) | **ACCEPTED.** Added to P4. (Note: with P3 as primary, the 'Pending Split' async state largely disappears — see §3.) |

---

## 2. Root cause (confirmed) and the two hard ceilings

**Confirmed root cause:** one synchronous transaction does order-create + per-unit clone loop + reprice +
activate, with per-clone CPU amplified by (a) 208 un-hoisted `getDescribe()` per clone and (b) 2
record-triggered OrderItem flows per clone (the after-save one re-entrant). CPU (not SOQL/DML) is what throws:
dead-txn snapshot (point-in-time 2026-06-26, NOT re-measured this session) SOQL 19/100, DML 480/10,000,
CPU >10,000 — consistent with the rule that DB time for SOQL/DML is excluded from CPU but flow/workflow
app-server CPU is included.

**Two ceilings the fix MUST respect (cannot be engineered around):**

1. **10,000 DML rows per transaction — identical sync and async.** Async raises CPU 10s→60s and heap 6→12 MB
   but **NOT** the DML-row ceiling. On the OLO+partition path the class emits ~`3N` rows (insert clones +
   insert partitions + update clones) → fails on DML rows alone at **N≈3,333**; on the dominant no-partition
   real path (3,812/3,816 lines have null `Partition_Record__c`) only ~`N` rows → fails at **N≈10,000**. Real
   Power qty routinely sits at 999,999 — orders of magnitude beyond either sub-ceiling.
2. **The seat/sentinel reality:** 18,137 latent Power QLIs at qty>1; 1,573 over qty 100; **402 in the
   100k–1M range; max 999,999**. 134 live OrderItems at the 999,999 sentinel. Per-unit explosion of a seat
   count is semantically wrong: native RLM/RCA models qty as **one OrderItem Quantity=N + one Asset
   Quantity=N**; per-unit only exists at the **fulfillment** layer via DRO `DecompositionScope` +
   `FulfillmentQtyCalcMethod=AlwaysOne`, declaratively and async.

**Empirical proof the feature only ever worked tiny:** ~63–66 split clones exist org-wide; largest
SF-activated group = 9 (Workday then **Failed**); largest Workday-clean = 4. Requirement is up to 750,000 —
~5 orders of magnitude beyond anything that has ever succeeded. **Hardware/Partition cloning is vestigial:**
3,812 of 3,816 real qty>1 Power lines have `Partition_Record__c=null`; the 4 that don't are UAT tests; the
OLH branch's only ever order is a test fixture.

---

## 3. THE DECISIVE FINDING — Workday takes quantity=N (wave-2 file 12)

**Verdict (HIGH confidence): Workday's contract integration accepts ONE contract line with `quantity=N`.
Per-unit seat splitting is NOT required by Workday — and it actively breaks Workday.**

Three independent legs, all converging:
1. **API spec** (`Submit_Customer_Contract.md`, Workday Rev Mgmt v46.1): `Customer_Contract_Line_Data` carries
   `Quantity` decimal(22,2)[0..1], `Unit_Cost`, `Extended_Amount`; Workday's own model is
   `Extended = Unit_Price × Quantity` (explicit in the FV field description). **No per-unit / per-seat /
   serial-per-line constraint exists** anywhere in the 1,693-line spec. The only contract invariant is
   `currentContractAmount == SUM(line extendedAmount)` — satisfied identically by 1 line of N×unit or N lines
   of 1×unit. Splitting buys **nothing**.
2. **Captured payload** (Order 00095355, `Workday_Sync_Payload__c`): every `contractLineData` entry carries a
   real `"quantity"` field; verified **1 OrderItem → 1 contract line** (2 OrderItems → 2 lines). The
   write-back External ID (`Workday_Contract_Line_Reference_ID__c`) is on OrderItem, one per OrderItem —
   re-confirming the 1:1 design.
3. **Mule mapping** (inferred strongly from the SC-3347 extendedAmount fix spec + the qty=1 payloads):
   `line.quantity = OrderItem.Quantity`, `line.extendedAmount = OrderItem.NetTotalPrice (= NetUnitPrice ×
   Quantity)`. If quantity were hardcoded to 1, the extendedAmount reconciliation the integration team is
   debugging would be wrong for every qty>1 line.

**Corroboration that splitting HARMS Workday:** SC-3210/3368 — for a pure qty split (every clone same
Product2, `Original_Order_Item__c=parent.Id`), the older line-type flow mis-classified the parent as a
"subsplit parent" and stamped it `FIXED AMOUNT BILLING ONLY` (zero revenue) → `SUM(extendedAmount) ≠
currentContractAmount` → **Workday REJECTS** (live repro 00095351, $11,025 billed ≠ $7,350 recognized). Not
splitting sidesteps the entire subsplit-conflation defect class.

**Residual unknown (the #1 Joe/Workday question, below):** the Mule DataWeave is not in-repo; the
`line.quantity ← OrderItem.Quantity` mapping is inferred (very strongly) but should be confirmed by the
Mule/Workday owners against the actual DataWeave or an Anypoint log of a qty>1 resubmit. This is a
**confirmation**, not a re-open — Legs 1–3 converge.

**Impact:** with quantity=N the convert-time CPU blowup **disappears at the source** — O(line-count) instead
of O(qty). P2 collapses. The only scenario that would resurrect a per-row materialization is a genuine
**per-machine** (hardware-count-driven) requirement — for which the driver is real Hardware/Partition data,
NOT raw license quantity, and which the 10k-row ceiling still caps at low thousands.

---

## 4. Wave-2 supplementary findings (CPU floor, no hidden N-scaler)

### 4a. Order-header cascade — NO hidden synchronous N-scaler (file 10)
There is exactly **ONE Apex trigger on Order** — `OrderValidationTrigger` (Active, before-insert ONLY, api 65)
→ `OrderValidationTriggerHandler.handleBeforeInsert` loops over quoteIds (= one quote during convert),
calling `ChecklistValidationService.validateChecklistForQuote` **once**. O(1). **No OrderItem Apex trigger
exists.** Six active Order record-triggered flows fire synchronously in the convert txn — all **O(1)
header-scoped**, none loops over OrderItems. The two Order automations that DO per-OrderItem child creation —
`Fortra_Order_to_Billing_Schedule` (one `Billing_Schedule` per OrderItem via managed action
`createBillingSchedulesFromBillingTransaction`) and `Fortra_Assetize_Order` (one Asset per line) — are **BOTH
`AsyncAfterCommit` + `Status='Activated'`-gated** and run in **separate post-commit transactions**, so neither
touches the synchronous convert CPU budget.

**Verdict:** the suspected B1 N-scaler (per-OrderItem Billing Schedule in-line) is **NOT present**. The
Order-header cascade contributes only a **FIXED, qty-independent CPU floor** (~15–18 cheap O(1) flow
interviews + 1 before-insert trigger, paid ~5–6× across the chain's Order DMLs) — ~3 orders of magnitude
below the per-clone driver. P1's `Is_Split_Line__c=false` guard is on the right object (OrderItem); it needs
**no Order-header analogue** because the floor is fixed, not N-scaling. **Caveat for P2-if-ever:**
`Fortra_Order_to_Billing_Schedule` creates one Billing_Schedule per OrderItem in its **own** async txn, so at
extreme N it hits the same 10k-DML ceiling there — an async-tail scaling concern that reinforces "don't
materialize seat rows."

### 4b. Checklist / Mapper / managed-pkg + per-original DOUBLE-FIRE (file 11)
- **ChecklistValidationService** = O(1) per convert (1 SOQL, 0 DML, no per-line loop; api 65; NOT in repo).
  Negligible CPU. Its only SC-3447 defect is the **missing faultConnector** (→ P0).
- **QuoteToOrderFieldMapper** is bulkified (3 SOQL + ≤2 DML, no loop DML) — CONFIRMED. BUT its `update
  toUpdate` over all changed originals (L260, runs BEFORE the split) **re-fires both OI flows once per
  original** — a SECOND firing on top of createOrderFromQuote's insert firing = a **per-ORIGINAL DOUBLE-FIRE**
  scaling **O(2·L)** (L = distinct lines). **P1's `Is_Split_Line__c=false` guard does NOT suppress this** —
  originals are `false` by design, exactly the value the guard admits. The only mechanism that removes it is a
  **transient Custom-Permission OI-flow bypass** on the convert running user, with the split/mapper Apex
  stamping derived fields on originals.
- **Managed-package trigger surface = EMPTY** on the convert path: 0 managed-namespace Apex triggers on
  Order/OrderItem/Asset/Contract; all active Order/OrderItem record-triggered flows are NamespacePrefix=None
  (custom); the only managed Order flows (`revenue_o2aflows`, `revenue_o2bsflows`) are INACTIVE. RLM /
  `commerceorders` is **platform-native code** (its Force-reprice CPU accrues to the budget but registers no
  trigger). So no hidden packaged trigger surface; the managed CPU IS the native reprice/createOrderFromQuote
  execution itself, O(N).
- **Net non-clone CPU floor = O(line-count)**, dominated by the 2·L OI-flow double-fire on originals + the
  reprice tail re-firing those flows on originals + the native V16 reprice over all lines + the activate-time
  native `submitOrder` (O(line-count) managed work). **On a single-high-qty-line quote (L=1) this floor is
  trivial and P1 is decisive. On a multi-distinct-line quote (large L) P1 alone may NOT converge** — it needs
  the custom-permission OI-flow bypass and/or the async tail.

**How this interacts with the headline (P3):** P3 stops *splitting*, which removes the per-clone work
entirely. The O(2·L) per-original double-fire is **independent of splitting** — it is paid on every convert,
high-qty or not. So even under P3, a quote with very many distinct lines could still strain the budget; the
custom-permission OI-flow bypass remains the durable lever for that case. P3 fixes the qty-driven blowup; the
bypass fixes the line-count-driven floor. They are complementary.

---

## 5. FINAL plan P0 → P4

> Guard rails honored throughout: read-only-until-authorized; never exceed the 10k-DML-row ceiling; never
> touch Quote DML (RLM platform lock — [[project_rlm_quote_dml_lock]]); clones (where they still exist for
> genuine per-machine cases) INHERIT the parent line type verbatim, never re-derive. The live V11 line-type
> flow has **no reverse-lookup** (C1), so the SC-3210/3368 re-break risk is "verify-at-build," not active.

### Priority ordering (REVISED — P3 promoted)
1. **P0 now** — guardrail + fault-close + kill-switch CMDT. Stops the silent gack on the live backlog.
2. **P3 is the PRIMARY resolution** — don't explode seat/sentinel lines; keep one qty-N OrderItem (Workday
   takes quantity=N). Pending the single Joe/Workday confirmation (§3 residual unknown).
3. **P1 next / alongside** — CPU reduction that benefits *all* converts (multi-distinct-line quotes still
   blow up independent of P3); also lowers risk for any residual genuine per-machine split. Worth doing even
   under P3.
4. **P2 DEMOTED** — heavy async split is **only** relevant for genuine per-machine (hardware-driven) split at
   scale, if any such case exists. For seat/sentinel quantities the 10k-row ceiling forbids it regardless, so
   P2 is NOT the seat-line answer. Likely **dropped** once Joe confirms quantity=N suffices for Workday.
5. **P4 throughout** — tests/coverage (0% today) are a deploy blocker regardless.

---

### P0 — Guardrail: catchable hard cap + fault-close + kill-switch (biggest immediate safety win)
**Goal:** replace the silent governor gack + full rollback (live backlog ~80–170 non-terminal quotes, mostly
NULL-status renewals) with a fast, friendly failure.

**Apex — `PowerOrderSplittingService.cls`:**
- Introduce a **Custom Metadata** cap, NOT a hardcoded static (C4): new `SC3447_Split_Config__mdt` with field
  `Max_Sync_Clones__c` (Number). Read once via a cached helper
  `getMaxSyncClones()` that returns the CMDT value or an Apex default `200` if no record (so the org always
  has a safe floor). The CMDT row is the admin kill-switch (set to 0 to block all splits; set high to relax).
- **Cap check placement (C3): compute the clone total and bail BEFORE the savepoint at L108.** Add a
  lightweight aggregate/count of qualifying clones before `Database.setSavepoint()`. Concretely: run a
  count-oriented variant of `queryOrderItemsToSplit` (only `Id, OrderId, Quantity, Solution_Group` needed) to
  compute `Integer totalClones = Σ(qty−1)` per order; if `totalClones > getMaxSyncClones()`, set **every**
  result in `resultByOrderId` to `success=false` with a clear `errorMessage` (consistent with the null-orderId
  path at L37-41 and the catch block) and `return` **before** `Database.setSavepoint()`. (If you prefer to
  reuse the existing full query, the correct wording is "returns before any DML; the no-op savepoint at L108
  is harmless and needs no rollback" — but moving the check above L108 is cleaner and is the chosen approach.)
- Message example: "Power split would create N lines, exceeding the supported synchronous maximum of {cap}.
  This quantity represents seat/site licenses; it should not be split. Contact your administrator."

**Flow — `Fortra_Quote_to_Order_Conversion` (V28):**
- Wire `SplitPowerOrderLines.success` into a new decision; on `false` route to
  `Screen_Error_Order_Creation_Failed` showing `errorMessage`. (The invocable returns `SplitResult`; it does
  not throw — the flow must branch on it.)
- **Add a `faultConnector` to ALL THREE currently-unguarded actions (C5):** `Validate_Checklist_Complete`
  (ChecklistValidationService), `MapQuoteLineFieldsToOrderItems` (Mapper), and `SplitPowerOrderLines` (Split)
  — all currently have none — routing to the same error screen. Closes the "silent swallow" across the whole
  Apex chain, not just the split.

- **Coupling/rollback note (completeness §D2):** the Apex cap and the flow result-branch MUST deploy/roll back
  **together** (a cap that sets `success=false` with no flow branch to read it = silent swallow again). The
  flow rollback is version-based (deactivate V28, reactivate V27). The CMDT cap is independently tunable
  without redeploy.
- **Risk:** very low (pure guard; additive). **Effort:** ~0.5–1 day. **Sign-off:** standard UAT deploy auth;
  **set the cap WITH Joe** so it does not block legitimate small per-machine splits.

### P3 — PRIMARY RESOLUTION: don't explode seat/sentinel lines; keep one qty-N OrderItem
**Why this is now primary (§3):** Workday takes `quantity=N` on one line; per-unit splitting is unnecessary
*and* causes Workday subsplit-conflation failures. Native RLM models qty as one OrderItem Quantity=N + one
Asset Quantity=N. There is no business need to materialize 7,500 / 999,999 OrderItems.

**Design (pending the single Joe/Workday confirmation, §6 Q1):**
- **Default: do NOT split seat-count Power lines.** Keep `Quantity=N` on a single OrderItem. Represent
  sentinels (9,999 / 99,999 / 999,999) as "unlimited/site" on one line; never split.
- **Gate any remaining split on genuine per-MACHINE evidence — real Hardware/Partition data, NOT raw license
  quantity.** For OLO with `Partition_Record__c=null` (3,812/3,816 real lines) there is nothing to split.
  Implementation: change the split's qualifying predicate (`queryOrderItemsToSplit`) to require real hardware
  presence (e.g. `Partition_Record__c != null` and/or a machine-count field), so seat-count lines never
  enter the clone loop. This is largely **config/predicate** change inside the existing class plus the P0 cap.
- **Add a before-save / convert-time rule** blocking per-unit Power splits above the agreed cap / on sentinel
  quantities, with a clear message (belt-and-suspenders with P0).
- **If true per-unit fulfillment is ever required**, do it via native DRO decomposition at the **fulfillment**
  layer (`FulfillmentQtyCalcMethod=AlwaysOne`), declarative and async — NOT hand-rolled Apex on the sales
  OrderItem.

- **Risk:** medium (behavior change), but it is the only durable fix and it *removes* a Workday-failure class.
- **Effort:** config-only-to-small if "don't split seats + gate on hardware + sentinel rule"; larger only if
  DRO fulfillment decomposition is adopted.
- **Sign-off:** **business-gated — Joe Romo + design owners** + the single Workday confirmation (§6 Q1). Must
  precede any P2 commitment.

### P1 — Kill redundant per-clone CPU (safe; benefits ALL converts, not just split)
Largest safe CPU win short of redesign; worth doing even under P3 because the **per-original double-fire and
the reprice/Order-header floor are independent of splitting** and multi-distinct-line quotes blow up too.

**#1 — Hoist the describe work (`createFullClone`):** the field MAP is cached but `getDescribe()` runs per
field per clone = 208×N. Add a lazily-computed static `createableFieldNames` (iterate the map once, keep names
where `getDescribe().isCreateable()`), then rewrite the clone-copy loop to iterate that pre-filtered list
doing only `original.get()` / `clone.put()` — **zero describe in-loop**. Add a parallel static
`accessibleFieldNames` to remove the per-field `isAccessible()` at `queryOrderItemsToSplit`. Collapses 208×N
describes to 208 total.
- **Subtlety (adversarial coverage-gap 1):** the hoisted list must be **all createable field names** (not a
  hand-curated subset), so the clone field-set is byte-identical to the pre-hoist output; the code then
  overwrites `Is_Split_Line__c`/`Original_Order_Item__c` at L162-163 as today. Test A8 asserts byte-identical
  clone field-set.
- **Risk:** very low — identical output set, pure CPU optimization.

**#2 — Apex-stamp derived fields on clones + suppress per-clone flows (two coupled parts):**
- (a) In the clone-customization block (L159-167) explicitly copy from the freshly-queried original (qty-1
  clones are value-identical to the parent): `Workday_Contract_Line_Type__c`, `Billing_Schedule_From_Date__c`,
  `Billing_Schedule_To_Date__c`, `Start_Date_Calculated__c`, `End_Date_Calculated__c`, `EndDate`,
  `ServiceDate`, `PricingTermCount`. **Use the verified field names** (`Billing_Schedule_From/To_Date__c`, NOT
  `Billing_Start/End_Date__c`). All createable=true.
  - **Scope decision (C2): copy = no-regression.** Clones will carry exactly what a non-split line carries. The
    freshly-converted FIXED AMOUNT original is itself `EndDate=null / PricingTermCount=0` at convert time
    (live-verified), so copy propagates that pre-existing gap — it does **not** close it. **Do NOT block
    SC-3447 on the 36% null EndDate/PTC gap; that is SC-3411/3420 scope.** A re-derive path (mirror Set_Dates
    V6 logic + copy parent line type) is an OPTIONAL enhancement only if the team chooses to close the gap
    here; it is not required for SC-3447 and must not gate it.
- (b) Add a Start **entry condition** `Is_Split_Line__c = false` to **BOTH** `Fortra_OrderItem_Set_Dates` and
  `Fortra_OrderItem_Set_Workday_Contract_Line_Type`. Clones carry `Is_Split_Line__c=true` in memory before the
  insert → both flows skip them with zero CPU (evaluated before the interview is created). Originals (slot 0)
  and all non-split lines are `false` → still stamped normally. **Verified SAFE:** nothing downstream consumes
  the per-clone flow run; clones inherit identical stamped values by copy. Must be added to BOTH flows.
- **Line-type safety (C1):** because the clone has the SAME Product2 as its parent, the V11 flow result on a
  clone would be identical to the parent (`Is_Subsplit_Product__c` is the same boolean) → copy-parent-verbatim
  == what the flow would have stamped. There is **no reverse-lookup** in live V11 to re-break. Re-verify V11
  is still product-boolean at build (daily churn).
- **Risk:** low. Field names verified; the entry condition is the canonical guard.

**#3 — Per-original double-fire mitigation (NEW, from wave-2 file 11):** the `Is_Split_Line__c=false` guard
does NOT suppress the 2·L OI-flow firing on originals (createOrderFromQuote insert + mapper update). If the
multi-distinct-line backlog makes this floor material, add a **transient Custom-Permission OI-flow bypass**:
gate BOTH OI flows on `Is_Split_Line__c = false AND $Permission.Bypass_OI_Flow = false`, assign the custom
permission to the convert running/integration user, and have the split/mapper Apex explicitly stamp the
derived fields on originals too. This is the ONLY mechanism that removes the per-original double-fire.
**Trade-off (adversarial-style caution):** this widens the Apex stamp-on-clone copy to originals and must be
regression-tested for un-split single-line orders (test A15). Treat as conditional on the CPU measurement
below.

**P1 EXIT GATE (C6):** before declaring P1 sufficient, run a **build-time `Limits.getCpuTime()` measurement**
in a sandbox convert on (i) a single high-qty Power line and (ii) a ~50-distinct-line quote. State explicitly:
**P1 alone may NOT make a multi-distinct-line quote converge** because it does not touch the O(2·L)
per-original double-fire, the reprice O(N+L) tail, the activate-time `submitOrder` O(line-count), or the fixed
Order-header floor. If the measurement shows the floor binding, enable #3 (custom-permission bypass) and/or
move the tail async (P2 contingency).

- **Effort:** ~1.5–2.5 days (#1+#2); +~1 day if #3 is enabled. **Sign-off:** the two entry-condition flow
  versions touch the Workday line-type flow family (`Set_Workday_Contract_Line_Type` V11 → V12) — coordinate
  with line-type owners (Ben Kozlowski; SC-3210/3366/3368). Additive entry filter; preserves verbatim-parent
  invariant. Re-verify V6/V11 active + product-boolean at deploy.

### P2 — DEMOTED / CONTINGENT: heavy async split (only for genuine per-machine cases, if any)
**Status: NOT the resolution for seat/sentinel lines.** Since Workday takes quantity=N (§3), P2 is needed ONLY
IF a genuine **per-machine** (hardware-count-driven) materialization at scale is confirmed by Joe — and even
then the **10k-DML-row ceiling still forbids 750k / sentinel quantities** (≥100 chunks, ~1M rows), so per-unit
explosion is architecturally unviable for the sentinel population regardless of sync vs async. **Default
expectation: P2 is dropped.**

If a real modest per-machine case nonetheless requires materialized rows (dozens–low thousands), the
**whole tail must move async together** (the design's load-bearing dependency, endorsed by both critics):
- **Thin synchronous convert:** validate → createOrderFromQuote → field-map → stamp
  `Order.Split_Status__c='Pending Split'` (new field — confirmed absent today) and commit. Do NOT split/
  reprice/activate in-line.
- **Async pipeline = Batch Apex** (each `execute()` chunk = fresh 10k-row / 60s txn). Chunk well under 10k
  rows/chunk (~2,000–2,500 clones on the partition path). NOT a single Queueable. Suppress per-clone flows via
  the same `Is_Split_Line__c=false` guard; Apex-stamp clones.
- **Re-sequence reprice + activate AFTER all chunks** (batch `finish()`): reprice the now-N-line order
  (`PricingPreference=System` + `isHighVolumeLineItems`, not blanket Force), clear `Order.ValidationResult`,
  then Activate — only once every chunk priced cleanly. **Reprice itself is O(N)** (one PATCH per OrderItem,
  verified) and the activate-time native `submitOrder` is a second O(N) tail — both may themselves need
  chunking at extreme N. Async does NOT remove these walls; it only raises CPU 10s→60s.
- **Idempotency:** key off `Original_Order_Item__c` + `Split_Status__c`; flip per chunk; re-run never
  double-creates.
- **Partial-failure + recovery:** Transaction Finalizer / `finish()` + `Database.SaveResult` inspection
  records per-chunk success on the Order, re-enqueues or quarantines failed slices, surfaces errors (status
  field + platform event). Async chunk failure does NOT roll back the committed convert. **Add a manual admin
  recovery path for orders stuck in `Pending Split`** (C7 / completeness §D4) — e.g. an admin-runnable
  "resume split" action keyed on `Split_Status__c='Pending Split'`.
- **Assetization sequencing (SC-3419):** async OrderItem DML (split+reprice+clear+activate) must FINISH before
  `Fortra_Assetize_Order` / `AssetizationAsyncJob` and must not race it. Activation/assetize is the final,
  serialized step. Re-running `PartnerNetPricePosthook` at activation can leave assetize stuck at
  ContextPersistence — watch.
- **Context survival:** clones MUST keep the full-field copy or re-trigger the V16 "couldn't fetch
  SalesTransactionContextExt_v2" incident ([[project_v16_order_pricing_contextfetch_incident]]).

- **Risk:** HIGH. **Effort:** ~4–7 days + heavy E2E **if pursued.** **Sign-off:** business sign-off on async
  convert UX + Workday confirmation that per-machine lines are genuinely required. **CEILING NOTE:** even
  perfectly chunked, P2 cannot persist seat/sentinel quantities; those need P3.

### P4 — Tests, coverage, E2E, rollout
- **Re-establish coverage (0% today — deploy blocker; org 75% gate).** The Apex test class never tests high
  qty, never asserts derived-field stamping on clones.
- Full test matrix (§6).
- **UAT validate-to-activation with Workday SUPPRESSED (C7 / completeness §D3):** add an explicit path to
  validate split/reprice/activate in UAT WITHOUT firing the terminal Workday send
  (`Fortra_Screen_Send_Order_to_Workday` / `Order_Completed_WD__e`). The platform-event resubmit mechanism
  means an accidental publish sends real data — validate up to activation and stub/suppress the Workday step.
- **Manual recovery path for stuck 'Pending Split' orders (C7):** documented admin procedure (only relevant if
  P2 is ever built; under P3-primary, this state does not occur).
- Standard gated rollout UAT → validate → prod; coordinate Workday line-type owners; **re-verify at build
  (daily churn):** active proc version (V16 today; V17–V20 staged), live `OrderRepriceInvocable` body (moved
  06-24), V6/V11 flow versions + V11 product-boolean (C1), `QuoteToOrderFieldMapper` live==force-app, convert
  flow apiVersion (62 today — decide keep vs bump on new version).
- **Build a fresh repro quote** (the documented one 0Q0WC000003AuQb0AK is GONE): Abstract `01tWC00000DD11GYAT`
  + qty ≥ ~50 on a new quote. Durable 999,999 reference = quote `0Q0WC000002QEKV0A4` "DO NOT SEND … ELA
  Renewal" — **do NOT convert it** (flagged DO NOT SEND); evidence only.

---

## 6. Test matrix (updated — adds the critics' missing scenarios)

### Apex unit (extend `PowerOrderSplittingServiceTest`)
| # | Scenario | Asserts |
|---|---|---|
| A1 | OLO qty 4 (existing) | 3 clones, qty=1, shared HW, amounts divided — keep |
| A2 | OLH qty 3 (existing) | 2 clones, HW cloned — keep (OLH is dead in prod) |
| A3 | non-Power qty 5 | 0 clones (Solution_Group≠Power) — keep |
| A4 | qty 1 | 0 clones — keep |
| A5 | bulk multi-order | bulk-safe; SOQL/DML under limit — keep |
| A6 | clone stamping | clone carries Workday_Contract_Line_Type__c, Billing_Schedule_From/To_Date__c, EndDate, ServiceDate, PricingTermCount, Start/End_Date_Calculated__c **equal to parent** |
| A7 | stamping WITH flows suppressed | run with `Is_Split_Line__c=false` entry guard; clones still fully stamped (Apex copy works without flows) |
| A8 | describe-hoist regression | qty ~50; assert `Limits.getCpuTime()` headroom + clone field-set **byte-identical** to pre-hoist output |
| A9 | hard cap | qty > cap → success=false, clear errorMessage, **0 DML / no Savepoint reached** (returns before L108) |
| A10 | cap boundary | qty = cap → succeeds; qty = cap+1 → capped |
| A11 | line-type verbatim inherit | clone Workday_Contract_Line_Type__c == parent (NOT reverse-lookup) — SC-3368 guard |
| A12 | FK + split flag | clone Original_Order_Item__c==parent.Id, Is_Split_Line__c=true; original reset false / FK null |
| A13 | ValidationResult restore | restores Order.ValidationResult=null on split orders that were clean |
| A14 | CMDT cap override | `SC3447_Split_Config__mdt.Max_Sync_Clones__c` value is honored; absent → Apex default 200; 0 → blocks all |
| **A15 NEW** | **non-split stamping NOT regressed by entry condition** | a normal single-line order (Is_Split_Line__c=false) is still fully stamped by BOTH flows after the entry filter is added (guards the un-split path the clone tests don't) |
| **A16 NEW** | **P3 seat-line not split** | qty=999,999 sentinel / seat-count line with `Partition_Record__c=null` → **0 clones**, single qty-N OrderItem kept (P3 predicate) |
| **A17 NEW** | **P3 per-machine line still splits** | OLO line with real `Partition_Record__c` and small machine count → legitimate split works |
| **A18 NEW (P2-contingent)** | batch chunk idempotency | re-running batch on a partially-split order does not double-create (key on Original_Order_Item__c + Split_Status__c) |

### E2E convert (post-deploy, explicit auth; build fresh quotes)
| # | Scenario | Expected |
|---|---|---|
| E1 | small Power OLO (≤10) | under P3: does NOT split if seat-count; if per-machine, splits + clones stamped + converts + activates + Workday clean |
| E2 | medium Power (~100, under cap) | converts within limits |
| E3 | repro-class (Abstract ~456) | P0: capped with friendly message; P3: converts as one qty-N line |
| **E4 negative** | non-Power high-qty (Endpoint DLP @ 750k) | converts and does NOT split (Solution_Group≠Power) — must not regress |
| **E5 guardrail** | sentinel Power (999,999) | P3: one qty-N line, converts; or P0: blocked with clear message — NOT a governor fault / not 1M rows |
| E6 | per-machine OLO with real Partition_Record__c (small N) | legitimate split works; partitions cloned correctly |
| E7 | mixed quote (Power + non-Power + qty-1) | only qualifying per-machine Power lines split (P3 predicate) |
| **E8 NEW (CPU)** | **multi-distinct-line quote (~50 different lines)** | converts within CPU limits; if not, custom-permission OI-flow bypass (P1#3) is enabled — exercises the per-original double-fire path the single-big-line cases miss |
| **E9 NEW (CPU)** | **reprice-only CPU regression at N~50, clones suppressed** | assert reprice + activate headroom; proves the tail isn't the new bottleneck after P1 |
| **E10 NEW (Order-header)** | **Order-header automation is O(1)** | on a high-N convert, `Fortra_Order_to_Billing_Schedule` etc. produce O(1) synchronous records (per-OrderItem Billing Schedule runs only in the async post-commit txn, not in the convert) |
| **E11 NEW (Workday-suppressed)** | **validate-to-activation, Workday send stubbed/suppressed** | convert → split (if any) → reprice → activate succeeds and the terminal Workday send is NOT fired (no `Order_Completed_WD__e`) |
| E12 | shared-proc context survival | repriced lines do NOT trigger "couldn't fetch SalesTransactionContextExt_v2" |
| E13 | assetize sequencing (P2-contingent) | post-activate assetize does not race async split (SC-3419); Assets created once |

---

## 7. Business / integration questions for Joe Romo (led by the decisive Workday question)

1. **[DECISIVE — Workday quantity]** Does the Workday contract integration require **one contract line per
   seat**, or **one contract line with `quantity=N`**? Read-only evidence (API spec + captured payload + the
   SC-3347 extendedAmount mapping) converges on **quantity=N**; confirm against the actual `Submit_Customer_
   Contract` DataWeave (or an Anypoint log of a qty>1 resubmit) that `line.quantity ← OrderItem.Quantity`
   verbatim, and that Workday accepts a single line with a large quantity (e.g. 7,500) with `extendedAmount =
   unitCost × quantity`. **If yes → P3 is the resolution and the seat-line explosion is removed.** Are there
   ANY downstream Workday processes (billing schedule, MEA revenue allocation, fulfillment/provisioning,
   entitlement/asset-per-seat) that require one contract line per seat?
2. **What does Power `Quantity` represent** — physical machines/LPARs, or user/seat licenses? (Live data points
   overwhelmingly to seats/sentinels.)
3. **When, if ever, is per-MACHINE materialization actually required?** Should any split be gated on real
   **Hardware/Partition** presence rather than license quantity? Is it ever needed above a few dozen lines?
4. **Are 999,999 / 99,999 / 9,999 intended "unlimited / site-license" sentinels?** If so, splitting them is
   never valid and must be excluded by rule.
5. **What synchronous cap value** (`SC3447_Split_Config__mdt.Max_Sync_Clones__c`) is safe for genuine
   per-machine cases without blocking real business (start 200; largest legitimate live split ever seen is 9)?
6. **[Only if Q1 says per-seat lines ARE required]** Acceptable convert UX if splitting goes async (P2): the
   Order exists before lines finalize; activation + Workday wait for async completion (no SLA). Hybrid (sync
   under a small threshold, async above)? — **and note the 10k-row ceiling still forbids sentinel quantities
   regardless.**
7. **Backlog handling:** ~80–170 non-terminal (mostly NULL-status renewal) quotes are un-convertible today and
   growing. Remediate by re-scoping the offending lines to qty=N (per Q1–Q4) rather than forcing a split?

---

## 8. Verified vs assumed (honesty ledger)

**Verified live this session / wave-2 (HIGH confidence):**
- Workday takes quantity=N on one line (API spec + captured payload + mapping; file 12) — the decisive driver.
- NO hidden synchronous Order-header N-scaler; Billing_Schedule + Assetize are AsyncAfterCommit in separate
  txns (file 10).
- Per-original OI-flow DOUBLE-FIRE (createOrderFromQuote insert + mapper L260 update), O(2·L), NOT suppressed
  by `Is_Split_Line__c` (file 11).
- ChecklistValidationService O(1), no faultConnector; managed-package trigger surface EMPTY on convert path
  (file 11).
- Live V11 line-type flow uses `Product2.Is_Subsplit_Product__c` boolean — NO reverse-lookup (C1).
- Savepoint at L108 precedes the query at L112 (read PowerOrderSplittingService.cls this session) — C3.
- 0% coverage; class source == live; billing field names `Billing_Schedule_From/To_Date__c`.

**Assumed / point-in-time (re-verify at build):**
- The Mule `line.quantity ← OrderItem.Quantity` mapping is INFERRED (strongly); the DataWeave is not in-repo
  — Q1 confirms it (does not change the verdict given convergent evidence).
- The "dead-txn snapshot" CPU numbers (480 DML / CPU>10k) are a 2026-06-26 artifact, NOT re-measured (repro
  quote gone; read-only). Point-in-time.
- `MAX_SYNC_CLONES=200` is a conservative default, NOT a measurement; the true CPU cliff is unmeasured. Set
  with Joe; tune via CMDT after a fresh `Limits.getCpuTime()` measurement.
- Active proc V16, live OrderRepriceInvocable body, SalesTransactionContextExt_v2 — move daily; re-verify.
- `Order.Split_Status__c` does not exist (must be created — only if P2 is ever built).

**Constraints respected:** read-only honored (design doc, no deploy/DML/flow-run); 10k DML-row ceiling (P0/P1
cap below it, P3 stops exploding seat/sentinel lines — the only way to honor it at 750k); RLM Quote-DML lock
(no Quote DML); SC-3210/3368 line-type (clones inherit parent verbatim; live V11 has no reverse-lookup).
