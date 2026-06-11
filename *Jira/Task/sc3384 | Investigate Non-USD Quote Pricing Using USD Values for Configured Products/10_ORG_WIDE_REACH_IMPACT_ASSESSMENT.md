<!-- Org-wide multi-currency reach/impact (broad workflow wj7f55boa: 29 agents, 101 findings, 14 verified). Addresses Jomil's leadership question: other configs affected + total effort incl DocGen. Companion to the focused per-defect RCA. -->

# SC-3384 — Multi-Currency Impact Diagnosis (FortraUAT / Revenue Cloud Advanced + RLM)

**Prepared for:** Jomil Bell (leadership) · Liam Jeong, Nir Kailash, Marc DeBrey (working team)
**Date:** 2026-06-11 · **Scope:** Multi-CURRENCY only (multi-language explicitly out of scope per Jomil)
**Evidence base:** Live FortraUAT (read-only: SOQL/COUNT/GROUP BY, Tooling API, sObject describe, metadata retrieve) cross-checked against the `Org Data/_src` mirror and the Orders-MultiCurrency design doc. All counts below are live unless noted.

---

## 1. Executive Summary

Multi-currency in FortraUAT is **partly working and partly broken, and it is NOT "only a data issue."** The RLM pricing engine itself is currency-correct — the single active pricing procedure (V12) and every named prehook contain zero hardcoded ISO codes or conversion logic — so the engine will price whatever currency a line carries. But correctness collapses on **two independent fronts that require code/config work, not just records**: (a) the org's exchange-rate data is corrupted — **7 of 11 non-corporate currencies (GBP, JPY, CHF, NZD, ILS, ARS, SEK) sit at conversion rate exactly 1.0**, and GBP/JPY/ARS/SEK were demonstrably *reset* to 1.0 across 2026-02-11/12/13 after being correctly maintained through Jan 2026; and (b) the surfacing assumption of **two decimal places and USD-magnitude absolute price overrides is hardcoded across ~8 Apex classes, 1 DocGen DataRaptor, and the AttributeBasedAdjustment data layer (13,072 rows, 100% USD Override).** The verdict on Wren's hope: thin-currency *transaction surfacing* (JPY/CHF/NZD) is mostly a data problem (those records are a one-time 2026-05 migration batch with zero-priced PBEs), but making multi-currency **correct end-to-end** is a mixed DATA + CONFIG/CODE effort whose reporting blast radius is large — **129 reports and 20 dashboards (incl. the Cyber Exec, Renewals Forecast, and Sales Manager dashboards) silently consolidate foreign amounts into USD at face value** (e.g. ¥221M JPY pipeline shown as $221M). **Total effort: ~6–9 weeks of effort across 3 workstreams** (rate-data + governance; pricing/adjustment data + decision-table key; DocGen + Apex decimal handling), excluding the external Workday-tenant currency setup which is an unverified third-party dependency. DocGen does **not** print "$" on foreign documents (worst-case fear is false), but it mis-renders JPY (forces 2 decimals) and shows no currency symbol — a small, contained CONFIG/BUILD fix.

---

## 2. Current State in FortraUAT — What Actually Exists vs the Design Doc

The Orders-MultiCurrency design doc materially **overstates** what is deployed. The doc cannot be trusted as a deployment manifest; every component was re-verified live.

| Design-doc claim ("deployed & verified in production") | Live FortraUAT reality | Verdict |
|---|---|---|
| `CurrencyConversionService` (class) | Exists only as `Fortra_CurrencyConversionService` | renamed |
| `PricebookCurrencyUpdateBatch`, `PricebookUpdateRollbackService` | **Do not exist** (only `Fortra_BulkPriceUpdateBatch` / `_Invocable`) | confirmed absent |
| `ExchangeRateUpdateTrigger`, `SetOpportunityCurrencyOnCreate` (triggers) | **0 rows.** Live exchange-rate trigger is `QuoteLineItemExchangeRateTrigger` (on QLI) | confirmed absent (capability under a different name) |
| 5 supported currencies (USD/EUR/GBP/AUD/CAD) | **12 active currencies**; real txns in JPY/CHF/NZD/ARS | refuted |
| Currency mismatch warning flows + `Legal_Entity_Currency_Match` VR on Quote | Both Warn flows **Draft** (one Obsolete); the VR **does not exist** (Quote has 4 VRs, none currency) | confirmed inert |
| `Fortra_Opportunity_Legal_Entity_AutoSelect` = core automation | **Obsolete** (no active version) | confirmed dead |
| `Fortra_Opportunity_Currency_Sync` | **Active** — the one piece matching the doc | confirmed |

