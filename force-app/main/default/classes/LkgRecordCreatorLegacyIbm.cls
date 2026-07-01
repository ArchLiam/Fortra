public with sharing class LkgRecordCreatorLegacyIbm extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData legacyIbmKeyData = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) keyData;

    licenseKey.Modification__c = legacyIbmKeyData.modification;
    licenseKey.Number_of_Users__c = legacyIbmKeyData.UsageLimit;
    licenseKey.LPAR_Feature_Code__c = legacyIbmKeyData.FeatureCode;
    licenseKey.LPAR_Model_Number__c = legacyIbmKeyData.Model;
    //licenseKey.Is_Support_Key__c = legacyIbmKeyData.supportKey;
  }
}