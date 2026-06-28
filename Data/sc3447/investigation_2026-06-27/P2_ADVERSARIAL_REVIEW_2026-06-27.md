# SC-3447 P2 — Adversarial Architecture Review (read-only, FortraUAT 2026-06-27)

**Reviewer stance:** adversarial. Attack the dangerous parts of the proposed P2 async pipeline.
**Org:** FortraUAT (00DWC000006eUFF2A2). All live facts re-verified this session.
**Verdict:** PARTIALLY-SOUND. The mechanics are largely correct and honestly hedged; the design is
buildable as a contingency BUT (a) has one genuine unresolved feasibility hole at high N (the mandatory
final whole-order reprice cannot itself be chunked), (b) rests on one unproven showstopper assumption with
ZERO positive evidence, and (c) is NOT justified now — live evidence is overwhelmingly against building it.

---

## 1. Can reprice + activate actually run async? — UNPROVEN SHOWSTORPER, correctly flagged

**Verified live this session:**
- `OrderRepriceInvocable_live.cls` body: only input = `Id orderId` (L10-13). NO `contextDefinitionName`,
  NO flow-only input, NO `SalesTransactionContextExt_v2` reference in the Apex. Context binding is resolved
  by the platform via the active pricing procedure (V16), not by the calling code. (L33-91.)
- It reads ONLY `r.success` (L70) — the SYNCHRONOUS part of `PlaceOrderResult`. It never polls
  `requestIdentifier` / `statusURL`. Confirmed.
- `OrderRepriceInvocableTest` header (live retrieve) states verbatim: `PlaceOrderExecutor.execute()` "leaves
  the RLM / commerce pricing engine in a state that makes a subsequent QuoteLineItem INSERT in any sibling
  method of the SAME Apex test job fail with INVALID_CROSS_REFERENCE_KEY" — proven by bisection in THIS org.
  The state-poisoning hazard is REAL and correctly forces Batch (fresh txn per execute) over a looping Queueable.
- **DECISIVE for risk #1:** the ONLY live caller of `PlaceOrderExecutor.execute()` in the entire org is
  `OrderRepriceInvocable`, and it is ONLY ever invoked from the convert SCREEN FLOW (CurrentTransaction).
  Tooling `SELECT Name FROM ApexClass WHERE Name LIKE '%PlaceOrder%' OR '%Reprice%' OR '%Commercial%'` →
  `OrderCommercialNetService`, `OrderRepriceInvocable` (+ tests) only. There is **NO existing Batch /
  Queueable / Schedulable anywhere in this org that runs the Force reprice.**

**Adversarial conclusion:** The design's central "it works async" finding is supported by the *absence* of a
documented async-Apex ban + the *absence* of flow-context binding in the visible code + the fact the only
input is an Order Id. That is reasonable but it is **proof of nothing**. There is zero positive evidence
(no async run, no async caller anywhere) that the managed RCA engine resolves the V16 context and completes
pricing when `execute()` is invoked from Batch/Queueable. The test header even notes the executor "typically
can't fully run" in a unit-test context — so the E13 spike CANNOT be a plain Apex test; it requires a real
sandbox async run, which read-only mode cannot perform. **This is correctly flagged as the #1 risk and a
hard go/no-go spike (E13), and the fallback (hard-cap P0 + P3) is named.** The honesty is good. But the
spec's own verdict ("FEASIBLE as designed") overstates: it should read FEASIBILITY-UNPROVEN until E13 runs.
Activation itself (plain `Status='Activated'` update) is far lower risk and credibly async.

---

## 2. The assetize race (SC-3419) — adequately guarded IF the invariant holds, with one new exposure

The design's ordering invariant (build ALL N → reprice → clear ValidationResult → COMMIT → activate LAST →
assetize/billing fire post-commit automatically) is the correct guard and is stated at every boundary.
`Fortra_Assetize_Order` V17 is AsyncAfterCommit + Status='Activated'-gated, so it provably runs AFTER the
activate txn commits, on the full N-line order, single-threaded per order. Async does NOT amplify the
SC-3419 collision (which is a duplicate-line-vs-pre-existing-asset DATA-shape issue, not a timing issue).
The "no OrderItem DML after activate" rule correctly prevents the OrderCommercialNetService ContextPersistence
stuck-assetize race. **This part is sound** — async activation does not reintroduce 0-Assets *provided the
invariant holds*.

**NEW exposure the design does not fully close (manual-activate during build):** between STAGE A chunks the
committed order sits Draft, `Split_Status='Split In Progress'`, with a PARTIAL clone set. Nothing in the
design *blocks* a user (or the already-shipping `Screen1_OrderActivation` manual-activation path, or any
other Status-flipping automation) from activating that half-built Draft order. The `Split_Status` field is a
status label, not an activation lock. If a partial order is activated mid-build → 1-line-ish order activates,
clones land on an active order unpriced → **re-creates SC-3441 + SC-3419 exactly.** The design needs a hard
guard (a before-update Order validation/flow that blocks Status='Activated' while `Split_Status IN
('Pending Split','Split In Progress')`), not just a status label. This is a real gap, not flagged.

