# SC-3346 Maintenance (Derived) Pricing — Functional Core E2E Test

## Run metadata

| Field | Value |
|---|---|
| Org | FortraUAT |
| Active pricing procedure | Rev_Mgmt_Default_Pricing_Procedure **V14** (ExpressionSet `9QLWC0000015cDl4AI`; sole-active ExpressionSetVersion `9QMWC00000023eX4AQ`, VersionNumber=14; V1–V13 all IsActive=false) |
| Scope | **Core functional pricing only** — integration paths (Workday/MuleSoft), activation, and submission excluded |
| Verdict basis | Functional "partial" counted as PASS; the listed FAILs are the only open functional defects |
| Test method | Read-only SOQL/Tooling + fresh live metadata retrieves + non-destructive Force/Skip reprices on Draft quotes only (no Quote/QLI DML, no delete/activation/submit/platform-event) |
| Date | 2026-06-14 |
| Scenarios | 25 (19 pass, 5 fail, 1 out-of-scope) |
| Artifacts root | `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/` |

## Verdict — functional readiness statement

**NOT READY for the renewal-maintenance commit path. The new-business derived pricing path is functionally complete and correct.**

The build's structure is sound and most pricing functions work end-to-end on live V14: the first-year auto-add fires correctly, new-business derived net prices correctly across all 7 tiers (`tier × Source_List_Price__c`), the M-2 dead-code arm is removed, the renewal COLA *computation* is exact on every line, the COLA rate table is correct to the cent, partner-discount rate selection resolves correctly by product type (15/12/10), the null-guard formula is robust, and Source_List_Price carries faithfully to the Order.

The blocking problem is a single, repeating **renewal-maintenance COMMIT defect**: on auto-added "No Change" renewal lines (born without a linked `Renew` QuoteAction), the engine commits a partner-double-counted value (`COLA net × 0.90`) or `$0` instead of the correctly-computed COLA net — and a fresh Force reprice does **not** correct it (the value is born-stale/engine-owned on a structurally-excluded unpriced derived node). The correct value sits in `COLACalculatedPrice__c` but never reaches `NetUnitPrice`, so a wrong (under-)price rolls up to the Quote GrandTotal. This surfaces in 3 scenarios below and breaks end-to-end SC-3346 spec conformance. All three open defects are engineer-owned logic/creation-path defects (every pricing input is populated and computed correctly).

## Results at a glance

**Counts: 19 PASS · 5 FAIL · 1 OUT-OF-SCOPE (25 total). All 3 FAILs are the same renewal-commit root cause; all are high severity.**

