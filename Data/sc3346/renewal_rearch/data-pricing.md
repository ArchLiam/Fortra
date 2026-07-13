I have a complete, evidence-backed picture. Here is my focused report.

---

# RENEWAL PRICING — how each line type gets priced, and every place a net dies

**Angle:** value-provenance of every renewal line type through V23 procedure + the COLA committer chain. All data pulled read-only from FortraUAT 2026-07-09.

## Sources of truth (exact paths)
- **V23 pricing procedure (Active):** `Data/sc3346/test_nonrenewal/src/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`. This is the ESD with all 22 versions inline; **V23 = lines 124676–131338** (only block with `<status>Active</status>`, line 124688). Step labels are alphabetized in the dump; execution is driven by `parentStep`/`sequenceNumber` + `advancedCondition` filters, not label order.
- **Committer chain:** `force-app/main/default/classes/{COLAUpliftHandler, COLAUpliftPrehook, COLAUpliftCalculator, RenewalMaintenancePricingService, RenewalMaintenanceColaCalculator, PartnerNetPricePosthook, RenewalQuoteActionStamp}.cls`
- **Wiring:** `force-app/main/default/triggers/QuoteLineItemTrigger.trigger`; `force-app/main/default/flows/Fortra_Quote_Reprice.flow-meta.xml`
- **Rates:** `COLA_Uplift_Rules__mdt` (per Solution Category)

---

## 1. The COLA formula(s) actually in use, and precedence

**Rate selection (3-tier), one shared predicate** — `COLAUpliftCalculator.resolveTier` (lines 64–78), used by both the trigger handler and the prehook so they can't drift:
1. **Line Override** — `COLA_Uplift_Percent__c` differs from every system rate (`isManualLineOverride`, lines 36–41) OR differs from stamped `Default_COLA_Uplift_Percent__c` (`isPersistedLineOverride`).
2. **Contract Override** — `AssetContractRelationship.Contract.COLA_Override_Percent__c` where `Contract.Status='Activated'` and `COLA_Override_Persist_Until__c` is null or ≥ today (`COLAUpliftHandler.buildContractOverrideMap` 435–481; prehook 728–798).
3. **CMDT Lookup** — `COLA_Uplift_Rules__mdt.Default_Uplift_Percent__c` keyed by `Solution_Category__c`. Live rates (grounded): BoKS/Powertech = **7.85%**, Offensive Security = **6.2%**, Vulnerability Mgmt = **6.2%**, Brand Protection = **5%**, Data Protection/Core IGA/Capacity = **4.7%**, RPA = **9.85%**, Fortra Platform/IPP = **0%**.
- **MyCAP** is an **out-year** concept only (`COLA_Outyear_Uplift_Percent__c`, `MyCAP_Rules__mdt` default 3%), never a year-1 rate. Confirmed in code comments and by "0 of 7 real MyCAP lines carry the MyCAP value in year-1."

**Three distinct price math paths (this is the core finding — the "COLA formula" is not one thing):**

| Path | Formula | Base source | Who computes |
|---|---|---|---|
| **A. Subscription/standard renew** | `preCOLA × (1+uplift%)^terms` (compound if PricingTermCount>1, else flat) | `Pre_COLA_Price__c` = prior asset net = `UnitPrice/(1+defaultPct/100)` or SourceAsset.Price | `COLAUpliftCalculator.buildCOLAContextUpdate` (342–395); handler `populateCOLAFields` uses `SourceAsset.Price × (1+%/100)` (323) |
| **B. Renewal-maintenance net** | `(Base_Price__c − Prior_Partner_Discount__c − priorDisc) × (1+uplift%)` | stamped prior-year fossils; `priorDisc` = `Prior_Discretionary_Discount__c` or `Discount% × (Base−priorPartner)` | `computeStampedMaintenanceColaNet` (105–118) / `RenewalMaintenancePricingService.computeColaNet` (300–315) / `RenewalMaintenanceColaCalculator` (14–29) — three copies of the same formula |
| **C. New-business maintenance %** | `pct × base`, pct = Premier 30% / Standard 20% / Professional 20% / else 0 | `Base_Price__c` else `Pre_Partner_Price__c` else `InputUnitPrice` | V23 `DerivedPricingFormula` (line 2347) — **`IF(QuoteTypeText__c='Renewal', NetUnitPrice, …)`** i.e. a **no-op passthrough on renewals** |

