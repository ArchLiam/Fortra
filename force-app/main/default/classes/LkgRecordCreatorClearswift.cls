public with sharing class LkgRecordCreatorClearswift extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderClearswift.ClearswiftKeyData clearswiftKeyData = (LkgRequestBuilderClearswift.ClearswiftKeyData) keyData;

    //licenseKey.Clearswift_Company_Name__c = clearswiftKeyData.AccountName;
    licenseKey.Instances__c = clearswiftKeyData.Instances;
    licenseKey.Number_of_Users__c = clearswiftKeyData.NumberOfUsers;
  }
}