| ID | Domain | Status | Severity | Reason |
|---|---|---|---|---|
| CFG-AUTOADD | Auto-add first-year maintenance | pass | none | Active Year-1 Configurator rule (gated QuoteTypeText='New') auto-adds the right New-Maintenance SKU and fires live (same-second co-creation through 2026-06-11). |
| NB-DERIVED-NET | New-business derived pricing | pass | none | Standard-tier line commits NetUnitPrice=71 = 0.20 × 355 exactly; reprice-stable on live V14. |
| NB-DERIVED-PREMIER | Derived (new-business) pricing | pass | none | Premier branch resolves 0.30; canary commits 3000 = 0.30 × 10000, stable across Force reprice. |
| NB-DERIVED-TIER | New-business derived pricing | pass | none | 7-tier fix is LIVE in V14; all 7 CMDT tiers resolve nonzero × Source_List_Price; prior 3-tier defect fixed. |
| NB-DERIVED-FORMULA | New-business derived pricing | pass | none | Exactly one live NB derived formula (tier × Source_List_Price); Base_Price×tier dead arm removed; Base_Price=0 canary proves the Source_List arm. |
| RN-COLA-MATH | Renewal COLA pricing | pass | none | In-flight COLA net reproduces stamped COLACalculatedPrice__c exactly on 4/4 lines (67.38 / 60.64); re-fires under live reprice. |
| RN-COLA-COMMIT-RENEW | Renewal COLA pricing | pass | none | Line born linked to a Renew QuoteAction commits the correct 67.38 (rollups consistent), reproduced under fresh reprice. |
| **RN-COLA-COMMIT-AUTOADD** | **Renewal COLA pricing** | **fail** | **high** | **Auto-added (QuoteAction-null) line commits 60.64 = 67.38 × 0.90 (partner double-count); reprice does NOT correct it — born-stale creation-path defect.** |
| **RN-PARTNER-DD** | **Renewal COLA pricing** | **fail** | **high** | **Renewal-maint line commits 60.64 = 67.38 × 0.90 (2nd 10% partner factor on top of prior $8.52 already in base); creation-path/posthook logic defect.** |
| RN-COLA-RATES | Renewal COLA pricing | pass | none | Category COLA rate looked up & applied correctly (BoKS 7.85 → 67.38); all 21 category rates match spec to the cent. |
| RN-MULTIYEAR | Renewal COLA pricing | out-of-scope | none | No multi-year/out-year/MyCAP price ever computed/committed; out-year feeds only a Deal-Desk flag + read-only formula; single-year per both SDDs. |
| RN-LIC | Renewal pricing | pass | none | Renewal license/subscription leg (Renew QuoteAction) COLA-uplifts correctly: 5101.22×1.062=5417.50, Net 4442.35 (18% partner). |
| RN-SUB | Renewal pricing | pass | none | Renewal subscription leg = list × (1 − partner): 4442.35 = 5417.50 × 0.82, stable across reprice. |
| AMEND | Renewal pricing | pass | none | Amendment deterministically routes through the NB derived committer; COLA correctly suppressed; only residual is null-SLP migration data. |
| DECOMP-SPLIT | Order decomposition | pass | none | Decomposition commits correct money (maint OI Base=71=355×0.20, B-6 holds, 0 license-base leaks); FK-split premise is a doc mismatch, not a money defect. |
| DECOMP-BASE | Order decomposition | pass | none | OI.Base_Price__c = maintenance base (355×0.20=71), never raw license base; 16/16 maint OIs at 0.20 ratio, 0 leaks. |
| STAMP-FLOW | Stamp / data flow | pass | none | Live V14 before-save flow stamps Base/COLACalc/priors/COLA%/product-type exactly on 4/4 + NB canary; re-fires non-destructively. |
| SLP-CARRY | Stamp / data flow | pass | none | Active QuoteToOrderFieldMapper carries QLI.SLP → OI.SLP; 14/14 match, 0 carry failures org-wide. |
| **MAINT-ONLY** | **Edge cases** | **fail** | **high** | **Maint-only renewal commits NetUnitPrice/GrandTotal=60.64 (=67.38×0.90) instead of 67.38; born-stale on QuoteAction-null line, not reprice-fixable.** |
| MULTI-ASSET | Edge cases | fail | high | License leg correct (4442.35) but maintenance leg commits 54.58 = 60.64 × 0.90 (partner double-count); same SC-3404 commit cluster. |
| B3-PARTNER | Partner pricing | pass | none | Partner-discount RATE selected correctly by product type (Software 15 / New Maint 12 / Renewal Maint 10), never falling to the 15% default. |
| B4-NULLGUARD | Renewal formula robustness | pass | none | Sole-active V14 DerivedPricingRenewals wraps all 4 operands in ISNULL guards; all-null reprice returns clean numeric 0, no engine error. |
| M2-DEADCODE | Pricing mechanism | pass | none | DerivedPricingNewBusiness dead arm = 0 occurrences in active V14; one live NB formula remains; engine commits 71=0.20×355 cleanly. |
| PROC-V14 | Pricing engine | pass | none | V14 sole-active; all derived/COLA/partner elements present with documented resultIncluded wiring; reprices/commits correctly. |
| SDD-CONFORMANCE | Spec conformance | fail | high | Pillars 1–2 conform (single-year; 7-tier × Source_List), but pillar 3 (renewal COLA carry-forward) commits wrong money on auto-added lines. |

> Note: MULTI-ASSET and MULTI-ASSET appear once each above. The four FAIL rows (RN-COLA-COMMIT-AUTOADD, RN-PARTNER-DD, MAINT-ONLY, MULTI-ASSET, SDD-CONFORMANCE) are all manifestations of the single renewal-commit root cause; SDD-CONFORMANCE is the end-to-end rollup of that defect plus the (now-passing) pillars 1–2.

## ❌ FAILURES

These are the only open functional defects. All are engineer-owned (every pricing input is populated and the COLA net is computed correctly into `COLACalculatedPrice__c`; the defect is that the value never commits to `NetUnitPrice` on the auto-added/QuoteAction-null derived renewal line). All share one root cause.

