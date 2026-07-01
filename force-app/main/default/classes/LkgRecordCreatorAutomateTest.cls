@isTest
public with sharing class LkgRecordCreatorAutomateTest {
  private static LkgRecordCreatorAutomate lkgRecordCreator;
  private static LkgRequestBuilderAutomate.AutomateKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorAutomate();
    keyData = new LkgRequestBuilderAutomate.AutomateKeyData();
    keyData.modification = '01';
    keyData.Points = 'S1A2B3C4';
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('01', licenseKey.Modification__c, 'Modification should match');
  }

  @isTest
  static void createRecords_shouldSetPoints() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Points field should be set correctly
    System.assertEquals('S1A2B3C4', licenseKey.Points__c, 'Points should match');
  }
}