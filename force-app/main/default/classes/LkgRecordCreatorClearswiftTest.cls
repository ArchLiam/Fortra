@isTest
public with sharing class LkgRecordCreatorClearswiftTest {
  private static LkgRecordCreatorClearswift lkgRecordCreator;
  private static LkgRequestBuilderClearswift.ClearswiftKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorClearswift();
    keyData = new LkgRequestBuilderClearswift.ClearswiftKeyData();
    keyData.AccountName = 'Test Company';
    keyData.Instances = 2;
    keyData.NumberOfUsers = 50;
  }

  @isTest
  static void createRecords_shouldSetInstances() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Instances field should be set correctly
    System.assertEquals(2, licenseKey.Instances__c, 'Instances should match');
  }

  @isTest
  static void createRecords_shouldSetNumberOfUsers() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Number of Users field should be set correctly
    System.assertEquals(50, licenseKey.Number_of_Users__c, 'Number of Users should match');
  }
}