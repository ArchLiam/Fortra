# SC-3346 Maintenance (Derived) Pricing — BoKS DPP Functional E2E

## Run metadata (org FortraUAT, V14 active, scope = PIA-PIA-NRPS-PIAP per Nir, integration excluded, 2026-06-14)

| Field | Value |
|---|---|
| Org | FortraUAT |
| Date | 2026-06-14 |
| Active pricing procedure | `Rev_Mgmt_Default_Pricing_Procedure` **V14** — ExpressionSet `9QLWC0000015cDl4AI`, ExpressionSetVersion `9QMWC00000023eX4AQ` (`VersionNumber=14`, `IsActive=true`); V13/V12 inactive |
| Active posthook | `PartnerNetPricePosthook` `01pWC000002VmiLYAS` (ApiVersion 65, LastModified 2026-06-14T02:35Z, v1.4/v1.5 source) |
| Sanctioned scope (per Nir Kailash) | **PIA-PIA-NRPS-PIAP** (Powertech IAM BoKS, `01tWC00000DD1btYAD`) + its derived maintenance: New-Maint **PIA-PIA-RNM-PIAMBK** (`01tWC00000DD1bsYAD`), Renewal-Maint **PIA-PIA-RRM-PIAM** (`01tWC00000DD1buYAD`) |
| Reprice method | Live managed reprice — `POST /connect/rev/sales-transaction/actions/place`, `pricingPref=Force`, `configurationMethod=Skip` (RLM blocks direct Quote/QLI DML; configurator not re-run live per guardrails) |
| Out of scope | Integration / Workday round-trip; multi-product families other than BoKS |
| Total scenarios | 20 (functional only) |

**Framing applied to this run (per build owner direction):** functional "partial" is counted as PASS; data-team-rooted issues are reclassified out; every logic defect is engineer-owned (no owner-gating). Maintenance-not-on-catalog and no-maintenance-type-attribute are EXPECTED, not defects.

---

## Verdict — functional readiness on the sanctioned DPP product

**NOT READY for the renewal-maintenance commit path.** On the Fortra-sanctioned DPP product, the *upstream* maintenance pricing chain is correct end-to-end: auto-add fires, the new-business derived seed computes (0.20 × 355 = 71), the COLA math computes (67.38), the stamp flow stamps every input, the partner rate is selected by product type, the formula is null-guarded, and Source_List_Price carries Quote→Order. **The single failing surface is the committed `NetUnitPrice` on BoKS renewal-maintenance lines**, where the partner posthook re-applies the partner margin on top of an already-partner-net COLA price (a double-discount): 67.38 × 0.90 = 60.64. This is a single, well-localized, engineer-owned logic defect that manifests across six functional scenarios (one of them at **critical** spec-conformance severity) plus a related $0/unseeded derived-base variant on a partner multi-asset quote.

- **New-business** derived maintenance pricing: **fully conformant.**
- **Renewal COLA computation** (rate sourcing, math, stamping, null-guarding): **fully conformant** — `COLACalculatedPrice__c` / `UnitPrice` are always correct (67.38).
- **Renewal-maintenance committed money** (`NetUnitPrice`): **defective** on 3 of 4 sanctioned renewal quotes; only the QuoteAction.Type='Renew' born-net path commits correctly.

---

## Results at a glance

**Counts:** PASS **13** · FAIL **6** · OUT-OF-SCOPE **1** (Total 20)

> Note: the **6 FAILs are all facets of ONE root-cause family** — the renewal-maintenance commit path (partner double-discount on the already-net COLA price, plus the $0/unseeded-base variant on the partner multi-asset quote). Each is graded FAIL because its pass condition is the *committed money* (`NetUnitPrice`/GrandTotal) or the spec/engine conformance of that committed money. The COLA-computation, rate, stamp, and null-guard scenarios PASS because their pass condition is the correctly-*computed* value (`COLACalculatedPrice__c`/`UnitPrice`), which is always right (67.38). So: the math is correct everywhere; only the *committed* net on renewal-maintenance lines is wrong.

