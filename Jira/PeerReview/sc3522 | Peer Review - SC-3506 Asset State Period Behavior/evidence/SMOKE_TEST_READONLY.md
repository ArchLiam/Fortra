# Read-Only Smoke Test — ASP Invariants Across All Live Lifecycle Assets

**Org:** FortraUAT · **Date:** 2026-07-01 · **Method:** `sf data query` pull of every AssetStatePeriod + AssetAction for the 15 assets that have a non-`Generate` action, then invariant checks (contiguity/overlap, multi-year span, null EndDate, mrr=0 on renew/upsell, mrr-per-unit drop, cancel→no-new-period). 100% read-only.

## Result: 6 PASS / 9 FLAG (15 assets)

| Asset | Actions | #ASP | Verdict | Note |
|---|---|---|---|---|
| 06tCOTYA2 | Initial Sale, Renewals | 2 | **FLAG** | **MULTI-YEAR: ASP-083 2027-02-26→2039-02-25 (4382 days ≈ 12 yr)** — the PricingTermCount=12 bug |
| 07DSnFYAW | Initial Sale, Upsells | 2 | ✅ PASS | clean split, qty 1→2 |
| 07DXlKYAW | Initial Sale, Upsells | 2 | ✅ PASS | clean split |
| 08ARwnYAG | Initial Sale, Renewals | 2 | ✅ PASS | clean renewal, MRR uplifted 3.83→4.13 |
| 08ARwoYAG | Initial Sale, Renewals, Cancellations | 1 | ✅ PASS | **cancel → no new period ✓** |
| 08DFvvYAG | Initial Sale, Upsells | 2 | flag→**OK** | NULL EndDate (correct — OneTime product); latest MRR 0 |
| 08FcLaYAK | Initial Sale, Renewals | 2 | **FLAG** | MRR=0 on renewal period ASP-548 (COLA zero-price) |
| 08LXfZYAW | Initial Sale, Renewals, Upsells | 3 | **FLAG** | MRR=0 renewal period; MRR/unit 2→0 (qty 100→275) added units $0 |
| 08MuWnYAK | Initial Sale, Upsells | 2 | flag? | MRR 0 both periods — verify if product is $0-priced feature |
| 08MuWoYAK | Initial Sale, Upsells | 2 | flag? | same — feature add-on, likely legit $0 |
| 08MuWpYAK | Initial Sale, Upsells | 2 | flag? | same |
| 08MuWqYAK | Initial Sale, Upsells | 2 | flag? | same |
| 08deKLYAY | Initial Sale, Upsells | 2 | **FLAG** | **MRR/unit 492→164 (qty 1→3) — added units contributed $0** (self-reproduced amendment, Order 00095676) |
| 08deyfYAA | Initial Sale, Upsells | 1 | ✅ PASS | same-effective-date → single period (expected) |
| 08deygYAA | Initial Sale, Upsells | 1 | ✅ PASS | same-effective-date → single period (expected) |

## Interpretation
- **Structure invariants hold everywhere:** no overlaps, no gaps, cancel creates no new period, same-effective-date collapses to one period. The ASP *engine* is behaving correctly on every asset.
- **The only "impossible" value** is 06tCOTYA2's 12-year (2039) renewal period — a data-integrity defect sourced upstream (`PricingTermCount=12`).
- **The pervasive issue is price, not structure:** upsell/renewal periods repeatedly land at **MRR 0 / added-units-$0** (08deKLYAY is the cleanest self-reproduced case: a real-priced product whose 2 added units added $0). This is the `Asset.PricingSource = null` carryover gap (SC-3441 family) + COLA renewal zero-price (SC-3350/3346). The state period's **quantity is right; its price/MRR is wrong** — exactly the license-key risk SC-3506 raises.
- **False-positive guardrails:** 08DFvvYAG null EndDate = correct (OneTime); the 08MuWn family MRR=0 may be legitimately $0-priced feature add-ons (verify against PricebookEntry before flagging).
