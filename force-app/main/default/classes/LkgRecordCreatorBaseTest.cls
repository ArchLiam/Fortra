@isTest
public with sharing class LkgRecordCreatorBaseTest {
  private static LkgRecordCreatorBase recordCreator;
  private static LkgRequestBuilderBase.KeyData keyData;

  static {
    recordCreator = new LkgRecordCreatorBase();
  }

  @isTest
  static void createLicenseKeyRecord_shouldMapAllBaseFields() {
    // Given
    keyData = createTestKeyData();

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then - verify all base fields are mapped correctly
    System.assertEquals(keyData.AccountId, licenseKey.Account__c, 'Account should match');
    System.assertEquals(keyData.Brand, licenseKey.Brand__c, 'Brand should match');
    System.assertEquals('Permanent', licenseKey.Key_Type__c, 'Key Type should be mapped');
    System.assertEquals(keyData.Contact1Id, licenseKey.Contact_1__c, 'Contact 1 should match');
    System.assertEquals(keyData.Contact2Id, licenseKey.Contact_2__c, 'Contact 2 should match');
    System.assertEquals(keyData.ExpirationDate, licenseKey.End_Date__c, 'End Date should match');
    System.assertEquals(
      keyData.externalProductName,
      licenseKey.License_Key_Product_Name__c,
      'External Product Name should match'
    );
    System.assertEquals(
      keyData.internalProductName,
      licenseKey.Internal_Product_Name__c,
      'Internal Product Name should match'
    );
    System.assertEquals(keyData.LicenseKey, licenseKey.License_Key__c, 'License Key should match');
    System.assertEquals(
      keyData.lkgProductIdentifierName,
      licenseKey.LKG_Product_Identifier_Name__c,
      'LKG Product Identifier should match'
    );
    System.assertEquals(keyData.HardwareId, licenseKey.Hardware_ID__c, 'Hardware ID should match');
    System.assertEquals(keyData.ProductCode, licenseKey.Product_Code__c, 'Product Code should match');
    System.assertEquals(keyData.release, licenseKey.Release__c, 'Release should match');
    System.assertEquals(keyData.requestParameters, licenseKey.Request_Parameters__c, 'Request Parameters should match');
    System.assertEquals(keyData.responseMessage, licenseKey.Response_Message__c, 'Response Message should match');
    System.assertEquals(keyData.SendEmail, licenseKey.Send_Email__c, 'Send Email should match');
    System.assertEquals(keyData.serialNumber, licenseKey.License_Key_Serial_Number__c, 'Serial Number should match');
    System.assertEquals(keyData.Silo, licenseKey.Silo__c, 'Silo should match');
    System.assertEquals(keyData.StartDate, licenseKey.Start_Date__c, 'Start Date should match');
    System.assertEquals(keyData.Notes, licenseKey.Notes__c, 'Notes should match');
  }

  @isTest
  static void mapKeyType_shouldReturnPermanent() {
    // Given
    String keyType = 'Permanent';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Permanent', mappedType, 'Should map to Permanent');
  }

  @isTest
  static void mapKeyType_shouldReturnSpecificTemporary() {
    // Given
    String keyType = 'Specific_Temporary';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Specific/Temporary', mappedType, 'Should map to Specific/Temporary');
  }

  @isTest
  static void mapKeyType_shouldReturnGeneric() {
    // Given
    String keyType = 'Generic';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Generic', mappedType, 'Should map to Generic');
  }

  @isTest
  static void mapKeyType_shouldReturnSubscription() {
    // Given
    String keyType = 'Subscription';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Subscription', mappedType, 'Should map to Subscription');
  }

  @isTest
  static void mapKeyType_shouldReturnUnknownForInvalidType() {
    // Given
    String keyType = 'InvalidKeyType';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Unknown Key Type', mappedType, 'Should return Unknown Key Type for invalid input');
  }

  @isTest
  static void createAttachment_shouldReturnNull() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();
    String responseMessage = '{"status":"success","output":["Line 1","Line 2","Line 3"]}';
    licenseKey.Response_Message__c = responseMessage;
    insert licenseKey;

    // When
    Test.startTest();
    Attachment attachment = recordCreator.createAttachment(licenseKey);
    Test.stopTest();

    // Then
    System.assertEquals(null, attachment, 'Base class should return null - implementation is silo-specific');
  }

  @isTest
  static void insertLicenseKeyRecord_shouldInsertRecord() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();

    // When
    Test.startTest();
    recordCreator.insertLicenseKeyRecord(licenseKey);
    Test.stopTest();

    // Then
    List<License_Key__c> insertedKeys = [
      SELECT Id, Product_Code__c
      FROM License_Key__c
      WHERE Product_Code__c = 'TEST001'
    ];
    System.assertEquals(1, insertedKeys.size(), 'License key should be inserted');
    System.assertEquals('TEST001', insertedKeys[0].Product_Code__c, 'Product code should match');
  }

  @isTest
  static void mapBaseFields_shouldHandleNullValues() {
    // Given
    keyData = new LkgRequestBuilderBase.KeyData();
    keyData.KeyType = 'Permanent';
    // All other fields are null

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then - verify no exceptions and key type is mapped
    System.assertEquals('Permanent', licenseKey.Key_Type__c, 'Should handle null values without errors');
    System.assertEquals(null, licenseKey.Account__c, 'Null fields should remain null');
  }

  @isTest
  static void createLicenseKeyRecord_shouldMapCreateLicenseKeyFile() {
    // Given
    keyData = createTestKeyData();
    keyData.createLicenseKeyFile = true;

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then
    System.assertEquals(true, licenseKey.Create_License_Key_File__c, 'Create License Key File should be set to true');
  }

  @isTest
  static void createLicenseKeyRecord_shouldMapCreateLicenseKeyFileFalse() {
    // Given
    keyData = createTestKeyData();
    keyData.createLicenseKeyFile = false;

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then
    System.assertEquals(false, licenseKey.Create_License_Key_File__c, 'Create License Key File should be set to false');
  }

  @isTest
  static void createLicenseKeyRecord_shouldMapNotes() {
    // Given
    keyData = createTestKeyData();
    keyData.Notes = 'Test notes for license key';

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then
    System.assertEquals('Test notes for license key', licenseKey.Notes__c, 'Notes should be mapped correctly');
  }

  @isTest
  static void createLicenseKeyRecord_shouldHandleNullNotes() {
    // Given
    keyData = createTestKeyData();
    keyData.Notes = null;

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then
    System.assertEquals(null, licenseKey.Notes__c, 'Null notes should remain null');
  }

  @isTest
  static void insertLicenseKeyRecord_shouldInsertAttachment() {
    // Given
    License_Key__c licenseKey = createTestLicenseKey();
    insert licenseKey;

    Attachment attachment = new Attachment();
    attachment.ParentId = licenseKey.Id;
    attachment.Name = 'Test Attachment';
    attachment.Body = Blob.valueOf('Test content');
    attachment.ContentType = 'text/plain';

    // When
    Test.startTest();
    recordCreator.insertLicenseKeyRecord(attachment);
    Test.stopTest();

    // Then
    List<Attachment> insertedAttachments = [
      SELECT Id, Name, ParentId
      FROM Attachment
      WHERE ParentId = :licenseKey.Id AND Name = 'Test Attachment'
    ];
    System.assertEquals(1, insertedAttachments.size(), 'Attachment should be inserted');
    System.assertEquals('Test Attachment', insertedAttachments[0].Name, 'Attachment name should match');
  }

  @isTest
  static void mapKeyType_shouldReturnSubscriptionForIntermapperSubscription() {
    // Given
    String keyType = 'Subscription';

    // When
    Test.startTest();
    String mappedType = recordCreator.mapKeyType(keyType);
    Test.stopTest();

    // Then
    System.assertEquals('Subscription', mappedType, 'Intermapper_Subscription should map to Subscription');
  }

  @isTest
  static void createLicenseKeyRecord_shouldReplaceArgvInRequestParameters() {
    // Given - RequestParameters containing &argv= delimiters
    keyData = createTestKeyData();
    keyData.requestParameters = 'param1=value1&argv=param2=value2&argv=param3=value3';

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then - &argv= delimiters should be replaced with commas
    System.assertEquals(
      'param1=value1,param2=value2,param3=value3',
      licenseKey.Request_Parameters__c,
      '&argv= should be replaced with commas in Request Parameters'
    );
  }

  @isTest
  static void createLicenseKeyRecord_shouldDefaultCreateLicenseKeyFileToFalseWhenNull() {
    // Given - createLicenseKeyFile is explicitly null
    keyData = createTestKeyData();
    keyData.createLicenseKeyFile = null;

    // When
    Test.startTest();
    License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);
    Test.stopTest();

    // Then - should default to false
    System.assertEquals(
      false,
      licenseKey.Create_License_Key_File__c,
      'Create_License_Key_File__c should default to false when createLicenseKeyFile is null'
    );
  }

  // Helper methods
  private static LkgRequestBuilderBase.KeyData createTestKeyData() {
    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();

    // Create test account
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    // Create test contacts
    Contact contact1 = new Contact(FirstName = 'Test', LastName = 'Contact1', AccountId = testAccount.Id);
    Contact contact2 = new Contact(FirstName = 'Test', LastName = 'Contact2', AccountId = testAccount.Id);
    insert new List<Contact>{ contact1, contact2 };

    keyData.AccountId = testAccount.Id;
    keyData.Brand = 'Test Brand';
    keyData.KeyType = 'Permanent';
    keyData.Contact1Id = contact1.Id;
    keyData.Contact2Id = contact2.Id;
    keyData.ExpirationDate = Date.today().addDays(365);
    keyData.externalProductName = 'Test External Product';
    keyData.internalProductName = 'Test Internal Product';
    keyData.LicenseKey = 'TEST-LICENSE-KEY-12345';
    keyData.lkgProductIdentifierName = 'TEST_PRODUCT';
    keyData.HardwareId = 'HW-12345';
    keyData.ProductCode = 'PROD-001';
    keyData.requestParameters = '{"param1":"value1"}';
    keyData.responseMessage = '{"status":"success","output":["Test output"]}';
    keyData.SendEmail = true;
    keyData.serialNumber = 'SN-12345';
    keyData.Silo = 'TestSilo';
    keyData.StartDate = Date.today();
    keyData.release = '1.0.0';
    keyData.Notes = 'Test notes';

    return keyData;
  }

  private static License_Key__c createTestLicenseKey() {
    // Create test account
    Account testAccount = new Account(Name = 'Test Account for Attachment');
    insert testAccount;

    License_Key__c licenseKey = new License_Key__c();
    licenseKey.Account__c = testAccount.Id;
    licenseKey.Product_Code__c = 'TEST001';
    licenseKey.Silo__c = 'TestSilo';
    return licenseKey;
  }
}