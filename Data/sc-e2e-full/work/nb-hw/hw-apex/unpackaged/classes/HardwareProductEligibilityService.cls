/**
 * @description Service class for filtering products based on hardware eligibility criteria.
 *              Used in hardware-first workflow to determine which products are compatible
 *              with selected hardware based on processors and feature codes.
 * @author Marc DeBrey
 * @date 2025-11-10
 */
public with sharing class HardwareProductEligibilityService {

    /**
     * @description Main entry point for product eligibility filtering
     * @param hardwareId ID of the Hardware__c record to use as context
     * @return EligibilityResult containing eligible products and metadata
     */
    public static EligibilityResult filterProducts(Id hardwareId) {
        // 1. Get Hardware context
        Hardware__c hardware = getHardwareContext(hardwareId);

        // 2. Query all active products
        List<Product2> allProducts = queryActiveProducts();

        // 3. Apply filtering rules
        List<EligibleProduct> eligibleProducts = new List<EligibleProduct>();

        for (Product2 product : allProducts) {
            EligibilityCheck check = evaluateProductEligibility(product, hardware);

            if (check.isEligible) {
                eligibleProducts.add(new EligibleProduct(product, check.reasons));
            }
        }

        return new EligibilityResult(eligibleProducts, hardware);
    }

    /**
     * @description Retrieve hardware context with all required fields
     * @param hardwareId Hardware record ID
     * @return Hardware__c record with all context fields
     */
    @TestVisible
    private static Hardware__c getHardwareContext(Id hardwareId) {
        try {
            return [
                SELECT Id, Name, Number_of_Processors__c,
                       Feature_Code__c, Model_Number__c, Serial_Number__c
                FROM Hardware__c
                WHERE Id = :hardwareId
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new EligibilityException('Hardware record not found: ' + hardwareId);
        }
    }

    /**
     * @description Query all active products with eligibility fields
     * @return List of active Product2 records
     */
    @TestVisible
    private static List<Product2> queryActiveProducts() {
        return [
            SELECT Id, Name, ProductCode, Type,
                   Processor_Min__c,
                   Required_Feature_Codes__c,
                   Excluded_Feature_Codes__c
            FROM Product2
            WHERE IsActive = true
            ORDER BY Name
        ];
    }

    /**
     * @description Evaluate a single product against hardware eligibility criteria
     * @param product Product2 record to evaluate
     * @param hardware Hardware__c context
     * @return EligibilityCheck with eligibility status and reasons
     */
    @TestVisible
    private static EligibilityCheck evaluateProductEligibility(Product2 product, Hardware__c hardware) {
        EligibilityCheck check = new EligibilityCheck();

        // Rule 1: Processor Count Check
        if (product.Processor_Min__c != null && hardware.Number_of_Processors__c != null) {
            if (hardware.Number_of_Processors__c < product.Processor_Min__c) {
                check.isEligible = false;
                check.addReason('Hardware processors (' + hardware.Number_of_Processors__c + ') below minimum requirement (' + product.Processor_Min__c + ')');
                return check;
            } else {
                check.addReason('Processor requirement met');
            }
        }

        // Rule 2: Required Feature Codes Check
        if (String.isNotBlank(product.Required_Feature_Codes__c)) {
            Set<String> requiredCodes = parseFeatureCodes(product.Required_Feature_Codes__c);
            Set<String> hardwareCodes = parseFeatureCodes(hardware.Feature_Code__c);

            Set<String> missingCodes = new Set<String>();
            for (String requiredCode : requiredCodes) {
                if (!hardwareCodes.contains(requiredCode)) {
                    missingCodes.add(requiredCode);
                }
            }

            if (!missingCodes.isEmpty()) {
                check.isEligible = false;
                check.addReason('Missing required feature codes: ' + String.join(new List<String>(missingCodes), ', '));
                return check;
            } else {
                check.addReason('All required feature codes present');
            }
        }

        // Rule 3: Excluded Feature Codes Check
        if (String.isNotBlank(product.Excluded_Feature_Codes__c)) {
            Set<String> excludedCodes = parseFeatureCodes(product.Excluded_Feature_Codes__c);
            Set<String> hardwareCodes = parseFeatureCodes(hardware.Feature_Code__c);

            Set<String> conflictCodes = new Set<String>();
            for (String excludedCode : excludedCodes) {
                if (hardwareCodes.contains(excludedCode)) {
                    conflictCodes.add(excludedCode);
                }
            }

            if (!conflictCodes.isEmpty()) {
                check.isEligible = false;
                check.addReason('Hardware has excluded feature codes: ' + String.join(new List<String>(conflictCodes), ', '));
                return check;
            }
        }

        // Rule 4: Bundle Handling (using standard Product2.Type field)
        if (product.Type == 'Bundle') {
            // Note: Full bundle component eligibility check would require
            // querying bundle components and recursively checking each.
            // For now, we allow bundles if parent product passes all checks.
            // TODO: Implement bundle component eligibility verification
            check.addReason('Bundle product (component eligibility not yet implemented)');
        }

        // If we made it here, product is eligible
        check.isEligible = true;
        if (check.reasons.isEmpty()) {
            check.addReason('No specific eligibility criteria defined');
        }

        return check;
    }

    /**
     * @description Parse semicolon-separated feature codes into a Set
     * @param featureCodeString Semicolon-separated feature codes
     * @return Set of trimmed feature codes
     */
    @TestVisible
    private static Set<String> parseFeatureCodes(String featureCodeString) {
        Set<String> codes = new Set<String>();

        if (String.isNotBlank(featureCodeString)) {
            List<String> codeList = featureCodeString.split(';');
            for (String code : codeList) {
                String trimmedCode = code.trim();
                if (String.isNotBlank(trimmedCode)) {
                    codes.add(trimmedCode);
                }
            }
        }

        return codes;
    }

    // ========== INNER CLASSES ==========

    /**
     * @description Wrapper class for eligibility check results
     */
    public class EligibilityCheck {
        public Boolean isEligible { get; set; }
        public List<String> reasons { get; set; }

        public EligibilityCheck() {
            this.isEligible = false;
            this.reasons = new List<String>();
        }

        public void addReason(String reason) {
            this.reasons.add(reason);
        }
    }

    /**
     * @description Wrapper for an eligible product with reasons
     */
    public class EligibleProduct {
        public Product2 product { get; set; }
        public List<String> reasons { get; set; }

        public EligibleProduct(Product2 prod, List<String> reasonList) {
            this.product = prod;
            this.reasons = reasonList;
        }
    }

    /**
     * @description Result wrapper containing eligible products and hardware context
     */
    public class EligibilityResult {
        public List<EligibleProduct> eligibleProducts { get; set; }
        public Hardware__c hardware { get; set; }
        public Integer totalProductsEvaluated { get; set; }
        public Integer eligibleProductCount { get; set; }

        public EligibilityResult(List<EligibleProduct> eligible, Hardware__c hw) {
            this.eligibleProducts = eligible;
            this.hardware = hw;
            this.eligibleProductCount = eligible.size();
        }
    }

    /**
     * @description Custom exception for eligibility errors
     */
    public class EligibilityException extends Exception {}
}