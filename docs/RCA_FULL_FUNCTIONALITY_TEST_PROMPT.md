# RCA Full-Functionality Testing Prompt — FortraUAT · **CLI / Claude Code** (real-data, end-to-end)

> **Paste everything below the line into a fresh agent/tester session.** It drives an end-to-end validation
> of the entire Fortra Revenue Cloud Advanced (RCA) pricing + quote-to-cash engine against **real FortraUAT
> records** — using the **Salesforce CLI (`sf`) + SOQL** (agent as read-only oracle) — and delivers the outcome
> as a **high-visibility HTML + JSX report** (§9), color-coded **PASS / FAIL / BLOCKED**.

> **This is the CLI half of a pair.** For **manual E2E on the Salesforce Lightning UI** (Claude Chrome Extension —
> clicking Manage Assets → Renew/Amend/Cancel, the Transaction Line Editor, Reprice All, Convert Quote to Order,
> reading on-screen prices, screenshot evidence), use the companion
> [`docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md`](RCA_UI_MANUAL_E2E_TEST_PROMPT.md). Same engine, tickets, and acceptance.

> **PRIORITY THIS RUN — assigned-ticket status board (as of 2026-07-11).** Alongside the standing regression
> suite, deep-test every ticket in **§T** against its **live-verified** record and acceptance. Each is a **§9
> report row** (id `SC-####`). **Legend:** ✅ FIXED (regression-guard — must not re-break) · 🟢 RESOLVED /
> not-reproduced (guard) · 🟡 PARTIAL / has-regression · 🔴 OPEN · ⬜ spec pending. **`(org✓/git✗)`** = the fix is
> live in FortraUAT but **git-uncommitted** — a clean checkout of `main`/HEAD still reproduces the defect.

| Ticket | Area | Verdict | Current state (2026-07-11) |
|---|---|---|---|
| **SC-3346-ABP** | derived · partner ABP base | ✅ FIXED `185a670` | partner path no longer clobbers the ABP base — gates off `Source_List_Price__c`; JzHN 20k→17k, maint 4k→3.4k |
| **SC-3346** new-biz | derived new-maint | ✅ FIXED `185a670` | maint = source Base×tier, discount-immune (S1 20k→4k) |
| **SC-3346-MTD** | attribute-less new-maint | 🔴 OPEN | auto-add omits `Maintenance Type Defn` → tier 0 → **$0**; spec approved, impl **deferred** |
| **SC-3346-DEDUPE** | amend-carryover maint dup | ✅ FIXED `(org✓/git✗)` | `NewMaintenanceDedupeService` leaves one keeper per license |
| **SC-3346** renewal | renewal derived-maint | 🟢 not-repro | Path B born-net; the V14→V23 "priced-node wall" theory is **CLOSED** on the current proc |
| **SC-3346-QTYFOLD** | renewal COLA qty>1 | 🟡 `(org✓/git✗)` | COLA used extended `Asset.Price` as per-unit → qty× inflation; ÷qty fix deployed; **1 line escaped to Workday (00095510)** |
| **SC-3350** | renewal COLA at list / blank desc | 🟢 not-repro | COLA applied + descriptions present (`41b5622`) |
| **SC-3354** | COLA-renewal rework (parent of 3350) | 🟡 yr-1 ✅ · multi-yr 🔴 | year-1 defects resolved; multi-year out-year compounding still **inert** (scope fork open) |
| **SC-3384** | non-USD priced from USD (investigation) | 🟡 PARTIAL | committed sub-fixes below; the currency-aware-data path is **superseded by SC-3398** |
| **SC-3384-E** | auto-add maint PBE currency | ✅ FIXED `43fa4d1` | before-insert re-points mis-currencied PBE to same-currency sibling |
| **SC-3384-CTX** | context hydration re-sync | 🔴 OPEN | `SalesTransactionContextExt_v2` edited but not re-synced → live "went wrong hydrating the context" UI error |
| **SC-3398** | non-USD net = USD×rate (the chosen fix) | 🔴 OPEN | conversion-based approach; net=0 fix + rate table delivered, **core conversion step (Phase 3) pending**; reverts SC-3384 currency-matching |
| **SC-3501** | amendment qty → reprice | 🟡 `(org✓/git✗)` | per-unit carry works; qty-10 10× inflation fixed live (÷ asset qty) but **uncommitted** — HEAD still inflates |
| **SC-3502** | renewal Opp generation | 🟢 not-repro | Opp auto-generated (`Renewed_Contract__c`); distinct from SC-3500 (Amount ✅) |
| **SC-3544** | Sales Price blank on renewal/amend | ✅ FIXED `88c626f` | post-persist Apex stamp fills `UnitPrice`=Net (fill-only) |
| **SC-3505** | Workday amend original-contract ID | 🔴 PARKED | amend payload still carries own `Order.Id` only; **no code fix** (`5f21481` = docs) |
| **SC-3513** | Asset.Description re-derive | ✅ FIXED `47cb089` | re-derives on create + all 8 product-change events |
| **SC-3503** | contract cancellation fails | 🔴 OPEN | cancellation errors on a pricing **"Stamp Base Filter 1"** fault → cannot complete (6/29 demo, Marc; Critical); same procedure element as SC-3346-ABP |

> Each ticket's binding + acceptance is in **§T**; dated history is in the **CHANGELOG** (reset 2026-07-11).

## CHANGELOG
*History reset 2026-07-11 — newest first. Add one dated line per material change; keep §T as **current-state**, not archaeology.*

- **2026-07-11** — Full modernization. Status board + changelog established (prior inline "SUPERSEDES…/★ RESOLUTION" narrative cleared). Refreshed to the sole-active procedure **V25** (confirmed 2026-07-11). Fixtures **53→63** (added `setupJ03DerivedRenewalResetTestData` J-03, the 8-script SC-3346 **Path B** family, and the `create*LJsCompany` walkthrough helpers). SC-3346-ABP fixed + committed (`185a670`); SC-3501 & SC-3346-QTYFOLD qty-inflation fixes live-validated but **git-uncommitted**; SC-3384 split into runtime sub-fixes (E ✅ / CTX 🔴) with its currency-data path **superseded by SC-3398** (conversion-based, core step pending); added **SC-3354**, **SC-3398**, **SC-3505**, **SC-3513**, **SC-3503**; added the **Manage-Assets quote-creation** and **Convert-parity** lifecycle lanes (§6); split the prompt into a **CLI** and a **UI Manual E2E** (Chrome Extension) companion.

---

## ROLE & MISSION
You are an **RCA QA agent** validating the live Fortra Revenue Cloud Advanced engine on Salesforce org
**FortraUAT**. Exercise **as many scenarios as possible** across pricing and the full quote-to-cash
lifecycle, using **real UAT data only**, and produce a defect-grade report. Do not fabricate data; do not
change configuration. **Authorized writes** = the **reprices / converts / activations** the pricing/lifecycle
steps tell you to run; **for the lifecycle themes (§6)** — **creating a quote from a Contract's *Manage Assets* tab
via the Renew / Amend / Cancel actions** (§6A) and **converting a Quote to an Order via the "Convert Quote to
Order" quick action** (§6.3), then **Reprice All** on each; **for the §T ticket tests** — a **quantity edit on an
amendment line** (SC-3501), **generating a platform renewal from a contract** (SC-3346-renewal / SC-3350 /
SC-3502), a **tier-picklist edit on a maintenance line** (SC-3346), and **exercising a contract cancellation**
(SC-3503); and **for any scenario lacking real data** — running the
**`scripts/apex/` fixture setup scripts (§4B)** to mint real UAT records (each is **savepoint-protected** — it
rolls back on any error) plus the **headless renewal-generation** invocable (`Fortra_Create_Renewal_Quote` /
`initiateRenewal`) those scripts use, and adding **QuoteLineItemAttribute** rows via REST for attribute/derived
fixtures. Nothing else — no config/metadata changes, no Workday publishes unless a step explicitly says so.

## GROUND RULES
1. **Org:** `FortraUAT` (all `sf` commands use `-o FortraUAT`). Read-mostly.
2. **Real data only.** Use the bound scenario quotes in §3, or the SOQL in §4 to find a real record for any
   scenario not pre-bound. If none exists, **mint one with the §4B Apex fixtures** (savepoint-protected — they
   create real UAT records, not fakes). Only mark **BLOCKED (no data)** if neither a real record nor a fixture
   exists — never invent one.
3. **Reprice is the core action.** Repricing is idempotent by design: **run every priced scenario TWICE and
   assert first-click == second-click** (the SC-3390 idempotency guarantee).
4. **The oracle** is the per-line snapshot in §2. Capture it **before and after** each reprice and diff.
5. **After every reprice, check the D-18 exception log** (§7.4): a new `Exception_Log__c` row means a pricing
   hook silently swallowed an error — that is a FAIL to investigate, even if the price looks right.
6. **Deliver the outcome as a self-contained HTML + JSX report** (§9) — high-visibility, color-coded
   PASS/FAIL/BLOCKED, click-to-expand evidence — **not** a plain markdown table. Populate the provided
   template with real evidence (actual field values).

## §1 — THE PRICING WATERFALL (what you are validating)
A reprice runs the sole-active `Rev_Mgmt_Default_Pricing_Procedure` **V25** (confirmed 2026-07-11; to re-verify,
query **`ExpressionSetDefinitionVersion`** filtered by the ExpressionSetDefinition — **not** `ExpressionSetVersion`,
which is unsupported in this org — or Setup → Pricing Procedures → Versions) + Apex hooks in this order. Each stage
writes specific fields — know which stage owns which number.
**⚠️ Only native "Reprice All"** (Transaction Line Editor / managed place-action) fires the RevSignaling **plan
prehooks**; the headless `Fortra_Quote_Reprice` flow **bypasses the plan** (used only by the legacy migration
batch, 0 UAT runs), so plan-prehook effects (amend net-carry, etc.) read **$0 / stale** on a headless reprice —
a false FAIL. Test plan-prehook lines with **native** reprice.

