@isTest
public with sharing class LkgRecordCreatorTQSurveyorTest {
  private static LkgRecordCreatorTQSurveyor lkgRecordCreator;
  private static LkgRequestBuilderTQSurveyor.TQSurveyorKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorTQSurveyor();
    keyData = new LkgRequestBuilderTQSurveyor.TQSurveyorKeyData();
    keyData.accountName = 'Test Account Corp';
    keyData.modelNumber = 'Server123';
    keyData.numberOfLicenses = 25;
    keyData.KeyType = 'Permanent';
    keyData.Silo = 'tqjava';
    keyData.ProductCode = 'TQ-001';
    keyData.LicenseKey = 'TQ-LICENSE-KEY-12345';
    keyData.serialNumber = 'SN-TQ-001';
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
  static void createLicenseKeyRecord_shouldSetSilo() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Silo field should be set correctly
    System.assertEquals('tqjava', licenseKey.Silo__c, 'Silo should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetProductCode() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Product Code field should be set correctly
    System.assertEquals('TQ-001', licenseKey.Product_Code__c, 'Product Code should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetLicenseKey() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the License Key field should be set correctly
    System.assertEquals('TQ-LICENSE-KEY-12345', licenseKey.License_Key__c, 'License Key should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetSerialNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Serial Number field should be set correctly
    System.assertEquals('SN-TQ-001', licenseKey.License_Key_Serial_Number__c, 'Serial Number should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetKeyType() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Key Type field should be mapped correctly
    System.assertEquals('Permanent', licenseKey.Key_Type__c, 'Key Type should match');
  }
}