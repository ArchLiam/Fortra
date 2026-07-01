# V16 → V20 Pricing-Procedure Reconciliation (COLA pricing not working)

**Date:** 2026-06-29  **Proc:** `Rev_Mgmt_Default_Pricing_Procedure` (ExpressionSetId `9QLWC0000015cDl4AI`)
**Trigger:** Slack — Nir: "COLA Pricing is not working… everything from V16 has been moved to V20." Cross-check requested.

## Version state (live FortraUAT, retrieved fresh)
| Ver | Status | Created | By | Last Modified | By |
|-----|--------|---------|----|--------------|----|
| **V16** | **Inactive** | 06-21 | Nir Kailash | **06-29 15:09 UTC** | Nir Kailash |
| **V20** | **Active** | **Fri 06-26** | Nir Kailash | 06-29 16:32 UTC | Liam Jeong |

V20 is the live version. It was branched Friday and is **missing post-branch V16 work**. Nir's claim that "everything from V16 is in V20" is **incorrect** — 5 concrete gaps below.

## What V20 is MISSING vs V16 (must port)

### 1. Term-Defined line-level proration sub-tree — **THE COLA BREAKAGE** (3 steps)
Entirely absent from V20. V20 keeps only the parallel *Evergreen* proration sub-tree.
```
Term-Defined proration filter (Line level)   [ListGroup]  name=TermDefinedProrationFilterLinelevel
├── List Operation (AdvancedListFilter)       name=ListOperationTermDefinedPTC
│     filter: SellingModelType = 'TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull
└── Proration (BusinessKnowledgeModel)         actionType=Proration
      ProrationPeriod=PricingTermUnit, SubscriptionTerm=ItemSubscriptionTerm, EffectiveFrom/To
```
**Impact:** COLA renewals are `TermDefined` (fixed annual term + uplift). With this sub-tree gone, TermDefined/renewal lines never get **term-prorated** and **PricingTermCount (PTC)** is never stamped → net amount = full/un-prorated value, PTC null. Matches the known SC-3420 / SC-3411 PTC defect class. Child name literally `…TermDefinedPTC`.
→ Raw XML saved to `missing_term_proration_subtree.xml` (port this into V20).

### 2. Derived Pricing Formula tier regression (1 matched step, name=DerivedPricingFormula)
`formula-section-0-input` differs:
- **V16 (7 tiers):** Expert 0.35, Premier 0.30, Express 0.30, Premium 0.24, Standard 0.20, Professional 0.20, Basic 0.15
- **V20 (3 tiers):** Premier 0.30, Standard 0.20, Professional 0.20 (omits Expert/Express/Premium/Basic → those fall to 0)
- Renewal branch `IF QuoteTypeText__c='Renewal' → NetUnitPrice` identical in both.
**Impact:** new-business derived-maintenance lines on the 4 missing tiers price to $0. (Per [[project_nb_derived_tier_fix]] the 7-tier form is the correct one; this is a known clobber/oscillation on the co-owned formula.)

### 3 & 4. Lost null-guards on aggregate steps
`SoftwareAggregatePrice` and `SubscriptionAggregatePrice`: V16 has where-condition `ItemNetTotalPrice IsNotNull` (where-condition-count=1); V20 has count=0, no guard. Without the guard, null line totals can poison the SUM aggregate.

## What V20 ADDED vs V16 (Nir's currency work — KEEP)
10 new steps: 6 × `Attribute Value Pricing - {Calculated|Total Price|Unit Price} Mode {Base|Net} Bridge` + 4 × `Currency Conversion - {Net Unit Price|Unit Price Display|Net Total / Subtotal|Total Line Amount}` (end-of-line USD→currency conversion).

## Confirmed identical
`<variables>` (21/21). advancedCondition 32 (V16) vs 31 (V20) — the single missing one = the Term-Defined filter condition above.

## Action
Port items 1–4 from V16 into V20 (currency steps stay). Item 1 is the COLA fix. Then re-validate COLA on a TermDefined renewal before leaving V20 active.
