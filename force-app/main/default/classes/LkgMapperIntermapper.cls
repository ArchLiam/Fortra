public with sharing class LkgMapperIntermapper extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderIntermapper.IntermapperKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderIntermapper.IntermapperKeyData intermapperKeyData = (LkgRequestBuilderIntermapper.IntermapperKeyData) keyData;

    // Map silo-specific fields from 'intermapper' attributes
    intermapperKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    intermapperKeyData.modification = uiPayload.attributes.get(silo + '_Modification');

    // Map product-specific fields from Productidentifier attributes
    intermapperKeyData.ServerDevices = safeParseInt(uiPayload.attributes.get(product + '_Devices'));
    intermapperKeyData.ServerFlows = safeParseInt(uiPayload.attributes.get(product + '_Flows'));
    intermapperKeyData.Remotes = safeParseInt(uiPayload.attributes.get(product + '_Remotes'));
  }
}