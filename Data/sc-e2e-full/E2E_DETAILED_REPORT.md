# RCA Quote-to-Order E2E Test Report (Integration excluded)

**Report date:** 2026-06-13 · **Org:** FortraUAT · **Author:** E2E test lead · **Audience:** engineers + build owner

---

## Run metadata

| Item | Value |
|---|---|
| Org | FortraUAT (Revenue Cloud Advanced / RLM native) |
| Active pricing procedure | `Rev_Mgmt_Default_Pricing_Procedure` **V14** (ExpressionSet `9QLWC0000015cDl4AI`) — confirmed live by harness `isSuccess`; memory notes citing V9/V12/V13 are stale (versions churn daily, always trust live) |
| Active Apex hooks | `COLAUpliftPrehook` v1.1, `PartnerNetPricePosthook` v1.4, `PartnerPricingService`, `RegionalServicesPricingPrehook` v13.3, `AttributeVolumePricingPrehook` v3.0, `HardwareAttributePricingPrehook` v3.0; `SourceListPricePrehook` = disabled no-op stub |
| Reprice harness (sanctioned) | `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` with `{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{...PATCH Quote\|Order...}}`. `configurationPref` Skip is mandatory (omitting it re-runs configuration and can collapse/replace lines). Verified working on v64.0 and v67.0. |
| Order reprice (sanctioned, activation-free) | `OrderRepriceInvocable.reprice(...)` (Apex) **or** Order-typed Place Sales Transaction. Both leave `Status` unchanged → Workday-safe. |
| Scope | Quote pricing → Quote-to-Order conversion → Order pricing → Order-submission validation → DocGen content. |
| Excluded by design | Workday / MuleSoft integration (Order activation, `Status='Order Complete'`, `Order_Completed_WD__e`, contract-line decomposition for Workday) — SC-3347 / SC-3210 / MuleSoft `extendedAmount`. |
| Guardrails honored | No record/metadata delete; no Order activation or submission; no platform events published; no direct Quote/QLI DML (RLM-blocked); Accepted/Ordered/In Review/Approved/Presented quotes read-only (esp. 00781068, 00780507, 00734122). |

**Method note:** Quote/QLI direct DML is blocked by RLM at the platform tier; every quote reprice went through the managed Place Sales Transaction API with `configurationMethod=Skip`. Order/OrderItem DML is *not* blocked, so existing Draft orders were repriced/inspected in place. No new quote could be headlessly converted to an order within guardrails (see Coverage & gaps).

---

## Results at a glance

**Counts (27 scenarios):**

| Bucket | Count | Scenarios |
|---|---|---|
| **PASS** | 13 | NB-PERP, NB-SVC, RN-LIC, RN-SUB, AMEND, MOD-PART15, QO-CONVERT, QO-DECOMP, VAL-REQ, VAL-SUBMIT, CFG-AUTOMAINT, DOC-PDF, TOT-ALE |
| **FAIL — known issue (attributed to ticket)** | 8 | NB-MAINT (SC-3372), NB-TIER (SC-3384 $0-net), NB-BUNDLE (SC-3384), RN-MAINT (SC-3404), MOD-PART12 (SC-3404), MOD-LDISC (SC-3359), MOD-CUR-AUD (SC-3384), MOD-CUR-EUR (SC-3384), MOD-CUR-USDONLY (SC-3384), QO-PRICEPARITY (SC-3359) |
| **FAIL — regression / un-ticketed** | 1 | MOD-REGION (regional price computed but not committed in V14) |
| **PARTIAL** | 4 | NB-HW, MOD-QDISC, TOT-CONSIST, NB-BUNDLE |
| **OUT-OF-SCOPE touched** | 0 standalone (integration excluded throughout) |

> Note: NB-BUNDLE is counted once as **partial** (USD path passes; CAD path fails on SC-3384). The known-issue FAIL row lists the failing currency paths; the partial row reflects the per-scenario verdict. The fail bucket above lists 10 underlying failing paths across the 9 distinct FAIL/partial scenarios that carry a known-issue ticket.

**One row per scenario:**

| ID | Domain | Title | Status | Severity | Known-issue / ticket |
|---|---|---|---|---|---|
| NB-PERP | New-business | Perpetual/license net pricing | **pass** | none | — |
| NB-MAINT | New-business | Maintenance derived + auto-add | **fail** | high | known · SC-3372 |
| NB-SVC | New-business | Services-only catalog pricing | **pass** | none | — |
| NB-HW | New-business | Hardware attribute pricing | **partial** | medium | new (2 defects) |
| NB-TIER | New-business | Tiered / attribute-volume | **fail** | high | known · SC-3384 ($0-net) |
| NB-BUNDLE | New-business | Bundle / config-rule pricing | **partial** | high | known · SC-3384 (CAD path) |
| RN-LIC | Renewal | Renewal license COLA uplift | **pass** | none | — |
| RN-MAINT | Renewal | Renewal maintenance COLA net | **fail** | high | known · SC-3404 |
| RN-SUB | Renewal | Renewal subscription pricing | **pass** | none | — |
| AMEND | Renewal | Amendment quote pricing | **pass** | none | — |
| MOD-PART12 | Modifiers | Partner discount 12% (renewal-maint) | **fail** | high | known · SC-3404 |
| MOD-PART15 | Modifiers | Partner discount 15% | **pass** | none | — |
| MOD-QDISC | Modifiers | Quote-level header discount | **partial** | medium | new (functional gap) |
| MOD-LDISC | Modifiers | Line partner + discretionary | **fail** | high | known · SC-3359 (variant) |
| MOD-CUR-AUD | Modifiers | Multi-currency AUD net | **fail** | high | known · SC-3384 |
| MOD-CUR-EUR | Modifiers | Multi-currency EUR configured | **fail** | high | known · SC-3384 |
| MOD-CUR-USDONLY | Modifiers | Non-USD configured + JPY rate | **fail** | high | known · SC-3384 |
| MOD-REGION | Modifiers | Regional services (Italy 0.64) | **fail** | high | **regression (un-ticketed)** |
| TOT-CONSIST | Totals | Multi-line totals consistency | **partial** | medium | known · SC-3345 (TDA residue) |
| TOT-ALE | Totals | ALE + Services aggregate + stale | **pass** | none | — |
| QO-CONVERT | Quote-to-Order | Convert + field mapping | **pass** | none | — |
| QO-PRICEPARITY | Quote-to-Order | Order pricing parity vs quote | **fail** | high | known · SC-3359 (variant) |
| QO-DECOMP | Quote-to-Order | Order line decomposition | **pass** | none | — |
| VAL-REQ | Validation | Required-fields completeness | **pass** | none | — (SC-3338 enhancement) |
| VAL-SUBMIT | Validation | Order-submit validation | **pass** | none | — (SC-3291) |
| CFG-AUTOMAINT | Configuration | Auto-add first-year maintenance | **pass** | low | secondary · SC-3372 |
| DOC-PDF | DocGen | Quote PDF pricing + descriptions | **pass** | none | — (SC-3335/3349) |

---

## Domain-by-domain detail

### Domain: New-business pricing

#### NB-PERP — Perpetual/license net pricing · **PASS**
- **Expected:** `NetUnitPrice = ListPrice × (1 − PartnerDiscount%/100) × (1 − Discount%/100)`; when both zero, net = list; with discretionary present, committed net = lower of procedure-net vs raw partner-net (PartnerUnitPrice preserves the raw partner net).
- **Actual:** Every Perpetual line matched exactly.
  - Baseline 00781106 / `0Q0WC0000038U7F0AU`: DM-WCU-NRPS-5250PE List 3675, partner 0, disc 0 → net = list = 3675; header Subtotal=TotalPrice=GrandTotal=18675, Discount=0. Live reprice `isSuccess:true`.
  - Partner-only 00780964 / `0Q0WC000003735t0AA`: PIA-PIA-NRPS-PIAP List 355, partner 15% → 355×0.85 = **301.75** committed (PartnerUnitPrice 301.75, Pre_Partner_Price__c 355, model Discount). Live reprice `isSuccess:true`, stable.
  - Partner+discretionary (committed, read-only) `0QLWC000003clIj4AI`: List 355, partner 15, disc 10 → procedure-net 271.58, partner-net 301.75, commercial = lower = **271.58** (PartnerUnitPrice stays 301.75).
  - 20% Guaranteed-Margin (committed) `0QLWC000003broP4AQ`: List 2008 × 0.80 = **1606.40**.
- **Verdict:** SC-3359 NOT reproduced on Perpetual; partner net is applied on every line tested. Operational caveat: the Quote VR `Quote_BillToPlacceAcct_Equal_QuoteAcct` re-fires on every managed reprice and blocked the harness on quotes with inconsistent Bill-To-Place data (00380330, 00780927) — a data-state issue, not a pricing defect.

