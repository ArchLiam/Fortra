@isTest
public with sharing class LkgRecordCreatorVitylTest {
  private static LkgRecordCreatorVityl lkgRecordCreator;
  private static LkgRequestBuilderVityl.VitylKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorVityl();
    keyData = new LkgRequestBuilderVityl.VitylKeyData();
    keyData.HardwareId = 'HW12345';
    keyData.modification = '01';
    keyData.release = '02';
  }

  @isTest
  static void createLicenseKeyRecord_shouldNotReturnNull() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, licenseKey, 'License key record should not be null');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetHardwareId() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Hardware Id field should be set correctly
    System.assertEquals('HW12345', licenseKey.Hardware_Id__c, 'Hardware Id should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('01', licenseKey.Modification__c, 'Modification should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetRelease() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Release field should be set correctly
    System.assertEquals('02', licenseKey.Release__c, 'Release should match');
  }
}