public with sharing class LkgRecordCreatorRSF extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderRSF.RSFKeyData rsfKeyData = (LkgRequestBuilderRSF.RSFKeyData) keyData;

    licenseKey.LPAR_Serial_Number__c = rsfKeyData.LParSerialNumber;
    licenseKey.Release__c = rsfKeyData.Release;
    licenseKey.Modification__c = rsfKeyData.Modification;
  }
}