#### NB-MAINT — Maintenance derived + auto-add (SC-3346) · **FAIL (known · SC-3372)** · high
- **Expected:** After reprice, each auto-added first-year maintenance line (ListPrice=0) computes a derived `NetUnitPrice` from its contributing perpetual via native DerivedPricing + a `PriceBookEntryDerivedPrice` config row, and stamps `Source_List_Price__c` = parent ListPrice. Working contrast: Order 00095394 line FIM-FIM-RNM-VEMENM priced 7992.5 with Source_List_Price__c=34750 (it *has* a config row).
- **Actual:** Reprice of 00307854 (GS-GSE-RNM-* New Maintenance) and 00407375 (GS-GSE-RRM-* Renewal Maintenance) returned `isSuccess:true` / `CompletedWithPricing`; contributing perpetual lines priced fine (e.g. GS-GSE-NRPS-EFT7 net 5987.85), **but every derived-maintenance line committed `NetUnitPrice=null`, `TotalLineAmount=null`, `Source_List_Price__c=null`**. They only carry stale legacy NetTotalPrice values (1164.76 / 388.29 / 140.9 ... on 00307854) the engine did not recompute.
- **Root cause / evidence:** These 6 derived PBEs have **0** `PriceBookEntryDerivedPrice` config rows. Org-wide: **176 config rows vs 3,453 IsDerived PBEs (5.1% covered)** → ~95% of derived-maintenance products uncovered; native DerivedPricing produces no value. `CompletedWithPricing` is a false positive here.
- **Verdict:** Known systemic SC-3372 gap (the same gap that gates the SC-3346 build; SC-3403 peer review NO-GO). The auto-add itself works (lines exist); the *pricing* of those lines fails. Do not count carried NetTotalPrice as engine output.

#### NB-SVC — Services-only catalog pricing · **PASS**
- **Expected:** USD, US-ship, no partner/discretionary discount → each Services line nets to list (15000); US multiplier 1.0 → no regional adjustment (audit fields null); `Total_Services__c` = sum of Services-line net.
- **Actual (00781102 / `0Q0WC0000038Rir0AE`):** After reprice (`isSuccess:true`), both lines: NetUnitPrice=15000=ListPrice, NetTotalPrice=TotalLineAmount=30000, `Regional_NetUnit_Price__c`/`PrehookRSNetUnitPrice__c`=null. Header: GrandTotal=TotalPrice=Subtotal=ALE=60000, Total_Services__c=60000, Discount=0, TDA=0, `CompletedWithPricing`. USD catalog PBE = 15000 (parity). Line count unchanged 2→2.
- **Verdict:** Clean PASS. Secondary observations out of scope: partner-Services quote 00380153 blocked by Bill-To-Place VR (data); EUR quote 00780956 VMA net 500 > list 460 belongs to the SC-3384 family.

#### NB-HW — Hardware attribute pricing · **PARTIAL** · medium · **2 new defects**
- **Expected:** `AdjustedPrice = ListPrice × pGroupMult × userTierMult × (1 − sysTypeDiscount/100)` via `HardwareAttributePricingPrehook` v3.0; no-attribute lines fall to System Default (P20/Production/1u = 1.0×) and stay at catalog; audit fields reflect the adjustment.
- **Actual:**
  - **Engine wired + fires:** debug log `07LWC00000OxmQz2AJ` (reprice of 00781106) shows `HardwareAttributePricingPrehook v3.0 START ... 2 items updated`.
  - **Formula correct:** `HardwareAttributePricingPrehookTest` 57/57 pass; canonical scenarios verified (P30×75u×Production = 2.25× → $22,500; P10×25u×Test = 0.46875× → $4,687.50); independent replication matches.
  - **No-attribute path passes E2E:** 00781106 lines resolved System Default → 1.000× → stayed at 3675 / 15000; `isSuccess:true`, line count/Ids preserved.
- **Why partial — could not exercise a non-1.0 multiplier flowing to net headlessly** (no Draft quote has a positive-price line with a valid/matched HW attribute; Configurator UI out of scope; Skip + RLM DML lock prevent setting attributes), **plus two genuine defects:**
  - **Defect A (reprice-breaker, 57 QLIAs):** Draft 00437231 5250 line carries QLIA `Pgroup='P5'`; reprice **FAILS** `INVALID_API_INPUT` "Enter an Attribute Picklist Value that is in an active or draft state." (`P5` value `0v6WC0000000AAbYAM` is Inactive). 57 of 163 Pgroup QLIAs store inactive `P5`. Corollary: the prehook map keys are `P05/P10/…`, so even if accepted, `P5` → default 1.0× (silently no discount; expected P05=0.5×).
  - **Defect B (persistence gap):** 0 QuoteLineItems org-wide ever have `Hardware_Pricing_Applied__c=true`; the 7 `Hardware_Reference__c`-linked QLIs show `Applied=False`, Multiplier/Pre-price null; OrderItem has no HW-pricing fields at all. Prehook context writes are never committed → HW-applied lines are indistinguishable from catalog downstream and unverifiable on the order.
- **Verdict:** Discovery's "Hardware = N/A" premise is corrected — hardware pricing is real, live, and well-tested, but two defects (A material) plus a coverage gap prevent a full E2E PASS. Recommend (a) data-fix the 57 `P5` QLIAs to `P05` (or add active alias + map key), (b) confirm HW audit-field persistence intent, (c) build a Configurator Draft quote with P30/Users>10 to assert net = list × mult.

#### NB-TIER — Tiered / attribute-volume (SC-3390) · **FAIL (known · SC-3384 $0-net)** · high
- **Expected:** First-click tier resolution (SC-3390 fix: IsPriceImpacting=true) **and** V14 commits the resolved tier into net. E.g. CLSACH qty50 'Managed' Vol=50 → tier [50-99] 'Total Price' Tier_Value=1957.20 → NetTotalPrice=1957.20.
- **Actual:** **SC-3390 first-click resolution WORKS** (volume hydrated, tier matched on the first reprice pass; confirmed twice) — but **committed net is $0 on all three lines**. The prehook correctly wrote `Base_Price__c` + `Attribute_Price_Mode__c` (CLSACH 1957.20/'Total Price'; CLSAAS 2180/'Unit Price') and even landed UnitPrice=1957.20, yet `NetUnitPrice=NetTotalPrice=TotalLineAmount=0` and Quote Subtotal/TotalPrice/GrandTotal/Total_Subscription__c all 0.
- **Evidence:** Debug `07LWC00000OxmIv2AJ` (00781108): "MATCH … PriceMode=Total Price, BasePrice=1957.200000" on the FIRST pass; context FINAL shows `Base_Price__c=1957.2` but `ItemNetTotalPrice=0E-16`, `NetUnitPrice=0.0`. Debug `07LWC00000Oxmh72AB` (00781107): both CLSAAS lines Vol=null → documented RESET-to-ListPrice path (working) but net still 0.
- **Verdict:** SC-3390 is genuinely FIXED and durable — **do not attribute this to SC-3390**. The break is downstream: the V14 step that should consume `Base_Price__c`/`Attribute_Price_Mode__c` into the net channel ('Total Price'→ItemNetTotalPrice; 'Unit Price'→InputUnitPrice) does not fire. This is the SC-3384 "$0-net" family. **Severity high** — every tiered line on this org currently commits $0, which would carry $0 into an order. **Recommend a dedicated ticket** for "attribute-volume tier resolves but net commits $0 on V14."

#### NB-BUNDLE — Bundle / config-rule pricing · **PARTIAL** · high · **known SC-3384 on CAD path**
- **Expected:** USD flat-include bundle CYB-DCS-ESS-BUN-V2 (`DoesBundlePriceIncludeChild=true`): List 5000, qty 10 → NetTotalPrice 50000. CAD configured bundle: BI-ISA-NRPS-IACP List 3375 CAD → net should equal CAD list.
- **Actual:**
  - **USD 00307075 PASSES exactly:** reprice `isSuccess:true`; List 5000, NetUnitPrice 5000, NetTotalPrice 50000; header Subtotal=TotalPrice=GrandTotal=ALE=50000; single bundle line preserved. 16 children all flat-include.
  - **CAD 00437346 FAILS (SC-3384):** reprice blocked by Bill-To-Place VR (validated committed state instead). BI-ISA-NRPS-IACP shows ListPrice **3375** (CAD-correct) but **NetUnitPrice 2500** (= the USD Standard PBE value; CAD FX 1.35 not applied). The Robot bundle parent/component $0 lines are *legitimate* (their CAD Standard PBE = 0; bundle price lives only in the unused Fortra Price Book).
- **Verdict:** Bundle mechanism (flat-include, component decomposition, list-channel currency) is correct. The CAD net-channel currency-blindness is known SC-3384, not a new regression. A clean CAD reprice requires fixing the Bill-To-Place data first.

---

### Domain: Renewal pricing

