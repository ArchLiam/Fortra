# SC-3346 Maintenance (Derived) Pricing — E2E Test Executive Summary

## Run metadata

| Field | Value |
|---|---|
| Org | FortraUAT |
| Active pricing procedure | Rev_Mgmt_Default_Pricing_Procedure **V14** (ExpressionSet `9QLWC0000015cDl4AI`; sole-active ExpressionSetVersion `9QMWC00000023eX4AQ`; V1–V13 inactive) |
| Scope | **Functional pricing / quoting behavior** for SC-3346 Maintenance (Derived) Pricing |
| Excluded | Workday / MuleSoft integration (not exercised) |
| Date | 2026-06-14 |
| Method | Read-only SOQL / Tooling / metadata retrieve + non-destructive Force reprices (`pricingPref=Force`, `configurationMethod=Skip`) on Draft quotes only; protected Accepted quote 00781068 untouched throughout |
| Scenarios | 26 |

This report covers the as-built functional pricing behavior of SC-3346: auto-add of first-year maintenance, new-business derived pricing, renewal COLA pricing, order decomposition, the stamp/data flow, edge cases, partner pricing, the pricing mechanism/engine, and overall spec conformance.

---

## Verdict — functional readiness

**The SC-3346 maintenance-pricing architecture is sound and the core paths price correctly, but it is not yet fully ready: there is one functional defect cluster and two narrower defects that produce wrong committed prices on live renewal and minority-tier paths.**

What works (functionally proven live on V14):
- **Auto-add** of first-year maintenance fires correctly on every post-rule New quote and is correctly suppressed on Renewal quotes (no double-add).
- **New-business derived pricing** computes and commits exactly `tier × Source_List_Price__c` for the three handled tiers (Standard 0.20, Premier 0.30, Professional 0.20), via a single unambiguous live formula (the competing dead-code arm is gone).
- **Renewal COLA computation** is exact everywhere — `(Base − PriorPartner − PriorDisc) × (1 + COLA%/100)` reproduces the stamped `COLACalculatedPrice__c` to the cent on all canaries.
- **Renewal license/subscription legs** uplift and commit correctly.
- **Order decomposition** stamps the maintenance base (not the license base) correctly (B-6 holds), the **stamp flow** stamps all inputs correctly and re-fires on reprice, **Source_List_Price carry-forward** (M-4) copies faithfully, the **renewal COLA formula is ISNULL-guarded** (B-4), and **partner-rate selection by product type** (B-3) is correct.

What's left (functional defects):
1. **Renewal-maintenance commit defect (SC-3404 cluster)** — the correctly-computed COLA net (e.g. 67.38) is **not committed** on auto-added / QuoteAction-less derived renewal-maintenance lines; they commit `0`, `54.58`, or `60.64 = 67.38 × 0.90` (a partner double-discount). Only lines born with a `Renew` QuoteAction commit correctly. (RN-COLA-COMMIT-AUTOADD, RN-PARTNER-DD, MAINT-ONLY, MULTI-ASSET, M1-SDD, SDD-CONFORMANCE)
2. **Incomplete tier table (NB-DERIVED-TIER)** — the live new-business derived formula hard-codes only 3 of 7 tiers; Basic / Premium / Express / Expert / 'platinum' derive **$0** instead of `rate × Source_List_Price__c`.
3. **COLA rate grain (RN-COLA-RATES)** — category-grain rates are exact, but two spec'd per-solution exceptions (MessengerConsole 12.00%, SecureCare 4.70%) are not honored (structurally present, currently un-exercised on live lines).

The defects are isolated to identifiable paths and each has a clear, bounded fix direction (below). The computation layer is correct throughout; the failures are at the **commit layer** (renewal) and in **formula completeness** (tiers/grain).

---

## Results at a glance

| Status | Count |
|---|---|
| Pass | 15 |
| Fail | 5 |
| Partial | 5 |
| Out-of-scope | 1 |
| **Total** | **26** |

