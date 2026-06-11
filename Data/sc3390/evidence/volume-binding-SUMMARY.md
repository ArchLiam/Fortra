# SC-3390 — Attribute_Volume ↔ Quantity binding (evidence summary)

## AttributeDefinition (live FortraUAT, 2026-06-11)
- Id: 0tjWC0000000tqvYAA
- DeveloperName: **Attribute_Volume** | Name: "Unit Volume" | Label: **"Unit Quantity"**
- DataType: **Number** | IsActive: true
- Description (verbatim): "Volume for attribute-based tier pricing. **Entered by reps in Product Configurator.**"

## ProductAttributeDefinition (26 tiered products incl. CLSAAS 01tWC00000DD17PYAT → PAD 0v7WC0000000TvBYAU)
- IsRequired=false, MinimumValue=null, MaximumValue=null, **DefaultValue=null**, IsHidden=false, IsReadOnly=false, IsPriceImpacting=false on ALL 26.
- No default ⇒ nothing pre-fills it; blank until rep types a number.

## Configuration rules — NO auto-sync from Quantity
- 302 ProductConfigurationRules (all RuleType=Configurator/Transaction).
- Scan of every ConfigurationRuleDefinition JSON: **0 reference Attribute_Volume, 0 reference Quantity, 0 Set-attribute actions.**
- Action types present: Requires(17), Validate(40), AutoAdd(262), AutoRemove(61) — none write attribute values.
- No Flow / metadata anywhere in force-app or Org Data references Attribute_Volume (grep = 0 hits outside the 2 Apex prehooks).

## Live data proves decoupling (QuoteLineItemAttribute, AttributeDefinitionId=0tjWC0000000tqvYAA)
- 150 live rows; while QuoteLineItem.Quantity = 1, Attribute_Volume value was **null** on ~149 and **100.0** on one (0QLWC000003d4Ob4AI). Value ≠ Quantity in every observed case.
- That 100.0 row was re-nulled by a 14:44 save the same day; data churns live.

## CLSAAS tier boundaries (Attribute_Tier_Pricing_Storage__c, Product__c=01tWC00000DD17PYAT)
Feature Options / "Self Managed" tiers (volume range → Tier_Value, Price_Mode):
- 1–49 → 2160 Total Price
- 50–99 → 2580 Total Price
- 100–199 → 24 Unit Price
- 200–299 → 19.2 Unit Price ... 8000–10000 → 3.85 Unit Price; 10001+ → reset
⇒ crossing a volume boundary (e.g. 49→50) flips the matched tier. Match key is the **Attribute_Volume number range**, never QuoteLineItem.Quantity.

## Prehook usage
- AttributeVolumePricingPrehook only READS Attribute_Volume (const line 33; getAttributeVolumeValue line 783; reset-on-null line 282-290; reset-on-no-tier-match line 294-303). It NEVER writes it.
- On null volume OR no tier match → resets line to ListPrice.

## CONCLUSION
"Quantity" in the ticket = the configurator **"Unit Quantity" attribute (Attribute_Volume)**, a manual rep-typed Number, NOT the standard QuoteLineItem.Quantity field. There is NO automation that derives/syncs Attribute_Volume from Quantity, so there is no "Attribute_Volume one step behind Quantity" data automation in this area. Any first-click-stale lag must come from how the freshly typed Attribute_Volume value is snapshotted into the pricing context (hydration/reprice ordering), not from a Quantity→attribute sync.