**The real live currency-setting mechanism is undocumented:** `Fortra_Opportunity_LE_Currency_Validation` (Active, RecordBeforeSave on Opportunity) loops `Legal_Entity_Currency__mdt` and auto-corrects `CurrencyIsoCode` to the primary legal-entity currency. (Correction from earlier framing: it sets *only* `CurrencyIsoCode`, not `Legal_Entity__c`, and it **coexists** with the still-Active after-save `Fortra_Opportunity_Currency_Sync` rather than replacing it.) This flow is the rework epicenter and is absent from all documentation.

**The Legal-Entity backbone the doc relies on is effectively unpopulated:** `Account.Default_Legal_Entity__c` 64/179,980 (0.04%); `Opportunity.Legal_Entity__c` 741/125,637 (0.6%); `Quote.Original_Opportunity_Currency__c` 0/166,304 (0%). The documented top-down propagation cannot fire. `Quote.LegalEntityId` is 16% populated, but 97.7% of those quotes have no Opportunity at all — so Quote LE arrives via a non-Opportunity path, **not** the documented Opp→Quote copy.

---

## 3. Reach Map — Every Affected Configuration Area

Single comprehensive table. **Sev**: H/M/L/Info. **Type**: Data / Config / Both. **DG**: DocGen-relevant.

