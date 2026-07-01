# K-07 Smoke Test Result (FortraUAT, active Rev_Mgmt_Default_Pricing_Procedure V21)
Date: 2026-06-29
Quote: 0Q0WC000003FZVB0A4 (Q-K07 DERIVED 3TIER REGRESSION)

## Active version: V21 (single Active), description = "V20 (COLA proration+guards+currency) with Derived Pricing Formula reverted to 3-tier. DRAFT."

## Three K-07 deltas verified end-to-end vs LIVE runtime:
1. TermDefined proration sub-tree: PRESENT in metadata (2 Proration actionTypes, ProrationTermDefined writer, StartProrationPeriod/ItemSubscriptionTerm guards). Runtime: SC-3473 Abstract line 0QLWC000003jN8P4AU PTC=1 EndDate=2027-06-25 (was null/null pre-fix).
2. Derived 7-tier reduction: METADATA serializes only 3 tiers (Premier .30 / Standard .20 / Professional .20; Basic/Premium/Express/Expert -> ,0 fallback). RUNTIME prices ALL 7 tiers correctly:
   - Basic 0.15  -> NetUnitPrice 53.25  (0.15 x 355)
   - Standard 0.20 -> 71      (0.20 x 355)
   - Expert 0.35 -> 124.25    (0.35 x 355)
   - Premium 0.24 -> 85.20    (0.24 x 355)
   => METADATA/RUNTIME DIVERGENCE: deployed V21 says 3-tier, engine executes 7-tier.
3. Guards: present (13 StartProrationPeriod, 3 ItemSubscriptionTerm); PB-null TermDefined lines skip clean.

## Verdict: PASS (runtime correct end-to-end; no live mispricing) with a DURABILITY/GOVERNANCE finding:
the active V21 serialized metadata (3-tier, "DRAFT") does NOT match the 7-tier compiled runtime -> exactly the co-owned clobber/re-apply ping-pong K-07 warns about. Any future republish from the V21 metadata snapshot WOULD ship the 3-tier regression (Basic/Premium/Express/Expert -> $0). 1,031+ historical org rows on dropped tiers (per prior tally) are the exposure if that happens.
