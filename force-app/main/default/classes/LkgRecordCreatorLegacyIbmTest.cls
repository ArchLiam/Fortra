@isTest
public with sharing class LkgRecordCreatorLegacyIbmTest {
  private static LkgRecordCreatorLegacyIbm lkgRecordCreator;
  private static LkgRequestBuilderLegacyIbm.LegacyIbmKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorLegacyIbm();

    keyData = new LkgRequestBuilderLegacyIbm.LegacyIbmKeyData();
    keyData.UsageLimit = 10;
    keyData.FeatureCode = 'FC123';
    keyData.Model = 'ModelX';
    keyData.supportKey = true;
    keyData.Modification = '11';
  }

  @isTest
  static void createRecords_shouldSetUsageLimit() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then verify the UsageLimit is set correctly
    System.assertEquals(10, licenseKey.Number_of_Users__c);
  }

  @isTest
  static void createRecords_shouldSetFeatureCode() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then verify the FeatureCode is set correctly
    System.assertEquals('FC123', licenseKey.LPAR_Feature_Code__c);
  }

  @isTest
  static void createRecords_shouldSetModel() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then verify the Model is set correctly
    System.assertEquals('ModelX', licenseKey.LPAR_Model_Number__c);
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then verify the Modification is set correctly
    System.assertEquals('11', licenseKey.Modification__c);
  }
}