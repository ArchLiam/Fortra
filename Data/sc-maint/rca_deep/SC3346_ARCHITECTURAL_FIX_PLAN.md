# SC-3346 Renewal-Maintenance — Architectural Fix Plan (FortraUAT, 2026-06-15)

## Executive recommendation — which option, and why

**Recommend Option B (renew the OWNED maintenance product as-itself), in its low-blast-radius "rule-retarget" form — NOT B-merge, and NOT Option A.** The four probes converge on one decisive fact: **the COLA renewal commit is gated by action type, not by the RRM product.** Procedure V14 step `COLAUpliftonRenewal` (ExpressionSet `9QLWC0000015cDl4AI`) fires on `SalesTransactionActionType='Renew' + ItemPricingSource='LastTransaction'` with **no Product2-Id, ProductCode, or `Fortra_Product_Type__c` criterion anywhere in the gate** — so an RNM line renewed as `Type='Renew'` against the customer's owned RNM asset commits the COLA exactly the way the beSECURE subscription line already does (proven live: `VM-BSL-RSL-BESECB` → NetUnitPrice 4442.35 committed). Option A is **strictly weaker and structurally broken**: the first renewal that would *create* the RRM asset itself commits the fossil bug (Nir's first renewal activated 60.64), so it cannot heal renewal #1 for any of the ~current real customers, none of whom own an RRM asset. The real defect is not "wrong product" — it is that **maintenance renewal lines are bound to their asset as `QuoteAction.Type='No Change'`, never `'Renew'`** (50,000-line live sample: 43,720 Renewal-Maint + 6,280 New-Maint, ALL with empty QuoteAction.Type), and the current design *deletes* the owned-RNM carryover and replaces it with an asset-less AutoAdd RRM line that can never resolve a contributor.

## The blast radius — what depends on the RNM/RRM split

This is **not a single-SKU problem.** The PIA BoKS trio is one instance of a catalog-wide modeling pattern.

