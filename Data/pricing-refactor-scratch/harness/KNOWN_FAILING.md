# Known-failing baselines — tracked SEPARATELY

These are pre-existing defects captured at baseline. They are **excluded from the pass/fail gate** so a
refactor is never credited with "accidentally fixing" pricing. If a wave changes one of these lines, that is
an **intended** change and must be documented as such (not a silent regression).

## KF-2..KF-4 · NON-IDEMPOTENT baselines (caught by the idempotency gate 2026-07-06; PRE-EXISTING, no refactor done)
First-reprice ≠ second-reprice → these baselines are **not stable oracles** and are EXCLUDED from the 0-delta
cleanup gate. They are live **Wave-4 (hardening/idempotency) targets** — the SC-3390 family with exact repro.
Convergence (does 2nd==3rd?) still to confirm with one more reprice.

- **KF-2 · S5** (`0Q0WC000003IKeT`, partner Discount): 🔴 **DIVERGENT.** Net `4442.35 → 3642.727 → 2987.04` across
  1st/2nd/3rd reprice — **×0.82 EVERY reprice** (18% partner discount re-applied each time; posthook re-discounts an
  already-discounted line instead of recomputing from `Pre_Partner_Price__c`). Repeated reprice erodes price toward $0.
  **Live severe bug — warrants its own ticket independent of the refactor.** No stable baseline. Guards INV-5/D-11.
- **KF-3 · S7** (`0Q0WC0000039bwH`, Fortra-Orig): 🟡 **CONVERGES at 2nd click.** `line2 UnitPrice 71 → 355` between
  1st/2nd, then **2nd == 3rd (0 delta)**. Sales Price/`UnitPrice` stabilizes after two clicks (classic SC-3390 pattern).
  **Usable baseline = the 2nd-reprice snapshot (`idem/S7`).** Ties to the Marc DeBrey Sales-Price thread. Wave-4 target (should be 1st-click stable).
- **KF-4 · S11** (`0Q0WC000003FcrF`, attribute-tier): 🟠 **NOT converged after 3.** Net settled by 2nd but
  `Subtotal/TotalLineAmount` still moving on the 3rd (`2066.46 → 1471.995`). Multi-click rollup instability (SC-3390 family,
  worse than S7). No stable baseline yet. Guards INV-14/D-17.

## KF-1 · S3 — SC-3346 New-Maintenance qty=0 → $0 total
- Quote `0Q0WC000003IKkv`, line **"BoKS Administration License Fee"**: `Quantity=0`, `NetUnitPrice=722.5`, **`TotalPrice=$0`**.
- Root cause (per memory `sc3346_newmaint_qty0`): the middle maintenance line is born with `Quantity=0`, so `net × 0 = $0`.
- Frozen at baseline; `diff.py` on S3 runs with this line's `TotalPrice`/`Quantity` expected-as-is.
