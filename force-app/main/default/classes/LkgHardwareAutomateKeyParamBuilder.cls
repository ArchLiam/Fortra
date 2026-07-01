public with sharing class LkgHardwareAutomateKeyParamBuilder
    implements ILkgHardwareKeyParamBuilder {

    public void addKeyDataFromAsset(
        LkgMapperHardwareBase.AssetData assetData,
        LkgRequestBuilderBase.KeyData keyData
    ) {
        if (assetData == null || assetData.productData == null || keyData == null) {
            return;
        }

        if (!(keyData instanceof LkgRequestBuilderAutomate.AutomateKeyData)) {
            return;
        }

        LkgRequestBuilderAutomate.AutomateKeyData automateKeyData =
            (LkgRequestBuilderAutomate.AutomateKeyData) keyData;

        System.debug('---ILkgHardwareKeyParamBuilder KeyData:---');
        System.debug(JSON.serializePretty(keyData));
        System.debug('---ILkgHardwareKeyParamBuilder AssetData:---');
        System.debug(JSON.serializePretty(assetData));

        Map<String, String> attrs =
            assetData.attributes == null
            ? new Map<String, String>()
            : assetData.attributes;

        AutomatePointsBuilderContext pointsBuilderContext =
            new AutomatePointsBuilderContext();

        pointsBuilderContext.productCode = assetData.productData.productCode;
        pointsBuilderContext.tier = attrs.get('Tier');
        pointsBuilderContext.release = safeParseInt(assetData.productVersion);
        pointsBuilderContext.isGte11 =
            pointsBuilderContext.release >= 11 ||
            pointsBuilderContext.release == null;

        pointsBuilderContext.TActions = parseActions(attrs.get('T'));
        pointsBuilderContext.MActions = parseActions(attrs.get('M'));
        pointsBuilderContext.NActions = parseActions(attrs.get('N'));
        pointsBuilderContext.PActions = parseActions(attrs.get('P'));

        pointsBuilderContext.bots = safeParseInt(attrs.get('agents')) ?? 0;
        pointsBuilderContext.studios = safeParseInt(attrs.get('studios')) ?? 0 ;
        pointsBuilderContext.webSmcs = 0;
        System.debug(JSON.serializePretty(pointsBuilderContext));
        automateKeyData.HardwareId = assetData.hardwareId;
        automateKeyData.points = getPoints(pointsBuilderContext);
        automateKeyData.modification = assetData.productModification;
        System.debug('---ILkgHardwareKeyParamBuilder KeyData:---');
        System.debug(JSON.serializePretty(automateKeyData));
    }

    private String getPoints(AutomatePointsBuilderContext context) {
        ILkgAutomatePointsBuilder pointsBuilder =
            LkgAutomatePointsBuilderFactory.getBuilder(context);
        return pointsBuilder.build(context);
    }

    private Integer parseActions(String actionsString) {
        if (String.isBlank(actionsString) || actionsString == '[]') {
            return 0;
        }

        if (actionsString.startsWith('[') && actionsString.endsWith(']')) {
            String cleaned =
                actionsString.substring(1, actionsString.length() - 1)
                    .replaceAll('[\'\"]', '');

            List<String> actionValues = cleaned.split(',');
            Integer total = 0;

            if (actionValues != null && !actionValues.isEmpty()) {
                for (String value : actionValues) {
                    Integer actionInt = safeParseInt(value);
                    if (actionInt != null) {
                        total += actionInt;
                    }
                }
            }

            return total;
        }

        return safeParseInt(actionsString);
    }

    private Integer safeParseInt(String input) {
        if (String.isBlank(input)) {
            return null;
        }

        try {
            return Integer.valueOf(input.trim());
        } catch (Exception e) {
            return null;
        }
    }
}