#### RN-LIC — Renewal license COLA uplift · **PASS**
- **Expected (00781053, PIA-PIA-RRM-PIAM, Powertech IAM BoKS, COLA 7.85%):** `preCOLA = 71 − 8.52 − 6.25 = 56.23`; `COLACalculatedPrice__c = 56.23 × 1.0785 = 60.64`; commercial net = 60.64 × 0.90 (10% discretionary) = **54.58**. Header totals reconcile.
- **Actual:** Reprice `isSuccess:true`, `CompletedWithPricing`, 2 lines preserved. PIA-PIA-RRM-PIAM committed `COLACalculatedPrice__c=60.64` (re-derived on reprice → COLA prehook ran), NetUnitPrice=54.58 = 60.64×0.90. Subscription line VM-BSL-RSL-BESECB net 4442.35 = 5417.5×0.82 (18% margin). Header reconciles exactly: ΣNetTotalPrice 4496.93 = TotalPrice = GrandTotal; ΣTotalLineAmount 5472.08 = Subtotal = ALE; Discount 17.82%.
- **Verdict:** This is **NOT** SC-3404. The dossier's "67.38" assumes Prior_Disc=0, but this line carries Prior_Disc=6.25, so 60.64 is the correct COLA net for the actual data and 54.58 the correct commercial net. The COLA uplift portion (the scenario subject) is mathematically correct and provably executed. `Total_Renewal__c=null` is residual SC-3345-family stale aggregate, not a COLA defect.

#### RN-MAINT — Renewal maintenance COLA net · **FAIL (known · SC-3404)** · high
- **Expected:** For Prior_Disc=0 (Base 71, Prior_Partner 8.52, COLA 7.85): committed `NetUnitPrice = (71 − 8.52 − 0) × 1.0785 = 67.38`. Live `PartnerNetPricePosthook` v1.4 `computeRenewalMaintenanceColaNet` returns 67.38 and `buildRenewalMaintenanceColaUpdate` writes colaNet directly to NetUnitPrice (no further 10% haircut in current code).
- **Actual:** All four SC-3404 lines commit `NetUnitPrice ≠ 67.38`, even after a fresh Force reprice:
  - 00781109 (canary): NetUnitPrice **60.64**, COLACalc 67.38 (correct value stamped to audit field but never reaches net); after reprice still 60.64.
  - 00781043: NetUnitPrice **0**, COLACalc 67.38.
  - 00781053: NetUnitPrice **54.58** (=60.64×0.90, double-haircut of a stale state), COLACalc 60.64.
  - 00781084: NetUnitPrice **60.64** while UnitPrice=67.38 and COLACalc=67.38 (net kept stale).
- **Root cause:** The derived (ItemIsDerived=true) + qty-0 + ListPrice=0 + 'No Change' maintenance line is structurally excluded from the engine price map → never appears in the posthook's lineItems graph → `buildRenewalMaintenanceColaUpdate` never persists colaNet to NetUnitPrice. The committed values are stale residue (60.64 = (71−8.52−6.25)×1.0785).
- **Verdict:** Documented KNOWN-FAIL SC-3404, not a new regression. Refinement vs dossier: live v1.4 writes colaNet directly (no 10% renewal-maint haircut), so **67.38 is the single correct expected net**; the family now shows three distinct stale residues (0, 54.58, 60.64). No SC-3404 ticket folder exists in repo — **confirm ticket id with the team**.

#### RN-SUB — Renewal subscription pricing · **PASS**
- **Expected:** Subscription renewals price through the standard path (NOT COLA — `COLAUpliftPrehook` line 419 filters `Fortra_Product_Type__c='Renewal Maintenance'`). Direct lines net to catalog; partner lines apply `Subscription_Percent__c`.
- **Actual:** Three Draft renewal quotes all repriced `isSuccess:true` / `CompletedWithPricing`, every subscription line matched:
  - 00781053 (PARTNER, AB Test Partner Account, Discount model, Sub%=18): VM-BSL-RSL-BESECB 5417.5×0.82 = **4442.35** = NetUnitPrice = PartnerUnitPrice. Reprice correctly applied a pre-reprice under-applied discount (intended).
  - 00780886 (DIRECT): 929.25 + 4697.95 → header Subtotal=TotalPrice=GrandTotal=ALE=Total_Subscription=5627.20.
  - 00780882 (DIRECT): 2674.85×2 + 2674.85 + two qty-0 zero lines → Total_Subscription=Subtotal=TotalPrice=GrandTotal=ALE=8024.55.
- **Verdict:** Correct and stable. The co-resident SC-3404 maintenance defect on 00781053 is a separate scenario, excluded here.

#### AMEND — Amendment quote pricing · **PASS**
- **Expected:** Amendment Draft reprices cleanly via Skip harness carrying forward negotiated unit prices; per-line NetTotalPrice = NetUnitPrice × Qty, UnitPrice == NetUnitPrice (non-partner); header totals reconcile per D4; reprice non-destructive.
- **Actual (00307854, 20 lines USD, Quote_Type=Amendment):** Reprice `isSuccess:true`, idempotent, line count 20→20. All 20 lines satisfy NetTotalPrice = NetUnitPrice × Qty and UnitPrice == NetUnitPrice. GS-GSE-RNM-* maintenance lines priced cleanly (qty=1, positive UnitPrice) **without** hitting SC-3372 or SC-3404. Header: Subtotal=TotalPrice=GrandTotal=ALE=21273.72, Discount=0, TDA=0, `CompletedWithPricing`. All D4 relationships exact.
- **Verdict:** PASS. The SC-3372/SC-3404 defects are tied to the degenerate qty-0/ListPrice-0 'no-change' line shape (e.g. 00780905), not to amendment pricing. 00780905 itself could not be exercised (Bill-To-Place VR data issue). Guardrail VR `Enforce_Amendment_Sales_Restriction` confirmed active.

---

### Domain: Pricing modifiers

#### MOD-PART12 — Partner discount 12% (renewal-maint) · **FAIL (known · SC-3404)** · high
- **Expected:** On PIA-PIA-RRM-PIAM with PartnerDiscountPercent=12, COLA net 67.38; a correct 12% applied → 67.38×0.88 = 59.29 (or at minimum 67.38).
- **Actual:** The 12% is **never multiplied into net**. `buildRenewalMaintenanceColaUpdate` sets NetUnitPrice = colaNet (COLA-only, line 859) and stamps PartnerDiscountPercent only as passive metadata (lines 868-872). Worse, committed net is a stale prior value: 00781109/00781084 commit **60.64** while COLACalc=67.38; 00781043 commits **0**; 00781053 commits **54.58**. No line commits 59.29 (or even 67.38). Additionally the partner accounts carry Discount-type models with **all margin percent columns null**, so the 12% is a stamped prior value, not a live model-derived margin.
- **Verdict:** The only 12% lines in the corpus are renewal-maintenance lines entangled with SC-3404; the partner-12% mechanism cannot be isolated and is subsumed by the SC-3404 structural-exclusion defect. Known-issue fail attributed to SC-3404 (partner-discount-not-applied is a facet of the same defect). Owning posthook was modified today by the user — re-verify after in-flight rework lands.

#### MOD-PART15 — Partner discount 15% · **PASS**
- **Expected:** `NetUnitPrice = ListPrice × 0.85`. Canonical PIA-PIA-NRPS-PIAP (List 355) → 301.75; Perpetual partner net must apply (no SC-3359 leak).
- **Actual (00780964 / `0Q0WC000003735t0AA`):** Reprice `isSuccess:true`; L1 PIA-PIA-NRPS-PIAP: ListPrice 355, NetUnitPrice **301.75** = 355×0.85, PartnerUnitPrice 301.75, Pre_Partner_Price__c 355, model Discount, source System Calculated. Header Subtotal=TotalPrice=GrandTotal=ALE=301.75. NetUnit 301.75 ≠ List 355 → partner net applied (no SC-3359 leak). USD → no SC-3384 confound. Secondary 00435554 (CYB-DCS-UC-CMP, Guaranteed Margin): PartnerUnitPrice 212.5 raw vs commercial NetUnitPrice 180.63 = lower-of, internally consistent.
- **Verdict:** PASS. Mechanism finding: the 15% is driven by the std QLI `PartnerDiscountPercent` field (stamps model='Discount'), independent of any `Partner_Pricing_Model__c` record (the test account has none).

#### MOD-QDISC — Quote-level header discount · **PARTIAL** · medium · **new functional gap**
- **Expected:** A header % or amount distributes to lines (equal/proportionate), reducing line net and quote TotalPrice; `Total_Discount_Amount__c` reflects it.
- **Actual:** The header discount is **captured but never applied** by V14. After reprice, every line stays at full list, TotalAdjustmentAmount=0, header Discount=0, TDA=0.
  - 00307092 (Header_Discount_Type=Percentage, Value=20, Manual_Discount=20): Subtotal=TotalPrice=GrandTotal=1587 unchanged; expected if 20% proportionate: TotalPrice 1269.60, TDA 317.40.
  - 00307058 (Amount, 200): line stays 275000; expected 274800.
  - Fortra custom fields (`Header_Discount_Type__c`/`Header_Discount_Value__c`/`Manual_Discount__c`) are display-only (referenced only in DocGen extract + demo factory), not consumed by pricing.
  - Native RLM distribution fields (`AdjustmentDistributionLogic` = {Proportionate, Equal}, `AppliedDiscount`, `AppliedDiscountAmount`) populated on **0** quotes org-wide and rejected as non-writable by the place API (`INVALID_FIELD`) → feature effectively not enabled.
  - **Control:** line-level discount works (QLI List 150, Disc 32% → net 102, AdjAmt −48).
