# MDT-RECORDS — Fix Spec / Resolution

**Status:** DEFECT-B ✅ RESOLVED in UAT 2026-06-13/14 (deployed). DEFECT-A = business-gated (latent).
**Org:** FortraUAT · Domain: Config & data integrity (SC-3346 maintenance pricing CMDTs).

## Core data (re-verified live, correct)
- `Maintenance_Rate__mdt` = 7 tiers exact (Basic 0.15, Professional 0.20, Standard 0.20, Premium 0.24, Express 0.30, Premier 0.30, Expert 0.35).
- `COLA_Uplift_Rules__mdt` = 22→**21** rows after fix, all `Is_Active__c=true`, all uplift match D4 (zero drift). `Solution_Category__c` is **unique-constrained**.
- COLA lookup (`COLAUpliftHandler.getCOLARulesMap`): keys on `Product2.Solution_Category__c` text → `COLA_Uplift_Rules__mdt.Solution_Category__c`, `Is_Active__c=true` + effective-date filtered.
- "Maintenance_Type_Defn" is the **MTD AttributeDefinition** (`0tjWC000000096bYAA`, picklist), NOT a CMDT — naming, not a defect.

## DEFECT-B — TEMP/duplicate BoKS COLA row → ✅ RESOLVED (value-neutral)
Two BoKS rows existed (different category text → distinct unique keys, both 7.85):
- `TEMP_BoKS_IAM_ProductCat` — category "Powertech Identity & Access Manager (BoKS)" → **17 live products** match. Load-bearing. Its own Description said *"TEMP UAT-only … DELETE before go-live."*
- `Powertech_IAM_BoKS` — category "Powertech IAM BoKS" → **0 products** (dead; the original intended row whose text never matched).

**Fix deployed** (`Data/sc-maint/sc3346_fix/cola_fix/`, pre-destructive, api 67):
1. Updated `Powertech_IAM_BoKS.Solution_Category__c` → "Powertech Identity & Access Manager (BoKS)" (+ Description aligned).
2. Deleted `TEMP_BoKS_IAM_ProductCat` (destructiveChangesPre — must precede the update because of the unique constraint).

**Verified:** COLA rows 22→21; one clean `Powertech_IAM_BoKS` row carrying the live category, 7.85, active; TEMP_ gone; anonymous-Apex replication of `getCOLARulesMap` → map size 21, BoKS resolves **7.85**. No pricing change.

## DEFECT-A — platinum orphan → BUSINESS-GATED (latent, not active mispricing)
The MTD picklist has 8 values; `platinum` (lowercase) has no `Maintenance_Rate__mdt` row → V14 formula ELSE=0.
- **Profile:** 18 live `platinum` QLI-attribute rows, all on **2 EFT-WSM products** (`GS-GSE-RRM-EFWO` ×13, `GS-GSE-RRM-EFSMB` ×5), all **Renewal Maintenance**, all on Approved quotes.
- Renewal maintenance prices via **COLA carry-forward** (`DerivedPricingRenewals`), NOT the tier formula → **these 18 lines are not mis-priced by the tier gap**. platinum is a **latent** trap (only a *new*-maintenance EFT-WSM platinum line would hit $0; none exist today).
- **Resolution needs business:** define the EFT-WSM "platinum" maintenance rate (then add a `Maintenance_Rate__mdt` row + the V14 formula branch), OR confirm it's a misconfig to remap to an existing tier (then retire the picklist value). Same item flagged in [NB_DERIVED_TIER_FIX_SPEC.md](NB_DERIVED_TIER_FIX_SPEC.md); the V14 formula already returns 0 safely until then. Do NOT guess the rate.
