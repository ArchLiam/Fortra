# SC-3447 — Consolidated Fix Design (Quote→Order convert CPU blow-up on high-qty Power lines)

**Ticket:** SC-3447 (Blocker) · **Reporter:** Joe Romo · **Assignee:** Liam Jeong · Label CRM-Revenue-Cloud
**Date:** 2026-06-27 · **Author:** synthesis lead (read-only; no mutations performed)
**Org:** FortraUAT (00DWC000006eUFF2A2)
**Status of this doc:** design only. NOTHING below is deployed. Every UAT deploy/DML needs a fresh explicit
authorization ([[feedback_uat_deploy_authorization]]); prod is separately gated.

**Inputs:** 9 read-only investigation agents (files `01`–`09` in this folder) + prior reports
`00_DEEP_RESEARCH_REPORT.md` (2026-06-26) and `01_LIVE_EVIDENCE_DATA.md` + live class
`force-app/main/default/classes/PowerOrderSplittingService.cls`.

---

## 0. The defect in one paragraph

Converting a quote with a high-quantity `Product2.Solution_Group__c='Power'` line throws
`System.LimitException: Apex CPU time limit exceeded` (surfaced as `FLOW_INTERVIEW_LIMIT_EXCEEDED`) and the
whole order rolls back. The convert screen flow `Fortra_Quote_to_Order_Conversion` (active **V27 /
301WC00000kSRnZYAW**) runs its entire Apex chain (`ChecklistValidationService → createOrderFromQuote →
QuoteToOrderFieldMapper → PowerOrderSplittingService → OrderRepriceInvocable → Activate`) **all
`flowTransactionModel=CurrentTransaction`** — one synchronous request, one 10,000 ms CPU budget, no async
boundary anywhere (file `01`). `PowerOrderSplittingService` explodes a qty-N Power line into N qty-1 OrderItem
clones in a `for(i=1;i<qty;i++)` loop; per clone, `createFullClone` calls `getDescribe()` 208× (file `04`) and
two record-triggered OrderItem flows fire — the after-save `Set_Workday_Contract_Line_Type` does a
`recordUpdate` on `$Record` that re-fires the before-save `Set_Dates` (re-entrancy; files `02`,`08`). CPU scales
1:1 with quantity. Power "quantity" is a **seat/user/license count or an "unlimited" sentinel** (9,999 / 99,999
/ 999,999), **not a machine count** (files `05`,`06`,`07`,`09`) — so one-OrderItem-per-unit is the wrong model,
not merely slow.

---

## 1. Drift reconciliation vs the 2026-06-26 report — CONFIRMED vs UNCERTAIN today

| Item | 2026-06-26 | 2026-06-27 live | Verdict |
|---|---|---|---|
| Convert flow active version | V27 / 301WC00000kSRnZYAW | V27 / 301WC00000kSRnZYAW, LastMod 2026-06-09 Nir | **CONFIRMED, no drift** |
| Whole chain `CurrentTransaction`, no async | yes | exactly 6 `<flowTransactionModel>` = CurrentTransaction; 0 async/scheduled/PE | **CONFIRMED** |
| Split result read / faultConnector | not flagged | `SplitResult` stored but NEVER read; **no faultConnector** on Split or on QuoteToOrderFieldMapper | **CONFIRMED (new detail)** — silent swallow |
| PowerOrderSplittingService body | local==live | live == force-app except trailing newline; LastMod 2026-06-09 | **CONFIRMED, no drift; source trustworthy** |
| Set_Dates | V6 RecordBeforeSave | V6 (301WC00000knsJNYAY), 0 SOQL/0 DML, no entry filter | **CONFIRMED** |
| Set_Workday_Contract_Line_Type | V11 RecordAfterSave | V11 (301WC00000kUYVFYA4), Get_Product SOQL + `$Record` recordUpdate, no entry filter | **CONFIRMED** |
| Autolaunched line-type subflow | inactive (SC-3366) | Draft/V7, only caller (Order-object flow) Obsolete → no live caller | **CONFIRMED inactive** |
| OrderRepriceInvocable | (repo) | **LIVE NEWER than repo** — adds `OrderCommercialNetService.patchOrderItemCommercialUnitPrices` + `PartnerNetPricePosthook.applyNetPricesToOrder` + setScale helper; LastMod **2026-06-24** | **DRIFT — repo stale** |
| Active Order pricing proc | not pinned | `Rev_Mgmt_Default_Pricing_Procedure` **V16** (9QMWC00000024PJ4AY); V17–V20 inactive | **NEW FACT (moves daily — re-verify at build)** |
| Context definition | SalesTransactionContextExt_v2 | confirmed, LastMod 2026-06-25 | **CONFIRMED** |
| Repro quote 0Q0WC000003AuQb0AK / Q-00781200 | exists, qty 456 | **GONE — 0 rows by Id and name** (daily churn) | **DRIFT — repro record deleted** |
| Repro product Abstract 01tWC00000DD11GYAT | Power/OLO/Active | confirmed Power/OLO/Active/Family=Subscription/Is_Subsplit=true | **CONFIRMED** |
| Power catalog | 3,406 / 2,782 active / 3,405 OLO / 1 OLH | identical; the 1 OLH = **UAT test fixture** `01tWC00000FiKdVYAV` | **CONFIRMED; OLH path is dead** |
| Code coverage of the class | not flagged | **0%** (ApexCodeCoverageAggregate 0/231; 0 per-test rows) — tests never run since 2026-06-09 deploy | **NEW — deploy blocker** |
| Billing field names | (fix sketch said Billing_Start/End_Date__c) | those **do not exist**; real fields `Billing_Schedule_From_Date__c` / `Billing_Schedule_To_Date__c` | **CORRECTION** |
| Class API version | — | v62 (org deploy memory uses 67) | **NEW — decide at deploy** |

