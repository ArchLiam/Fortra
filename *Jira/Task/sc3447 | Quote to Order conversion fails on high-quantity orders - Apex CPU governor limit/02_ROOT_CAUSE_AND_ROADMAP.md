# SC-3447 — Root Cause & Fix Roadmap

## Root cause (one statement)

Quote→Order conversion runs **synchronously** and calls `PowerOrderSplittingService`, which expands a
`Solution_Group='Power'` line into **(qty − 1) individual qty=1 OrderItem clones** — each with a cloned
Hardware + Partition record and each re-triggering **three autolaunched flows** (Set Dates, Set Workday
Contract Line Type, and a deprecated duplicate). The per-unit fan-out is **unbounded by quantity**, so a
Power line of a few hundred units accumulates > 10,000 ms of Apex CPU in a single transaction →
`System.LimitException: Apex CPU time limit exceeded` → the convert flow faults and the whole
transaction rolls back. The platform surfaces the governor failure as the generic
*"Limit Exceeded / exceeded the maximum limit for this feature"* (or *"unhandled fault in this flow"*).

**Three compounding flaws:**
1. **Per-unit cardinality** — `for (i=1; i<qty; i++)` makes record volume scale 1:1 with quantity. This cannot scale and even bursts the 10,000-row DML limit well before any realistic top-end quantity.
2. **Redundant per-clone automation** — the same 3 flows re-run on every clone (incl. a deprecated dead duplicate), instead of stamping the derived values once in Apex.
3. **Synchronous execution** — all of it runs in the user's 10,000 ms request rather than async (60,000 ms + chunking).

---

## Key decision before building (business + design)

**Q: At what quantity is per-machine Power line splitting actually meaningful?**
Splitting exists to produce one order line + Hardware + Partition per physical IBM Power machine/LPAR
for license tracking. Real Power-hardware counts are modest (dozens, maybe low hundreds) — not the
thousands the test data implies. We must confirm the realistic ceiling with the PO/business, because it
determines whether high-qty Power lines are a **data/config error** (re-tag / validate) or a genuine
scenario the architecture must support.

Two non-exclusive outcomes:
- If high-qty Power lines are **not** a real scenario → add a guardrail/validation and treat the repro's
  `Abstract = Power` tagging as test noise; the architecture fix still lands for safety.
- If they **are** real → the per-unit model must be re-represented (you cannot persist hundreds of
  thousands of OrderItems regardless of CPU; the 10,000 DML-row limit is a hard ceiling).

---

## Roadmap

### Phase 0 — Triage & unblock (hours)
- ✅ Root cause confirmed (this dossier).
- Confirm whether the repro products are correctly tagged: `Abstract` is `Solution_Group='Power'` on a
  *Subscription*-family product — likely mis-tagged test data. Validate against the real Power catalog.
- Unblock the specific order if business-urgent: correct the Solution-Group tag (if wrong) **or** run the
  conversion with the splitting deferred to an async path (Phase 2 spike) — owner-gated.
- **No prod changes.** (UAT deploy/DML requires fresh explicit authorization.)

### Phase 1 — Cut per-clone cost (1–2 days) — biggest, lowest-risk win
- **Remove / stop invoking the deprecated `Autolaunched Set Workday Contract Line Type` subflow** (≈ ⅓ of
  flow interviews). Coordinate with the SC-3366 owner (same dead flow).
- **Stamp the derived fields on clones in Apex** inside `PowerOrderSplittingService` before insert
  (Workday Contract Line Type, Set-Dates outputs), and **guard the per-record flows to skip
  `Is_Split_Line__c = true` clones**, so Set Dates / Set Workday line-type do not re-run per clone.
- **Reuse one describe/field map** instead of rebuilding it inside `createFullClone` per clone.
- *Expected:* removes ~1,000+ flow interviews + most repeated CPU from the sync path; raises the qty
  ceiling several-fold and likely clears the repro quote synchronously.

### Phase 2 — Make it scale: async + hard guardrail (3–5 days)
- **Move splitting off the synchronous convert request** into a `Queueable`/`Batchable` (60,000 ms CPU,
  chunked DML). Convert returns immediately; the order shows "line splitting in progress".
- **Chunk** clone creation so no single transaction approaches CPU/DML limits (e.g. N clones per chunk,
  chained queueables).
- **Add a hard cap** on synchronous split count with a clear, catchable validation message (no more raw
  governor fault to the UI).
- Surface async status/errors on the Order (status field + platform event), replacing the silent
  rollback.

### Phase 3 — Design correctness (gated on Phase-0 business answer)
- If high-qty Power lines are out of scope → add a **before-save validation** preventing
  `Solution_Group='Power'` lines above the agreed ceiling, and correct catalog tagging.
- If in scope → redesign the representation so a high count of identical machines does **not** require one
  physical OrderItem per unit (aggregate line + child Hardware/Partition collection, or summarized
  licensing model). Persisting 100k+ OrderItems per order is infeasible regardless of async.

### Phase 4 — Test, validate, roll out
- **Apex tests** for `PowerOrderSplittingService`: qty boundaries (1, 2, ~50, cap), bulk multi-order,
  both split types (Order-Line-Only vs Order-Line-and-Hardware), async path, rollback-on-error.
- **E2E convert matrix:**
  - small Power order (≤10) — passes, splits correctly.
  - medium Power order (~100) — passes within limits.
  - the repro (`Abstract` 456) — passes (post-fix).
  - **negative test:** non-Power high-qty order (Endpoint DLP @ 750,000) — must convert **fine and not
    split** (proves the gate and that high qty alone is safe).
- Deploy UAT → validate → prod via the standard gated process (prod authorization required;
  Workday line-type flows are prod-promotion-sensitive — coordinate owners).

---

## Ownership / coordination
- `PowerOrderSplittingService` — custom Fortra Apex (this ticket).
- `Fortra | OrderItem | Set Workday Contract Line Type` + deprecated Autolaunched duplicate — Workday
  line-type flow family (coordinate with the SC-3366 / line-type owners).
- `Fortra Quote to Order Conversion` flow — convert orchestration owner.

## Residual risks
- Re-tagging Solution Group changes pricing/splitting behavior elsewhere — verify no collateral.
- Async split changes the convert UX (order exists before lines finalize) — needs UI/messaging + any
  downstream (Workday submission, activation) to wait for split completion.
- The 10,000 DML-row ceiling is absolute — Phase 3 must resolve the representation for genuinely large
  counts; async alone does not.
