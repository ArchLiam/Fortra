public with sharing class LkgMapperSequelQueryBuilder extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String productIdentifierName = uiPayload.productData.identifierName;
    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData sqbKeyData = (LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData) keyData;

    sqbKeyData.Release = uiPayload.attributes.get(silo + '_Release');
    sqbKeyData.Modification = uiPayload.attributes.get(silo + '_Modification');
    sqbKeyData.NumberOfConnectors = safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Connectors'));
    sqbKeyData.NumberOfDesigners = safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Designers'));
    sqbKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    sqbKeyData.HasDataDecorations = safeParseInt(uiPayload.attributes.get(silo + '_Has_Data_Decorations')) == null
      ? 1
      : safeParseInt(uiPayload.attributes.get(silo + '_Has_Data_Decorations'));
  }
}