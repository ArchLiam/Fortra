# ZERO-LIST-PBE re-test 2026-06-14 (live FortraUAT)

## Verdict: FAIL (unchanged), severity HIGH, fixability uat-fixable (data backfill; partly done this session)

## What changed vs prior verdict
- PBEDP rows 176 -> 201 (+25, marker Legacy_Rule_Id__c='SC3372BACKFILL', all Formula=UnitPrice / Scope=Both / Source=Product)
- Distinct PBEs covered 174 -> 199 (+25); uncovered derived PBEs 3279 -> 3254
- Fortra Price Book (real transacting book): 172 -> 197 covered / 1717 -> 1692 uncovered (~89.6%)
- Backfill scope = FIM family ONLY (CCM*, Tripwire Log Center, File Integrity Manager, Device Profiler, IP360), both New & Renewal Maintenance

## What did NOT change (still failing)
- Derived PBEs: 3453 total, 3453 zero-list (UnitPrice=0), 0 nonzero -- 100% zero-list by design (unchanged)
- Canonical repro 00780964 / 0Q0WC000003735t0AA (Draft, BoKS): re-repriced live (Place ST + Skip, isSuccess:true, lines 2->2, LastMod advanced 2026-06-14T05:01:42).
  New-Maint line 0QLWC000003cFh44AE STILL NetUnitPrice=0 / UnitPrice=0 / ListPrice=0, Base_Price__c=355, Source_List_Price__c=NULL. Expected 0.20x355=71, actual 0.
  Its maint PBE 01uWC000004dT3QYAU = BoKS, NOT in the FIM backfill, 0 PBEDP rows.
- Draft New-Maintenance prevalence: 14 zero-net / 17 nonzero; of 14 zero-net: 12 null Source_List_Price__c, 1 positive-source -- IDENTICAL to prior
- CCMLSE gate product 01tWC00000DD16HYAT: Fortra-PB PBE covered, Standard-PB PBE 01uWC000005q7HbYAI STILL uncovered (duplicate-uncovered pattern persists off-book)
- Inconsistency control holds: same product on 0Q0WC000002ssK10AI prices 71 (ListPrice 0, Source_List null) -> $0-list PBE itself does not block pricing; stamping/derivation layer is the variable
- 1 true persistence-wall case 0QLWC000003broQ4AQ (CCMLSE NewMaint, UnitPrice=2008, Source_List 2008, NetUnitPrice=0, NO MTD tier attr); its PBE 01uWC000005wsyeYAA IS covered yet still $0 -> NB-DERIVED-TIER untiered-else-0, not a coverage miss. Could not reprice 00780927 (FIELD_CUSTOM_VALIDATION: Bill To Place not related to Account -- quote-data, out of scope).

## Root cause (two-layer, matches prior)
1. Every derived maintenance PBE is zero-list by design -> net depends entirely on derived layer.
2. Dominant: null Source_List_Price__c on the new-business line -> DerivedPricingFormula (tier x Source_List_Price__c) has no input -> $0.
   Secondary: SC-3372 native "contributing products are missing" gate when PBEDP missing (FIM cohort now backfilled).

## Fixability
uat-fixable: PBEDP backfill (data, no republish) demonstrably works in UAT (25 done this session). REMAINING uat-fixable work:
- ~163 non-FIM in-use derived PBEs need a business crosswalk before backfill (per FIX-STATE)
- 4 zero-list contributor licenses need a list-price fix
- the dominant null Source_List_Price__c stamping gap (Stamp_Source_List_Price coverage on new-business lines) is the real lever for the canonical $0 repro -- not addressed by PBEDP backfill
