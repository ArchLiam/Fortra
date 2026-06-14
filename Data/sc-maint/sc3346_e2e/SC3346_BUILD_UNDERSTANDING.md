# SC-3346 Maintenance (Derived) Pricing — Build Understanding & Fix Plan

> Active procedure: **Rev_Mgmt_Default_Pricing_Procedure V14** (ExpressionSet `9QLWC0000015cDl4AI`, sole-active ExpressionSetVersion `9QMWC00000023eX4AQ`). Version churns fast (V9→V14 in days, sometimes mid-republish with ZERO active versions). **Re-poll `ExpressionSetVersion WHERE ExpressionSetId='9QLWC0000015cDl4AI' AND IsActive=true` before any reprice or element-level conclusion.**

---

## 1. What the build does (the two features, in plain terms)

SC-3346 adds two maintenance-pricing behaviors on top of the single shared pricing procedure:

**Feature 1 — New-business first-year DERIVED maintenance.** When a rep adds a license, RC auto-adds a matching maintenance/support line. The rep picks a tier (Premier / Standard / Professional / …) and the line prices as `tier-rate × Source_List_Price__c` (the source license's list price, stamped onto the line so pricing does not depend on fragile native contributor resolution). At Quote-to-Order, an Apex service decomposes that priced net into `Base_Price__c` / `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` stamped on the OrderItem, so a future renewal can carry real dollars forward. **This half works end-to-end** (NetUnitPrice = 71 = 0.20 × 355 proven live).

**Feature 2 — Additional-year RENEWAL maintenance via COLA carry-forward.** On a renewal quote, the committed net should be `(Base_Price − Prior_Partner$ − Prior_Disc$) × (1 + COLA%/100)`. Canary: `(71 − 8.52 − 0) × 1.0785 = 67.38`. The build **correctly COMPUTES** this value (three parallel Apex methods + the procedure formula all agree at 67.38) but **commits the WRONG NetUnitPrice** — $0, or `67.38 × 0.90 = 60.64` (a partner double-discount). The correct 67.38 lands only in the custom field `COLACalculatedPrice__c`, never in a price field. **This half is broken at the commit layer.**

Both SDDs scope renewal as **single-year / annual**. A multi-year/MyCAP path exists in the build (`COLA_Outyear_Uplift_Percent__c`, MyCAP branch) **ahead of any design doc** — an open owner decision.

---

## 2. Components — labeled inventory

### 2.1 Apex (11 build classes; live bodies pulled via Tooling 2026-06-13)

| Layer | Class | Role |
|---|---|---|
| Quote trigger | **QuoteRenewalTypeHandler** | Sets `Quote_Type__c='Renewal'` when `OriginalActionType='Renew'`. Constants reused org-wide. |
| Quote trigger | **RenewalQuoteHeaderHandler** | Copies ~40 commercial/routing header fields (places, partner, currency, contacts) from source order's quote; fills blanks only. |
| QLI after-insert → Queueable | **RenewalQuoteLineHandler** | Deletes New-Maintenance/Perpetual carryover lines once a Renewal-Maintenance line exists. |
| QLI after-insert → Queueable | **RenewalAssetQuantityHandler** | Sets renewal-maint QLI.Quantity from source asset entitlement; flips QuoteAction.Type `No Change`→`Renew`. |
| QLI before-ins/upd | **COLAUpliftHandler** | Asset-renew COLA fields on QLI; shares `isManualLineOverride` predicate with the prehook. |
| **PRICING PREHOOK** | **COLAUpliftPrehook** (`implements RevSignaling.SignalingApexProcessor`, 1252 ln, Liam 2026-06-13) | Before procedure. Writes ONLY custom COLA fields; **does NOT seed any price field**. `appendStampedRenewalMaintenanceUpdates` writes `{COLACalculatedPrice__c, PartnerDiscountPercent, Discount}` only. Logs "Found 0 renewal QLIs" for No-Change lines. |
| **PRICING POSTHOOK** | **PartnerNetPricePosthook** (`implements RevSignaling.SignalingApexProcessor`, 975 ln, @version 1.4) | After procedure. Computes colaNet and writes context incl. NetUnitPrice — but the write is a **silent no-op** on an unpriced node. Also **re-stamps PartnerDiscountPercent** → partner double-count. |
| Service + invocable | **MaintenanceOrderDecompositionService** (903 ln) | New-business decomposition (`compute`, `resolveTierRate`) + Q2O carry-forward stamping + reprice persist/backfill. The heart of the new-business path. |
| Invocable | **QuoteToOrderFieldMapper** (239 ln) | Q2O bridge; maps QLI→OI incl. `Source_List_Price__c` (LIVE copy has it active; force-app copy stale/commented). |
| Invocable | **OrderRepriceInvocable** (138 ln) | Programmatic Reprice-All (PlaceOrderExecutor Force) before Activate. |
| Service + invocable | **RenewalMaintenancePricingService** (486 ln) | Applies COLA net into pricing context when DPP leaves NetUnitPrice 0. |
| Support service | **PartnerPricingService** (334 ln) | Partner margin/discount resolution; B-3 bulk-overload fixed to fall through to Product2 lookup. |

> Deploy landmine: author against **LIVE `Org Data/_src` copy** (has `buildOverrideMap`/`buildNetUnitPriceUpdate`), NOT the stale `Data/sc-maint/src` copy. Deploy `--test-level RunSpecifiedTests` to dodge a ~28-class recompile cascade.

### 2.2 V14 procedure elements (run order = single seq space 1..40; XML lists alphabetically)

| Seq | Element | actionType | resultIncluded | Role |
|---|---|---|---|---|
| 1 | PricingSetting (L73829) | PricingSettings | TRUE | engine init |
| 2 | **PriceBookEntries** (L73687) | ListPrice | TRUE | hydrates `DerivedPricingAttribute←IsDerived`, `ListPrice` (=0 for derived maint, 95% PBEDP gap) |
| 4.2 | DerivedPricingNetUnitPriceValueReset (L71755) | FormulaBasedPricing | FALSE | resets net (3-tier hard-code) |
| **5.2** | **DerivedProductsRenewals** (L72097) | DerivedPricing | **TRUE** | **the ONLY native committer of a derived net** — owns new-business 71. Gated by 5.1 `DerivedProductsNonRenewal` (QuoteTypeText≠'Renewal') → **skipped for renewals** |
| 6.2 | **DerivedPricingFormula** (L71690) | FormulaBasedPricing | FALSE | `IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,0)))×Source_List_Price__c`. **3 tiers only**; gate code `MTD` |
| 7.2 | DerivedPricingNewBusiness (L71820) | FormulaBasedPricing | FALSE | `×Base_Price__c`; gate misspelled **`MDT`** → **dead code** (no MDT AttributeDefinition) |
| 7.3 | **DerivedPricingRenewals** (L71885) | FormulaBasedPricing | FALSE | **computes 67.38** (ISNULL-guarded, B-4) → **DISCARDED** (resInc=false) |
| 7.4 | DerivedPricingValuesAssignment (L71936) | Assignment | FALSE | NetUnitPrice→InputUnitPrice (non-committing) |
| 8.2 | PartnerDiscountDerivedMaintenance20 (L73538) | ManualDiscount | TRUE | new-business partner %; 8.1 excludes renewals |
| 10.2 | COLAUpliftonRenewal27 (L71378) | Assignment | FALSE | `COLACalculatedPrice__c→InputUnitPrice`; gate (10.1) needs DPA=false + 'Renew' |
| 10.3 | **COLAUpliftonRenewalNet** (L71429) | Assignment | FALSE | `COLACalculatedPrice__c→NetUnitPrice` — **where 67.38 WOULD commit, but DISCARDED** |
| 11.2 | PartnerDiscount30 (L73393) | ManualDiscount | TRUE | general partner %; 11.1 excludes derived (DPA=true) |

### 2.3 Flows
- **Stamp_Maintenance_Pricing_Inputs** (V13, Active) — stamps `Base_Price__c`/`COLACalculatedPrice__c` **AFTER pricing**, no reprice follows → value lives only in the custom field.
- **Stamp_Source_List_Price** — stamps `Source_List_Price__c`.

### 2.4 Custom fields
| Field | Object(s) | Type | Note |
|---|---|---|---|
| `Base_Price__c` | QLI, OI | **Number(16,2)** (not Currency — currency-blind, SC-3384 risk) | decomposition + stamp flow |
| `Source_List_Price__c` | QLI, OI | Currency(16,2) | SourceListPricePrehook; Q2O map LIVE-active |
| `COLACalculatedPrice__c` | QLI(16,2), OI(14,2) | Currency | holds the correct 67.38 |
| `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` | QLI, OI | Currency(16,2) | carry-forward; often null on renewal OIs (B-4) |
| `COLA_Uplift_Percent__c` | QLI **Number(3,2)** / OI **Number(16,2)** | precision mismatch (max 9.99 on QLI; current max MDT 9.85) | from CMDT; formula ÷100 |
| `Fortra_Product_Type__c` | Product2, QLI, OI | Picklist | 'New Maintenance' \| 'Renewal Maintenance' \| … |
| `QuoteTypeText__c` | Quote, Order | Formula(Text) | derives 'Renewal' — the runtime gate |

### 2.5 CMDT
- **Maintenance_Rate__mdt** (7 rows): Basic 0.15, Professional 0.20, Standard 0.20, Premium 0.24, Express 0.30, Premier 0.30, Expert 0.35. **Referenced 0× in the procedure** (formula hard-codes only 3).
- **COLA_Uplift_Rules__mdt** (22 rows, `Default_Uplift_Percent__c` whole percents, all values correct/zero drift): e.g. GoAnywhere/Globalscape/Cybersecurity 7.85, RPA 9.85, Fortra_Platform/IPP 0. Blemishes: BoKS duplicate (dead 'Powertech IAM BoKS' vs load-bearing `TEMP_BoKS_IAM_ProductCat` covering 17 products) + 88 null-category products at silent 0%.

### 2.6 PBEDP coverage
- **3,453 IsDerived PBEs** (all UnitPrice=0, IsActive=true) vs **176 PriceBookEntryDerivedPrice rows** covering 174 distinct PBEs → **~95% gap (3,279 uncovered)**. By type: New Maint 1,665 missing, Renewal Maint 1,614 missing. Formula tally: 175 UnitPrice + 1 ListPrice outlier (FIM-FIM-RNM-DPEENM). M-5 "resolved" was 4 canary PBEs only.

---

## 3. End-to-end pricing flow — who computes vs who commits, and where it breaks

**Hook firing order (canary FINEST):** Hardware → Regional → Partner → AttributeVolume → **COLAUpliftPrehook** → [procedure] → **PartnerNetPricePosthook** → QLDescription. Both hooks are recursion-guarded and **fail-open**.

### (A) New-business first-year maintenance — WORKS
```
Phase 0 triggers: QuoteRenewalType/HeaderHandler stamp header; AssetQuantity normalizes qty.
seq1 PricingSetting (init)
seq2 PriceBookEntries → DPA=true, ListPrice=0; contributing license priced at catalog 355
seq4.2 reset (non-commit)
seq5.2 DerivedProductsRenewals (resInc=TRUE) ← NATIVELY DERIVES & COMMITS NetUnitPrice 71 = 0.20×355
        (via contributing license + PriceBookEntryDerivedPrice)        ◀── COMMIT OWNER
seq6.2/7.2 inline tier formulas compute into context (resInc=false, non-committing)
seq8.2 PartnerDiscountDerivedMaintenance20 (resInc=TRUE) → partner % if partner & non-Fortra-Originated & non-renewal
Q2O: createOrderFromQuote → QuoteToOrderFieldMapper.mapFields → MaintenanceOrderDecompositionService.compute
     decomposes 71 into Base_Price__c / Prior_Partner$ / Prior_Disc$ on OrderItem (carry-forward seed)
```
**Breaks only on tier**: seq5.2 native pull + the inline IF-chain both resolve only Premier/Standard/Professional. Basic/Premium/Express/Expert/`platinum` → **$0** (NB-DERIVED-TIER, 207 QLIA rows).

### (B) Renewal maintenance — BROKEN (no committed owner)
```
seq1 PricingSetting → seq2 PriceBookEntries (DPA=true, ListPrice=0, qty 0, SalesTransactionActionType='No Change')
seq4.2 reset (non-commit)
seq5.2 DerivedProductsRenewals  ──SKIPPED── (5.1 DerivedProductsNonRenewal: QuoteTypeText≠'Renewal')
seq7.3 DerivedPricingRenewals   COMPUTES 67.38 (ISNULL-guarded)  ──DISCARDED── (resInc=false)
seq8.2 PartnerDiscountDerivedMaintenance20  ──SKIPPED── (8.1 excludes renewal)
seq10.3 COLAUpliftonRenewalNet  COLACalc→NetUnitPrice  ──DISCARDED── (resInc=false; 10.1 also needs DPA=false + 'Renew')
seq11.2 PartnerDiscount30        ──SKIPPED── (11.1 excludes derived, DPA=true)
RESULT: NO resultIncluded=true element emits a NetUnitPrice for this line.
```

**Who computes vs who commits the 67.38:**
- **Computes (4 places, all agree):** `COLAUpliftPrehook.computeStampedMaintenanceColaNet:447`, `PartnerNetPricePosthook.computeRenewalMaintenanceColaNet:907`, `RenewalMaintenancePricingService.computeColaNet:300`, and procedure `DerivedPricingRenewals` (7.3).
- **Commits:** **nobody.** The line is an **UNPRICED NODE** — `ItemIsDerived=true` + `ListPrice=0` + `DerivedPricingAttribute` **null/unhydrated**. It is absent from every engine NetUnitPrice/InputUnitPrice/PartnerUnitPrice map (0 of 16 snapshots; present 646× as a context node). NetUnitPrice is **engine-owned, persisted only for priced nodes**.

**Proven-dead write layers:**
1. Procedure FBP/Assignment → NetUnitPrice (seq 33/41) — no commit (not a node).
2. Before-save flow → NetUnitPrice — **rejected**, `createable=False/updateable=False`.
3. Posthook `updateContextAttributes` — runs clean (linesUpdated=1) but **silent no-op** on the unpriced node.

**The two committed-wrong values:**
- **$0** = line never seeded → true unpriced node.
- **60.64 = 67.38 × 0.90** = **partner double-count**: `PartnerNetPricePosthook.buildRenewalMaintenanceColaUpdate` (L820) writes colaNet (already net of the prior $8.52 partner via L916) but **also re-stamps `PartnerDiscountPercent`** (L868-873) → engine re-applies ~10%. (54.58 = 60.64 × 0.90 on the priorDisc variant.) A genuine bug, **partly fixable in Apex without the procedure**.

> **Correction trail:** doc-11 native-override theory is **REFUTED** (native runs seq 5 BEFORE the formula seq 7, gated to non-renewals, and the formula's 67.38 is resInc=false so there is nothing to overwrite). doc-12 over-specified the disqualifier as qty-0/'No Change' — the **license line shares both and prices fine at 301.75**; the true disqualifier is **`DerivedPricingAttribute` null + ItemIsDerived + ListPrice=0** (doc-13). **Trust docs 12/13, not FINAL_REPORT's native-override narrative.**

---

## 4. The failure map

| Failure (sev) | Root cause | Shares root with | Fix lever | Risk | Owner-gated? |
|---|---|---|---|---|---|
| **CLUSTER: RENEWAL-COMMIT** — RN-COLA-COMMIT (crit), MAINT-ONLY (crit), RN-PARTNER-DD (high), RN-MULTIYEAR (high), MULTI-ASSET (high) | Derived renewal-maint line is an **unpriced node** (ItemIsDerived + ListPrice=0 + DerivedPricingAttribute null) → no resInc=true element commits NetUnitPrice; 67.38 lives only in `COLACalculatedPrice__c`. **Sub-mechanism A** = $0 structural exclusion; **Sub-mechanism B** = `×0.90` partner double-count (posthook re-stamps PartnerDiscountPercent). | each other (one wall) | (A) prehook seed `InputUnitPrice`+`ListPrice`+`DerivedPricingAttribute=false` + broaden QLI gate to admit 'No Change'/'New Maintenance'; OR cohort-scoped `DerivedPricingRenewals.resultIncluded=true`; OR native PBEDP config. (B) stop re-stamping PartnerDiscountPercent in posthook (Apex-only). | **HIGH** (513K live renewal-maint QLIs; in-place V14; A unproven) for the structural fix; **LOW** for the partner fix | **YES** (Nir/Marc) for procedure; partner-fix design-gated only |
| **NB-DERIVED-TIER** (high) | Tier rate hard-coded inline to 3 of 7 tiers (`DerivedPricingFormula` L71690 + twin L71820); `Maintenance_Rate__mdt` referenced 0×. Basic/Premium/Express/Expert/`platinum` → $0 (207 QLIA / 16 OIA rows). | M-2, MDT 'platinum' | Complete inline IF for all 7 tiers OR data-drive from `Maintenance_Rate__mdt`; resolve 'platinum'. Procedure edit (or data re-tag). | Med-high (procedure republish) | YES |
| **NB-DERIVED-FORMULA / M-2** (partial) | `DerivedPricingNewBusiness` (×Base_Price, gate misspelled `MDT` — no such AttributeDefinition) is permanently unreachable dead code. | NB-DERIVED-TIER (same element family) | Delete dead element + fix MTD/MDT literal; reconcile SDD. Rides the V15 cycle. | Low functional, inherits packaging risk | YES |
| **PBEDP-COVERAGE + ZERO-LIST-PBE** (high; SC-3372) | 3,279/3,453 (95%) derived PBEs lack PriceBookEntryDerivedPrice; all UnitPrice=0. Native DerivedPricingDataRetrieval hard-errors "contributing products missing"; also null `Source_List_Price__c` on new-biz lines → $0. | each other | **Data-only** REST backfill of PBEDP rows (Formula=UnitPrice, source=Product, scope=Both) + verify Stamp_Source_List_Price coverage; (design: remove native retrieval element). | Low per-PBE; no republish | Deploy-auth only |
| **RN-COLA-RATES + MDT-RECORDS** (partial; SC-3350) | All 22 COLA rates correct (zero drift). BoKS duplicate (dead 'Powertech IAM BoKS' vs load-bearing `TEMP_BoKS_IAM_ProductCat`) + 88 null-category products at silent 0%; orphan picklist 'platinum' has no rate row. | NB-DERIVED-TIER ('platinum') | CMDT/data: resolve BoKS duplicate, backfill Solution_Category__c on 88 products, decide 'platinum'. | Low (data) | Deploy-auth only |
| **DECOMP-SPLIT** (partial) | **Non-defect.** Build uses value-stamping on a self-contained maint SKU (`MaintenanceOrderDecompositionService` L869), NOT `Original_Order_Item__c` FK split (that field = PowerOrderSplittingService qty-splits, SC-3210/3368). B-6 holds. | none | Doc-only SDD reconciliation. | None | No |
| **B-5** (cleared/off-path) | `Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`) RefreshStatus=Failed ("Hash Key Group >200 rows") ~12 months — but feeds **native asset-initiated renewal** (discovery procedures), not the build's Q2O carry-forward. Renewals work without it. | M-3 (discovery anomaly) | Re-key to Asset.Id (valid) — but 3 active discovery procedures + DecisionTable UI-only deploy → separate change-managed window. | High blast (deferred) | YES (change-managed) |

> RN-PARTNER-DD's "double discount" is sub-mechanism B of the cluster; MULTI-ASSET proves the license/subscription leg prices correctly (4442.35) — isolating the defect to the derived maintenance leg.

---

## 5. Fix plan / sequencing

### Bundle A — Low-risk, UAT-in-place, do FIRST (no procedure republish)
- **A4 · `Fortra_Product_Type__c` typing fix** *(prerequisite)* — if the canary renewal line should be 'Renewal Maintenance' (currently 'New Maintenance' on a renewal quote), fix `Stamp_Maintenance_Pricing_Inputs`/decomposition typing so the line hits the prehook seed gate (L419-420) and the v1.4 posthook filter (L806). Flow/data, reversible.
- **A1 · Partner double-count removal** — in `PartnerNetPricePosthook.buildRenewalMaintenanceColaUpdate`, **stop re-stamping `PartnerDiscountPercent`** (drop L868-873) for renewal-maint lines whose colaNet already nets prior partner. Moves committed net 60.64→67.38 on lines that ARE priced nodes. Apex-only, `--test-level RunSpecifiedTests`, author against `Org Data/_src`. **Design-gated** (confirm no additional partner factor — evidence says yes).
- **A2 · Tier resolution** — if 4 missing tiers can map to the 3 live branches via data re-tag, do it here (data). If formula extension is required, it rides Bundle C.
- **A3 · PBEDP backfill** — create rows for the in-scope renewal test cohort (canary done); systemic 95% → defer to SC-3372.

### Bundle B — Dead-code removal (rides a procedure cycle)
- **B1 · Collapse M-2** — remove inert `DerivedPricingNewBusiness`, fix MTD/MDT literal, keep `DerivedPricingFormula`. Procedure XML → bundle into the **V15** clone with C. Low functional risk (already inert).

### Bundle C — High-risk, owner-gated, 513K-blast: renewal-COMMIT procedure fix
- **C1 · Make the derived renewal line a persisting priced node.** Candidate levers (none proven): (a) prehook seeds `InputUnitPrice`+`ListPrice`=COLACalculatedPrice__c AND hydrates `DerivedPricingAttribute=false` to route through the standard NetUnitPrice=InputUnitPrice assignment; (b) cohort-scoped `DerivedPricingRenewals.resultIncluded=true` (a blanket flip zeros ~513,622/513,627 renewal-maint QLIs — catastrophic); (c) native PBEDP-config route.

**Mandatory gates, in order:**
1. **Decisive clone test (UNRUN — required before any build):** on a V14 clone with an active version, seed InputUnitPrice+ListPrice+DerivedPricingAttribute=false on canary `0Q0WC0000038aXd0AI`, reprice with FINEST. **PASS** = `dn3y4` enters the NetUnitPrice map at 67.38 and persists, ValidationResult clean. **FAIL** (doc-13 predicts a bare InputUnitPrice seed is skipped — `AttributePricingFilter` requires DerivedPricingAttribute IsNotNull AND =false) → pivot to native-config route.
2. **Owner confirmation (Nir/Marc):** commit-precedence (first vs last resInc=true writer wins → 1 vs 2 edits); `DerivedProductsNonRenewal` filter polarity; that Formula Branch B (`Renewal AND ItemIsDerived`, unstamped) is broader than the stamped cohort.
3. **FIM-462 REGRESSION GATE:** any procedure edit must preserve native pricing on the ~513,627 native-priced renewal-maint QLIs (536,195 native lines org-wide). One wrong assumption silently zeros them — **no rollback net** (in-place V14, ExpressionSetVersion delete platform-blocked). Regression-gate product: **FIM-FIM-RNM-CCMLSE** (`01tWC00000DD16HYAT`).
4. **Context resync:** Context Def Manager → Deactivate All Dependencies → verify `SalesTransactionContextExt_v2` OrderEntitiesMapping carries every attr the formula reads → Sync/republish → activate the **single** V15 row (**never** LWC "Reactivate All Dependencies" — caused 8-versions-active corruption). Skipping re-opens gack 572633412-308158.
5. **V14 backup + rollback** (re-activate prior version + resync).

### Dependency order
`A4 (typing) → A1 (partner)` land immediately and raise priced-node lines to 67.38. `A2/A3` independent. Then `C1` (gated by its decisive test) closes the $0 structural case; `B1` rides C1's V15 cycle. Doc M-1 and prod M-3/M-6 are parallel, owner/prod-auth gated, off the UAT critical path.

### UAT-in-place vs sign-off matrix
- **No sign-off beyond standard:** A1 (Apex), A3 (data), A4 (Flow/data) — reversible, no republish.
- **Design-gated but UAT-safe:** A1 (partner-not-re-applied decision); A2 (tier fallback + 'platinum').
- **Owner sign-off + FIM-462 gate + clone test MANDATORY:** C1 (+ B1). The only 513K-blast item.

### Open DESIGN decisions for the owner
1. **Partner discount (headline):** confirm renewal maintenance carries ONLY the prior-year partner $ (already in the COLA base) and applies **no** additional partner factor. (Accepted quote `00781068` carries 60.64 — re-pricing it needs Finance/business sign-off; the "working" 60.64 may itself be the double-count or term/proration.)
2. **Multi-year / MyCAP scope:** single-year only (both SDDs say annual) or owe out-year/MyCAP? Build has `COLA_Outyear_Uplift_Percent__c` + MyCAP branch with no SDD backing — out-year rate source + per-year partner re-netting undefined.
3. **Typing:** is 'New Maintenance' on a renewal quote a stamping bug (→ 'Renewal Maintenance')?
4. **Tier fallback:** $0 (current) vs all 7 tiers resolve; what is picklist 'platinum' (typo for Premier? dead?); re-tag straggler products.
5. **PBEDP 95% gap:** backfill all 3,279 vs remove the native DerivedPricingDataRetrieval element (mutually exclusive) — SC-3372.
6. **Prod cutover (M-3/M-6, out of UAT scope):** create+map `SalesTransactionContextExt_v2`; co-deploy reconciled prehook/posthook (prod lineages stale, prod=Marc vs UAT=Nir).

---

## 6. Quick-reference appendix

**IDs**
- Procedure: `Rev_Mgmt_Default_Pricing_Procedure` V14/V140 · ExpressionSet `9QLWC0000015cDl4AI` · sole-active ESV `9QMWC00000023eX4AQ` · ESD `9QAWC0000003mg14AA`
- Canary quote: `0Q0WC0000038aXd0AI` (00781109) · maint QLI `0QLWC000003dn3y4AA` (PIA-PIA-RNM-PIAMBK `01tWC00000DD1bsYAD`, typed 'New Maintenance') · license line `0QLWC000003dn3x4AA` / PIA-PIA-NRPS-PIAP `01tWC00000DD1btYAD` (Perpetual, prices 301.75/355)
- Only renewal order priced E2E: `00095475` / `801WC00000kaGBpYAM` (60.64, null priors, UnitPrice=0)
- Renewal test quotes: `00781043` (single-line MissingContributor, line `ck6X4` — proves a clean 67.38 write does NOT land on a derived line even as a map key), `00781053`→54.58, `00781084`→60.64, `00781068` (ACCEPTED 60.64 — do not disturb without sign-off)
- Maint PBE `01uWC000005wsbUYAQ` (IsDerived, UnitPrice=0) + PBEDP `182WC000000FN26YAG` (Formula=UnitPrice)
- AttributeDefinition: `MTD` = Maintenance_Type_Defn `0tjWC000000096bYAA` (**no `MDT` record exists**)
- B-5 table: `0lDa50000007BJhEAM` Asset_Action_Source_Entries_Decision_Table_V2 (~430,335 rows)
- PBE decision table: `Price_Book_Entry_Decision_Table_v2` `0lDa50000007BErEAM`

**Formulas**
- New-business: `NetUnitPrice = IF(Premier,0.30,IF(Standard,0.20,IF(Professional,0.20,0))) × Source_List_Price__c`
- Renewal (canonical): `(Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA_Uplift_Percent__c/100)`, HALF_UP. Canary `(71 − 8.52 − 0) × 1.0785 = 67.38`.
- B-4 V14 form (ISNULL-guarded, resInc=FALSE): `IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (ISNULL(Base_Price__c,0) − ISNULL(Prior_Partner_Discount__c,0) − ISNULL(Prior_Discretionary_Discount__c,0)) × (1 + ISNULL(COLA_Uplift_Percent__c,0)/100)), NetUnitPrice)`
- Wrong commits: `$0` (unpriced node) · `60.64 = 67.38 × 0.90` (partner double-count) · `54.58 = 60.64 × 0.90`

**Apex file:line**
- `COLAUpliftPrehook.computeStampedMaintenanceColaNet:447` · `appendStampedRenewalMaintenanceUpdates` (gate L419-420) · `buildMaintenanceColaItemUpdate` (~L465-510, writes only COLACalc/PartnerDiscountPercent/Discount)
- `PartnerNetPricePosthook.computeRenewalMaintenanceColaNet:907/916` · `buildRenewalMaintenanceColaUpdate:820` · partner re-stamp L868-873 · `loadRenewalMaintenanceLines:806` (='Renewal Maintenance')
- `RenewalMaintenancePricingService.computeColaNet:300` · `applyToContext:178` · `applyColaNetFinalizeToContext:246`
- `MaintenanceOrderDecompositionService.buildPatchesFromWork:312` · maintenanceBase L869 · `OrderRepriceInvocable` persistFromWork L38/L70
- `PartnerPricingService` bulk overload L241/244 (B-3 fixed, falls through to Product2 lookup)

**Procedure element → full-file line**
PriceBookEntries L73687 · DerivedProductsRenewals L72097 (5.1 filter L71969) · DerivedPricingFormula L71690 · DerivedPricingNewBusiness L71820 · DerivedPricingRenewals L71885 · DerivedPricingValuesAssignment L71936 · COLAUpliftonRenewal27 L71378 · COLAUpliftonRenewalNet L71429 (10.1 gate L71327) · PartnerDiscountDerivedMaintenance20 L73538 (8.1 L73452) · PartnerDiscount30 L73393 (11.1 L73307) · seq-7 DerivedPricing filter L71603. Snapshot: `Data/sc-maint/sc3404/v14_snapshot_pre_reactivate/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (V14 block L69795-75410).

**Engine landmines**
ISNULL only (no BLANKVALUE/NULLVALUE/ISBLANK) · API v67 (v66 throws "Property 'dataType' not valid") · ExpressionSetDefinition deploys via mdapi but **DecisionTable is UI-only** · never LWC "Reactivate All Dependencies" · ExpressionSetVersion delete platform-blocked · NetUnitPrice createable/updateable=False (flow lever dead) · `COLACalculatedPrice__c` not a valid resource in native-pull/contributor filter context (scope on QuoteTypeText__c there).

**Artifacts:** verdicts `Data/sc-maint/sc3346_e2e/verdicts_merged.json` (19 scenarios: 7 pass / 4 partial / 8 fail) · base canary log `Data/sc-maint/sc3404/logs/07LWC00000OxZTl2AN.log` · v1.5 posthook log `…Oxacj2AB.log` · single-line `…OxZYb2AN.log`.