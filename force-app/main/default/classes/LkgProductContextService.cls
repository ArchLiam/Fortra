public with sharing class LkgProductContextService {

    //  ===============================
    //  SILO CACHE
    //  ===============================
    private static Map<String, LKG_Silo__mdt> siloById;

    private static Map<String, LKG_Silo__mdt> getSiloMap() {

        if (siloById == null) {

            siloById = new Map<String, LKG_Silo__mdt>();

            for (LKG_Silo__mdt s : [
                SELECT Id, Label
                FROM LKG_Silo__mdt
            ]) {
                siloById.put(String.valueOf(s.Id), s);
            }
        }

        return siloById;
    }

    //  ===============================
    //  MAIN METHOD
    //  ===============================
    public static LKGMapperBase.ProductData getProductData(
        String productKey
    ) {

        LKGMapperBase.ProductData data =
            new LKGMapperBase.ProductData();

        if (String.isBlank(productKey)) return data;

        String key = productKey.trim().toLowerCase();

        LKG_Product__mdt pMeta;
        //todo where clause
        for (LKG_Product__mdt p : [
            SELECT Id,
                   DeveloperName,
                   QualifiedApiName,
                   LKG_Silo__c,
                   Product_Code__c,
                   Internal_Product_Name__c,
                   License_Key_Product_Name__c
            FROM LKG_Product__mdt
        ]) {

            String dev = p.DeveloperName.toLowerCase();
            String qual = p.QualifiedApiName.toLowerCase();

            if (
                key == dev ||
                key == qual ||
                key.endsWith('.' + dev)
            ) {
                pMeta = p;
                break;
            }
        }

        if (pMeta == null) {
            System.debug('❌ Product metadata not found: ' + productKey);
            return data;
        }

        // Core fields
        data.productMetadataRecordId = String.valueOf(pMeta.Id);
        data.productCode = pMeta.Product_Code__c;
        data.internalName = pMeta.Internal_Product_Name__c;
        data.name = pMeta.Internal_Product_Name__c;
        data.identifierName = pMeta.DeveloperName;
        data.externalName = pMeta.License_Key_Product_Name__c;

        // Silo
        if (pMeta.LKG_Silo__c != null) {

            Map<String, LKG_Silo__mdt> silos = getSiloMap();
            String siloRef = String.valueOf(pMeta.LKG_Silo__c);

            if (silos.containsKey(siloRef)) {
                data.silo = silos.get(siloRef).Label;
            }
        }

        // ===============================
        // DYNAMIC DEFAULT ATTRIBUTES
        // ===============================
        Map<String, String> defaultAttributes =
            new Map<String, String>();

        
        for (LKG_UI_Field__mdt f : [
            SELECT MasterLabel,
                Default_Value__c,
                LKG_Product__c,
                Is_Hidden__c
            FROM LKG_UI_Field__mdt
            WHERE LKG_Product__c = :pMeta.Id
            AND Is_Hidden__c = true   
        ]) {


            if (String.isNotBlank(f.Default_Value__c)) {

                defaultAttributes.put(
                    f.MasterLabel,
                    f.Default_Value__c
                );
            }
        }

        data.defaultAttributes = defaultAttributes;

        System.debug('Default Attributes Loaded: ' + defaultAttributes);

        return data;
    }
    public static LKGMapperBase.ProductData getProductDataById(
    String metadataId
) {

    if (String.isBlank(metadataId)) {
        System.debug('❌ metadataId is blank');
        return null;
    }

    LKG_Product__mdt pMeta;

    // Query directly by Id
    for (LKG_Product__mdt p : [
        SELECT Id,
               DeveloperName
        FROM LKG_Product__mdt
        WHERE Id = :metadataId
        LIMIT 1
    ]) {
        pMeta = p;
    }

    if (pMeta == null) {
        System.debug('❌ No product metadata found for Id: ' + metadataId);
        return null;
    }


    return getProductData(pMeta.DeveloperName);
}
}