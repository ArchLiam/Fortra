public with sharing class LkgMapperAccessAuth extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderAccessAuth.AccessAuthKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderAccessAuth.AccessAuthKeyData accessAuthKeyData = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) keyData;

    accessAuthKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    accessAuthKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
    accessAuthKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Users'));
  }
}