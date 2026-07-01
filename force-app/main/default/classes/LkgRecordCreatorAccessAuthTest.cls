@isTest
public with sharing class LkgRecordCreatorAccessAuthTest {
  private static LkgRecordCreatorAccessAuth lkgRecordCreator;
  private static LkgRequestBuilderAccessAuth.AccessAuthKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorAccessAuth();
    keyData = new LkgRequestBuilderAccessAuth.AccessAuthKeyData();
    keyData.modification = '05';
    keyData.NumberOfUsers = 50;
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
  static void createRecords_shouldSetNumberOfUsers() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Number of Users field should be set correctly
    System.assertEquals(50, licenseKey.Number_of_Users__c, 'Number of Users should match');
  }
}