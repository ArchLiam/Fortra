@isTest
public with sharing class LkgRecordCreatorDocMTest {
  private static LkgRecordCreatorDocM lkgRecordCreator;
  private static LkgRequestBuilderDocM.DocMKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorDocM();
    keyData = new LkgRequestBuilderDocM.DocMKeyData();
    keyData.Tier = 'S3B100';
    keyData.HardwareId = '1234567890';
    keyData.NumberOfUsers = 50;
    keyData.Modification = '05';
  }

  @isTest
  static void createRecords_shouldSetPoints() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Points field should be set correctly
    System.assertEquals('S3B100', licenseKey.Points__c, 'Points should match');
  }

  @isTest
  static void createRecords_shouldSetHardwareId() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Hardware Id field should be set correctly
    System.assertEquals('1234567890', licenseKey.Hardware_Id__c, 'Hardware Id should match');
  }

  @isTest
  static void createRecords_shouldSetNumberOfUsers() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Number of Users field should be set correctly
    System.assertEquals(50, licenseKey.Number_Of_Users__c, 'Number of Users should match');
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
}