public interface ILkgRecordCreator {
  License_Key__c createLicenseKeyRecord(LkgRequestBuilderBase.KeyData keyData);
  void insertLicenseKeyRecord(SObject record);
  Attachment createAttachment(License_Key__c licenseKey);
}