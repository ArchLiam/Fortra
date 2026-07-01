public with sharing class LkgRecordCreatorPtMulti extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderPtMulti.PtMultiKeyData ptMultiKeyData = (LkgRequestBuilderPtMulti.PtMultiKeyData) keyData;

    licenseKey.Modification__c = ptMultiKeyData.modification;
    licenseKey.Points__c = ptMultiKeyData.points;
  }
}