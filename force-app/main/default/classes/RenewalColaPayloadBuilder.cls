/**
 * @description Pure assembler of the ExpressionSet context-update payload for the renewal-COLA
 *              builders, extracted verbatim from PartnerNetPricePosthook (Wave-2 decomposition,
 *              build*Update step 8). Two distinct attribute sets: the commit payload carries
 *              Subtotal/TotalLineAmount and NO COLA stamp; the maintenance payload carries the
 *              COLACalculatedPrice__c stamp and no Subtotal/TotalLineAmount. No SOQL/DML/context/tag
 *              reads — deterministic over primitive inputs; guards/idempotency stay in the shells.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalColaPayloadBuilder {

    /**
     * @description Builds the renewal-COLA COMMIT context-update payload: 6 OUTPUT-only fixed pricing
     *              attributes (NetUnitPrice/NetTotalPrice/TotalPrice/PartnerUnitPrice/Subtotal/
     *              TotalLineAmount) with no COLA stamp, plus any partner/software discount attributes.
     *              Deliberately EXCLUDES the input-oriented UnitPrice/InputUnitPrice — including an
     *              input-type attribute silently poisons the whole updateContextAttributes node batch
     *              (COLA SDD §6), which was why the committed NetUnitPrice was being discarded (SC-3350).
     * @param updatePath The ExpressionSet dataPath the update targets.
     * @param colaNet The COLA-adjusted net unit price stamped onto the unit-level attributes.
     * @param lineTotal The line total stamped onto the total/subtotal attributes.
     * @param partnerPercent The partner discount percent; added only when non-null and greater than zero.
     * @param softwareDiscount The software discount; added only when non-null and greater than zero.
     * @return The assembled context-update payload map (nodePath plus attributes).
     */
    public static Map<String, Object> buildCommitPayload(
        Object updatePath,
        Decimal colaNet,
        Decimal lineTotal,
        Decimal partnerPercent,
        Decimal softwareDiscount
    ) {
        // SC-3350: write OUTPUT-only pricing fields. `InputUnitPrice` (and `UnitPrice`) are
        // input-oriented context attributes; per the COLA SDD §6, including an input-type
        // attribute in an updateContextAttributes batch SILENTLY POISONS THE WHOLE NODE BATCH,
        // so NetUnitPrice and every other write on the line is discarded. The proven-persisting
        // paths (PartnerNetPricePosthook.buildNetPriceUpdate, CancelLineCreditCalculator.buildNodeUpdate)
        // write output fields only. Match that set so the COLA net actually commits.
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal }
        };
        addDiscountAttrs(attributes, partnerPercent, softwareDiscount);
        return payload(updatePath, attributes);
    }

    /**
     * @description Builds the renewal-MAINTENANCE-COLA context-update payload: 7 fixed pricing attributes
     *              including the COLACalculatedPrice__c stamp (and no Subtotal/TotalLineAmount), plus any
     *              partner/software discount attributes.
     * @param updatePath The ExpressionSet dataPath the update targets.
     * @param colaNet The COLA-adjusted net unit price stamped onto the unit-level attributes and COLACalculatedPrice__c.
     * @param lineTotal The line total stamped onto the total-price attributes.
     * @param partnerPercent The partner discount percent; added only when non-null and greater than zero.
     * @param softwareDiscount The software discount; added only when non-null and greater than zero.
     * @return The assembled context-update payload map (nodePath plus attributes).
     */
    public static Map<String, Object> buildMaintenancePayload(
        Object updatePath,
        Decimal colaNet,
        Decimal lineTotal,
        Decimal partnerPercent,
        Decimal softwareDiscount
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'InputUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet }
        };
        addDiscountAttrs(attributes, partnerPercent, softwareDiscount);
        return payload(updatePath, attributes);
    }

    /**
     * @description Conditionally appends the partner discount percent and software discount attributes,
     *              adding each only when its value is non-null and greater than zero.
     * @param attributes The attribute list being assembled, mutated in place.
     * @param partnerPercent The partner discount percent; appended only when non-null and greater than zero.
     * @param softwareDiscount The software discount; appended only when non-null and greater than zero.
     */
    private static void addDiscountAttrs(
        List<Map<String, Object>> attributes,
        Decimal partnerPercent,
        Decimal softwareDiscount
    ) {
        if (partnerPercent != null && partnerPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => partnerPercent
            });
        }
        if (softwareDiscount != null && softwareDiscount > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => softwareDiscount
            });
        }
    }

    /**
     * @description Wraps the assembled attribute list in the context-update envelope, nesting the
     *              update path under nodePath.dataPath.
     * @param updatePath The ExpressionSet dataPath placed under nodePath.dataPath.
     * @param attributes The assembled attribute list included in the payload.
     * @return The context-update payload map (nodePath plus attributes).
     */
    private static Map<String, Object> payload(Object updatePath, List<Map<String, Object>> attributes) {
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }
}