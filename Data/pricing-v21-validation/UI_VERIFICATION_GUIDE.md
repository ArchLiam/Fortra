# V21 — Manual UI Verification Guide (13 defects)

**Org:** FortraUAT — https://fortra--uat.sandbox.lightning.force.com  ·  **Active proc:** Rev_Mgmt_Default_Pricing_Procedure V21 (LastModified 22:01Z)

## How to reprice a Quote in the UI

1. Open the Quote (links below).
2. Click your **Reprice** action (the button your team uses to recalculate — commonly "Reprice", "Reprice All", or "Calculate Prices"; if your layout has none, open the **Quote Line Editor**, make a trivial edit, and **Save** — that reprices).
3. Open the specific **Quote Line Item** and read the field in the "Field to read" column. If a field (e.g. Net Unit Price, Unit Price) is not on the line layout, add it to the Quote Line Editor grid or the QLI page layout, or ping me to query it.

> A defect is **still open (FAIL)** if you see the "Still-broken looks like" value, and **fixed (PASS)** if you see the "Fixed looks like" value.

| # | id | category | Open this record | Action | Field to read | ✅ Fixed (PASS) looks like | ❌ Still-broken (FAIL) looks like |
|---|---|---|---|---|---|---|---|
| 1 | **K-01** | Edge Cases | [Quote 0Q0WC000003FoMA0A0 (cancellation, Qty -1)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FoMA0A0/view) | Reprice the quote | Reprice result + line Total Price | Reprice SUCCEEDS; the -1 line Total Price shows a NEGATIVE credit (net x -1, e.g. -3000) | Reprice ERRORS (SF-Pricing-00006 / SF-BRE-00004) or Total Price = 0 |
| 2 | **F-12** | Transaction Type | [Quote 0Q0WC000003FapR0AS (amend / remove, Qty -50000)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FapR0AS/view) | Reprice the quote | Reprice result + line Net/Total | Reprice SUCCEEDS and the removed line shows a prorated NEGATIVE delta | Reprice ABORTS at StampBaseFilter; Net Unit Price = blank, Total Price = 0 |
| 3 | **G-01** | Multi-Currency / Regional | [QLI 0QLWC000003kmG14AI (EUR line, Quote 0Q0WC000003FcrF0AS)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kmG14AI/view) | Reprice, open the line | Unit Price vs Net Unit Price | Unit Price == Net Unit Price (~1471.995 EUR) | Unit Price is HIGHER than Net (FX applied twice on the display channel) |
| 4 | **G-02** | Multi-Currency / Regional | [Quote 0Q0WC000003FcrF0AS (EUR, AAM)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view) | Reprice, open the EUR line(s) | Net Unit Price / List Price | Net derived from the EUR List Price (~2943.99); no line at $0 | Net = 1471.995 (=USD 1575 x 0.9346 -> USD ABA override leaked into EUR), or a combo line prices $0 |
| 5 | **H-01** | Discounts | [Quote 0Q0WC000003Fs1Z0AS (One-Time, list 50000, manual amount disc 5000, Qty 2)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fs1Z0AS/view) | Reprice TWICE (reprice, then reprice again) | Net Unit Price | Net Unit Price stays 45000 on BOTH reprices (50000 - 5000) | Net drops below 45000 on the 2nd reprice (40500, then lower) -> discount compounds |
| 6 | **I-03** | Proration | [QLI 0QLWC000002LCwH4AW (mid-term Term-Defined, ~270/365 of term)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view) | Reprice, open the line | Net Total Price / Total Line Amount | Prorated (~554.79 = 250 x 3 x 0.7397) | Full annual (750) -> fractional PTC derived but net not multiplied by it |
| 7 | **E-04** | Deal / Customer Type | [Quote 0Q0WC0000039bwH0AQ (Deal_Type = Fortra Originated, partner)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view) | Reprice, open the BoKS Perpetual line | Net Unit Price | Reflects the Non_Orig (Fortra-Originated) band -> different from the channel result | Net = 301.75 (=355 x 0.85, the CHANNEL 15% band) -> Deal_Type had no effect |
| 8 | **F-09** | Transaction Type | [Quote 0Q0WC000003AaoT0AS (EUR partner)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view) | Reprice, open the Cobalt Strike EUR line | Net Unit Price | ~4521.59 (EUR list x 0.82, single FX) | ~4159.87 (double FX: USD list x 0.92 x 0.82 x 0.9346) -> ~8% too low |
| 9 | **J-06** | Derived / Maintenance | [Quote 0Q0WC000003FdCD0A0, maint line QLI 0QLWC000003kmeE4AQ](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdCD0A0/view) | Reprice, open the maintenance line | Net Unit Price | 62.48 (=71 x 0.88, New-Maintenance 12% band) | 60.35 (=71 x 0.85, license Software 15% band carried onto maint) |
| 10 | **J-09** | Derived / Maintenance | [Quote 0Q0WC0000029Agw0AE, QLI 0QLWC000003KEbO4AW (GS-GSE-RNM-EF8)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view) | Reprice, open the line | Net Unit Price | A non-null, priced Net Unit Price | Net Unit Price = blank / $0 (derived PBE has no PBEDP contributor config) |
| 11 | **J-10** | Derived / Maintenance | [Quote 0Q0WC000003FZN70AO, EUR maint line QLI 0QLWC000003kinW4AQ](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZN70AO/view) | Reprice, open the EUR maintenance line | Net Unit Price | Committed, non-zero (COLA-derived net) | $0 (COLA value computed but not committed -> EUR PBE IsDerived=false) |
| 12 | **A-07** | Pricing Source / Channel | [A quote with a FIM CCM New-Maintenance line (vs the BoKS control 0Q0WC000003FKRJ0A4)](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view) | Reprice, open the FIM CCM maint line; also check the FIM CCM Product for the "Maintenance Type Defn" attribute | Net Unit Price + Product attribute | FIM CCM maint prices a non-zero derived tier (like BoKS 0.20 x list) | FIM CCM maint = $0 or 100%-of-list (product is missing the Maintenance Type Defn attribute) |
| 13 | **G-08** | Multi-Currency / Regional | [Setup -> Company Settings -> Manage Currencies (NOT a quote)](https://fortra--uat.sandbox.my.salesforce.com/lightning/setup/CurrencySettings/home) | Open Manage Currencies | Conversion Rate for ARS, CHF, GBP, ILS, JPY, NZD | Correct rates (ARS 666.6667, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667) | Any of them = 1.0 (placeholder) -> reporting/invoicing FX wrong (pricing proc itself unaffected) |

## Notes

- **G-08** and **A-07** are config/data, not a single reprice: G-08 = check Manage Currencies; A-07 = check whether the FIM CCM product carries the "Maintenance Type Defn" attribute (BoKS does, FIM CCM does not).

- **K-01 / F-12** pass = the reprice completes without error AND shows a negative credit / prorated negative delta; fail = the reprice throws an error.

- All record IDs are the run3 evidence records; if a record was changed/deleted since, tell me and I'll point you at a fresh one.