**Net drift since 2026-06-26:** the flow chain, the split class, and the per-clone flows are byte-stable; the
repro quote vanished; the reprice tail (OrderRepriceInvocable + active proc V16 + SalesTransactionContextExt_v2)
moved 06-24/06-25 and the repo copy is stale; and we now know coverage is 0% and the billing field names were
wrong in the old sketch.

**UNCERTAIN today (must re-verify at build/deploy time):**
- The **current empirical CPU threshold**. With the deprecated subflow off since SC-3366, the 456 repro may now
  be borderline. No fresh measurement exists (read-only; the repro quote is gone). Do NOT quote a fixed clone
  ceiling as current.
- Whether the **original OrderItem is fully stamped (line-type/dates/PTC) at split time** during convert. Live
  split-line data shows ~36% of clones have null billing/term/EndDate **even with the flows running** (file
  `06`) — so "copy from original" is necessary but may be **insufficient if the original is itself unstamped**.
  This single question decides P1 "copy vs derive" (see §3.P1 and Joe questions).
- Active proc version (V16 today; V17–V20 staged) and the live OrderRepriceInvocable body — both move daily.

---

## 2. Root cause (confirmed) and the two hard ceilings

**Confirmed root cause:** a single synchronous transaction does order-create + per-unit clone loop + reprice +
activate, with per-clone CPU amplified by (a) 208 un-hoisted `getDescribe()` per clone and (b) 2 record-triggered
flows per clone (the after-save one re-entrant). CPU (not SOQL/DML) is what throws: dead-txn snapshot SOQL 19/100,
DML 480/10,000, CPU >10,000 — consistent with the cheatsheet footnote-5 rule that DB time for SOQL/DML is excluded
from CPU but flow/workflow app-server CPU is included (file `08`).

**Two ceilings the fix must respect (cannot be engineered around):**
1. **10,000 DML rows per transaction — identical sync and async** (file `08`). Async raises CPU 10s→60s and heap
   6→12 MB but **NOT** the DML-row ceiling. On the common OLO+partition path the class emits ~`3N+2` rows
   (insert clones + insert partitions + update clone partitions), so it fails on DML rows alone at **N≈3,333
   (qty≈3,334)** even with infinite CPU (file `04`). Real Power qty routinely sits at 999,999.
2. **The seat/sentinel reality:** 18,136 latent OLO Power QLIs at qty>1; 1,573 over qty 100; **402 in the
   100k–1M range; max 999,999** (files `05`,`06`). 134 live OrderItems at the 999,999 sentinel. Per-unit
   explosion of a seat count is semantically wrong: native RLM/RCA models qty as **one OrderItem Quantity=N +
   one Asset Quantity=N**; per-unit only exists at the **fulfillment** layer via DRO `DecompositionScope` +
   `FulfillmentQtyCalcMethod=AlwaysOne`, declaratively and async (file `09`).

