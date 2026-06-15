# SC-3346 NB-DERIVED-FORMULA (M-2) — Resolution (2026-06-14, FortraUAT)

## Verdict: functionally NOT a defect. The live formula is correct; the competing formula is provably inert
## dead code. Functionally PASS; the only open item is the COSMETIC removal of the dead element (procedure
## edit, owner/user-gated, best bundled with the eventual SC-3404 V15 cutover — NOT worth a risky standalone in-place edit).

## The live new-business derived formula (correct, SDD-canonical)
`DerivedPricingFormula` (V14, ListContainer9, FormulaBasedPricing → NetUnitPrice, gated by AttributeDefinitionCode='MTD'):
```
IF(AttributeValue='Premier',0.30, IF('Standard',0.20, IF('Professional',0.20, 0))) * Source_List_Price__c
```
**Proven empirically** (not just by reading): line `0QLWC000003cL1i4AE` (EFT 8 NewMaintenance) — MTD tier=Premier(0.30),
`Source_List_Price__c=10000`, **`Base_Price__c=0`**, committed `NetUnitPrice=3000` = 0.30×10000. Because Base_Price__c=0,
a Base×tier formula would have produced **$0** — the actual 3000 rules it out and proves `Source_List_Price__c` is the input.
(Corroborated: broR4 Source 2008→462; cGRp Source 355→62.48=71×0.88 partner.)

## The competing formula is TRIPLY-inert dead code
`DerivedPricingNewBusiness` (V14, ListContainer, FormulaBasedPricing, v14block.xml L1970-2034):
```
IF(QuoteTypeText__c='Renewal', NetUnitPrice, Base_Price__c * tier)   -> output NetUnitPrice
```
It cannot affect any committed price, for **three independent reasons**:
1. **Base×tier arm is unreachable.** Its container gate `DerivedPricing` = `(1 AND 2 AND 3) OR (4 AND 5) OR (6 AND 7 AND 8)`:
   - Branch A `(1 AND 2 AND 3)` requires `AttributeDefinitionCode='MDT'` — **MDT does not exist** (live AttributeDefinition: only `MTD`/Maintenance_Type_Defn). Permanently false.
   - Branch B `(4 AND 5)` and Branch C `(6 AND 7 AND 8)` both require `QuoteTypeText__c='Renewal'`.
   - So every admitted line is a **Renewal** — but the Base×tier arm only fires for **non**-Renewal lines. They never co-occur.
2. **No-op for the renewal lines it does admit** — the formula returns `NetUnitPrice` (the first IF arm) for them.
3. **`resultIncluded=false`** (L2028) — even that no-op output is discarded by the engine.

Confirmed live: `SELECT Code FROM AttributeDefinition WHERE Code IN ('MTD','MDT')` → only `MTD`. Active version =
ExpressionSetVersion `9QMWC00000023eX4AQ` V14 (sole active).

## Out-of-scope (a DIFFERENT defect, not formula-choice)
Canonical NB quote 00780964 maint line `0QLWC000003cFh44AE` prices $0 because it is `ItemIsDerived__std=false`
with `Source_List_Price__c=null`, `Base_Price__c=355` (license-list leak) — the derived branch never fires on it.
That is an **auto-add line-stamping** defect (the maintenance SKU wasn't stamped derived / wasn't given the
license list price), not a formula-choice issue. Belongs to the auto-add/CFG-AUTOADD scenario.

## STATUS 2026-06-14: dead element REMOVED from V14 (deployed, pending reactivation)
User deactivated V14 and authorized the edit. Removed the `DerivedPricingNewBusiness` `<steps>` block from the
V14 block of `Rev_Mgmt_Default_Pricing_Procedure` and renumbered `ListContainer` to stay contiguous
(DerivedPricingRenewals 3→2, DerivedPricingValuesAssignment 4→3). Deployed via metadata API (NoTestRun; the
`metadata.transfer:Finalizing` error is the cosmetic CLI bug — deploy succeeded). **Verified by re-retrieve:**
DerivedPricingNewBusiness 6→5 (only V14's removed), V14 ListContainer seqs = 1/2/3, line count 75412→75347,
diff = exactly the −65 block + 2 seq renumbers, XML valid. V14 remains inactive.
**REMAINING (user-gated): reactivate V14 + re-sync the scale cache, then a confirmation reprice.** Functionally
a no-op (the removed element was triply-inert), so post-reactivation pricing should be byte-identical.
Pristine rollback snapshot: `pristine_v14edit/`. Edited source: `retrieve_v14edit/`.

## Recommendation
- **Functional resolution: PASS.** The correct formula computes the net; the dead formula is provably incapable
  of changing any price. There is no pricing risk today.
- **Cosmetic removal (optional):** deleting the `DerivedPricingNewBusiness` step is a V14 ExpressionSetDefinition
  edit. Per this session's experience, ANY procedure operation is scale-cache-fragile: an in-place edit requires
  deactivate-V14 → deploy → reactivate-V14 → re-sync, the deactivation window takes UAT pricing down, and
  reactivation is user-gated. For **zero functional benefit**, doing this as a standalone in-place edit is poor
  risk/reward. **Recommend deferring the removal to the SC-3404 V15 cutover** (when the procedure is already being
  reworked for a real reason), exactly as the original M-2 finding/memory advise.
- The edit, when done: remove the single `<steps>…</steps>` block whose `<name>DerivedPricingNewBusiness</name>`
  (v14block.xml L1970-2034). Leave `DerivedPricingFormula` (live) and `DerivedPricingRenewals` (B-4) untouched.