Result of all three lands in `COLACalculatedPrice__c`, which the procedure then tries to commit.

---

## 2. V23 procedure: the two renewal-relevant blocks

**COLA commit block** (`ListContainer2`, procedure lines 2044–2189). Filter `COLAUpliftonRenewal` (2096–2127) fires only when **ALL**: `ItemPricingSource = 'LastTransaction'` AND `DerivedPricingAttribute IsNotNull` AND `SalesTransactionActionType = 'Renew'` AND `COLA_Uplift_Percent__c IsNotNull`. Then two assignments copy the pre-stamped value in: `InputUnitPrice = COLACalculatedPrice__c` (seq 2) and `NetUnitPrice = COLACalculatedPrice__c` (seq 3). **The procedure does not calculate COLA — it copies a value the Apex hooks already stamped, and only for a Renew line that reached the LastTransaction priced node.**

**Derived block** (`DerivedProductsNativePull` ListGroup, lines 2469–2628). Child seq-1 `DerivedProductsNonRenewal` is an `AdvancedListFilter` with `QuoteTypeText__c NotEquals 'Renewal'` (2481–2500); child seq-2 `DerivedProductsRenewals` is the native `DerivedPricing` action (contributor-keyed, 2502–2628). Despite the name, **the filter strips every renewal line before the DerivedPricing action runs** — so the native derived committer only ever prices *non-renewal* lines. A renewal line that is `IsDerived` and has no contributor gets **nothing** here. `DerivedPricingFormula` (2340–2402) and `DerivedPricingNetUnitPriceValueReset` (2404–2467) both short-circuit to `NetUnitPrice` passthrough on renewals — no-ops that leave a null net null.

Because the procedure can't reliably commit renewal nets, the real work is done by Apex hooks around it (§3).

---

## 3. The committer chain (execution order) — every layer is a workaround

1. **`QuoteLineItemTrigger` before-insert** (trigger lines 36–43): `RenewalQuoteActionStamp.synthesizeRenewQuoteActions` runs **first**, then `COLAUpliftHandler.handleBeforeInsert`. The Stamp mints a `Type='Renew'` QuoteAction on QA-less RRM lines pointed at the owned **New-Maintenance (else Perpetual)** asset, keyed by `account|Solution_Category__c` (cross-product), so the line is *born* a priced Renew node (RenewalQuoteActionStamp 37–144). This is the **proven fix** — already wired, but see §5 for rollout state.
2. **`COLAUpliftHandler.handleBeforeInsert`** (34–47): only for `QuoteAction.Type='Renew'`. Sets `UnitPrice = SourceAsset.Price × (1+colaPercent/100)`, `Pre_COLA_Price__c = SourceAsset.Price`, `COLA_Uplift_Percent__c`, `COLA_Source__c`. **Does not write `NetUnitPrice` or `COLACalculatedPrice__c`.** `handleBeforeUpdate` re-syncs % to CMDT and promotes genuine line overrides.
3. **`COLAUpliftPrehook`** (pricing prehook, during DPP): subscriptions get `COLACalculatedPrice__c` (compound) + an **isolated `NetUnitPrice` seed** — SC-3350 comment (COLAUpliftCalculator 138–176) states a prehook-level `NetUnitPrice` write "is the only mechanism proven live to COMMIT the net… a Formula/Assignment write from a procedure ListGroup updates only the context var and never flushes." RRM-without-renew-asset lines get `appendStampedRenewalMaintenanceUpdates` → `computeStampedMaintenanceColaNet` → writes `COLACalculatedPrice__c` (prehook 553–596).
4. **V23 COLA block** copies `COLACalculatedPrice__c → NetUnitPrice` (only for LastTransaction/Renew, §2).
5. **`PartnerNetPricePosthook.buildRenewalColaCommitUpdate`** (posthook, 1177–1224): if `COLACalculatedPrice__c > 0` but the procedure's `NetUnitPrice` ≠ colaNet, force `NetUnitPrice/TotalPrice/PartnerUnitPrice = COLACalculatedPrice__c`. Idempotent (skips if already equal). Also applies partner net.
6. **`RenewalMaintenancePricingService`** (reprice flow, two-phase, `Fortra_Quote_Reprice`): `Apply_Renewal_Maintenance_Net` (pre-DPP: seed `COLACalculatedPrice__c`/`InputUnitPrice`/`SalesTransactionActionType='Renew'`, lines 218–225) then `Finalize_Renewal_Maintenance_Net` (`finalizeAfterPricing=true`, post-DPP: hard-stamp `UnitPrice/NetUnitPrice/NetTotalPrice/TotalPrice/PartnerUnitPrice = colaNet`, 271–282) then `Persist_Context`. Gated by `usesColaOnlyRepriceForLines` — renewal quote with RRM lines and no live subscription/perpetual (65–97).