| ID | Domain | Title | Status | Severity |
|---|---|---|---|---|
| CFG-AUTOADD | Auto-add first-year maintenance | Auto-add first-year maintenance fires on perpetual add | pass | none |
| NB-DERIVED-NET | Derived (new-business) pricing | First-year maintenance derived NetUnitPrice value is correct (tier × Source_List_Price) | pass | none |
| NB-DERIVED-PREMIER | Derived (new-business) pricing | Premier tier (0.30) first-year maintenance prices correctly | pass | none |
| NB-DERIVED-TIER | Derived (new-business) pricing | 7-tier derived-maintenance rate fix is NOT live — only 3 of 7 tiers; minority tiers derive $0 | fail | high |
| NB-DERIVED-FORMULA | Derived (new-business) pricing | Single live new-business derived formula; competing Base_Price × tier arm removed (M-2) | pass | none |
| RN-COLA-MATH | Renewal COLA pricing | Renewal COLA net computed in-flight = (Base − priorPartner − priorDisc) × (1+COLA%) = 67.38 | pass | none |
| RN-COLA-COMMIT-RENEW | Renewal COLA pricing | Renewal-maint line born with QuoteAction=Renew commits correct 67.38 | pass | none |
| RN-COLA-COMMIT-AUTOADD | Renewal COLA pricing | Auto-added No-Change renewal-maint line commits 60.64 born-stale vs 67.38 | fail | high |
| RN-PARTNER-DD | Renewal COLA pricing | Partner discount double-applied on renewal maintenance (×0.90 = 60.64 instead of 67.38) | fail | high |
| RN-COLA-RATES | Renewal COLA pricing | Category COLA uplift applied correctly (BoKS 7.85); per-solution exceptions still wrong | partial | medium |
| RN-MULTIYEAR | Renewal COLA pricing | Multi-year / out-year / MyCAP COLA inert at commit layer; single-year only per SDD | out-of-scope | none |
| RN-LIC | Renewal pricing | Renewal license COLA uplift commits correctly | pass | none |
| RN-SUB | Renewal pricing | Renewal subscription (license) leg = list × (1 − partner discount) | pass | none |
| AMEND-PRICING | Renewal pricing | Amendment quote routes through new-business derived path; no COLA carry-forward | partial | medium |
| DECOMP-SPLIT | Order decomposition | Parent license → derived maintenance child (FK-split premise vs value-stamp as-built) | partial | medium |
| DECOMP-BASE | Order decomposition | B-6 maintenance OrderItem carries maintenance base (71) not license base (355) | pass | none |
| STAMP-FLOW | Stamp / data flow | Stamp_Maintenance_Pricing_Inputs stamps inputs correctly and re-fires on reprice | pass | none |
| SLP-CARRY | Stamp / data flow | Source_List_Price carry-forward Quote→Order (M-4) | pass | none |
| MAINT-ONLY | Edge cases | Maintenance-only renewal (no contributor) commit behavior | fail | high |
| MULTI-ASSET | Edge cases | Multi-asset renewal: license + maintenance both priced | fail | high |
| B3-PARTNER | Partner pricing | B-3: maintenance partner discount (12% New / 10% Renewal) vs 15% Software by product type | pass | none |
| B4-NULLGUARD | Renewal formula robustness | B-4: renewal COLA formula ISNULL-guarded (no null/0 leak) | pass | none |
| M1-SDD | Pricing mechanism | Prehook seeds COLACalc + posthook/handler net mechanism (M-1) | partial | high |
| M2-DEADCODE | Pricing mechanism | DerivedPricingNewBusiness dead arm removed; no mispricing path (M-2) | pass | none |
| PROC-V14 | Pricing engine | V14 active + derived/COLA elements present & correctly wired | pass | none |
| SDD-CONFORMANCE | Spec conformance | Build matches SC-3346 user story (single-year; tier × Source_List; COLA carry-forward) | partial | high |

---

## Domain detail

### Auto-add & derived new-business pricing

**CFG-AUTOADD — Auto-add first-year maintenance fires on perpetual add — PASS / none.**
- *Expected:* Adding a Perpetual license to a New quote auto-injects the matching first-year (New) maintenance SKU via an Active ProductConfigurationRule, gated to `QuoteTypeText__c='New'` so renewals get the Year-2 SKU instead.
- *Actual:* The auto-add is a Configurator-type ProductConfigurationRule (not a bundle — 0 ProductRelatedComponent rows under the perpetual). The BoKS Year-1 rule `14OWC0000022ULp2AM` (Active, seq 10) is criteria-gated `ItemProductCode='PIA-PIA-NRPS-PIAP' AND QuoteTypeText__c='New'` → AutoAdd target `01tWC00000DD1bsYAD` (PIA-PIA-RNM-PIAMBK, 'New Maintenance'). Companion Year-2 rule `14OWC0000022Eyb2AE` (Active, seq 20) is gated to `'Renewal'` and targets the Renewal Maintenance SKU — mutually exclusive gates, no double-add. Fires live: 23/23 post-rule New quotes co-created the maintenance line in the exact same second (most recent 2026-06-11T15:30:29). The 2 New quotes lacking the line predate the rule's 2026-04-24 creation; 28 Renewal quotes correctly suppressed. The 99-rule Year-1 / 98-rule Year-2 sets are all Active.
- *Evidence:* Year-1 rule definition decoded (criteria + AutoAdd action + target SKU); exact-second co-create on quotes `0Q0WC0000037rFZ0AY` / `0Q0WC0000037uLV0AY`; `Data/sc-maint/e2e_func/work/cfg-autoadd/`.

**NB-DERIVED-NET — First-year derived NetUnitPrice value correct (tier × Source_List_Price) — PASS / none.**
- *Expected:* New-business derived net = `tier × Source_List_Price__c`; Standard 0.20 × 355 = 71.00, committed and stable.
- *Actual:* On Draft New quote 00781057, all 9 active Standard-tier New-Maintenance lines (PIA-PIA-RNM-PIAMBK) commit `NetUnitPrice=71`, `Source_List_Price__c=355`. A fresh Force reprice held all 9 at 71 (LastModified advanced to 14:38:52Z, non-destructive 32→32). Contributing license lines price at catalog 355, so the full chain works end-to-end. The one null-net line is `Quantity=0` (inactive), not a defect.
- *Evidence:* MTD attribute 'Standard' confirmed on tested lines; live V14 `DerivedPricingFormula` reads `IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,0))) * Source_List_Price__c`; `Data/sc-maint/e2e_func/work/nb-derived-net/`.

