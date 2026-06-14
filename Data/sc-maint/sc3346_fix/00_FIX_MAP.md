# SC-3346 Maintenance (Derived) Pricing — Fix Map (live-confirmed 2026-06-13)

Org FortraUAT · active pricing procedure **V14** (`9QMWC00000023eX4AQ`, sole active, re-confirmed live).
Constraints in force: **UAT only / no prod**; pricing-procedure edits **in-place on V14, no new versions** (snapshot-first, FIM-462 regression gate, user owns UI activate+resync); any UAT deploy/DML needs explicit go-ahead.

## Live canary state (queried this session)
| Quote | maint line | UnitPrice | **NetUnitPrice** | COLACalc (expected net) | ratio |
|---|---|---|---|---|---|
| 00781043 | ck6X4 | 0 | **0** | 67.38 | $0 (no contributor) |
| 00781053 | cy334 | 0 | **54.58** | 60.64 | **×0.9000** |
| 00781068 | dAaT4 | 0 | **60.64** | 67.38 | **×0.9000** (Accepted — do not disturb) |
| 00781084 | dEW24 | **67.38** | **60.64** | 67.38 | **×0.9000** |
| 00781109 | e2Sn4 | 0 | **60.64** | 67.38 | **×0.9000** |

**Key reframe vs dossier:** the renewal-maintenance commit defect is TWO mechanisms, not one. 4 of 5 canaries commit `COLA-net × 0.90` (a partner discount **double-applied**); only the lone no-contributor line commits `$0` (the "no priced node" case docs 11–13 chased). `00781084` proves the line IS a priced node: UnitPrice carries the correct 67.38, then a partner-margin layer takes it ×0.90 → 60.64.

## The 8 fails → 3 families
| Fail | Sev | Root cause (live-confirmed) | Fix location | Risk |
|---|---|---|---|---|
| RN-PARTNER-DD | HIGH | partner margin (`getMarginForProductType`→`calculateDiscountPrice`, 10%) re-applied on a COLA net that **already** subtracted `Prior_Partner_Discount__c` | Apex `PartnerNetPricePosthook` (or proc PartnerDiscount step) — **trace pins it** | **LOW–MED ✅** revertable |
| RN-COLA-COMMIT | CRIT | = RN-PARTNER-DD for 4/5 lines; = MAINT-ONLY for the 5th | (split) | — |
| MULTI-ASSET | HIGH | same ×0.90 on the maintenance leg (license leg fine) | same as RN-PARTNER-DD | same |
| RN-MULTIYEAR | HIGH | same ×0.90 (computed right, committed ×0.90) | same as RN-PARTNER-DD | same |
| MAINT-ONLY | CRIT | single maint line, no contributor on cart → not a priced node (`DerivedPricingAttribute` null) + MissingContributor → $0 | prehook seed + DPA hydrate / native config — **owner-gated, unproven (doc 13)** | HIGH |
| NB-DERIVED-TIER | HIGH (new) | V14 `DerivedPricingFormula` = `IF(Premier .30, Standard .20, Professional .20, ELSE 0)×Source_List_Price__c` — only 3 tiers; Basic/Premium/Express/Platinum → 0×SLP = **$0**. `Maintenance_Rate__mdt` has all 7 but the formula never reads it | V14 procedure IF-chain (add 4 tiers, in-place ritual) | MED |
| PBEDP-COVERAGE | HIGH | 3,279/3,453 derived PBEs (95%) have no `PriceBookEntryDerivedPrice` config | data (3,279 rows) | **SC-3372, out of SC-3346 scope** |
| ZERO-LIST-PBE | HIGH | all derived PBEs zero-list (UnitPrice=0) | data | **SC-3372** |

PARTIAL (config-integrity notes, low priority): DECOMP-SPLIT, MDT-RECORDS, NB-DERIVED-FORMULA (M-2 dead code), RN-COLA-RATES (SC-3350).

## Resolutions logged
- **MULTI-ASSET / renewal ×0.90 cluster** → prehook-seed fix PROVEN DEAD (engine owns derived-line price); owner-gated native-config/renewal-line-typing. See `01_MULTI_ASSET_RESOLUTION.md`.
- **DECOMP-SPLIT** → NOT a defect; works-as-designed (FORTRA-PRODUCT-018 Step 5 value-stamping, scenario's parent-FK premise was wrong). Reclassify PARTIAL→PASS; test green (0 fail). Do NOT add `Original_Order_Item__c` to maintenance lines (breaks Workday line-type flow). See `02_DECOMP_SPLIT_RESOLUTION.md`.
- **NB-DERIVED-FORMULA (M-2)** → functionally NOT a defect; live formula = tier×Source_List_Price__c (proven on a Base=0 line netting 3000), competing `DerivedPricingNewBusiness` is TRIPLY-inert dead code (MDT gate dead + no-op for renewals + resultIncluded=false). Functionally PASS. Cosmetic dead-code removal = V14 procedure edit, defer to SC-3404 V15 (scale-cache-fragile, zero functional benefit). See `03_NB_DERIVED_FORMULA_RESOLUTION.md`.

## Recommended fix order
1. **RN-PARTNER-DD ×0.90** — clears 4 of 5 renewal-commit lines (RN-COLA-COMMIT/MULTI-ASSET/RN-MULTIYEAR too). Apex, revertable, no procedure churn. Step 1 = non-destructive FINEST reprice of `00781084` to pin the exact ×0.90 write layer, then a scoped guard (exclude COLACalc-stamped renewal-maintenance from partner-margin), deploy `RunSpecifiedTests`, reprice-verify all 4 canaries → 67.38/60.64.
2. **NB-DERIVED-TIER** — extend the V14 tier IF-chain to all 7 tiers (in-place V14 ritual + FIM-462 regression).
3. **MAINT-ONLY $0** — owner-gated decisive prehook-seed+DPA-hydrate test (doc 13).
4. PBEDP/ZERO-LIST → **SC-3372** (separate ticket). PARTIAL items → cleanup.
