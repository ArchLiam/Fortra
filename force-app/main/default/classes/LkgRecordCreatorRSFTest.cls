@isTest
public with sharing class LkgRecordCreatorRSFTest {
  private static LkgRecordCreatorRSF lkgRecordCreator;
  private static LkgRequestBuilderRSF.RSFKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorRSF();
    keyData = new LkgRequestBuilderRSF.RSFKeyData();
    keyData.LParSerialNumber = 'Serial12345';
    keyData.Flag = 'TestFlag';
  }

  @isTest
  static void createRecords_shouldSetSerialNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Serial Number field should be set correctly
    System.assertEquals('Serial12345', licenseKey.LPAR_Serial_Number__c, 'Serial Number should match');
  }
}