| Area | Finding (evidence) | Sev | Type | DG | Effort |
|---|---|---|---|---|---|
| **Exchange rates (core)** | 7 of 11 non-corporate currencies at `ConversionRate=1.0` (GBP/JPY/CHF/NZD/ILS/ARS/SEK). GBP/JPY/ARS/SEK had real dated rates through 2026-01-01 then **reset to 1.0 on 2026-02-11/12/13**; CHF/ILS/NZD never maintained. CurrencyType AND current-effective DatedConversionRate both 1.0. | H | Data | — | S–M (reload rates) + find the job that wrote 1.0 |
| **Reporting blast radius** | **129 reports** consolidate money into USD with no per-currency breakout (342/342 reports with a `<currency>` setting = USD; 0 group by ISO). JPY Opp pipeline ¥221M shown as **$221M** (~$219M overstatement); GBP £14.1M counted 1:1. | H | Data | — | S (fixed by rate correction; reports need no change) |
| **Dashboards** | **20 of 39** dashboards inherit poisoned aggregates: Cyber Exec (16 high-risk sources), Sales Manager (11), Pipeline Generation (11), Renewals Forecast (8, money col), PS Business (8), Marketing, Services Delivery. | H | Data | — | S (same data fix) |
| **Parenthetical conversion** | `Currency.settings`: `isParenCurrencyConvDisabled=false` → every list view, detail page, related list, search result also renders converted corporate value at 1.0 for the 7 broken currencies. Org-wide UI reach. | H | Config | — | N/A (poisoning source is rate data) |
| **AttributeBasedAdjustment (AAMP)** | 13,072 rows **100% USD, 100% AdjustmentType=Override** (absolute, e.g. 900,000/584,995). Decision table `Attribute_Based_Adjustment_Decision_Table` (Active) has **no CurrencyIsoCode match column** → USD override is *matched and applied* to non-USD lines (mis-applies magnitude; does NOT skip). 595/889 (67%) of non-USD products carry such an adjustment. | H | Both | — | M–L (per-currency rows + add CurrencyIsoCode to decision-table key) |
| **PricebookEntryDerivedPrice (maintenance/derived)** | 173 rows 100% USD → no non-USD derived/maintenance prices; ties to SC-3372 "contributing products missing." PBE itself is currency-keyed, so gap is purely missing rows. | H | Data | — | M (generate non-USD derived rows) |
| **PricebookEntry coverage** | Only 8 of 12 currencies have PBE: USD 18,875 / EUR 6,527 / GBP 6,513 / AUD 6,511 / CAD 6,504 / **JPY 42 / CHF 17 / NZD 12 / ILS=MXN=SEK=ARS=0**. | H | Data | — | M–L per currency (run Bulk Multi-Currency batch once formulas+rates set) |
| **Conversion-formula CMDT** | `Currency_Conversion_Formula__mdt` = 6 rows (ARS/AUD/CAD/EUR/GBP/USD). Missing JPY/CHF — **which ARE legal-entity currencies.** Batch loops only `keySet()` of active formulas → cannot mint PBE for the other 6 currencies at all. (Note: framework is functional — code reads `Conversion_Formula__c` string, not the null `Conversion_Rate__c`.) | H | Both | — | S (author 6 rows) — gated on rate-source decision |
| **Three-store rate fragmentation** | CurrencyType vs DatedConversionRate vs static CMDT formula strings disagree (GBP formula `*0.79` vs CurrencyType 1.0; ARS `*666.67` vs 1.0). PBE minted from CMDT; reporting from CurrencyType/Dated. No reconciliation. Plus a 4th: Certinia/FF `c2g__`/`fferpcore__` exchange-rate objects. | H | Both | — | M (pick single source of truth) |
| **`Corporate_Currency_Amount__c`** | Opp & Quote formula `CURRENCYRATE("USD") * Amount` = 1.0 × local → returns **raw local amount mislabeled corporate**. 15,033 non-USD Opps + 24,551 non-USD Quotes wrong. BUT consumers = only 2 Quote page layouts; **0 reports/Apex/Flow/DocGen** bind it. | H→M | Config | — | S (fix formula; also needs rate fix to be correct) |
| **`Order/OrderItem.Exchange_Rate_To_USD__c`** | 0/5,162 non-USD Orders, 1/29,711 OrderItems populated (no Order-side writer; only Opp+QLI paths exist). Field meta: "Read by Workday for financial reporting." QLI is 100% populated but 1.0 for GBP/JPY/CHF/NZD. | H | Both | — | M (add Order-side writer + backfill) |
| **Renewal flows (currency carry)** | `Fortra_Create_Renewal_Quote` (v6) inherits currency from **original Quote** (not Asset), never re-stamps or re-validates LE/rate; `Fortra_Renewal_Quote_Creation` from **Contract**; `Fortra_RCA_Renewal_Enhancement` from **$Record** → renewal currency non-deterministic across 3 entry points. 100% of JPY/CHF/NZD renewal QLIs have `ListPrice=0`. | H | Both | DG | M–L (ties to SC-3350) |
| **`Asset.PricingSource`** | Null on **all 430,327 assets** → renewal reprice has no last-price fallback, fully dependent on PBE list in carried currency (which is 0 for thin currencies). Structural link to SC-3350 $0-net. | H | Data | — | M |
| **Q2O conversion reprice** | `Fortra_Quote_to_Order_Conversion` v27 runs `OrderRepriceInvocable` before activation on 5,087 non-USD renewal orders → with ListPrice=0 lines → CompletedWithoutPricing / SC-3308 activation failures. | M | Config | — | S |
| **DocGen — JPY decimals** | `DMTransformFortraQuote` hardcodes `CONCAT("",ROUND(x,2))` on **12 money fields** → JPY (CurrencyType.DecimalPlaces=0, the only zero-decimal active currency) renders `689,400.00`. 7,288 JPY QLIs / 855 JPY OIs exercise it live. | H | Config | DG | M (parameterize by `CurrencyType.DecimalPlaces`) |
| **DocGen — no symbol / single template** | No per-amount symbol; one `Currency: {{currency}}` ISO label (correct passthrough of CurrencyIsoCode). Single hardwired en_US template; no $/USD hardcoded on amounts (the one `$` is legal boilerplate). | L | Config | DG | S (symbol map optional) |
| **DocGen — Order docs** | `Order_Form` template = **Draft/unwired**; no live Order doc path. Must be built currency-aware if activated. | Info | Config | DG | (future) |
| **Apex 2-decimal `setScale(2)`** | 8 classes round money to 2dp with no currency awareness: `Fortra_CurrencyConversionService` (mints PBE prices), `MaintenanceOrderDecompositionService`, `COLAUpliftPrehook`, `PartnerNetPricePosthook`, `QuoteRepricingController`, `PartnerPricingService(V2)`, `HardwareAttributePricingPrehook` (~17 sites). **No code anywhere reads `CurrencyType.DecimalPlaces`.** | H | Config | — | L (one currency-scale helper + retrofit) |
| **`QuoteRepricingController:178`** | UI toast hardcodes `'$' + headerDiscount` regardless of currency. Cosmetic. | L | Config | — | XS |
| **Legal-Entity coverage** | 37 LegalEntity records, 7 active currencies (ARS/AUD/CAD/EUR/GBP/JPY/USD); CHF inactive-only; **NZD/ILS/MXN/SEK have none** → LE-driven path cannot produce them, yet NZD/CHF txns exist. `Fortra, LLC` has **two** Is_Primary=true rows (GBP + USD). | M | Both | — | S (fix dup primary + add rows) |
| **`CurrencySelectionService`** | Hardcodes US/CA/AU + Eurozone→EUR, defaults all else to USD (no GBP/JPY). Legacy, **orphan** (no caller), 0% coverage. | L | Config | — | S (delete or extend) |
| **`OrderMigrationService`** | Auto-creates `UnitPrice=0` PBEs in order currency when none exists (line 1457) → source of $0 non-USD catalog rows. | M | Data | — | S (audit) |
| **`Dynamic_Conversion_Rate__c`** | **Dead field**: 0% populated org-wide, no writer, no consumer except 1 page layout. Third abandoned rate vector. | L | Config | — | XS (retire) |
| **Workday downstream** | **0 of 5,162 non-USD orders ever reached Workday "Success"** (5,160 stuck "Activated"; only 2 GBP "Order Complete"). Multi-currency downstream entirely **untested**. Mule payload IS currency-aware (`currencyIsoCode` + `currencyID`, verified on USD 00095381). | H | Both | — | M (drive a non-USD order through) |
| **Workday tenant currency** | API mandates `Currency_Reference [1..1]` on Billing Schedule; rejects unaccepted/unrated currencies. Whether the 12 SF currencies are Accepted Currencies + have WD conversion rates is **external, unverifiable from SF**, never exercised. | H | Config (external) | — | M (Workday/MuleSoft team) |
| **`NetTotalPrice` for Mule extendedAmount** | ~0% populated on non-USD OrderItems (EUR 0/15,054, JPY 0/855) — if the SC-3347 Mule fix reads `NetTotalPrice` it sends null. Should compute `NetUnitPrice × Qty`. | M | Both | — | S–M |
| **PSA / Certinia packages** | ~25 active `pse__` currency-mismatch VRs (Assignment/Budget/Project/etc.); Certinia `CurrencyRevaluation`/`ExchangeRate` triggers; ~101 unretrievable managed reports incl. a "Currency Revaluation Reports" folder. Separate currency subsystem. | M | Config | — | M–L (separate scoping; not Fortra-custom) |
| **Cross-object formula `Quote.Original_Contract_ARR__c`** | `= Renewal_Contract__r.Expected_Ren_Amount__c` across a plain lookup → no conversion. 1 of 75 live quotes already mismatched (CAD quote / USD contract). Will scale. | M | Config | — | S |
| **PSMO subscription PBE** | 0 PSM-keyed PBE in JPY (CHF 11, NZD 4). **But** no JPY/CHF/NZD transaction has any subscription line (100% SellingModel=None; only 3–4 legacy "SKU-Other" products); so this is a *latent* gap, not a live defect. | H→latent | Both | — | M only if subscription products sold in these currencies |
| **Pricing engine (negative)** | V12 procedure (64,752 lines) + all 11 named prehooks: **0 ISO literals, 0 conversion logic.** Only 1 active pricing procedure exists; "Maintenance/COLA/Derived" are steps within V12, not separate procedures. | Info | (correct) | — | none |
| **Master-detail SUM rollups (negative)** | QLI→Quote, OI→Order SUMs structurally same-currency (cannot corrupt). No native Roll-Up Summary fields on Account/Contract/Opp/Order (0 summary fields). No DLRS. Currency snapshot fields are TEXT() formulas (cannot drift). | Info | (safe) | — | none |

