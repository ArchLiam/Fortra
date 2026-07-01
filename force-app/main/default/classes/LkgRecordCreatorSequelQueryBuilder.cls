public with sharing class LkgRecordCreatorSequelQueryBuilder extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData sqbKeyData = (LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData) keyData;

    licenseKey.Release__c = sqbKeyData.Release;
    licenseKey.Modification__c = sqbKeyData.Modification;
  }
}