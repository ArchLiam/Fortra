# SC-3447 — Adversarial Feasibility Review of the Fix Design (read-only, 2026-06-27)

Reviewer: adversarial feasibility critic. Org: FortraUAT (00DWC000006eUFF2A2). All checks read-only.
Verdict: **PARTIALLY-SOUND** — root cause and phased strategy are correct and feasibility-clean;
two factual errors in the supporting evidence and one self-acknowledged open risk that live data
now resolves against the design's optimistic branch. No showstoppers.

---

## What I independently re-verified live (and it held)

| Claim | Live check | Result |
|---|---|---|
| Convert flow active V27 / 301WC00000kSRnZYAW | `Flow` tooling | CONFIRMED V27 Active |
| Set_Dates V6 active, Set_Workday V11 active | `Flow` tooling | CONFIRMED |
| Class API v62, len matches | ApexClass | CONFIRMED (16635, API 62) |
| Live class == force-app (newline only) | diff | CONFIRMED (only `\ No newline at end of file`) |
| 0% code coverage (deploy blocker) | ApexCodeCoverageAggregate | CONFIRMED 0/231 |
| Power QLI qty>1 = ~18,136 | SOQL COUNT | CONFIRMED 18,137 |
| qty>100 = 1,573; qty>=100k = 402; max 999,999 | SOQL | CONFIRMED |
| 134 live OrderItems at 999,999 sentinel | SOQL | CONFIRMED |
| Repro product Abstract Power/OLO/Active/Subsplit | SOQL | CONFIRMED (+ Rev_Category RC_41202) |
| Reprice = 1 RecordWithReferenceRequest per OrderItem, Force | live OrderRepriceInvocable | CONFIRMED O(N) |
| Order.Split_Status__c (P2 new field) does not exist | FieldDefinition | CONFIRMED absent (must be created) |

Root cause (single sync transaction, no async boundary, CPU is the wall, per-clone describe ×N +
2 re-entrant flows ×N, plus the deeper seat/sentinel decomposition mismatch) is **CONFIRMED and sound.**
The two hard ceilings (10k DML rows identical sync/async; seat counts up to 999,999 not machine counts)
are real and the design respects both.

---

## Attack 1 — Async re-sequencing: does reprice + ACTIVATE still work? (P2)

**Design is correct here.** I verified via the live `OrderRepriceInvocable` body that reprice builds the
Force-reprice graph from `work.allOrderItems` (one PATCH per line) and activation is gated on
`Order.ValidationResult`. So if only the split moved async, reprice would price the un-split qty-N line
and Activate a 1-line order, leaving clones unpriced on an already-active order (re-creating the SC-3441
null-NetUnitPrice defect) and re-dirtying ValidationResult with no clearing pass. The design recognizes
this and moves the WHOLE Split→Reprice→Activate tail async together, activating LAST (in batch finish()),
serialized before `Fortra_Assetize_Order` V17 / AssetizationAsyncJob (SC-3419 race). **This is the only
legal sequencing and the design uses it.** Not a showstopper.

Caveat the design already flags and I endorse: reprice itself is O(N) (verified per-OrderItem graph), so
"async" does not remove the wall — the reprice may itself need chunking at extreme N. Honest.

## Attack 2 — Flow suppression / Workday line-type reverse-lookup (P1#2b)

**The fix is SAFER than the design's own supporting docs claim, but the docs contain a stale error.**

The prompt's worry: does suppressing per-clone flows break the SC-3210/3368 subsplit-parent reverse-lookup
that queries `OrderItem WHERE Original_Order_Item__c=parentId` (the clones ARE those children)?

I read the LIVE V11 `Fortra_OrderItem_Set_Workday_Contract_Line_Type` flow XML directly. It determines
subsplit purely from `$Record.Product2.Is_Subsplit_Product__c` (a product-level boolean; cross-object on
`$Record`, no SOQL) — **there is NO reverse-lookup on `Original_Order_Item__c` anywhere in the current
line-type flow.** I also grepped every retrieved flow and every Apex class: `Original_Order_Item__c` is
referenced ONLY by `PowerOrderSplittingService(.Test)`. `Is_Split_Line__c` likewise. No
flow/trigger/rollup/VR consumes either, so suppressing the flows on clones breaks nothing downstream.

Because the clone has the SAME Product2 as its parent, the flow result on a clone would be identical to the
parent (`Is_Subsplit_Product__c` is the same boolean) → **copy-parent-line-type-verbatim == what the flow
would have stamped.** P1#2a/#2b are internally consistent and safe.

**ERROR to correct:** investigation file 06 §5 (and DESIGN §3 P1, plus openRisk "SC-3368 reverse-lookup")
state the line-type flow "does a parent/child Product2 reverse-lookup and has historically mis-stamped
pure qty-split parents." That describes an OLDER version (V10-era, per MEMORY); it is NOT true of the live
V11. The design's mitigation is still correct, but the risk is OVERSTATED — there is no reverse-lookup to
re-break today. Down-rank the "SC-3368 reverse-lookup" open risk to "verify V11 still product-boolean at
build" (daily churn could reintroduce a reverse-lookup version).

## Attack 3 — 10k DML-row ceiling: honestly handled, or wall just moved? (P2/P3)