| # | ID | Domain | Status | Severity | Reason |
|---|---|---|---|---|---|
| 1 | BOKS-AUTOADD | Auto-add (BoKS) | pass | none | Active Year-1 AutoAdd rule `14OWC0000022ULp2AM` fires on PIAP + QuoteType=New, co-creates PIAMBK at NUP 62.48 (=71−8.52). |
| 2 | BOKS-NB-DERIVED-NET | New-business derived (BoKS) | pass | none | Live reprice commits NUP=71 (=0.20 tier × 355 Source_List) on every New-Maint line; partner variant 62.48 = single 12% discount. |
| 3 | BOKS-NB-FORMULA | New-business derived (BoKS) | pass | none | NB maint re-derives 71 via the live MTD-gated Source_List × tier arm; Base×tier arm gated by non-existent code 'MDT' (dead/unreachable). |
| 4 | BOKS-RN-COLA-MATH | Renewal COLA (BoKS) | pass | none | COLA net (71−8.52)×1.0785 = 67.38 stamped to COLACalculatedPrice__c / UnitPrice; stable across reprice. |
| 5 | BOKS-RN-COMMIT-RENEW | Renewal COLA (BoKS) | pass | none | Renew-born line (QuoteAction.Type='Renew') commits NUP=UnitPrice=COLACalc=67.38; born-net avoids the posthook re-discount. |
| 6 | BOKS-RN-COMMIT-AUTOADD | Renewal COLA (BoKS) | **fail** | **high** | Auto-added No-Change renewal-maint line commits NUP=60.64 (=67.38×0.90) instead of 67.38. |
| 7 | BOKS-RN-PARTNER-DD | Renewal COLA (BoKS) | **fail** | **high** | Posthook seeds correct COLA net 67.38 then re-applies 10% partner Discount → 60.64 (double-discount). |
| 8 | BOKS-RN-RATES | Renewal COLA (BoKS) | pass | none | BoKS category rate 7.85% resolved from CMDT and applied to correct base 62.48 → 67.38. |
| 9 | BOKS-RN-LIC | Renewal (BoKS) | pass | none | Perpetual leg commits partner-net 301.75 (=355×0.85), correctly receives NO COLA. |
| 10 | BOKS-MAINT-ONLY | Edge cases (BoKS) | **fail** | **high** | Maintenance-only renewal commits GrandTotal=60.64 (=67.38×0.90) instead of 67.38. |
| 11 | BOKS-MULTI-ASSET | Edge cases (BoKS) | **fail** | **high** | License commits 301.75 (correct) but derived maint commits **$0** (Source_List_Price__c=null, unseeded). |
| 12 | BOKS-DECOMP-BASE | Order decomposition (BoKS) | pass | none | Maint OrderItem base = 71 (not license 355); 355 appears only as the Source_List derivation source. |
| 13 | BOKS-STAMP-FLOW | Stamp / data flow (BoKS) | pass | none | Stamp_Maintenance_Pricing_Inputs stamps Base/priors/COLA%/COLACalc exactly; deterministic re-stamp. |
| 14 | BOKS-SLP-CARRY | Stamp / data flow (BoKS) | pass | none | OI.Source_List_Price__c == QLI.Source_List_Price__c on 9/9 converted orders (8×355, 1×null faithful). |
| 15 | BOKS-B3-PARTNER | Partner pricing (BoKS) | pass | none | Rate selected by product type: Renewal-Maint=10%, New-Maint=12%, Perpetual=15% (not Software 15% leak). |
| 16 | BOKS-B4-NULLGUARD | Formula robustness (BoKS) | pass | none | V14 Renewal COLA formula ISNULL-guards every input; live canary populated 67.38, no null/0 leak. |
| 17 | BOKS-PROC-V14 | Pricing engine (BoKS) | **fail** | **high** | V14 active & reprices, COLA computes 67.38, but committed NUP=60.64; 1 of 7 BoKS RRM lines correct. |
| 18 | BOKS-SDD-CONFORMANCE | Spec conformance (BoKS) | **fail** | **critical** | Committed NUP non-conformant on 3 of 4 sanctioned renewal quotes (0 / 54.58 / 60.64 vs 67.38). |
| 19 | BOKS-CATALOG | Catalog (BoKS) | pass | none | Only PIAP is catalog-visible; both maint products have 0 ProductCategoryProduct rows — expected per Nir. |
| 20 | BOKS-MULTIYEAR | Renewal COLA (BoKS) | out-of-scope | none | V14 references 0 out-year/MyCAP tokens; canary single-year; multi-year inert — out-of-scope per single-year SDD. |

---

## ❌ FAILURES (engineer-owned logic defects only)

| No. | ID | Scenario | Reason for fail | Severity |
|---|---|---|---|---|
| 1 | BOKS-SDD-CONFORMANCE | BoKS renewal-maintenance committed NetUnitPrice does not conform to the SC-3346 user story (COLA carry-forward) on the sanctioned DPP product | Committed NUP wrong on **3 of 4** sanctioned BoKS renewal quotes (commits 0 / 54.58 / 60.64 vs expected 67.38 / 60.64). COLACalculatedPrice__c & UnitPrice are correct; the *ordered money* is not, due to an engineer-owned posthook partner double-count. Only the Renew-born quote (00781084) conforms. | **critical** |
| 2 | BOKS-PROC-V14 | V14 active but derived/COLA/partner elements mis-commit the BoKS renewal-maintenance net (double-discount) | V14 is active and reprices clean, COLA element computes 67.38 correctly, but committed NUP=60.64 (=67.38×0.90) — partner margin re-applied on the already-net COLA price. Only **1 of 7** BoKS RRM-PIAM lines org-wide commits 67.38. | **high** |
| 3 | BOKS-RN-PARTNER-DD | BoKS renewal maintenance double-discounted: commits 60.64 (=67.38×0.90) instead of COLA net 67.38 | `PartnerNetPricePosthook` seeds the correct COLA net 67.38, then `calculateDeferredPartnerPrice` re-applies the 10% partner Discount model to it (67.38×0.90=60.64), double-discounting an already-partner-net COLA base. Reproducible after clean Force/Skip reprice. | **high** |
| 4 | BOKS-RN-COMMIT-AUTOADD | BoKS auto-added (No-Change) renewal-maint line commits correct COLA net (not 60.64/$0) | Auto-added No-Change line (`QuoteActionId=null`, not Renew-born) commits NUP=60.64 instead of 67.38; the v1.4 `buildRenewalMaintenanceColaUpdate` short-circuit is bypassed and the generic deferred-partner path wins. | **high** |
| 5 | BOKS-MAINT-ONLY | BoKS maintenance-only renewal commits correct COLA net (GrandTotal right) | Single-line maintenance-only renewal commits GrandTotal=60.64 (=67.38×0.90); per-unit understatement 6.74 (~10%). Same posthook double-discount; v1.4 short-circuit did not win on this maint-only line. | **high** |
| 6 | BOKS-MULTI-ASSET | BoKS multi-asset renewal: license + maintenance both commit correct net | On a partner multi-asset quote the license commits 301.75 (correct) but the derived maintenance commits **$0** (`Source_List_Price__c=null`, base never seeded); the posthook bails on `currentPrice <= 0` and cannot recover. Standard non-partner multi-asset passes (355 + 71). | **high** |