**Empirical proof the feature only ever worked tiny:** just 63–66 split clones exist org-wide; largest SF-
activated group = 9 (Workday then Failed); largest Workday-clean = 4 (file `06`). Requirement is up to 750,000 —
~5 orders of magnitude beyond anything that has ever succeeded.

**Hardware/Partition cloning is vestigial:** 3,812 of 3,816 real qty>1 Power lines have `Partition_Record__c=null`;
the 4 that don't are UAT tests; the OLH branch's only ever order is the test fixture (file `07`). So the dominant
real path clones nothing but OrderItems, and the per-unit explosion carries zero business payload for real data.

---

## 3. Layered plan P0 → P4

> Guard rails honored throughout: read-only-until-authorized; never exceed the 10k-DML-row ceiling; never touch
> Quote DML (RLM platform lock — [[project_rlm_quote_dml_lock]]); never re-break Workday line-type via the
> `Original_Order_Item__c` reverse-lookup (SC-3210/3368) — clones must INHERIT the parent line type verbatim,
> never re-derive (files `06`,`02`).

### P0 — Guardrail: catchable hard cap (no design change, biggest safety win)
**Goal:** stop the silent governor gack + full rollback on the live backlog (~80–170 non-terminal quotes, mostly
NULL-status renewals — files `05`,`06`) by failing fast with a friendly message instead of CPU-exceeding.

**Apex change — `PowerOrderSplittingService.cls`:**
- Add a named constant `private static final Integer MAX_SYNC_CLONES = 200;` (conservative; below both the
  empirical CPU cliff "well below 100–456" and far below the 3,333 DML-row floor — start at 200, tune after a
  fresh measurement in P4).
- In `processOrders`, immediately **after** `queryOrderItemsToSplit` loads `itemsToSplit` (after L113, before the
  `if (itemsToSplit.isEmpty())` at L115): compute `Integer totalClones = 0; for (OrderItem oi : itemsToSplit)
  totalClones += (Integer.valueOf(oi.Quantity) - 1);`. If `totalClones > MAX_SYNC_CLONES`, set every result's
  `success=false` + a clear `errorMessage` (e.g. "Power split would create N lines, exceeding the supported
  synchronous maximum of 200. Contact your administrator.") and `return` **before any DML / Savepoint**. Because
  the invocable returns `SplitResult` (it does not throw), the screen flow can branch on it (see flow change).

**Flow change — `Fortra_Quote_to_Order_Conversion` (V28):** wire `SplitPowerOrderLines.success` into a new
decision; on `false` route to `Screen_Error_Order_Creation_Failed` showing `errorMessage`. **Also add a
`faultConnector` to `SplitPowerOrderLines` and `MapQuoteLineFieldsToOrderItems`** (both currently have none —
file `01`) routing to the same error screen. This closes the "silent swallow" gap.

- **Risk:** very low (pure guard; no behavior change under the cap; result-inspection is additive).
- **Effort:** ~0.5–1 day (Apex + 1 flow version + re-run tests).
- **Sign-off / coordination:** none beyond standard UAT deploy auth. P0 does NOT touch the Workday line-type
  family. **Set the cap WITH Joe** so it does not block legitimate small per-machine splits.

### P1 — Kill redundant per-clone CPU (safe, no functional change) — pairs #1+#2+#3
This is the largest safe CPU win short of redesign and lifts the sync ceiling several-fold. **#1 and #2 are
inseparable** (suppressing flows without Apex-stamping ships unstamped clones).

**#1 — Hoist the describe work (`createFullClone`, L363-380):** the field MAP is cached (`getOrderItemFieldMap`
L382-387) but `getDescribe()` (L367) runs per field per clone = 208×N. Add a lazily-computed static
`List<String> createableFieldNames` (iterate the map once, keep names where `getDescribe().isCreateable()`),
then rewrite the L366-377 loop to iterate that pre-filtered list doing only `original.get()` / `clone.put()` —
**zero describe in-loop**. Add a parallel static `accessibleFieldNames` to remove the per-field `isAccessible()`
at `queryOrderItemsToSplit` L337-342 (smaller win, runs once not per clone). Collapses 208×N describes to 208
total.
- **Risk:** very low — identical output set, pure CPU optimization.

