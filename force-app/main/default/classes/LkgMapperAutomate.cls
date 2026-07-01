public with sharing class LkgMapperAutomate extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderAutomate.AutomateKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderAutomate.AutomateKeyData automateKeyData = (LkgRequestBuilderAutomate.AutomateKeyData) keyData;
    AutomatePointsBuilderContext pointsBuilderContext = new AutomatePointsBuilderContext();
    pointsBuilderContext.productCode = uiPayload.productData.productCode;
    pointsBuilderContext.tier = uiPayload.attributes.get(product + '_Tier');
    pointsBuilderContext.release = safeParseInt(uiPayload.attributes.get(silo + '_Release'));
    pointsBuilderContext.isGte11 = pointsBuilderContext.release >= 11 || pointsBuilderContext.release == null;
    pointsBuilderContext.TActions = parseActions(uiPayload.attributes.get(product + '_Actions_T'));
    pointsBuilderContext.MActions = parseActions(uiPayload.attributes.get(product + '_Actions_M'));
    pointsBuilderContext.NActions = parseActions(uiPayload.attributes.get(product + '_Actions_N'));
    pointsBuilderContext.PActions = parseActions(uiPayload.attributes.get(product + '_Actions_P'));
    pointsBuilderContext.bots = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Bots'));
    pointsBuilderContext.studios = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Studios'));
    pointsBuilderContext.webSmcs = safeParseInt(uiPayload.attributes.get(product + '_Number_of_BPA_WebSMCs'));

    automateKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    automateKeyData.points = getPoints(pointsBuilderContext);
    automateKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
  }

  private String getPoints(AutomatePointsBuilderContext context) {
    ILkgAutomatePointsBuilder pointsBuilder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    return pointsBuilder.build(context);
  }

  private Integer parseActions(string actionsString) {
    if (String.isBlank(actionsString) || actionsString == '[]') {
      return 0;
    }

    if (actionsString.startsWith('[') && actionsString.endsWith(']')) {
      String cleaned = actionsString.substring(1, actionsString.length() - 1).replaceAll('[\'\"]', '');
      List<String> actionValues = cleaned.split(',');
      Integer total = 0;
      if (actionValues != null && actionValues.size() > 0) {
        for (String value : actionValues) {
          System.debug('Parsing action value: ' + value);
          Integer actionInt = safeParseInt(value);
          System.debug('Parsed action integer: ' + actionInt);
          if (actionInt != null) {
            System.debug('Adding action integer to total: ' + actionInt);
            total += actionInt;
          }
        }
      }
      return total;
    } else {
      // Handle single integer value
      return safeParseInt(actionsString);
    }
  }
}