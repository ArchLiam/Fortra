public with sharing class LkgHardwareKeyDataFactory {
    public static LkgRequestBuilderBase.KeyData createKeyDataInstance(
        LkgMapperHardwareBase.AssetData assetData
    ) {
        if (assetData == null || assetData.productData == null) {
            return null;
        }

        String silo = assetData.productData.silo;
        String subSilo = assetData.productData.subSilo;

        if (String.isBlank(silo)) {
            return null;
        }

        switch on silo.toLowerCase() {
            when 'automate' {
                return new LkgRequestBuilderAutomate.AutomateKeyData();
            }

            

            when else {
                return null;
            }
        }
    }
}