| No. | ID | Scenario | Reason for fail | Severity |
|---|---|---|---|---|
| 1 | RN-COLA-COMMIT-AUTOADD | Auto-added No-Change renewal-maint line commits 60.64 not 67.38 | Auto-added (QuoteAction-null) renewal-maint canary `0QLWC000003e2Sn4AI` commits `NetUnitPrice=60.64 = 67.38 × 0.90` (re-applied 10% partner margin) while the correct COLA net 67.38 sits uncommitted in `COLACalculatedPrice__c`; a fresh Force reprice does NOT correct it (born-stale, engine-owned creation-path defect). | high |
| 2 | RN-PARTNER-DD | Partner discount double-applied on renewal maintenance | Same canary commits `60.64 = 67.38 × 0.90` — a 2nd 10% partner factor on top of the prior partner $8.52 already netted into the COLA base; PartnerNetPricePosthook re-stamps PartnerDiscountPercent and its write no-ops on the unpriced node, so the born-stale value persists. Creation-path/posthook logic defect. | high |
| 3 | MAINT-ONLY | Maintenance-only renewal commits correct COLA net (GrandTotal right) | Maint-only cart (single Renewal-Maintenance line, no contributor) commits `NetUnitPrice=NetTotalPrice=Subtotal=GrandTotal=60.64` (=67.38×0.90) instead of 67.38; born-stale on the QuoteAction-null derived line and not corrected by a fresh Force reprice. | high |
| 4 | MULTI-ASSET | Multi-asset renewal: license + maintenance both commit correct net | License/subscription leg commits the correct 4442.35, but the renewal-maintenance leg `0QLWC000003cy334AA` commits `54.58 = 60.64 × 0.90` (partner double-count) instead of the computed COLA net 60.64; GrandTotal rolls up 4496.93 instead of 4502.99. | high |
| 5 | SDD-CONFORMANCE | Build matches SC-3346 user story (single-year; tier × Source_List; COLA carry-forward) | Pillars 1 (single-year scope) and 2 (first-year = tier × Source_List, now all 7 tiers) conform, but pillar 3 (renewal COLA carry-forward) commits wrong money on auto-added "No Change" renewal lines ($0 / 54.58 / 60.64 vs spec 67.38 / 60.64), so end-to-end spec conformance is not met. | high |

## ✅ Passing functional paths

- **CFG-AUTOADD** — Active Year-1 Configurator ProductConfigurationRule (gated to `QuoteTypeText__c='New'`) auto-adds the correct New-Maintenance SKU `PIA-PIA-RNM-PIAMBK` when the perpetual is added; fires live (same-second co-creation through 2026-06-11). New/Renewal gates are mutually exclusive (no double-add).
- **NB-DERIVED-NET** — Standard-tier (0.20) first-year maintenance commits `NetUnitPrice=71 = 0.20 × Source_List_Price 355` on all 9 active lines; reprice-stable and non-destructive.
- **NB-DERIVED-PREMIER** — Premier branch resolves 0.30; canary commits `3000 = 0.30 × 10000` (Base_Price=0 falsifies any Base_Price path); stable across Force reprice.
- **NB-DERIVED-TIER** — 7-tier fix is live in V14; all 7 `Maintenance_Rate__mdt` tiers resolve nonzero × Source_List_Price; prior 3-tier defect fixed (Basic/Premium/Express/Expert no longer fall to $0).
- **NB-DERIVED-FORMULA** — Exactly one live NB derived formula (`tier × Source_List_Price__c`); competing `Base_Price × tier` arm (M-2 dead code, MDT-gated) removed; single `Source_List_Price__c` reference in V14.
- **RN-COLA-MATH** — In-flight COLA computation reproduces stamped `COLACalculatedPrice__c` exactly on 4/4 lines (67.38; 60.64 priorDisc variant); re-fires correctly under live reprice.
- **RN-COLA-COMMIT-RENEW** — Renewal-maint line *born linked to a `Renew` QuoteAction* commits the correct 67.38 (UnitPrice/NetUnitPrice/rollups all 67.38) — the working creation-path half of the renewal-commit story.
- **RN-COLA-RATES** — Category COLA rate looked up from `COLA_Uplift_Rules__mdt` and applied as `(1+rate/100)` (BoKS 7.85 → 67.38); all 21 category-default rates match the SC-3350 spec to the cent.
- **RN-LIC** — Renewal license leg COLA-uplifts correctly across all 4 COLA sources: `5101.22 × 1.062 = 5417.50` UnitPrice, then 18% partner → 4442.35 Net.
- **RN-SUB** — Renewal subscription leg = `list × (1 − partner)`: `4442.35 = 5417.50 × 0.82`; stable across reprice; a real priced node distinct from the broken maintenance leg.
- **AMEND** — Amendment (`QuoteTypeText != 'Renewal'`) deterministically routes through the NB derived committer; COLA correctly suppressed; the only gap is null-SLP / qty-0 migration data.
- **DECOMP-SPLIT** — Decomposition feature commits correct money (maint OI Base=71=355×0.20, B-6 holds, 0 license-base leaks); the FK-split premise is a doc/SDD mismatch, not a money defect.
- **DECOMP-BASE** — OI.`Base_Price__c` = maintenance base (355×0.20=71), never raw license base; all 16 maint OIs at 0.20 ratio with zero leaks; end-to-end chain proven.
- **STAMP-FLOW** — Live V14 before-save flow stamps Base/COLACalc/priors/COLA%/product-type exactly on 4/4 renewal + NB canary; re-fires non-destructively on reprice; V14 also seeds UnitPrice.
- **SLP-CARRY** — Active `QuoteToOrderFieldMapper` carries `QLI.Source_List_Price__c → OI.Source_List_Price__c` (preserved through lock-recovery fallback); 14/14 sampled OIs match, 0 carry failures org-wide.
- **B3-PARTNER** — Partner-discount rate selected correctly by product type (Software 15 / New Maint 12 / Renewal Maint 10), proven by FINEST traces; never falls through to the 15% default; Product2 fallback rescues 61,309 NULL-typed maintenance QLIs.
- **B4-NULLGUARD** — Sole-active V14 `DerivedPricingRenewals` wraps all 4 operands in `ISNULL(...)` guards (only version that does); all-null reprice returns a clean numeric 0 with no engine error; populated canary still computes 67.38.
- **M2-DEADCODE** — `DerivedPricingNewBusiness` (Base_Price × tier, MDT-gated) = 0 occurrences in the active V14 block; one live NB formula remains; engine commits 71=0.20×355 cleanly.
- **PROC-V14** — V14 is the sole-active version; all derived/COLA/partner elements present with the documented `resultIncluded` wiring and correct formula bodies; engine prices/commits correctly on a live Force pass.
- **RN-MULTIYEAR** (out-of-scope) — No multi-year/out-year/MyCAP price is ever computed into or committed onto any price field; the out-year rate feeds only a Deal-Desk approval flag and a read-only formula field; both SDDs scope renewal COLA as single-year/annual.

