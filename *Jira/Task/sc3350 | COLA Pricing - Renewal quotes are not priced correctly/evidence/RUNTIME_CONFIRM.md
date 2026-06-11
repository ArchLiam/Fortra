# SC-3350 — Runtime confirmation of the net-price fix (live renewal population)

Read-only SOQL over all renewal QLIs (`QuoteAction.Type='Renew'`), 2026-06-10. Done BEFORE building V11, per
the "confirm 3 runtime facts first" decision. It materially refined the fix.

## What the population shows

| Observation | Evidence | Consequence for the fix |
|---|---|---|
| **Bug is PARTIAL, not universal** | Many renewal lines have NetUnitPrice > 0 (Active Defense BEC 296100, Automate 8041/2574/2400, 5250 Integrator 2021/6539, Device Profiler 334.75, Structural Sanitization 560.88). The $0 lines cluster on recent quotes 00780869/881/882/883/885/886 (incl. our Abstract 4697.946 → 0, beSECURE 929.25 → 0). | The seed must NOT blanket-overwrite Net; it must target only the genuine zeros. |
| **Some Fortra-Originated renewals carry a DISCOUNTED net** | Automate Professional 00734184: UnitPrice 2674.85 / **Net 2574.85**; Device Profiler: 341.25 / **334.75**; 5250 Integrator 00780852: UnitPrice 6306.3 / **Net 2021.25**. Net ≠ UnitPrice → a real discount/override is applied to net. | A blanket `Net := InputUnitPrice` would ERASE these. **A "only when Net unset" guard is mandatory.** |
| **Unseeded Net appears as BOTH 0 and null** | Abstract/beSECURE Net = 0; Structural Sanitization (00437526) Net = null. | Guard must cover both: `NetUnitPrice IsNull OR NetUnitPrice <= 0`. |
| **No regional renewals exist** | `Allow_Regional_Pricing__c = false` on all 35 renewal lines. | Runtime Q3 (regional) is theoretical now — can't be exercised; flag for later. |
| **No explicit partner renewals** | `Quote.Deal_Type__c` is only `null` or `'Fortra Originated'` across the population. | Runtime Q2 (partner) is theoretical now; the "Net unset" guard covers it anyway (an already-discounted partner net is skipped). |
| **A no-COLA renewal CAN have correct Net** | Structural Sanitization 00734244 (COLA% null): Net 560.88 ✓. But Additional Threat (COLA null, Qty 0, OneTime): Net 0. | Runtime Q1: no-COLA renewals are handled by the guard (seed only if net unset AND InputUnitPrice valid). |
| Nearly all renewals are `TermDefined` | `ProductSellingModel.SellingModelType = TermDefined` for 34/35. | SubscriptionPricing (seq 24) runs after the seed and multiplies the seeded per-unit net by term — correct. |

## The one residual (does NOT block the guarded fix)
Whether the "working" lines' Net is **real under V10** or **stale from an earlier path** is unresolved (our
Abstract line repriced under V10 → 0, yet other lines show Net > 0). **It doesn't matter for safety:** the
`NetUnitPrice IsNull OR ≤ 0` guard fires only on genuine zeros, so stale-but-positive nets are skipped and
real discounts are preserved — the fix is safe either way. (A waterfall on a working line would settle it, but
isn't required to ship the guarded seed.)

## Refined gate (supersedes the blanket gate in 06_NETPRICE_FIX_SPEC.md)
Seed `InputUnitPrice → NetUnitPrice` in `ListContainer62`, sequenced before its FormulaBasedPricing child, gated:

```
ItemPricingSource Equals 'LastTransaction'
  AND DerivedPricingAttribute = false           (protect Path-B derived/MDT renewals)
  AND (NetUnitPrice IsNull OR NetUnitPrice <= 0) (only fill genuine zeros; preserve any computed/discounted net)
```
Optional extra: `Deal_Type__c Equals 'Fortra Originated'` as belt-and-suspenders for the rare 100%-discount edge
(a Fortra-Originated line legitimately discounted to exactly 0 with InputUnitPrice>0 would otherwise be re-seeded).

**Known limitation:** a line legitimately discounted to net $0 with a positive InputUnitPrice would be re-seeded.
None exist in the current population; accept and revisit if it appears.
