public with sharing class LkgHardwareKeyService {
    public static void addKeyDataFromAsset(
        LkgMapperHardwareBase.AssetData assetData,
        LkgRequestBuilderBase.KeyData keyData
    ) {
        System.debug(LoggingLevel.DEBUG, '=== LkgHardwareKeyService.addKeyDataFromAsset START ===');

        if (assetData == null) {
            System.debug(LoggingLevel.WARN, 'AssetData is null');
            return;
        }

        if (assetData.productData == null) {
            System.debug(LoggingLevel.WARN, 'AssetData.productData is null');
            System.debug(LoggingLevel.DEBUG, 'AssetData: ' + JSON.serializePretty(assetData));
            return;
        }

        if (keyData == null) {
            System.debug(LoggingLevel.WARN, 'KeyData is null');
            System.debug(LoggingLevel.DEBUG, 'AssetData: ' + JSON.serializePretty(assetData));
            return;
        }

        System.debug(
            LoggingLevel.DEBUG,
            'Incoming AssetData: ' + JSON.serializePretty(assetData)
        );
        System.debug(
            LoggingLevel.DEBUG,
            'Incoming KeyData (before mapping): ' + JSON.serializePretty(keyData)
        );

        // 1) Map common/base fields first
        addCommonKeyDataFromAsset(assetData, keyData);

        System.debug(
            LoggingLevel.DEBUG,
            'KeyData after common mapping: ' + JSON.serializePretty(keyData)
        );

        // 2) Resolve silo-specific builder
        String silo = assetData.productData.silo;
        System.debug(LoggingLevel.DEBUG, 'Resolved silo from assetData.productData.silo = ' + silo);

        ILkgHardwareKeyParamBuilder paramBuilder =
            LkgHardwareKeyParamBuilderFactory.getBuilder(silo);

        if (paramBuilder == null) {
            System.debug(
                LoggingLevel.WARN,
                'No hardware key param builder found for silo: ' + silo
            );
            System.debug(LoggingLevel.DEBUG, '=== LkgHardwareKeyService.addKeyDataFromAsset END ===');
            return;
        }

        System.debug(
            LoggingLevel.DEBUG,
            'Resolved hardware key param builder: ' + String.valueOf(paramBuilder)
        );

        // 3) Add silo-specific fields
        paramBuilder.addKeyDataFromAsset(assetData, keyData);

        System.debug(
            LoggingLevel.DEBUG,
            'KeyData after silo-specific mapping: ' + JSON.serializePretty(keyData)
        );
        System.debug(LoggingLevel.DEBUG, '=== LkgHardwareKeyService.addKeyDataFromAsset END ===');
    }

    private static void addCommonKeyDataFromAsset(
        LkgMapperHardwareBase.AssetData assetData,
        LkgRequestBuilderBase.KeyData keyData
    ) {
        if (assetData == null || assetData.productData == null || keyData == null) {
            System.debug(
                LoggingLevel.WARN,
                'Skipping common key mapping because assetData, productData, or keyData is null'
            );
            return;
        }

        System.debug(LoggingLevel.DEBUG, '--- Common key mapping START ---');
        System.debug(
            LoggingLevel.DEBUG,
            'productData.silo = ' + assetData.productData.silo
        );
        System.debug(
            LoggingLevel.DEBUG,
            'productData.subSilo = ' + assetData.productData.subSilo
        );
        System.debug(
            LoggingLevel.DEBUG,
            'productData.productCode = ' + assetData.productData.productCode
        );
        System.debug(
            LoggingLevel.DEBUG,
            'assetData.productVersion = ' + assetData.productVersion
        );
        System.debug(
            LoggingLevel.DEBUG,
            'assetData.hardwareId = ' + assetData.hardwareId
        );

        // These two are the most important because request-builder factory routing
        // depends on them later.
        keyData.Silo = assetData.productData.silo;
        keyData.subSilo = assetData.productData.subSilo;
        keyData.HardwareId = assetData.hardwareId != null ? String.valueOf(assetData.hardwareId) : null;
        keyData.serialNumber = assetData.serialNumber;

        // Product information
        keyData.ProductCode = assetData.productData.productCode;
        keyData.externalProductName = assetData.productData.externalName;
        keyData.internalProductName = assetData.productData.internalName; // May be overridden by subclasses

    // Silo will be determined by subclass based on product/metadata

    // Default settings
        keyData.createLicenseKeyFile = false;

        // Add more common/base mappings here only if these fields
        // actually exist on your concrete/base KeyData classes.
        //
        // Examples:
        // keyData.productCode = assetData.productData.productCode;
        // keyData.version = assetData.productVersion;
        // keyData.hardwareId = String.valueOf(assetData.hardwareId);

        System.debug(
            LoggingLevel.DEBUG,
            'Mapped common fields -> keyData.Silo=' + keyData.Silo +
            ', keyData.subSilo=' + keyData.subSilo
        );
        System.debug(LoggingLevel.DEBUG, '--- Common key mapping END ---');
    }
}