## Domain detail

### FAIL — RN-COLA-COMMIT-AUTOADD (Renewal COLA pricing, high)

**Expected.** On a renewal quote, an auto-added "No Change" renewal-maintenance line (born WITHOUT a linked `Renew` QuoteAction) should commit `NetUnitPrice = COLA net = (Base − PriorPartner − PriorDisc) × (1 + COLA%/100)` = stamped `COLACalculatedPrice__c`. Canary 00781109 BoKS `PIA-PIA-RRM-PIAM`: `(71 − 8.52 − 0) × 1.0785 = 67.38`. The $8.52 prior partner $ is already embedded in the COLA base, so NO additional ~10% partner factor should reduce the committed net.

**Actual.** FAIL on live V14. Canary `0QLWC000003e2Sn4AI` (Draft/Renewal/USD, `QuoteActionId=null`, `ListPrice=0`) commits `NetUnitPrice=60.64 = 67.38 × 0.90` (ratio 0.89997) while `COLACalculatedPrice__c=67.38` sits stamped-but-uncommitted and `UnitPrice=67.38`. The wrong 60.64 rolls into `NetTotalPrice=Subtotal=TotalLineAmount=PartnerUnitPrice=60.64`. A fresh Force/Skip reprice (`isSuccess:true`, no ScaleCacheServiceException) left `NetUnitPrice` at 60.64 while `LastModifiedDate` advanced `14:51:48 → 18:31:40` (genuine recompute) — the born-stale value is engine-owned/immutable on the unpriced derived node, confirming a creation-path (not reprice-fixable, not data) defect.