---

## 3. The SC-3441 trap (unpriced lines on an activatable order) — mostly closed, ONE unresolved hole

Closed correctly:
- STAGE A `finish()` verifies `existingClones == N-1` for every original before enqueuing reprice → reprice
  never sees a partially-built order via the pipeline's own path.
- STAGE B `finish()` gates STAGE C on REAL pricing completion (CalculationStatus='CompletedWithPricing' AND
  ValidationResult null AND totals match — the live `isPricingReady`, OrderRepriceInvocable L106-121), NOT
  bare `r.success`. This correctly addresses the part-sync/part-async `PlaceOrderResult` hazard at >100 lines.

**UNRESOLVED HOLE — the mandatory final whole-order reprice cannot itself be chunked (high N):**
P2_01 §3 is honest that (i) order totals + the `pricingReady` total-match (`quoteTotal == Order.TotalAmount`)
are inherently WHOLE-ORDER, so a final whole-order reconciliation pass is MANDATORY; and (ii) that final
whole-order Force reprice over N lines is the O(N) operation (1 PATCH/OrderItem + ~4×N bulk updates + 92KB
posthook) that hits the 10k-row + CPU wall. **These two facts collide:** at the high N where chunking is
needed at all, the mandatory final whole-order pass does not fit one transaction either, and there is no
documented RLM mechanism for a partial-graph Force that yields correct whole-order totals. The spec defers
this to "measure at build," but it is not a measurement question — it is a design gap: the reprice stage's
chunking story does not close at the band P2 claims to serve. At low N (the only real population) it is a
non-issue because the whole order fits one txn — which is itself the point: **if N always fits one txn, you
do not need the chunked async pipeline at all.** The chunking exists to serve a band where the reprice
chunking provably does not work.

---

## 4. 10k-row honesty + chunk math — ACCURATE

- DML rows/clone: VERIFIED against `PowerOrderSplittingService.cls` — OLO partition path = OI insert (Phase 4
  L243) + Partition insert (Phase 6 L303) + OI partition-ref update (Phase 7 L325) = ~3 rows; OLH adds
  Hardware insert (Phase 2 L218) = ~4. Spec's `1,500 clones × 3 = 4,500 rows (>50% headroom)` is correct.
- "Scope is NOT originals-with-fixed-scopeSize because one high-qty original can blow 10k rows" — correct;
  Phases 4/6/7 expand per-unit, so the cursor must be (originalId, nextSlotIndex). Sound.
- 10k DML rows identical sync/async; async raises only CPU 10s→60s, heap 6→12MB, SOQL 100→200; enqueue
  limit async = 1 (forbids fan-out, allows self-chain) — all consistent with the cheatsheet.
- **Seats/sentinels NEVER materializable** — explicitly and correctly stated everywhere (≥75-100 chunks,
  ~1M+ rows, + un-chunkable managed submitOrder/billing tails). P3 predicate (`Quantity > 1 AND
  (Partition_Record__c != null OR (OLH AND Hardware__c != null))`) is the gate sync AND async; seat lines
  carry neither lookup → never enter the loop. VERIFIED in `queryOrderItemsToSplit` (force-app L393-395).
- **Real max N is honestly stated** as low thousands (~2,000-5,000), bounded by the UN-chunkable managed
  ceilings (in-line sync submitOrder at activate, O(N); per-OrderItem billing-schedule job, 10k wall in its
  own txn) — both managed, both confirmed AsyncAfterCommit/CurrentTransaction in the mechanics files. Good.

Minor honesty-ledger defect: P2_SPEC §7 says the population is "4 lines, all N=2"; the body §0/§6.4 say
"qty=3 (2 clones each)." Live truth (below) = qty=3 (2 clones each). The "N=2" phrasing is wrong wording
(it conflates clone-count with quantity); harmless to substance, should be corrected.

---

## 5. Is P2 justified NOW? — NO. Building it now is PREMATURE / speculative. (HIGH confidence)

Live evidence gathered this session:
- **Split-eligible population (exact P3 predicate, live):** EXACTLY 4 OrderItems org-wide, ALL Quantity=3
  (2 clones each, max materialization = 2 extra lines). Query run verbatim. Two are OLO, two OLH; all on
  distinct test orders.
- DESIGN_FINAL §2: ~63-66 split clones exist org-wide ever; largest SF-activated group = 9 (then Workday
  FAILED); largest Workday-clean = 4. Requirement is "up to 750,000" — ~5 orders of magnitude beyond
  anything that has ever succeeded.