- **Verdict:** Genuine functional gap (not a catalogued defect): the header-discount capability exists in the data model and the native distribution feature exists in schema but is not wired into V14. Only per-line discounting works. Partial/medium — existing prices not corrupted, line-level workaround exists.

#### MOD-LDISC — Line partner + discretionary · **FAIL (known · SC-3359 variant)** · high
- **Expected:** Discretionary alone: `List × (1−Disc%)`. Combined partner+discretionary: commercial = lower of [partnerUnit] vs [procNet], each margin **exactly once**, NetTotalPrice = NetUnitPrice × Qty.
- **Actual:**
  - **Discretionary-only CORRECT** (00781070): Secure Collaboration List 25000 × 0.80 = 20000 (×2); header reconciles (Discount 24.53%).
  - **Combined NON-DETERMINISTIC / DEFECTIVE:** two identical-product quotes on the SAME partner account diverge after Skip reprice:
    - 00437490 priced **correctly** (kept stored pdisc 25/20: Unlimited Class net 76.50 = 150×0.75×0.68; Accelerated qty20 net 0.80 / NetTotal 16).
    - 00307067 priced **wrong**: re-derived pdisc to model values (25→18, 20→8) and **double-applied** the partner margin (Unlimited Class net = 150×0.82×0.82×0.68 = 68.5848 vs expected 83.64; Accelerated net = 0.92² = 0.8464→0.85) **and collapsed quantity** (qty20 NetTotal = 0.85 vs 18.40).
  - Both outcomes stable/idempotent across repeated reprices → a real data-state-dependent defect, not a race.
- **Root cause (live `PartnerNetPricePosthook`, modified 2026-06-13 17:57Z):** `calculateDeferredPartnerPrice()` (lines 377/403/420) applies the partner-margin calc to `currentPrice = NetUnitPrice` (which already includes the partner margin) instead of ListPrice; this branch runs only when the PartnerUnitPrice tag is null/0 at posthook time (`needsDeferredPartnerPricing`), explaining the divergence. The deferred branch's `resolveLineTotalFromQuantity → resolveColaLineTotal` drops the qty multiplier.
- **Verdict:** SC-3359 partner-net family, but the over-application + qty-collapse symptoms are a distinct variant — **confirm exact ticket**. Severity high (under-charges; mis-totals qty>1). Owning posthook is active in-flight work (modified today) — re-verify after the rework lands.

#### MOD-CUR-AUD — Multi-currency AUD (rate 1.52) · **FAIL (known · SC-3384)** · high
- **Expected (00781098, AUD):** ES-CEP-RSL-ACTIDB NetUnitPrice should equal the AUD list 142880 (= 94000 USD × 1.52, correctly stored on the AUD PBE).
- **Actual:** ListPrice correctly sourced the AUD PBE (142880) but the net channel committed the bare USD value: UnitPrice=NetUnitPrice=NetTotalPrice=TotalLineAmount=**94000** (no ×1.52). Header Subtotal=TotalPrice=GrandTotal=ALE=94000 — **understated by 48,880 AUD (34.2%)**. Reprice `isSuccess:true`, single line/Id preserved, identical USD-magnitude net.
- **Evidence:** AUD ConversionRate=1.52 (real); USD baseline ACTIDB QLIs net=list=94000 (so AUD net=94000 is the un-scaled USD value, not a converted AUD value). Internal inconsistency: list channel resolved the AUD PBE correctly while the net channel collapsed to USD.
- **Verdict:** Known SC-3384, not a regression. Severity high (~34% understated customer-facing price), not critical (order creation not blocked).

#### MOD-CUR-EUR — Multi-currency EUR (rate 0.92) configured · **FAIL (known · SC-3384)** · high
- **Expected (00780956, EUR):** priced channels reflect EUR-converted values; BESEPB net ≤ EUR list 758.08; VMA net ≤ EUR list 460; AAMP net a EUR-converted ABA adjustment; CLSAAS net resolves a EUR tier (not 0).
- **Actual:** Catalog LIST is correctly EUR-converted (AAMP 2898=3150×0.92, CLSAAS 2005.6, BESEPB 758.08, VMA 460), but **every priced channel carries the raw USD value:**
  - BESEPB NetUnitPrice **824** (USD; *exceeds* EUR list 758.08 — structurally impossible).
  - VMA NetUnitPrice **500** (USD; exceeds EUR list 460).
  - AAMP NetUnitPrice **1575** = exact USD ABA Override row (all 3 AAMP ABA rows USD; all 13,073 org-wide ABA rows USD).
  - CLSAAS NetUnitPrice **0** / TLA 1357.2 = exact USD tier 'Managed Service 50-99' (all 1,117 tier-storage rows USD-only → no EUR match → $0).
  - Header Subtotal=5831.2 (USD-blind TLA channel, not EUR list sum 6121.68); phantom Discount 50.28%.
- **Verdict:** Known SC-3384. The net-over-list on BESEPB/VMA is a clear marker; CLSAAS net=0 is the related "$0 downstream" tiered symptom. EUR=0.92 is a real rate, so this cleanly isolates configured-pricing currency-blindness (`AttributeBasedAdjustment` 13073/13073 USD; `Attribute_Tier_Pricing_Storage` 1117/1117 USD — both have an unused CurrencyIsoCode field).

