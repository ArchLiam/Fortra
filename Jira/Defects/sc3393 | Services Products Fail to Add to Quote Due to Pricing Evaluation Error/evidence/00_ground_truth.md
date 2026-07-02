# SC-3393 Ground Truth (inline scouting, 2026-06-11)

## Error
SF-Pricing-00006: value specified for evaluation resource for RegionalNetReconcileGate#1 isn't valid.
SF-BRF-00004: couldn't simulate the step because one or more specified resources don't have corresponding values for evaluation.
Fires when ADDING a Services product to a quote; quote then has 0 lines.

## Failing quote
- 0Q0WC0000037tXV0AY  "Q-Wren - Test Services"  #00781060  Draft
- Account: OhioHealth Corporation | BillingCountry=United States | ShippingCountry=United States
- CurrencyIsoCode=USD | Pricebook=Fortra Price Book (01sWC0000022GHFYA2)
- => US/USD => RegionalServicesPricingPrehook is a NO-OP (default multiplier 1.0, writes nothing)

## The 5 Services products — ALL Product2.Allow_Regional_Pricing__c = TRUE
- 01tWC00000DD115YAD  24 X 7 X 365 Monitoring        VM-DDL-NRSU-2X7X3M    Services  true
- 01tWC00000DD11VYAT  Administering Automated Password Management  IGA-AAS-NRST-ADMIAP  Training  true
- 01tWC00000DD11xYAD  AIC Expert Services            RPA-AUT-RSP-AICEXP   Services  true
- 01tWC00000DD148YAD  Automate Expert Services       RPA-AUT-RSP-AUEX     Services  true
- 01tWC00000DD17hYAD  CSCO I & II Course             OS-COS-NRST-CIICS    Services  true
- CONTROL: 01tWC00000FBWonYAH  24 X 7 X 365 Monitoring (Technical)  Allow_Regional_Pricing=false
- Product2 field help text: "Services products only."

## Active pricing procedure: Rev_Mgmt_Default_Pricing_Procedure (memory: active V12)
RegionalNetReconcile ListGroup (top-level seq 33) — ADDED in V10 (2026-06-10 per SC-3374 memory). Children:
- RegionalNetReconcileGate (AdvancedListFilter, seq1), conditionLogic "1 AND 2":
    crit1: AllowRegionalPricing__c Equals true
    crit2: RegionalNetUnitPrice__c GreaterThan 0
- RegionalNetUnitPrice (BKM seq2): NetUnitPrice = IF(RegionalNetUnitPrice__c < NetUnitPrice, RegionalNetUnitPrice__c, NetUnitPrice)
- RegionalInputUnitPrice (seq3): InputUnitPrice
- RegionalNetTotal (seq4, resultIncluded): ItemNetTotalPrice = NetUnitPrice*LineItemQuantity
- RegionalListTotal (seq5): TotalLineAmount = NetUnitPrice*LineItemQuantity

## Prehook RegionalServicesPricingPrehook v13.3 (live == Org Data/_src copy)
- Writes context attrs ONLY when country has non-default multiplier: UnitPrice, RegionalNetUnitPrice__c,
  PrehookRSNetUnitPrice__c, RegionalPricingExplainer__c, RegionalPricingApplied__c, Pre_Regional_Price__c, Regional_Multiplier__c
- Does NOT write AllowRegionalPricing__c. For US: no-op (no writes at all).

## Context def SalesTransactionContextExt_v2 (11OWC000002m21Z2AQ) — DESIGN has the mappings
SalesTransactionItem node, source QuoteLineItem block (~5297-7049):
  Regional_NetUnit_Price__c -> RegionalNetUnitPrice__c  (contextInputAttributeName, INPUT)
  Allow_Regional_Pricing__c -> AllowRegionalPricing__c  (contextInputAttributeName, INPUT)
SalesTransactionItem node, source OrderItem block (~10810-12403): same attrs mapped 1:1 by name.
=> design mappings present on Quote line. Sync state of ACTIVE version = TBD.

## Field defaults
- QLI Allow_Regional_Pricing__c: Checkbox default=false (Product2 mirror sets it true for services)
- QLI Regional_NetUnit_Price__c: Currency, NO default => NULL on a fresh US line
- OrderItem AllowRegionalPricing__c / RegionalNetUnitPrice__c: "Mirror ... Named to match Context Definition tag attribute"

## PRIMARY HYPOTHESIS
Services products (Allow_Regional_Pricing=true) make gate crit1 TRUE -> engine evaluates crit2
(RegionalNetUnitPrice__c > 0) -> Regional_NetUnit_Price__c is NULL on US line (prehook no-op, no default)
-> gate resource has no value -> SF-BRF-00004. Non-services (flag=false) short-circuit crit1 -> never reach crit2 -> no error.
Recently-introduced = RegionalNetReconcile gate added V10 (2026-06-10).