**NB-DERIVED-PREMIER — Premier tier (0.30) prices correctly — PASS / none.**
- *Expected:* Premier-tier derived net = `0.30 × Source_List_Price__c`; for SLP=10000, NetUnitPrice = 3000.00.
- *Actual:* Premier canary line `0QLWC000003cL1i4AE` (GS-GSE-RNM-EFT8, MTD='Premier'): `Source_List_Price__c=10000`, `Base_Price__c=0`, committed `NetUnitPrice=3000` (= 0.30 × 10000 exact). Because Base_Price=0, a Base_Price × tier formula would have produced $0 — the 3000 result proves Source_List_Price is the live input and the Premier 0.30 branch resolves. Held under a fresh Force reprice (LastModified 04:53:57 → 14:39:30). FINEST log `07LWC00000OyWYf2AN` confirms the line entered pricing carrying Maintenance_Type_Defn='Premier'.
- *Evidence:* Sibling Premier line with SLP=0 → Net=0 cleanly isolates that, given a stamped source, the rate resolves; `Data/sc-maint/e2e_func/work/nb-derived-premier/`.

**NB-DERIVED-TIER — 7-tier fix NOT live; minority tiers derive $0 — FAIL / high.** *(See Critical findings.)*

**NB-DERIVED-FORMULA — Single live derived formula; M-2 dead code removed — PASS / none.**
- *Expected:* Exactly one live new-business derived formula (`DerivedPricingFormula` = tier × Source_List_Price), with the competing `DerivedPricingNewBusiness` (Base_Price × tier, gated by the nonexistent code 'MDT') gone from the active version.
- *Actual:* In the active V14 block, `DerivedPricingNewBusiness` appears 0 times (the 5 file-wide occurrences are all in inactive versions); the only live new-business maintenance-tier formula is `DerivedPricingFormula` (Source_List_Price × tier). The gate code 'MDT' still does not exist (`AttributeDefinition` returns only 'MTD'). Empirically confirmed by the Premier Base=0 → 3000 discriminator under a fresh reprice, plus corroborating handled-tier lines (355→71, 275000→55000).
- *Evidence:* Whole-file grep of the active block; `Data/sc-maint/e2e_func/work/nb-derived-formula/`.

### Renewal COLA pricing

**RN-COLA-MATH — In-flight COLA net computed correctly = 67.38 — PASS / none.**
- *Expected:* COLA net = `(Base − PriorPartner − PriorDisc) × (1 + COLA%/100)`, HALF_UP; canary 67.38, discretionary variant 60.64.
- *Actual:* The computation reproduces the stamped `COLACalculatedPrice__c` exactly on all 4 canary lines: 67.38 (priorPartner-only) and 60.64 (priorDisc=6.25). Uniform inputs (Base 71, PriorPartner 8.52, COLA% 7.85). Re-fired live under a fresh Force reprice (LastModified 13:54:10 → 14:37:10, re-stamped 67.38). COLA% input validated against `COLA_Uplift_Rules__mdt` Powertech_IAM_BoKS (7.85). The downstream commit is tested separately.
- *Evidence:* Python Decimal HALF_UP re-derivation; `Data/sc-maint/e2e_func/work/rn-cola-math/`.

**RN-COLA-COMMIT-RENEW — Line born with Renew QuoteAction commits correct 67.38 — PASS / none.**
- *Expected:* A renewal-maintenance line born carrying `QuoteAction.Type='Renew'` commits NetUnitPrice = the COLA net = 67.38, with consistent rollups.
- *Actual:* On quote 00781084, line `0QLWC000003dEW24AM` carries `QuoteActionId=7ocWC00000u7yf8YAA` (Type='Renew') and commits `UnitPrice=NetUnitPrice=NetTotalPrice=Subtotal=TotalLineAmount=67.38`. Reproducible under a fresh Force reprice (COLA_Applied_Date 14:34:30 → 14:37:33). The sibling QuoteAction-less line on 00781109 commits 60.64 — proving the Renew QuoteAction routes the line to a writable priced node. This is the working creation path.
- *Evidence:* `Data/sc-maint/e2e_func/work/rn-cola-commit-renew/`.

**RN-COLA-COMMIT-AUTOADD — Auto-added No-Change line commits 60.64 born-stale — FAIL / high.** *(See Critical findings.)*

**RN-PARTNER-DD — Partner discount double-applied (×0.90 = 60.64 instead of 67.38) — FAIL / high.** *(See Critical findings.)*

**RN-COLA-RATES — Category rate correct; per-solution exceptions wrong — PARTIAL / medium.**
- *Expected:* COLA% sourced by matching the product to the rule store; spec keys rates at SOLUTION-NAME grain with two per-solution exceptions (MessengerConsole 12.00%, SecureCare 4.70%) overriding the category default; BoKS canary 7.85.
- *Actual:* Core behavior PASSES — the category-grain rate is looked up and applied correctly (BoKS 7.85 → 67.38, re-stamped under a fresh reprice), and all 21 live category-default rates match the spec to the cent. The residual functional gap: the live lookup is **category-grain** (`COLAUpliftPrehook` reads `Solution_Category__c`, never `Solution__c`), so the two spec'd per-solution exceptions are not honored — MessengerConsole would apply 7.85 vs 12.00 (under by 4.15 pts across 24 active products), SecureCare 7.85 vs 4.70 (over by 3.15 pts across 2). Structurally present but currently un-exercised: 0 live QLIs for those solutions carry a COLA% stamp, so no live line is mis-priced today. Fix requires a business/design decision (SC-3350 D1).
- *Evidence:* `COLAUpliftPrehook` indexOf shows `Solution__c` never referenced; 0 per-solution override rows; `Data/sc-maint/e2e_func/work/rn-cola-rates/`.

