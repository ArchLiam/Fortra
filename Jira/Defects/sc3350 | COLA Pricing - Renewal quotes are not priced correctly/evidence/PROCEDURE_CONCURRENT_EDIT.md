# SC-3350 — Concurrent edit on the active pricing procedure (2026-06-10 19:28Z)

**Trigger:** "someone is working on it." Re-retrieved the active procedure and diffed against our analysis copy.

## What changed
- Active version is still **V10** but was **modified in place at 2026-06-10T19:28:24Z by Nir Kailash** (was
  Liam's 03:22Z copy when we analyzed it). +120 lines (52499 → 52619), 192 changed lines.
- **Nir's change does NOT touch `NetUnitPrice`.** It adds `PricingTermCount` defaulting
  (`EvergreenPricingTermCountConstant`/`OneTimePricingTermCountConstant → PricingTermCount`),
  `InclusivePriceConstant → TotalLineAmount`, attribute pricing (`Assignment86`), and adjustment null-safety
  (`NullCheckforLineAdjustment`, `IF(ISNULL(ItemTotalAdjustmentAmount),0,…)`). New containers:
  `ListContainer11/63/74/78/81/84` + filters `ListOperation64/67/71/75/79/82/85`.

## Our net-price fix re-verified against the CURRENT V10
- `ListContainer62` (the `LastTransaction` renewal container) is **unchanged** — children = `ListOperation63`
  (filter) + `FormulaBasedPricing` (NetUnitPrice*Qty reader). **Still no `InputUnitPrice → NetUnitPrice` seed.**
- `NetUnitPrice` write-count unchanged at 467 → Nir added no net-price writer. **The $0-net bug persists and our
  fix (06_NETPRICE_FIX_SPEC.md) is still correct and needed.**
- Fresh baseline saved at `Data/sc3350/retrieve2/`.

## Decision: HOLD the V11 build — coordinate first
Do **not** build/activate V11 while Nir is editing the active V10 in place:
- A V11 cloned now would either be clobbered by Nir's next publish, or our activation would clobber Nir's
  19:28Z work — the classic two-editors-on-one-active-procedure collision (prior gack incidents).
- When clear: rebase onto whatever version is active after Nir finishes, **re-verify `ListContainer62` + its
  sequence number** (sequences shift as containers are added), then build V11 per the spec.

## Recommended coordination
- Confirm with **Nir / Marc** that the procedure is in a stable state before we build.
- Loop them on the net-price fix now (they're in the procedure) — they may fold the seed in, or we sequence
  ours after theirs. Either way the seed targets `ListContainer62` with the guarded gate
  (`LastTransaction AND DerivedPricingAttribute=false AND (NetUnitPrice IsNull OR ≤0)`).
