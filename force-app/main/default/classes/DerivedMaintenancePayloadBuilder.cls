/**
 * @description Pure assembler of the ExpressionSet context-update payload (nodePath.dataPath +
 *              ordered attribute list) for the New-Business derived-maintenance builders, extracted
 *              verbatim from PartnerNetPricePosthook (Wave-2 decomposition, build*Update steps 6-7).
 *              Holds NO arithmetic decisions and NO guards — only the verbose, mechanical attribute-
 *              map construction. No SOQL/DML/context/tag reads; deterministic over primitive inputs.
 */
public with sharing class DerivedMaintenancePayloadBuilder {

    /**
     * @description Sequential-discount payload for buildDerivedMaintenanceSequentialDiscountUpdate:
     *              10 fixed attributes + conditional Base_Price__c / PartnerDiscountPercent / Discount,
     *              byte-identical order, source string 'System Calculated (Post-Procedure)'.
     */
    public static Map<String, Object> buildSequentialDiscountPayload(
        Object updatePath,
        Decimal commercialNet,
        Decimal lineTotal,
        Decimal partnerUnitPrice,
        Decimal derivedListNet,
        Decimal contributorNetPrice,
        Decimal partnerPercent,
        Decimal manualPercent
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => commercialNet },
            new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'Subtotal', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'TotalLineAmount', 'attributeValue' => lineTotal },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => partnerUnitPrice },
            new Map<String, Object>{ 'attributeName' => 'ListPrice', 'attributeValue' => derivedListNet },
            new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => derivedListNet },
            new Map<String, Object>{
                'attributeName' => 'Pre_Partner_Price__c',
                'attributeValue' => derivedListNet
            },
            new Map<String, Object>{
                'attributeName' => 'Partner_Pricing_Source__c',
                'attributeValue' => 'System Calculated (Post-Procedure)'
            }
        };

        if (contributorNetPrice != null && contributorNetPrice > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Base_Price__c',
                'attributeValue' => contributorNetPrice
            });
        }

        if (partnerPercent != null && partnerPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => partnerPercent
            });
        }
        if (manualPercent != null && manualPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => manualPercent
            });
        }

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }
}
