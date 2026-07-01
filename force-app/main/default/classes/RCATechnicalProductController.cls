/**
 * @description Controller class for RCA Technical Product Creator LWC
 * Provides methods for searching commercial products, validation, and technical product creation
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
public with sharing class RCATechnicalProductController {

    /**
     * @description Search for commercial products (products with Type or DecompositionScope set)
     * @param searchTerm Search string for name or product code
     * @param filterType Optional filter: 'bundle', 'all', or specific type
     * @return List of commercial Product2 records
     */
    @AuraEnabled(cacheable=true)
    public static List<CommercialProductWrapper> searchCommercialProducts(String searchTerm, String filterType) {
        String search = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<CommercialProductWrapper> results = new List<CommercialProductWrapper>();

        // Query for commercial products (products that are sold - have Type or are active)
        // Include Workday integration fields for downstream billing/rev rec
        String query = 'SELECT Id, Name, ProductCode, Description, Family, Type, ' +
                       'DecompositionScope, IsActive, ' +
                       'Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c, ' +
                       '(SELECT Id FROM SourceProduct) ' +
                       'FROM Product2 ' +
                       'WHERE (Name LIKE :search OR ProductCode LIKE :search) ' +
                       'AND IsActive = true ';

        // Add filter based on type
        if (filterType == 'bundle') {
            query += 'AND Type = \'Bundle\' ';
        } else if (filterType == 'commercial') {
            query += 'AND (Type != null OR DecompositionScope != null) ';
        }
        // 'all' shows all active products

        query += 'ORDER BY Name LIMIT 100';

        List<Product2> products = Database.query(query);

        for (Product2 p : products) {
            CommercialProductWrapper wrapper = new CommercialProductWrapper();
            wrapper.id = p.Id;
            wrapper.name = p.Name;
            wrapper.productCode = p.ProductCode;
            wrapper.description = p.Description;
            wrapper.family = p.Family;
            wrapper.productType = p.Type;
            wrapper.decompositionScope = p.DecompositionScope;
            wrapper.isActive = p.IsActive;
            wrapper.hasExistingTechnicalProducts = p.SourceProduct != null &&
                                                    !p.SourceProduct.isEmpty();
            wrapper.existingTechProductCount = p.SourceProduct != null ?
                                                p.SourceProduct.size() : 0;
            // Workday integration fields
            wrapper.workdaySalesItemId = p.Workday_Sales_Item_ID__c;
            wrapper.revCategory = p.Rev_Category__c;
            wrapper.financeBusinessUnit = p.Finance_Business_Unit__c;
            wrapper.fortraProductType = p.Fortra_Product_Type__c;
            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Get products by IDs
     * @param productIds List of Product2 IDs
     * @return List of Product2 records with related decomp rules
     */
    @AuraEnabled
    public static List<CommercialProductWrapper> getProductsByIds(List<String> productIds) {
        List<CommercialProductWrapper> results = new List<CommercialProductWrapper>();

        if (productIds == null || productIds.isEmpty()) {
            return results;
        }

        List<Product2> products = [
            SELECT Id, Name, ProductCode, Description, Family, Type,
                   DecompositionScope, IsActive,
                   Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c,
                   (SELECT Id, DestinationProductId, DestinationProduct.Name,
                           DestinationProduct.ProductCode, Priority
                    FROM SourceProduct
                    ORDER BY Priority)
            FROM Product2
            WHERE Id IN :productIds
        ];

        for (Product2 p : products) {
            CommercialProductWrapper wrapper = new CommercialProductWrapper();
            wrapper.id = p.Id;
            wrapper.name = p.Name;
            wrapper.productCode = p.ProductCode;
            wrapper.description = p.Description;
            wrapper.family = p.Family;
            wrapper.productType = p.Type;
            wrapper.decompositionScope = p.DecompositionScope;
            wrapper.isActive = p.IsActive;
            wrapper.hasExistingTechnicalProducts = p.SourceProduct != null &&
                                                    !p.SourceProduct.isEmpty();
            wrapper.existingTechProductCount = p.SourceProduct != null ?
                                                p.SourceProduct.size() : 0;
            // Workday integration fields
            wrapper.workdaySalesItemId = p.Workday_Sales_Item_ID__c;
            wrapper.revCategory = p.Rev_Category__c;
            wrapper.financeBusinessUnit = p.Finance_Business_Unit__c;
            wrapper.fortraProductType = p.Fortra_Product_Type__c;

            // Add existing technical products
            wrapper.existingTechnicalProducts = new List<TechnicalProductInfo>();
            if (p.SourceProduct != null) {
                for (ProductFulfillmentDecompRule rule : p.SourceProduct) {
                    TechnicalProductInfo techInfo = new TechnicalProductInfo();
                    techInfo.id = rule.DestinationProductId;
                    techInfo.name = rule.DestinationProduct.Name;
                    techInfo.productCode = rule.DestinationProduct.ProductCode;
                    techInfo.priority = rule.Priority;
                    techInfo.decompRuleId = rule.Id;
                    wrapper.existingTechnicalProducts.add(techInfo);
                }
            }

            results.add(wrapper);
        }

        return results;
    }

    /**
     * @description Validate technical product requests
     * @param requests JSON string of TechnicalProductRequest list
     * @return List of validation error messages
     */
    @AuraEnabled
    public static List<String> validateRequests(String requestsJson) {
        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            (List<RCATechnicalProductService.TechnicalProductRequest>)
            JSON.deserialize(requestsJson, List<RCATechnicalProductService.TechnicalProductRequest>.class);

        return RCATechnicalProductService.validateRequests(requests);
    }

    /**
     * @description Create technical products
     * @param requestsJson JSON string of TechnicalProductRequest list
     * @return BatchCreationResult with success/failure details
     */
    @AuraEnabled
    public static RCATechnicalProductService.BatchCreationResult createTechnicalProducts(String requestsJson) {
        List<RCATechnicalProductService.TechnicalProductRequest> requests =
            (List<RCATechnicalProductService.TechnicalProductRequest>)
            JSON.deserialize(requestsJson, List<RCATechnicalProductService.TechnicalProductRequest>.class);

        return RCATechnicalProductService.createTechnicalProducts(requests);
    }

    /**
     * @description Get reference data for the UI
     * @return ReferenceData object with classifications, rulesets, and families
     */
    @AuraEnabled(cacheable=true)
    public static ReferenceData getReferenceData() {
        ReferenceData data = new ReferenceData();

        // Get product classifications
        data.productClassifications = [
            SELECT Id, Name
            FROM ProductClassification
            ORDER BY Name
            LIMIT 200
        ];

        // Get rulesets
        try {
            data.rulesets = [
                SELECT Id, Name
                FROM Ruleset
                ORDER BY Name
                LIMIT 100
            ];
        } catch (Exception e) {
            // Ruleset may not be available in all orgs
            data.rulesets = new List<Ruleset>();
        }

        // Get product families
        data.productFamilies = getProductFamilyPicklist();

        return data;
    }

    /**
     * @description Generate suggested technical product details based on commercial product
     * @param commercialProductId The commercial product ID
     * @return Suggested technical product details
     */
    @AuraEnabled
    public static TechnicalProductSuggestion getSuggestedTechnicalProduct(String commercialProductId) {
        TechnicalProductSuggestion suggestion = new TechnicalProductSuggestion();

        Product2 commercial = [
            SELECT Id, Name, ProductCode, Description, Family,
                   Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c
            FROM Product2
            WHERE Id = :commercialProductId
            LIMIT 1
        ];

        // Generate suggested name and code
        suggestion.suggestedName = commercial.Name + ' - Technical';
        suggestion.suggestedCode = commercial.ProductCode + '-TECH';
        suggestion.suggestedDescription = 'Technical fulfillment product for ' + commercial.Name;
        suggestion.suggestedFamily = commercial.Family;
        // Inherit Workday integration fields from commercial product
        suggestion.workdaySalesItemId = commercial.Workday_Sales_Item_ID__c;
        suggestion.revCategory = commercial.Rev_Category__c;
        suggestion.financeBusinessUnit = commercial.Finance_Business_Unit__c;
        suggestion.fortraProductType = commercial.Fortra_Product_Type__c;

        // Check if suggested code already exists
        List<Product2> existing = [
            SELECT ProductCode FROM Product2 WHERE ProductCode = :suggestion.suggestedCode LIMIT 1
        ];
        if (!existing.isEmpty()) {
            // Append a number
            Integer counter = 1;
            String baseCode = suggestion.suggestedCode;
            while (!existing.isEmpty() && counter < 100) {
                counter++;
                suggestion.suggestedCode = baseCode + '-' + String.valueOf(counter);
                existing = [SELECT ProductCode FROM Product2 WHERE ProductCode = :suggestion.suggestedCode LIMIT 1];
            }
        }

        return suggestion;
    }

    /**
     * @description Bulk generate suggested technical products for multiple commercial products
     * @param commercialProductIds List of commercial product IDs
     * @return Map of commercial product ID to suggestion
     */
    @AuraEnabled
    public static Map<String, TechnicalProductSuggestion> getBulkSuggestedTechnicalProducts(List<String> commercialProductIds) {
        Map<String, TechnicalProductSuggestion> suggestions = new Map<String, TechnicalProductSuggestion>();

        if (commercialProductIds == null || commercialProductIds.isEmpty()) {
            return suggestions;
        }

        List<Product2> commercialProducts = [
            SELECT Id, Name, ProductCode, Description, Family,
                   Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c
            FROM Product2
            WHERE Id IN :commercialProductIds
        ];

        // Collect all potential codes to check for existence
        Set<String> potentialCodes = new Set<String>();
        for (Product2 p : commercialProducts) {
            potentialCodes.add(p.ProductCode + '-TECH');
        }

        // Check existing codes
        Set<String> existingCodes = new Set<String>();
        for (Product2 existing : [SELECT ProductCode FROM Product2 WHERE ProductCode IN :potentialCodes]) {
            existingCodes.add(existing.ProductCode);
        }

        // Generate suggestions
        for (Product2 commercial : commercialProducts) {
            TechnicalProductSuggestion suggestion = new TechnicalProductSuggestion();
            suggestion.suggestedName = commercial.Name + ' - Technical';
            suggestion.suggestedCode = commercial.ProductCode + '-TECH';
            suggestion.suggestedDescription = 'Technical fulfillment product for ' + commercial.Name;
            suggestion.suggestedFamily = commercial.Family;
            // Inherit Workday integration fields from commercial product
            suggestion.workdaySalesItemId = commercial.Workday_Sales_Item_ID__c;
            suggestion.revCategory = commercial.Rev_Category__c;
            suggestion.financeBusinessUnit = commercial.Finance_Business_Unit__c;
            suggestion.fortraProductType = commercial.Fortra_Product_Type__c;

            // Handle code conflicts
            if (existingCodes.contains(suggestion.suggestedCode)) {
                Integer counter = 1;
                String baseCode = suggestion.suggestedCode;
                while (existingCodes.contains(suggestion.suggestedCode) && counter < 100) {
                    counter++;
                    suggestion.suggestedCode = baseCode + '-' + String.valueOf(counter);
                }
            }
            existingCodes.add(suggestion.suggestedCode); // Prevent duplicates within this batch

            suggestions.put(commercial.Id, suggestion);
        }

        return suggestions;
    }

    /**
     * @description Get product family picklist values
     */
    private static List<String> getProductFamilyPicklist() {
        List<String> families = new List<String>();
        Schema.DescribeFieldResult fieldResult = Product2.Family.getDescribe();

        for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
            if (entry.isActive()) {
                families.add(entry.getValue());
            }
        }

        return families;
    }

    // ========== Wrapper Classes ==========

    public class CommercialProductWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public String productType { get; set; }
        @AuraEnabled public String decompositionScope { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Boolean hasExistingTechnicalProducts { get; set; }
        @AuraEnabled public Integer existingTechProductCount { get; set; }
        @AuraEnabled public List<TechnicalProductInfo> existingTechnicalProducts { get; set; }
        // Workday integration fields - inherited by technical products
        @AuraEnabled public String workdaySalesItemId { get; set; }
        @AuraEnabled public String revCategory { get; set; }
        @AuraEnabled public String financeBusinessUnit { get; set; }
        @AuraEnabled public String fortraProductType { get; set; }
    }

    public class TechnicalProductInfo {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public Integer priority { get; set; }
        @AuraEnabled public String decompRuleId { get; set; }
    }

    public class TechnicalProductSuggestion {
        @AuraEnabled public String suggestedName { get; set; }
        @AuraEnabled public String suggestedCode { get; set; }
        @AuraEnabled public String suggestedDescription { get; set; }
        @AuraEnabled public String suggestedFamily { get; set; }
        // Workday integration fields - inherited from commercial product
        @AuraEnabled public String workdaySalesItemId { get; set; }
        @AuraEnabled public String revCategory { get; set; }
        @AuraEnabled public String financeBusinessUnit { get; set; }
        @AuraEnabled public String fortraProductType { get; set; }
    }

    public class ReferenceData {
        @AuraEnabled public List<ProductClassification> productClassifications { get; set; }
        @AuraEnabled public List<Ruleset> rulesets { get; set; }
        @AuraEnabled public List<String> productFamilies { get; set; }
    }

    // ========== Spreadsheet Parsing Methods ==========

    /**
     * @description Parse uploaded spreadsheet (CSV format) for technical product creation
     * Expected columns: ProductCode, TechnicalProductName, TechnicalProductCode, Description, Family, Priority
     * ProductCode is required (lookup key), other columns are optional overrides
     * @param csvContent Base64 encoded CSV content
     * @param fileName Original filename for format detection
     * @return SpreadsheetParseResult with parsed rows and any errors/warnings
     */
    @AuraEnabled
    public static SpreadsheetParseResult parseSpreadsheet(String csvContent, String fileName) {
        SpreadsheetParseResult result = new SpreadsheetParseResult();
        result.success = false;
        result.rows = new List<SpreadsheetRow>();
        result.errors = new List<String>();
        result.warnings = new List<String>();
        result.validatedProducts = new List<CommercialProductWrapper>();

        if (String.isBlank(csvContent)) {
            result.errors.add('No file content provided');
            return result;
        }

        try {
            // Decode base64 content
            String decodedContent;
            try {
                decodedContent = EncodingUtil.base64Decode(csvContent).toString();
            } catch (Exception e) {
                // Try treating it as plain text
                decodedContent = csvContent;
            }

            // Parse CSV
            List<List<String>> csvData = parseCSV(decodedContent);

            if (csvData.isEmpty()) {
                result.errors.add('File is empty or could not be parsed');
                return result;
            }

            // Get header row
            List<String> headers = csvData[0];
            Map<String, Integer> headerMap = new Map<String, Integer>();
            for (Integer i = 0; i < headers.size(); i++) {
                headerMap.put(headers[i].toLowerCase().trim(), i);
            }

            // Validate required columns
            if (!headerMap.containsKey('productcode')) {
                result.errors.add('Required column "ProductCode" not found in spreadsheet');
                return result;
            }

            // Parse data rows
            Set<String> productCodes = new Set<String>();
            for (Integer i = 1; i < csvData.size(); i++) {
                List<String> row = csvData[i];

                // Skip empty rows
                if (row.isEmpty() || String.isBlank(String.join(row, ''))) {
                    continue;
                }

                SpreadsheetRow spreadsheetRow = new SpreadsheetRow();
                spreadsheetRow.rowNumber = i + 1;

                // Get ProductCode (required)
                Integer codeIdx = headerMap.get('productcode');
                if (codeIdx < row.size()) {
                    spreadsheetRow.productCode = row[codeIdx].trim();
                }

                if (String.isBlank(spreadsheetRow.productCode)) {
                    result.warnings.add('Row ' + (i + 1) + ': Missing ProductCode, skipping');
                    continue;
                }

                productCodes.add(spreadsheetRow.productCode);

                // Get optional override fields
                if (headerMap.containsKey('technicalproductname')) {
                    Integer idx = headerMap.get('technicalproductname');
                    if (idx < row.size()) {
                        spreadsheetRow.technicalProductName = row[idx].trim();
                    }
                }

                if (headerMap.containsKey('technicalproductcode')) {
                    Integer idx = headerMap.get('technicalproductcode');
                    if (idx < row.size()) {
                        spreadsheetRow.technicalProductCode = row[idx].trim();
                    }
                }

                if (headerMap.containsKey('description')) {
                    Integer idx = headerMap.get('description');
                    if (idx < row.size()) {
                        spreadsheetRow.description = row[idx].trim();
                    }
                }

                if (headerMap.containsKey('family')) {
                    Integer idx = headerMap.get('family');
                    if (idx < row.size()) {
                        spreadsheetRow.family = row[idx].trim();
                    }
                }

                if (headerMap.containsKey('priority')) {
                    Integer idx = headerMap.get('priority');
                    if (idx < row.size() && String.isNotBlank(row[idx])) {
                        try {
                            spreadsheetRow.priority = Integer.valueOf(row[idx].trim());
                        } catch (Exception e) {
                            result.warnings.add('Row ' + (i + 1) + ': Invalid priority value, using default');
                        }
                    }
                }

                result.rows.add(spreadsheetRow);
            }

            // Validate product codes exist and get product details
            if (!productCodes.isEmpty()) {
                Map<String, Product2> productMap = new Map<String, Product2>();
                for (Product2 p : [
                    SELECT Id, Name, ProductCode, Description, Family, Type,
                           DecompositionScope, IsActive,
                           Workday_Sales_Item_ID__c, Rev_Category__c, Finance_Business_Unit__c, Fortra_Product_Type__c,
                           (SELECT Id FROM SourceProduct)
                    FROM Product2
                    WHERE ProductCode IN :productCodes
                    AND IsActive = true
                ]) {
                    productMap.put(p.ProductCode, p);
                }

                // Validate each row
                for (SpreadsheetRow row : result.rows) {
                    if (!productMap.containsKey(row.productCode)) {
                        row.isValid = false;
                        row.validationError = 'Product not found or inactive';
                    } else {
                        Product2 p = productMap.get(row.productCode);
                        row.isValid = true;
                        row.productId = p.Id;
                        row.productName = p.Name;

                        // Build CommercialProductWrapper for validated products
                        CommercialProductWrapper wrapper = new CommercialProductWrapper();
                        wrapper.id = p.Id;
                        wrapper.name = p.Name;
                        wrapper.productCode = p.ProductCode;
                        wrapper.description = p.Description;
                        wrapper.family = p.Family;
                        wrapper.productType = p.Type;
                        wrapper.decompositionScope = p.DecompositionScope;
                        wrapper.isActive = p.IsActive;
                        wrapper.hasExistingTechnicalProducts = p.SourceProduct != null &&
                                                                !p.SourceProduct.isEmpty();
                        wrapper.existingTechProductCount = p.SourceProduct != null ?
                                                            p.SourceProduct.size() : 0;
                        // Workday integration fields
                        wrapper.workdaySalesItemId = p.Workday_Sales_Item_ID__c;
                        wrapper.revCategory = p.Rev_Category__c;
                        wrapper.financeBusinessUnit = p.Finance_Business_Unit__c;
                        wrapper.fortraProductType = p.Fortra_Product_Type__c;

                        // Add warning for products with existing tech products
                        if (wrapper.hasExistingTechnicalProducts) {
                            result.warnings.add('Product ' + p.ProductCode + ' already has ' +
                                wrapper.existingTechProductCount + ' technical product(s)');
                        }

                        result.validatedProducts.add(wrapper);
                    }
                }
            }

            result.success = result.rows.size() > 0;
            result.validRowCount = 0;
            for (SpreadsheetRow row : result.rows) {
                if (row.isValid) {
                    result.validRowCount++;
                }
            }

        } catch (Exception e) {
            result.errors.add('Error parsing spreadsheet: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Generate CSV template for technical product upload
     * @return Base64 encoded CSV template content
     */
    @AuraEnabled
    public static String getSpreadsheetTemplate() {
        String template = 'ProductCode,TechnicalProductName,TechnicalProductCode,Description,Family,Priority\n';
        template += 'EXAMPLE-001,"Example Product (Technical)",EXAMPLE-001-TECH,"Technical fulfillment product",Software,1\n';
        template += '# ProductCode is required - used to lookup the commercial product\n';
        template += '# Other columns are optional - if blank, values will be auto-generated\n';

        return EncodingUtil.base64Encode(Blob.valueOf(template));
    }

    /**
     * @description Parse CSV content into a 2D array
     * Handles quoted fields and embedded commas
     * @param csvContent Raw CSV string
     * @return List of rows, each row is a list of field values
     */
    private static List<List<String>> parseCSV(String csvContent) {
        List<List<String>> result = new List<List<String>>();

        if (String.isBlank(csvContent)) {
            return result;
        }

        // Normalize line endings
        csvContent = csvContent.replace('\r\n', '\n').replace('\r', '\n');

        List<String> lines = csvContent.split('\n');

        for (String line : lines) {
            // Skip comment lines
            if (line.startsWith('#')) {
                continue;
            }

            List<String> row = parseCSVLine(line);
            if (!row.isEmpty()) {
                result.add(row);
            }
        }

        return result;
    }

    /**
     * @description Parse a single CSV line, handling quoted fields
     * @param line Single line of CSV
     * @return List of field values
     */
    private static List<String> parseCSVLine(String line) {
        List<String> fields = new List<String>();

        if (String.isBlank(line)) {
            return fields;
        }

        Boolean inQuotes = false;
        String currentField = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    // Escaped quote
                    currentField += '"';
                    i++;
                } else {
                    // Toggle quote mode
                    inQuotes = !inQuotes;
                }
            } else if (c == ',' && !inQuotes) {
                // End of field
                fields.add(currentField.trim());
                currentField = '';
            } else {
                currentField += c;
            }
        }

        // Add last field
        fields.add(currentField.trim());

        return fields;
    }

    // ========== Spreadsheet Wrapper Classes ==========

    public class SpreadsheetParseResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public List<SpreadsheetRow> rows { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
        @AuraEnabled public List<CommercialProductWrapper> validatedProducts { get; set; }
        @AuraEnabled public Integer validRowCount { get; set; }
    }

    public class SpreadsheetRow {
        @AuraEnabled public Integer rowNumber { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public String productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String technicalProductName { get; set; }
        @AuraEnabled public String technicalProductCode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String family { get; set; }
        @AuraEnabled public Integer priority { get; set; }
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public String validationError { get; set; }
    }
}