> All six failures are facets of one root cause family: the renewal-maintenance commit path. Five are the partner **double-discount** on a correctly-computed COLA base; one (BOKS-MULTI-ASSET) is the **$0/unseeded derived base** variant where the posthook's `currentPrice <= 0` bail leaves the line at zero. No data gap, no owner gate — all engineer-owned logic.

---

## ✅ Passing (one-line reason each)

- **BOKS-AUTOADD** — Active Configurator rule `14OWC0000022ULp2AM` auto-adds PIAMBK at NUP 62.48 on New quotes; co-created at identical timestamps.
- **BOKS-NB-DERIVED-NET** — New-business derived net commits 71 = 0.20 × 355 on every active New-Maint line; partner variant 62.48 = single 12% discount.
- **BOKS-NB-FORMULA** — Live Source_List × tier arm (gated by real code 'MTD') prices NB maint to 71; the Base × tier arm is gated by non-existent 'MDT' → dead code, never commits.
- **BOKS-RN-COLA-MATH** — (71−8.52)×1.0785 = 67.3847 → 67.38 stamped to COLACalculatedPrice__c and UnitPrice; stable across reprice.
- **BOKS-RN-COMMIT-RENEW** — Renew-born line (QuoteAction.Type='Renew') commits the correct 67.38; born-net avoids the posthook re-discount.
- **BOKS-RN-RATES** — BoKS category COLA rate 7.85% sourced from `COLA_Uplift_Rules__mdt` and applied to the correct base 62.48 → 67.38 (not a leaked global default).
- **BOKS-RN-LIC** — Perpetual license leg commits partner-net 301.75 (=355×0.85) and correctly receives no COLA (0/91 BoKS perpetual QLIs ever carry COLA).
- **BOKS-DECOMP-BASE** — Maintenance OrderItem base = 71 (license 355 × 0.20), not the license base 355; 355 is only the derivation source.
- **BOKS-STAMP-FLOW** — `Stamp_Maintenance_Pricing_Inputs` stamps Base_Price=71, priors 8.52/0, COLA%=7.85, COLACalc=67.38 — all exact and deterministic.
- **BOKS-SLP-CARRY** — Source_List_Price carries Quote→Order value-faithfully on 9/9 converted orders (8×355, the one null carried null faithfully).
- **BOKS-B3-PARTNER** — Partner rate selected by `Fortra_Product_Type__c`: Renewal-Maint=10%, New-Maint=12%, Perpetual=15% (no Software-15% leak).
- **BOKS-B4-NULLGUARD** — V14 Renewal COLA formula wraps every input in `IF(ISNULL(x),0,x)`; live canary populated 67.38 with no null/0 leak.
- **BOKS-CATALOG** — Only PIAP is catalog-visible; both maintenance products have 0 ProductCategoryProduct rows (expected per Nir); they retain selling-model options so remain derivable.

---

## Domain detail

### Failing scenarios — expected vs actual + evidence

#### FAIL #1 (critical) — BOKS-SDD-CONFORMANCE: committed NetUnitPrice does not conform to the SC-3346 user story
- **Expected:** Per SC-3346 (single-year; tier × Source_List for new-business seed; COLA carry-forward (Base − PriorPartner − PriorDisc) × (1+COLA/100), HALF_UP), committed `NetUnitPrice` on PIA-PIA-RRM-PIAM should equal the computed COLA net: 67.38 = (71 − 8.52 − 0) × 1.0785 on 00781109 / 00781043 / 00781084, and 60.64 = (71 − 8.52 − 6.25) × 1.0785 on 00781053.
- **Actual:** Committed `NetUnitPrice` wrong on **3 of 4** sanctioned renewal quotes — 00781109 commits **60.64** (=67.38×0.90, partner double-count, 10.00% under) vs 67.38; 00781053 commits **54.58** (=60.64×0.90) vs 60.64; 00781043 commits **0** (unpriced node) vs 67.38. Only 00781084 (born with QuoteAction.Type='Renew') commits the correct 67.38. On all four, `UnitPrice` and `COLACalculatedPrice__c` hold the correct value but `NetUnitPrice` (the ordered money) does not. Single-year and the tier × Source_List seed (0.20 × 355 = 71 = Base_Price) DO conform.
- **Evidence:**
  - Active procedure confirmed: ESV **V14** sole `IsActive=true` (`9QMWC00000023eX4AQ`, ExpressionSet `9QLWC0000015cDl4AI`); 14 versions, only V14 active.
  - Canary **00781109** (`0Q0WC0000038aXd0AI`) QLI `0QLWC000003e2Sn4AI` PIA-PIA-RRM-PIAM, `Fortra_Product_Type__c`='Renewal Maintenance', `QuoteTypeText__c`='Renewal': ListPrice=0, NUP=60.64, UnitPrice=67.38, COLACalculatedPrice__c=67.38, Base_Price__c=71, Source_List_Price__c=355, Prior_Partner_Discount__c=8.52, Prior_Discretionary_Discount__c=0, COLA_Uplift_Percent__c=7.85.
  - Math: (71−8.52−0)×1.0785 = 67.38 (expected); committed 60.64 = 67.38×0.90; delta 6.74; pct error 10.00% (prior 12% partner already inside the 67.38 base; posthook re-applies ~10%).
  - 00781053: Base=71, PriorPart=8.52, PriorDisc=6.25, COLA=7.85 → expected 60.64, committed 54.58 (=60.64×0.90).
  - 00781043: COLACalc=67.38 but NUP=0 (structural unpriced node, never seeded).
  - 00781084: NUP=67.38=expected (born-Renew path).
  - Mechanism: `PartnerNetPricePosthook.buildRenewalMaintenanceColaUpdate` (L820) re-stamps `PartnerDiscountPercent` (L868-873) causing the engine to re-apply the partner margin to an already-net COLA value — engineer-owned LOGIC defect, not a data gap.

