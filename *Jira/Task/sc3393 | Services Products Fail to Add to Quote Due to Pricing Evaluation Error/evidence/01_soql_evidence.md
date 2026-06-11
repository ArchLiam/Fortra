# SC-3393 — Live UAT SOQL Evidence (FortraUAT, read-only, 2026-06-11)

## Failing quote
0Q0WC0000037tXV0AY | #00781060 "Q-Wren - Test Services" | Draft
Account: OhioHealth Corporation | Billing/ShippingCountry = United States | USD | Pricebook = Fortra Price Book

## The 5 reported products — ALL Product2.Allow_Regional_Pricing__c = TRUE
01tWC00000DD115YAD  24 X 7 X 365 Monitoring        VM-DDL-NRSU-2X7X3M    Services  true
01tWC00000DD11VYAT  Administering Automated Password Management  IGA-AAS-NRST-ADMIAP  Training  true
01tWC00000DD11xYAD  AIC Expert Services            RPA-AUT-RSP-AICEXP   Services  true
01tWC00000DD148YAD  Automate Expert Services       RPA-AUT-RSP-AUEX     Services  true
01tWC00000DD17hYAD  CSCO I & II Course             OS-COS-NRST-CIICS    Services  true
CONTROL 01tWC00000FBWonYAH  24 X 7 X 365 Monitoring (Technical)  Allow_Regional_Pricing=false

## "Allow=true + Regional_NetUnit_Price=null" is the NORMAL state for US services lines
QuoteLineItem WHERE Allow_Regional_Pricing__c = true            => COUNT = 386
   ...AND Regional_NetUnit_Price__c = null                       => COUNT = 340   (88%)
Only Italy/regional lines carry a value (e.g. EFT Arcus 1540, 24x7 Monitoring 9600, Hourly Sr Consultant 180).

## These exact 5 products were ADDED SUCCESSFULLY through June 9 (BEFORE the gate went live)
0QLWC000003cCw54AE  CSCO I & II Course        US  Allow=true  RegionalNet=null  UnitPrice=850    2026-06-09T16:19:16Z
0QLWC000003bo494AA  Automate Expert Services  US  Allow=true  RegionalNet=null  UnitPrice=12000  2026-06-08T17:03:44Z
0QLWC000003Zi7o4AC  AIC Expert Services       US  Allow=true  RegionalNet=null  UnitPrice=12000  2026-06-03T15:45:19Z
0QLWC000003Zi1G4AS  24 X 7 X 365 Monitoring   US  Allow=true  RegionalNet=null  UnitPrice=15000  2026-06-03T15:42:38Z
0QLWC000003ayOw4AI  24 X 7 X 365 Monitoring   Italy Allow=true RegionalNet=9600 UnitPrice=9600   2026-06-06T16:35:23Z
=> The reporter's "added successfully during other quote testing" = these June 3-9 adds, under V9 (no gate).

## Propagation Product2.Allow_Regional_Pricing -> QLI.Allow_Regional_Pricing (turned on early June)
CSCO I & II Course history (Product2 flag = true throughout):
  0QLWC000003JtQ24AK  2026-05-04  QLI Allow = FALSE   (propagation not yet active)
  0QLWC000003bSWg4AM  2026-06-08  QLI Allow = TRUE
  0QLWC000003cCw54AE  2026-06-09  QLI Allow = TRUE
(Exact automation that copies Product2->QLI is not in local source; behavior confirmed by data. Immaterial to RCA.)

## Debug logs
- No ApexLog for reporter German Wren (pricing-engine UI error does not emit an ApexLog without a trace flag).
- Confirming FINEST/pricing repro log is the one remaining empirical step (needs authorized add-line repro).

## Field defaults (decisive)
- QLI Allow_Regional_Pricing__c : Checkbox, default=false  (never null)
- QLI Regional_NetUnit_Price__c : Currency, NO default      (=> NULL on fresh US line)
- OrderItem mirror fields "Named to match Context Definition tag attribute"
