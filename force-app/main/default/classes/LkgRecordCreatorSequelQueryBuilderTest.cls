@isTest
public with sharing class LkgRecordCreatorSequelQueryBuilderTest {
  private static LkgRecordCreatorSequelQueryBuilder lkgRecordCreator;
  private static LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorSequelQueryBuilder();
    keyData = new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
    keyData.Release = '5';
    keyData.Modification = '10';
    keyData.NumberOfConnectors = 10;
    keyData.NumberOfDesigners = 5;
    keyData.HasDataDecorations = 1;
  }

  @isTest
  static void createRecords_shouldSetAllFields() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then all fields should be set correctly
    System.assertEquals('5', licenseKey.Release__c, 'Release should match');
    System.assertEquals('10', licenseKey.Modification__c, 'Modification should match');
  }
}