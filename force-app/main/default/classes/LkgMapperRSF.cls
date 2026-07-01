public with sharing class LkgMapperRSF extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderRSF.RSFKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderRSF.RSFKeyData rsfKeyData = (LkgRequestBuilderRSF.RSFKeyData) keyData;

    rsfKeyData.LParSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');
    rsfKeyData.Release = uiPayload.attributes.get(silo + '_Release');
    rsfKeyData.Modification = uiPayload.attributes.get(silo + '_Modification');
  }
}