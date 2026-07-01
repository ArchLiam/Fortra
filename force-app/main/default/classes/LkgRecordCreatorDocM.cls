public with sharing class LkgRecordCreatorDocM extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderDocM.DocMKeyData docMKeyData = (LkgRequestBuilderDocM.DocMKeyData) keyData;

    licenseKey.Points__c = docMKeyData.Tier;
    licenseKey.Hardware_Id__c = docMKeyData.HardwareId;
    licenseKey.Number_Of_Users__c = docMKeyData.NumberOfUsers;
    licenseKey.Modification__c = docMKeyData.Modification;
  }
}