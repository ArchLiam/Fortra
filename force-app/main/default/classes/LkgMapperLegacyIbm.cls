public with sharing class LkgMapperLegacyIbm extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderLegacyIbm.LegacyIbmKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData legacyIbmKeyData = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) keyData;

    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;

    legacyIbmKeyData.HardwareId = uiPayload.attributes.get(silo + '_Serial_Number');
    legacyIbmKeyData.processorGroup = uiPayload.attributes.get(silo + '_Processor_Group');
    legacyIbmKeyData.usageLimit = safeParseInt(uiPayload.attributes.get(silo + '_Usage_Limit'));
    legacyIbmKeyData.model = uiPayload.attributes.get(silo + '_Model_Number');
    legacyIbmKeyData.featureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    legacyIbmKeyData.supportKey = uiPayload.productData.isSupportProduct;
    legacyIbmKeyData.Release = uiPayload.attributes.get(product + '_Release'); //getRelease(uiPayload);
    legacyIbmKeyData.modification = uiPayload.attributes.get(product + '_Modification'); //getModification(uiPayload);
  }

  // private String getRelease(LkgMapperBase.UiPayload uiPayload) {
  //   if (uiPayload.productData.productCode == 'AS') {
  //     return '6';
  //   } else if (uiPayload.productData.productCode == 'MS') {
  //     // TO DO: Add version from UI. hardcoding version 7.00 for MS for now
  //     return '7';
  //   } else if (uiPayload.productData.productCode == 'S1') {
  //     // TO DO: Add version from UI. hardcoding version 3.10 for S1 for now
  //     return '3';
  //   }
  //   return uiPayload.attributes.get('legacyibm_Version_RxxMxx');
  // }

  // private String getModification(LkgMapperBase.UiPayload uiPayload) {
  //   if (uiPayload.productData.productCode == 'AS') {
  //     return '11';
  //   } else if (uiPayload.productData.productCode == 'MS') {
  //     // TO DO: Add version from UI. hardcoding version 7.00 for MS for now
  //     return '00';
  //   } else if (uiPayload.productData.productCode == 'S1') {
  //     // TO DO: Add version from UI. hardcoding version 3.10 for S1 for now
  //     return '10';
  //   }
  //   return '';
  // }
}