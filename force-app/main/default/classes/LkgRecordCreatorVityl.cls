public with sharing class LkgRecordCreatorVityl extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderVityl.VitylKeyData vitylKeyData = (LkgRequestBuilderVityl.VitylKeyData) keyData;

    licenseKey.Hardware_Id__c = vitylKeyData.HardwareId;
    licenseKey.Modification__c = vitylKeyData.modification;
    licenseKey.Release__c = vitylKeyData.release;
  }
}