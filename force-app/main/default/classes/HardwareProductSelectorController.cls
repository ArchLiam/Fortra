/**
 * @description Controller for hardwareProductSelector Lightning Web Component
 * @author Marc DeBrey
 * @date 2025-11-10
 */
public with sharing class HardwareProductSelectorController {

    /**
     * @description Get eligible products for a given hardware record
     * @param hardwareId Hardware__c record ID
     * @return EligibilityResultWrapper containing hardware context and eligible products
     */
    @AuraEnabled(cacheable=true)
    public static EligibilityResultWrapper getEligibleProducts(Id hardwareId) {
        try {
            HardwareProductEligibilityService.EligibilityResult result =
                HardwareProductEligibilityService.filterProducts(hardwareId);

            return new EligibilityResultWrapper(result);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to retrieve eligible products: ' + e.getMessage());
        }
    }

    /**
     * @description Add selected products to a quote
     * @param quoteId Quote record ID
     * @param productIds List of Product2 IDs to add
     * @param hardwareId Hardware__c record ID for context
     * @return Success message
     */
    @AuraEnabled
    public static String addProductsToQuote(Id quoteId, List<Id> productIds, Id hardwareId) {
        try {
            // Validate inputs
            if (quoteId == null || productIds == null || productIds.isEmpty()) {
                throw new AuraHandledException('Quote ID and at least one product are required');
            }

            // Get quote and hardware context
            Quote quote = [SELECT Id, Pricebook2Id FROM Quote WHERE Id = :quoteId LIMIT 1];
            Hardware__c hardware = [SELECT Id, Number_of_Processors__c, Model_Number__c
                                   FROM Hardware__c WHERE Id = :hardwareId LIMIT 1];

            // Get pricebook entries for selected products
            List<PricebookEntry> pbes = [
                SELECT Id, Product2Id, Pricebook2Id, UnitPrice, IsActive
                FROM PricebookEntry
                WHERE Product2Id IN :productIds
                AND Pricebook2Id = :quote.Pricebook2Id
                AND IsActive = true
            ];

            if (pbes.isEmpty()) {
                throw new AuraHandledException('No active pricebook entries found for selected products in this quote\'s pricebook');
            }

            // Create quote line items
            List<QuoteLineItem> newLines = new List<QuoteLineItem>();
            for (PricebookEntry pbe : pbes) {
                QuoteLineItem qli = new QuoteLineItem(
                    QuoteId = quoteId,
                    PricebookEntryId = pbe.Id,
                    Product2Id = pbe.Product2Id,
                    Quantity = 1,
                    UnitPrice = pbe.UnitPrice,
                    Hardware__c = hardwareId
                    // Note: BillingFrequency will be set via field defaults or process automation
                    // Setting it here causes validation errors with PricingTermUnit
                );

                newLines.add(qli);
            }

            insert newLines;

            return 'Successfully added ' + newLines.size() + ' product(s) to quote';
        } catch (Exception e) {
            throw new AuraHandledException('Failed to add products to quote: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper class for LWC consumption
     * Serializes the HardwareProductEligibilityService.EligibilityResult for wire service
     */
    public class EligibilityResultWrapper {
        @AuraEnabled public List<EligibleProductWrapper> eligibleProducts { get; set; }
        @AuraEnabled public HardwareContextWrapper hardwareContext { get; set; }
        @AuraEnabled public Integer totalProductsEvaluated { get; set; }
        @AuraEnabled public Integer eligibleProductCount { get; set; }

        public EligibilityResultWrapper(HardwareProductEligibilityService.EligibilityResult result) {
            this.eligibleProducts = new List<EligibleProductWrapper>();
            for (HardwareProductEligibilityService.EligibleProduct ep : result.eligibleProducts) {
                this.eligibleProducts.add(new EligibleProductWrapper(ep));
            }
            this.hardwareContext = new HardwareContextWrapper(result.hardware);
            this.totalProductsEvaluated = result.totalProductsEvaluated;
            this.eligibleProductCount = result.eligibleProductCount;
        }
    }

    public class EligibleProductWrapper {
        @AuraEnabled public String productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public List<String> eligibilityReasons { get; set; }

        public EligibleProductWrapper(HardwareProductEligibilityService.EligibleProduct ep) {
            this.productId = ep.product.Id;
            this.productName = ep.product.Name;
            this.productCode = ep.product.ProductCode;
            this.productType = ep.product.Type;
            this.eligibilityReasons = ep.reasons;
        }
    }

    public class HardwareContextWrapper {
        @AuraEnabled public String hardwareId { get; set; }
        @AuraEnabled public String hardwareName { get; set; }
        @AuraEnabled public Decimal numberOfProcessors { get; set; }
        @AuraEnabled public String modelNumber { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String featureCodes { get; set; }

        public HardwareContextWrapper(Hardware__c hardware) {
            this.hardwareId = hardware.Id;
            this.hardwareName = hardware.Name;
            this.numberOfProcessors = hardware.Number_of_Processors__c;
            this.modelNumber = hardware.Model_Number__c;
            this.serialNumber = hardware.Serial_Number__c;
            this.featureCodes = hardware.Feature_Code__c;
        }
    }
}