#### MOD-CUR-USDONLY — Non-USD configured + JPY rate corruption · **FAIL (known · SC-3384)** · high
- **Expected:** AAMP UnitPrice should = EUR catalog 2898 (not USD 3150) and net should be EUR-appropriate (not USD-derived 1575); all 12 active currencies should carry real rates (JPY ~149.25).
- **Actual:** AAMP on EUR 00780956 committed UnitPrice=**3150** (USD list, not EUR 2898) and NetUnitPrice=**1575** (USD ABA). Reprice re-committed identical USD-derived values (live engine behavior, not stale data). All 1117 tier-storage rows USD-only; CLSAAS nets 0. Separately, **8/12 active currencies stuck at ConversionRate=1.0** (ARS, CHF, GBP, ILS, JPY, NZD, SEK + USD), so JPY=1.0 vs authoritative ~149.25 = ~149× understatement.
- **Verdict:** Two interlocking SC-3384 defects: (1) configured/ABA/tier products currency-blind; (2) currency-rate corruption. Severity high (path-specific — straight currency-specific catalog PBE lines like BESEPB list price correctly). JPY configured-product proof limited (org's only JPY quotes carry legacy null-Product2/list-0 lines); JPY symptom established at the rate-corruption level.

#### MOD-REGION — Regional services pricing (Italy 0.64) · **FAIL — REGRESSION (un-ticketed)** · high
- **Expected:** `regionalPrice = CEILING(listPrice × multiplier / 5) × 5` on the LIST channel, landing on the persisted QLI (UnitPrice / `Regional_NetUnit_Price__c` / `PrehookRSNetUnitPrice__c`). Italy 0.64; e.g. 565 → 365; 15000 → 9600. Short-circuit for default-1.0 countries.
- **Actual:** The prehook fires and computes correctly and writes to context (`updateContextAttributes isSuccess=true`), **but V14 does NOT reconcile that output back onto the persisted QLI.** On a fresh AU reprice of 00781106 (mult 0.65) the prehook logged 15000×0.650=9750 and 3675×0.650=2390, yet persisted lines stayed at catalog: UnitPrice=15000/3675, NetUnitPrice=15000/3675, `Regional_NetUnit_Price__c`=null, `PrehookRSNetUnitPrice__c`=null. **Regional services pricing is computed but never committed.**
- **Evidence:** Debug `07LWC00000OxnBl2AJ` (AU): "Regional price: 15000.0 × 0.650 = 9750 … Result: 2 items updated … Update result {isSuccess=true}". Control `07LWC00000OxnDN2AZ` (US): mult 1.000, lines unchanged (country gating correct). Italy 0.64 formula confirmed valid via CMDT (IT, 0.64) + a **persisted artifact** `0QLWC000002U4g94AC` (list 565 → UnitPrice=NetUnitPrice=`Regional_NetUnit_Price__c`=365 = CEILING(565×0.64/5)×5) — proving regional **did** land historically.
- **Scope note:** Italy could not be exercised end-to-end (no Draft Italy quote; Quote DML RLM-blocked; only Italy quote 00780507 is Accepted). The identical code path was proven live via Australia (real 0.65) and the Italy 0.64 verified via CMDT + artifact + formula. The defect is multiplier-independent.
- **Verdict:** **Regression in the commit/reconcile leg** — the prehook computation is correct, but the V14 step that maps `PrehookRSNetUnitPrice__c` onto the line (e.g. `RegionalServicesPrice27` / `RegionalNetReconcileGate`) appears dropped/renamed. The historical persisted artifact proves it once worked. **No ticket exists — recommend filing.**

---

### Domain: Totals & rollups

#### TOT-CONSIST — Multi-line totals consistency · **PARTIAL** · medium · **known SC-3345 (TDA residue)**
- **Expected:** ΣNetTotalPrice = TotalPrice = GrandTotal; ΣTotalLineAmount = Subtotal = ALE; NetUnit×Qty = NetTotal; Discount = (1−TotalPrice/Subtotal)×100; `Total_Discount_Amount__c` = Subtotal − TotalPrice; category totals by `Fortra_Product_Type__c`.
- **Actual:** **All core money relationships hold exactly** on both repriced quotes (16-line 00340940 and 3-line discounted 00781070), per-line NetUnit×Qty = NetTotal, and Discount%/category rollups reconcile. The **one failing relationship is `Total_Discount_Amount__c`:** on 00781070 it committed **0** when it should be 13000 (Subtotal 53000 − TotalPrice 40000; |Σline adjustments| = 13000). Systemic: of 14 most-recent discounted Draft quotes, **11 have TDA that does not reconcile** (most read 0 despite real discounts — 00781050 discount 148439 → TDA 0; 00781059 28340 → 0; 00780777 15956.5 → 0).
- **Verdict:** Core scenario PASSES; the residual is the SC-3345 totals family (`Total_Discount_Amount__c` is one of the engine-written aggregates not written on zero-discount-aware/empty paths). Partial/medium — order-affecting values (NetUnitPrice, NetTotalPrice, Subtotal, GrandTotal, Discount%) are right; only the reporting field is wrong. **If SC-3345 is considered fully closed, this is a borderline regression on `Total_Discount_Amount__c` specifically — confirm attribution.**

#### TOT-ALE — ALE + Services aggregate + stale (SC-3345) · **PASS**
- **Expected:** `ALE__c = Subtotal` (formula, BlankAsZero); `Total_Services__c` = Σ Services-line net; SC-3345 fix re-zeroes/re-sums aggregates so a stale value corrects on reprice.
- **Actual:**
  - Quote A (00781106, Perpetual 3675 net + Services 15000 net): after reprice Subtotal=TotalPrice=GrandTotal=ALE=18675, Total_Services__c=15000, Total_Software__c=null, Discount=0. All match.
  - Quote B (00437471): **before** reprice = SC-3345 stale signature (Subtotal=0 but Total_Services__c=38800). **After** reprice: Subtotal=38800, TotalPrice=0, GrandTotal=0, ALE=38800 (=Subtotal), Discount=100, **Total_Services__c 38800→0** (stale corrected → SC-3345 fix working).
- **Verdict:** PASS. Two non-blocking follow-up observations (not SC-3345 regressions): (a) category totals exclude `Fortra_Product_Type__c='Perpetual'` (so they won't reconcile to GrandTotal when Perpetual lines exist) — matches the documented pre-existing follow-up; (b) `Total_Discount_Amount__c=0` instead of 38800 on the degenerate all-zero-net Services quote — the same $0-net TDA edge as TOT-CONSIST.

---

### Domain: Quote-to-Order

#### QO-CONVERT — Convert + field mapping · **PASS**
- **Expected:** After conversion the Order is created in Draft (not activated); header Bill/Ship Account+Address+Contact carried from the source Quote; per-line `Ship_To_Address__c` and `Source_List_Price__c` stamped; dates/currency carry; quote→order parity; a subsequent Force/Skip reprice leaves Status unchanged.
- **Actual (validated against existing converted Draft orders — a fresh headless convert is blocked within guardrails):**
  - Header mapping CORRECT (00095394 vs source 00780934): `Bill_To_Account__c=001WC00000XiZP4YAN` (= Place `a0lWC000004cO79YAE`.Account__c), `Bill_To_Address__c`/`Ship_To_Address__c=a0lWC000004cO79YAE` (= Quote Bill/Ship Place), `BillToContactId`/`ShipToContactId=003WC00000WRrlmYAD`.
  - `Source_List_Price` decomposition CORRECT: derived maint FIM-FIM-RNM-VEMENM (List 0) carries `Source_List_Price__c=34750` = parent LIC list.
  - Per-line `Ship_To_Address__c` stamped from Quote.Ship_To_Place__c. Dates populated (Billing From 2026-06-08 / To 2027-06-07; EffectiveDate 2026-06-08). AUD currency carried (00095487).
  - Pricing parity CORRECT on the clean order 00095477: TotalAmount 94000 = Quote TotalPrice 94000.
  - **Non-activating reprice CONFIRMED:** Order-typed Place Sales Transaction (Force/Skip) on 00095477 `isSuccess:true`; Status stayed **Draft** (`CompletedWithPricing`), 1 line preserved — no activation, no Order Complete, no platform event.
- **Verdict:** PASS. **Correction to discovery/memory:** `Order.Bill_To_Account__c` is **place-derived** (`Place.Account__c`), not `Quote.AccountId` — they coincide on these all-US/same-account orders but the code path differs and matters for partner billing.

#### QO-PRICEPARITY — Order pricing parity vs quote · **FAIL (known · SC-3359 variant)** · high
- **Expected:** Every OrderItem net = source QLI net; Order.TotalAmount = source Quote.GrandTotal. For the partner-discounted (15%) Perpetual line on 00780934, the partner net was already applied once on the quote (QLI net = PartnerUnitPrice = 34750×0.85 = 29537.5), so the order line should also be 29537.5 and Order.TotalAmount = 37530.
- **Actual:** **PARTIAL PARITY.**
  - Clean baseline 00095477 (single Subscription line): Quote net 94000 = Order net 94000 = TotalAmount 94000 (PARITY).
  - **00095394 BREAKS parity on the Perpetual line:** Quote 'VnE Manager Ev' NetUnitPrice=**29537.5** (15% applied once, AdjAmt=0) vs **Order OI NetUnitPrice=25106.875** (= 29537.5×0.85), with Order TotalAdjustmentAmount=−4430.625 (= 29537.5×15%). **The 15% partner discount was applied a SECOND time during the post-conversion order reprice.** The derived maintenance line carried in perfect parity (7992.5; Source_List_Price 34750).
  - Net: Order.TotalAmount **33099.375** vs Quote.GrandTotal **37530**, a −4430.625 gap. `CompletedWithPricing` (a committed result, not an error).
- **Verdict:** SC-3359 partner-net family on the One-Time/Perpetual order path — here a **double-application** during Quote-to-Order reprice (opposite polarity to the documented "net left at list"). Distinct from SC-3384 (this is USD), SC-3404 (Perpetual new-business, not renewal-maint), and integration (this is order *pricing*). Severity high (under-charged real order; breaks parity). **Confirm SC-3359 is the right ticket for this polarity or file a sibling.**

#### QO-DECOMP — Order line decomposition · **PASS**
- **Expected:** Maintenance split → derived line `Source_List_Price__c` = parent ListPrice, `Base_Price__c` = parent UnitPrice, consistent maint rate, two-line totals reconcile. Quantity split → N qty=1 lines linked by `Original_Order_Item__c` to the SAME Product2, NO `Source_List_Price` carry. (Workday line-type out of scope.)
- **Actual:**
  - Maintenance split (00095394, `CompletedWithPricing`): license List 34750 / Unit 29537.5 / Net 25106.875; derived line Source_List_Price__c=**34750** (= parent List), Base_Price__c=**29537.5** (= parent Unit, on source quote), Net 7992.5 = Base × 0.27059. TotalAmount 33099.375 = 25106.875 + 7992.5 (reconciles).
  - Quantity split (00095316, `CompletedWithPricing`): 1 parent + 4 qty=1 children DM-WCU-NRPS-5250PE all linked `Original_Order_Item__c=802WC00000OHEWzYAP`, same product/price 3675, `Source_List_Price__c=null` on all (correctly distinct). 5×3675 = 18375 = TotalAmount.
  - Degenerate $0 (00095369): `Source_List_Price__c=355` carried onto PIA-PIA-RNM-PIAMBK from parent License List 355 even at qty 0 (only derived NetUnitPrice null — the qty-0 SC-3404 family, out of scope).
  - Live `MaintenanceOrderDecompositionService` (mod 2026-06-12) confirms it patches `Source_List_Price__c` + `Base_Price__c` targeting "the discount-immune maintenance base."
- **Verdict:** PASS. Two adjacent symptoms excluded per scope: derived maint NetUnitPrice=null on qty-0 (SC-3404); Workday line-type stamping (SC-3347/SC-3210).

---

### Domain: Validation

#### VAL-REQ — Required-fields completeness (SC-3338) · **PASS**
- **Expected:** `OrderSubmissionValidator` returns hasErrors=false for a fully-populated order; for an order missing only rep-owned Account fields, returns exactly those bullets; for a heavily-unpopulated order, one error per genuinely-missing field (null related record → all its rules fire).
- **Actual (all three Draft orders matched config exactly):**
  - 00095493 (fully populated): hasErrors=false, errorCount=0.
  - 00095497 (AB Test Account): hasErrors=true, errorCount=2 → exactly **Account Phone** + **Account D&B DUNS**; field-state confirmed those are the ONLY two missing.
  - 00095494 (BoKS, heavily unpopulated): hasErrors=true, errorCount=**16** → 3 Account + 3 Order + 5 BillToContact + 5 ShipToContact (both FKs null → 5 each) + 0 OrderItem; independent decomposition (3/3/10/0) matched. No OrderItem rule fired on any order (line fields auto-populated: LineNumber, Billing_Frequency__c=Yearly_Billing_Template, TotalLineTaxAmount=0, Workday_Contract_Line_Type__c).
  - Read-only confirmed: all three remained Status=Draft / Workday_Sync_Status=Pending afterward.
- **Verdict:** PASS — the existing 25-rule validator works precisely as designed. SC-3338 is an enhancement (surface rep-owned fields earlier), not a defect. Architectural caveats: enforcement lives only in the Order "Update Status → Order Complete" flow v13 (no VR/record-trigger backstop → headless convert + Data Loader bypass it); whole framework is UAT-only (do NOT deploy to prod, 2026-06-01 directive).

#### VAL-SUBMIT — Order-submit validation (SC-3291) · **PASS**
- **Expected:** Populated order 00095481 passes (0 errors); unpopulated 00095497 fails with exactly 2 (Phone + DUNS). "Populated" semantics: Boolean false and numeric 0 count as populated.
- **Actual:** EXACT MATCH.
  - 00095481 (Order Complete): hasErrors=false, errorCount=0.
  - 00095497 (Draft): hasErrors=true, errorCount=2 → "Account Phone is required" + "Account D&B DUNS is required", both with correct Link-to-Record href to Account `001WC00000QBhaXYAT`.
  - Zero false pos/neg: failing-order Contact `Workday_MobilePhone_Primary__c=False` (Boolean false — NOT flagged) and OrderItem `TotalLineTaxAmount=0` (zero — NOT flagged) confirm the semantics.
  - Post-run re-read: 00095481 still 'Order Complete' (sync Success), 00095497 still 'Draft' (sync Pending) — no state change.
- **Verdict:** PASS. Read-only mirror of what flow v13 checks before it would set Status='Order Complete'. Same UAT-only + bypassable caveats as VAL-REQ.

---

### Domain: Configuration

#### CFG-AUTOMAINT — Auto-add first-year maintenance · **PASS** · low · *secondary SC-3372*
- **Expected:** Adding a Perpetual license with a "Year 1 Maintenance Sku added to … Perpetual" `ProductConfigurationRule` (actionType=AutoAdd) auto-adds the matching first-year New-Maintenance SKU 1:1, and that line prices from its contributing perpetual.
- **Actual — auto-add assertion PASSES:**
  - 99 active rules, all actionType=AutoAdd; 98/99 gated on `QuoteTypeText__c='New'`; all 95 unique targets resolve to active Product2.
  - Converted-order proof (00095394): VnE Manager Ev Perpetual (List 34750) + auto-added VnE Manager Ev-NewMaintenance (Net 7992.5, Source_List_Price__c=34750).
  - Live repro: Draft New quote 00674002 contains GS-GSE-NRPS-E8CP + its auto-added GS-GSE-RNM-EFT8 (rule Active); reprice `isSuccess:true`, line count preserved at 39.
- **Secondary (SC-3372, NOT a failure of auto-add):** only 77 of 181 derived PBEs for auto-add targets have a config row (~57% gap); GS-GSE-RNM-EFT8 *has* config yet derives $0 because contributor GS-GSE-NRPS-E8CP carries ListPrice=0/UnitPrice=0 (SC-3372 secondary $0-list defect). Where config + a priced contributor exist (VnE/FIM family), it prices correctly.
- **Verdict:** PASS (severity low — only the derived-maintenance line *pricing* fails, which is the pre-existing SC-3372 gap, not a regression in auto-add). Minor data-quality notes: one rule's second criterion mis-set to a product name instead of 'New'; one target (FIM-FIM-NRPS-TEAI) adds a Perpetual academic site license (likely intentional).

---

### Domain: DocGen

#### DOC-PDF — Quote PDF pricing + descriptions (SC-3335/3349) · **PASS**
- **Expected:** Active pipeline renders a Quote PDF whose line Descriptions come verbatim from `QuoteLineItem.Description` (QLDescriptionGeneratorPrehook) with an ISBLANK→Product2.Name fallback; pricing columns map line Amount←net TotalPrice, Subtotal←list, GrandTotal←net.
- **Actual (00780458 / `0Q0WC000002iszf0AA`, 3 lines):**
  - Pipeline active: DocumentTemplate `Fortra Quote Consolidated EN` v3 Active (Extract=DMExtractFortraQuote, Mapper=DMTransformFortraQuote, ClientSide); IP + OmniScript Active; QLDescriptionGeneratorPrehook + Test Active.
  - Pricing consistency: L1 list18500/net17020, L2 6200/5704, L3 24000/22080; NetTotal=NetUnit×Qty on all; ΣTLA=48700=Subtotal; ΣNetTotal=44804=TotalPrice=GrandTotal; uniform 8% discount.
  - Descriptions render verbatim ("Core Security ISPF annual maintenance – primary production LPAR (CBCPROD01 / P01).") with correct glyphs.
  - Transform fallback present (`IF(ISBLANK(description), productName, description)`); extract wiring confirmed `amountRaw←TotalPrice (net)`, `subtotalRaw←Quote.Subtotal (list)`, `grandTotalRaw←Quote.GrandTotal (net)`.
  - JPY target 00340931: 4 lines, ΣNetTotal=4845735=GrandTotal; large-yen integers render; descriptions populated.
- **Verdict:** PASS. One non-blocking artifact: the downloaded PDF (generated 2026-04-30, when net==list) shows Amount as the list subtotal 48700 with a separate (8.00%) Discount column — a **stale-doc artifact**, not a live mapping defect (the live Extract maps Amount←net). Reprice of this quote is independently blocked by the Bill-To-Place VR (data, out of DocGen scope); the quote is already fully priced so reprice isn't needed for doc content.

---

## Critical findings (severity critical/high)

No **critical** (order-blocking) defects were found within scope. The following **high-severity** issues break or distort core pricing paths:

| # | Finding | Scenario(s) | Classification | Impact |
|---|---|---|---|---|
| 1 | **Tiered/attribute-volume lines commit $0 net** — tier resolves correctly but V14 never maps `Base_Price__c`/`Attribute_Price_Mode__c` into the net channel; every tiered line on the org nets $0 and carries $0 into orders. | NB-TIER | Known family SC-3384 ($0-net); **needs dedicated ticket** | Every tiered SKU prices $0 |
| 2 | **Regional services price computed but NOT committed** — prehook computes the CEILING formula and writes context successfully, but V14 dropped/renamed the reconcile step; persisted line stays at catalog. Proven once-worked (persisted artifact). | MOD-REGION | **REGRESSION — un-ticketed; file ticket** | Regional discount never applied |
| 3 | **Multi-currency net is currency-blind** — non-USD configured/ABA/tier products and even straight non-USD net channels commit raw USD magnitudes (AUD ~34% understated; EUR net>list structurally impossible; CLSAAS nets 0). Plus 8/12 currency rates stuck at 1.0. | MOD-CUR-AUD, -EUR, -USDONLY, NB-BUNDLE(CAD) | Known SC-3384 | Wrong customer prices on every non-USD configured path |
| 4 | **Renewal-maintenance COLA net never reaches NetUnitPrice** — derived/qty-0/List-0 'No Change' line is excluded from the engine price map; commits stale 0/54.58/60.64 vs correct 67.38; the 12% partner discount also never multiplies into net. | RN-MAINT, MOD-PART12 | Known SC-3404 | Renewal-maint lines mis-price |
| 5 | **Partner-net double-application + qty collapse** — on the partner+discretionary combined path the partner margin can be applied twice and quantity dropped from NetTotalPrice, depending on whether PartnerUnitPrice was pre-stamped (deferred branch computes off NetUnitPrice not ListPrice). | MOD-LDISC | Known family SC-3359 (distinct variant — **confirm ticket**) | Under-charges; mis-totals qty>1 |
| 6 | **Quote-to-Order partner double-discount** — the post-conversion order reprice re-applies the 15% partner discount the quote already absorbed; breaks quote→order parity (33099.375 vs 37530). | QO-PRICEPARITY | Known family SC-3359 (opposite polarity — **confirm ticket**) | Orders under-charged vs accepted quote |
| 7 | **Derived-maintenance lines unpriced** — ~95% of IsDerived PBEs lack a `PriceBookEntryDerivedPrice` config row (176/3,453); auto-added maintenance commits null net while `CompletedWithPricing` falsely reports success. | NB-MAINT, CFG-AUTOMAINT(secondary) | Known SC-3372 | Maintenance lines price null/$0 |

**New (un-ticketed) defects requiring tickets:** #2 (MOD-REGION regression), #1 (NB-TIER $0-net — distinct from SC-3390), NB-HW Defect A (inactive `P5` picklist + `P5`/`P05` key mismatch, 57 QLIAs, hard `INVALID_API_INPUT`) and Defect B (HW audit fields never persisted), and the MOD-QDISC header-discount functional gap.

---

## Known issues confirmed still open (with tickets)

| Ticket | Symptom | Status this run | Evidence |
|---|---|---|---|
| **SC-3384** | Non-USD configured/attribute/ABA/tier products price in USD; 8/12 currency rates stuck at 1.0 | **Open / confirmed** | AUD net 94000 vs list 142880; EUR AAMP net 1575 (USD), BESEPB net 824>list 758.08; CLSAAS net 0; ABA 13073/13073 USD; tier-storage 1117/1117 USD |
| **SC-3404** | Renewal-maintenance COLA net commits 0/54.58/60.64 instead of 67.38; 12% partner never applied | **Open / confirmed** | All 4 quotes reproduce after fresh reprice; structural price-map exclusion (UnitPrice=0 on 00781109) |
| **SC-3372** | Derived PBEs lack `PriceBookEntryDerivedPrice` config → null/$0 maintenance net; contributing-products gap | **Open / confirmed** | 176 config vs 3,453 IsDerived PBEs (5.1%); GS-GSE-RNM-EFT8 derives $0 (contributor list=0) |
| **SC-3359** | Partner net mishandled on One-Time/Perpetual + combined partner/discretionary (double-apply variant) | **Open / confirmed (variant)** | MOD-LDISC 00307067 double-apply + qty collapse; QO-PRICEPARITY order double-discount −4430.625 |
| **SC-3345** | Phantom discount / wrong ALE / Services totals | **FIXED on core; residue on `Total_Discount_Amount__c`** | TOT-ALE stale Services 38800→0 corrected; TOT-CONSIST TDA reads 0 on 11/14 discounted quotes |
| **SC-3390** | Tiered "Update Price" double-click | **FIXED (durable)** | First-click tier match on pass 1, repriced twice; IsPriceImpacting=true on configurator PADs |
| **SC-3393** | Services add to quote fails | **FIXED** (not re-triggered) | NB-SVC added/priced without RegionalNetReconcileGate error |

> **Caveat on SC-3404 ticket id:** no SC-3404 folder exists in repo; the symptom is documented in the sc3403 dossier (files 11/12/13). Confirm the ticket id with the user/team. Same applies to the SC-3359 *variants* in MOD-LDISC and QO-PRICEPARITY.

---

## Coverage & gaps — what could NOT be tested and why

| Gap | Reason | Affected scenarios |
|---|---|---|
| **No headless Quote-to-Order convert of a NEW Draft quote** | The screen flow `Fortra_Quote_to_Order_Conversion` gates on `Quote.Status='Accepted'` (do-not-touch), and the AutoLaunched flag path needs a `Quote.Create_Order_from_Quote__c` write that RLM blocks. Conversion mechanics were validated against EXISTING converted Draft orders + a live non-activating Order reprice. | QO-CONVERT, QO-PRICEPARITY, QO-DECOMP |
| **No direct Quote/QLI DML** | RLM/Subscription Mgmt blocks Quote/QLI DML at the platform tier (Apex + REST). All quote repricing went through the managed Place Sales Transaction API. Cannot set attributes, header-distribution fields, or Ship-To Place programmatically. | NB-HW, MOD-QDISC, MOD-REGION |
| **Regional Italy end-to-end** | No Draft quote has an Italy place; the only Italy quote org-wide (00780507) is Accepted/do-not-touch; Quote DML to set an Italy Ship-To Place is RLM-blocked. Validated the identical code path via Australia (real 0.65) + Italy 0.64 via CMDT + persisted artifact + formula. | MOD-REGION |
| **Non-1.0 Hardware multiplier flowing to net** | No Draft quote has a positive-price line with a valid/matched HW attribute; setting HW attributes requires the Configurator UI (out of scope); harness Skip + RLM DML lock prevent it. Validated formula (57/57 tests) + no-attribute fall-through path E2E. | NB-HW |
| **MXN multi-currency** | No MXN quotes exist org-wide (rate configured but unused); substituted CAD (real 1.35) and AUD/EUR. | MOD-CUR-* |
| **Hardware Family** | 0 Product2 with Family='Hardware'; substituted Perpetual + the live `HardwareAttributePricingPrehook` path. | NB-HW |
| **Live flow v13 UI run** | Running the Order "Update Status → Order Complete" flow would risk a Status transition + Workday platform event; validated the underlying `OrderSubmissionValidator` Apex (the deterministic gate the flow calls) read-only instead. | VAL-REQ, VAL-SUBMIT |
| **Rendered DocGen visual layout** | Rendered cell/column layout lives in the binary `.docx` (not in repo); validated the merge inputs (QLI.Description + pricing fields) + transform wiring + a downloaded rendered PDF via pdftotext. | DOC-PDF |
| **Workday / MuleSoft integration** | Excluded by design. E2E stops at order creation + order pricing. No activation, no `Status='Order Complete'`, no platform events. | All |
| **Several blocked reprices** | The Quote VR `Quote_BillToPlacceAcct_Equal_QuoteAcct` re-fires on every managed reprice and blocks the harness on quotes with inconsistent Bill-To-Place data (00380330, 00780927, 00437346, 00380153, 00780905, 00780458). Data-state issue, not a pricing defect. | NB-PERP, NB-SVC, NB-BUNDLE, AMEND, DOC-PDF |

---

## Recommendations / next actions

1. **File a new ticket for MOD-REGION (regression):** the V14 procedure dropped/renamed the regional-net reconcile step (`RegionalServicesPrice27` / `RegionalNetReconcileGate`) that maps `PrehookRSNetUnitPrice__c` onto the line. The prehook computes correctly; only the commit leg is broken. A persisted artifact (`0QLWC000002U4g94AC`, 565→365) proves it once worked. High severity — regional discounts are silently not applied.
2. **File a dedicated ticket for NB-TIER $0-net** (distinct from SC-3390, which is fixed): V14 does not consume `Base_Price__c`/`Attribute_Price_Mode__c` into the net channel ('Total Price'→ItemNetTotalPrice; 'Unit Price'→InputUnitPrice). Every tiered SKU currently commits $0. Likely a missing/mis-gated `DerivedPricingAttribute` or Base_Price-to-net mapping step.
3. **NB-HW Defect A (data fix):** re-key the 57 `Pgroup='P5'` QLIAs to `P05` (or add `P5` as an active picklist alias **and** map key) — `P5` lines currently hard-fail the place API and would silently get no hardware discount even if accepted.
4. **NB-HW Defect B (decision):** confirm whether HW audit-field persistence (`Hardware_Pricing_Applied__c`, multiplier, pre-price) is intended; if so, wire the context writes to QLI/OI and add the fields to OrderItem so HW-applied lines are auditable downstream.
5. **Confirm SC-3359 ticket attribution** for the two distinct variants observed: MOD-LDISC (partner-margin double-apply + qty collapse via the deferred branch) and QO-PRICEPARITY (Quote-to-Order partner double-discount). Both are under-charging on real paths. The owning `PartnerNetPricePosthook` was modified today — **re-verify after the in-flight rework lands.**
6. **SC-3404:** prioritize the structural fix so the derived/qty-0/List-0 renewal-maintenance line participates in the engine price map (so `buildRenewalMaintenanceColaUpdate` can persist colaNet). Note live v1.4 writes 67.38 directly (no 10% haircut) — align test expectations to 67.38.
7. **SC-3384:** add a `CurrencyIsoCode` key to the ABA decision table and the `Attribute_Tier_Pricing_Storage`/`AttributeBasedAdjustment` lookups (both objects already have the field, unused), populate non-USD rows or apply `ConversionRate`, and **fix the 8 corrupted currency rates** (ARS 666.67, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667 per the dossier targets).
8. **SC-3372:** backfill `PriceBookEntryDerivedPrice` config for the ~95% of IsDerived PBEs that lack it (gate the SC-3346/SC-3403 build on this); also fix the GS-GSE-NRPS-E8CP $0-list contributor.
9. **MOD-QDISC:** decide whether to wire the header-discount distribution (enable the native `AdjustmentDistributionLogic` Proportionate/Equal path, or consume the Fortra `Header_Discount_*__c` fields in V14). Today only per-line discounting works.
10. **TOT-CONSIST / SC-3345 residue:** fix `Total_Discount_Amount__c` to write `Subtotal − TotalPrice` (or zero-init then re-sum) on discounted/zero-discount paths; it reads 0 on 11/14 discounted quotes even immediately post-reprice. Confirm whether to reopen SC-3345 or file a sibling.
11. **Data hygiene:** resolve the Bill-To-Place VR data inconsistencies on the blocked quotes so future reprice runs aren't gated by `Quote_BillToPlacceAcct_Equal_QuoteAcct`.

---

## Appendix — discovery reference

### A. Pricing formulas (live-verified 2026-06-13; re-pull Apex before relying on line numbers — several classes modified today)

| Mechanism | Owner | Formula |
|---|---|---|
| **Standard partner net** | `PartnerNetPricePosthook` v1.4 + `PartnerPricingService` | procedureNet = `List × (1 − PartnerDiscount%/100) × (1 − Discount%/100)`; partnerNet = `List × (1 − margin%/100)` (margin product-type-specific: Software/NewMaint/RenewalMaint/Subscription/Services columns); **commercial = lower of** procedureNet vs partnerNet. 'Guaranteed Margin' = additive Σ margins (cap 100%); 'Discount' = billing partner's % only. All HALF_UP. |
| **Renewal COLA** | `COLAUpliftPrehook` v1.1 + `COLA_Uplift_Rules__mdt` | preCOLA = `Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c`; `COLACalculatedPrice__c = preCOLA × (1 + COLA%/100)`. Only Renew-type + `Fortra_Product_Type__c='Renewal Maintenance'` + Base>0. 22 active CMDT rows keyed by Solution_Category (e.g. Powertech IAM BoKS 7.85). Live v1.4 posthook writes colaNet directly to NetUnitPrice (no extra haircut). |
| **Tiered / attribute-volume** | `AttributeVolumePricingPrehook` v3.0 + `Attribute_Tier_Pricing_Storage__c` (1117 USD rows) | Match `Product\|SellingModel\|AttrName\|AttrValue` then `Attribute_Volume` ∈ [Lower,Upper]; modes: 'Unit Price'→InputUnitPrice=Tier_Value; 'Calculated'→ItemNetTotalPrice=Tier_Value×Multiplier; 'Total Price'→ItemNetTotalPrice=Tier_Value. Null volume → RESET to ListPrice. |
| **Regional (services)** | `RegionalServicesPricingPrehook` v13.3 + `Services_Regional_Pricing__mdt` (125 rows) | `regionalPrice = CEILING(currentPrice × multiplier / 5) × 5` on LIST channel; Italy/most-EU-east 0.64, AU/NZ 0.65, US/CA 1.0. NET (catalog) unchanged. |
| **Hardware (Powertech)** | `HardwareAttributePricingPrehook` v3.0 | `AdjustedPrice = List × pGroupMult × userTierMult × (1 − sysTypeDiscount/100)`; pGroup P05:0.5…P60:4.0; userTier 1.0…3.0; sysType Production:0/Staging:25/Test:50. No-attribute → P20/Production/1u = 1.0×. |
| **Derived maintenance** | native DerivedPricing + `PriceBookEntryDerivedPrice` (`SourceListPricePrehook` = disabled stub) | contributor net × maintenance % via config row; renewal-maint governed by the COLA path + `Source_List_Price__c` stamp. SC-3372 open. |
| **Multi-currency** | should be `USD × CurrencyType.ConversionRate` / currency-specific PBE | **Actual (SC-3384):** configured/ABA/tier are currency-blind (USD-only data, no currency key). Rates: AUD 1.52, CAD 1.35, EUR 0.92, MXN 0.056 real; ARS/CHF/GBP/ILS/JPY/NZD/SEK stuck at 1.0. |

### B. Quote totals / rollups model

- **Formula fields:** `ALE__c = Subtotal` (BlankAsZero); `Annualized_License_Equivalent_Base__c = Subtotal`; `Total_Contract_Value_TCV__c = TotalPrice`. A wrong ALE is almost always a wrong Subtotal.
- **Engine-written (not zero-init on empty → stale residue):** `GrandTotal`, `Total_Services__c`, `Total_Software__c`, `Total_Subscription__c`, `Total_Discount_Amount__c`, `Total_ARR__c`, `Total_Renewal__c`.
- **Verified relationships:** `Subtotal = ΣTotalLineAmount = Σline Subtotal` (list); `TotalPrice = ΣNetTotalPrice` (net); `GrandTotal = TotalPrice`; `Discount = (1 − TotalPrice/Subtotal)×100`; `Total_Discount_Amount__c = Subtotal − TotalPrice` (post-V9 clamp); category totals split by `Fortra_Product_Type__c` (NOT standard Family). Note: `Product2.Family` does not GROUP BY through the QLI relationship (returns null) — read per-row.

### C. Order-submission validation chain

`Order_Submit_Validation__mdt` (25 active rules) → `Fortra_Order_Submission_Check` flow v13 → `OrderSubmissionValidator.cls`. Active rules: Account (Name/Phone/Type/DB_DUNS__c rel=AccountId); Contact ×10 (FirstName/LastName + 3 Workday_MobilePhone_* for BillToContactId and ShipToContactId); Order (Bill_To_Account__c/Ship_To_Account__c/Status/EffectiveDate/Workday_Contract_ID__c/WorkdayReferenceID__c rel=Id); OrderItem (Id/LineNumber/Billing_Frequency__c/TotalLineTaxAmount/Workday_Contract_Line_Type__c rel=OrderId). "Populated" semantics: Boolean false and numeric 0 count as populated; only text/null fails. Constant SOQL (SC-3366 fix). Validation is **read-only** in `validate()`. Whole framework is **UAT-only** (absent from prod). `FieldPopulatedCheck.cls` deprecated, not called by v13.

### D. DocGen pipeline

Active `DocumentTemplate 'Fortra Quote Consolidated EN' v3` (ClientSide) binds `DMExtractFortraQuote` (Extract) + `DMTransformFortraQuote` (Transform, the ~1952-line payload builder) via `useTemplateDRExtract=Yes`; `IPFortraGenerateQuoteDoc` v4 picks the template; `Fortra Quote Generate Document` OmniScript v3 drives it. Line Descriptions come from `QLDescriptionGeneratorPrehook` (Active) with `IF(ISBLANK(description), productName, description)` fallback. Extract wiring: Amount←net TotalPrice, Subtotal←list, GrandTotal←net. Quote header total field is `GrandTotal` (no `TotalAmount` column on Quote). `*Copy*` DataRaptors are NOT bound to the active template.

### E. Representative records (corpus)

| Quote / Order | Scenario use |
|---|---|
| 00781106 / `0Q0WC0000038U7F0AU` | NB-PERP baseline, NB-HW no-attr path, MOD-REGION (AU), TOT-ALE quote A |
| 00780964 / `0Q0WC000003735t0AA` | NB-PERP partner-only, MOD-PART15 canonical |
| 00307854 / `0Q0WC0000028GmQ0AU` | NB-MAINT (GS-GSE-RNM null net), AMEND (20-line) |
| 00407375 / `0Q0WC0000028Czm0AE` | NB-MAINT (GS-GSE-RRM null net) |
| 00781102 / `0Q0WC0000038Rir0AE` | NB-SVC catalog Services |
| 00781107/08 / `0Q0WC0000038Vkr0AE`,`0Q0WC0000038W930AE` | NB-TIER ($0-net) |
| 00307075 / `0Q0WC0000026Bin0AE` (USD) · 00437346 / `0Q0WC000002Bzi90AC` (CAD) | NB-BUNDLE |
| 00781053 / `0Q0WC0000037muD0AQ` | RN-LIC, RN-SUB (partner), MOD-PART12, co-resident SC-3404 |
| 00781043/84/109 | RN-MAINT / MOD-PART12 SC-3404 family |
| 00780886/82 | RN-SUB direct renewals |
| 00781070 / `0Q0WC0000037yyb0AA` | MOD-LDISC discretionary, TOT-CONSIST discounted |
| 00437490 / `0Q0WC000002GZtV0AW` · 00307067 / `0Q0WC0000024pHJ0AY` | MOD-LDISC combined (correct vs defective) |
| 00307092/58 | MOD-QDISC header discount |
| 00781098 / `0Q0WC0000038OD70AM` (AUD) · 00780956 / `0Q0WC0000036xy90AA` (EUR) · 00340931 (JPY) | MOD-CUR-* |
| 00340940 / `0Q0WC0000028Qao0AE` | TOT-CONSIST 16-line |
| 00437471 / `0Q0WC000002Fhcz0AC` | TOT-ALE stale-aggregate |
| Order 00095394 / `801WC00000kNla1YAC` | QO-CONVERT mapping, QO-PRICEPARITY break, QO-DECOMP maint split |
| Order 00095477 / `801WC00000kcF6vYAE` | QO-CONVERT/PARITY clean baseline, non-activating Order reprice |
| Order 00095316 / 00095369 | QO-DECOMP qty-split / degenerate $0 |
| Orders 00095481/93/94/97 | VAL-REQ / VAL-SUBMIT |
| 00674002 / `0Q0WC000002QnYB0A0` | CFG-AUTOMAINT live repro |
| 00780458 / `0Q0WC000002iszf0AA` | DOC-PDF |

### F. Methods & guardrails recap

- **Quote reprice:** `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` with `pricingPref=Force`, `configurationPref.configurationMethod=Skip` (mandatory), `graph` PATCH Quote. `isSuccess:true` = ran; line count/Ids preserved = non-destructive.
- **Order reprice (activation-free):** same action with type=Order, or `OrderRepriceInvocable.reprice`. Both leave `Status` unchanged.
- **Never:** delete records/metadata; set Order.Status to 'Activated'/'Order Complete'; publish `Order_Completed_WD__e`/`_Legacy__e`/`Invoice_PO_Updated_WD__e`; direct Quote/QLI DML; touch Accepted/Ordered/In Review/Approved/Presented quotes (esp. 00781068, 00780507, 00734122).
- **Debug capture:** FINEST logs (`07LWC00000OxmIv2AJ`, `07LWC00000Oxmh72AB`, `07LWC00000OxmQz2AJ`, `07LWC00000OxnBl2AJ`, `07LWC00000OxnDN2AZ`) used to prove prehook execution vs commit. Working artifacts under `/Users/liamjeong/Documents/Code/Fortra/Data/sc-e2e-full/work/<scenario>/`.