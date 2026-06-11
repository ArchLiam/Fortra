# SC-3393 — Runtime Data & Logs thread findings (2026-06-11)

## (1) ApexLogs today
- Debug logs ON for **Nir Kailash** only (~250 logs 14:00-16:09Z). NO German Wren logs; NO non-Success logs today.
- Large /aura configurator logs (1.5M-2.2M) at 15:31-16:09Z reference quote **0Q0WC0000037v1R0AQ "Renewal Quote"** (beSECURE renewal) — NOT the SC-3393 failing quote. Downloaded to evidence/logs/raw_07LWC*.log.
- The literal strings SF-Pricing-00006 / SF-BRF-00004 / RegionalNetReconcileGate appear in ZERO Apex logs. => the SF-Pricing/SF-BRF "couldn't simulate the step" error is raised inside the managed RLM pricing engine (ExpressionSet/BRE simulate), which does NOT emit to Apex debug logs. No Apex-side capture of the repro exists.
- Logs DO show RegionalServicesPricingPrehook (27x) + AttributeVolumePricingPrehook fire during pricing — confirms prehooks run, but on a different (succeeding) quote.

## (2) Failing quote 0Q0WC0000037tXV0AY
- LineItemCount = 0; QuoteLineItem query returns 0 rows. CONFIRMED 0 lines. LastModified 2026-06-11T15:18Z.

## (3) Field defaults (metadata RETRIEVE from live FortraUAT)
- QLI **Regional_NetUnit_Price__c**: Currency(18,2), required=false, **NO <defaultValue>** => NULL on fresh line. CONFIRMED.
- QLI **Allow_Regional_Pricing__c**: Checkbox, <defaultValue>false</defaultValue>; desc "...eligible for Fortra regional pricing. Results in the Pricing Procedure calculating the regional pricing." (mirrored true from Product2 for services).

## (4) Existing regional lines — does a successful regional line populate Regional_NetUnit_Price__c?
- 386 QLIs total with Allow_Regional_Pricing=true. MOST have Regional_NetUnit_Price__c = **NULL** and still priced fine (US lines). Only EUR/regional or specific lines carry a value (e.g. EAQS=1540, HRSCTM=180, 24x7x365=9600).
- Two of the 5 failing products already exist as successful NULL-regional US lines BEFORE V10: **CSCO I & II Course (OS-COS-NRST-CIICS)** Regional=null UnitPrice=850 (2026-06-09 16:19) and **Automate Expert Services (RPA-AUT-RSP-AUEX)** Regional=null UnitPrice=12000 (2026-06-08).
- OrderItem mirror (188 rows AllowRegionalPricing=true): same pattern — null RegionalNetUnitPrice lines succeeded on 2026-06-09 (EESE, MSPSS, HRAHFU = null).
=> A successful US regional line does NOT populate Regional_NetUnit_Price__c; it stays NULL. Population only happens for non-US/regional multiplier countries (prehook writes it).

## (5) Can other (non-Services) products be added to this quote / today?
- ALL QLIs created on 2026-06-11 (dozens, by German Wren / Nir / Joe Romo / Marc) have **Allow_Regional_Pricing__c = false** and added successfully (beSECURE, PIAMBK, CLSAAS, Automate Enterprise, hardware, etc.).
- ZERO Allow_Regional_Pricing=true QLIs created on/after 2026-06-10 (V10 day) OR today 2026-06-11.
- Last successful Allow_Regional_Pricing=true QLI = **2026-06-09 18:55Z** (HRM-HRM-NRST-MSPSS, Jordan Pollard).

## TEMPORAL SMOKING GUN
- V10 added RegionalNetReconcile gate on 2026-06-10. Since 2026-06-10 00:00Z: 0 regional-flagged lines created; before that, hundreds. Non-regional lines unaffected (still adding today).
- Gate XML (active V12 group) confirmed: crit1 AllowRegionalPricing__c Equals (true); crit2 RegionalNetUnitPrice__c GreaterThan (0). Children derive NetUnitPrice/InputUnitPrice from RegionalNetUnitPrice__c.

## VERDICT
Strongly SUPPORTS H1. The added-OK-before / fails-after-V10 boundary lands exactly on the V10 gate deploy, and the only products that can no longer be added are the Allow_Regional_Pricing=true ones — while flag=false products add fine all day. No runtime Apex log of the actual failure exists (managed-engine error), so the BRF resource-missing mechanism is inferred from config+data, not directly traced. Cannot distinguish H1 vs H3-at-runtime from logs alone; H2 not evidenced (prehooks run, context builds for succeeding quotes).
