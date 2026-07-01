public with sharing class LkgRecordCreatorAutomate extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderAutomate.AutomateKeyData automateKeyData = (LkgRequestBuilderAutomate.AutomateKeyData) keyData;

    licenseKey.Modification__c = automateKeyData.modification;
    licenseKey.Points__c = automateKeyData.Points;
  }
}