public with sharing class LkgHardwareAssetEnrichmentService {
    public class Result {
        public LkgMapperHardwareBase.AssetData assetData;
        public List<String> errors = new List<String>();
        public List<String> debugLog = new List<String>();
    }

    public static Result enrich(
        LkgMapperHardwareBase.AssetData assetData
    ) {
        Result res = new Result();
        res.assetData = assetData;

        if (assetData == null) {
            res.errors.add('AssetData is null');
            return res;
        }

        if (assetData.assetId == null || assetData.hardwareId == null) {
            res.errors.add('AssetData must include assetId and hardwareId.');
            return res;
        }

        res.debugLog.add(
            'Starting enrichment for hardwareId=' + assetData.hardwareId +
            ', assetId=' + assetData.assetId
        );

        String productMetadataId =
            resolveProductMetadataId(
                assetData.hardwareId,
                assetData.assetId,
                res
            );

        if (!res.errors.isEmpty()) {
            return res;
        }

        res.debugLog.add('Resolved productMetadataId=' + productMetadataId);
        System.debug('Resolved productMetadataId=' + productMetadataId);
        LKGMapperBase.ProductData pd =
            LkgProductContextService.getProductDataById(productMetadataId);

        if (pd == null || pd.productMetadataRecordId == null) {
            res.errors.add(
                'Product metadata not found for metadata id: ' + productMetadataId
            );
            return res;
        }

        res.debugLog.add(
            'Loaded ProductData with productMetadataRecordId=' +
            pd.productMetadataRecordId
        );

        LkgSystemAggregationService.SystemResult sr =
            LkgSystemAggregationService.aggregateSystem(
                assetData.hardwareId,
                pd.productMetadataRecordId,
                assetData.assetId
            );

        res.debugLog.add('Aggregation completed');

        if (sr != null && sr.warnings != null && !sr.warnings.isEmpty()) {
            res.debugLog.addAll(sr.warnings);
        }

        assetData.productData = pd;

        assetData.attributes = buildFlattenedAttributes(pd, sr, res);

        res.debugLog.add(
            'Final flattened attributes count=' +
            String.valueOf(
                assetData.attributes == null ? 0 : assetData.attributes.size()
            )
        );

        res.assetData = assetData;
        return res;
    }

    private static String resolveProductMetadataId(
        Id hardwareId,
        Id assetId,
        Result res
    ) {
        List<Asset> assets = [
            SELECT Id,
                   Hardware__c,
                   Name,
                   Product2.ProductCode
            FROM Asset
            WHERE Id = :assetId
            LIMIT 1
        ];

        if (assets.isEmpty()) {
            res.errors.add('Asset not found: ' + assetId);
            return null;
        }

        Asset a = assets[0];

        if (a.Hardware__c != hardwareId) {
            res.errors.add('Asset does not belong to the supplied hardware.');
            return null;
        }

        if (a.Product2 == null) {
            res.errors.add('Asset does not have an associated Product.');
            return null;
        }

        String key = a.Product2.ProductCode + ' | ' + a.Name;
        res.debugLog.add('Intersect match key=' + key);
        System.debug('Intersect match key=' + key);

        Set<String> productMetadataIds = new Set<String>();

        for (LKG_Intersect__mdt i : [
            SELECT Match_Description__c,
                   LKG_Product_Match__c,
                   LKG_SKU_Type__c
            FROM LKG_Intersect__mdt
            WHERE Match_Description__c = :key
        ]) {
            if (
                i.LKG_SKU_Type__c != null &&
                i.LKG_SKU_Type__c.trim().toLowerCase() == 'primary' &&
                !String.isBlank(i.LKG_Product_Match__c)
            ) {
                productMetadataIds.add(i.LKG_Product_Match__c);
            }
        }

        if (productMetadataIds.size() != 1) {
            res.errors.add(
                'Unable to resolve a single primary product metadata id. Found: ' +
                productMetadataIds.size()
            );
            return null;
        }

        return productMetadataIds.iterator().next();
    }

    private static Map<String, String> buildFlattenedAttributes(
        LKGMapperBase.ProductData pd,
        LkgSystemAggregationService.SystemResult sr,
        Result res
    ) {
        Map<String, String> finalAttributes = new Map<String, String>();

        // 1) Metadata defaults
        if (pd != null && pd.defaultAttributes != null) {
            mergeWithCollisionProtection(
                finalAttributes,
                pd.defaultAttributes,
                'def_'
            );
            res.debugLog.add(
                'Copied defaultAttributes count=' +
                String.valueOf(pd.defaultAttributes.size())
            );
        } else {
            res.debugLog.add('No defaultAttributes found');
        }

        // 2) Quantities
        Map<String, String> quantityAttributes =
            extractQuantityAttributes(sr, res);
        mergeWithCollisionProtection(
            finalAttributes,
            quantityAttributes,
            'qty_'
        );

        // 3) Actions
        Map<String, String> actionAttributes =
            extractActionAttributes(sr, res);
        mergeWithCollisionProtection(
            finalAttributes,
            actionAttributes,
            'act_'
        );

        return finalAttributes;
    }

    private static void mergeWithCollisionProtection(
        Map<String, String> target,
        Map<String, String> source,
        String prefix
    ) {
        if (source == null) {
            return;
        }

        for (String key : source.keySet()) {
            if (!target.containsKey(key)) {
                target.put(key, source.get(key));
            } else {
                target.put(prefix + key, source.get(key));
            }
        }
    }

    private static Map<String, String> extractQuantityAttributes(
        LkgSystemAggregationService.SystemResult sr,
        Result res
    ) {
        Map<String, String> result = new Map<String, String>();

        if (sr == null || sr.quantities == null || sr.quantities.isEmpty()) {
            res.debugLog.add('No quantity attributes found');
            return result;
        }

        for (String key : sr.quantities.keySet()) {
            Integer value = sr.quantities.get(key);
            if (value != null) {
                result.put(key, String.valueOf(value));
            }
        }

        res.debugLog.add(
            'Extracted quantity attributes count=' +
            String.valueOf(result.size())
        );

        return result;
    }

    private static Map<String, String> extractActionAttributes(
        LkgSystemAggregationService.SystemResult sr,
        Result res
    ) {
        Map<String, String> result = new Map<String, String>();

        if (sr == null || sr.actions == null || sr.actions.isEmpty()) {
            res.debugLog.add('No action attributes found');
            return result;
        }

        for (String key : sr.actions.keySet()) {
            Set<Integer> rawValues = sr.actions.get(key);
            if (rawValues == null || rawValues.isEmpty()) {
                continue;
            }

            List<Integer> sortedValues = new List<Integer>();
            sortedValues.addAll(rawValues);
            sortedValues.sort();

            // Serialize to string form like "[64,128]"
            result.put(key, JSON.serialize(sortedValues));
        }

        res.debugLog.add(
            'Extracted action attributes count=' +
            String.valueOf(result.size())
        );

        return result;
    }
}