**Evidence.**
- Live SOQL canary: `UnitPrice=67.38, NetUnitPrice=60.64, NetTotal=Subtotal=TotalLineAmount=PartnerUnitPrice=60.64, COLACalc=67.38, Base=71, PriorPartner=8.52, PriorDisc=0, COLA%=7.85`.
- Arithmetic (Decimal HALF_UP): `(71−8.52−0)×1.0785 = 67.38`; `60.64 = 67.38 × 0.90`; priorDisc variant `54.58 = 60.64 × 0.90`.
- 4-line cross-tab (all `PIA-PIA-RRM-PIAM`, IsDerived PBE ListPrice=0, identical inputs): `dEW24` (00781084) QuoteAction.Type='Renew' → 67.38 CORRECT; `e2Sn4` (canary) null → 60.64; `ck6X4` (00781043) null → 0; `cy334` (00781053) null → 54.58. Only the linked-Renew line commits 67.38.
- Mechanism (build RCA + prior FINEST `07LWC00000OyWbt2AF`): prehook computes 67.38 and stamps COLACalc; `[246] 'Found 0 renewal QLIs from 1 total'`; posthook emits override `Net=67.38` but it is a silent no-op on the structurally-excluded unpriced node (ItemIsDerived + ListPrice=0); 67.38 never enters the NetUnitPrice map.
- Artifacts: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/rn-cola-commit-autoadd/`.

### FAIL — RN-PARTNER-DD (Renewal COLA pricing, high)

**Expected.** Renewal-maintenance committed `NetUnitPrice` = COLA net with the prior partner discount embedded ONCE (via the `Prior_Partner_Discount__c` subtraction) and NO additional partner factor re-applied. Canary: `(71−8.52−0)×1.0785 = 67.38 = COLACalc`; expected committed `NetUnitPrice = 67.38`.

**Actual.** FAIL. Canary `0QLWC000003e2Sn4AI` commits `NetUnitPrice=60.64 = 67.38 × 0.90` — the `0.90 = (1 − 0.10)` Renewal_Maintenance partner margin re-applied on top of the $8.52 prior partner discount already in the COLA base. The discriminator is proven live: only the line carrying a linked `QuoteAction.Type='Renew'` (`7ocWC00000u7yf8YAA`) commits 67.38; the 3 QuoteAction-null lines mis-commit (0 / 54.58 / 60.64). A fresh Force reprice did not move it off 60.64. `PartnerNetPricePosthook` (`01pWC000002VmiLYAS`, `buildRenewalMaintenanceColaUpdate`) writes `colaNet=67.38` but also re-stamps `PartnerDiscountPercent` and the write no-ops on the unpriced node.

**Evidence.**
- Arithmetic: `60.64/67.38 = 0.89997`; `54.58/60.64 = 0.90007`; `0.90 = 1 − 0.10`.
- Live posthook `PartnerNetPricePosthook 01pWC000002VmiLYAS` (LastMod 2026-06-14T02:35) re-stamps PartnerDiscountPercent; FINEST `07LWC00000OyWVR2A3`: `[604]` prehook 67.38, `[246]` "Found 0 renewal QLIs from 1 total", `[898]` posthook emits Net=67.38 yet 60.64 commits.
- All inputs populated (Base/PriorPartner/PriorDisc/COLA%/COLACalc) → engineer-owned, not data-rooted.
- Artifacts: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/rn-partner-dd/`.

### FAIL — MAINT-ONLY (Edge cases, high)

**Expected.** A maintenance-only renewal cart (single Renewal-Maintenance line, no on-cart contributor) should commit the correct COLA net to `NetUnitPrice` and roll it up to GrandTotal. Canary 00781109: `(71−8.52−0)×1.0785 = 67.38`; expected `NetUnitPrice = NetTotalPrice = GrandTotal = 67.38`.

**Actual.** FAIL. Canary `0Q0WC0000038aXd0AI` is a true maint-only cart (single line `0QLWC000003e2Sn4AI`, `ParentQuoteLineItemId=null`, `RelatedQuoteLineItemId=null`, `QuoteActionId=null`, `ListPrice=0`). A fresh Force/Skip reprice (`isSuccess:true`, LastModifiedDate `18:32:23 → 18:35:42` = genuine recompute) left the line committing `NetUnitPrice=NetTotal=Subtotal=TotalLineAmount=PartnerUnitPrice=60.64` while `UnitPrice=67.38` and `COLACalc=67.38` carry the correct value. The Quote `GrandTotal=Subtotal=TotalPrice=60.64` instead of 67.38.

