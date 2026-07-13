I now have a complete, segmented picture. All queries are read-only aggregates. Here is my focused report.

---

# RENEWALS — UAT DATA SHAPE & BLAST RADIUS (FortraUAT, read-only, 2026-07-09)

## Headline numbers
- **124,718 renewal Quotes** (`Quote_Type__c='Renewal'`) — 80% of all quotes org-wide (next: New 31,208).
- **925,225 renewal QuoteLineItems** across 124,437 quotes; **486,583 (52.6%) are maintenance lines** (RRM 464,005 + RNM 22,578).
- **First-renewal maintenance defect exposure: 22,805 owned RNM assets across 1,041 accounts.** Of those accounts, **752 are "pure first-renewal" (hold RNM but zero RRM assets — never successfully renewed maintenance).**
- **Live defect materialized right now: 7,202 unpriced New-Maintenance/OneTime renewal lines across 1,774 quotes / 687 accounts**, all created 2026‑05‑04 → 2026‑06‑29 (RLM-generated, not legacy).

## CRITICAL METHODOLOGY NOTE — NetUnitPrice is runtime-only
The established-fact defect signal `NetUnitPrice=null` is **not measurable on persisted data**: `NetUnitPrice > 0` exists on only **9 QuoteLineItems org-wide** (7 Draft, 2 Accepted). It is a transient pricing-engine field cleared before save. `NetUnitPrice` is null on 463,996/464,005 RRM and 22,576/22,578 RNM renewal lines — i.e. null on ~everything, so it cannot segment the defect. **The persisted proxy is `UnitPrice` (Sales Price)**; a blank/`$0` UnitPrice on a maintenance renewal line is the durable defect signature (this is the SC-3544 "blank Sales Price" surface). All defect sizing below uses `UnitPrice`.
SOQL: `SELECT Quote.Status,COUNT(Id) FROM QuoteLineItem WHERE Quote.Quote_Type__c='Renewal' AND Fortra_Product_Type__c IN ('New Maintenance','Renewal Maintenance') AND NetUnitPrice>0 GROUP BY Quote.Status` → 9 rows total.

## 1. Renewal Quotes by Status
`SELECT Status,COUNT(Id) FROM Quote WHERE Quote_Type__c='Renewal' GROUP BY Status`
| Status | Quotes |
|---|---|
| Won | 71,885 |
| null | 26,606 |
| Draft | 15,147 |
| Approved | 10,341 |
| In Review | 715 |
| Accepted | 23 |
| Ordered | 1 |

Won (58%) is dominated by legacy-migrated history — material for the legacy-vs-live split below.

## 2. Renewal-quote line composition by Fortra_Product_Type__c
`SELECT Fortra_Product_Type__c,COUNT(Id) FROM QuoteLineItem WHERE Quote.Quote_Type__c='Renewal' GROUP BY Fortra_Product_Type__c`
| Product type | Lines |
|---|---|
| Renewal Maintenance (RRM) | 464,005 |
| Subscription | 253,652 |
| Perpetual | 108,468 |
| null | 73,509 |
| **New Maintenance (RNM)** | **22,578** |
| Services | 2,981 |
| Software / Other / Change Fee | 32 |

The presence of **22,578 RNM lines on renewal quotes is itself the defect signature** — on a correct renewal, maintenance should carry as RRM. These span **3,575 quotes / 1,200 accounts**.

## 3. Maintenance lines: type × selling model × price outcome
`... AND Fortra_Product_Type__c IN ('New Maintenance','Renewal Maintenance') GROUP BY Fortra_Product_Type__c, SellingModelType` (cross-tabbed with UnitPrice>0 / =0 / =null):

| Type | SellingModel | Total | UnitPrice>0 | UnitPrice=0 | UnitPrice=null |
|---|---|---|---|---|---|
| Renewal Maint | TermDefined | 452,429 | 331,998 | 120,009 | 105 |
| Renewal Maint | null | 11,570 | 7,072 | 4,498 | 0 |
| Renewal Maint | OneTime | 6 | 5 | 1 | 0 |
| **New Maint** | **OneTime** | **17,629** | **10,397** | **7,189** | **13** |
| New Maint | TermDefined | 4,943 | 3,891 | 1,008 | 0 |
| New Maint | null | 6 | 6 | 0 | 0 |

Key reads:
- **RRM is overwhelmingly TermDefined (452,429/464,005 = 97.5%)** → renewable, prices via native LastTransaction path (established fact). This is the healthy channel.
- **RNM is overwhelmingly OneTime (17,629/22,578 = 78%)** → not renewable → derived-pricing exclusion → 41% land at `$0`/null (7,202/17,629). This is the defect.

## 4. Legacy vs LIVE — the essential caveat
The two large `$0` maintenance populations have opposite provenance (segmented by Quote.Status):

**RRM TermDefined `$0` (120,009) is 98.9% legacy-migrated, NOT a live defect:**
| Status | Lines |
|---|---|
| Won | 118,759 |
| Draft | 1,057 |
| Approved | 189 |
| In Review / null | 4 |

→ Won `$0` = migration artifact (historical renewals loaded with no persisted UnitPrice). Live actionable RRM `$0` ≈ 1,250 only.

**RNM OneTime `$0`/null (7,202) is ~98% LIVE:**
`... AND Fortra_Product_Type__c='New Maintenance' AND SellingModelType='OneTime' AND (UnitPrice=0 OR UnitPrice=null) GROUP BY Quote.Status`
| Status | Lines |
|---|---|
| Approved | 3,836 |
| Draft | 3,225 |
| Won | 125 |
| In Review / null | 16 |

