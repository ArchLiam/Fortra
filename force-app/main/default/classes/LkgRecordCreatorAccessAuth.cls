public with sharing class LkgRecordCreatorAccessAuth extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderAccessAuth.AccessAuthKeyData accessAuthKeyData = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) keyData;

    licenseKey.Modification__c = accessAuthKeyData.modification;
    licenseKey.Number_of_Users__c = accessAuthKeyData.NumberOfUsers;
  }
}