**Honestly handled.** The design explicitly states P2 (chunked async) CANNOT persist 999,999 OrderItems
for one line (~100+ chunks, a million rows) and that ONLY P3 (don't explode seat/sentinel lines) honors
the ceiling at 750k. DML-row math verified: on the OLO+partition path ~3N rows (Phase 4 insert clones +
Phase 6 insert partitions + Phase 7 update clones), failing at N≈3,333; on the dominant no-partition real
path (3,812/3,816 lines have null Partition) only Phase 4 (N rows), failing at N≈10,000. Both sub-ceilings
are below the client's real quantities by orders of magnitude. The hard-cap (MAX_SYNC_CLONES=200) is
defensible as a conservative floor, explicitly to be set WITH Joe; the design correctly treats the real
fix as P3 (config: keep Quantity=N on one line), not the cap. **Sound.**

## Attack 4 — Apex stamping correctness (P1#2a): are copied values right per-unit?

**The design's "copy vs derive" open risk is REAL and live data resolves it against the optimistic branch.**

I queried freshly-created (2026-06-25/26/27) NON-split Power OrderItems (the would-be split originals):
- `FIXED AMOUNT` lines: `EndDate=null`, `PricingTermCount=0` (SC-3411/3420 backstop NOT firing).
- `FIXED AMOUNT BILLING ONLY` (subsplit) lines: EndDate + PTC=1 present.

So the ORIGINAL is itself partially unstamped at convert time for the dominant FIXED AMOUNT case. P1#2a
"copy from parent" would faithfully copy `EndDate=null / PTC=0` onto every clone — it PROPAGATES the
existing 36% gap, it does not close it. The design flagged this as a build-time verification ("if the
original is unstamped, RE-DERIVE mirroring Set_Dates V6"); current data already answers it: **copy is
sufficient only to NOT REGRESS (clones match what a non-split line would have); closing the 36% gap
requires the RE-DERIVE path and is effectively SC-3411/3420 scope, not SC-3447's to own.**

Correction: the design should COMMIT P1#2a to the re-derive path only if the team wants to close the gap;
otherwise scope P1 as "copy = no-regression" and explicitly defer the 36% null EndDate/PTC to SC-3411/3420.
Do not block SC-3447 on closing a pre-existing line-stamping defect.

Per-unit AMOUNTS: `Manual_Discount__c/qty` and `Displaced_ARR__c/qty` are evenly divided; prices
(NetUnitPrice/UnitPrice/TotalPrice) are NOT copied-then-trusted — the reprice tail recomputes them via
PlaceOrderExecutor Force. So there is no double-counting risk from the copy. Correct.

## Attack 5 — Deploy auth / prod risk

All phases are gated on fresh UAT deploy auth; design honors read-only-until-authorized. P1/P2 add a
version to the Workday line-type family (Set_Workday V11→V12, Set_Dates) — additive entry condition,
preserves the verbatim-parent invariant; design flags coordination with line-type owners (Ben Kozlowski)
and re-verification of V6/V11 active at deploy. **No undisclosed prod risk.** The "DO NOT SEND" 999,999
quote (0Q0WC000002QEKV0A4) is correctly marked reference-only.

**Minor implementation error (P0):** the design says set success=false and `return` "BEFORE any
Savepoint/DML." But `Database.setSavepoint()` is already taken at L108, BEFORE `queryOrderItemsToSplit`
at L112. The cap check (after L113) therefore runs AFTER the savepoint. This is harmless (a savepoint with
no subsequent DML costs nothing and needs no rollback), but the stated placement is inaccurate; either move
the cap check ABOVE L108, or correct the wording to "before any DML" (the savepoint is unavoidable as
written). Also: at L37-41 a null orderId already sets success=false per-request; the cap loop must set
success=false on ALL results in `resultByOrderId`, consistent with the catch block at L316-325.

---

## Coverage gaps in the design

1. **The describe-hoist (P1#1) has a correctness subtlety not called out.** `createFullClone` copies every
   createable field, INCLUDING `Original_Order_Item__c` and `Is_Split_Line__c` if the original had them set
   — but the original is queried fresh (its own Is_Split_Line=false, Original_Order_Item=null), so the clone
   starts clean and the code overwrites both at L162-163. Hoisting to a static `createableFieldNames` list is
   safe ONLY if the list excludes nothing the loop currently copies; since the current loop copies all
   createable non-null fields, the hoisted list must be "all createable field names" (not a hand-curated
   subset). Low risk but the test A8 must assert the clone field-set is byte-identical to the pre-hoist output.

2. **P0 cap on a MULTI-order invocable.** The cap sums clones across ALL orders in one invocable call. The
   convert flow passes one orderId per call, so in practice it is single-order — but if any future caller
   batches orders, a single large order would fail the whole batch. Acceptable given the current single-order
   caller, but note it.

3. **No mention of `OrderItemAttribute` / config attributes on clones.** `createFullClone` clones only the
   OrderItem, not its OrderItemAttribute children (config attrs). File 02 confirms no active automation on
   OrderItemAttribute, and the current behavior already does not clone them, so this is not a regression — but
   if Power lines carry pricing-relevant attributes, unattributed clones could reprice differently. Worth a
   one-line E2E assert (E9 partially covers via context survival).

4. **Convert flow apiVersion is 62** (file 01). If P0/P1 deploy a new flow version, decide whether to keep
   v62 or bump (org memory uses higher). Cosmetic; flag only.

---

## Bottom line

The design's diagnosis is correct and independently reproduced. The phased plan (P0 guard + fault-close,
P1 hoist + Apex-stamp + flow-suppress, P2 whole-tail async+chunk, P3 don't-explode-seats, P4 tests) is
feasibility-clean and respects every governor/platform constraint I could test, including the hard ones
(10k DML rows, activation-after-split-only, assetize race). The honest weaknesses are: (a) two supporting
docs overstate the SC-3368 reverse-lookup risk that the live V11 flow no longer has; (b) the "copy vs
derive" open risk resolves, per current data, to "copy = no-regression; closing the 36% gap is separate
SC-3411/3420 scope"; (c) a minor P0 savepoint-ordering wording error. None break the design.