**#2 — Apex-stamp derived fields on clones + suppress per-clone flows.** Two coupled parts:
- (a) In the clone-customization block **L159-167** (which already sets Quantity / Manual_Discount__c /
  Displaced_ARR__c / Is_Split_Line__c / Original_Order_Item__c), explicitly copy from the freshly-queried
  original (qty-1 clones are value-identical to the parent for these): `Workday_Contract_Line_Type__c`,
  `Billing_Schedule_From_Date__c`, `Billing_Schedule_To_Date__c`, `Start_Date_Calculated__c`,
  `End_Date_Calculated__c`, `EndDate`, `ServiceDate`, `PricingTermCount`. **Use the verified field names**
  (`Billing_Schedule_From/To_Date__c`, NOT `Billing_Start/End_Date__c` — file `04`). All are createable=true
  (file `07`). (`createFullClone` already copies all createable non-null fields, so this is belt-and-suspenders
  + makes the stamping explicit/testable.)
  - **CRITICAL CAVEAT:** this is correct ONLY if the original is itself stamped at split time. Live data shows
    ~36% of existing clones have null dates/term EVEN with flows running (file `06`), implying the original may
    be unstamped during convert. If a fresh-converted original is unstamped, the Apex must **RE-DERIVE** these
    values (mirror `Set_Dates` V6 logic: non-perpetual From=ServiceDate else Order.EffectiveDate, To=EndDate
    else From+12mo-1; perpetual Rev_Category__c=RC_41000 → all four = Order.EffectiveDate; TermDefined backstop
    EndDate + PricingTermCount=1) and the line type by **copying the parent** (never reverse-lookup — SC-3368).
    **This is a build-time verification, not assumable now.** P1 stamping is an OPPORTUNITY to also close the
    existing 36% gap.
- (b) Add a Start **entry condition** `Is_Split_Line__c = false` (Boolean, evaluated as `{!$Record.Is_Split_Line__c}
  Equals False`) to **BOTH** `Fortra_OrderItem_Set_Dates` and `Fortra_OrderItem_Set_Workday_Contract_Line_Type`.
  Clones carry `Is_Split_Line__c=true` in memory before the Phase-4 insert (L162) → both flows skip them with
  zero CPU (evaluated before the interview is created — file `08`). The original (slot 0) and all non-split
  lines are `Is_Split_Line__c=false` → still stamped normally. **Verified SAFE** (file `02`): nothing downstream
  depends on the per-clone flow run; clones inherit identical stamped values by copy; the Phase-5 update of the
  original keeps `Is_Split_Line__c=false` so it re-stamps harmlessly. **Must be added to BOTH** flows; adding it
  only to the after-save flow stops the after-save DML on clones (which transitively stops the Set_Dates re-fire)
  but leaves the clone's initial Set_Dates insert firing.
- **Risk:** low-medium. The "copy vs derive" question (caveat above) gates this; field names verified; the entry
  condition is the canonical, documented guard (file `08`). The line-type entry-condition + Apex parent-copy
  also **eliminates** the SC-3368 reverse-lookup mis-stamp risk on qty-split clones (files `02`,`06`).

**#3 — (covered by P0)** the hard cap; in P1 keep it as the synchronous-path floor.

- **Effort:** ~1.5–2.5 days (Apex stamping + hoist + 2 flow versions + test class extension).
- **Sign-off / coordination:** the two entry-condition flow versions touch the **Workday line-type flow family**
  (`Set_Workday_Contract_Line_Type` V11 → V12) — coordinate with the line-type owners (Ben Kozlowski; SC-3210/
  3366/3368 context). The change is additive (an entry filter), does NOT alter the line-type derivation for
  non-split lines, and the Apex copy preserves the verbatim-parent invariant. Re-verify V6/V11 are still active
  at deploy (heavy daily churn).

### P2 — Make the tail scale: move the WHOLE Split→Reprice→Activate async + chunk
**Why split-only-async is wrong (file `03`):** reprice (`OrderRepriceInvocable`) builds a Force-reprice graph
with **one PATCH per OrderItem** (`for oi : work.allOrderItems`) and Activate is gated on `Order.ValidationResult`.
If only the split moves async, reprice prices the un-split qty-N line, Activate activates a 1-line order, and the
clones land unpriced on an already-active order (re-creating the SC-3441 null-NetUnitPrice / TotalPrice=0 defect)
and re-dirty ValidationResult with no clearing pass. **The entire tail must move together.**