**RN-MULTIYEAR — Multi-year/out-year/MyCAP inert; single-year per SDD — OUT-OF-SCOPE / none.**
- *Expected:* Both SDDs scope renewal COLA as single-year/annual. The question is whether the out-year/MyCAP path actually computes/commits a distinct price (an in-scope priced feature with a commit defect) or is inert (only a Deal-Desk flag).
- *Actual:* Genuinely inert at the pricing/commit layer. The live V14 procedure has zero references to multi-year logic (outyear/mycap/final_year all 0; single-year `COLA_Uplift_Percent` appears 21×). The prehook reads `COLA_Outyear_Uplift_Percent__c` only into the `outyearBelowMin` approval decision; it is never assigned to `targetUplift`. `COLA_Outyear_Uplift_Percent__c` is populated on only 15 of 1,223,413 QLIs (none Renewal Maintenance), and arithmetic on those lines proves the committed value tracks year-1 COLA, not out-year. MyCAP's sole side effect is `Quote.Mycap__c`. No required multi-year pricing behavior to validate; if the business later scopes it in, it is a new feature build, not a fix.
- *Evidence:* `Data/sc-maint/e2e_func/work/rn-multiyear/`.

### Renewal pricing (license / subscription / amendment)

**RN-LIC — Renewal license COLA uplift commits correctly — PASS / none.**
- *Expected:* Renewal license/subscription line (carrying a 'Renew' QuoteAction) commits a COLA-uplifted price = `SourceAsset.Price × (1 + COLA%/100)`, persisting through reprice with partner discount layered on top.
- *Actual:* These lines are priced at creation by `COLAUpliftHandler.populateCOLAFields` onto a normally-priced node, so they commit and persist. Canary beSECURE (00781053): asset 5101.22 × 1.062 = `UnitPrice 5417.50`, 18% partner → `NetUnitPrice 4442.35`. Held under a fresh Force reprice (COLA_Applied_Date 14:46:22 → 14:48:01). Breadth: across a 25-line sample, `UnitPrice = Pre_COLA_Price × (1+COLA%/100)` holds in every case across all four COLA sources (CMDT Lookup, Contract Override, Line Override, MyCAP Default). Apparent "mismatches" are full-precision exact values vs 2-decimal display.
- *Evidence:* `Data/sc-maint/e2e_func/work/rn-lic/`.

**RN-SUB — Renewal subscription leg = list × (1 − partner discount) — PASS / none.**
- *Expected:* The subscription/license leg commits a correct net via the standard priced-node path (list minus partner factor), carried by a 'Renew' QuoteAction.
- *Actual:* Two canaries verified after fresh reprices: beSECURE commits `NetUnitPrice 4442.35 = 5417.50 × 0.82`; RPA-AUD-RSS-AUPS commits `2674.85` (undiscounted) with consistent NetTotalPrice. A real priced node, so it commits cleanly. The ~10,671 Net=0/null renewal subscription lines are stale pre-V14 quotes never repriced (one created 2022-09-02), confirmed by the two live reprices producing correct nets — not a behavior defect.
- *Evidence:* `Data/sc-maint/e2e_func/work/rn-sub/`.

**AMEND-PRICING — Amendment routes through new-business derived path — PARTIAL / medium.**
- *Expected:* On an Amendment-type quote, COLA carry-forward must NOT apply, and a derived maintenance line should price through the new-business derived path (`tier × Source_List_Price`), committing non-zero when the contributor is resolved.
- *Actual:* The mechanism is correct by design: the only V14 quote-type discriminator is 'Renewal' vs not-'Renewal' (`DerivedProductsNonRenewal` gate), so Amendment routes through the new-business path exactly like 'New' — NOT into the broken renewal-COLA cluster. COLA carry-forward is correctly suppressed (`COLAUpliftPrehook` gates on `QuoteTypeText__c='Renewal'`; FINEST log `07LWC00000OyWon2AF` shows 'Found 0 renewal QLIs from 19 total', zero COLA overrides). The shortcoming: on the live amendment quote, the 4 derived New-Maintenance lines committed `NetUnitPrice=null` because they inherit the new-business derived path's own gaps (null Source_List_Price + 26 MissingContributor markers) — the routing/gating is correct, but the lines price only as well as the shared new-business derived path does on the available data. No amendment-specific defect.
- *Evidence:* `Data/sc-maint/e2e_func/work/amend/`.

### Order decomposition

**DECOMP-SPLIT — Parent license → derived maintenance child (FK-split) — PARTIAL / medium.**
- *Expected:* Decomposition produces a derived maintenance child OrderItem linked to the parent license via `Original_Order_Item__c`, stamped `Base_Price__c = license source list × tier rate`.
- *Actual:* The FK-split decomposition model in the scenario premise does not exist in SC-3346 — but the decomposition feature works correctly via a different mechanism (value-stamping on a self-contained maintenance SKU). `MaintenanceOrderDecompositionService` references `Original_Order_Item__c` 0 times; it derives `maintenanceBase = sourceBase × tierRate` from the maintenance line's own QLI and stamps it. Of 40 OrderItems carrying `Original_Order_Item__c`, all 40 are same-product quantity-splits (the PowerOrderSplittingService FK, SC-3210/3368), 0 license-to-maintenance. Of 19,844 maintenance OrderItems, 0 carry the FK. B-6 holds (16/16 carry the maintenance base, 0 license-base leaks). Premise/design mismatch, not a value defect.
- *Evidence:* Order 00095427 shows the license and maintenance OIs as two independent records with no link field; `Data/sc-maint/e2e_func/work/decomp-split/`.

