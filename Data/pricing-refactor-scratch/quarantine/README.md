# Quarantine

## scratch_v210.xml  (moved from repo root 2026-07-06)
A **V20-lineage hybrid** snapshot of the V21 ESD block — NOT the deployable/authoritative V21.
It still contains the retired partner-percent trio (`Partner Percent Procedure Audit` / `Partner Percent
Resolved Filter` / `Resolve Partner Discount Percent`) and lacks `Reset Amount Base From List` — so deploying
it would re-introduce those removed ESD steps and drop a guard (a regression). See PRICING_REFACTOR_PLAN.md INV-20 / VR-12.

Authoritative V21 = the org's active version (mirrored read-only at
`Data/pricing-refactor-scratch/live-esd/ACTIVE_V21_block.xml`), editable only via the canvas in-place.
Kept here (not deleted) for history; do NOT deploy it.
