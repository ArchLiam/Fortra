@isTest
private class LkgRecordCreatorHalcyonIbmTest {
  private static final LkgRecordCreatorHalcyonIbm recordCreator = new LkgRecordCreatorHalcyonIbm();
  private static final LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData keyData;

  static {
    keyData = new LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData();
    keyData.modelNumber = '42A';
    keyData.lparSerialNumber = '780B530';
    keyData.featureCode = 'FC123';
    keyData.lparNumber = 'LPAR001';
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetLparModelNumber() {
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    System.assertEquals('42A', licenseKey.LPAR_Model_Number__c, 'LPAR model number should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetSerialNumbers() {
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    System.assertEquals('780B530', licenseKey.LPAR_Serial_Number__c, 'LPAR serial number should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetFeatureCode() {
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    System.assertEquals('FC123', licenseKey.LPAR_Feature_Code__c, 'Feature code should match');
  }

  @isTest
  static void createLicenseKeyRecord_shouldSetLparNumber() {
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    System.assertEquals('LPAR001', licenseKey.LPAR_Number__c, 'LPAR number should match');
  }
}