#### FAIL #2 (high) — BOKS-PROC-V14: V14 active but the COLA/partner elements mis-commit the renewal-maintenance net
- **Expected:** PIA-PIA-RRM-PIAM commits `NetUnitPrice` = `COLACalculatedPrice__c` = 67.38 = (71 − 8.52) × 1.0785; partner discount must NOT be re-applied because the COLA base already nets out the prior partner discount.
- **Actual:** Canary 00781109 commits NUP=NetTotalPrice=TotalLineAmount=PartnerUnitPrice=**60.64** with COLACalculatedPrice__c=67.38 (unchanged after a fresh Force reprice under live V14); 60.64 = 67.38×0.90, a −6.74/unit (~10%) under-collection. Across the BoKS renewal-maintenance population only **1 of 7** lines commits 67.38 (00382MH); the other 6 commit 60.64, 54.58, or $0 while COLACalculatedPrice__c is correct.
- **Evidence:**
  - Active version: ESV `9QMWC00000023eX4AQ` `VersionNumber=14` `IsActive=true` under ExpressionSet `9QLWC0000015cDl4AI`; V13/V12 inactive.
  - Reprice under live V14 returned `isSuccess=true` (`POST /connect/rev/sales-transaction/actions/place`, `pricingPref=Force`, `configurationMethod=Skip`) on `0Q0WC0000038aXd0AI`; post-reprice SOQL NUP=60.64, NetTotalPrice=60.64, TotalLineAmount=60.64, COLACalculatedPrice__c=67.38.
  - Math: (71−8.52)×1.0785 = 67.38 (== COLACalc); 67.38×0.90 = 60.64 (== committed NUP).
  - Live `PartnerNetPricePosthook` (`01pWC000002VmiLYAS`, ApiVersion 65, LastModified 2026-06-14T02:35Z) is v1.5 with the RN-COLA-COMMIT skip-gate present, yet the canary still commits 60.64 → **the v1.5 fix does not generalize across the BoKS renewal-maint population**.
  - Cross-quote BoKS RRM-PIAM committed vs COLA: `0Q0WC0000037AKH0A2`=0/67.38, `0Q0WC0000037XvB0AU`=0/67.38, `0Q0WC0000037muD0AQ`=54.58/60.64, `0Q0WC0000037yTx0AI`=60.64/67.38, `0Q0WC00000382MH0AY`=67.38/67.38 (only correct), `0Q0WC0000038aXd0AI`=60.64/67.38 (canary), `0Q0WC0000039AMb0AM`=54.58/60.64 → **1 of 7 correct**.

#### FAIL #3 (high) — BOKS-RN-PARTNER-DD: renewal maintenance double-discounted (60.64 instead of 67.38)
- **Expected:** Committed `NetUnitPrice` = 67.38 (the COLA net, where the 12% prior partner discount is already inside the 8.52 base), matching `COLACalculatedPrice__c`=67.38; no further partner re-discount.
- **Actual:** Committed NUP=**60.64** (=67.38×0.90) on `0QLWC000003e2Sn4AI`, while COLACalculatedPrice__c=67.38 and UnitPrice=67.38; `Pre_Partner_Price__c`=67.38 → `Partner_Adjusted_Price__c`=60.64 → `Partner_Pricing_Model_Applied__c`=Discount. Stable after a clean Force/Skip reprice.
- **Evidence:**
  - Partner fields prove the seeded 67.38 was fed into the partner-discount path: Pre_Partner_Price__c=67.38, Partner_Adjusted_Price__c=60.64, Partner_Pricing_Model_Applied__c='Discount'.
  - `PartnerNetPricePosthook.cls` v1.4: `buildRenewalMaintenanceColaUpdate` (L803-871) seeds NUP/UnitPrice/COLACalculatedPrice__c = colaNet = 67.38; `computeRenewalMaintenanceColaNet` (L890-905) subtracts `Prior_Partner_Discount__c`, so the 12% partner is already in the base.
  - `calculateDeferredPartnerPrice` (L360-401) reads the seeded NUP as `currentPrice` and re-applies `PartnerPricingService.calculateDiscountPrice(67.38, 10%)` = 60.64 — **the double-discount**.
  - Data is complete (Source_List_Price__c=355, COLA_Uplift_Percent__c=7.85, Base_Price__c populated) → not data-rooted; the defect is posthook logic ordering.