→ 7,061/7,202 (98%) are in actionable (non-Won) status; all created 2026‑05‑04→06‑29. **This is the active first-renewal maintenance defect.** (The whole RNM-OneTime population of 17,629 is likewise live — only 244 Won — so ~59% get priced somehow, e.g. reprice flow / manual / recent fix, and ~41% remain unpriced.)

## 5. First- vs subsequent-renewal exposure (asset-level)
Asset counts confirm established facts exactly (Product2 join == ProductCode `-RNM-`/`-RRM-` pattern):
`SELECT Product2.Fortra_Product_Type__c,COUNT(Id),COUNT_DISTINCT(AccountId) FROM Asset GROUP BY ...`
| Asset maintenance type | Assets | Accounts |
|---|---|---|
| Renewal Maintenance (RRM) | 91,354 | 1,467 |
| New Maintenance (RNM) | 22,805 | 1,041 |

Account set algebra (distinct AccountId sets diffed locally):
- **752 accounts hold RNM but NO RRM** → pure first-renewal exposure (never renewed maintenance; their first renewal hits the defect).
- **289 accounts hold both** → mixed (some maintenance renewed to RRM, but remaining RNM assets still hit the defect on their own first renewal).
- 1,178 accounts are RRM-only → already through ≥1 renewal; native exact `Asset.Product2Id = line.Product2Id` match works.

**Total addressable first-renewal defect exposure = 22,805 assets / 1,041 accounts.** Currently materialized on quotes = 687 accounts (subset that has generated a renewal quote). Defect core is 99% USD (7,125/7,202; EUR 66, GBP 7, AUD 4).

## 6. Currency distribution (renewal maintenance lines)
`... GROUP BY CurrencyIsoCode`: USD 456,848 (93.9%), EUR 13,053, AUD 8,002, GBP 7,437, CAD 1,017, JPY 186, NZD 40. Renewal quotes overall: USD 106,449 / EUR 8,246 / CAD 3,450 / GBP 3,140 / AUD 1,725 / JPY 1,504 / CHF 168 / NZD 36. Non-USD ≈ 6% — small but the population where the multi-currency pricing defects (SC-3384) compound with the maintenance defect.

## 7. QuoteAction (renewal action type) — ephemeral, not a reliable census
`SELECT Type,COUNT(Id) FROM QuoteAction` → only **305 records org-wide** (they are transient, deleted after quote calc). On renewal quotes at this instant: Renew 102, No Change 18, Amend 14, Add 2 (Subtype all null). This confirms the established mechanism qualitatively (Renew dominates when it works; Amend is the mis-route) but **cannot be used to size the defect** — the durable persisted signal is the RNM-line + `$0 UnitPrice` combination in §3–4. `QuoteLineItem.QuoteActionId` points at these ephemeral rows so it is also not a reliable historical join.

## 8. Contracts & Opportunities
Contract (29,475 total; 29,452 Activated, 23 Draft):
- `Renewal_Status__c`: null 28,295 / **Pending 1,173** / Accepted 7 — i.e. the field is populated on <4% of contracts; renewal state is not tracked on Contract in practice.
- `Renewal_Type__c`: Direct 29,474 (essentially universal); `Auto_Renew__c` and `IsRenewalProcessEnabled` exist but renewal is driven by the custom flow, not native contract renewal.

Renewal Opportunities: `SELECT Type,COUNT(Id) FROM Opportunity` → **Renewal 11,632** (vs New 10,555, Upsell 3,910, null 99,966). By stage: Closed Won 11,523 (99%), open pipeline ~95 (Renewal Forecast 63, Pricing & Approval 11, Order Processing 7, others). Opportunity carries `Expected_Renewal_Amount__c` / `RenewalForecastAmount`-style forecast fields (ties to SC-3500).

## Re-architecture scope implications (from the numbers)
1. **Maintenance is 52.6% of all renewal line volume** — any re-architecture of renewals is primarily a re-architecture of maintenance pricing.
2. **The two-catalog RNM/RRM design is the defect root at data scale**: 22,805 OneTime RNM assets (1,041 accounts) can never renew natively; every first renewal mis-routes. 752 accounts have *only* RNM assets and have never been rescued by the subsequent-renewal native exact-match.
3. **~41% first-pass failure rate** on live RNM-OneTime renewal lines (7,202/17,629) — the fix (synthesize Renew QuoteAction, RNM→RRM by account|Solution_Category__c) must retire the two-catalog split or the exposure regenerates on every future first renewal.
4. **Do not conflate the 120K RRM `$0` with the defect** — 98.9% is legacy-migration noise (Won, no persisted UnitPrice); live actionable RRM `$0` is only ~1,250. The genuinely-live maintenance-pricing gap is the 7,202 RNM-OneTime lines.
5. **`NetUnitPrice` is not a persisted metric** — any monitoring/telemetry for the re-architecture must instrument `UnitPrice` (post-persist), consistent with the SC-3544 stamp approach.

Scratchpad account-set files: `/private/tmp/claude-501/-Users-liamjeong-Documents-Code-Fortra/1a1c15cd-2cb9-4780-8bf3-c7c97523dce3/scratchpad/rnm_accts.txt` and `rrm_accts.txt`.