**DECOMP-BASE — B-6 maintenance base (71) not license base (355) — PASS / none.**
- *Expected:* The maintenance OrderItem.Base_Price__c carries the maintenance base (license source list × tier), never the raw license base; no row has `Base == Source_List_Price`.
- *Actual:* `MaintenanceOrderDecompositionService` computes `maintenanceBase = (sourceBase × tierRate).setScale(2,HALF_UP)` and stamps the result. Regression query: 0 maintenance OIs with `Base=355 AND SLP=355`; all 16 live maintenance OIs with Base>0 have Base/SLP ratio 0.20, 0 license-base leaks. Two chains proven end-to-end: PIAMBK 355→71; Automate Ultimate 275000→55000. The lone Renewal-Maintenance OI carries the correct Base=71 (its NetUnitPrice issue is the separate renewal-commit defect).
- *Evidence:* `Data/sc-maint/e2e_func/work/decomp-base/`.

### Stamp / data flow

**STAMP-FLOW — Stamp_Maintenance_Pricing_Inputs stamps inputs correctly and re-fires on reprice — PASS / none.**
- *Expected:* The before-save QLI flow (V13, RecordBeforeSave/CreateAndUpdate) stamps Base_Price, priors, COLA%, Fortra_Product_Type, and `COLACalculatedPrice__c = (Base − PriorPartner − PriorDisc) × (1+COLA%/100)`; new-business Base = source license pre-partner price.
- *Actual:* All stamps exact on 4/4 renewal canaries (COLACalc 67.38 / 60.64) plus the new-business canary (Base 355 = source Pre_Partner_Price 355). Flow formulas match the canonical contract (`ComputedRenewalColaNet`, `ResolvedLicenseSourceBase = Pre_Partner_Price else ListPrice else UnitPrice`). Re-fires on a fresh non-destructive reprice (LastModified advanced, line count unchanged). The downstream committed-net defect is separate; `COLACalculatedPrice__c` carries the correct value on every line, which is what this flow owns.
- *Evidence:* `Data/sc-maint/e2e_func/work/stamp-flow/`.

**SLP-CARRY — Source_List_Price carry-forward Quote→Order (M-4) — PASS / none.**
- *Expected:* On Quote→Order conversion, `QuoteToOrderFieldMapper` copies each maintenance QLI's `Source_List_Price__c` onto the matching OrderItem; every QLI-linked maintenance OI's SLP must equal its source QLI's SLP across all values.
- *Actual:* The live deployed class has the SLP-carry mapping active at both the copy loop and the merge-preserve; the supporting decomposition-service query selects the field on both sides (no silent runtime null). A join over all 23 QLI-linked maintenance OIs with SLP set returned 23 MATCH / 0 mismatch / 0 QLI-null, across 6 distinct prices ({33, 325, 355, 2008, 34750, 275000}) — value-agnostic. The inverse check (QLI has SLP but OI null) = 0 org-wide; the 5 null-OI cases have a source QLI whose SLP is also null (nothing to carry). The dedicated runtime behavior test passes.
- *Evidence:* `Data/sc-maint/e2e_func/work/slp-carry/`.

### Edge cases

**MAINT-ONLY — Maintenance-only renewal (no contributor) — FAIL / high.** *(See Critical findings.)*
- Part (a) MissingContributor handling = **PASS / graceful** (CompletedWithPricing, isSuccess:true, non-blocking). Part (b) commit = **FAIL**: the canary commits `UnitPrice=67.38` (the $0-commit sub-defect is resolved via a seeded InputUnitPrice) but `NetUnitPrice=60.64 = 67.38 × 0.90`, propagating to the Quote GrandTotal. Engine-owned / born-stale; a fresh reprice did not move it.

**MULTI-ASSET — Multi-asset renewal: license + maintenance both priced — FAIL / high.** *(See Critical findings.)*
- Split outcome: the license/subscription leg renews **correctly** (beSECURE 4442.35 = 5417.50 × 0.82, carries a 'Renew' QuoteAction); the renewal-maintenance leg **mis-commits** (PIA-PIA-RRM-PIAM: COLACalc 60.64 correct, committed `NetUnitPrice=54.58 = 60.64 × 0.90`, UnitPrice=0, QuoteActionId=null). Quote GrandTotal 4496.93 vs correct 4502.99. Same renewal-commit mechanism, isolated to the derived maintenance leg.

### Partner pricing

**B3-PARTNER — Partner discount selected by product type (12% New / 10% Renewal vs 15% Software) — PASS / none.**
- *Expected:* The partner-discount margin is selected by the line's product type (Software/Perpetual → 15%, New-Maintenance → 12%, Renewal-Maintenance → 10%), even when the line-level Fortra_Product_Type is null (resolved from Product2).
- *Actual:* Proven by a fresh live reprice on partner Discount quote Q-Maint 3: the Perpetual line committed `PartnerDiscountPercent=15`, NetUnitPrice 355→301.75; the New-Maintenance line committed `12` (NOT 15). FINEST log `07LWC00000OyUwg2AF` shows '...New Maintenance → PartnerDiscountPercent 12.00%' vs perpetual '15.00% Discount'. The fix mechanism is intact (`PartnerPricingService.resolveProductType` falls QLI→Product2→'Software'; the posthook pre-populates the product-type map before the resolution loop). The Product2 fallback is load-bearing: 61,312 maintenance QLIs carry a null line-level type. Honest caveat: 9 lines mis-stamped line-level 'Software' resolve to 15% — a data-typing condition outside this functional scope; the fix rescues the dominant null cohort.
- *Evidence:* `Data/sc-maint/e2e_func/work/b3-partner/`.