| Dependency | Detail / verified id | Coupling to the split | Breaks under B (rule-retarget)? |
|---|---|---|---|
| **Catalog scale** | 1,711 active Renewal-Maint + 1,682 New-Maint Product2 (near 1:1 pairing) + 1,521 Perpetual; ~202 active Configurator PCRs follow the license→maintenance AutoAdd pattern | The whole catalog mirrors this | No (rule-retarget is config-layer, not a product wipe) |
| **The 3 products** | License `01tWC00000DD1btYAD` (PIA-PIA-NRPS-PIAP, Perpetual, RC_41000); RNM `01tWC00000DD1bsYAD` (PIA-PIA-RNM-PIAMBK, New Maintenance, RC_42000); RRM `01tWC00000DD1buYAD` (PIA-PIA-RRM-PIAM, Renewal Maintenance, RC_43000). All active; both maintenance products non-Services, non-Subsplit | Identity of which product carries each line | Product kept; line just stays RNM |
| **Pricing procedure V14** | ExpressionSet `9QLWC0000015cDl4AI` / ESD `9QAWC0000003mg14AA`. `COLAUpliftonRenewal` gate = action-type only (no product/type criterion); `COLAUpliftonRenewalNet` writes `COLACalculatedPrice__c → NetUnitPrice`. NOTE: the V14 **entry** step `DerivedPricing` (seq 1) DOES carry crit 6-7-8 `QuoteTypeText__c='Renewal' AND Fortra_Product_Type__c='Renewal Maintenance' AND COLACalculatedPrice__c>0` | Entry gate references the literal label; commit gate does not | **Entry-gate criterion must widen** to accept New Maintenance (see RECOMMENDATION) |
| **COLAUpliftPrehook** (live LMD 2026-06-14T14:40:21Z, api65) | Primary `buildLineItemUpdates`: `WHERE QuoteAction.Type='Renew'` (product-agnostic — the path B relies on). Fallback `appendStampedRenewalMaintenanceUpdates` (line ~511-520): `WHERE Fortra_Product_Type__c='Renewal Maintenance'` — the **one** hard product-type filter in the commit chain | Fallback hard-codes the literal; primary does not | **One SOQL filter widens** `'Renewal Maintenance' → IN (...,'New Maintenance')` |
| **COLAUpliftHandler** | `handleBeforeInsert` gates on `QuoteAction.Type='Renew'` + `SourceAsset.Product2.Solution_Category__c`. **Zero** references to Fortra_Product_Type / RRM / RNM | None | No |
| **PCR Year-1** `14OWC0000022ULp2AM` | criteria `ItemProductCode='PIA-PIA-NRPS-PIAP' AND QuoteTypeText__c='New'` → AutoAdd RNM `01tWC00000DD1bsYAD`. Active | New-business maintenance | No change (keeps adding RNM) |
| **PCR Year-2** `14OWC0000022Eyb2AE` | criteria `...='PIA-PIA-NRPS-PIAP' AND QuoteTypeText__c='Renewal'` → AutoAdd RRM `01tWC00000DD1buYAD`. Active | THE swap to RRM | **Retarget to RNM or disable** (PCR has no migration tooling — Setup UI/manual) |
| **PBEDP** (4 rows) | BOTH RNM and RRM derive from the SAME contributing product = the LICENSE `01tWC00000DD1btYAD`, Formula='UnitPrice'. That is why pointing the renewal at the license yields UnitPrice=325 (wrong). RNM is itself derived (`01uWC000005wsbUYAQ`), so RNM→RRM PBEDP is platform-rejected | Contributor resolution | No PBEDP edit under B — B uses **Asset Discovery product-match** (asset.Product2 = line.Product2), bypassing PBEDP |
| **RenewalQuoteLineHandler.cls** | Entire purpose = the RNM→RRM swap: after PCR adds RRM, it DELETES the New-Maintenance + Perpetual carryover (`CARRYOVER_PRODUCT_TYPES={New Maintenance, Perpetual}`) once a Renewal-Maintenance line exists, so "Year 2+ bills Renewal Maintenance only" | The swap choreography | **Inverted/removed** — must change together with PCR Year-2 or risk double-billing |
| **Workday line-type** `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (ACTIVE V11) | Decisions key ONLY on `pse__IsServicesProduct__c`, `Is_Subsplit_Product__c`, PS-Service-Type attr. **0** field references to Fortra_Product_Type (only in `<description>` text). Both maintenance products → FIXED AMOUNT identically | NONE (low coupling) | **No** — biggest de-risk |
| **Billing dates** `Fortra_OrderItem_Set_Dates` (ACTIVE) | Branches only on `Rev_Category__c='RC_41000'` (Perpetual). RC_42000 (New Maint) and RC_43000 (Renewal Maint) take the IDENTICAL non-perpetual path | NONE | No |
| **ARR** `Fortra_QuoteLineItem_Calculate_ARR` (ACTIVE) | Double-count guard = `Quote.Quote_Type__c != 'Renewal'`, NOT product type. An RNM line on a Renewal quote → ARR=0. **Single biggest Option-B de-risking finding** | Guard is quote-type, not product-type | No (provided renewals stay Quote_Type='Renewal' — guaranteed by initiateRenewal) |
| **Partner pricing** `Partner_Pricing_Model__c` (30 rows) | SEPARATE margin columns `New_Maintenance_Percent__c` vs `Renewal_Maintenance_Percent__c` + `Non_Orig_New_Maint_Pct__c` / `Non_Orig_Ren_Maint_Pct__c`; selected via QLI `Fortra_Product_Type__c`. **THE principal B-merge breaker** | High under B-MERGE | **Yes for B-merge** — collapsing forces one rate across 30 models. Under rule-retarget B, the line carries 'New Maintenance' → would select the NEW-maint band on a renewal (see Open Questions) |
| **Workday/MuleSoft payload** | Mule reads OrderItem `Workday_Contract_Line_Type__c` (flow-stamped, unchanged under B), NOT Fortra_Product_Type__c. `MaintenanceOrderDecompositionService` only passes the value through | NONE | No |
| **DocGen / reporting** | DataRaptors `DMTurboExtractQuoteLineItem_1`, `DMExtractFortraQuote_1`, `DMTransformFortraQuote_1`; OmniScript `Quote_GenerateDoc`; `Order.Renewal_Maintenance_Quote__c`; `RCATechnicalProductService`. Read the label for template selection / reporting | Low (read-only) but reclassifies renewal bookings | Re-test PDF; **audit reporting** (see Open Questions) |
| **Missing schema** | `Product2.Renewal_Product__c` / `Substitution_Product__c` **DO NOT EXIST** in this org | Blocks Option A's declarative substitution sub-variant | n/a |

**Live volume / the smoking gun:** Assets — RNM=11, License=68, **RRM=1** (the artificial Nir test asset). QuoteLineItem — RNM=53, License=91, **RRM=124**. OrderItem — RNM=17, License=53, **RRM=1**. The 124 RRM quote lines vs 1 RRM asset/order item is the defect's shape: RRM lines are auto-added at renewal but never resolve a matching-product contributor (no real RRM assets exist), so they never commit and never reach an Order.

## Option A — bootstrap an RRM asset

**Premise:** make a customer OWN a `PIA-PIA-RRM-PIAM` asset so the native discovery contributor resolves by product, with zero procedure changes.

**Steps (across the three sub-paths):**
- (i) NB-creates-RRM: change Year-1 PCR `14OWC0000022ULp2AM` to add RRM instead of RNM on new business.
- (ii) RNM→RRM substitution at renewal: swap the renewal line's product.
- (iii) First-renewal bootstrap: let the first activated RRM renewal mint the RRM asset, then ride the self-sustaining loop.

**What is PROVEN true (so we're honest):**
- An activated order containing an RRM line **does** create an RRM asset (asset `02iWC000008GKPaYAO`, Price 60.64, born 2026-06-11 18:40:36 from activated Order 00095475 / OrderItem `802WC00000OgsuEYAR`; AssetAction `4nLWC00000319M62AI` Type=Generate, CategoryEnum='Initial Sale'). Step (iii) self-creation is real.
- It is **self-sustaining from renewal #2**: that RRM asset became the SourceAsset of the second renewal's Renew QuoteAction (`7ocWC00000u7yf8YAA`) on quote `0Q0WC00000382MH0AY` — the 67.38 control line. Once an account owns an RRM asset, the gate passes and net commits correctly each cycle.

**The first-renewal chicken-and-egg (the fatal flaw):**
The FIRST renewal that creates the RRM asset itself commits the **WRONG** value. On first-renewal quote `0Q0WC0000037yTx0AI` the RRM QLI had `QuoteActionId=NULL` and committed `NetUnitPrice=60.64` (the fossil bug); the only Renew QuoteAction on that quote pointed at a beSECURE subscription asset, not maintenance. The 60.64 line activated into an RRM asset carrying Price=60.64. **Bootstrapping RRM via the normal flow propagates the bug on cycle #1 for EVERY real account** (none own RRM today), and only heals from cycle #2. The crucial mechanical correction: committed net is `Base_Price__c`-derived (`COLAUpliftPrehook`: `(Base_Price − priorPartner − priorDisc) × (1+cola%)`, control Base_Price=71 → 67.38), **provenance-independent of the asset Price** — so the literal RRM asset matters only for *satisfying the gate*, not for the number. That means an asset bootstrap buys nothing that a Renew QuoteAction against the **already-owned RNM asset** doesn't already buy (62.48 × 1.0785 = 67.38, confirmed).

**Feasibility: HARD / rejected as primary.**
- Sub-path (i) is **wrong**: mislabels a new sale as 'Renewal Maintenance' and RRM new-business hits the COLA gate with no prior transaction.
- Sub-path (ii) has **no declarative path** — `Renewal_Product__c`/`Substitution_Product__c` don't exist; substitution needs net-new Apex in the renewal-creation path, exposed to the RLM/Subscription-Mgmt Quote-DML lock.
- Sub-path (iii) cannot close the egg: no RRM asset exists at cycle #1, so the gate can only be satisfied by a Renew QuoteAction against an already-owned asset — which is Option B, not Option A.
- PBEDP can't map RNM→RRM (RNM is itself derived; platform rejects "a derived product can't be set as the source product").

**Blast radius of A:** every cycle-1 asset/Order/Workday record born from a fossil renewal is wrong and needs separate remediation; 1,711-product asset-model migration; new schema for the declarative variant. **Option A is downstream-equivalent to, but strictly weaker than, Option B.**

## Option B — renew the owned product (RNM-as-itself) / B-merge

**Does COLA still fire? — YES, by ACTION TYPE, not product (verified four ways):**
- Procedure V14 `COLAUpliftonRenewal` advancedCondition = `ItemPricingSource='LastTransaction' AND DerivedPricingAttribute=false AND SalesTransactionActionType='Renew' AND COLA_Uplift_Percent__c IsNotNull`. **No product/type criterion.** Child `COLAUpliftonRenewalNet` writes `COLACalculatedPrice__c → NetUnitPrice`.
- `COLAUpliftPrehook.buildLineItemUpdates` (primary) gates purely on `QuoteAction.Type='Renew'`, derives from `SourceAsset.Price` + `SourceAsset.Product2.Solution_Category__c`. Product-agnostic.
- `COLAUpliftHandler.handleBeforeInsert` gates on `QuoteAction.Type='Renew'` + Solution_Category. Zero product/type references.
- **Live proof of equivalence:** on Nir DPP Test 2, the RRM line WITH `QuoteAction.Type='Renew'` (SourceAsset = RRM asset) committed NetUnitPrice=67.38; a sibling RRM line WITHOUT a Renew QA got `COLACalculatedPrice__c=67.38` stamped but NetUnitPrice stayed 60.64 (uncommitted). **The commit depends on the Renew-QA + matching asset, not the product.** The beSECURE subscription line proves the same mechanism end-to-end (NetUnitPrice 4442.35 committed).

**The true linchpin / systemic root:** maintenance renewal lines are **never** bound to a Renew QuoteAction. The platform DOES carry the owned RNM asset onto the renewal — but as `QuoteAction.Type='No Change'` (live: QLI `0QLWC000003cMIj4AM`, SourceAsset `02iWC000008DSBZYA4` RNM 62.48, Type='No Change'), which fails BOTH the procedure gate and the prehook SOQL. Then `RenewalQuoteLineHandler` deletes that carryover and substitutes an asset-less AutoAdd RRM line that can never resolve a contributor. **Option B = stop deleting/replacing the RNM carryover, and ensure it renews as `Type='Renew'` so asset-product matches line-product.**

**Steps (rule-retarget B):**
1. Disable/retire PCR Year-2 `14OWC0000022Eyb2AE` (the asset-less RRM AutoAdd).
2. Invert/remove the carryover-delete in `RenewalQuoteLineHandler.cls` so the platform-created RNM line bound to the owned RNM asset survives.
3. Make the kept RNM maintenance renewal line carry `QuoteAction.Type='Renew'` (not 'No Change') — the central unknown; tied to which asset Ids `initiateRenewal`/`Fortra_Create_Renewal_Quote` pass in `renewAssetIds` and asset lifecycle/term state.
4. Widen the V14 entry-step `DerivedPricing` criterion 7 and the prehook fallback SOQL from `='Renewal Maintenance'` to include `'New Maintenance'`.

**What breaks downstream — verified SAFE under B:**
- **Workday contract line type:** unchanged — both products are non-Services/non-Subsplit → FIXED AMOUNT; the live flow never reads Fortra_Product_Type.
- **Billing dates:** unchanged — RC_42000 and RC_43000 share the non-perpetual path.
- **ARR:** unchanged — guard is `Quote_Type__c != 'Renewal'`, so an RNM line on a Renewal quote → ARR=0 (no double-count).
- **MuleSoft payload:** unchanged — Mule keys on `Workday_Contract_Line_Type__c`, not Fortra_Product_Type.

**What breaks under B:** the stamped-fallback prehook path (one SOQL filter), the V14 entry-gate criterion, PCR Year-2, and `RenewalQuoteLineHandler` (must change together with the PCR or risk double-billing both RNM carryover AND any residual RRM). **Partner pricing** is the real residual: an RNM line carries 'New Maintenance', which would select `New_Maintenance_Percent__c` on a *renewal* unless partner logic also keys on quote type — must be checked.

**B-merge (collapse RNM+RRM into one product) — feasibility: viable but high-cost, NOT recommended.** Forces New and Renewal maintenance to share ONE partner margin rate across all 30 `Partner_Pricing_Model__c` rows (silent re-rating), requires re-targeting both Year-1 and Year-2 PCRs to one product, rewriting `RenewalQuoteLineHandler` to key on quote-type + QuoteAction.Type, and auditing every consumer of the distinct global-value-set values. **Prefer the rule-retarget form of B.**

**Feasibility: viable-with-caveats.** The biggest open caveat is step 3 — whether `initiateRenewal` can be forced to emit `'Renew'` (not `'No Change'`) for the maintenance asset.

## RECOMMENDATION — chosen path with concrete ordered steps

**Choose Option B in rule-retarget form. Renew the owned RNM asset as `Type='Renew'`; keep RNM as a distinct product; do not bootstrap RRM assets; do not merge.** Rationale: lowest blast radius (config + one Apex handler + one PCR + two label-filter widenings), no asset migration, no new schema, and it fixes renewal #1 for current customers (the thing Option A cannot do).

**The ONE decisive UAT proof to run FIRST (before any change):**
On a real RNM-owning account (e.g. DPP Test 1, or any of the 11 RNM-asset accounts), produce a renewal where the OWNED RNM asset's maintenance line carries `QuoteAction.Type='Renew'` (asset.Product2 = line.Product2 = RNM) and capture a **FINEST pricing log**. Confirm: (1) `ItemPricingSource='LastTransaction'` and `SalesTransactionActionType='Renew'` materialize, (2) Asset Discovery resolves the prior RNM asset as contributor by product, (3) `NetUnitPrice` flips to the Base_Price-derived COLA value (expect 67.38, identical to the beSECURE line behaviour), (4) the fossil asset Price does not leak into the committed net. This isolates "Renew vs No Change" as the sole lever, independent of any product swap. **If the renewal can be made to renew the RNM asset as 'Renew', Option B is confirmed buildable; if `initiateRenewal` cannot be coerced off 'No Change' for the maintenance asset, escalate — that is the single make-or-break dependency.**

**Ordered build steps (reversible-testable first):**

| # | Layer | Action | Reversible in UAT? | Decisive |
|---|---|---|---|---|
| 0 | Pre-flight | **Re-retrieve live**: confirm V14 is the sole Active procedure version; re-pull `COLAUpliftPrehook`/`COLAUpliftHandler`/`RenewalQuoteLineHandler` live (stack churns V9→V14 in days). | n/a | yes |
| 1 | Proof | Run the FINEST decisive proof above on a canary RNM-owning account. **GO/NO-GO gate.** | read-only | **YES** |
| 2 | Procedure | Widen V14 entry-step `DerivedPricing` crit 7 `Fortra_Product_Type__c` from `='Renewal Maintenance'` to `IN ('Renewal Maintenance','New Maintenance')`. Deactivate→deploy (api67, --metadata-dir)→reactivate; offline window. | yes (revert criterion) | gates RNM into COLA block |
| 3 | Apex | Widen `COLAUpliftPrehook.appendStampedRenewalMaintenanceUpdates` SOQL `Fortra_Product_Type__c IN ('Renewal Maintenance','New Maintenance')`. (Fallback only — primary asset path is what commits.) | yes (git revert + redeploy) | belt-and-suspenders |
| 4 | Apex | Invert/remove the carryover-delete in `RenewalQuoteLineHandler.cls` so the owned-RNM carryover survives. **Must ship together with #5.** | yes | structural |
| 5 | Config (PCR) | Disable Year-2 PCR `14OWC0000022Eyb2AE` (asset-less RRM AutoAdd). Setup UI only — PCR has no API/migration tooling. **Ship with #4.** | yes (re-enable) | structural |
| 6 | Flow / platform | Make `Fortra_Create_Renewal_Quote` / `initiateRenewal` renew the maintenance asset as `Type='Renew'` (the step-1 dependency). Owner: renewal/pricing flow owner (Nir/Marc). | depends | **make-or-break** |
| 7 | Regression | E2E: renewal → order → activate → Workday. Verify line type FIXED AMOUNT, billing dates non-perpetual, ARR=0 on renewal, partner band correct, DocGen PDF renders. Re-seat `COLAUpliftTest` (memory: 41-error architecture drift, prod-cutover blocker) before trusting coverage. | yes | confirms safety |
| 8 | Fossils | Remediate existing 60.64/54.58/$0 RRM Draft lines by **delete-and-re-add born-correct** (attaching a QA to a settled line + reprice is a proven false positive — COLACalculatedPrice moves but NetUnitPrice stays fossil). Forward-only; stage the 124-line backlog. | yes | cleanup |

Everything above is design-only. **Any DML/deploy (even validate-only) needs a fresh explicit UAT authorization** per the standing rule.

## What needs a business/product decision vs what we can build

**Build (engineering, no business decision):**
- Procedure entry-gate criterion widen (#2), prehook fallback SOQL widen (#3), `RenewalQuoteLineHandler` inversion (#4), PCR Year-2 disable (#5). All config/Apex/declarative, all reversible.
- The FINEST proof (#1) and E2E regression (#7).

**Needs a business / product-owner decision:**
1. **Renew-vs-No-Change platform behaviour (#6):** whether `initiateRenewal` can/should be driven to renew the maintenance asset as `'Renew'`. If platform won't yield, this becomes a flow/Apex design decision with owner sign-off (Nir/Marc). **This is the make-or-break.**
2. **Partner pricing band on renewals:** if the renewal line carries 'New Maintenance', does partner logic select `New_Maintenance_Percent__c` (wrong for a renewal) or does it key on quote type? Product owner must confirm intent — keep RNM distinct but ensure renewals use the **renewal** margin band, or accept the new-maint band. 30 models affected.
3. **Bookings/renewal reporting reclassification:** under B, renewal lines report as New Maintenance / RC_43000→RC_42000. Finance/RevOps must accept (or we add a quote-type-aware reporting layer).
4. **B vs B-merge:** confirm we do NOT collapse the products (recommended). A merge is a product-catalog decision with partner-pricing and DocGen impact.
5. **Catalog-wide rollout sequencing:** PIA BoKS is the pilot; rolling to the other ~1,710 maintenance pairs / ~202 PCRs is a migration program needing wave plan + owner approval.

## Open questions / next verification

1. **Can `initiateRenewal` emit `Type='Renew'` for the maintenance asset?** Today it emits `'No Change'` for maintenance but `'Renew'` for subscriptions (beSECURE). Determine whether this is driven by `renewAssetIds` membership, asset lifecycle/term state, or selling model. **Highest-priority verification — gates the entire fix.**
2. **Does the V14 `DerivedPricing` entry gate actually block RNM renewal lines today, or do they fall through another branch?** The probes confirmed the *commit* gate is product-agnostic but flagged the *entry* gate crit 6-7-8 references the literal label. Trace in the same FINEST proof.
3. **Partner pricing keying** — does `PartnerDiscountDerivedMaintenance19/20` / `StampPartnerUnitPriceDerivedMaintenance` select the band by `Fortra_Product_Type__c` alone, or also by quote type? Trace before committing to B.
4. **Approval-criteria flows** (`Maintenance_Discounts_Approval_Criteria` and the other 11+ flows referencing Fortra_Product_Type) — spot-check for a `='Renewal Maintenance'`-only branch that an RNM renewal line would now miss. Not traced in these probes.
5. **Reporting/CRMA datasets** segmenting by `Fortra_Product_Type__c='Renewal Maintenance'` / `RC_43000` — inventory before cutover (out of probe scope; transactional flows confirmed safe).
6. **`COLAUpliftTest` re-seat** — 41-error architecture drift (test = list-passing API vs live ctxInstanceId) is a prod-cutover blocker independent of this fix; coverage can't be trusted until reseated. Coordinate with SC-3346 test-suite remediation.
7. **Version drift discipline** — the COLA stack moved V9→V14 in days; re-pull live (procedure + 3 Apex classes + PCRs) immediately before any deploy. Repo carries stale/inactive copies (the Autolaunched Workday flow is inactive/Draft; V8/V9 line-type variants are NOT live).

**Key evidence files:** `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/sc3346_fix/rn_partner_dd/V14_ACTIVE_block.json` (procedure), `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/rca_deep/arch/work/A3-optionB-renew-owned/live_classes/unpackaged/classes/COLAUpliftPrehook.cls`, `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/rca_deep/arch/work/A4-cola-gate-downstream/live_flows/unpackaged/flows/Fortra_OrderItem_Set_Workday_Contract_Line_Type.flow`, `/Users/liamjeong/Documents/Code/Fortra/Data/sc-maint/rca_deep/arch/work/A1-blast-radius/renewal_flow/unpackaged/flows/Fortra_Create_Renewal_Quote.flow`.