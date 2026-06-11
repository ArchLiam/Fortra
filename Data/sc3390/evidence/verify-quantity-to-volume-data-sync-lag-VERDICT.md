# SC-3390 — Adversarial verification of candidate [quantity-to-volume-data-sync-lag]

VERDICT: **REFUTED** (candidate was offered as "Likely DEAD"; independent checks kill it.)

Claim under test: a Quantity -> Attribute_Volume sync runs one cycle behind the
reprike, so the first "Update Price" prices off the previous Quantity. This requires
SOME automation (flow/trigger/PCR/context map) that WRITES Attribute_Volume FROM
QuoteLineItem.Quantity. If no such writer exists, the mechanism cannot exist.

## Independently re-verified facts (live FortraUAT, 2026-06-11, read-only)

1. AttributeDefinition (live): Id 0tjWC0000000tqvYAA, DeveloperName=Attribute_Volume,
   Name="Unit Volume", **Label="Unit Quantity"**, DataType=Number, IsActive=true.
   -> The ticket word "quantity" maps to this REP-TYPED attribute, not QLI.Quantity.

2. Prehook AttributeVolancingPrehook.cls (live == local, only trailing-newline diff):
   - Reads Attribute_Volume only: const line 33, getAttributeVolumeValue line 279/783,
     skipped as a key line 397-400. NEVER assigned.
   - Writes back ONLY: Base_Price__c (line 468), Attribute_Price_Mode__c (line 474),
     Attribute_Multiplier_Pct__c (line 482, Calculated only). Reset path (line 535-543)
     writes Base_Price__c + Attribute_Price_Mode__c='Unit Price'. **Attribute_Volume is
     never in any write-back list.**

3. QLDescriptionGeneratorPrehook.cls: also READ-only on Attribute_Volume
   (resolveUnitQuantity line 472-485 — attrs.get(UNIT_QUANTITY_ATTR), returns string).

4. Repo-wide grep: "Attribute_Volume" appears ONLY in the 2 prehooks + their 2 test
   classes. Zero flows, zero triggers, zero rule XML.

5. ProductConfigurationRule (live COUNT = 302, matches prior). Full scan of all 302
   ConfigurationRuleDefinition bodies:
   - usageSubType: Transaction x302.
   - actionTypes: Requires 17, Validate 40, AutoAdd 262, AutoRemove 61. **No Set-Attribute action type.**
   - 0 occurrences of Attribute_Volume / Quantity / Unit Volume / Unit Quantity /
     AttributeValue / SetAttribute (case-insensitive).

6. Apex triggers on QuoteLineItem: QuoteLineItemTrigger, QuoteLineItemExchangeRateTrigger.
   Neither references Attribute_Volume or QuoteLineItemAttribute.

7. QLI flows (Product_Configurator_Flow, Fortra_QuoteLineItem_Calculate_ARR,
   Fortra_QuoteLineItem_Legal_Entity_Copy): 0 references to Attribute_Volume / Unit Volume /
   QuoteLineItemAttribute. The only "*Volume*/*Tier*/*Attribute*"-named flows are
   GearsetCloneSupportFlow* deploy helpers, not runtime sync flows.

8. Live data decoupling (150 QLIA "Unit Volume" rows, file
   verify-quantity-to-volume-data-sync-lag-live-qlia.json):
   - non-null volume where value == parent Quantity: **0 / 150**
   - non-null volumes (20,50,100,400,10) all sit on Quantity=1 or 0 lines.
   - lines with Quantity=100 / 52 / 2 carry NULL volume.
   A lagging sync would still produce value≈Quantity in SOME recent rows; we see none.
   The two fields are fully independent.

## Conclusion
There is NO automation (flow/trigger/PCR/context map) that writes Attribute_Volume from
Quantity. The prehook only reads Attribute_Volume and never writes it. Therefore the
proposed "Quantity->Attribute_Volume sync that lags one cycle" mechanism does not exist in
this org. Candidate REFUTED. Any genuine first-click-stale lag must come from how the
freshly-typed Attribute_Volume is snapshotted into the pricing CONTEXT (hydration / reprice
ordering / recursion-guard), not from a Quantity->attribute data sync.