### Pricing mechanism & engine

**B4-NULLGUARD — Renewal COLA formula ISNULL-guarded — PASS / none.**
- *Expected:* The active V14 `DerivedPricingRenewals` formula wraps all 4 renewal carry-forward operands in `IF(ISNULL(...),0,...)` so a null operand computes a valid number, not null/garbage; ISNULL (not BLANKVALUE/NULLVALUE/ISBLANK).
- *Actual:* The active V14 formula carries all 4 ISNULL guards; all 5 inactive predecessors (V9–V13) carry the unguarded form (0 ISNULL each). Function choice correct (ISNULL 20× in-file; BLANKVALUE/NULLVALUE/ISBLANK = 0). Live proof: a Force reprice of an all-null renewal quote (`0Q0WC000002A7Wv0AK`) returned isSuccess:true and yielded `COLACalculatedPrice__c=0` (clean numeric) on all 5 lines; the populated canary held 67.38 exactly. The $0/×0.90 committed-net behavior is the separate commit defect, not a B-4 regression.
- *Evidence:* `Data/sc-maint/e2e_func/work/b4-nullguard/`.

**M1-SDD — Prehook seeds COLACalc + posthook/handler net mechanism (M-1) — PARTIAL / high.** *(See Critical findings.)*
- Half 1 (prehook seeds `COLACalculatedPrice__c`) **works** — fires and seeds 67.38. Half 2 (posthook/handler net mechanism) **computes and submits the correct override** (no ×0.90 in code) but does **not land** on QuoteAction-less derived nodes: the canary commits the wrong 60.64. Positive control (00781084, Renew QuoteAction) lands 67.38. The mechanism is correctly built but does not persist the corrected net on every renewal-maint line.

**M2-DEADCODE — DerivedPricingNewBusiness dead arm removed — PASS / none.**
- *Expected:* Exactly one live new-business derived-net formula; the competing `DerivedPricingNewBusiness` (Base_Price × tier, 'MDT' gate) removed; no mispricing path.
- *Actual:* The dead arm is gone from the active V14 block (0 occurrences; all 5 file-wide occurrences are in inactive V9–V13). One live new-business tier IF-chain remains, multiplying `Source_List_Price__c` (not Base_Price). The only residual is a cosmetic, permanently-false 'MDT' filter criterion OR'd with two live admitting branches — it can only fail to add lines, never suppress them, so it is not a mispricing path. End-to-end clean: a fresh reprice of canary 00781057 re-committed the derived lines at 71 = 0.20 × 355.
- *Evidence:* `Data/sc-maint/e2e_func/work/m2-deadcode/`.

**PROC-V14 — V14 active + derived/COLA elements present & correctly wired — PASS / none.**
- *Expected:* V14 is the sole active version; all SC-3346 derived/COLA/partner elements present and wired to documented inputs/outputs/gates; M-2 dead code removed; engine reprices and commits correctly.
- *Actual:* Exactly one `<status>Active</status>` block = V14. All 11 documented elements present with the expected actionType/resultIncluded/parentStep wiring (PriceBookEntries, DerivedProductsRenewals committer behind the DerivedProductsNonRenewal gate, DerivedPricingFormula, DerivedPricingRenewals, COLAUpliftonRenewalNet, PartnerDiscount elements, etc.). Formula bodies match the documented V14 form. M-2 confirmed removed. Engine live: a Force reprice re-committed the derived Standard lines at 71. The `resultIncluded=false` on the COLA elements is the documented intended wiring (its downstream commit consequence is owned by RN-COLA-COMMIT).
- *Evidence:* `Data/sc-maint/e2e_func/work/proc-v14/`.

### Spec conformance

**SDD-CONFORMANCE — Build matches SC-3346 user story — PARTIAL / high.**
- *Expected:* Conformance on all three pillars: (1) single-year only; (2) first-year = `tier × Source_List_Price` for every tier; (3) renewal = COLA carry-forward, committed to NetUnitPrice on every renewal-maintenance line.
- *Actual:* Structure and intent conform on all three pillars and the canonical canary computes correctly: scope is single-year (zero out-year/MyCAP wiring; multi-year inert); the first-year formula is exactly `tier × Source_List_Price` (0.20 × 355 = 71 live); the renewal COLA formula is byte-identical to the canonical form and computes 67.38 into `COLACalculatedPrice__c`. Two value/commit-layer gaps prevent a full pass: (1) the first-year tier formula resolves only 3 of 7 tiers (NB-DERIVED-TIER); (2) the renewal COLA net commits only on 'Renew'-QuoteAction lines — the 3 QuoteAction-less canary lines commit 0 / 54.58 / 60.64 vs expected 67.38 / 60.64 (RN-COLA-COMMIT + RN-PARTNER-DD). The spec's architecture is faithfully implemented and single-year-correct; end-to-end conformance awaits the two fixes.
- *Evidence:* renewal canary cross-tab; `Data/sc-maint/e2e_func/work/sdd-conformance/canary.json`.

---

## Critical findings (high severity)

All high-severity findings are functional pricing-correctness defects that commit a wrong price on a live path. There are two root defects (a renewal-commit cluster and an incomplete tier table); the remaining high-severity scenarios are the same renewal-commit defect surfacing in different carts.

### 1. Renewal-maintenance commit defect — correct COLA net not committed on QuoteAction-less derived lines
**Scenarios:** RN-COLA-COMMIT-AUTOADD, RN-PARTNER-DD, MAINT-ONLY, MULTI-ASSET, M1-SDD (partial), SDD-CONFORMANCE (partial). (The SC-3404 renewal-commit cluster.)

