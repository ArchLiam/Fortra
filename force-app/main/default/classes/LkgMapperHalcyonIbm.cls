public with sharing class LkgMapperHalcyonIbm extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String productIdentifierName = uiPayload.productData.identifierName;

    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData halcyonIbmKeyData = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) keyData;

    halcyonIbmKeyData.featureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    halcyonIbmKeyData.modelNumber = uiPayload.attributes.get(silo + '_Model_Number');
    halcyonIbmKeyData.cores = uiPayload.attributes.get(silo + '_Number_of_Cores');
    halcyonIbmKeyData.performanceGroup = uiPayload.attributes.get(silo + '_Performance_Group');
    halcyonIbmKeyData.lparSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');
    halcyonIbmKeyData.lparSystemName = uiPayload.attributes.get(silo + '_System_Name');

    halcyonIbmKeyData.individualMonitors = uiPayload.attributes.get(productIdentifierName + '_Individual_Monitors');
    halcyonIbmKeyData.individualProducts = uiPayload.attributes.get(productIdentifierName + '_Individual_Products');
  }
}