- DESIGN_FINAL §2: **the per-machine path P2 is built for is VESTIGIAL** — 3,812 of 3,816 real qty>1 Power
  lines have `Partition_Record__c=null`; the only 4 that don't are UAT tests; the OLH branch's only-ever
  order is a test fixture.
- DESIGN_FINAL §3 (HIGH confidence, three converging legs: API spec + captured payload 00095355 + Mule
  mapping): **Workday takes ONE contract line with `quantity=N`.** Per-unit splitting is unnecessary AND
  actively breaks Workday (SC-3210/3368 subsplit conflation). With quantity=N, "P2 collapses" (their words)
  and is "likely dropped."

P2 is a ~5-8 dev-day + 2-3 day heavy-E2E build (multi-stage build/reprice/activate batches + Finalizer +
Scheduler + resume + platform event + status field family + LWC + the go/no-go spike), at 0% coverage today
(deploy blocker), with one unproven showstopper and one unresolved high-N reprice hole — to materialize, for
the entire current org, at most 2 extra OrderItems per line on 4 test records. The design team's own decisive
finding (Workday quantity=N) is expected to eliminate the need for P2 entirely.

**Build order is right: P0 (live) + P1 (cheap clones, measure the real sync ceiling) + P3 (don't split
seats; keep qty=N — the actual fix per the Workday finding). Hold P2 on the shelf.** P1 + measurement very
likely pushes the synchronous ceiling above any genuine per-machine count that will ever exist (largest ever
= single digits), making P2 moot even before the Workday answer.

### The single gating fact

ONE fact should gate any P2 build, and it is a business/integration answer, not an engineering one:
**Does Workday require one contract line per unit (per-machine), and if so, what is the genuine maximum
per-machine count?** (Operationally: get Joe / the Mule-Workday owners to confirm `line.quantity =
OrderItem.Quantity` against the actual DataWeave or an Anypoint log of a qty>1 resubmit.)
- If Workday takes quantity=N (expected, HIGH confidence) → **P3 is the resolution; P2 is DROPPED.**
- Only if Workday genuinely needs per-unit lines AND a real case exceeds the P1-measured sync ceiling
  (hundreds) does P2 become warranted — and even then the high-N reprice hole (§3) must be solved and the
  E13 async-executor spike (§1) must pass before any commitment.

---

## 6. Corrections the spec/design should make

1. Soften the headline verdict from "FEASIBLE as designed" to "FEASIBILITY UNPROVEN pending E13" — the
   async-executor-runs-against-V16-context claim has zero positive evidence (no async caller exists in-org).
2. Resolve or explicitly mark UNSOLVED the high-N reprice hole: the mandatory final whole-order Force pass is
   itself the O(N) operation that doesn't fit one transaction; do not bury it under "measure at build."
3. Add a hard activation guard (before-update Order rule blocking Status='Activated' while
   Split_Status IN ('Pending Split','Split In Progress')) — otherwise a manual/automation activate of a
   half-built Draft re-creates SC-3441 + SC-3419. Currently Split_Status is a label, not a lock.
4. Fix the §7 honesty-ledger wording "all N=2" → "all Quantity=3 (2 clones each)" (matches live + the body).
5. Resolve the field-naming collision before any build (Split_Status__c lifecycle vs Split_Sync_* family) —
   already flagged, just pick one.
6. State plainly in the executive summary that, given live evidence, the recommended action is DO NOT BUILD
   P2 now; the design is shelf contingency gated on the Workday quantity=N answer.

---

## 7. Live verification log (this session)
- `FieldDefinition` Order `Split%` → 0 rows (Split_Status__c ABSENT, confirmed). ValidationResult +
  CalculationStatus = non-calculated Picklists (writable gates), confirmed.
- `FieldDefinition` OrderItem → Original_Order_Item__c (Lookup→OrderItem), Is_Split_Line__c (Checkbox),
  Partition_Record__c (Lookup→Partition), Hardware__c (Lookup→Hardware) all PRESENT.
- Live P3 predicate query → 4 OrderItems, all Quantity=3 (2 OLO + 2 OLH, distinct test orders).
- `OrderRepriceInvocable_live.cls` read: input = Order Id only; reads r.success only; no context binding in code.
- `OrderRepriceInvocableTest.cls` header: state-poisoning (INVALID_CROSS_REFERENCE_KEY) proven by bisection.
- ApexClass tooling: only OrderRepriceInvocable calls PlaceOrderExecutor; no async caller in-org.
- `PowerOrderSplittingService.cls`: MAX_SYNC_CLONES=200 (hardcoded static, NOT yet CMDT-backed); P3 predicate
  L393-395; per-clone DML phases L218/243/303/325 (~3 OLO / ~4 OLH rows).
- DESIGN_FINAL §2/§3: vestigial per-machine path; Workday quantity=N (HIGH); P2 "collapses"/"likely dropped".
