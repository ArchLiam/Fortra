# Orchestrator independent cross-checks (2026-07-06, main-loop verification)

Verified first-hand to cross-check the lanes. Cite alongside lane findings.

## OX-1 — Partner V2 flip is PARTIAL (prehook V2 / posthook V1-service split) — CONFIRMED
- Live `PartnerPricingPrehookV2` (seq-3, runtime) calls **`PartnerPricingServiceV2`**: `getPricingModelCandidates` (live-classes/PartnerPricingPrehookV2.cls:384), `selectBestModelForLine` (:708,:735), `getMarginForProductType` (:715,:742), `calculateDiscountPrice` (:720), `calculateGuaranteedMarginPrice` (:760).
- Dead `PartnerPricingPrehook` (V1) calls **`PartnerPricingService`**: `getPricingModels` (PartnerPricingPrehook.cls:390), `resolveProductType` (:632), `resolveTotalPartnerPercent` (:693), `buildPartnerMarginDetailJson` (:777).
- **`PartnerNetPricePosthook` (seq-11, LIVE) STILL calls V1 `PartnerPricingService`**: `getPricingModels` (PartnerNetPricePosthook.cls:146,:1480), `ensureProductTypesLoaded` (:159), `resolveProductType` (:319,:545,:1112), `getMarginForProductType` (:569,:581), `calculateDiscountPrice` (:574), `calculateGuaranteedMarginPrice` (:591).
- => **Both `PartnerPricingService` (V1) and `PartnerPricingServiceV2` run in the SAME reprice** — V2 in the prehook, V1 in the posthook. The flip did not retire V1's service; it created a prehook/posthook margin-logic split. Divergence risk = internally-inconsistent partner net. **This is a NEW debt item the flip introduced (2026-07-01).**

## OX-2 — E-04 is now a LIVE DATA RISK, not a pre-flip blocker — CONFIRMED
- `PartnerPricingServiceV2.getMarginForProductType` (live-classes/PartnerPricingServiceV2.cls:114) returns `0` when model null (:120) and default `0` (:152); null-guards each `Non_Orig_*_Pct__c` with `!= null ? x : 0` (:128–:148).
- Since V2 is now the runtime prehook, **unpopulated `Non_Orig_*_Pct__c` on `Partner_Pricing_Model__c` silently yields 0% partner margin** (list price stands). Prior docs said "V2 flip blocked by E-04"; reality = flip happened, E-04 is a latent data-completeness risk. OPEN QUESTION owner: Partner Pricing data owner (Marc DeBrey / Sales Ops) — is `Non_Orig_*` populated in UAT & prod?

## OX-3 — Posthook recursion guard IS safe (has finally) — CONFIRMED
- `PartnerNetPricePosthook`: `private static Boolean isProcessing = false` (:32), checked (:58), set true (:65), reset false in `finally` (:81–:82). This hook is NOT a stuck-guard risk. (Lane 1 to confirm the others.)

## OX-4 — Design-doc vs LIVE wiring divergences (design docs are STALE; live is authoritative)
From FORTRA_SOLUTION_DESIGN_KNOWLEDGE_BASE.md §3:
- **RegionalServicesPricingPosthook** (doc §Regional: "writes regional price to NetUnitPrice as last-writer after the procedure; chains to PartnerPricingPosthook via Type.forName()") is **NOT in the live ProcedurePlanOption wiring** (only PartnerNetPricePosthook + CancelLineCreditPosthook are posthooks). Its function appears absorbed into `PartnerNetPricePosthook`. CORRECTED vs design doc.
- **COLA ordering**: COLA doc claims "COLA applied BEFORE Regional Pricing; compound Final=(Asset.Price×(1+COLA%))×Regional Mult." LIVE prehook order = Regional seq-2 BEFORE COLA seq-6. The contradiction resolves via the COLA **dual path**: `COLAUpliftHandler` (before-insert/update trigger) applies COLA at DML time (before any reprice prehook), while `COLAUpliftPrehook` runs seq-6 (after Regional). Effective COLA timing is split across two surfaces => the dual-path divergence cluster (SC-3350 churn).
- **Design-doc section numbers are stale**: AttributeVolume doc says "Section 3 (after Regional §1, Partner §2, before Procedure §4)" — omits Hardware (live seq-1) and COLA (live seq-6). Live seq = Hardware1/Regional2/Partner3/AttrVol4/COLA6/ESD10/PartnerNetPost11/QLDesc12/CancelPost13. Verify order from plan records, not prose.

## OX-5 — SourceListPrice* no-op EXPLAINED by design decision — CONFIRMED intent
- Maintenance-Derived doc §: "No custom Apex prehook — a prehook was empirically abandoned because for IsDerived lines the native derived-pricing element owns Net Unit Price and discards prehook writes." => `SourceListPricePrehook`/`SourceListPriceResolver` are the abandoned prehook, superseded by `Stamp_Source_List_Price` flow + ESD "Derived Pricing Formula" (Formula Based Pricing, List Container 9). Delete-or-quarantine is design-sanctioned.

## OX-6 — 3-tier hardcoded derived formula = regression #4 surface, live-confirmed
- Active V21 `<description>`: "Derived Pricing Formula reverted to 3-tier."
- Maintenance-Derived doc §: formula `IF(tier='Premier',0.30,IF('Standard',0.20,IF('Professional',0.20,<fallback>)))×Source_List_Price__c` — 3 tiers hardcoded INLINE in the ESD Formula-Based-Pricing element, though the doc says rates "in Maintenance_Rate custom metadata." Straggler tiers (Premium×2, Expert×1, platinum×1) hit the fallback → $0 trap. Matches memory nb-derived-tier-fix / mdt-records-fix (orphan platinum). Inline-constant anti-pattern (Priority A) + engine-only field with no Apex backstop.
