# SC-3384 — Live re-verification of the 6 blockers (FortraUAT, 2026-06-11, read-only)

All read-only queries; no DML/reprice performed. These confirm the build gates B1–B6.

## B1 — AA line is NOT live engine output
`QuoteLineItem 0QLWC000003cBGr4AM`: CurrencyIsoCode=**EUR**, **Has_Attribute_Adjustment__c=false**, UnitPrice=3150, NetUnitPrice=1575, ListPrice=2898, TotalPrice=1575, Quantity=1, **CreatedDate=2026-06-09** (the QLI itself; the *ABA data* it mirrors is the 2026-03-24/2026-05-06 migration set — see B2). Flag=false ⇒ the attribute-adjustment path did not fire live on this line; 3150/1575 are stored values to be re-grounded by a fresh reprice.

## B2 — 3150 and 1575 are two different rows / two different steps
`AttributeBasedAdjustment WHERE ProductId='01tWC00000DD11YYAT'` → **3 rows, all USD, all Override**:
| Name | Value | Currency | EffectiveFrom | EffectiveTo | Hash | Created |
|---|---|---|---|---|---|---|
| 00000220 | **1575** | USD | 2025-11-14 | null (active) | `9da979e8…` | 2026-03-24 |
| 00000219 | 3150 | USD | 2025-11-14 | **2026-06-01 (expired)** | `adf67826…` | 2026-03-24 |
| 00022777 | **3150** | USD | 2026-06-01 | null (active) | `adf67826…` | 2026-06-08 |
Two **active** rows have **different hashes** (`9da979…`=1575, `adf678…`=3150) ⇒ mutually-exclusive attribute combos ⇒ one line/one step cannot produce both. 219 (expired) shares 22777's hash. Reconciles the SC-3360 "2 rows" vs SC-3384 "3 rows" (3 exist; 1 expired). Seeding a EUR row with the same hash + overlapping dates and no currency key would collide with 22777 → confirms "unsafe seeding without a currency key."

## B3 — active procedure = V13 (verified via SC-3346 work + SC-3393 V130 retrieve)
Active `Rev_Mgmt_Default_Pricing_Procedure` = **V13** (the SC-3393 RegionalNetReconcileGate null-guard). Context def `SalesTransactionContextExt_v2`. Moved V9→V12→V13 within days — always pull live.

## B4 — phantom matrix vs the real one (grep of the live V13 retrieve `…V130.expressionSetVersion`)
| Decision table | Appears in V13 | Meaning |
|---|---|---|
| `0lDa50000007BEuEAM` (Attribute Based Adjustment) | **2×** | the ABA table the procedure actually uses — currency key goes HERE |
| `0lDWC0000000Gft2AE` (Attribute Tier Pricing **Matrix**) | **0×** | PHANTOM — not referenced; editing it is a no-op (attr-tier is Apex+data only) |
| `0lDa50000007BEsEAM` (volume-tier) | 1× | a 2nd absolute-value table; candidate source of BESEPB 824 — add to audit |
| `0lDa50000007BErEAM` (PriceBookEntry) | 1× | the currency-keyed list path (why EUR list is correct) |

## B5 — item currency tag = STICurrencyIsoCode (context def, lines)
`SalesTransactionContextExt_v2.contextDefinition`: header node `CurrencyIsoCode` (line 60-61); **item node `STICurrencyIsoCode`** (line 903-905, inherited from `…/SalesTransactionItem/STICurrencyIsoCode`). The prehook must read `STICurrencyIsoCode`; bare `CurrencyIsoCode` is header-only → captures null on a line.

## B6 — CLSAAS Net=0 + EUR PBE exists
`QLI 0QLWC000003cE8H4AU` (EUR): List=**2005.6** (EUR, correct), Unit=Base_Price__c=**1357.2** (USD tier value), **Net=Total=0**. EUR PBE `01uWC000005wyVjYAI`: EUR, 2005.6, Product `01tWC00000DD17PYAT`, Book `01sWC0000022GHFYA2` → EUR PBE EXISTS; the line still grabs the USD tier and drops Net to 0.

## Data census
`AttributeBasedAdjustment GROUP BY CurrencyIsoCode` → **USD 13,072 / non-USD 0** (100% USD). `Attribute_Tier_Pricing_Storage__c` = 1,115 rows 100% USD (prior census). Filling the currency key without seeding EUR data would zero/reset EUR lines (B6 sequencing).
