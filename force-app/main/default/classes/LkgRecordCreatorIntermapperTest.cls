@isTest
public with sharing class LkgRecordCreatorIntermapperTest {
  private static LkgRecordCreatorIntermapper lkgRecordCreator;
  private static LkgRequestBuilderIntermapper.IntermapperKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorIntermapper();
    keyData = new LkgRequestBuilderIntermapper.IntermapperKeyData();
    keyData.modification = '03';
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('03', licenseKey.Modification__c, 'Modification should match');
  }
}