So a single RRM renewal net can be written by **up to four different committers** (prehook seed, procedure copy, posthook commit, reprice finalize), each reading `COLACalculatedPrice__c` — which is exactly why nets diverge (§4, §5).

---

## 4. Real repriced examples (UnitPrice vs NetUnitPrice vs COLACalculatedPrice__c)

**Subscription renewal — WORKS** (TermDefined, QA=Renew, ItemPricingSource=LastTransaction):
- beSTORM (Q…FgP0AW): preCOLA 60000, C%=6.2 → calc 63720, **UnitPrice 63720, Net 63720**. 60000×1.062 ✓
- Active Defense BEC: preCOLA 94000, C%=5 → calc/U/Net all 98700 ✓
- **Partner** subscription beSECURE (Q…iBh0AK): preCOLA 6695.30, C%=6.2 → calc 7110.41, **UnitPrice 7110.41 (list-COLA'd), Net 6257.16 (= 7110.41 × 0.88 partner)**. Shows UnitPrice=list vs NetUnitPrice=post-partner.

**Renewal Maintenance (RRM) via proven fix — WORKS** (the *only* RRM/Renew line in the org):
- Powertech BoKS (Q…iBh0AK): p2t=Renewal Maintenance, TermDefined, QA=Renew, **source asset = New Maintenance (cross-product)**, Base 355, preCOLA 71 (= 20% of 355), C%=7.85 → **Net 76.57 (= 71×1.0785)**, UnitPrice 76.57. **But `COLACalculatedPrice__c = 382.87` (= 355×1.0785) — a stale/wrong fossil that disagrees with the committed net.** The correct net came from the maintenance-base path (preCOLA 71), not from the procedure copy of the fossil.

**RNM OneTime → Amend — CONFIRMED DEFECT** (8 lines, all Powertech BoKS maintenance):
- Q…qRp0AK / GgL0AW: p2t=New Maintenance, OneTime, **QA=Amend**, source=New Maintenance, C%=7.85, **`COLACalculatedPrice__c = 76.57` (= Base 71 × 1.0785) correctly computed — but `UnitPrice = NULL`, `NetUnitPrice = NULL`.** COLA was calculated and stranded in the fossil field; nothing ever committed it because (a) the derived committer is filtered out on renewals and (b) the procedure COLA block requires `SalesTransactionActionType='Renew'` which an Amend line fails. Same pattern at larger bases: OpB0AW calc 3300.21 (Base 3060), R6D0AW calc 3666.90 (Base 3400) — all Net=NULL.

**Odd combos showing provenance conflict:**
- RRM OneTime → Renew (Q…2MH0AY): Base 60.64, preCOLA 60.64, C%=7.85 → `COLACalculatedPrice__c = 65.40` (Base×COLA) but **Net = 67.38 (= asset price 62.48 × 1.0785)** — the handler's SourceAsset.Price path won over the Base path; the two disagree by ~3%.

---

## 5. EVERY place a renewal net ends up null / $0 / stale-fossil (with mechanism + magnitude)

Aggregate over all renewal-quote lines (`Quote.Quote_Type__c='Renewal'`), by product type × selling model × QuoteAction:

| Failure mode | Mechanism | Evidence / count |
|---|---|---|
| **RNM OneTime routed to Amend** | OneTime can't Renew → QuoteAction=Amend + IsDerived → derived path, which `DerivedProductsNonRenewal` filters out of renewals; COLA block also skips (needs action='Renew'). `COLACalculatedPrice__c` computed, `NetUnitPrice` never written → **NULL** | `New Maintenance/OneTime/Amend`: 8 lines, **sumNet=NULL** |
| **RRM contributor-less freeze** | Configurator auto-adds RRM line with **no `Type='Renew'` QuoteAction**; native `DerivedProductsRenewals` is contributor-keyed → line skipped → `NetUnitPrice` freezes at the COLA fossil / $0 (RenewalQuoteActionStamp doc, lines 4–9) | **`Renewal Maintenance/TermDefined/None`: 185,285 lines, sumNet=NULL** — the dominant population |
| **Source Asset.Price = 0 or null** | Handler multiplies COLA× the prior asset base; a legacy/migrated asset with Price 0 gives 0×(1+%)=$0. `COLA_Uplift_Percent__c` still stamped, so it looks "priced" | Q…IXBt0AO: 3 Core Impact/Cobalt Strike lines, TermDefined/Renew, **source Asset.Price=0**, C%=6.2, preCOLA=null, **Net=0** |
| **`computeColaNet` null guard** | Returns null when `Base_Price__c` null/≤0, **or `preColaNet = Base − priorPartner − priorDisc ≤ 0`** (RenewalMaintenancePricingService 300–315; Calculator 114–116). Over-stamped prior partner/discretionary fossils sink the base below zero → line stays $0 | design guard; triggers on stale/over-stamped `Prior_*` |
| **`Base_Price__c` holds the contributor/perpetual base** | For RRM, `Base_Price__c` sometimes = the **license** base (355) not the maintenance base (71) → fossil `COLACalculatedPrice__c=382.87` is ~5× too high; `isContributorBaseOnMaintenanceLine` (≥10000 & net<50% of base) tries to fall back to prior-year net, else null (RenewalMaintenanceColaCalculator 35–50) | Q…iBh0AK fossil 382.87 vs true net 76.57 |
| **Stale fossil disagrees with committed net** | Four committers each read `COLACalculatedPrice__c`; last writer wins. `COLACalculatedPrice__c` (Base×COLA) can permanently disagree with `NetUnitPrice` (preCOLA×COLA or assetPrice×COLA) | iBh0AK (382.87 vs 76.57); 2MH0AY (65.40 vs 67.38) |
| **No-Change lines** | OneTime license/perpetual carried unchanged → Quantity 0, $0 by platform design (not re-sold) | `Perpetual/OneTime/No Change`: 6 lines; `Subscription/OneTime/No Change`: 5 @ $0 |
| **Lines never linked to a priced QuoteAction** | `QuoteAction.Type = None` (unlinked) → never enters any Renew/LastTransaction committer → `NetUnitPrice` NULL | `Subscription/TermDefined/None`: 23,653 (sumNet 743); `New Maintenance/OneTime/None`: 16,682 |
| **`updateContextAttributes` batch poisoning** | Including a context-only attribute (`COLA_Uplift_Percent__c`, `COLAExplainer__c`, `COLAApplied__c`) silently fails the whole batch — nets don't flush (COLAUpliftCalculator 282–285; prehook 16–18) | latent; drives the "% present, price absent" signature |

**Contrast that works:** `Subscription/TermDefined/Renew` = 85 lines, sumNet **$9.11M** (healthy). The correct path (LastTransaction priced node + COLA block + prehook seed) is proven at scale for subscriptions.

---

## 6. Re-architecture headline

- The native RLM derived-pricing engine is **structurally excluded from renewals** (`DerivedProductsNonRenewal`), so **all** renewal maintenance pricing is carried by an out-of-band Apex fossil-reconstruction chain: stamp `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` / `Base_Price__c` at some earlier point, then recompute `(Base − priors) × (1+COLA%)` and force it into the context via up to four redundant committers. Every failure mode above is a fossil that is missing, zero, or stale.
- `COLACalculatedPrice__c` is simultaneously **the transport for the answer** and **a stale fossil** — its meaning depends on what `Base_Price__c` happened to hold (license base vs maintenance base), so it cannot be trusted as the net without cross-checking `Pre_COLA_Price__c`.
- The real fix (`RenewalQuoteActionStamp`, born-net `Type='Renew'` QA sourcing the RNM/Perpetual asset cross-product by `account|Solution_Category__c`) is **wired in the trigger but exercised on exactly 1 line** in UAT (`Renewal Maintenance/TermDefined/Renew`, sumNet 76.57) against **185,285** frozen-null RRM lines. Rollout = repricing the backlog through the born-Renew path (or replacing the two-catalog RNM/RRM design so maintenance renews as a TermDefined LastTransaction node like subscriptions do).