**Design:**
- **Thin synchronous convert (V28+):** validate → createOrderFromQuote → field-map → **stamp
  `Order.Split_Status__c='Pending Split'`** (new field) and commit. **Do NOT split, reprice, or activate
  in-line.** This is O(line-count), well under 10,000 ms. User gets an immediate response: "Order created; line
  splitting in progress."
- **Async pipeline = Batch Apex** (the documented tool for thousands/millions of records; each `execute()` chunk
  is a fresh 10,000-row / 60,000 ms transaction — file `08`). NOT a single Queueable (one job's DML is still one
  10k-row transaction). Chained Queueable is acceptable only for small cascades (≤ a few k clones) given the
  "1 enqueue per async context" rule.
  - **Chunk size:** keep each chunk's clone inserts + partition inserts well under 10,000 rows. With ~3 rows/clone
    on the OLO+partition path, a scope of **~2,000–2,500 clones/chunk** (`Database.executeBatch(b, 2000)`) leaves
    headroom; for the no-partition path (the real-data norm, file `07`) ~9,000 is safe but keep one conservative
    size.
  - **Suppress per-clone flows** in batch via the same `Is_Split_Line__c=false` entry guard (P1#2b) — already in
    place. Apex-stamp clones (P1#2a) so suppressed clones are correct.
- **Re-sequence reprice + activate AFTER all chunks:** in batch `finish()` (or the final Queueable link), run
  reprice on the now-N-line order, clear `Order.ValidationResult`, then Activate — only once every chunk priced
  cleanly. Use `PricingPreference=System` (delta pricing) + `isHighVolumeLineItems` (API 63.0+) instead of
  blanket `Force` over N lines (file `09`), to keep reprice itself from re-hitting the wall (file `03` warns the
  reprice tail is O(N) too). **Reprice may itself need chunking** at extreme N — flag as a sub-task.
- **Idempotency:** key off `Original_Order_Item__c` (the existing qty-split FK) + `Split_Status__c`. Process only
  rows still Pending; flip per chunk (`Pending Split → Split In Progress → Split Complete`). A re-run/retry never
  double-creates.
- **Partial-failure:** Transaction Finalizer (Queueable) or batch `finish()` + `Database.SaveResult` inspection
  records per-chunk success/failure on the Order, re-enqueues or quarantines failed slices, and surfaces errors
  on the Order (status field + platform event). Async chunk failure does NOT roll back the user's committed
  convert (step 1).
- **Assetization sequencing (load-bearing — SC-3419):** `Fortra_Assetize_Order` V17 (active) runs post-activate
  and spawns `AssetizationAsyncJob`. Async OrderItem DML must FINISH (split+reprice+clear+activate) before
  assetization, and must not race it (optimistic-lock swallow → 0 Assets). `OrderCommercialNetService` header
  also warns re-running `PartnerNetPricePosthook` at activation can leave assetize stuck at ContextPersistence
  (file `03`). Activation/assetize must be the final, serialized step.

- **Risk:** HIGH (largest change; touches reprice/activate ordering, ValidationResult gate, assetize race, and
  the V16 shared-proc context-fetch — clones MUST keep the full-field copy or re-trigger the V16 "couldn't fetch
  SalesTransactionContextExt_v2" incident — files `03`,[[project_v16_order_pricing_contextfetch_incident]]).
- **Effort:** ~4–7 days + heavy E2E.
- **Sign-off / coordination:** **business sign-off required** on async convert UX (order exists before lines
  finalize; activation/Workday wait for completion) — Joe Q4. Prod-promotion coordination with reprice/pricing
  owners (active proc V16) and Workday line-type owners.
- **CEILING NOTE:** even perfectly chunked, P2 cannot persist 999,999 OrderItems for one line (10k-row ceiling →
  ~100+ chunks → a million rows; absurd, file `04`). P2 unblocks the genuine modest cases (dozens–low thousands);
  **it does not make seat/sentinel lines splittable.** Those need P3.

### P3 — Design correctness: what Power Quantity means; when per-unit is ever valid (the real fix)
**Data verdict (files `05`,`06`,`07`,`09`):** Power Quantity is a seat/user/license count or an "unlimited"
sentinel, never a machine count. Partitions are per-machine (~2.4/machine), never per-seat. There is no business
need to materialize 7,500 / 999,999 OrderItems. Native RLM models this as **Quantity=N on one OrderItem + one
Asset Quantity=N**; per-unit lives only at the fulfillment layer (DRO `FulfillmentQtyCalcMethod=AlwaysOne`),
declarative and async.

**Recommended resolution (pending Joe sign-off):**
- **Default = do NOT explode seat-count Power lines.** Keep Quantity=N on a single OrderItem. Represent
  sentinels (9,999/99,999/999,999) as "unlimited/site" on one line; never split.
- **Restrict any split to genuine per-MACHINE cases**, driven by actual Hardware/Partition data (a real machine
  count), not raw license quantity. For OLO with `Partition_Record__c=null` (3,812/3,816 real lines) there is
  nothing to split — gate the split on real hardware presence, not quantity.
- **Add a before-save (or convert-time) rule** blocking per-unit Power splits above the agreed cap / on sentinel
  quantities, with a clear message.
- **If true per-unit fulfillment is ever required**, do it via native DRO decomposition at the fulfillment layer,
  not hand-rolled Apex on the sales OrderItem (file `09`).

- **Risk:** medium (behavior change), but it is the only durable fix. **Blocked on business decision.**
- **Effort:** depends on the decision (config-only if "don't split seats" + sentinel rule; larger if DRO
  fulfillment decomposition is adopted).
- **Sign-off:** **business-gated — Joe Romo + design owners.** Must precede committing P2's heavy async build,
  otherwise we engineer scaling for a model the business may abandon.

### P4 — Tests, coverage, E2E, rollout
- Re-establish coverage (currently **0%**, file `04`) — deploy blocker; org 75% gate.
- Extend the Apex test class (it never tests high qty, never asserts derived-field stamping on clones — file `04`).
- Full E2E convert matrix (see §4).
- Standard gated rollout UAT → validate → prod; coordinate Workday line-type owners; re-verify active proc
  version + live OrderRepriceInvocable body at build (daily churn).
- **Build a fresh repro quote** (the documented one is gone): Abstract `01tWC00000DD11GYAT` + qty ≥ ~50 on a new
  quote. Durable reference for the 999,999 case = quote `0Q0WC000002QEKV0A4` "DO NOT SEND … ELA Renewal"
  (Won, not converted, Power OLO @ 999,999) — **do NOT convert it** (flagged DO NOT SEND); use as evidence only.

---

## 4. Test matrix

### Apex unit (extend `PowerOrderSplittingServiceTest`; add `@TestSetup` flow-bypass or assert with flows)
| # | Scenario | Asserts |
|---|---|---|
| A1 | OLO qty 4 (existing) | 3 clones, qty=1, shared HW, amounts divided — keep |
| A2 | OLH qty 3 (existing) | 2 clones, HW cloned — keep (note OLH is dead in prod) |
| A3 | non-Power qty 5 | **0 clones** (negative — Solution_Group≠Power) — keep |
| A4 | qty 1 | 0 clones — keep |
| A5 | bulk multi-order | bulk-safe; SOQL/DML under limit — keep |
| **A6 NEW** | **clone stamping** | clone carries `Workday_Contract_Line_Type__c`, `Billing_Schedule_From/To_Date__c`, `EndDate`, `ServiceDate`, `PricingTermCount`, `Start/End_Date_Calculated__c` **equal to parent** — asserted explicitly |
| **A7 NEW** | **stamping WITH flows suppressed** | run with `Is_Split_Line__c=false` entry guard active; clones still fully stamped (proves Apex copy/derive works without the flows) |
| **A8 NEW** | **describe-hoist regression** | qty ~50; assert `Limits.getCpuTime()` headroom + clone count; guards against re-introducing per-clone `getDescribe()` |
| **A9 NEW** | **hard cap** | qty > cap → `success=false`, clear `errorMessage`, **0 DML / no Savepoint** (returns before any insert) |
| **A10 NEW** | **cap boundary** | qty = cap → succeeds; qty = cap+1 → capped |
| **A11 NEW** | **line-type verbatim inherit** | clone `Workday_Contract_Line_Type__c` == parent (NOT reverse-lookup) — SC-3368 guard |
| **A12 NEW** | **FK + split flag** | clone `Original_Order_Item__c`==parent.Id, `Is_Split_Line__c`=true; original reset to false / FK null (Phase 5) |
| **A13 NEW** | **ValidationResult restore** | Phase 8 restores `Order.ValidationResult=null` on split orders that were clean |
| **A14 NEW (P2)** | **batch chunk idempotency** | re-running the batch on a partially-split order does not double-create (key on Original_Order_Item__c + Split_Status__c) |

### E2E convert (post-deploy, with explicit auth; build fresh quotes)
| # | Scenario | Expected |
|---|---|---|
| E1 | small Power OLO (≤10) | splits, all clones stamped, converts + activates + Workday clean |
| E2 | medium Power (~100, under cap) | converts within limits |
| E3 | repro-class (Abstract ~456) | P0/P1: capped with friendly message; P2: converts async + activates |
| **E4 negative** | **non-Power high-qty (e.g. Endpoint DLP @ 750k)** | converts and **does NOT split** (Solution_Group≠Power gate) — must not regress |
| **E5 guardrail** | **sentinel Power (999,999) / thousands-qty** | **blocked with a clear message, NOT a governor fault / not 1M rows** |
| E6 | per-machine OLO with real `Partition_Record__c` (small N) | legitimate split works; partitions cloned correctly |
| E7 | mixed quote (Power + non-Power + qty-1) | only qualifying Power lines split |
| **E8 (P2)** | async partial-failure | chunk failure surfaces on Order, does NOT roll back the committed convert; retry resumes idempotently |
| **E9** | shared-proc context survival | repriced clones do NOT trigger "couldn't fetch SalesTransactionContextExt_v2" (full-field clone preserved) |

---

## 5. Business questions for Joe Romo (block the real fix)
1. **What does Power `Quantity` represent** — physical machines/LPARs, or user/seat licenses? (Live data points
   overwhelmingly to seats/sentinels: every top-20 high-qty product is per-seat software/maintenance.)
2. **When, if ever, is per-unit (one OrderItem per unit) splitting actually required?** Is it ever needed above
   a few dozen lines? Should it be gated on real **Hardware/Partition** presence rather than license quantity?
3. **Are 999,999 / 99,999 / 9,999 intended "unlimited / site-license" sentinels?** If so, splitting them is never
   valid and must be excluded by rule.
4. **Acceptable convert UX if splitting goes async** (P2): the Order exists before lines finalize; activation and
   Workday submission wait for async completion (no SLA). Is a non-immediate activation acceptable, or do we need
   a hybrid (sync activate under a small qty threshold, async above)?
5. **What synchronous cap value** (P0 `MAX_SYNC_CLONES`) is safe for the genuine per-machine cases without
   blocking real business (start 200; the largest legitimate live split ever seen is 9)?
6. **Backlog handling:** ~80–170 non-terminal (mostly NULL-status renewal) quotes are un-convertible today and
   growing. Do we remediate them by re-scoping the offending lines (per Q1–Q3) rather than forcing a split?

---

## 6. Explicit non-violations (constraints respected)
- **Read-only honored:** this is a design doc; no deploy/DML/flow-run performed. Every change above is gated on
  fresh explicit authorization.
- **10k DML-row ceiling:** P0/P1 cap below it; P2 chunks per transaction; P3 stops exploding seat/sentinel lines
  (the only way to honor it at 750k).
- **RLM Quote-DML lock:** nothing touches Quote DML; all DML is OrderItem/Partition/Hardware/Order (not platform-
  locked — file `03`).
- **SC-3210/3368 `Original_Order_Item__c` conflation:** clones INHERIT the parent line type verbatim (Apex copy);
  the entry-condition suppression + parent-copy removes the reverse-lookup path on clones — a split-behavior
  change that does NOT re-break Workday line-type.

---

## 7. Sequencing recommendation
1. **P0 now** (guardrail + result-inspection + faultConnectors) — stops the silent gack on the live backlog;
   lowest risk; gives Joe time on the design questions.
2. **P1 next** (hoist + Apex-stamp + entry guards) — after build-time verification of "copy vs derive" and line-
   type owner coordination; lifts the sync ceiling for genuine cases.
3. **Joe answers Q1–Q4 → P3 decision** before committing P2.
4. **P2** only if the business confirms per-unit splitting is genuinely needed at scale (likely NO for seats);
   otherwise P3 config (don't split seats + sentinel rule) is the resolution and P2 shrinks to "modest per-machine
   async" or is unnecessary.
5. **P4** throughout (tests/coverage are a deploy blocker regardless).
