@isTest
public with sharing class LkgRecordCreatorSgavxTest {
  private static LkgRecordCreatorSgavx lkgRecordCreator;
  private static LkgRequestBuilderSgavx.SgavxKeyData keyData;

  static {
    lkgRecordCreator = new LkgRecordCreatorSgavx();
    keyData = new LkgRequestBuilderSgavx.SgavxKeyData();
    keyData.modification = '10';
    keyData.NumberOfUsers = 100;
    keyData.createLicenseKeyFile = true;
  }

  @isTest
  static void createRecords_shouldSetModification() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('10', licenseKey.Modification__c, 'Modification should match');
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
  static void createRecords_shouldSetCreateLicenseKeyFile() {
    // When createLicenseKeyRecord is called
    Test.startTest();
    License_Key__c licenseKey = lkgRecordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then the create license key file should be set
    Assert.isTrue(licenseKey.Create_License_Key_File__c, 'Create license key file should be set to true.');
  }

  @isTest
  static void createAttachment_shouldCreateAttachmentWithCorrectContent() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();
    String responseMessage = '{"status":"success","output":["Line 1","Line 2","Line 3"]}';
    licenseKey.Response_Message__c = responseMessage;
    insert licenseKey;

    // When
    Test.startTest();
    Attachment attachment = lkgRecordCreator.createAttachment(licenseKey);
    Test.stopTest();

    // Then
    System.assertEquals(licenseKey.Id, attachment.ParentId, 'Parent ID should match license key');
    System.assert(attachment.Name.startsWith('License Key '), 'Attachment name should start with "License Key "');
    System.assert(attachment.Name.endsWith('.SGA'), 'Attachment name should end with .SGA');
    System.assertEquals('text/plain', attachment.ContentType, 'Content type should be text/plain');
    System.assertEquals(false, attachment.IsPrivate, 'Attachment should not be private');

    String expectedContent = 'Line 1\nLine 2\nLine 3\n';
    String actualContent = attachment.Body.toString();
    System.assertEquals(expectedContent, actualContent, 'Attachment content should match response output');
  }

  @isTest
  static void createAttachment_shouldHandleSingleOutputLine() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();
    String responseMessage = '{"status":"success","output":["Single Line"]}';
    licenseKey.Response_Message__c = responseMessage;
    insert licenseKey;

    // When
    Test.startTest();
    Attachment attachment = lkgRecordCreator.createAttachment(licenseKey);
    Test.stopTest();

    // Then
    String expectedContent = 'Single Line\n';
    String actualContent = attachment.Body.toString();
    System.assertEquals(expectedContent, actualContent, 'Should handle single output line');
  }

  @isTest
  static void createAttachment_shouldHandleEmptyOutputList() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();
    licenseKey.Response_Message__c = '{"status":"success","output":[]}';
    insert licenseKey;

    // When
    Test.startTest();
    Attachment attachment = lkgRecordCreator.createAttachment(licenseKey);
    Test.stopTest();

    // Then
    System.assertEquals('', attachment.Body.toString(), 'Empty output lists should create an empty attachment body.');
  }

  // Helper method
  private static License_Key__c createTestLicenseKey() {
    // Create test account
    Account testAccount = new Account(Name = 'Test Account for Attachment');
    insert testAccount;

    License_Key__c licenseKey = new License_Key__c();
    licenseKey.Account__c = testAccount.Id;
    licenseKey.Product_Code__c = 'TEST001';
    licenseKey.Silo__c = 'sgavx';
    return licenseKey;
  }
}