**Evidence.**
- `60.64 = 67.38 × 0.90` exactly (`60.64/67.38 = 0.9000`); prior FINEST `log_OyWnB2AV.txt`: `[604]` prehook 67.38, `[246]` "Found 0 renewal QLIs from 1 total", `[913]` "PERCENT ONLY … PartnerDiscountPercent 10.00%" re-stamp on InputUnitPrice=67.38 → NetUnitPrice 60.64; posthook override is a silent no-op.
- Born-immutable: reprice held 60.64 across the recompute.
- Artifacts: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/maint-only/`.

### FAIL — MULTI-ASSET (Edge cases, high)

**Expected.** On the multi-asset renewal cart (00781053), BOTH legs commit correct net: beSECURE subscription `NetUnitPrice=4442.35` (=5417.50 × 0.82, 18% off); BoKS renewal-maintenance `NetUnitPrice=COLACalc=60.64 = (71 − 8.52 − 6.25) × 1.0785`. GrandTotal `= 4442.35 + 60.64 = 4502.99`.

**Actual.** Split outcome (confirmed after fresh Force/Skip reprice). **License leg CORRECT**: `VM-BSL-RSL-BESECB 0QLWC000003cxzq4AA` UnitPrice=5417.50, Net=4442.35 = 5417.50 × 0.82; carries `QuoteAction 7ocWC00000u7tqlYAA` Type='Renew'. **Maintenance leg WRONG**: `PIA-PIA-RRM-PIAM 0QLWC000003cy334AA` computes correct `COLACalc=60.64` but commits `NetUnitPrice=NetTotal=54.58 = 60.64 × 0.90` (partner double-count; `QuoteActionId=null`; PBE `01uWC000006XPPBYA4` IsDerived=true/UnitPrice=0). Header `GrandTotal=TotalPrice=4496.93 = 4442.35 + 54.58` (correct would be 4502.99).

**Evidence.**
- Both QLI LastModifiedDate advanced to 2026-06-14T18:36:27Z (genuine recommit), line count unchanged.
- `(71−8.52−6.25)×1.0785 = 60.64` (stamped, correct); `60.64 × 0.90 = 54.58` (committed, wrong); `5417.50 × 0.82 = 4442.35` (correct).
- Null QuoteAction on the maintenance leg vs Renew action on the subscription leg = the differentiator.
- Artifacts: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/multi-asset/`.

### FAIL — SDD-CONFORMANCE (Spec conformance, high)

**Expected.** As-built SC-3346 conforms to all three user-story pillars: (1) single-year/annual only; (2) first-year NB derived net = `tier × Source_List_Price__c` for every defined tier; (3) renewal net = COLA carry-forward committed to `NetUnitPrice` on EVERY renewal-maintenance line.

**Actual.** FAIL on end-to-end conformance, driven by pillar 3. **Pillar 1 CONFORMS** — V14 block has zero out-year/MyCAP/additional_year wiring; only single-year `COLA_Uplift_Percent__c` is referenced; all 4 canary QLIs have `COLA_Outyear_Uplift_Percent__c=null`. **Pillar 2 CONFORMS (improvement)** — V14 DerivedPricingFormula extended to all 7 tiers matching `Maintenance_Rate__mdt` exactly; Standard 0.20 × 355 = 71.00 commits live; only orphan picklist 'platinum' (no rate row) is unhandled (data matter). **Pillar 3 COMPUTES but FAILS TO COMMIT** — the renewal formula is byte-exact to spec and `COLACalc=67.38/60.64` is stamped correctly on all 4 canary lines, but `DerivedPricingRenewals`/`DerivedPricingFormula`/`COLAUpliftonRenewalNet` are all `resultIncluded=false` and the only `resultIncluded=true` committer (`DerivedProductsRenewals`) is gated to skip renewals. A live reprice committed `$0 / 54.58 / 60.64` on the three QuoteAction-null lines vs the correct `67.38` only on the linked-Renew line.

