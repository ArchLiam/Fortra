@isTest
public with sharing class LkgRecordCreatorSequelWebTest {
  private static LkgRecordCreatorSequelWeb lkgRecordCreator;
  private static LkgRequestBuilderSequelWeb.SequelWebKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorSequelWeb();
    keyData = new LkgRequestBuilderSequelWeb.SequelWebKeyData();
    keyData.Release = '10';
    keyData.Modification = '5';
  }

  @isTest
  static void createRecords_shouldSetRelease() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Release field should be set correctly
    System.assertEquals('10', licenseKey.Release__c, 'Release should match');
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Modification field should be set correctly
    System.assertEquals('5', licenseKey.Modification__c, 'Modification should match');
  }
}