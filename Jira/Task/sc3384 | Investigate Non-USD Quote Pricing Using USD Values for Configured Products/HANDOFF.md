# SC-3384 — Handoff to Marc DeBrey

**From:** Liam Jeong · **Date:** 2026-06-11 · **State:** Read-only RCA complete (no DML/deploy). Ready to build.

## Start here (read order)
1. `02_ROOT_CAUSE_AND_FIX_SPEC.md` — **the engineering deliverable**: per-defect RCA, ordered fix spec, IDs, code locations, regression risks.
2. `03_CURRENCY_AUTHORITY_AND_RATES.md` — authoritative currency list + ARR rates + the 5/10/12 scope question.
3. `01_REPRO_GROUND_TRUTH.md` — live repro numbers + `evidence/docx_screenshots/`.
4. `10_ORG_WIDE_REACH_IMPACT_ASSESSMENT.md` — broader multi-currency reach (rates@1.0, reports, DocGen, Workday) — context only, not required for the fix.

## What's confirmed
On EUR quote `0Q0WC0000036xy90AA`, list prices are correct EUR but configured/derived prices come from USD. Unifying cause: **currency-blind lookups over USD-only supporting data.**

## The fix, by defect (what to actually do)

| # | SKU | Fix | Owner notes |
|---|-----|-----|-------------|
| 1 | `VM-BSL-RSL-BESEPB` | Add `CurrencyIsoCode` key to ABA decision table **+** seed EUR ABA rows | data+config, sequence together |
| 2 | `GS-GSE-NRPS-AAMP` | **Decide first:** remodel discount as a **percentage** (currency-neutral, also fixes SC-3360) — *preferred* — OR currency-key + per-currency flat rows | shares the SC-3360 matrix |
| 3 | `VM-VLM-NRSU-VMA` | **Seed EUR ABA Override rows only** (native engine already currency-aware) | pure data, simplest |
| 4 | `HRM-HRM-RSL-CLSAAS` | Add `CurrencyIsoCode` to `AttributeVolumePricingPrehook` SOQL + composite key **+** seed EUR `Attribute_Tier_Pricing_Storage__c` rows | data+code |
| 5 | `PIA-PIA-RNM-PIAMBK` | Add `CurrencyIsoCode = Quote.CurrencyIsoCode` to the auto-add PBE resolver (EUR PBE already exists) | **resolver not yet identified — see below** |

**Sequencing rule (non-negotiable):** for any line where you add a currency filter, EUR data must land **first or concurrently** — otherwise lines flip from "wrong USD number" to "reset to list / 0" (visible regression).

## 🔑 ID / code cheat-sheet
- **ABA decision table (no currency key, the bug):** `Attribute_Based_Adjustment_Decision_Table` = `0lDa50000007BEuEAM`
- **PBE decision table (HAS currency key, the good example):** `Price_Book_Entry_Decision_Table_v2` = `0lDa50000007BErEAM`
- **Attribute-tier matrix:** `Attribute_Tier_Pricing_Matrix` = `0lDWC0000000Gft2AE`
- **USD schedule hardcoded in the discount step:** `84Xa50000010nWQEAY`
- **Prehook (live):** `AttributeVolumePricingPrehook` = `01pWC000001wAzJYAU` → SOQL `cls:212-219`; composite key `cls:358-363`; also `buildTierLookupMap` 336-338, `lookupTierFromMap` 409
- **Supporting data (USD-only):** `AttributeBasedAdjustment` 13,072 rows · `Attribute_Tier_Pricing_Storage__c` 1,115 rows
- **PIAMBK PBEs:** EUR (correct) `01uWC000005wzX8YAI` · USD (wrongly picked) `01uWC000005wsbUYAQ`
- **Pricing procedure:** `Rev_Mgmt_Default_Pricing_Procedure` (active V9); discount step `AttributeDiscountEntries`
- **Auth currency doc:** `Currency+Conversion+for+Pricebooks.doc` (10 currencies; ARR rates are the corrected rate-fix values)

## ⚠️ Decisions needed before building (these block it)
1. **AAMP** — percentage vs per-currency flat? (drives Defect 2 + data scope)
2. **EUR values** — catalog-defined or FX-derived (USD × ARR rate)? (who supplies the load file)
3. **Currency scope** — 5 / 10 / 12? (MVP recommend **core 5 + JPY**; MXN/SEK not in the doc → deactivate)
4. **PIAMBK** — which automation inserts the maintenance line? Not a `ProductRelatedComponent` (0 rows); likely a managed RLM `ProductConfigurationRule` (302 exist) — needs a debug-log reprice trace to pin.

## ⚠️ Time-sensitive caveats / gotchas
- `Stamp_Maintenance_Pricing_Inputs` was **re-versioned today 2026-06-11T14:08:16Z** — re-retrieve before Family-B work.
- The **live ExpressionSetVersion** of the pricing procedure was NOT metadata-retrievable this session; the discount-step line refs come from the force-app copy (±2 lines). The **decision-table key WAS verified live** (authoritative). Re-confirm the version equals live before editing.
- **CLSAAS Net=0** is a *separate, currency-independent* downstream "Total Price"-mode step — not pinned to an exact element. Verify it persists/resolves after EUR data lands.
- Editing the active pricing procedure / decision-table key = **new ExpressionSet version + republish + re-sync `SalesTransactionContextExt_v2`** (in-place edits have caused gacks before). Version hard-delete is blocked; do NOT remove the `PricingActionParameters` bindings (`17gWC…AvYAK` Order / `17gWC…AwYAK` Quote).
- **SC-3360 shares the same ABA matrix** — coordinate to avoid double-changing it.
- Data loads: ABA is platform-managed (no Apex DML) — use REST/composite-key per the SC-3137 playbook.

## What I did NOT do
No DML, no deploy, no metadata change. PIAMBK resolver not identified. CLSAAS Net=0 element not pinned. Live procedure version not retrieved. Regression on USD/other currencies not run.
