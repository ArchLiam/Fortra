public with sharing class LkgRecordCreatorSequelWeb extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderSequelWeb.SequelWebKeyData sequelWebKeyData = (LkgRequestBuilderSequelWeb.SequelWebKeyData) keyData;

    licenseKey.Release__c = sequelWebKeyData.Release;
    licenseKey.Modification__c = sequelWebKeyData.Modification;
  }
}