#### FAIL #4 (high) — BOKS-RN-COMMIT-AUTOADD: auto-added (No-Change) renewal-maint line commits 60.64 instead of 67.38
- **Expected:** NUP/NetTotalPrice/TotalPrice = 67.38 (COLA net = (71 − 8.52 − 0) × 1.0785), with no second partner discount.
- **Actual:** After a fresh managed V14 reprice the committed NUP=NetTotalPrice=TotalPrice=**60.64** (= 67.38×0.90); COLACalculatedPrice__c=67.38 and UnitPrice=67.38 are correct but not committed to Net. Provenance proves double-discount: Pre_Partner_Price__c=67.38, Partner_Adjusted_Price__c=60.64, PartnerDiscountPercent=12, `QuoteActionId=null` (auto-added, not Renew-born).
- **Evidence:**
  - 00781109 / `0Q0WC0000038aXd0AI`, Status=Draft, USD; line `0QLWC000003e2Sn4AI`, Product2 `01tWC00000DD1buYAD`, PIA-PIA-RRM-PIAM.
  - Reprice (`pricingPref=Force`, `configurationPref=Skip`) returned `isSuccess=true`; post-reprice NUP=60.64, UnitPrice=67.38, COLACalculatedPrice__c=67.38.
  - COLA inputs: Base_Price__c=71, Prior_Partner_Discount__c=8.52, Prior_Discretionary_Discount__c=0, COLA_Uplift_Percent__c=7.85, Fortra_Product_Type__c='Renewal Maintenance', Quote.QuoteTypeText__c='Renewal'.
  - Mechanism: the fixed `buildRenewalMaintenanceColaUpdate` (L803-871) / `computeRenewalMaintenanceColaNet` (L890-905) stamps colaNet without re-discount but is **bypassed**; the generic `calculateDeferredPartnerPrice` (L400) re-applies the partner margin on the 67.38 base. Contrast: born-Renew Q00781084 commits the correct 67.38.

#### FAIL #5 (high) — BOKS-MAINT-ONLY: maintenance-only renewal GrandTotal 60.64 instead of 67.38
- **Expected:** GrandTotal = 67.38 (single derived renewal-maint line, qty 1; COLA net (71 − 8.52 − 0) × 1.0785 = 67.38 correctly stamped).
- **Actual:** GrandTotal = **60.64**; line NUP=NetTotalPrice=TotalPrice=PartnerUnitPrice=60.64. Trace: Pre_Partner_Price__c=67.38 → Partner_Adjusted_Price__c=60.64 (=67.38×0.90), Partner_Pricing_Source__c='System Calculated (Pre-Procedure, Deferred List)'. The 12% partner discount is ALREADY inside the 67.38 base (Prior_Partner_Discount__c=8.52=71×12%), so the deferred-list partner path re-applies a 10% partner margin → double-discount, understating committed money by 6.74 (~10%). Reproduced live after a fresh Skip-config reprice on active V14 + PartnerNetPricePosthook v1.4. The v1.4 short-circuit did not win on this maint-only line.
- **Evidence:**
  - 00781109 / `0Q0WC0000038aXd0AI`: GrandTotal=60.64, TotalPrice=60.64, Status=Draft, single QLI (line count=1) → true maintenance-only renewal.
  - QLI `0QLWC000003e2Sn4AI` PIA-PIA-RRM-PIAM (`01tWC00000DD1buYAD`): COLACalculatedPrice__c=67.38, UnitPrice=67.38, NUP=60.64, NetTotalPrice=60.64, PartnerUnitPrice=60.64, Pre_Partner_Price__c=67.38, Partner_Adjusted_Price__c=60.64.
  - Drivers: Base_Price__c=71, Prior_Partner_Discount__c=8.52 (=71×12%), Prior_Discretionary_Discount__c=0, PartnerDiscountPercent=12, COLA_Uplift_Percent__c=7.85, Quote.QuoteTypeText__c='Renewal', Partner_Pricing_Model__c='Discount', Billing_Partner__c=`001WC00000ZtazZYAR`.
  - Active `PartnerNetPricePosthook` `01pWC000002VmiLYAS` (LastModified 2026-06-14T02:35Z, LengthWithoutComments=35566, fresh v1.4); defect path = `calculateDeferredPartnerPrice` → `PartnerPricingService.calculateDiscountPrice(67.38,10%)` = 60.64.

