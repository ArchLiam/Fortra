# Pricing Procedure Lane — Amend net=0 forensics (2026-06-29)

ACTIVE PROC: ExpressionSet "Revenue Management Default Pricing Procedure"
  Id 9QLWC0000015cDl4AI, ApiName Rev_Mgmt_Default_Pricing_Procedure, UsageType=DefaultPricing
ACTIVE VERSION: V20  (ESV 9QMWC00000024yn4AA, DefVer 9QBWC0000000oG94AI)
  IsActive=true, status=Active, label "Rev Mgmt Default Pricing V20"
  Created 2026-06-26T21:21 by Nir Kailash; LastModified 2026-06-29T16:32 (in-place edited TODAY)
  Description: "...USD pricing with end-of-line currency conversion (Inactive until UAT)"  <-- label lies; it IS active

VERSION TIMELINE (regression boundary Jun23 good -> Jun27 broken):
  V16 created Jun21 (Nir) — last-good era base
  V17 Jun23 01:01 (Liam)
  V18 Jun25 04:15 (Liam) — has SC-3441 CancelNetUnitPrice__c branch
  V19 Jun26 17:28 (Liam) — has SC-3441 branch
  V20 Jun26 21:21 (Nir) ACTIVE — forked off V16, ADDED currency conv, DROPPED SC-3441 branch

AMEND-LINE DATAFLOW IN V20 (ItemPricingSource='LastTransaction', action='Amend'):
  - PricingSetting (seq1) seeds NetUnitPrice/ItemNetTotalPrice from INPUT/CONTEXT
  - ALL base/list/attr/qty/sync/stamp steps gated `ItemPricingSource NotEquals 'LastTransaction'` -> SKIP amend lines
  - COLA branch gated `SalesTransactionActionType Equals 'Renew'` -> SKIP for Amend (only Renew)
  - ONLY amend pricing step: ListContainer79/FormulaBasedPricing -> ItemNetTotalPrice = NetUnitPrice * Qty (CONSUMES NetUnitPrice, never sets it)
  - CurrencyConversion* (unconditional, end of line): multiplies by rate (CAD 1.3889, USD 1.0) — cannot create 0 from nonzero
  - Tail TotalAmount/AggregatePrice aggregate
  => Proc NEVER derives a base price for Amend lines. It passes through whatever NetUnitPrice arrives at PricingSetting.
  => This pass-through structure is IDENTICAL in V16/V18/V19/V20. If NetUnitPrice arrives 0 -> line is 0, no recovery.

CONCLUSION: The pricing procedure (V20) is NOT the zeroing mechanism. Its amend branch is a faithful pass-through,
unchanged in semantics from the last-good V16. The zero originates UPSTREAM of the proc — whatever supplies
NetUnitPrice for LastTransaction (amend) lines (input mapping / context / asset price seed / "Stamp Maintenance
Pricing Inputs" flow / Create Amendment Quote flow). New Sale works because New Sale lines run the full base-price
stack (PriceBookEntries/AttributeBasedPrice/etc.), which is NEVER reached by amend lines.

V20 DIFFS vs V16 (none affect amend pass-through):
  + 4 CurrencyConversion steps (unconditional ×rate, end-of-line) — currency-blind to amend vs new
  + 6 AttributeValuePricing*Bridge steps (inside ListContainer5/6/720, attr-priced new-sale path; ref Base_Price__c which is NULL)
  + DerivedPricingFormula tier table trimmed (Expert/Premium/Basic tiers dropped)
  - StampBaseFilter lost `NetUnitPrice IsNull` null-safe clause (affects new-sale derived stamping, NOT amend)
  - TermDefinedProration block removed (SC-3420 PTC null; not net=0)
  - SC-3441 CancelNetUnitPrice__c branch DROPPED (V20 forked off V16, not V18/V19)
