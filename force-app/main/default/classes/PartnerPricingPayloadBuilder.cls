/**
 * @description Pure assembler of the partner-pricing context-update attribute list, extracted
 *              verbatim from PartnerPricingPrehookV2 (Wave-2 hook-thinning). No SOQL/DML/context/tag
 *              reads and no margin math (that stays in PartnerPricingServiceV2) — deterministic over
 *              primitive inputs. The margin-detail maps are pre-built by the hook shell (which owns
 *              the PartnerMarginDetail inner type) and passed in already-serializable.
 */
public with sharing class PartnerPricingPayloadBuilder {

    public static List<Map<String, Object>> buildPartnerPricingAttributes(
        Decimal currentPrice,
        Decimal adjustedPrice,
        String partnerPricingModel,
        List<Map<String, Object>> detailMaps,
        Decimal totalPercent,
        String warning
    ) {
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'Pre_Partner_Price__c', 'attributeValue' => currentPrice },
            new Map<String, Object>{ 'attributeName' => 'Partner_Adjusted_Price__c', 'attributeValue' => adjustedPrice },
            new Map<String, Object>{ 'attributeName' => 'Partner_Pricing_Model_Applied__c', 'attributeValue' => partnerPricingModel },
            new Map<String, Object>{ 'attributeName' => 'Partner_Pricing_Source__c', 'attributeValue' => 'System Calculated' },
            new Map<String, Object>{
                'attributeName' => 'Partner_Margin_Detail__c',
                'attributeValue' => (detailMaps == null || detailMaps.isEmpty()) ? null : JSON.serialize(detailMaps)
            },
            new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => adjustedPrice },
            new Map<String, Object>{ 'attributeName' => 'PartnerDiscountPercent', 'attributeValue' => totalPercent }
        };

        // D-PARTNER-5 (PartnerPricing SDD §6.2): stamp the custom total-partner-% audit field on the
        // success path too (was only ever nulled on the stale-clear path), symmetric with the standard
        // PartnerDiscountPercent above.
        attributes.add(new Map<String, Object>{ 'attributeName' => 'Partner_Discount_Percent__c', 'attributeValue' => totalPercent });

        // RLM propagates PartnerUnitPrice -> NetUnitPrice for TermDefined (Services) lines only;
        // OneTime (Perpetual) lines keep list price unless we set these explicitly.
        if (totalPercent != null && totalPercent > 0) {
            attributes.add(new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => adjustedPrice });
            attributes.add(new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => adjustedPrice });
        }

        // D-PARTNER-1 (PartnerPricing SDD §6.3 / BR-007): identify any configured partner missing a
        // matching model (null when all participating partners resolved a model).
        attributes.add(new Map<String, Object>{ 'attributeName' => 'Partner_Pricing_Warning__c', 'attributeValue' => warning });

        return attributes;
    }
}
