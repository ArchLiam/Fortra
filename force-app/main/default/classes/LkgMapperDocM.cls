public with sharing class LkgMapperDocM extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderDocM.DocMKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String productIdentifierName = uiPayload.productData.identifierName;
    LkgRequestBuilderDocM.DocMKeyData docMKeyData = (LkgRequestBuilderDocM.DocMKeyData) keyData;

    docMKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    docMKeyData.Release = uiPayload.attributes.get(silo + '_Release');
    docMKeyData.Modification = uiPayload.attributes.get(silo + '_Modification');
    docMKeyData.NumberOfUsers = Integer.valueOf(uiPayload.attributes.get(productIdentifierName + '_Number_of_Users'));
    docMKeyData.Tier = uiPayload.attributes.get(productIdentifierName + '_Tier');
  }
}