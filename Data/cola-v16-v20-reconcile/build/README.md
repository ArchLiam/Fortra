# Draft V21 — V20 currency + restored V16 logic

**Built:** 2026-06-29 (local, NOT deployed)
**File:** `expressionSetDefinitionVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V210.expressionSetDefinitionVersion`
**Header:** label `Rev Mgmt Default Pricing V21`, `status=Inactive`, `versionNumber=21`
**Base:** live V20 (retrieved 2026-06-29) — Nir's currency version, kept verbatim.

## What was merged in (the 4 V16 deltas V20 was missing)
1. **Term-Defined proration sub-tree** (3 steps, deep-copied from V16) — the COLA fix:
   `TermDefinedProrationFilterLinelevel` (ListGroup) → `ListOperationTermDefinedPTC` (filter: `SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull`) + `ProrationTermDefined` (Proration BKM, outputs ProrationMultiplier→PricingTermCount).
2. **DerivedPricingFormula** → restored V16 7-tier table (Expert/Premier/Express/Premium/Standard/Professional/Basic) over V20's 3-tier.
3. **SoftwareAggregatePrice** → restored `ItemNetTotalPrice IsNotNull` guard (where-condition-count 1).
4. **SubscriptionAggregatePrice** → restored same guard.

## What was KEPT from V20 (Nir's currency work, untouched)
6 × `Attribute Value Pricing - … Mode … Bridge` + 4 × `Currency Conversion - …` (end-of-line USD→currency).

## What was deliberately NOT changed
`Assignment92`/`SubscriptionPricing89` flagged by one verifier were **name-renumber false positives** — matched by function, all those assignment/subscription-pricing behaviors exist in both V16 and V20. No edit needed.

## Acceptance tests (both pass)
- **V21 vs V20** = exactly the 4 patches above (nothing lost from V20).
- **V21 vs V16** = MATCHED-BUT-CHANGED **0**; the only difference is the +10 currency steps. → V21's pricing logic is byte-identical to V16.

Result: 122 steps (V20's 119 + 3), 21 variables (unchanged).

## NOT YET DEPLOYED
Deploy requires explicit go-ahead. Open question for deploy: creating a brand-new version (21) via MDAPI may need the version cloned in the RLM UI first (clone V20 → V21), then deploy this file into that member. Activation is UI-only. Re-retrieve V20 immediately before deploy — it is co-owned and was edited by both Nir and Liam within the hour today.
