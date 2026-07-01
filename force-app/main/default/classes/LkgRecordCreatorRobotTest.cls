@isTest
public with sharing class LkgRecordCreatorRobotTest {
  private static LkgRecordCreatorRobot lkgRecordCreator;
  private static LkgRequestBuilderRobot.RobotKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorRobot();
    keyData = new LkgRequestBuilderRobot.RobotKeyData();
    keyData.IAspGroup = 'Test IAsp Group';
    keyData.LParEnd = 'EndLPAR001';
    keyData.FeatureCode = 'FeatCode123';
    keyData.ModelNumber = 'ModelX';
    keyData.LParNumber = 'LPARNum001';
    keyData.LParSerialNumber = 'Serial12345';
    keyData.NumberOfProcessors = 4;
    keyData.NumberOfUsers = 100;
    keyData.ProcessorType = 'TypeA';
    keyData.Notes = 'Test Notes';
  }

  @isTest
  static void createRecords_shouldSetIAspGroup() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the IASP Name field should be set correctly
    System.assertEquals('Test IAsp Group', licenseKey.IASP_Name__c, 'IASP Name should match');
  }

  @isTest
  static void createRecords_shouldSetEndLParNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the LPAR End Number field should be set correctly
    System.assertEquals('EndLPAR001', licenseKey.LPAR_End_Number__c, 'LPAR End Number should match');
  }

  @isTest
  static void createRecords_shouldSetFeatureCode() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the LPAR Feature Code field should be set correctly
    System.assertEquals('FeatCode123', licenseKey.LPAR_Feature_Code__c, 'LPAR Feature Code should match');
  }

  @isTest
  static void createRecords_shouldSetModelNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Model Number field should be set correctly
    System.assertEquals('ModelX', licenseKey.LPAR_Model_Number__c, 'Model Number should match');
  }

  @isTest
  static void createRecords_shouldSetLParNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the LPAR Number field should be set correctly
    System.assertEquals('LPARNum001', licenseKey.LPAR_Number__c, 'LPAR Number should match');
  }

  @isTest
  static void createRecords_shouldSetSerialNumber() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the LPAR Serial Number field should be set correctly
    System.assertEquals('Serial12345', licenseKey.LPAR_Serial_Number__c, 'LPAR Serial Number should match');
  }

  @isTest
  static void createRecords_shouldSetNumberOfProcessors() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Number of Processors field should be set correctly
    System.assertEquals('4', licenseKey.Number_of_Processors__c, 'Number of Processors should match');
  }

  @isTest
  static void createRecords_shouldSetNumberOfUsers() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Number of Users field should be set correctly
    System.assertEquals(100, licenseKey.Number_of_Users__c, 'Number of Users should match');
  }

  @isTest
  static void createRecords_shouldSetProcessorType() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();
    // Then the Processor Type field should be set correctly
    System.assertEquals('TypeA', licenseKey.Processor_Type__c, 'Processor Type should match');
  }

  //   @isTest
  //   static void createRecords_shouldSetNotes() {
  //     // When createLicenseKeyRecord is called
  //     Test.startTest();
  //     License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
  //     Test.stopTest();
  //     // Then the Notes field should be set correctly
  //     System.assertEquals('Test Notes', licenseKey.Notes__c, 'Notes should match');
  //   }
}