@isTest
public with sharing class LkgRecordCreatorPtMultiTest {
  private static LkgRecordCreatorPtMulti lkgRecordCreator;
  private static LkgRequestBuilderPtMulti.PtMultiKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorPtMulti();
    keyData = new LkgRequestBuilderPtMulti.PtMultiKeyData();
    keyData.modification = '05';
    keyData.points = '42';
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('05', licenseKey.Modification__c, 'Modification should match');
  }

  @isTest
  static void createRecords_shouldSetPoints() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Points field should be set correctly
    System.assertEquals('42', licenseKey.Points__c, 'Points should match');
  }
}