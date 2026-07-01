public with sharing class LkgRecordCreatorFortra extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderFortra.FortraKeyData fortraKeyData = (LkgRequestBuilderFortra.FortraKeyData) keyData;

    licenseKey.Points__c = fortraKeyData.tiers;
  }
}