#### FAIL #6 (high) — BOKS-MULTI-ASSET: derived maintenance commits $0 on a partner multi-asset quote
- **Expected:** License PIA-PIA-NRPS-PIAP and its derived maintenance PIA-PIA-RNM-PIAMBK both commit correct net. Standard path: 355 + 71 (71 = 355 × 0.20). Partner Discount path: 301.75 license + ~62.48 maintenance (71 × 0.88), as proven on 4 Accepted DPP quotes.
- **Actual:** Partner quote **Q-Maint 3** (`0Q0WC000003735t0AA`), Force-repriced `isSuccess=true`: license NUP=301.75 **CORRECT**; derived maintenance NUP=**0**, NetTotalPrice=0, `Source_List_Price__c=null` — commits $0. (Standard non-partner multi-asset Q-Wren copy `0Q0WC0000037rFZ0AY` passes: 355 + 71.)
- **Evidence:**
  - Force reprice (`configurationPref=Skip`) of `0Q0WC000003735t0AA` → `isSuccess:true`; post-reprice PIA-PIA-NRPS-PIAP NUP=301.75, PIA-PIA-RNM-PIAMBK NUP=0/NetTotalPrice=0/Source_List_Price__c=null (LastModified 2026-06-14T19:10:53Z).
  - Standard multi-asset Q-Wren copy `0Q0WC0000037rFZ0AY` → license 355×10, derived maint 71×9 BOTH CORRECT (path passes).
  - PBEDP `182WC000000FN26YAG` present and correct: PIAMBK derives from license PIAP, Formula=UnitPrice, scope=Both, source=Product → **config is NOT the gap**.
  - 4 Accepted partner quotes priced the same RNM maintenance to 62.48; only this Q-Maint 3 line is $0.
  - Failing line `0QLWC000003cFh44AE` has Source_List_Price=null vs passing line `0QLWC000003cGRp4AM` Source_List_Price=355 → derivation never seeded the maintenance base.
  - `PartnerNetPricePosthook.calculateDeferredPartnerPrice` (L394-397) bails `if (currentPrice == null || currentPrice <= 0) return null` → with unseeded base 0 the posthook cannot recover, line commits $0.
  - Class header confirms derivation+posthook own this line: "Derived maintenance lines also have UnitPrice/ListPrice = 0 until DPP formulas run in-procedure" + "Apply deferred partner pricing on derived maintenance when needed".
  - Evidence file: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_boks/work/boks-multi-asset/FINDINGS.txt`.

### Notable passes

- **BOKS-RN-COMMIT-RENEW (the control that localizes the defect):** the line born with `QuoteAction.Type='Renew'` (Q00781084, `0Q0WC00000382MH0AY`, line `0QLWC000003dEW24AM`) commits NUP=UnitPrice=COLACalc=**67.38** and stays stable across a fresh managed reprice. The *only* structural difference from the failing canary is provenance: Renew-born vs auto-added (`QuoteActionId=null`). This pass is the proof that the creation-path born-net avoids the posthook re-discount — and is the basis of Fix Option A below.
- **BOKS-NB-FORMULA:** the new-business derived arm prices through the live `MTD`-gated Source_List × tier formula; the alternate Base × tier arm is gated by `AttributeDefinitionCode='MDT'`, which returns 0 AttributeDefinition rows (the code does not exist), so that arm is unreachable dead code — it never affects committed money. This isolates new-business pricing to a single, proven formula path.
- **BOKS-B4-NULLGUARD:** V14's Renewal COLA formula (`V140.expressionSetVersion` L2043) wraps Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, and COLA_Uplift_Percent__c each in `IF(ISNULL(x),0,x)`, with the upstream assignment additionally gated by `AdvancedListFilter COLA_Uplift_Percent__c IsNotNull AND SalesTransactionActionType='Renew'`. The formula layer cannot leak null/0 — confirming the $0 in BOKS-MULTI-ASSET originates in the posthook bail, not the formula.
- **BOKS-MULTIYEAR (out-of-scope):** active V14 references zero out-year / MyCAP / multi-year / final-year tokens; 0 maintenance-family QLIs have out-year populated or `PricingTermCount>1`; the half-built compounding loop and broken display-only `Final_Year_COLA_Calculated_Price__c` write no committed money. Confirmed inert and out-of-scope per the single-year SDD (BR-002) / User Story Req #5.

---

## Fix plan (engineer-owned, ordered)

All six failures collapse to one defect family: the renewal-maintenance commit path re-applies the partner margin to an already-partner-net COLA price (and, in the unseeded variant, bails to $0). The COLA computation, stamping, rate selection, and null-guarding are all correct. Two fixes resolve the entire set.

### Fix 1 (P0) — Suppress the posthook partner re-discount on COLA-seeded BoKS renewal-maintenance lines
Resolves **BOKS-SDD-CONFORMANCE, BOKS-PROC-V14, BOKS-RN-PARTNER-DD, BOKS-RN-COMMIT-AUTOADD, BOKS-MAINT-ONLY** (and the discount half of multi-asset).

- **Root cause:** In `PartnerNetPricePosthook.cls`, `buildRenewalMaintenanceColaUpdate` (L803-871) correctly seeds `NetUnitPrice`/`UnitPrice`/`COLACalculatedPrice__c` = colaNet (= (Base − PriorPartner − PriorDisc) × (1+COLA/100)), in which the prior partner discount is already netted out. But the generic deferred path `calculateDeferredPartnerPrice` (L360-401) then reads the seeded `NetUnitPrice` as `currentPrice` and re-applies `PartnerPricingService.calculateDiscountPrice(colaNet, 10%)` → 67.38 × 0.90 = 60.64. The v1.4/v1.5 short-circuit (skip-gate / `buildNetPriceUpdate` returns null for renewal-maint) does not win across the population — it only fires on the Renew-born path, leaving auto-added and maintenance-only lines double-discounted.
- **Fix:** Make the renewal-maintenance suppression authoritative and provenance-independent. In `calculateDeferredPartnerPrice` (and any `buildNetPriceUpdate` branch reachable for these lines), short-circuit `return null`/no-op when the line is a COLA-seeded renewal-maintenance line — gate on `Fortra_Product_Type__c='Renewal Maintenance' AND Quote.QuoteTypeText__c='Renewal' AND COLACalculatedPrice__c != null AND COLACalculatedPrice__c > 0`. Do NOT gate on `QuoteActionId` (that is exactly what makes the current short-circuit miss the auto-added/maintenance-only lines). The COLA base already contains the partner discount (`Prior_Partner_Discount__c` was subtracted in `computeRenewalMaintenanceColaNet`), so the committed net must be `COLACalculatedPrice__c` verbatim.
- **Verify:** Force/Skip reprice on 00781109, 00781053, 00781043, 00781084 → committed `NetUnitPrice` must equal `COLACalculatedPrice__c` on all four (67.38 / 60.64 / 67.38 / 67.38); population check on the 7 BoKS RRM-PIAM lines → 7/7 committed == COLA (currently 1/7).

### Fix 2 (P0, alternative/complement) — Creation-path born-net for auto-added renewal-maintenance lines
Resolves the auto-add/No-Change provenance gap directly (**BOKS-RN-COMMIT-AUTOADD**, and removes the asymmetry behind **BOKS-MAINT-ONLY** / **BOKS-PROC-V14**).

- **Rationale:** The control scenario BOKS-RN-COMMIT-RENEW proves the *born-net* path is correct — the line created with `QuoteAction.Type='Renew'` via `COLAUpliftHandler` commits 67.38 because its net is born correct and the posthook does not re-discount it. The defective lines differ only in that they are auto-added with `QuoteActionId=null`.
- **Fix:** Ensure the auto-added No-Change renewal-maintenance line is born with the COLA net (and the suppression flag/provenance the posthook respects) the same way the Renew-born line is — i.e., have the creation/COLA-handler path stamp the committed net (not just `COLACalculatedPrice__c`/`UnitPrice`) so the line enters the procedure already at its final net, matching the proven-correct born-Renew behavior.
- **Verify:** Auto-added line on 00781109 commits 67.38 (matches the Renew-born 00781084 control); GrandTotal on the maintenance-only quote = 67.38.

> Recommended sequencing: ship **Fix 1** first (it is the localized, provenance-independent suppression that closes five of six failures with the least surface area), then apply **Fix 2** as the creation-path hardening so both the born-Renew and auto-added paths converge on identical committed net regardless of provenance.

### Fix 3 (P1) — Seed the derived maintenance base before the deferred-partner bail (multi-asset $0)
Resolves the $0 half of **BOKS-MULTI-ASSET**.

- **Root cause:** On the partner multi-asset quote the derived maintenance line's `Source_List_Price__c` is null and its base is never seeded (0); `calculateDeferredPartnerPrice` (L394-397) bails on `currentPrice <= 0 → return null`, so the line commits $0. Config is correct (PBEDP `182WC000000FN26YAG` present, Formula=UnitPrice, scope=Both); the standard non-partner multi-asset path seeds 71 fine, so this is a derivation/posthook ordering gap specific to the partner multi-asset case, not a data gap.
- **Fix:** Ensure the derived maintenance base (`Source_List_Price__c` ← contributing-license PBE UnitPrice 355 → tier × 0.20 = 71) is seeded before the deferred-partner step on partner multi-asset lines, so the posthook receives a non-zero `currentPrice` and applies the single correct partner discount (71 × 0.88 = 62.48) instead of bailing to $0. Confirm the seeding runs for every derived maintenance line on multi-asset quotes regardless of partner-model branch.
- **Verify:** Force reprice Q-Maint 3 (`0Q0WC000003735t0AA`) → derived PIAMBK commits 62.48 (= 71 × 0.88), Source_List_Price__c=355; non-partner Q-Wren copy still 71.

---

## Appendix (BoKS ids, formulas)

### Sanctioned BoKS product set
| Product | ProductCode | Product2 Id | Fortra_Product_Type__c | Catalog |
|---|---|---|---|---|
| Powertech IAM BoKS (license/perpetual) | PIA-PIA-NRPS-PIAP | `01tWC00000DD1btYAD` | Perpetual | Visible (PCP `0ZRWC000000Aig54AC` → Category `0ZGWC0000007iz54AA` "Powertech Identity & Access Manager (BoKS)" → Catalog `0ZSWC00000071XG4AY` "Tech") |
| BoKS New Maintenance (Year-1) | PIA-PIA-RNM-PIAMBK | `01tWC00000DD1bsYAD` | New Maintenance | Absent (0 PCP rows) — expected |
| BoKS Renewal Maintenance | PIA-PIA-RRM-PIAM | `01tWC00000DD1buYAD` | Renewal Maintenance | Absent (0 PCP rows) — expected |

### Key pricing config ids
| Entity | Id | Note |
|---|---|---|
| Active pricing procedure ExpressionSet | `9QLWC0000015cDl4AI` | `Rev_Mgmt_Default_Pricing_Procedure` |
| Active ExpressionSetVersion (V14) | `9QMWC00000023eX4AQ` | `VersionNumber=14`, `IsActive=true`; V13/V12 inactive |
| Active ExpressionSetDefinitionVersion | `9QBWC0000000nIT4AY` | `VersionNumber=14`, Status=Active |
| Active posthook | `PartnerNetPricePosthook` `01pWC000002VmiLYAS` | ApiVersion 65, LastModified 2026-06-14T02:35Z, v1.4/v1.5 |
| Year-1 AutoAdd rule | `14OWC0000022ULp2AM` | Active Configurator/Transaction; PIAP + QuoteType=New → AutoAdd PIAMBK |
| Year-2 (Renewal) AutoAdd rule | `14OWC0000022Eyb2AE` | Active; QuoteType=Renewal → AutoAdd PIAM |
| License PBE (USD) | `01uWC000005ws8MYAQ` | UnitPrice=355 on RLM pricebook `01sWC0000022GHFYA2` |
| Derived PBEDP (PIAMBK ← PIAP) | `182WC000000FN26YAG` | Formula=UnitPrice, scope=Both, source=Product |
| Derived PBEDP (PIAM ← PIAP) | `182WC000000FN2tYAG` (+`000HNcvYAG`,`000HNcwYAG`) | Formula=UnitPrice, source=Product |
| BoKS COLA rule (CMDT) | `COLA_Uplift_Rules__mdt` `m0eWC000003G7vKYAS` | "Powertech IAM BoKS", `Default_Uplift_Percent__c=7.85`, `Is_Active__c=true` |
| AttributeDefinition (live formula gate) | `MTD` = "Maintenance Type Defn" (Picklist) | `MDT` does NOT exist → Base × tier NB arm is dead code |

### Canary records
| Quote | Quote Id | Key line | Note |
|---|---|---|---|
| 00781109 (renewal canary) | `0Q0WC0000038aXd0AI` | `0QLWC000003e2Sn4AI` PIA-PIA-RRM-PIAM | Auto-added No-Change; COLACalc=67.38, committed NUP=60.64 (FAIL) |
| 00781084 (control) | `0Q0WC00000382MH0AY` | `0QLWC000003dEW24AM` PIA-PIA-RRM-PIAM | Born QuoteAction.Type='Renew'; committed NUP=67.38 (PASS) |
| 00781053 | — | PIA-PIA-RRM-PIAM | Expected 60.64, committed 54.58 (=60.64×0.90) |
| 00781043 | — | PIA-PIA-RRM-PIAM | COLACalc=67.38, committed NUP=0 (unpriced node) |
| Q-Maint 3 (partner multi-asset) | `0Q0WC000003735t0AA` | `0QLWC000003cFh44AE` PIA-PIA-RNM-PIAMBK | Derived maint commits $0 (Source_List_Price__c=null) |
| Q-Wren copy (standard multi-asset) | `0Q0WC0000037rFZ0AY` | PIA-PIA-RNM-PIAMBK | License 355×10 + derived maint 71×9 (PASS) |
| NB derived canary | `0Q0WC0000037rFZ0AY` | `0QLWC000003d2QU4AY` | NUP=71 = 0.20 × 355 (PASS) |
| Renewal-license canary | `0Q0WC0000037AiT0AU` | PIA-PIA-NRPS-PIAP, QuoteAction='No Change' | NUP=301.75 = 355×0.85, no COLA (PASS) |

### Formulas (as committed in V14 + posthook)
- **New-business derived seed:** `NetUnitPrice = tier_rate × Source_List_Price__c` = `0.20 × 355 = 71` (Standard/Professional=0.20, Premier=0.30). Live arm gated by `AttributeDefinitionCode='MTD'` (`DerivedPricingFormula`, ListContainer9 seq2). The `DerivedPricingNewBusiness` Base × tier arm is gated by `'MDT'` (non-existent) → dead.
- **Renewal COLA (carry-forward, single-year, HALF_UP):**
  `COLACalculatedPrice__c = (Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA_Uplift_Percent__c/100)`
  = `(71 − 8.52 − 0) × 1.0785 = 67.3847 → 67.38`. (With `Prior_Discretionary_Discount__c=6.25`: `(71 − 8.52 − 6.25) × 1.0785 = 60.64`.) V14 formula ISNULL-guards every input.
- **Partner discount (by product type):** Perpetual/Software → `Software_Percent__c` 15%; New Maintenance → `New_Maintenance_Percent__c` 12%; Renewal Maintenance → `Renewal_Maintenance_Percent__c` 10%. License: `355 × 0.85 = 301.75`. New-Maint: `71 × 0.88 = 62.48`.
- **The defect (double-discount):** posthook re-applies the renewal-maint 10% partner margin onto the already-net COLA value → `67.38 × 0.90 = 60.64` (and `60.64 × 0.90 = 54.58` when prior-discretionary is present). The prior 12% partner discount is already inside the COLA base via `Prior_Partner_Discount__c` (`71 × 12% = 8.52`), so any further partner discount is a double-count.

### Source / evidence locations
- Posthook source: `Org Data/_src/classes/PartnerNetPricePosthook.cls` (also live `01pWC000002VmiLYAS`).
- Multi-asset findings: `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/e2e_boks/work/boks-multi-asset/FINDINGS.txt`.
- Nir DPP scope FYI: `Data/sc-maint/sc3346_e2e/NIR_DPP_SCOPE_FYI.md` ("Maintenance Product won't be shown on Catalog — that is expected").
- Multi-year verdict (out-of-scope): `Data/sc-maint/sc3346_fix/rn_multiyear/RN_MULTIYEAR_VERDICT.md`.