**Mechanism (proven by FINEST logs `07LWC00000OyWbt2AF`, `07LWC00000OyWVR2A3`, `07LWC00000OyWnB2AV`, `07LWC00000OyWX42AN`):**
- The prehook computes the correct COLA net (67.38) and seeds `COLACalculatedPrice__c`.
- A renewal-maintenance line born **without** a linked `Renew` QuoteAction is a derived / zero-list **unpriced node** (`ItemIsDerived__std=true`, `ListPrice=0`). The renewal-QLI seed gate logs "Found 0 renewal QLIs from N total".
- The line is **born stale** at `60.64 = 67.38 × 0.90` — a flat ~10% Renewal_Maintenance partner margin re-applied even though the prior 12% partner discount ($8.52) is already netted into the COLA base. (Discretionary variant: `54.58 = 60.64 × 0.90`; some lines land `$0`.)
- The posthook **actively emits** the correct override (`Net=67.38`) via `updateContextAttributes`, but on a derived/zero-list/QuoteAction-null node the write is a **silent no-op** — the engine-owned NetUnitPrice is not writable post-creation. A fresh Force reprice does **not** correct it (value immutable). The wrong net propagates into NetTotalPrice/Subtotal/TotalLineAmount and the Quote GrandTotal/TCV.
- **Differentiator proven:** the only canary line that commits the correct 67.38 is `0QLWC000003dEW24AM` (00781084), which carries `QuoteAction.Type='Renew'` and routes to a writable priced node. The determinant is the line being **born linked** to a Renew action, not merely the quote having one (quote 00781053 has a Renew action but its maintenance line is not linked → still wrong 54.58).

**Severity high (not critical):** the correctly-actioned creation path commits 67.38, so it is not 100% of renewal-maintenance lines; the computation is correct everywhere.

**Fix direction — creation-path (lower-risk lever):** ensure every renewal-maintenance line is **born linked to a `Renew` QuoteAction** so it routes to a writable priced node where the engine commits the COLA net — OR a cohort-scoped procedure / native-PBEDP redesign for QuoteAction-less derived renewal lines. The fix is on the creation path; it is not reprice-fixable.

### 2. Incomplete derived-maintenance tier table — only 3 of 7 tiers handled; minority tiers derive $0
**Scenario:** NB-DERIVED-TIER (fail/high), reflected in SDD-CONFORMANCE.

**Mechanism:** The active V14 `DerivedPricingFormula` hard-codes a 3-branch IF-chain:
`IF(AttributeValue='Premier',0.30,IF('Standard',0.20,IF('Professional',0.20,0))) * Source_List_Price__c`.
Only Premier / Standard / Professional resolve a rate; the else branch = 0. So **Basic (0.15), Premium (0.24), Express (0.30), Expert (0.35)** and the orphan picklist value **'platinum'** all resolve to 0 and derive **$0** instead of `rate × Source_List_Price`. `Maintenance_Rate__mdt` (the 7-row CMDT with the correct rates) is referenced **0 times** in the procedure, so it is decorative for this path and can silently drift. The 3 dominant tiers (~99.6% of live MTD attributes) price correctly (positive control Standard 0.20 × 355 = 71, re-proven under a fresh reprice); 207 live MTD attribute rows are on the unhandled minority tiers.

**Fix direction — tier-table completion:** extend the IF-chain to resolve all 7 tiers (Basic 0.15 / Professional 0.20 / Standard 0.20 / Premium 0.24 / Express 0.30 / Premier 0.30 / Expert 0.35), ideally re-keyed off `Maintenance_Rate__mdt` so the formula and the CMDT cannot drift.

---

## Recommendations / next actions (ordered, functional)

1. **Fix the renewal-maintenance commit (Critical finding 1).** Prefer the creation-path lever: born-link every renewal-maintenance line to a `Renew` QuoteAction so it routes to a writable priced node and the correct COLA net (67.38) commits. This single fix closes RN-COLA-COMMIT-AUTOADD, RN-PARTNER-DD, MAINT-ONLY part (b), MULTI-ASSET maintenance leg, the M1-SDD commit half, and the renewal pillar of SDD-CONFORMANCE.
2. **Complete the derived-maintenance tier table (Critical finding 2).** Extend `DerivedPricingFormula` to all 7 tiers (re-keyed off `Maintenance_Rate__mdt`), so Basic/Premium/Express/Expert/'platinum' derive `rate × Source_List_Price` instead of $0. Closes NB-DERIVED-TIER and the first-year pillar of SDD-CONFORMANCE.
3. **Decide and implement the COLA rate grain (RN-COLA-RATES).** A business/design decision (SC-3350 D1) is needed on the two per-solution exceptions (MessengerConsole 12.00%, SecureCare 4.70%). If confirmed, add per-solution override rows and re-key the `COLAUpliftPrehook` lookup from `Solution_Category__c` to `Solution__c`. Currently un-exercised (no live line mis-priced), so it is lower urgency than 1–2.
4. **Reconcile the decomposition design doc (DECOMP-SPLIT).** The as-built decomposition is value-stamping on a self-contained maintenance SKU, not the `Original_Order_Item__c` FK-split the premise describes. The arithmetic is correct (B-6 holds); this is a documentation/SDD reconciliation, nothing to fix in pricing behavior.
5. **No action required** for the passing paths (auto-add, new-business handled-tier pricing, renewal license/subscription legs, stamp flow, SLP carry-forward, B-3 partner-rate selection, B-4 null guard, M-2 dead-code removal, V14 wiring) — re-verify after fixes 1–2 land to confirm no regression on the working creation path.
6. **Multi-year/out-year/MyCAP (RN-MULTIYEAR)** is out of scope per both single-year SDDs and is inert at the commit layer. If the business later scopes it in, treat it as a new feature build, not a fix.

