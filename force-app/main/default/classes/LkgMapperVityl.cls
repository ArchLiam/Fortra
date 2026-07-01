public with sharing class LkgMapperVityl extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderVityl.VitylKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderVityl.VitylKeyData vitylKeyData = (LkgRequestBuilderVityl.VitylKeyData) keyData;

    vitylKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    vitylKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
    vitylKeyData.release = uiPayload.attributes.get(silo + '_Release');
    vitylKeyData.Tier = uiPayload.attributes.get(product + '_Tier');
    vitylKeyData.Count = safeParseInt(uiPayload.attributes.get(product + '_Count'));
    vitylKeyData.Flag = uiPayload.attributes.get(product + '_Flag');
  }
}