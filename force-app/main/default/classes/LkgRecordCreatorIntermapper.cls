public with sharing class LkgRecordCreatorIntermapper extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderIntermapper.IntermapperKeyData intermapperKeyData = (LkgRequestBuilderIntermapper.IntermapperKeyData) keyData;
    licenseKey.Modification__c = intermapperKeyData.modification;
  }
}