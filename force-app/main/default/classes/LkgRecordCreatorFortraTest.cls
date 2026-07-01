@isTest
public with sharing class LkgRecordCreatorFortraTest {
  private static LkgRecordCreatorFortra lkgRecordCreator;
  private static LkgRequestBuilderFortra.FortraKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorFortra();
    keyData = new LkgRequestBuilderFortra.FortraKeyData();
    keyData.tiers = 'A0B0C0D1E5S2';
  }

  @isTest
  static void createRecords_shouldSetPoints() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Points field should be set correctly
    System.assertEquals('A0B0C0D1E5S2', licenseKey.Points__c, 'Points should match');
  }
}