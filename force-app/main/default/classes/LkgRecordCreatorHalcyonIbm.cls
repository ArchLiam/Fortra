public with sharing class LkgRecordCreatorHalcyonIbm extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData halcyonIbmKeyData = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) keyData;

    licenseKey.LPAR_Model_Number__c = halcyonIbmKeyData.modelNumber;
    licenseKey.LPAR_Serial_Number__c = halcyonIbmKeyData.lparSerialNumber;
    licenseKey.LPAR_Feature_Code__c = halcyonIbmKeyData.featureCode;
    licenseKey.LPAR_Number__c = halcyonIbmKeyData.lparNumber;
    licenseKey.LPAR_System_Name__c = halcyonIbmKeyData.lparSystemName;
  }
}