**Evidence.**
- Decisive differentiator = `QuoteActionId`: `dEW24='Renew'` → 67.38 commits; `ck6X4/cy334/e2Sn4 = null` → $0 / x0.90.
- `resultIncluded` analysis (live V14): `DerivedProductsRenewals=true` (only committer, gated to skip renewals); `DerivedPricingFormula=false`; `DerivedPricingRenewals=false`; `COLAUpliftonRenewalNet=false`.
- Inputs all present → creation-path LOGIC defect, not data.
- Artifacts: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_func2/work/sdd-conformance/`.

### Notable PASS — NB-DERIVED-TIER (7-tier fix now live)

**Expected.** The active V14 DerivedPricingFormula resolves a tier rate for ALL 7 `Maintenance_Rate__mdt` tiers, so Basic/Premium/Express/Expert no longer fall to $0.

**Actual.** PASS — improvement vs the prior 3-tier FAIL. Live V14 formula (line 70304): `IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,IF(Basic,0.15,IF(Premium,0.24,IF(Express,0.30,IF(Expert,0.35,0))))))) * Source_List_Price__c`. All 7 branches match the CMDT exactly. Positive control re-confirmed: Standard lines commit 71 = 0.20 × 355 under a fresh reprice (32→32 lines, LastModifiedDate advanced). The only residual ($0 on orphan 'platinum') has no defined rate (data/CMDT-hygiene). Maintainability note (non-money): the 7 rates are hard-coded rather than read from `Maintenance_Rate__mdt` (CMDT referenced 0× in the procedure), so the table could silently drift if changed.

### Notable PASS — RN-COLA-COMMIT-RENEW (the working creation path)

**Expected.** A renewal-maintenance line born carrying `QuoteAction.Type='Renew'` commits `NetUnitPrice = COLA net = 67.38` with consistent rollups.

**Actual.** PASS. Canary 00781084 line `0QLWC000003dEW24AM` is linked to `QuoteActionId=7ocWC00000u7yf8YAA` (Type='Renew', verified live) and commits the correct 67.38 (UnitPrice/NetUnitPrice/NetTotal/Subtotal/TotalLineAmount all 67.38), reproduced under a fresh Force reprice (COLA_Applied_Date advanced 18:29:38 → 18:31:36). This is the direct contrast that isolates the FAIL root cause: the linked `Renew` QuoteAction routes the line to a writable priced node, whereas QuoteAction-null auto-added lines do not.

### Notable PASS — CFG-AUTOADD (trigger correctness)

Auto-add is an Active Configurator `ProductConfigurationRule` (RuleType=Configurator, ProcessScope/RuleSubType=Transaction), NOT a `ProductRelatedComponent` bundle (COUNT=0). Year-1 rule `14OWC0000022ULp2AM` (Active, seq 10, EffFrom 2026-04-01): criteria `ItemProductCode = 'PIA-PIA-NRPS-PIAP'` AND `QuoteTypeText__c = 'New'`; action AutoAdd target `01tWC00000DD1bsYAD` (`PIA-PIA-RNM-PIAMBK`). Companion Year-2 rule gated to `QuoteTypeText__c='Renewal'` → mutually exclusive, no double-add. Fires live: 9 most-recent quotes co-created the New-Maintenance line in the same second as the perpetual (0 diff-second pairs), most recent 2026-06-11T15:30:29.

## Fix plan

All open defects (FAILs #1–#5) collapse to one root cause: **auto-added renewal-maintenance lines are born without a linked `Renew` QuoteAction, landing on a structurally-excluded unpriced derived node (ItemIsDerived + ListPrice=0) where the correct `COLACalculatedPrice__c` (67.38) is never committed to `NetUnitPrice`, and the posthook re-stamps a second ~10% partner factor producing `× 0.90`.** Ordered, concrete, engineer-owned fixes:

**P0 — Fix the renewal-maintenance commit (resolves FAILs #1 RN-COLA-COMMIT-AUTOADD, #2 RN-PARTNER-DD, #3 MAINT-ONLY, #4 MULTI-ASSET maint leg, and pillar 3 of #5 SDD-CONFORMANCE).** Choose the lowest-risk of:
- **(a) Creation-path (recommended, lowest risk):** ensure auto-added "No Change" renewal-maintenance lines are born linked to a `Renew` QuoteAction (the proven-working `RN-COLA-COMMIT-RENEW` / 00781084 path) so they route to a writable priced node that commits `COLACalculatedPrice__c` to `NetUnitPrice`. Validate against the existing differentiator: the only currently-correct line is the one with `QuoteAction.Type='Renew'`.
- **(b) Stop the partner double-count:** in `PartnerNetPricePosthook` (`01pWC000002VmiLYAS`, `buildRenewalMaintenanceColaUpdate`), do NOT re-stamp `PartnerDiscountPercent` (the 10% factor) on a renewal-maintenance line whose COLA base already nets the prior partner $8.52. This removes the `× 0.90` even where the node is writable. (This alone does not fix the `$0` no-op lines — pair with (a) or (c).)
- **(c) Make the derived renewal line a persisting priced node:** cohort-scoped procedure redesign / native PriceBookEntryDerivedPrice so the renewal-maintenance line is a writable priced node and `COLAUpliftonRenewalNet` (currently `resultIncluded=false`) lands. Higher blast radius — gate on regression-testing the NB derived path (NB-DERIVED-NET/TIER must stay green).

After P0, re-run the 4-line canary cross-tab (00781043/00781053/00781084/00781109): every renewal-maintenance line should commit `NetUnitPrice = COLACalculatedPrice__c` with no `× 0.90` and no `$0`, and the Quote GrandTotal should roll up the COLA net.

**P1 — De-risk the 7-tier formula maintainability (hardening, not a current money defect).** The V14 `DerivedPricingFormula` hard-codes all 7 rates and references `Maintenance_Rate__mdt` 0×. Values match today, but the table can silently drift from the formula. Either drive the formula off the CMDT or add a guard/test that fails if CMDT ≠ formula. Also resolve the orphan picklist value `'platinum'` (15 live QLIA rows, no rate row, resolves to else=0) — add a `Maintenance_Rate__mdt` row or remove the picklist value (CMDT/data hygiene).

**Out of scope for this fix plan (already passing or genuinely inert):** single-year scope, NB derived tiers, partner-rate selection, null-guards, M-2 dead-code removal, SLP carry, decomposition, stamp flow, and multi-year/MyCAP (inert at the commit layer).

## Appendix

### Core formulas (live V14)

- **New-business derived net** (`DerivedPricingFormula`, resultIncluded=false, output NetUnitPrice):
  `IF(AttributeValue='Premier',0.30,IF('Standard',0.20,IF('Professional',0.20,IF('Basic',0.15,IF('Premium',0.24,IF('Express',0.30,IF('Expert',0.35,0))))))) * Source_List_Price__c`
- **Renewal COLA carry-forward** (`DerivedPricingRenewals`, resultIncluded=false, output NetUnitPrice):
  `IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (IF(ISNULL(Base_Price__c),0,Base_Price__c) − IF(ISNULL(Prior_Partner_Discount__c),0,Prior_Partner_Discount__c) − IF(ISNULL(Prior_Discretionary_Discount__c),0,Prior_Discretionary_Discount__c)) * (1 + (IF(ISNULL(COLA_Uplift_Percent__c),0,COLA_Uplift_Percent__c)/100))), NetUnitPrice)`
- **COLA net (canary)**: `(71 − 8.52 − 0) × 1.0785 = 67.38` (HALF_UP); priorDisc variant `(71 − 8.52 − 6.25) × 1.0785 = 60.64`.
- **Partner double-count signature**: committed `60.64 = 67.38 × 0.90`; `54.58 = 60.64 × 0.90`; `0.90 = 1 − 0.10` (Renewal_Maintenance partner margin).
- **Renewal license uplift**: `UnitPrice = Pre_COLA_Price__c × (1 + COLA%/100)` → `5101.22 × 1.062 = 5417.50`; partner `× 0.82` → `4442.35`.
- **Decomposition base (B-6)**: `OI.Base_Price__c = license source list × tier rate = 355 × 0.20 = 71` (SLP=355 carried separately).

### Key identifiers

| Entity | Id / Value |
|---|---|
| ExpressionSet | `9QLWC0000015cDl4AI` |
| Active ExpressionSetVersion (V14) | `9QMWC00000023eX4AQ` (VersionNumber=14, sole IsActive) |
| Stamp_Maintenance_Pricing_Inputs (active V14 flow) | `301WC00000kkPydYAE` |
| COLAUpliftPrehook | `01pWC000001wNGbYAM` |
| PartnerNetPricePosthook | `01pWC000002VmiLYAS` |
| PartnerPricingService | `01pWC000001wAzPYAU` |
| MaintenanceOrderDecompositionService | `01pWC000002W5rRYAS` (ApiVersion 62) |
| QuoteToOrderFieldMapper | `01pWC000002IuvRYAS` (ApiVersion 62) |
| Perpetual SKU | `PIA-PIA-NRPS-PIAP` / `01tWC00000DD1btYAD` |
| New-Maintenance SKU | `PIA-PIA-RNM-PIAMBK` / `01tWC00000DD1bsYAD` |
| Renewal-Maintenance SKU | `PIA-PIA-RRM-PIAM` / `01tWC00000DD1buYAD` |
| Year-1 auto-add rule | `14OWC0000022ULp2AM` |
| Year-2 auto-add rule | `14OWC0000022Eyb2AE` |

### Renewal-maintenance 4-line cross-tab (canary)

| QLI | Quote | QuoteActionId | COLACalc | Committed NetUnitPrice | Verdict |
|---|---|---|---|---|---|
| `0QLWC000003dEW24AM` | 00781084 | `7ocWC00000u7yf8YAA` (Type='Renew') | 67.38 | **67.38** | CORRECT (RN-COLA-COMMIT-RENEW) |
| `0QLWC000003e2Sn4AI` | 00781109 | null | 67.38 | 60.64 (=67.38×0.90) | WRONG |
| `0QLWC000003ck6X4AQ` | 00781043 | null | 67.38 | 0 | WRONG |
| `0QLWC000003cy334AA` | 00781053 | null (priorDisc 6.25) | 60.64 | 54.58 (=60.64×0.90) | WRONG |

### Reprice method (all scenarios)

`POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` with `{pricingPref:Force, configurationPref:{configurationMethod:Skip}}` — non-destructive, Draft quotes only; verified `isSuccess:true`, `errorResponse:[]`, no `ScaleCacheServiceException`, line counts unchanged, `LastModifiedDate` advanced (genuine recompute). Accepted quote 00781068 untouched throughout.