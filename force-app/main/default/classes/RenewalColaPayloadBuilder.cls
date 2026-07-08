/**
 * @description Pure assembler of the ExpressionSet context-update payload for the renewal-COLA
 *              builders, extracted verbatim from PartnerNetPricePosthook (Wave-2 decomposition,
 *              build*Update step 8). Two distinct attribute sets: the commit payload carries
 *              Subtotal/TotalLineAmount and NO COLA stamp; the maintenance payload carries the
 *              COLACalculatedPrice__c stamp and no Subtotal/TotalLineAmount. No SOQL/DML/context/tag
 *              reads — deterministic over primitive inputs; guards/idempotency stay in the shells.
 */
public with sharing class RenewalColaPayloadBuilder {

    /** @description Renewal-COLA COMMIT payload: 8 fixed attrs (incl. Subtotal/TotalLineAmount), no COLA stamp. */
    public static Map<String, Object> buildCommitPayload(
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
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal }
        };
        addDiscountAttrs(attributes, partnerPercent, softwareDiscount);
        return payload(updatePath, attributes);
    }

    /** @description Renewal-MAINTENANCE-COLA payload: 7 fixed attrs incl. COLACalculatedPrice__c stamp. */
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

    private static Map<String, Object> payload(Object updatePath, List<Map<String, Object>> attributes) {
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }
}
