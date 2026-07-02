# H1-selling-model-mix — DIFFERENTIAL LENS findings (read-only, FortraUAT)

## Re-derivation (independent of Mission E)
Query: SELECT QuoteLineGroupId, ProductSellingModel.SellingModelType FROM QuoteLineItem WHERE QuoteLineGroupId != null
-> 54 grouped lines, 33 distinct groups with members (Mission E only saw 22 lines = stale/HW-filtered snapshot).

## FIVE mixed OneTime+TermDefined groups exist org-wide (NOT one):
- 1C9WC0000003eNV0AY "Hardware Test"   quote 0Q0WC0000026Egf0AE  HWtype=False Draft    survivors=0
- 1C9WC00000090SD0AY "HW-1"            quote 0Q0WC0000035N0f0AE  HWtype=False Ordered  survivors=2
- 1C9WC00000091xl0AA "Secure Email"    quote 0Q0WC0000037Zc10AE  HWtype=False Accepted survivors=0
- 1C9WC00000092Ij0AI "Hardware Group 1"quote 0Q0WC0000037vXh0AI  HWtype=False Draft    survivors=0
- 1C9WC00000097of0AA "Test HW1"        quote 0Q0WC000002U2020AC  HWtype=True  Accepted survivors=2  <== FAILING

## H1's claimed "structurally distinct OneTime line" is UNIVERSAL, not unique:
- Every OneTime line in every mixed group uses the SAME PSM 0jPWC00000005yz2AA, PricingTerm=null, PricingTermCount=0, ConfigureDuringSale=Allowed.
- OneTime PSM 0jPWC00000005yz2AA has 3,939 PSMOs, ALL with ProrationPolicyId=null (the "null proration" asymmetry H1 cites is org-wide, not group-specific).

## Real discriminators (which H1 does NOT name):
1. Hardware_Group_Type__c=True: failing group is the ONLY HW-type group among the 5 mixed groups (24 other HW-type groups are single-SM).
2. net>>list markup (~10x, 29060 vs 2850): ONLY the failing group has it among the 5 mixed groups.
3. Survivor-reprice path: among 25 HW-type group quotes, only the failing quote (and one Denied quote whose grouped line is actually in a non-HW group) has ungrouped survivors; the other 23 are all-grouped (delete = empty quote, no survivor reprice).

## Counter-examples
- 90SD0AY: SM-mix + 2 ungrouped survivors (the full reprice path) but HWtype=False, no markup. Untestable only due to Ordered status. Near-miss the SM-mix mechanism cannot distinguish away.
- 91xl0AA "Secure Email": Accepted+USD+4-line+SM-mix (same coarse profile as failing) but HWtype=False, no markup, no survivors.

## Verdict: REFINED toward REFUTED of the *named mechanism*.
SM-mix is necessary-but-NOT-sufficient and is confounded with HW-type + markup + survivor-reprice. H1 names the wrong primary key (selling-model) when the surviving discriminator is HW-type/markup.