---

## 4. Is It "Only a Data Issue"? — Verdict

**No.** The honest split:

**Pure-DATA fixes (Wren's hope is correct here):**
- **Conversion rates.** Reload correct rates for GBP/JPY/CHF/NZD/ILS/ARS/SEK in `CurrencyType` + `DatedConversionRate`. This single fix corrects all 129 reports, 20 dashboards, the entire parenthetical-conversion UI surface, the Opp/QLI `Exchange_Rate_To_USD__c` values, and the `CURRENCYRATE()` formulas — *no report/dashboard rework needed.* This is the highest-leverage, lowest-effort fix and the rates were demonstrably correct 5 months ago.
- **PBE coverage backfill** for actively-transacted products (JPY/CHF/NZD already have same-currency PBEs for every product quoted — 0 referential-integrity breaks across 11,830 sampled lines — they are merely zero-priced).
- **Conversion-formula CMDT rows** for the 6 missing currencies.
- **Retire dead config** (`Dynamic_Conversion_Rate__c`, orphan `CurrencySelectionService`).

**CONFIG/CODE fixes (data alone will NOT make it correct):**
- **`AttributeBasedAdjustment` decision table** needs a `CurrencyIsoCode` match column added — *cloning rows alone would cause same-product collisions.* And the USD-Override-applied-to-foreign-line is a structural magnitude bug today.
- **2-decimal hardcoding** in ~17 Apex sites + 12 DocGen formulas — a single currency-scale helper reading `CurrencyType.DecimalPlaces` (JPY=0, all others=2) is the correct oracle; no code reads it today.
- **`Corporate_Currency_Amount__c`** formula is wrong by construction (multiplies by 1.0).
- **Renewal currency** is sourced inconsistently from 3 different upstream records; `Asset.PricingSource` null org-wide breaks the reprice fallback.
- **Inert guardrails** — the documented mismatch warnings and VR must be built/activated.
- **`OrderMigrationService`** manufactures $0 PBEs.

**The clinching evidence against "data only":** `ListPrice=0` is **systemic across all currencies** (USD 63.3%, AUD 55%, CAD 45%), not multi-currency-specific. Backfilling thin-currency PBE prices would NOT make those quotes behave like USD quotes, because USD lines themselves are predominantly zero-list and rely on the RLM waterfall/overrides. Making multi-currency correct = running transactions through the same pricing config/process, which is CONFIG/PROCESS.

---

## 5. DocGen Impact — Leadership's Explicit Question

**Verdict: documents do NOT mis-render foreign currency as "$" today — the worst-case fear is FALSE.** The active Quote template ("Fortra Quote Consolidated EN" V3) prints bare numbers plus one `Currency: {{currency}}` label that correctly echoes the record's `CurrencyIsoCode`. The single `$` in the document is static legal boilerplate ("a fee of $150,000, as liquidated damages"). The Extract DataRaptor pulls amounts in the record's stored currency with **no conversion math** — so there is no double-conversion, and the stale-rate problem does **not** corrupt DocGen output directly (DocGen prints whatever the record stored).

**What IS wrong (all CONFIG/BUILD, not data):**
1. **JPY mis-formats.** Every money token is `ROUND(x,2)` → JPY (zero-decimal) renders `689,400.00` instead of `¥689,400`. Live exposure: 2,019 JPY quotes / 202 JPY orders. Fix: derive scale from `CurrencyType.DecimalPlaces`.
2. **No per-amount currency symbol** — cosmetically weak/ambiguous on multi-page docs.
3. **Renewal documents** for JPY/CHF/NZD render `$0` list prices and broken discount math — but this is upstream pricing data (ListPrice=0), not a template defect; fixes itself once pricing is corrected.
4. **Order DocGen** does not exist (Draft/unwired); must be built currency-aware if activated.

**Scope:** ~1 active template + 1 Transform DataRaptor (~6–12 formulas) + optional symbol map = **S (2–4 days)**. The `QLDescriptionGeneratorPrehook` is currency-agnostic (text only). **Caveat:** OmniProcess/OmniDataTransform could not be queried via Tooling API in this org; conclusions rely on force-app metadata synced during SC-3335. A live JPY document render would be definitive proof.

---

## 6. Effort Sizing & Load-Share

Total: **~6–9 weeks of effort**, shareable in parallel across three workstreams. Jomil's intent — not Liam on an island — is achievable because the workstreams are largely independent.

| # | Workstream | Contents | T-shirt / days | Suggested owner |
|---|---|---|---|---|
| **WS1** | **Rate data + governance** | Reload correct CurrencyType + DatedConversionRate for 7 currencies; identify & stop the job that wrote 1.0 on 2026-02-11/12/13; pick single rate source-of-truth; reconcile the static CMDT formulas vs platform rates; establish a maintained feed (the doc's claimed `ExchangeRateUpdateTrigger` does not exist). Auto-fixes 129 reports + 20 dashboards + UI. | **M, ~5–8d** (analysis-heavy, low code) | **Marc** (owns the V9/rate-context history; surfaced the reprice/context regressions) |
| **WS2** | **Pricing data + adjustment config** | Author 6 missing CMDT formula rows; backfill PBE for transacted products; add `CurrencyIsoCode` to `Attribute_Based_Adjustment_Decision_Table` + per-currency Override rows (13,072 base); non-USD `PricebookEntryDerivedPrice` (SC-3372 tie-in); audit `OrderMigrationService` $0 PBEs. | **L, ~8–12d** | **Nir** (peer-review owner on SC-3350/RLM pricing; AAMP/derived family) |
| **WS3** | **DocGen + decimal-correctness code** | Currency-scale helper reading `CurrencyType.DecimalPlaces`; retrofit ~17 Apex sites; fix 12 DocGen formulas + optional symbol map; `Corporate_Currency_Amount__c` formula; `QuoteRepricingController` `$` toast; retire dead config; JPY end-to-end render test. | **M–L, ~7–10d** | **Liam** (owns SC-3349/3350 description+prehook work, DocGen pipeline) |
| **WS4** | **Renewal currency + Q2O + Workday (cross-cutting)** | Standardize renewal currency source across the 3 flows; `Asset.PricingSource`; Order-side `Exchange_Rate_To_USD__c` writer; drive a non-USD order through to Workday; Mule `extendedAmount = NetUnitPrice×Qty`. | **M–L, ~6–10d** | **Shared** (Liam flows / Nir reprice / Marc Workday-context) |
| **External** | **Workday tenant currency setup** | Confirm 12 SF currencies are Accepted Currencies per customer/company + WD conversion rates defined. **Cannot be verified from Salesforce.** | M (blocking dependency) | **Workday/MuleSoft team** (not Fortra SF) |
| **Out of band** | **Certinia/PSA currency subsystem** | ~25 `pse__` VRs + Certinia revaluation/exchange-rate triggers + ~101 managed reports. Separate currency model. | M–L (scoping) | Defer / separate ticket |

**Sequencing:** WS1 first (unblocks reporting immediately and is a prerequisite for WS2's rate decisions). WS2 and WS3 run in parallel after the rate-source decision. WS4 needs WS1+WS2 outputs. Workday-external runs in parallel from day 1 (longest lead time).

---

## 7. Open Questions / Risks / Not-Verified

**Highest-risk unknowns:**
1. **Workday tenant currency config (external).** No non-USD order has ever reached WD Success, so the mandatory `Currency_Reference` / Accepted-Currency gates have never been exercised. The first real non-USD completion could be rejected purely on WD-side config. **Cannot be queried from Salesforce — confirm with Workday/MuleSoft team.**
2. **Who/what wrote 1.0 to the rate tables on 2026-02-11/12/13?** Rates were correct through Jan 2026 then reset. Until the writer is found and stopped, any reload will be re-corrupted. The doc's `ExchangeRateUpdateTrigger` does not exist, so the actual rate-maintenance owner is unknown.
3. **RLM platform fallback behavior on a missing same-currency adjustment row** was not traced live (read-only constraint). We confirmed the decision table has no currency key, so a USD Override *is matched* and applied — but a live reprice debug-log on a non-USD quote would confirm the exact magnitude behavior.

**Not verified / caveats:**
- **DocGen live render.** OmniProcess/OmniDataTransform not queryable via Tooling API here; relied on force-app metadata (synced SC-3335). A live JPY document generation would confirm the `689,400.00` hypothesis definitively.
- **MuleSoft DataWeave** is not in this repo (Mule-owned); `currencyID`/`extendedAmount` sourcing is inferred from the logged USD 00095381 payload.
- **Thin-currency intent.** JPY/CHF/NZD records are a 2026-05 migration batch with zero organic activity since. Whether they must transact again (renewals) vs are read-only archive flips WS2's PBE/rate effort from optional to required — **business decision needed.**
- **ILS/MXN/SEK/ARS** have 0 PBE and ~0 transactions but active rates/dated history — intended future currencies or stale activations? Business intent unknown; standing up coverage would be new capability, not remediation.
- **Certinia/PSA currency subsystem** (~101 managed reports, revaluation triggers) was inventoried but its internal currency handling not inspected — separate scoping question.
- The `Conversion_Rate__c=null` on the CMDT is a **red herring** (code reads `Conversion_Formula__c`, which is populated) — do not size effort against "null rates break conversion."

**Key artifacts:** `Data/sc3384/` (retrieve, report_risk.json, settings_out, mdapi V12); `docs/Fortra-Orders-MultiCurrency-Solution-Design-Doc.docx`; `Org Data/_src/classes/Fortra_CurrencyConversionService.cls`, `DatedConversionRateLookup.cls`, `Fortra_BulkPriceUpdateBatch.cls`; `Org Data/_src/objects/{Opportunity,Quote}/fields/Corporate_Currency_Amount__c.field-meta.xml`; `force-app/main/default/omniDataTransforms/DMTransformFortraQuote_1.rpt-meta.xml`.
