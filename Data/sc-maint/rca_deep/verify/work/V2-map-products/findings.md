# V2-map-products findings

## PBEDP (Map Products) rows for RRM derived PBE 01uWC000006XPPBYA4
- 182WC000000HNcwYAG: ProductId=01tWC00000DD1buYAD (RRM PIAM) <- ContributingProductId=01tWC00000DD1btYAD (PIA-PIA-NRPS-PIAP license)
- DerivedPricingScope=Both, PricingSource=Product, Formula=UnitPrice

## ALL PBEDP where ProductId=RRM (01tWC00000DD1buYAD): 3 rows, ALL contributor = PIAP license
- 182WC000000HNcvYAG (PBE 01uWC000006XPNZYA4)
- 182WC000000HNcwYAG (PBE 01uWC000006XPPBYA4 = the target)
- 182WC000000FN2tYAG (PBE 01uWC000005wsbVYAQ)

## Is owned RNM PIAMBK (01tWC00000DD1bsYAD) ever a CONTRIBUTOR? NO. 0 rows.
- Only PBEDP touching PIAMBK = 182WC000000FN26YAG, where PIAMBK is itself a DERIVED product (contributor=PIAP license again)

## Asset products
- Control source asset 02iWC000008GKPaYAO = PIA-PIA-RRM-PIAM (prod 01tWC00000DD1buYAD), Price 60.64 -> matches derived RRM product
- Canary owns 02iWC000008DmS1YAK = PIA-PIA-RNM-PIAMBK (62.48) + 02iWC000008DmS2YAK = PIA-PIA-NRPS-PIAP (301.75); NO RRM asset

## QuoteAction state
- Control quote 0Q0WC00000382MH0AY: 2x QuoteAction Type=Renew, SourceAssetId = real RRM assets (incl 02iWC000008GKPaYAO)
- Canary quote 0Q0WC0000038aXd0AI: 0 QuoteActions -> no contributor -> DerivedProductsRenewals skipped -> fossil 60.64 retained

## Pricing-proc consumer
- DerivedProductsRenewals (V14 step name=DerivedProductsRenewals, actionType=DerivedPricing, parentStep=DerivedProductsNativePull, advancedCondition QuoteTypeText__c via sibling Non-Renewal filter)
- NetUnitPrice + Subtotal are OUTPUT params; ContributingProduct/Contributor* are INPUT params -> engine writes Net, never source data