---

## Appendix

### Formulas

**New-business derived maintenance net (live V14 `DerivedPricingFormula`, output NetUnitPrice):**
```
IF(AttributeValue='Premier', 0.30,
   IF(AttributeValue='Standard', 0.20,
      IF(AttributeValue='Professional', 0.20, 0))) * Source_List_Price__c
```
(else-branch 0 → minority tiers derive $0; canonical handled-tier: Standard 0.20 × 355 = **71.00**)

**Renewal COLA carry-forward (live V14 `DerivedPricingRenewals`, ISNULL-guarded, output NetUnitPrice):**
```
IF(QuoteTypeText__c='Renewal',
   IF(COLACalculatedPrice__c > 0, COLACalculatedPrice__c,
      (IF(ISNULL(Base_Price__c),0,Base_Price__c)
       - IF(ISNULL(Prior_Partner_Discount__c),0,Prior_Partner_Discount__c)
       - IF(ISNULL(Prior_Discretionary_Discount__c),0,Prior_Discretionary_Discount__c))
      * (1 + (IF(ISNULL(COLA_Uplift_Percent__c),0,COLA_Uplift_Percent__c)/100))),
   NetUnitPrice)
```
Canary: `(71 − 8.52 − 0) × 1.0785 = 67.38`; discretionary variant: `(71 − 8.52 − 6.25) × 1.0785 = 60.64`.
Born-stale defect: committed `60.64 = 67.38 × 0.90`; discretionary `54.58 = 60.64 × 0.90`.

**Renewal license/subscription COLA uplift (`COLAUpliftHandler`):** `UnitPrice = SourceAsset.Price × (1 + COLA%/100)`; partner discount layered → NetUnitPrice. Canary: `5101.22 × 1.062 = 5417.50`, 18% off → `4442.35`.

**Order decomposition (`MaintenanceOrderDecompositionService`):** `maintenanceBase = (sourceBase × tierRate).setScale(2, HALF_UP)` → OrderItem.Base_Price__c (e.g. `355 × 0.20 = 71`; `275000 × 0.20 = 55000`).

**Maintenance rate tiers (`Maintenance_Rate__mdt`, 7 rows):** Basic 0.15 · Professional 0.20 · Standard 0.20 · Premium 0.24 · Express 0.30 · Premier 0.30 · Expert 0.35.

### Key IDs

| Entity | ID / value |
|---|---|
| Active pricing procedure ExpressionSet | `9QLWC0000015cDl4AI` (Rev_Mgmt_Default_Pricing_Procedure) |
| Active ExpressionSetVersion (V14) | `9QMWC00000023eX4AQ` (VersionNumber 14, sole active) |
| BoKS perpetual (canary) | `01tWC00000DD1btYAD` — PIA-PIA-NRPS-PIAP |
| BoKS New-Maintenance | `01tWC00000DD1bsYAD` — PIA-PIA-RNM-PIAMBK |
| BoKS Renewal-Maintenance | `01tWC00000DD1buYAD` — PIA-PIA-RRM-PIAM |
| Year-1 auto-add rule | `14OWC0000022ULp2AM` (Active, seq 10, gate `'New'`) |
| Year-2 auto-add rule | `14OWC0000022Eyb2AE` (Active, seq 20, gate `'Renewal'`) |
| MTD AttributeDefinition (Maintenance_Type_Defn) | `0tjWC000000096bYAA` (Code 'MTD'; 'MDT' = 0 rows) |
| COLAUpliftPrehook | `01pWC000001wNGbYAM` |
| PartnerNetPricePosthook | `01pWC000002VmiLYAS` |
| PartnerPricingService | `01pWC000001wAzPYAU` |
| COLAUpliftHandler | (live, renewal-license creation-path pricer) |
| MaintenanceOrderDecompositionService | `01pWC000002W5rRYAS` |
| QuoteToOrderFieldMapper (M-4) | `01pWC000002IuvRYAS` |
| Stamp_Maintenance_Pricing_Inputs | `301WC00000kgtSIYAY` (V13 Active) |
| Renewal canary quotes (Draft) | 00781043 / 00781053 / 00781084 (Renew-actioned, commits 67.38) / 00781109 (canary, commits 60.64) |
| New-business canary quote | 00781057 (`0Q0WC0000037rFZ0AY`); Premier canary 00780977 |
| Protected quote (untouched) | 00781068 (Accepted) |

### Work artifacts
All per-scenario evidence under `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func/work/` (subfolders: `cfg-autoadd`, `nb-derived-net`, `nb-derived-premier`, `nb-derived-tier`, `nb-derived-formula`, `rn-cola-math`, `rn-cola-commit-renew`, `rn-cola-commit-autoadd`, `rn-partner-dd`, `rn-cola-rates`, `rn-multiyear`, `rn-lic`, `rn-sub`, `amend`, `decomp-split`, `decomp-base`, `stamp-flow`, `slp-carry`, `maint-only`, `multi-asset`, `b3-partner`, `b4-nullguard`, `m1-sdd`, `m2-deadcode`, `proc-v14`, `sdd-conformance`).