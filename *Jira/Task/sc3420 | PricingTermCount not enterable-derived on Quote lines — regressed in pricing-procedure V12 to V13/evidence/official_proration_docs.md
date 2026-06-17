# Evidence — official Salesforce Proration documentation (design validation)

The Fortra `Rev_Mgmt_Default_Pricing_Procedure` follows Salesforce's standard Revenue Cloud
"Subscription Pricing with Proration" design for deriving `PricingTermCount`. The deleted V11
TermDefined step matches this design verbatim.

## Salesforce Trailhead — "Implement Subscription Pricing and Proration Strategies" → *Set Up Subscription Pricing with Proration*

Key statements (fetched 2026-06-16):

- **The Proration element outputs the *Proration Multiplier*** — "a value that indicates the
  number of pricing periods included in an order product's term."
- **Formula:** `Proration Multiplier = Actual Subscription Duration / Product's Standard Subscription Term`.
- **Required input context mappings:** `EffectiveFrom`, `EffectiveTo`, `PricingTermUnit`
  (months or days), `ItemSubscriptionTerm` (product's standard term), `StartProrationPeriod` /
  `StartProrationPeriodDay` / `StartProrationPeriodMonth`, `AllowPartialProrationPeriods`,
  `SellingModelType`.
- **Output mapping — the decisive line:** *"map the variable to this context tag:
  **Proration Multiplier → `PricingTermCount`**."*
- The output is then consumed by downstream Subscription Pricing elements to adjust price for the
  actual service duration.

## Cross-check against the deleted Fortra step (V11)

| Salesforce-documented Proration element | Fortra V11 `Proration` step (TermDefined) |
|---|---|
| Output: Proration Multiplier → `PricingTermCount` | output `ProrationMultiplier` (output=true) → `PricingTermCount` ✅ |
| Input: EffectiveFrom / EffectiveTo | `EffectiveFrom` / `EffectiveTo` ✅ |
| Input: PricingTermUnit | `ProrationPeriod = PricingTermUnit`, `SubscriptionTermUnit = PricingTermUnit` ✅ |
| Input: ItemSubscriptionTerm | `SubscriptionTerm = ItemSubscriptionTerm` ✅ |
| Input: AllowPartialProrationPeriods | `AllowPartialProrationPeriods` ✅ |
| Gated by selling model | parent filter `SellingModelType = 'TermDefined'` ✅ |

**Conclusion:** Fortra implemented the standard pattern correctly through V11. The V12 rebuild
removed the TermDefined instance of this standard element. Re-adding it (per §6 of the README) is
a return to Salesforce's documented design, not a custom invention. For a 1-year line on an annual
selling model, Proration Multiplier = 1 ⇒ `PricingTermCount = 1` (matching the value observed on
pre-regression working lines).

## Sources

- [Trailhead — Implement Subscription Pricing and Proration Strategies (Set Up Subscription Pricing with Proration)](https://trailhead.salesforce.com/content/learn/modules/advanced-price-management-with-revenue-cloud/set-up-subscription-pricing-with-proration)
- [Salesforce Help — Build Your Pricing Procedures Using Salesforce Pricing](https://help.salesforce.com/s/articleView?id=ind.pricing_pricing_procedures.htm&type=5)
- [Salesforce — CPQ and Billing Proration Implementation Guide (PDF)](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_proration_implementation_guide.pdf)