| Order | Stage | Sets / does |
|---|---|---|
| 1 | **List Price** (native `ListPrice` → `Price_Book_Entry_Decision_Table_v2`, currency-keyed) | `ListPrice`, `Base_Price__c` from the per-currency PricebookEntry — **list stays NATIVE, never FX-converted** |
| 2 | **HardwareAttributePricingPrehook** | Hardware price = `ListPrice × pGroup × userTier × (1 − systemType%)` |
| 3 | **RegionalServicesPricingPrehook** | country multiplier on the **LIST** channel only (`RegionalNetUnitPrice__c`) |
| 4 | **PartnerPricingPrehookV2** | partner Discount / Guaranteed-Margin on non-derived lines (`Pre_Partner_Price__c`, `PartnerDiscountPercent`) |
| 5 | **AttributeVolumePricingPrehook** | attribute/volume tier price (`Base_Price__c` via Net Bridge). Tier lookup was made currency-aware (`255f7c5`) but that data-match path is being **reverted by SC-3398** (USD tiers for all currencies + a late conversion step) |
| 6 | **COLAUpliftPrehook** | renewal COLA (`COLACalculatedPrice__c`, `COLA_Uplift_Percent__c`, `COLA_Source__c`); carries prior per-unit net = `SourceAsset.Price ÷ SourceAsset.Quantity` (SC-3346-QTYFOLD) |
| 7 | **AmendNetCarryPrehook** | amend lines: seed prior per-unit net = `SourceAsset.Price ÷ SourceAsset.Quantity` + recompute `NetTotal = net × current qty` (SC-3501; **sole** amend-carry — the procedure's Amend group was removed). Plan pos 6; native reprice only |
| 8 | **ESD procedure steps** | subscription/proration → derived-maint → aggregation (zero-init before aggregates). **SC-3398 (proposed): one late step multiplies the USD-computed net × `Currency_Conversion_Formula__mdt` rate → local-currency net** (USD/blank → ×1.0) |
| 9 | **PartnerNetPricePosthook** | applies partner net to `NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount`; deferred (derived-maint) partner pricing; **deal-aware (D-11)**; ABA currency-localization (`185a670`) |
| 10 | **QLDescriptionGeneratorPrehook** | line description (registered LAST in the prehook chain) |
| 11 | **CancelLineCreditPosthook** | negative-qty credit lines (`CancelNetUnitPrice__c`) |
| 12 | **Sales-Price stamp** (`QuotePriceStampQueueable`, post-persist Apex) | fills blank `UnitPrice = Net` **fill-only** (SC-3544); runs async after the reprice, never overwrites an existing UnitPrice |

## §2 — REPRICE + SNAPSHOT MECHANICS (exact commands)
**Reprice a Quote:**
```
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" \
  --method POST --body '{"inputs":[{"QuoteId":"<QUOTE_ID>"}]}' -o FortraUAT
```
Assert the response has `"isSuccess": true` (the CLI prepends warning lines — parse from the first `[`).

**Snapshot the oracle fields (read-only)** — capture before AND after:
```
sf data query -o FortraUAT -q "SELECT LineNumber, Product2.Name, Fortra_Product_Type__c, Quantity, \
UnitPrice, ListPrice, Base_Price__c, NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount, \
PricingTerm, PricingTermCount, PricingTermUnit, StartDate, EndDate, \
Pre_Partner_Price__c, PrehookRSNetUnitPrice__c, PartnerDiscountPercent, Partner_Discount_Percent__c, \
COLACalculatedPrice__c, COLA_Uplift_Percent__c, CancelNetUnitPrice__c \
FROM QuoteLineItem WHERE QuoteId='<QUOTE_ID>' ORDER BY LineNumber"
```
(There's also a ready-made harness: `ORG=FortraUAT Data/pricing-refactor-scratch/harness/snapshot.sh Quote <id> out.tsv`,
then `python3 Data/pricing-refactor-scratch/harness/diff.py baseline.tsv out.tsv` → `GATE PASS — 0 delta`.)

**Order reprice:** flow `Fortra_Order_Reprice` (same shape, `OrderId`). **Convert Quote→Order:** flow
`Fortra_Quote_to_Order_Conversion`. **Order snapshot:** `snapshot.sh Order <orderId>` (Order uses
`RegionalNetUnitPrice__c` + `Workday_Contract_Line_Type__c`).

## §3 — REAL UAT SCENARIO BINDINGS (the backbone — these are live quotes)
| S# | Real Quote Id | Covers | Known reference |
|---|---|---|---|
| S1 | `0Q0WC000003IIT0` | New USD baseline, one-time (6 lines) | nullPTC×2 ok on one-time |
| S2 | `0Q0WC000003GMu5` | term subscription | has `PricingTermCount=1` |
| S3 | `0Q0WC000003IKkv` | renewal COLA | COLA applied (S3 carries a known SC-3346 qty0→$0 line — expected) |
| S4 | `0Q0WC0000028bsk` | derived / new maintenance (18 lines, 17 New-Maint) | nullPTC correct for maint |
| S5 | `0Q0WC000003IKeT` | **partner Discount** (Channel-Originated, 18%) | |
| S6 | `0Q0WC0000035dGj` | **partner Guaranteed-Margin** (Reseller+Distributor, GM 28%) | 824 → **593.28** |
| S7 | `0Q0WC0000039bwH` | **Fortra-Originated, Non_Orig POPULATED** | Non_Orig 12%: 355 → **312.40** |
| S9 | `0Q0WC000003Fr77` | regional EUR | 1 regional line |
| S10 | `0Q0WC000003ICoz` | non-USD (GBP) | |
| S11 | `0Q0WC000003GMu5` | attribute-tier (Has_Attribute_Adjustment) | idempotent (SC-3390) |
| S11b | `0Q0WC000003FcrF` | EUR multi-currency | USD-base × hardcoded 0.9346 FX |
| S12 | `0Q0WC000002RK6g` | **hardware / Power** (23 lines, maxQty 20) | |
| S13 | `0Q0WC000003FapR` | **cancel / amend-remove** credit | negQty −50000 credit line |
| S14 | `0Q0WC0000028HhT` | **governor** (73 lines, 29 nullPTC) | SC-3366 stress |
| S8 | *(mint via §4B)* | Fortra-Originated with Non_Orig **NULL** | no longer hard-BLOCKED: `setupE08PartnerNullPercentTestData` covers the null-percent→**net=list** branch; for the exact Fortra-Orig combo, script a variant from the `setupDirectFortraOriginatedQuoteTestData` (E-01) pattern |

**Assigned-ticket bindings (live records for the §T deep tests — re-verify each at preflight with §4's SOQL; the org drifts):**

| Ticket | Real record(s) | Covers | Current state (2026-07-11) |
|---|---|---|---|
| **SC-3346-ABP** | Quote `0Q0WC000003JzHN` (New, USD, partner Discount 15%); non-partner control **S1** `0Q0WC000003IIT0` | Net-New DPP + ABP base-stamp | ✅ **FIXED** `185a670` — JzHN `Source_List_Price__c`=20000 → perpetual **20000→17000** (−15%), maint **4000→3400**; S1 (no partner) 20000 / 4000 |
| **SC-3346** renewal / QTYFOLD | BoKS contract 00069410 (`800WC00000Sy0Rf`); proven renewal quotes 00781793/94; **escaped Workday order 00095510** (ES-SEG qty100) | renewal derived-maint + qty-fold | renewal derives via Path B (71×1.0785=**76.57**); QTYFOLD ÷qty fix deployed `(org✓/git✗)`; fix order 00095510 |
| **SC-3346-MTD** | Quote `0Q0WC000003JXMj` (line 04267561 Device Profiler qty1, no `Maintenance Type Defn` QLIA = $0) | attribute-less new-maint $0 | 🔴 **OPEN** — auto-add omits the tier attribute |
| **SC-3350 / SC-3354** | Quote `0Q0WC000003Ibx3` (Renewal, Draft); also `Ibqb`/`IbnN`/`2ljtN` | renewal COLA at list / blank desc | 🟢 **not-repro** (COLA applied + desc present); SC-3354 multi-year out-year compounding still **inert** 🔴 |
| **SC-3384 / SC-3398** | EUR quote `0Q0WC0000036xy9` ("Q-Wren Test Currencies"); CAD `0Q0WC000003ASz1` | non-USD net priced from USD | SC-3398 target: net = **USD net × currency rate** (EUR 0.9346), **list native**; core conversion step 🔴 **pending** |
| **SC-3501** | Cypress contract 00069475 (`800WC00000TWqUD`, Activated) → **fresh amend** on a qty-10 asset (EFT 7 Enterprise 273540/10=**27354**/u); healed baseline quote `0Q0WC000003KLsz` (total 156,819.99) | amend qty → per-unit carry | 🟡 **fixed live** `(org✓/git✗)` — per-unit ÷ asset qty; HEAD still 10× inflates |
| **SC-3502** | Contract `800WC00000TNpyn` (00069451, Activated); also `TNjN7`/`TNBRw` | renewal-opp generation | 🟢 **not-repro** — Opp auto-generated (distinct from SC-3500 Amount ✅) |
| **SC-3503** | *no bound record (6/29 demo, Marc)* — mint a cancel via §4B `setupCancelOrderTestData` / `setupCancelQuoteTestData`, or drive **Contract → Cancel** on an activated contract | contract cancellation fails | 🔴 **OPEN** — "**Stamp Base Filter 1**" fault blocks cancel |
| **SC-3544** | Quote `0Q0WC000003Ifvp` (Renewal); new-biz control `0Q0WC000003Ih3B` | Sales Price blank on renewal/amend | ✅ **FIXED** `88c626f` — `UnitPrice` **4573.80 / 918.75 = Net** (fill-only; new-biz 2021.25 unchanged) |
| **SC-3505** | Amend orders 00095512 / 00095642 (payloads carry own `Order.Id` only); native amends 00095531 / 00095676 | Workday amend original-contract ID | 🔴 **PARKED** — no code fix (`5f21481` = docs) |
| **SC-3513** | *needs a real Upgrade/Downgrade **AssetAction** on a stamped asset*; backfill dry-run `Data/sc3513/backfill_16.apex` | Asset.Description re-derive | ✅ **FIXED** `47cb089` — 8 product-change categories |

> Verify each Id still exists + is repriceable before use:
> `sf data query -o FortraUAT -q "SELECT Id, Name, Status, CurrencyIsoCode FROM Quote WHERE Id='<id>'"`.
> If an Id is stale, use §4 to find a fresh real record of the same type.

## §4 — SOQL TO FIND REAL RECORDS (for any scenario not pre-bound)
Run these against FortraUAT to pull a **real** record; pick one in a workable (Draft/editable) status:
```
-- Partner Discount quote:            SELECT Id,Name FROM Quote WHERE Partner_Pricing_Model__c='Discount' AND Billing_Partner__c!=null ORDER BY LastModifiedDate DESC LIMIT 5
-- Partner Guaranteed-Margin quote:   SELECT Id,Name FROM Quote WHERE Partner_Pricing_Model__c='Guaranteed Margin' AND Billing_Partner__c!=null ORDER BY LastModifiedDate DESC LIMIT 5
-- Fortra-Originated deal:            SELECT Id,Name,Deal_Type__c FROM Quote WHERE Deal_Type__c='Fortra Originated' ORDER BY LastModifiedDate DESC LIMIT 5
-- EUR / GBP quote:                   SELECT Id,Name,CurrencyIsoCode FROM Quote WHERE CurrencyIsoCode IN ('EUR','GBP','CHF','JPY','AUD') ORDER BY LastModifiedDate DESC LIMIT 10
-- Renewal quote:                     SELECT Id,Name FROM Quote WHERE Type__c LIKE '%Renewal%' OR RecordType.Name LIKE '%Renewal%' ORDER BY LastModifiedDate DESC LIMIT 5
-- Hardware/Power lines:              SELECT QuoteId FROM QuoteLineItem WHERE Fortra_Product_Type__c IN ('Hardware') OR Product2.Family='Hardware' GROUP BY QuoteId LIMIT 5
-- Cancel/amend (negative qty):       SELECT QuoteId FROM QuoteLineItem WHERE Quantity<0 GROUP BY QuoteId LIMIT 5
-- Activated Order w/ Assets:         SELECT Id,OrderNumber,Status FROM Order WHERE Status='Activated' ORDER BY ActivatedDate DESC LIMIT 5
-- Multi-line (governor):             SELECT QuoteId, COUNT(Id) c FROM QuoteLineItem GROUP BY QuoteId HAVING COUNT(Id)>=15 LIMIT 5
```

## §4B — SCENARIO DATA SETUP (mint real records with the `scripts/apex` Apex fixtures)
When §3/§4 turn up **no** repriceable real record, don't stop at BLOCKED — **mint one** with the matching Apex
fixture in `scripts/apex/`. These are the project's own **savepoint-protected** setup scripts (they roll back
on any error) that insert **real UAT records** and print the created Id + the expected oracle. There are **63
scripts** in `scripts/apex/` (48 `.compact.apex` fixtures + 15 targeted/renewal/Path-B scripts) covering nearly
every §5 letter and ticket.

**Run a fixture:** `sf apex run --target-org FortraUAT -f scripts/apex/<script>` (compact scripts end `.compact.apex`).
**Capture the record:** grep the run log (ERROR level) for the `✅ <CODE>-FIXTURE CREATED` marker — it prints
`QuoteId=<id>` (or `quoteId=`/`QUOTEID=`/`OrderId:`), a clickable Lightning URL, and the QLI/line ids. Then treat
it like any §3 binding: **Force-reprice (§2) ×2 → snapshot → grade.**
**Read the oracle off the script.** Each fixture's debug block prints its own **EXPECTED post-reprice** net and
the **DEFECT signatures** (e.g. G-01 prints `EXPECT NetUnitPrice=19159.30 (EUR list)` + `DEFECT: USD-leak Net=20500`).
Use those as the per-scenario Expected — the numbers are authoritative.

**Four caveats:**
- **Pre-reprice:** fixtures insert but do NOT reprice — reprice before reading the final net.
- **Attribute rows via REST:** for derived/attribute (D / J / K-derived) fixtures, add the `QuoteLineItemAttribute`
  rows (e.g. "Maintenance Type = Standard") via REST **after** the run (Apex DML is rejected on the managed QLIA
  sObject), then reprice.
- **Renewal-generation scripts** (`f04_initiateRenewal`, `sc3346_confirm_rnm_renewal`) invoke the renewal flow
  against **pre-existing** contract/assets — run **`setupSC3502Lineage`** first to build a fresh activated
  contract + asset, then renew. This is the fixture path for the "most faithful" SC-3350 / SC-3346-renewal tests.
- **Empty-repro scripts** (`setupHrmClsaasEurRepro`, `setupPiambkAutoAddEurRepro`) create an **empty** EUR quote
  on purpose — add the SKU in the UI Transaction Line Editor to fire the SC-3384 defect.

**Fixture map (script → scenario/ticket → creates + expected). Run `sf apex run -f scripts/apex/<script>`:**

*Pricing source / selling model / COLA:*
| Script | Code | Creates + expected |
|---|---|---|
| `setupCatalogListPriceTestData.compact.apex` | A-01 | USD Cobalt line off catalog PBE → net = list 20500 |
| `setupCarryForwardLastTxnTestData.compact.apex` | A-02 | amend on beSECURE asset → net carries prior **6695.30**, not catalog 0 |
| `setupB01OneTimePtcTestData.compact.apex` | B-01 | one-time Perpetual Qty=2 → PTC=1, 2200×2×1=**4400** |
| `setupOneTimeNoProrationTestData.compact.apex` | B-08 | one-time Qty=3 → excluded from both proration filters |
| `setupTieredSubQuoteTestData.compact.apex` | B-03 | TermDefined tiered attribute sub line (add QLIA via REST) |
| `setupColaUatTestData.compact.apex` | C | COLA/DPP fixture quote (fresh Contact→Place) |
| `setupAddOnGroupedTestData.compact.apex` | C-06 | GoAnywhere base + add-on → add-on nets own list (no bundle override) |

*Attribute / GSA / partner:*
| Script | Code | Creates + expected |
|---|---|---|
| `setupAttrServerTypeTestData.compact.apex` | D-03 / SC-3360 | 3 AAMP lines, 3-attr ABA key → L1=3150 (no match), L3=**1575** (ABA fires) |
| `setupD03IsolatedTestData.compact.apex` | D-03 | 3 single-line AAMP quotes (isolate ABA from multi-line $0 collapse) |
| `setupContractAttrPriceTestData.compact.apex` | D-06 | contracted vs catalog AAMP lines (CONTRACTED AttributeBasedPrice branch) |
| `setupAttrCalcQuoteTestData.compact.apex` | D-01 | Calculated attribute pricing (Base_Price__c / AttributeMultiplierPct__c) |
| `setupGsaPricingTestData.compact.apex` | D-04 | GSW=true → list×0.5 vs GSW=false control |
| `setupDirectFortraOriginatedQuoteTestData.compact.apex` | E-01 | Fortra-Originated, **no partner** (control — no discount) |
| `setupE02PartnerDiscountTestData.compact.apex` | E-02 | Channel Discount partner, Cobalt → net **17425** (15%) |
| `setupPartnerOneTimeQuoteTestData.compact.apex` | E-03 / SC-3359 | partner OneTime CCM → 2008×0.85=**1706.8** (partner% not lost on one-time) |
| `setupE06GsaPartnerCrossTestData.compact.apex` | E-06 | GSA×partner → GSA-only 10250 / partner-only 17425 / stacked **8712.5** |
| `setupE08PartnerNullPercentTestData.compact.apex` | E-08 | NEG (null pct) → net **2400=list**; POS (18%) → 1968 |

*Currency / regional / manual discount:*
| Script | Code | Creates + expected |
|---|---|---|
| `setupCurrencyEurCatalogTestData.compact.apex` | G-01 | EUR Cobalt → net **19159.30** (EUR list); DEFECT USD-leak 20500 / double-FX 17906 |
| `setupG02CurrencyAbaTestData.compact.apex` | G-02 / SC-3384 | EUR AAMP, ABA table is 100% USD → DEFECT if net=1575 (USD leak) |
| `setupG03PartnerNonUsdTestData.compact.apex` | G-03 | EUR partner Software → 100000×0.9346×0.85=**79441** |
| `setupG03PartnerNonUsdOneTimeTestData.compact.apex` | G-03 clean | same, OneTime (isolates partner×FX from PTC) → **79441** |
| `setupG07RegionalEurTestData.compact.apex` | G-07 | EUR Italy (×0.64) services → LIST 32900 EUR, NET 51403 (no double-FX) |
| `setupRegionalServicesTestData.compact.apex` | G-04 | Italy services → RegionalServicesPrehook writes LIST channel only; net = catalog |
| `setupH01ManualAmountDiscountTestData.compact.apex` | H-01 | per-unit −5000 Qty=2 → net **45000**, NetTotal 90000 |
| `setupH02ManualPercentDiscountTestData.compact.apex` | H-02 | manual 30% Qty=4 → net **35000**, NetTotal 140000 |
| `setupH03ManualDiscountDerivedMaintTestData.compact.apex` | H-03 | manual % on derived maint → license stays 355, maint = 71×(1−disc) |

*Derived maintenance / edge / regression:*
| Script | Code | Creates + expected |
|---|---|---|
| `setupJ02DerivedTierTestData.compact.apex` | J-02 | license + Std/Expert maint → Std **71**; Expert $0 (3-tier) vs 124.25 (7-tier) |
| `setupJ03DerivedRenewalResetTestData.compact.apex` | J-03 *(new)* | BoKS PIAP 355 + derived New-Maint PIAMBK, non-renewal reset: NetUnitPrice Value Reset clears context net → `0.20×355` re-seeds → maint **71** |
| `setupJ06PartnerDerivedMaintTestData.compact.apex` | J-06 | partner derived maint → 71×(1−newMaint%), no double-discount |
| `setupJ07NewMaintPosthookTestData.compact.apex` | J-07 / SC-3412 | posthook fills maint net when procedure leaves $0 → **71** |
| `setupJ09DerivedNoPbedpTestData.compact.apex` | J-09 / SC-3372 | derived line, PBE with no PBEDP row → hard-error "contributing products missing" |
| `setupJ10FourFactorTestData.compact.apex` | J-10 | EUR renewal derived maint (partner + COLA + FX) → each applied once |
| `setupJ11ZeroPriceContributorTestData.compact.apex` | J-11 / SC-3372 | $0-list contributor → derived net 0.20×0 = **$0** (expected) |
| `setupK02MissingContributorTestData.compact.apex` | K-02 | derived maint, NO contributor on cart → net 0 surfaced as validation (not silent) |
| `setupK06ZeroAndMissingPbeTestData.compact.apex` | K-06 / SC-3345 | anchor + genuine $0 + retired-SKU lines → must NOT corrupt header rollup |
| `setupK07DerivedTierTestData.compact.apex` | K-07 | 7-tier Basic=**53.25** vs 3-tier regression Basic→0 |
| `setupK08DerivedCancelTestData.compact.apex` | K-08 / SC-3441 | cancel derived maint Qty=−1 → credit maint net **71**, not license, not list-0 |
| `setupK09StaleCategoryTotalTestData.compact.apex` | K-09 / SC-3345 | delete a Services line + reprice → `Total_Services__c` resets to 0 (not stale) |
| `setupK10NullSafeMixedQtyTestData.compact.apex` | K-10 / SC-3441 | (+5) and (−1) same product → negative excluded from positive aggregate |

*Orders / convert / lifecycle / ticket repros (surface `OrderId` / Contract Id, not QuoteId):*
| Script | Code | Creates + expected |
|---|---|---|
| `setupNewQuoteWaterfallTestData.compact.apex` | F-01 | brand-new full-waterfall Software line (contributor base stamped) |
| `setupAmendRemoveProrationTestData.compact.apex` | F-12 | amend-REMOVE Qty=−50000 → prorated negative delta; seeds `CancelNetUnitPrice__c` |
| `setupTermDefinedConvertTestData.compact.apex` | I-02 / SC-3420 | 2 TermDefined lines bracketing the PTC-writer guard (null PTC/EndDate at convert) |
| `setupTieredConvertTestData.compact.apex` | B-07 | tiered attribute line, convert-ready → tier re-eval on Order after convert |
| `setupK03LargeOrderTestData.compact.apex` | K-03 / SC-3366/3447 | ~35-OrderItem Order incl. high-qty Power → governor smoke test |
| `setupK05RepriceOrderingTestData.compact.apex` | K-05 / SC-3308 | Order left pre-reprice → must reprice before Activate (INVALID_INPUT race) |
| `setupCancelOrderTestData.compact.apex` | SC-3441 | Order Qty=−1 cancel line → `CancelLineNetSeedHandler` stamps net from asset |
| `setupCancelQuoteTestData.compact.apex` | SC-3441 | convert-ready cancel Quote Qty=−1, `CancelNetUnitPrice__c` seeded |
| `setupPowerConvertQuoteTestData.compact.apex` | SC-3447 | convert-ready high-qty Power line → stays ONE Qty=N OrderItem |
| `setupSC3502Lineage.apex` | SC-3502 | activated **Contract** + Asset + Source Opp/Order + Renewal Opp (renew lineage) |
| `f04_initiateRenewal.apex` | F-04 / SC-3346-ren | headless renewal Quote from COLA-eligible assets (needs a prior contract) |
| `sc3346_confirm_rnm_renewal.apex` | SC-3346 | headless renewal on RNM maint asset — does it land Renew/committed or Amend/$0? |
| `setupHrmClsaasEurRepro.apex` | SC-3384 (UI) | **empty** EUR quote — add HRM-CLSAAS tier SKU in UI → expect EUR ~2373.60 not USD 2580 |
| `setupPiambkAutoAddEurRepro.apex` | SC-3384 (UI) | **empty** EUR quote — add PIAP in UI → auto-add PIAMBK currency-mismatch error |

*SC-3346 Path B (renew owned maintenance **as itself**) + walkthrough helpers — mostly `DRY_RUN`/read-only, org config not scenario oracles:*
| Script | Code | Creates + does |
|---|---|---|
| `sc3346_pathB_boks_termdefined.apex` | Path B pilot | BoKS PIAMBK: non-default **Term-Based-Annual** PSMO + derived USD TermDefined PBEs (both books) so maint renews as the same product |
| `sc3346_pathB_prove.apex` | Path B prove | renew-as-itself **exact Product2Id** match + Renew QuoteAction → reprice commits COLA net |
| `sc3346_add_rrm_line.apex` | Path B born-net | before-insert `RenewalQuoteActionStamp` mints a Renew QA sourcing the owned RNM asset |
| `sc3346_pathB_scaleout_owned_maintenance.apex` | Path B scale (DRY) | batch the pilot across all owned installed New-Maint products; mirrors OneTime PBEs both books/all currencies |
| `sc3346_pathB_scaleout_verify.apex` | Path B verify | **read-only** 6 invariants INV-1..6 (expect all PASS) |
| `sc3346_fix_mirror_prices.apex` | Path B (DRY) | align $0 non-USD TermDefined `IsDerived=false` PBE UnitPrice to the non-zero OneTime sibling |
| `sc3346_revert_harmful_flips.apex` | Path B (DRY) | allowlist restore OneTime-as-DEFAULT, demote harmful 07-06 Term-Annual default |
| `sc3346_run_catalog_batch.apex` | Path B (COMMIT) | enqueue `RenewalMaintenanceCatalogProvisionBatch(false)` @50/chunk |
| `createAccountLJsCompany.apex` | helper | Account "LJ's Company" (Customer/USD, idempotent) — start of an end-to-end RLM walkthrough |
| `createOpportunityLJsCompany.apex` | helper | Opp "LJ's Company - New Business Deal" (Net-New/USD, idempotent) |

## §5 — PRICING SCENARIO MATRIX (run each; reprice TWICE)
For every scenario: pick the real record (§3/§4) → snapshot BEFORE → reprice → reprice AGAIN → snapshot AFTER
→ verify the **Expected** against the **oracle fields** → check the D-18 log → record PASS/FAIL/BLOCKED.

**A. List price / One-Time / Perpetual** — *S1.* `NetUnitPrice`/`UnitPrice` = catalog `ListPrice` (no discount);
one-time & perpetual lines legitimately have `PricingTermCount = null`; `TotalPrice = NetUnitPrice × Quantity`.

**B. Subscription (term + evergreen) / Proration / PricingTermCount** — *S2, S14.* Term lines carry a non-null
`PricingTermCount` (engine-only writeable — a null on a TermDefined line is the SC-3420/3411 defect);
proration reflects `StartDate`/`EndDate`; `PricingTermUnit` correct.

**C. Renewal + COLA (Line > Contract > CMDT > MyCAP)** — *S3.* `COLACalculatedPrice__c` = prior net × (1+uplift);
`COLA_Uplift_Percent__c` and `COLA_Source__c` reflect the winning tier; a manual line override wins over
Contract wins over CMDT; MyCAP = out-year floor (year-1 keeps the CMDT rate). Renewal maintenance lines are
owned by the SC-3346 derived path, not COLA.

**D. Derived / New maintenance** — *S4.* New-Maintenance lines derive net from the contributor base × tier rate
(not from list); band via `Partner_Pricing_Model__c`. A middle line at $0 is a defect **only if it has a matching
license contributor**; a $0 on an orphan maint line with no contributor is a DATA condition (not a priced node),
not a bug — see §8 SC-3346 resolution (SC-3346/3412).

**E. Partner Discount** — *S5.* `NetUnitPrice = Pre_Partner_Price__c × (1 − billingPartner Discount%)`;
`PartnerDiscountPercent` stamped; **re-reprice must NOT compound** the discount (DEF-1: base off
`Pre_Partner_Price__c`, not the already-discounted `NetUnitPrice`).

**F. Partner Guaranteed-Margin (additive, multi-partner)** — *S6.* `NetUnitPrice = ListPrice × (1 − Σ all partner
margins%)`; verify S6's 824 → **593.28** (28% total); a 0-margin partner is excluded from the sum.

**G. Fortra-Originated — Non_Orig populated AND null** — *S7 (populated 12% → 312.40).* When `Deal_Type__c =
'Fortra Originated'` the Non_Orig_* schedule applies; when a `Non_Orig_*_Pct__c` is **blank**, the engine falls
back to the standard band (owner decision — never silent 0%). **Both the prehook and (post D-11) the posthook
deferred path** must behave identically here. *(Non_Orig-NULL end-to-end = S8, BLOCKED no-data.)*

**H. Regional** — *S9.* Country multiplier applies to the **LIST** channel only → `UnitPrice`/`RegionalNetUnitPrice__c`
scaled; **NET stays catalog** (structural `TotalLineAmount ≠ NetTotalPrice` is expected); an Active regional row
with a null `Multiplier__c` must be skipped, not applied.

**I. Multi-currency (EUR/GBP/…)** — *S10 (GBP), S11b (EUR).* Non-USD lines price in the transaction currency;
today the engine prices USD then applies FX (`0.9346` for EUR) — verify the final `NetUnitPrice` equals the
expected converted value; flag any **double-FX** (corporate rate × hardcoded FX ≈ 8% under = F-09).

**J. Attribute / Volume / Tiered** — *S11.* The configured attribute volume selects a tier price; a **tier change
must reprice cleanly on the FIRST click** (SC-3390: no stale price, no reset-to-list); reprice twice → identical.

**K. Hardware / Power** — *S12.* `Hardware_Price = ListPrice × pGroup × userTier × (1 − systemType%)`; user
override > `Hardware__c` > default; on a high-qty Power line, convert must not blow CPU (SC-3447).

**L. Cancel / Amend-remove credit** — *S13.* A negative-quantity line yields a **credit** (negative
`TotalPrice`), not $0; `CancelNetUnitPrice__c` seeds the credit; a null `NetUnitPrice` on a cancel line must not
abort the whole reprice (K-01/SC-3441 null-safety).

## §5X — DEEP / EDGE PRICING SCENARIOS (fixture-backed — run for broader coverage)
The §5 A–L matrix is the backbone; **§5X widens it** to the corner cases the waterfall actually breaks on. Each
row is minted with its **§4B fixture** (no live record needed — you create a real one), then repriced ×2 and
graded against the fixture's own printed oracle. Run as many as time allows; each is a `RESULTS` row in §9
(`group:"§5X Deep/Edge"`). Reprice ×2 + check the D-18 log applies to every one.

| # | Deep scenario (what it stresses) | §4B fixture | Expected (PASS) | Defect signature (FAIL) | Ref |
|---|---|---|---|---|---|
| X-01 | Prior-transaction carry-forward on amend (net ≠ catalog) | `setupCarryForwardLastTxnTestData` | net carries **6695.30** | net = catalog **0** | A-02 |
| X-02 | One-time PTC + total (`Qty×list×PTC`) | `setupB01OneTimePtcTestData` | PTC=1 → **4400** | PTC null / total off | B-01 |
| X-03 | One-time excluded from proration | `setupOneTimeNoProrationTestData` | full amount, no proration | prorated down | B-08 |
| X-04 | 3-attribute ABA key (Feature×Deploy×ServerType) | `setupAttrServerTypeTestData` | L3 → **1575** (ABA fires) | L3 = 3150 (no match) | D-03 / SC-3360 |
| X-05 | Multi-line ABA $0-collapse guard | `setupD03IsolatedTestData` | each line prices independently | multi-line lines → $0 | SC-3360 |
| X-06 | Contracted attribute-based price branch | `setupContractAttrPriceTestData` | contracted L1 ≠ catalog L2 | contracted ignored | D-06 |
| X-07 | GSA pricing (GSW=true → ×0.5) | `setupGsaPricingTestData` | GSW=true → **list×0.5** | full list on GSW line | D-04 |
| X-08 | Partner Discount (Channel, 15%) | `setupE02PartnerDiscountTestData` | net **17425** | list / compounded | E-02 |
| X-09 | Partner % survives one-time branch | `setupPartnerOneTimeQuoteTestData` | 2008×0.85 = **1706.8** | partner% dropped on one-time | E-03 / SC-3359 |
| X-10 | GSA × partner cross-stack | `setupE06GsaPartnerCrossTestData` | stacked = **8712.5** | wrong stack order | E-06 |
| X-11 | Partner resolved-percent NULL → no discount | `setupE08PartnerNullPercentTestData` | NEG net **2400=list** / POS 1968 | NEG silently discounted | E-08 |
| X-12 | EUR catalog (currency-matched PBE) | `setupCurrencyEurCatalogTestData` | net **19159.30** EUR | USD-leak 20500 / double-FX 17906 | G-01 / SC-3384 |
| X-13 | EUR + ABA (tier table is USD-only) | `setupG02CurrencyAbaTestData` | EUR-consistent net | net = 1575 (USD leak) | G-02 / SC-3384 |
| X-14 | Partner × non-USD (FX × discount, once each) | `setupG03PartnerNonUsdOneTimeTestData` | 100000×0.9346×0.85 = **79441** | double-FX / double-discount | G-03 |
| X-15 | Regional EUR Italy (×0.64, no double-FX) | `setupG07RegionalEurTestData` | LIST 32900 EUR, NET 51403 | double-FX’d net | G-07 |
| X-16 | Manual amount discount (per-unit −5000) | `setupH01ManualAmountDiscountTestData` | net **45000** / NetTotal 90000 | discount not applied / compounds | H-01 |
| X-17 | Manual percent discount (30%) | `setupH02ManualPercentDiscountTestData` | net **35000** / NetTotal 140000 | wrong base | H-02 |
| X-18 | Manual discount on a derived-maint line | `setupH03ManualDiscountDerivedMaintTestData` | license 355, maint = 71×(1−disc) | maint follows license discount | H-03 |
| X-19 | Derived 7-tier (Basic not $0) | `setupK07DerivedTierTestData` | Basic **53.25** | 3-tier regression Basic→0 | K-07 |
| X-20 | Derived line with no PBEDP row | `setupJ09DerivedNoPbedpTestData` | hard-error "contributing products missing" | silent null net | J-09 / SC-3372 |
| X-21 | $0-list contributor → $0 derived maint | `setupJ11ZeroPriceContributorTestData` | derived net **$0** (expected) | error / nonzero | J-11 |
| X-22 | Missing contributor surfaced (not silent) | `setupK02MissingContributorTestData` | ValidationResult on $0 maint | silent $0 | K-02 |
| X-23 | $0 / retired-SKU lines don't corrupt rollup | `setupK06ZeroAndMissingPbeTestData` | header totals correct | header rollup corrupted | K-06 / SC-3345 |
| X-24 | Stale category total resets on line delete | `setupK09StaleCategoryTotalTestData` | `Total_Services__c` → 0 | stays stale | K-09 / SC-3345 |
| X-25 | Null-safe mixed +/− qty aggregate | `setupK10NullSafeMixedQtyTestData` | negative excluded from positive agg | mixed into aggregate | K-10 / SC-3441 |
| X-26 | Large order governor (~35 OI incl. Power) | `setupK03LargeOrderTestData` | reprice/convert, no SOQL:101/CPU | governor limit | K-03 / SC-3366 / SC-3447 |
| X-27 | Order must reprice before Activate | `setupK05RepriceOrderingTestData` | activate succeeds after reprice | INVALID_INPUT race | K-05 / SC-3308 |
| X-28 | Cancel derived-maint credits maint net | `setupK08DerivedCancelTestData` | credit = maint net **71** | credits license / list-0 | K-08 / SC-3441 |
| X-29 ✅ | **ABP base lands on Net-New partner perpetual** (guard — fixed `185a670`) | `0Q0WC000003JzHN` (partner Discount 15%) / a New partner quote w/ ABP attr → 20,000 | perpetual `Base_Price__c`=`Pre_Partner`= **20,000** → net **17,000** (−15%) | REGRESSION if Base falls to catalog **355** → net 301.75 (partner-path clobber) | SC-3346-ABP |
| X-30 ✅ | **Derived maint follows ABP base × tier** (guard) | same | maint base 20,000×0.20 = **4,000** → **3,400** (−15%) | REGRESSION if `UnitPrice`=71 / net 62.48 (355 base) | SC-3346-ABP |
| X-31 ✅ | **Procedure must not clobber ABP base** (reprice-stable) | same | ABP base survives reprice ×3, no compounding | REGRESSION if it re-overrides ABP with list, or compounds the partner % | SC-3346-ABP |
| X-32 | **Non-USD net = USD net × currency rate** (SC-3398 conversion) | `setupCurrencyEurCatalogTestData` (G-01) / EUR `0Q0WC0000036xy9` | EUR net = USD net × **0.9346**; **list stays native** EUR | net stays raw USD (no conversion) **or** list gets FX-converted | G-01 / SC-3398 |
| X-33 | **Amend on qty>1 asset carries per-unit** (SC-3501 qty-fold) | Cypress 00069475 fresh amend (EFT7Ent 273540/10) | NetUnit = **27,354** (=Price÷asset-qty); NetTotal = 27,354×line-qty | NetUnit ≈ **273,540** (extended total as per-unit → ~qty× inflation) | SC-3501 |

## §T — ASSIGNED-TICKET DEEP TESTS (PRIORITY — see the status board for verdicts)
Run each ticket as its own scenario with its §3 binding. For each: snapshot BEFORE → do the ticket action(s) →
**native Reprice All** TWICE → snapshot AFTER → check the D-18 log (§7.4) → grade against the ticket's
**Acceptance**. **PASS only if every Acceptance bullet holds.** Each is an `SC-####` row in the §9 report.
Several refine a §5 letter (noted) — run both; the §T row is the ticket verdict. **A verdict of `(org✓/git✗)`**
means the fix is live in FortraUAT but git-uncommitted — grade the **org** behavior, and record the commit gap.

### SC-3544 — Sales Price (`UnitPrice`) blank / $0 on renewal & amendment — ✅ FIXED `88c626f` (regression-guard)
*Binding:* renewal `0Q0WC000003Ifvp`; new-biz control `0Q0WC000003Ih3B`.
*Symptom (was):* on renewal / amendment quotes the **Sales Price** (`UnitPrice`) showed **blank/$0** in the TLE
even though the line priced correctly (`NetUnitPrice` populated); new-business was unaffected.
*Fix:* `UnitPrice` is an **input** to the RCA waterfall, not an engine output, and the deleted before-save flow
never fired (`persistContext` doesn't fire QLI before-save; an idempotent reprice does 0 DML). It is now filled by
a **post-persist Apex stamp** (`QuotePriceStampQueueable`, §1 stage 12) — `resolveSalesPrice = COALESCE(Base_Price__c>0,
Pre_Partner_Price__c>0, NetUnitPrice)` — **fill-only** (never overwrites an existing UnitPrice).
*Test:* reprice ×2; snapshot `UnitPrice` vs `NetUnitPrice`.
**Acceptance:** renewal/amend lines where `NetUnitPrice > 0` have `UnitPrice` **populated ≈ Net** (`Ifvp`
4573.80 / 918.75); new-biz control unchanged (`Ih3B` 2021.25); net/COLA/subtotal **0-delta** vs pre-stamp;
reprice ×2 stable; no D-18 row. **Verdict:** FAIL if `UnitPrice` blank/0 while `NetUnitPrice > 0`.
*Residuals (not fails):* segmented lines carrying `QuoteLineDetail` stay blank by design (platform forbids editing
`UnitPrice` there); on the EUR/SC-3398 quote the stamp surfaces the **USD** Base in the Sales-Price column
(cosmetic side-effect of the underlying USD-net leak); the S6 Guaranteed-Margin quote may settle `UnitPrice` on
the 2nd click (watch it lands on the first — SC-3390 family). *Net is always correct regardless.*

### SC-3501 — Amendment pricing does not recalculate (stays $0 / inflates on qty change) — 🟡 fixed live `(org✓/git✗)`
*Binding:* **fresh amend** off Cypress contract **00069475** (`800WC00000TWqUD`, Activated) — Amend a **qty>1**
asset, canonical **EFT 7 Enterprise** (asset `Price`=273,540, `Quantity`=10 → per-unit **27,354**). Healed
baseline (already-inflated-then-fixed) quote `0Q0WC000003KLsz` (total **156,819.99**). Original beSTORM draft
`0Q0WC000003J4m9` **masks the bug** (its source asset is qty-1, so ÷1 is a no-op — passes even on buggy code).
*Symptom (two-stage):* (1) an amend line was born `NetUnitPrice=0` and a qty change left it **$0** — no layer
carried the prior net (Amend was the only lifecycle action with no net-carry hook). (2) After the carry hook
shipped, a **qty>1** source asset **inflated ~qty×**: the prehook seeded `NetUnitPrice = Asset.Price`, but
**`Asset.Price` in this org is the EXTENDED line total (per-unit × qty), never per-unit** (verified across 271
assets) — Joe's qty-10 amend billed **$1,568,199.90** vs correct **156,819.99**.
*Fix (deployed to UAT, **git-uncommitted**):* `AmendNetCarryPrehook` (§1 stage 7) now seeds
`AssetNetUnitPrice.perUnit(Price, Quantity)` = `Price ÷ max(Quantity,1)`, recomputes `NetTotal = per-unit ×
current qty`, and heals stale `UnitPrice`/`Subtotal`. It is the **sole** amend-carry (the procedure's Amend group
was removed). ⚠️ **Committed HEAD still seeds raw `Asset.Price` → the 10× inflation reproduces on a clean checkout.**
*Test (WRITE — authorized):* on the fresh amend, change the EFT 7 Enterprise line **Quantity** → **native Reprice
All** ×2 → snapshot. (Headless `Fortra_Quote_Reprice` **bypasses the plan prehook** → false $0 — must use native.)
**Acceptance:** `NetUnitPrice` = **27,354** (= 273,540 ÷ 10, per-unit — **NOT 273,540**); `UnitPrice (Sales
Price) == NetUnitPrice`; `NetTotalPrice == Subtotal == TotalPrice == 27,354 × line-qty`; totals + Opportunity
amount move; reprice ×2 identical; baseline `KLsz` still 156,819.99; no D-18 row. **Verdict:** FAIL if the line
stays $0, if `NetUnitPrice ≈ Asset.Price` (qty-fold), or if `UnitPrice`/`Subtotal` stay inflated. *(Twin of
SC-3346-QTYFOLD on the renewal path; New-Maintenance amend lines are excluded — SC-3346. Refines §5-L.)*

### SC-3350 — Renewal (COLA) quotes priced at list, not prior + COLA; line description blank — 🟢 not-reproduced (guard)
*Binding:* renewal `0Q0WC000003Ibx3` (or `Ibqb` / `IbnN` / `2ljtN`). **Most faithful:** generate a fresh
platform renewal from an activated contract (SC-3502 action) so a real *prior* line exists to grow.
*Symptom (was):* the renewal line priced at the **SKU default list**, not **prior net + COLA %**; the **Line Item
Description was blank** on renewal lines.
*Fix:* COLA net-price seed shipped in `COLAUpliftPrehook` v1.2 (`41b5622`) — an isolated `NetUnitPrice` seed batch
(guarded fill-only genuine $0, ListPrice fallback for null-asset lines). The 07-08 and 07-09 live runs both grade
it **PASS**: COLA applied, descriptions present.
*Test:* reprice ×2; snapshot `NetUnitPrice`, `COLACalculatedPrice__c`, `COLA_Uplift_Percent__c`, `COLA_Source__c`,
and the line Description; compare each renewed line's net to the **prior** net ×(1+COLA).
**Acceptance:** renewal (non-maint) net = **prior net ×(1+COLA)** (NOT catalog list); COLA fields reflect the
winning tier (Line > Contract > CMDT > MyCAP); **Description populated**; reprice ×2 stable; no D-18 row.
**Verdict:** FAIL if net = default list or Description blank. *(Refines §5-C; renewal **maintenance** lines belong
to SC-3346. Caveat: one line (Additional Threat Assessments) still prices $0 with COLA base = CMDT default —
confirm the prior-DISCOUNTED-net base on a genuine platform renewal descended from a real prior order.)*

### SC-3354 — COLA renewal-pricing rework (parent of SC-3350) — 🟡 year-1 ✅ · multi-year 🔴 scope-open
*Binding:* same renewal quotes as SC-3350; audit (correct) quote `0Q0WC000003671t`; repro line `0QLWC000003bHpl`.
*Context:* COLA is implemented **twice** — a trigger (`COLAUpliftHandler`) that stamps at QLI insert and a prehook
(`COLAUpliftPrehook`) that writes during a procedure reprice — and **renewals are generated headlessly and never
run a full procedure reprice**, which is the single root of both SC-3350 symptoms (priced-at-list + no description).
The **year-1** defects are resolved (see SC-3350). **THE OPEN FORK = the multi-year model:** the ticket
spreadsheet wants **out-year compounding** (Base+COLA 200→206→212.18; Renewal-Maint 140→144.20→148.53, ×1.03/yr,
year-1 = CMDT category rate, out-year = MyCAP 3%) on **both** license and maintenance lines. Live out-year code
computes into the display-only field `Final_Year_COLA_Calculated_Price__c` but **references it 0× in the
procedure → out-year compounding is computed but never billed (INERT)**, and the formula base/exponent is broken.
*Test:* on a multi-year renewal, snapshot year-2/year-3 `NetUnitPrice` for license AND maintenance lines; check
whether `Final_Year_COLA_Calculated_Price__c` reaches price.
**Acceptance (multi-year, once scoped):** year-2/3 net = prior ×(1+outYearCOLA) compounded, on both license and
maintenance; `Final_Year_COLA_Calculated_Price__c` (fixed base/exponent) actually feeds net; year-1 = CMDT rate,
out-year = MyCAP 3%. **Verdict:** year-1 PASS (= SC-3350); multi-year **BLOCKED (scope decision pending Marc/German
— single-year fix vs. wire out-year compounding into pricing)**. *Watch latent bugs:* multi-asset contract-override
collapses to one asset (`AssetContractQueryHelper`); prehook fail-silent-SUCCESS; TEMP_BoKS CMDT rule covers 17
live BoKS products (do not delete before go-live) — see `Jira/Defects/sc3350/evidence/prior-brief/SC-3354_Research_Brief.md`.

### SC-3346 — Derived maintenance pricing (cluster: ABP ✅ · new-biz ✅ · MTD 🔴 · dedupe ✅ · renewal 🟢 · qty-fold 🟡)
Derived New-Maintenance nets from the contributor's **pre-discount Base × tier%** (Premier 0.30 / Standard 0.20 /
Professional 0.20), then the maint line's **own** partner + discretionary discounts — never the license's net,
never catalog list. Six distinct testable items below; grade each as its own suffixed `RESULTS` row.
*Design (one gated formula slot, gated on `Quote.QuoteTypeText__c`):* **New/Net-New** — maint = source `UnitPrice`
(pre-discount Base, attribute-adjusted `Source_List_Price__c` when ABP present) × tier%, then own discounts.
**Renewal** — maint = prior `Asset.Price × (1+COLA)` (single-component; Asset.Price is already discount-netted;
do NOT restore the 3-component graft — double-discount hazard). *Worked example (license Base $1,000, 20% tier):*
new maint $200 − Partner $20 − Discretionary $40 = **$140**; renewal grows the prior net ×(1+COLA).

**SC-3346-ABP — ✅ FIXED `185a670` (regression-guard).** *Binding:* Quote `0Q0WC000003JzHN` (New, USD, partner
Discount 15%); non-partner control **S1** `0Q0WC000003IIT0`. A partner+ABP line's ABP base (`Source_List_Price__c
=20000`) used to be **clobbered to catalog 355** through the partner path (perpetual net 301.75, maint 62.48).
`PartnerNetPricePosthook.isAttributePricedPartnerLine` now gates off the true ABP signal `Source_List_Price__c`
(not `Pre_Partner_Price__c>ListPrice`) and bases the attr-reprice strictly off `Pre_Partner_Price__c` so it cannot
compound. **Acceptance:** perpetual Base **20000 → net 17000** (−15%); derived maint **4000 → 3400**;
`UnitPrice==NetUnitPrice`; idempotent reprice ×3 (no compounding); S1 (no partner) unchanged 20000 / 4000.
**FAIL** = base falls to 355. *(USD-only scope — a non-USD partner+ABP line does not self-correct: separate ticket.)*

**SC-3346 new-business — ✅ FIXED (regression-guard).** Maint = source Base × tier, **discount-immune** (discounting
the license must NOT drop the maint base to the license net — the old bug pulled 468→374.40). BoKS `355` Standard →
**71.00**, Premier → 106.50; S1 20000 → **4000**.

**SC-3346-MTD — 🔴 OPEN (attribute-less new-maint → $0).** *Binding:* Quote `0Q0WC000003JXMj` (line 04267561 Device
Profiler qty1 with **no `Maintenance Type Defn` QLIA** → tier 0 → **$0**). The engine is correct; the **bundle
auto-add / configurator omits the tier attribute** on generated maint lines. Spec approved (default auto-added
derived maint to Standard 20%, rep overrides to Premier) but **impl deferred**. **Acceptance (once built):** an
auto-added derived New-Maint line carries `Maintenance Type Defn=Standard` → Base×0.20, not $0. **Verdict now:** the
$0 is a **known open attribute-propagation gap**, not scored as a pricing-engine fail.

**SC-3346-DEDUPE — ✅ FIXED `(org✓/git✗)`.** Adding a bundle whose Add-Assets path carries prior maintenance as
`QuoteAction.Type='Amend'` copies produced duplicate/qty-10 $0 New-Maint lines colliding with the native keeper.
`NewMaintenanceDedupeService` leaves **exactly one** derived maint per license (keeper survives; no-keeper quotes
untouched; renewals untouched). *Binding:* IBjF (3→1), IIT (2→1), J3en (3→1); no-keeper JXMj untouched.

**SC-3346 renewal — 🟢 not-reproduced (Path B).** The V23-era "renewal derived-maint is not a priced node" wall
**no longer reproduces** on the current proc: renewal maint derives a born-net via **Path B** (Renew QuoteAction +
OneTime→TermDefined provisioning; §4B `sc3346_pathB_*`), e.g. BoKS 71×1.0785 = **76.57**. The V14→V23 "regression"
theory is **CLOSED** (`DerivedProductsNonRenewal` identical). *Binding:* BoKS contract 00069410 (`800WC00000Sy0Rf`);
proven renewal quotes 00781793/94. **Validate on COMMITTED NET only** — never renewal-count, never `UnitPrice`
(SC-3544 fill-only), never `PBE.UnitPrice` ($0 for derived is correct). *(The 24% $0 headline is ~92% May-2026
migration noise; engine-priced $0 rate is 7.86%.)*

**SC-3346-QTYFOLD — 🟡 `(org✓/git✗)` (renewal COLA on qty>1).** Twin of SC-3501: `COLAUpliftHandler` used the
extended `Asset.Price` as the per-unit → qty>1 renewal maint inflated ~qty×. ÷qty fix (`AssetNetUnitPrice.perUnit`)
deployed but **git-uncommitted**; **one line escaped to Workday (order 00095510, ES-SEG qty100, 157,500 vs ~1,575)**
— needs correction + WD re-sync. **Acceptance:** renewal maint on a qty>1 asset = `(Asset.Price ÷ Quantity) ×
(1+COLA)` per-unit; qty-1 unaffected (no double-division). **FAIL** = per-unit ≈ extended `Asset.Price`.
*(Refines §5-D and §8.)*

### SC-3384 — Non-USD quote lines priced from USD (investigation) — 🟡 PARTIAL; the fix is now **SC-3398**
*Binding:* EUR `0Q0WC0000036xy9` ("Q-Wren Test Currencies", 6 lines). The leak: `ListPrice` is correctly EUR but
**Net Unit / Net Total / Subtotal / Total** were computed from **USD** override/tier/attribute values (e.g.
beSECURE-Cloud net 8165 USD × 0.9346). Base **list**-price PBE lookup was already currency-correct; only the
configured/derived surfaces were currency-blind. **Two coexisting mechanisms — do not conflate:** (A) a
currency-aware NATIVE tier lookup (`255f7c5`) — correct-but-**dormant** (needs a per-currency data seed that was
never done) — **being reverted by SC-3398**; (B) an Apex posthook that FX-localizes raw-USD values (`185a670`) —
what actually delivers non-USD pricing today. **This ticket's two live sub-fixes:**

**SC-3384-E — ✅ FIXED `43fa4d1` (auto-add maintenance PBE currency).** A perpetual whose Year-1/2 maintenance
auto-adds PIAMBK **by Product2 Id** on an EUR quote threw *"price book entry currency … different than the
Quote."* A before-insert guard (`QuoteLineItemCurrencyCorrectionHandler`) re-points the mis-currencied PBE to the
same-product/book/PSM sibling in the quote currency. **Acceptance:** the EUR quote adding PIAP+PIAMBK **saves with
no currency-mismatch**; each auto-add QLI lands on a same-currency PBE; already-matching lines are 0-delta no-ops;
a product with no same-currency sibling is left untouched (native validation still fires). *Binding:* EUR quote
`00781700` / `setupPiambkAutoAddEurRepro.apex`.

**SC-3384-CTX — 🔴 OPEN (context re-sync).** `SalesTransactionContextExt_v2` was edited to add `ABA_Raw_Net__c`
but the active context version was **never re-synced** → live **"Something went wrong while hydrating the context"**
UI error on a managed reprice. **Acceptance:** opening a quote / native reprice does **not** throw the hydration
error; the active context version registers `ABA_Raw_Net__c`. *Org-config fix (re-sync via Context Def Manager),
needs UAT auth + a brief pricing-offline window; a UI SC-3398/ABA test will hit this until re-synced.*

### SC-3398 — Non-USD net = USD net × currency rate (the chosen conversion-based fix) — 🔴 OPEN (core step pending)
*Binding:* EUR `0Q0WC0000036xy9`; CAD `0Q0WC000003ASz1`. *Approach (supersedes SC-3384's data-load path):* price
everything in **USD** as always, then **one late procedure step** multiplies the USD-computed net by the line's
rate from `Currency_Conversion_Formula__mdt` (`STICurrencyIsoCode`, fallback `CurrencyIsoCode`; USD/blank → ×1.0).
**List price stays NATIVE** (per-currency PBE — never converted). This replaces the catalog-scale per-currency
override/tier data load with a single multiply.
*Status:* **delivered** — the Total-Price-mode `net=0` bug (3 value-pricing steps now output NetUnitPrice+InputUnitPrice)
and the rate table (`Currency_Conversion_Formula__mdt`, 10 currencies). **Pending** — (Ph3) add the conversion step
+ populate numeric `Conversion_Rate__c`; (Ph4) **revert** the SC-3384 currency-matching (decision-table currency
input, `AttributeVolumePricingPrehook` currency filter, loaded per-currency rows — else they double-match);
(Ph5) per-currency PBE coverage for list price (JPY/NZD/CHF token, MXN 0); (Ph6) enable NZD in the Legal-Entity
allow-list (`Legal_Entity_Currency__mdt`, depends on FORTRA-OPP-001). ⚠️ **Confirm the single live procedure
version before any builder edit** (SF team mid-edit).
*Test:* on the EUR quote, reprice ×2; per line compare net vs `USD_net × 0.9346`.
**Acceptance:** non-USD line **Net Unit / Net Total / Subtotal / Total = USD-computed net × currency rate** (EUR
0.9346, CAD 1.3889); **List Price stays native EUR/CAD (unconverted)**; USD quotes **0-delta** (rate 1.0); the
`net=0` Total-Price-mode line now nets before conversion; Subtotal + Sales-Price display reflect the converted
value; reprice ×2 stable; no D-18 row. **Verdict:** FAIL if a non-USD net stays **raw USD** (no conversion), if
**list gets FX-converted**, or if a USD line moves. *(Refines §5-I. NB: the earlier "EUR net must come from an EUR
PBE, not USD×FX" framing is **retired** — SC-3398 deliberately prices net = USD×FX, list-only from the EUR PBE.)*

### SC-3502 — Renewal process fails to generate the renewal Opportunity — 🟢 not-reproduced (observational)
*Binding:* activated contract `800WC00000TNpyn` (00069451) — or `TNjN7` / `TNBRw`. Renewal-Opp linkage =
`Opportunity.Renewed_Contract__c`. Fixture `setupSC3502Lineage.apex` builds a fresh activated Contract + Asset +
Source Opp/Order + Renewal Opp.
*Symptom (was):* initiating renewal **hung** — the renewal **Opportunity never appeared**, blocking quote sync.
*Test (WRITE — renewal generation authorized):* from an activated contract, run the renewal; wait for the async
job; `SELECT Id, StageName, Amount, Renewed_Contract__c FROM Opportunity WHERE Renewed_Contract__c='<contractId>'`.
**Acceptance:** a renewal **Opportunity is generated automatically** (row with `Renewed_Contract__c` = the
contract); the user can proceed to quote sync; no hang; no D-18 row. **Verdict:** FAIL if no renewal Opp / hang.
*(Distinct from **SC-3500** = Opp IS generated but Amount=0 — ✅ FIXED via the +15min after-assetization flow +
`RenewalForecastAmount` = Σ MRR×12×COLA; $0 is correct for one-time-only contracts. A clean SC-3502 Opp is the
**precondition** for faithful SC-3346-renewal / SC-3350 "prior-net base" tests. Feeds §6.10.)*

### SC-3505 — Amendment does not carry the original Workday contract ID — 🔴 PARKED (no code fix)
*Binding:* amend orders 00095512 / 00095642 (payloads carry own `Order.Id` only); native/manual amends 00095531 /
00095676. *Premise correction:* the "Workday Contract ID" is **not** Workday-returned — it is the SF `Order.Id`
(stamped by `Fortra_Order_Workday_Contract_ID`, own-key). Native RLM amendments **reuse the source contract in
place** (they do NOT mint a new contract), and the outbound is only the platform event `Order_Completed_WD__e`
(`Order_Id__c`) → MuleSoft builds `Submit_Customer_Contract`. **The gap:** an amendment's payload emits **no
reference to the original contract** — every id = the amend order's own Id.
*Symptom:* Workday cannot distinguish "amend existing contract X" from "create new contract."
*Test (read-only):* inspect the two populated payloads (`Order.Workday_Sync_Payload__c`) — every id resolves to the
own Order.Id, no original-contract reference. *(Live pass-check = re-sync an amendment [publish `Order_Completed_WD__e`]
then re-read the payload — a WRITE, authorization-gated.)*
**Acceptance (target — currently FAILS):** an amendment payload carries the **original** contract's Workday ID in a
**separate** field (e.g. `Original_Customer_Contract_Reference`), value ≠ the amend order's own Id, populated for
**all** amendments (incl. the manual ones with no Quote lineage); new/renewal orders get **no** spurious original
ref; the own-key mapping is unchanged. **Verdict:** FAIL — no code fix exists (`5f21481` = peer-review docs under
`Jira/PeerReview/sc3516`, 0 force-app changes; Marc's "implemented" claims re-verified NOT present in 5 orgs).
*(SC-3516 is the peer-review of SC-3505, not a separate feature. Feeds §6.8.)*

### SC-3513 — Asset needs a field indicating what was purchased (Asset.Description re-derive) — ✅ FIXED `47cb089`
*Binding:* needs a **real** Upgrade/Downgrade **AssetAction** on a stamped asset (AssetAction is not Apex-createable
→ no pure unit test); backfill dry-run `Data/sc3513/backfill_16.apex`. Field = writable **`Asset.Description`** (NOT
the system-locked `Asset.ProductDescription`).
*Fix:* flow `Fortra_AssetAction_Stamp_Line_Description` rebuilt to trigger on AssetAction-Create across **8**
product-change categories (Initial Sale, Upsells, Renewals, Downsells, Upgrades, Downgrades, Swaps, Cross-Sells),
closing the previously-missing **update** path (was create-only, 3 categories). Resolves `OrderItem.Description` via
`AssetActionSource.ReferenceEntityItemId` → OrderItem, or via `OrderItemDetail.OrderItemId` parent (14C prefix gotcha).
*Test:* on Initial Sale, confirm `Asset.Description === OrderItem.Description === QuoteLineItem.Description`; then
create a change AssetAction (Upgrade/Downgrade) on an already-stamped asset → confirm Description **re-derived** to
the new line.
**Acceptance:** create-path byte-identical to the line description; product-change on an existing asset **re-derives**
(all 8 categories); **excluded** events (Cancellations / Transfers / T&C / Other) do NOT re-derive; a manual
`Asset.Description` edit (no AssetAction) is NOT auto-reverted; flow stays best-effort async (fault → log-and-continue,
never blocks the AssetAction). **Verdict:** FAIL if a product-change leaves Description stale, or a create-path stamp
regresses. *(Feeds §6.7. Do not conflate with `AssetArrFromOrderItemHandler`, which copies ARR, not Description.)*

### SC-3503 — Contract cancellation fails with a "Stamp Base Filter 1" system error — 🔴 OPEN (Critical)
*Binding:* no bound record (surfaced in the **6/29 demo**, Marc). Mint a cancel via §4B `setupCancelOrderTestData` /
`setupCancelQuoteTestData`, or drive **Contract → Cancel** on an activated contract (e.g. a Cypress/00069475-style
activated contract). Same procedure element (**Stamp Base Filter**) as SC-3346-ABP — check whether the ABP-gate fix
(`185a670`) or the amend/qty-fold work moved this.
*Symptom:* initiating a **contract cancellation** errors out referencing **"Stamp Base Filter 1"** and the
cancellation **cannot complete** (no expected records created). Marc had never seen the error before → likely a
pricing-procedure fault surfacing on the cancel path.
*Test (WRITE — cancellation authorized):* from an activated contract, run the cancellation process; capture the
exact error + any D-18 `Exception_Log__c` row; identify which procedure element / hook raises "Stamp Base Filter 1".
**Acceptance:** the cancellation **completes successfully and creates the expected records** (credit line(s) /
cancel Order — §5-L), no "Stamp Base Filter" fault, no unhandled system error; reprice of the resulting
cancel/credit is stable; D-18 clean. **Verdict:** FAIL if the cancellation errors or cannot complete. *(Feeds §6A
Cancel / §6.9. First step = reproduce and capture the fault's originating element — it is a **pricing** fault on
a lifecycle path, so localize it against §1.)*

## §6 — END-TO-END QUOTE-TO-CASH SMOKE TEST (exhaustive lifecycle — **EXECUTE, don't just observe**)
This is a **full-lifecycle smoke test**: drive one real quote **all the way** Draft → Reprice → Order → Activated →
Contract → Assets → Workday → Amend → Renew, **grading every phase** with real evidence — then repeat across the
**line-type lanes** below so the e2e is exhaustive (not one happy path). Each phase × lane = its own `RESULTS` row
(`group:"§6 Lifecycle"`, id `6.x` / `6.x-<lane>`). Writes here (convert / activate / amend / renew) are **authorized**;
check the **D-18 log (§7.4) after every write**. A phase that cannot be driven headlessly → **drive it in the UI and
record the observed result** (BLOCKED-only if neither headless nor UI is possible; never silently skip).

**Run the lifecycle on EACH lane (exhaustive line-type coverage — mint the start with §4B if no clean record):**
| Lane | Starting quote / fixture | Exercises end-to-end |
|---|---|---|
| **L-SUB** | clean subscription (S2 / `setupTieredSubQuoteTestData`) | term + PTC + proration → asset + renewal COLA |
| **L-PERP** | perpetual + derived maint (S1 / S4) | one-time PTC-null + derived-maint **asset creation** |
| **L-HW** | hardware / Power (S12 / `setupPowerConvertQuoteTestData`) | Power **qty-split** + CPU (SC-3447) |
| **L-PARTNER** | partner Discount/GM (S5 / S6) | partner net **survives** convert + asset ARR (+ ABP base — SC-3346-ABP) |
| **L-FX** | non-USD (S10 GBP / S11b EUR) | currency **carries** to Order + Asset (no USD leak) |
| **L-CANCEL** | cancel/amend-remove (S13 / `setupCancelOrderTestData`) | credit line + re-activate |

**§6A — QUOTE CREATION FROM CONTRACT → MANAGE ASSETS (Renew / Amend / Cancel) — price-accuracy gate.**
Amend / Renew / Cancel quotes are **born** from an activated Contract's **Manage Assets** tab (the managed UI
action), not typed by hand — and the whole downstream lifecycle inherits whatever that step generates. So the
**first** graded phase for the amend / renewal / cancel lanes is: open the activated Contract → **Manage Assets** →
select the target asset(s) → **Renew** (Automatic Renewal) / **Amend** / **Cancel** → the platform generates a
Draft quote with QLIs sourced from the contract's assets → **native Reprice All**. This is a `RESULTS` row `6A-<lane>`.

*Verify — the generated QLIs are correct + complete, per line, against the source Asset:*
- **Line set:** one QLI per selected asset (per **unit** for Power); correct `QuoteAction.Type` (Renew / Amend /
  Cancel); `QuoteAction.SourceAsset` populated; no phantom/duplicate maintenance lines (SC-3346-DEDUPE).
- **List Price** = per-currency catalog `ListPrice` (native — never FX-converted; SC-3398).
- **Net Unit Price** — *Renew:* prior asset net ×(1+COLA) (SC-3350); *Amend:* prior **per-unit** net = `SourceAsset.Price
  ÷ SourceAsset.Quantity` — **not** the extended total (SC-3501 / SC-3346-QTYFOLD); *Cancel:* negative credit =
  `−CancelNetUnitPrice__c` (SC-3441); derived maintenance follows the SC-3346 branch.
- **Total Price / Net Total / Subtotal** = `Net Unit × Quantity`, **sign-correct** (negative on Cancel), **precise to
  the cent** — no rounding drift, no unexpected $0, no ~qty× inflation.
- **Sales Price (`UnitPrice`) == Net** (SC-3544, fill-only); **Line Description populated** (SC-3350).
- **Reprice ×2 idempotent** (SC-3390); **D-18 clean**.

**Verdict:** FAIL if any generated line has a wrong / blank / imprecise **List**, **Net Unit**, or **Total**, a
missing or duplicate line, a qty-fold, or if the create action **errors** — e.g. **SC-3503 "Stamp Base Filter 1"**
on Cancel, or a currency-mismatch on a non-USD Manage-Assets quote. This gate feeds the amend (§6.9) / renew
(§6.10) / cancel lanes. *(Headless can't drive Manage Assets — this is a UI action; agent is the read-only oracle, §UI U-2/U-6.)*

**The phases — grade each (expected → verify):**

**6.1 Configure** — add products/bundles/attributes in the Transaction Line Editor; config **saves** (no currency-mismatch,
no validation abort). *Verify:* lines + attributes present (`SELECT COUNT() FROM QuoteLineItemAttribute WHERE QuoteLineItemId IN (…)`).

**6.2 Reprice (Quote)** — §2 ×2. *Verify:* `isSuccess`; snapshot **idempotent** (0 delta); no line $0 that shouldn't be; **D-18 clean**.

**6.3 Convert → Order** — the **"Convert Quote to Order"** quick-action button (UI), or headless flow
`Fortra_Quote_to_Order_Conversion` (input `QuoteId`). *Verify:* an **Order** exists (`SELECT Id,Status,QuoteId FROM
Order WHERE QuoteId=…`) with **one OrderItem per QuoteLineItem** (per **unit** for Power — Power lines qty-split
into 1 OrderItem/unit: `SELECT Quantity,COUNT(Id) FROM OrderItem WHERE OrderId=… GROUP BY Quantity`),
`Order_Line_ARR__c` apportioned per-unit (not N×); converting an **un-repriced** Order → `INVALID_INPUT` is
SC-3308/K-05 (reprice first); **no CPU/SOQL:101** on high-qty Power (SC-3447).

**6.4 Reprice (Order) — QUOTE↔ORDER LINE PARITY (especially "Reprice All").** Run **Reprice All** on the Order
(quick action / `Fortra_Order_Reprice`, input `OrderId`) ×2. *Verify — the converted Order behaves the same as the
source Quote, line for line:*
- Each OrderItem maps to its QuoteLineItem (`OrderItem.QuoteLineItemId` / product + qty) and carries **identical**
  `ListPrice`, `UnitPrice`, `NetUnitPrice`, `NetTotalPrice`, `Subtotal`, `TotalPrice` (**dual-object parity, to the
  cent**), plus `PricingTerm` / `PricingTermCount` / `StartDate` / `EndDate`.
- Order-only fields resolve: `RegionalNetUnitPrice__c` + `Workday_Contract_Line_Type__c` (varied, **not** all
  'FIXED AMOUNT' — SC-3210/3368).
- **Reprice All on the Order is idempotent** (2nd click 0-delta) **and does not diverge from the Quote** — a
  post-convert Order reprice must not re-introduce a $0, a qty-fold, or a currency leak the Quote didn't have.
*Verify SOQL:* `snapshot.sh Order <orderId>` vs the Quote snapshot → `diff.py` **GATE PASS — 0 delta** (ignoring
object-specific fields). **FAIL** if any Order line's price differs from its Quote line, an OrderItem is missing,
or Reprice All on the Order changes values the Quote had settled.

**6.5 Activate Order** — set `Status='Activated'` (or the managed activate action). *Verify:* `Status='Activated'`;
`EndDate` + `PricingTermCount` present on **every** TermDefined line **before** activation (null blocks it — SC-3411/3406);
activation does not throw (`FAILED_ACTIVATION: contract inactive` = a stranded Draft — activate, don't leave Draft).

**6.6 Contract** — a Contract is created and **Activated** (not Draft). *Verify:* `SELECT Id,Status,ContractNumber FROM
Contract WHERE …` → `Status='Activated'`.

**6.7 Assets** — activation creates **Assets** (`SELECT COUNT() FROM Asset WHERE …` **> 0**). A subscription order
completing with **0 Assets** = the SC-3415/3419 optimistic-lock swallow (**FAIL**). *Verify:* Asset count == line count
(per **unit** for Power); `Asset.Price`/`ARR__c` = apportioned line value (not N×); `AssetAction`/`AssetActionSource`
present; Asset carries `Product2` + currency; derived-maint contributor pairs land as separate assets.

**6.8 Workday sync** — publish/observe `Order_Completed_WD__e` (`Order_Id__c`). *Verify:* each line's
`Workday_Contract_Line_Type__c` is correct (**NOT** every line 'FIXED AMOUNT' — SC-3210/3368), `extendedAmount` ==
`NetTotalPrice` and **sign-correct** (SC-3374), and an **amendment** carries the **original contract ID** (SC-3505).
**Observe-only** unless a step authorizes a publish.

**6.9 Amend** — amend the activated order/contract to reduce/remove a line → a **credit** line (negative `TotalPrice`,
`CancelNetUnitPrice__c` seeded — §5-L); amend **carries prior net** (`AmendNetCarryPrehook` — SC-3501); re-activate.
*Verify:* credit line negative; totals move; reprice succeeds (K-01 null-safety); amended non-touched lines = No Change qty 0.

**6.10 Renew** — from the **activated contract → Managed Assets → Renew** (Automatic Renewal) → renewal Quote + Opportunity:
the renewal **Opportunity is generated** (`Renewed_Contract__c` set — SC-3502), `Amount` non-zero where recurring,
`RenewalForecastAmount` = Σ MRR×12×COLA (SC-3500); the renewal lines **price after Reprice All** — **subscription** = prior
asset net ×(1+COLA); **perpetual** = No Change/$0 (correct — never re-bill a perpetual); **derived maint** = the SC-3346
branch. *Verify (proven 2026-07-10, contract 00069408):* Renew Cobalt/beSECURE → Reprice All → 6265.80 / 218.77 (×3 =
18797.40 / 656.31), **6.2% COLA**; a **No Change** action forces qty 0 → $0 (correct for perpetual); a **Cancel** action
**blocks** renewing that asset (data precondition, not a bug — "6 assets could not be renewed").

**E2E acceptance:** every phase completes and grades **PASS on ≥ L-SUB and L-PERP** (run the other lanes as far as data
allows); each repriced phase **idempotent**; **D-18 clean** throughout. The named **FAILs**: 0-Asset swallow (6.7),
stranded-Draft contract (6.5/6.6), all-lines-FIXED-AMOUNT (6.8), no-renewal-Opp / hang (6.10), un-repriced-convert
INVALID_INPUT (6.3), partner clobbering the ABP base into the order/asset (SC-3346-ABP feeding 6.7). Record **each phase
and each lane** as a `6.x` row; every FAIL → Defects section with its ticket ref.

## §7 — CROSS-CUTTING CHECKS (run on EVERY scenario)
1. **Idempotency** — reprice twice; the two snapshots must be byte-identical (SC-3390). A second-click delta = FAIL.
2. **Governor** — on the 15+ line quote (S14) the reprice must complete with **no `SOQL:101` / no CPU limit**
   (SC-3366). Capture limits from the debug log if available.
3. **Currency display** — non-USD line `NetUnitPrice` and the displayed converted value are consistent (no
   double-FX; G-01/F-09).
4. **D-18 exception log** — after each reprice:
   `sf data query -o FortraUAT -q "SELECT Source__c, Hook_Phase__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC"`.
   **Any new row = a pricing hook swallowed an error** (partner/COLA/regional/hardware/attr/etc.) → FAIL and
   attach the row, even if the price looks correct. (Real-context delivery latency is ~20–40s — wait then query.)

## §8 — REGRESSION MUST-NOT-BREAK (historically fragile — always include)
| Ticket | Test | Must NOT | Check |
|---|---|---|---|
| SC-3390 | tiered attr reprice twice | reset-to-list / need 2 clicks | 1st==2nd snapshot |
| DEF-1 | partner Discount re-reprice | compound (×0.82 each pass) | NetUnitPrice stable on 2nd reprice |
| SC-3441 / K-01 | cancel line, null NetUnitPrice | $0 instead of credit / abort reprice | negative TotalPrice; reprice succeeds |
| SC-3366 | 15+ line reprice (S14) | SOQL:101 / CPU | reprice isSuccess, limits under cap |
| SC-3384 / F-09 | non-USD (+partner) reprice | USD-blind / double-FX ~8% under | converted NetUnitPrice correct |
| SC-3415/3419 | activate subscription order | 0 Assets | Asset count > 0 |
| SC-3347/3374 | Workday sync | Contract Amt ≠ Line Amt / all FIXED | extendedAmount=NetTotalPrice; line-types varied |
| SC-3420/3411 | TermDefined line | null PricingTermCount | PTC non-null; activation succeeds |
| SC-3346/3412 | derived maint **with a matching contributor** | $0 | net > 0 from contributor base *(a $0 orphan/no-contributor line = data, not a fail; renewal derived-maint now prices via Path B — SC-3346 renewal)* |
| SC-3346-ABP | Net-New **partner** line with an ABP base (`Source_List_Price__c` set) | fall back to **catalog list** base | ✅ fixed `185a670` — perpetual Base = ABP (**20,000**, not 355), maint = ABP×tier (**4,000**, not 71); S6 GM reverts to catalog-list **593.28**, no compounding |

**Assigned-ticket regressions (once fixed, must not re-break — full detail + acceptance in §T):**

| Ticket | Test | Must NOT | Check |
|---|---|---|---|
| SC-3544 | renewal/amend Sales Price | blank/$0 `UnitPrice` while Net > 0 | `UnitPrice` populated ≈ Net on `Ifvp` |
| SC-3501 | amend qty>1 → native Reprice All | line $0 / totals stale / **~qty× inflation** | NetUnit = Price÷asset-qty (27,354 not 273,540); totals + Opp move |
| SC-3346-QTYFOLD | renewal COLA on qty>1 | per-unit = extended `Asset.Price` (~qty× inflation) | per-unit = Price÷Quantity; qty-1 unaffected |
| SC-3350 | renewal COLA reprice | price = default list / desc blank | net = prior ×(1+COLA); Description filled |
| SC-3346 (renewal) | Path B born-net derive | renewal maint $0 | committed net > 0 (e.g. 76.57); grade **COMMITTED NET only** (never UnitPrice / count / PBE) |
| SC-3398 | non-USD reprice (conversion) | net stays raw USD / **list FX-converted** / USD line moves | net = USD net × rate; list native EUR/CAD; USD 0-delta |
| SC-3384-E | non-USD auto-add maintenance | currency-mismatch error / wrong-currency PBE | saves clean; same-currency PBE |
| SC-3502 | renewal from contract | no renewal Opp / hang | Opportunity w/ `Renewed_Contract__c` created |
| SC-3513 | product-change AssetAction | stale `Asset.Description` on update | re-derived across 8 categories; create-path unchanged |
| SC-3505 | amendment Workday payload | *(open)* no original-contract ref | *target:* separate `Original_Customer_Contract_Reference` ≠ own `Order.Id` |
| SC-3503 | contract cancellation | "Stamp Base Filter 1" fault / cannot complete | cancel completes + creates credit records |

## §UI — UI-ONLY EXECUTION GUIDE (the scenarios the headless path cannot reach)
**Why this section exists.** The RLM / Revenue-Cloud engine prices only what is in the managed **SalesTransaction
context**, which the **cart (Transaction Line Editor)** establishes when you Add/Edit a line or run a managed
place-action. **Apex-DML-inserted lines and raw `sf data update` edits never enter that context** — so a headless
reprice (the `Fortra_Quote_Reprice` flow *or even* the Force-reprice place-action) reads **$0 / stale** on them
**regardless of whether the engine is correct** (proven repeatedly: §4B fixtures read net=$0 after a Force-reprice;
the SC-3501 false-FAIL; fixture quote `00781774` = net $0 with PTC/list populated). **A headless run therefore
cannot score the lanes below — they must be built and read in the UI.** Pattern for an agent-assisted run: the
**tester drives the UI**, the **agent is the read-only oracle** (snapshot SOQL §2 + D-18 §7.4 after each step).
**→ For a fully UI-driven run, use the companion prompt [`docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md`](RCA_UI_MANUAL_E2E_TEST_PROMPT.md)
(Claude Chrome Extension) — it drives every action on the Salesforce Lightning UI and reads the on-screen oracle.**
This §UI is the CLI-agent's map of *which* scenarios require that UI path.

**What is UI-only, and why:**
| Lane | Scenarios | Why headless can't score it |
|---|---|---|
| **U-1** | §5X deep/edge **X-01…X-28** (all §4B fixture-backed) | fixtures insert lines via Apex DML → never priced in context |
| **U-2** | §6.3 Convert · §6.4 Order-reprice (parity) · §6.5 Activate · §6.6 Contract · §6.7 Assets | a minted quote can't be priced, so converting it yields a $0 Order/Asset — drive the **"Convert Quote to Order"** quick action from a **real UI-priced** quote |
| **U-3** | SC-3384 / SC-3398 EUR repros (`setupHrmClsaasEurRepro`, `setupPiambkAutoAddEurRepro`) | fixtures build an **empty** EUR quote on purpose — the currency defect fires only when you **add the SKU in the cart** |
| **U-4** ✅ | **SC-3346-ABP** (partner + ABP base — now a **regression-guard**) | the partner+ABP base must survive a **cart-built partner** New quote (fixed `185a670`; guard against re-break) |
| **U-5** | SC-3390 tier reprice-twice · SC-3346 tier-picklist change | the tier/attribute change must be made in the **configurator** to enter context |
| **U-6** | §6A **Manage Assets → Renew / Amend / Cancel** creation + §6.10 renewal | managed UI actions (headless leaves lines $0 until Reprice All); the amend qty-fold (SC-3501) needs **native** reprice |
| **U-7** | **SC-3503** contract cancellation ("Stamp Base Filter 1") | the Cancel action + its pricing fault fire only via **Contract → Cancel / Manage Assets** in the UI |

### THE CORE RECIPE — build any pricing scenario in the Transaction Line Editor (use for every U-1 row)
1. **Header.** New Quote (or **Deep-Clone** a clean one) on the scenario's **Account** (partner lanes: set the
   **Billing Partner** + `Partner_Pricing_Model__c`), **Currency** (EUR/GBP for FX lanes), Quote Type = the required
   type (New / Renewal / Amendment). Save.
2. **Lines tab** → set **Instant Pricing = OFF** (you control when it prices).
3. **Add Product** (search box, top-right of the line grid) → the scenario's **SKU** → set **Quantity**.
4. **Configure attributes** — expand the line (▸ / the config gear) → set the scenario's attributes
   (*Feature*, *Deployment*, *Server Type*, *Maintenance Type Defn = Standard/Premier*, tier **volume**, GSA flag,
   manual discount) → **Apply**. *(Derived maintenance: the license auto-adds its `-RNM/-NM` maint line; make sure
   the maint line carries **Maintenance Type Defn** — if the auto-add omits it the tier is 0 → $0.)*
5. **Reprice All** (top-right — the full managed place-action). Wait for the green *"The prices were refreshed and
   the configuration was validated."* toast. *(A yellow "prices aren't up to date — Refresh" banner → click Refresh.)*
6. **Read the oracle** — List Price · **Net Unit Price** · Net Total · Subtotal · Total · Subscription Term / PTC —
   against the scenario's **Expected** (the §5X row, or the fixture's printed `EXPECT …`).
7. **Reprice All again** → every column **identical** (SC-3390 idempotency). Any change on the 2nd click = **FAIL**.
8. *(oracle:)* confirm with the §2 snapshot SOQL and check the **D-18 log** (§7.4) — a new `Exception_Log__c` row = FAIL.

**U-1 map — each §5X fixture → what to add in the UI → expected (build via the recipe; full expected in §5X):**
Open the named `scripts/apex/` fixture to read its **SKU + attribute values + printed EXPECT**, then build that same
line-set in the cart. High-value rows to prioritise (the open-defect-adjacent ones): **X-04/05** (ABA 3-attr key,
`setupAttrServerTypeTestData` — Feature×Deployment×ServerType → L3 **1575**), **X-12/13** (EUR catalog / EUR-ABA,
`setupCurrencyEurCatalogTestData`/`setupG02CurrencyAbaTestData` → **19159.30** EUR, no USD-leak), **X-18** (manual
discount on derived maint), **X-19** (7-tier Basic **53.25**), **X-21/22** ($0-contributor / missing-contributor
surfaced), **X-28** (cancel derived-maint credit **71**). The rest follow the same recipe.

### U-2 — Convert → Order → Activate → Contract → Assets (drive from a real UI-priced quote)
1. Start from a **priced** UI quote (a golden S-binding, or one you built via the recipe) — confirm the lines carry
   non-$0 **Net**. 2. **Convert Quote to Order** (header button) → note the new **Order**. 3. Open the Order → **Reprice
   All** → confirm **Net matches the Quote** (dual-object parity) and **Power lines split 1 OrderItem/unit**. 4.
   **Activate** the Order (Activate button / Mark Status) → **Status = Activated** (no `FAILED_ACTIVATION`; TermDefined
   lines must show **End Date + Subscription Term** first — else it blocks). 5. Verify a **Contract** is created and
   **Activated** (not Draft). 6. Open the Contract → **Managed Assets** → **Assets exist** (count == line count; a
   subscription order with **0 Assets** = SC-3415/3419). *Oracle SOQL:* `SELECT Status FROM Order WHERE Id=…`;
   `SELECT COUNT() FROM Asset WHERE …`; `SELECT Workday_Contract_Line_Type__c FROM OrderItem WHERE OrderId=…` (varied,
   not all FIXED AMOUNT — SC-3210/3368).

### U-3 — SC-3384 EUR (empty-quote repros)
1. Run `setupHrmClsaasEurRepro` **or** `setupPiambkAutoAddEurRepro` (creates an **empty EUR quote** — grab its Id/URL).
2. Open it → **Add Product** → **HRM-CLSAAS** (tier SKU) or **PIA-PIA-NRPS-PIAP** (auto-adds PIAMBK). 3. Set the tier
   **volume** attribute → **Reprice All**. 4. *Expected:* the tier/net is the **EUR** value (HRM-CLSAAS ≈ **2373.60**,
   not USD 2580), and the auto-add maintenance does **not** throw *"price book entry currency … different than the
   Quote."* **FAIL** if net is USD-sourced or the currency-mismatch fires.

### U-4 — SC-3346-ABP (partner clobbers the ABP base — the 2026-07-10 defect)
1. New **partner** quote (Billing Partner set, `Partner_Pricing_Model__c = Discount`, Quote Type **New**). 2. **Add
   Product** BoKS **PIA-PIA-NRPS-PIAP** and configure the attribute(s) that resolve its **Attribute-Based Price = 20,000**
   (`Source_List_Price__c` should read 20,000). 3. **Reprice All**. 4. *Expected:* perpetual **Base/Pre-Partner = 20,000
   → Net 17,000** (−15%); derived maint **20,000 × 0.20 = 4,000 → 3,400**. *Current defect:* Base falls to catalog **355**
   → net 301.75, maint 71 — **FAIL**. **Control:** repeat with **no partner** → the ABP base lands (20,000 → 20,000, maint
   4,000). The delta between the two = the partner-path bug (feeds the `Stamp Base Filter` / stage-4 fix).

### U-5 — SC-3390 / tier change (reprice-twice, first-click clean)
1. On a tiered-attribute line (S11 / a `setupTieredSubQuoteTestData` line), open the configurator and **change the
   tier volume** (or Standard→Premier maintenance). 2. **Reprice All ONCE**. *Expected:* the new tier price lands on
   the **first** click — **no reset-to-list, no need for a 2nd click**. 3. **Reprice All again** → identical. FAIL if it
   took two clicks or bounced to list.

### U-6 — Renewal from contract (managed)
Contract → **Managed Assets** → select the renewable **subscription** assets → **Renew** → **Automatic Renewal** →
open the generated renewal Quote → **Reprice All**. *Expected:* subscription lines = prior asset net ×(1+COLA)
(e.g. Cobalt 5900→**6265.80**, +6.2%); **perpetual** = No Change/$0 (correct); a **Cancel**-actioned asset is **blocked**
from renewing ("N assets could not be renewed" — a data precondition, not a bug). Proven live on contract **00069408**.

> **Report these UI-run rows** the same way as headless ones (§9): `group:"§5X Deep/Edge"` (U-1), `"§6 Lifecycle"`
> (U-2/U-6), or `"§T Assigned tickets"` (U-3/U-4), with `record` = the UI quote Id and `evidence` = the on-screen
> oracle values. Mark any you could not run **BLOCKED (UI not available)** — never silently drop them.

## §9 — OUTCOME: HTML + JSX REPORT (mandatory output format)
Deliver the results as a **single self-contained HTML file with embedded React/JSX** — high visibility,
color-coded, scannable. **Use the ready template** [`docs/rca_test_report_template.html`](rca_test_report_template.html):
copy it, fill the `META` object and the `RESULTS` array (one object per scenario), save as
`rca_test_report_<date>.html`, and open it in a browser. Do **not** hand back only a markdown table.

**Each `RESULTS` entry (the row schema):**
```
{ id, group, category, scenario, record,  // id (SC-#### / A–L / S# / X-##), group ("§T Assigned tickets" | "§5 Pricing" | "§5X Deep/Edge" | "§6 Lifecycle" | "§8 Regression"), category, one-line scenario, real UAT record Id (a §4B-minted Id counts as real)
  stage,                            // the waterfall stage it exercises (§1)
  ticket,                           // ticket / regression ref (e.g. "SC-3346", "SC-3390"), else ""
  verdict,                          // 'PASS' | 'FAIL' | 'BLOCKED'
  expected, actual,                 // expected vs actual oracle values (real numbers)
  evidence,                         // proof (e.g. "reprice ×2 identical", "824→593.28", "144.20/148.53")
  exceptionLog }                    // any Exception_Log__c row (§7.4), else "none" / "—"
```

**The report renders out of the box:** an overall PASS/FAIL banner + pass-rate %, big **PASS / FAIL /
BLOCKED** stat cards, a stacked pass-rate bar, status-filter chips, a most-severe-first scenario table with
color-coded status pills and **click-to-expand evidence**, a dedicated **Defects** section, and a **Blocked**
section listing each missing precondition. It is responsive and light/dark aware.

**Coverage the report must reflect:** **all six §T assigned tickets** (id `SC-####`, most-severe-first), every
§5 pricing scenario (A–L), **as many §5X deep/edge scenarios as you ran** (id `X-##`, `group:"§5X Deep/Edge"`),
each §6 lifecycle phase, and each §8 regression must-not-break — one `RESULTS` row apiece (with §5X the full run
is **~65+ rows**). Give the §T rows a `group:"§T Assigned tickets"` so they cluster at the top; put every §T/§5X
FAIL in the **Defects** section with its ticket ref. For a §4B-minted record, put the fixture name + the created
Id in `record`/`evidence` (the fixture's printed EXPECTED is your oracle). Populate `exceptionLog` from the §7.4
D-18 query per scenario — **a populated value on an otherwise PASS-looking row is still a FAIL.**

> To publish it as a shareable **Claude Artifact** instead of a local file, inline React/ReactDOM rather than
> the CDN `<script>` tags (the Artifact CSP blocks external scripts) — the JSX and structure are identical.

---
*Grounded in the sole-active pricing waterfall (`Rev_Mgmt_Default_Pricing_Procedure` **V25**, confirmed
2026-07-11) + the S1–S14 golden harness (`Data/pricing-refactor-scratch/harness/`); the
harness `baselines/` hold frozen 0-delta oracles you can diff against directly. **Status board + §T are current as
of 2026-07-11 (see CHANGELOG); several fixes are live in FortraUAT but git-uncommitted — flagged `(org✓/git✗)`,
grade the org.** Re-verify each binding with the §3/§4 SOQL before use (statuses drift). **§4B/§5X are
fixture-backed:** 63 scripts in `scripts/apex/` (savepoint-protected) mint real UAT records (each prints its own
EXPECTED oracle + DEFECT signatures) — use them to un-block any "no data" scenario and to run the §5X deep/edge
matrix. **Two companion prompts:** this **CLI** prompt (Claude Code + `sf`/SOQL) and the **UI Manual E2E** prompt
[`docs/RCA_UI_MANUAL_E2E_TEST_PROMPT.md`](RCA_UI_MANUAL_E2E_TEST_PROMPT.md) (Claude Chrome Extension, drives the
Salesforce Lightning UI). Report template: [`docs/rca_test_report_template.html`](rca_test_report_template.html);
ticket dossier `docs/RCA_TICKET_DOSSIER_20260709.md`.*
