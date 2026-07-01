/**
 * @description Controller class for RCA Product Creator LWC
 * Provides methods for file parsing, validation, and product creation
 *
 * @author Coastal - Fortra RCA Migration
 * @date 2024-12
 */
public with sharing class RCAProductCreationController {

    /**
     * @description Parse CSV content and return product requests
     * @param csvContent Base64 encoded CSV content
     * @param mappingConfig Column mapping configuration
     * @return ParseResult with parsed products and any errors
     */
    @AuraEnabled
    public static ParseResult parseCSVFile(String csvContent, String mappingConfig) {
        ParseResult result = new ParseResult();

        try {
            // Decode base64 content
            String decodedContent = EncodingUtil.base64Decode(csvContent).toString();

            // Parse CSV
            List<List<String>> csvData = parseCSV(decodedContent);

            if (csvData.isEmpty()) {
                result.success = false;
                result.errorMessage = 'CSV file is empty';
                return result;
            }

            // Get headers
            List<String> headers = csvData[0];
            result.headers = headers;

            // Parse mapping config
            Map<String, Object> mapping = (Map<String, Object>) JSON.deserializeUntyped(mappingConfig);

            // Parse data rows
            for (Integer i = 1; i < csvData.size(); i++) {
                List<String> row = csvData[i];
                if (isEmptyRow(row)) continue;

                try {
                    RCAProductCreationService.ProductRequest req = parseRow(row, headers, mapping);
                    result.products.add(req);
                } catch (Exception e) {
                    result.warnings.add('Row ' + (i + 1) + ': ' + e.getMessage());
                }
            }

            result.success = true;
            result.totalRows = csvData.size() - 1;
            result.parsedRows = result.products.size();

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Failed to parse CSV: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Parse Excel content (simplified - expects CSV export)
     */
    @AuraEnabled
    public static ParseResult parseExcelFile(String fileContent, String mappingConfig) {
        // For Excel, we'll convert to CSV format first
        // In a production scenario, you'd use a library like Apache POI via External Services
        // For now, we'll handle it as CSV
        return parseCSVFile(fileContent, mappingConfig);
    }

    /**
     * @description Validate parsed products
     */
    @AuraEnabled
    public static List<String> validateProducts(List<RCAProductCreationService.ProductRequest> products) {
        return RCAProductCreationService.validateRequests(products);
    }

    /**
     * @description Create products from requests
     */
    @AuraEnabled
    public static RCAProductCreationService.BatchCreationResult createProducts(
        List<RCAProductCreationService.ProductRequest> products
    ) {
        return RCAProductCreationService.createProducts(products);
    }

    /**
     * @description Get reference data for the UI
     */
    @AuraEnabled(cacheable=true)
    public static ReferenceData getReferenceData() {
        ReferenceData data = new ReferenceData();

        // Get selling models
        data.sellingModels = [
            SELECT Id, Name, SellingModelType, PricingTerm, PricingTermUnit, Status
            FROM ProductSellingModel
            WHERE Status = 'Active'
            ORDER BY Name
        ];

        // Get catalogs
        data.catalogs = [SELECT Id, Name FROM ProductCatalog ORDER BY Name];

        // Get categories
        data.categories = [
            SELECT Id, Name, ParentCategoryId, CatalogId
            FROM ProductCategory
            ORDER BY Name
        ];

        // Get pricebooks
        data.pricebooks = [
            SELECT Id, Name, IsStandard, IsActive
            FROM Pricebook2
            WHERE IsActive = true
            ORDER BY IsStandard DESC, Name
        ];

        // Get product families
        data.productFamilies = getProductFamilyPicklist();

        return data;
    }

    /**
     * @description Get existing products for bundle component selection
     */
    @AuraEnabled(cacheable=true)
    public static List<Product2> searchProducts(String searchTerm) {
        String search = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [
            SELECT Id, Name, ProductCode, Family, IsActive
            FROM Product2
            WHERE (Name LIKE :search OR ProductCode LIKE :search)
            AND IsActive = true
            ORDER BY Name
            LIMIT 50
        ];
    }

    /**
     * @description Get sample CSV template
     */
    @AuraEnabled(cacheable=true)
    public static String getCSVTemplate() {
        List<String> headers = new List<String>{
            'Name',
            'ProductCode',
            'Description',
            'ProductType',
            'Family',
            'IsActive',
            'UnitPrice',
            'SellingModel',
            'Category',
            'BundleComponents'
        };

        List<String> sampleRow = new List<String>{
            'Sample Product',
            'PROD-001',
            'Sample product description',
            'Simple',
            'Software',
            'TRUE',
            '99.99',
            'Term Based - Annual',
            'Defensive Security',
            ''
        };

        List<String> bundleRow = new List<String>{
            'Sample Bundle',
            'BUNDLE-001',
            'Sample bundle product',
            'Bundle',
            'Software',
            'TRUE',
            '199.99',
            'Term Based - Annual',
            'Defensive Security',
            'PROD-001:1:5:1|PROD-002:0:10:1'
        };

        return String.join(headers, ',') + '\n' +
               String.join(sampleRow, ',') + '\n' +
               String.join(bundleRow, ',');
    }

    /**
     * @description Get column mapping configuration
     */
    @AuraEnabled(cacheable=true)
    public static List<ColumnMapping> getDefaultColumnMappings() {
        return new List<ColumnMapping>{
            new ColumnMapping('Name', 'name', true, 'Product Name'),
            new ColumnMapping('ProductCode', 'productCode', true, 'Unique Product Code'),
            new ColumnMapping('Description', 'description', false, 'Product Description'),
            new ColumnMapping('ProductType', 'productType', false, 'Simple or Bundle'),
            new ColumnMapping('Family', 'family', false, 'Product Family'),
            new ColumnMapping('IsActive', 'isActive', false, 'TRUE/FALSE'),
            new ColumnMapping('UnitPrice', 'unitPrice', false, 'Base Price'),
            new ColumnMapping('SellingModel', 'sellingModel', false, 'Selling Model Name'),
            new ColumnMapping('Category', 'category', false, 'Category Name'),
            new ColumnMapping('Catalog', 'catalog', false, 'Catalog Name'),
            new ColumnMapping('Pricebooks', 'pricebooks', false, 'Pricebook Names (pipe-separated)'),
            new ColumnMapping('BundleComponents', 'bundleComponents', false, 'Component definitions')
        };
    }

    // ========== Helper Methods ==========

    /**
     * @description Parse CSV content into rows and columns
     */
    private static List<List<String>> parseCSV(String content) {
        List<List<String>> result = new List<List<String>>();

        // Normalize line endings
        content = content.replace('\r\n', '\n').replace('\r', '\n');

        List<String> lines = content.split('\n');

        for (String line : lines) {
            if (String.isNotBlank(line)) {
                result.add(parseCSVLine(line));
            }
        }

        return result;
    }

    /**
     * @description Parse a single CSV line handling quoted values
     */
    private static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();
        Boolean inQuotes = false;
        String currentValue = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                if (inQuotes && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    // Escaped quote
                    currentValue += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (c == ',' && !inQuotes) {
                values.add(currentValue.trim());
                currentValue = '';
            } else {
                currentValue += c;
            }
        }

        values.add(currentValue.trim());
        return values;
    }

    /**
     * @description Check if a row is empty
     */
    private static Boolean isEmptyRow(List<String> row) {
        for (String cell : row) {
            if (String.isNotBlank(cell)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @description Parse a row into a ProductRequest
     */
    private static RCAProductCreationService.ProductRequest parseRow(
        List<String> row,
        List<String> headers,
        Map<String, Object> mapping
    ) {
        RCAProductCreationService.ProductRequest req = new RCAProductCreationService.ProductRequest();

        // Build value map
        Map<String, String> valueMap = new Map<String, String>();
        for (Integer i = 0; i < headers.size() && i < row.size(); i++) {
            valueMap.put(headers[i].toLowerCase().trim(), row[i]);
        }

        // Map values to request
        req.name = getMapValue(valueMap, mapping, 'name');
        req.productCode = getMapValue(valueMap, mapping, 'productCode');
        req.description = getMapValue(valueMap, mapping, 'description');
        req.productType = getMapValue(valueMap, mapping, 'productType');
        req.family = getMapValue(valueMap, mapping, 'family');

        String isActiveStr = getMapValue(valueMap, mapping, 'isActive');
        req.isActive = String.isBlank(isActiveStr) || isActiveStr.equalsIgnoreCase('true') ||
                       isActiveStr.equalsIgnoreCase('yes') || isActiveStr == '1';

        String priceStr = getMapValue(valueMap, mapping, 'unitPrice');
        if (String.isNotBlank(priceStr)) {
            req.unitPrice = Decimal.valueOf(priceStr.replace('$', '').replace(',', ''));
        }

        // Parse selling models
        String sellingModelStr = getMapValue(valueMap, mapping, 'sellingModel');
        if (String.isNotBlank(sellingModelStr)) {
            req.sellingModelIds = resolveSellingModelIds(sellingModelStr);
        }

        // Parse category
        String categoryStr = getMapValue(valueMap, mapping, 'category');
        if (String.isNotBlank(categoryStr)) {
            req.categoryId = resolveCategoryId(categoryStr);
        }

        // Parse catalog
        String catalogStr = getMapValue(valueMap, mapping, 'catalog');
        if (String.isNotBlank(catalogStr)) {
            req.catalogId = resolveCatalogId(catalogStr);
        }

        // Parse pricebooks
        String pricebooksStr = getMapValue(valueMap, mapping, 'pricebooks');
        if (String.isNotBlank(pricebooksStr)) {
            req.pricebookIds = resolvePricebookIds(pricebooksStr);
        }

        // Parse bundle components
        String componentsStr = getMapValue(valueMap, mapping, 'bundleComponents');
        if (String.isNotBlank(componentsStr)) {
            req.bundleComponents = parseBundleComponents(componentsStr);
        }

        return req;
    }

    /**
     * @description Get value from map using mapping config
     */
    private static String getMapValue(Map<String, String> valueMap, Map<String, Object> mapping, String field) {
        String columnName = mapping.containsKey(field) ? (String) mapping.get(field) : field;
        return valueMap.get(columnName.toLowerCase().trim());
    }

    /**
     * @description Resolve selling model names to IDs
     */
    private static List<String> resolveSellingModelIds(String modelStr) {
        List<String> ids = new List<String>();
        List<String> names = modelStr.split('\\|');

        Map<String, Id> modelMap = new Map<String, Id>();
        for (ProductSellingModel psm : [SELECT Id, Name FROM ProductSellingModel WHERE Status = 'Active']) {
            modelMap.put(psm.Name.toLowerCase(), psm.Id);
        }

        for (String name : names) {
            String normalizedName = name.trim().toLowerCase();
            if (modelMap.containsKey(normalizedName)) {
                ids.add(modelMap.get(normalizedName));
            } else if (name.trim().startsWith('0jP')) {
                // Already an ID
                ids.add(name.trim());
            }
        }

        return ids;
    }

    /**
     * @description Resolve category name to ID
     */
    private static String resolveCategoryId(String categoryStr) {
        for (ProductCategory pc : [SELECT Id, Name FROM ProductCategory WHERE Name = :categoryStr LIMIT 1]) {
            return pc.Id;
        }
        // If it looks like an ID, return it
        if (categoryStr.startsWith('0ZG')) {
            return categoryStr;
        }
        return null;
    }

    /**
     * @description Resolve catalog name to ID
     */
    private static String resolveCatalogId(String catalogStr) {
        for (ProductCatalog cat : [SELECT Id, Name FROM ProductCatalog WHERE Name = :catalogStr LIMIT 1]) {
            return cat.Id;
        }
        // If it looks like an ID, return it
        if (catalogStr.startsWith('0ZS')) {
            return catalogStr;
        }
        return null;
    }

    /**
     * @description Resolve pricebook names to IDs
     */
    private static List<String> resolvePricebookIds(String pricebooksStr) {
        List<String> ids = new List<String>();
        List<String> names = pricebooksStr.split('\\|');

        Map<String, Id> pbMap = new Map<String, Id>();
        for (Pricebook2 pb : [SELECT Id, Name FROM Pricebook2 WHERE IsActive = true]) {
            pbMap.put(pb.Name.toLowerCase(), pb.Id);
        }

        for (String name : names) {
            String normalizedName = name.trim().toLowerCase();
            if (pbMap.containsKey(normalizedName)) {
                ids.add(pbMap.get(normalizedName));
            } else if (name.trim().startsWith('01s')) {
                ids.add(name.trim());
            }
        }

        return ids;
    }

    /**
     * @description Parse bundle components string
     * Format: ProductCode:MinQty:MaxQty:DefaultQty|ProductCode:MinQty:MaxQty:DefaultQty
     */
    private static List<RCAProductCreationService.BundleComponent> parseBundleComponents(String componentsStr) {
        List<RCAProductCreationService.BundleComponent> components = new List<RCAProductCreationService.BundleComponent>();

        List<String> componentDefs = componentsStr.split('\\|');
        Integer seq = 0;

        for (String def : componentDefs) {
            List<String> parts = def.split(':');
            if (parts.size() >= 1) {
                RCAProductCreationService.BundleComponent comp = new RCAProductCreationService.BundleComponent();
                comp.childProductCode = parts[0].trim();
                comp.minQuantity = parts.size() > 1 ? Integer.valueOf(parts[1].trim()) : 0;
                comp.maxQuantity = parts.size() > 2 ? Integer.valueOf(parts[2].trim()) : 999;
                comp.defaultQuantity = parts.size() > 3 ? Integer.valueOf(parts[3].trim()) : 1;
                comp.isRequired = comp.minQuantity > 0;
                comp.sortOrder = seq++;
                comp.groupName = 'Default';
                components.add(comp);
            }
        }

        return components;
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

    public class ParseResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<String> headers { get; set; }
        @AuraEnabled public List<RCAProductCreationService.ProductRequest> products { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
        @AuraEnabled public Integer totalRows { get; set; }
        @AuraEnabled public Integer parsedRows { get; set; }

        public ParseResult() {
            this.success = false;
            this.headers = new List<String>();
            this.products = new List<RCAProductCreationService.ProductRequest>();
            this.warnings = new List<String>();
        }
    }

    public class ReferenceData {
        @AuraEnabled public List<ProductSellingModel> sellingModels { get; set; }
        @AuraEnabled public List<ProductCatalog> catalogs { get; set; }
        @AuraEnabled public List<ProductCategory> categories { get; set; }
        @AuraEnabled public List<Pricebook2> pricebooks { get; set; }
        @AuraEnabled public List<String> productFamilies { get; set; }
    }

    public class ColumnMapping {
        @AuraEnabled public String csvColumn { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public String description { get; set; }

        public ColumnMapping(String csvColumn, String fieldName, Boolean required, String description) {
            this.csvColumn = csvColumn;
            this.fieldName = fieldName;
            this.required = required;
            this.description = description;
        }
    }
}