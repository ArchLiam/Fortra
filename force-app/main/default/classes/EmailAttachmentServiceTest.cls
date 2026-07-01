/**
 * Test class for EmailAttachmentService
 */
@isTest
private class EmailAttachmentServiceTest {
  /**
   * Test getting attachment from Attachment object
   */

  @TestSetup
  static void setupTestData() {
    // Create test Account and Contact for License Key relationships
    Account acc = new Account(Name = 'Test Account', AccountNumber = 'ACC001');
    insert acc;

    Contact contact = new Contact(
      FirstName = 'Test',
      LastName = 'User',
      Email = 'test@example.com',
      AccountId = acc.Id
    );
    insert contact;
    // Create test License Key
    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-001',
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Silo__c = 'Silo1',
      Create_License_Key_File__c = true
    );
    insert testKey;

    // Create Attachment
    Attachment att = new Attachment(
      Name = 'test-license.lic',
      ContentType = 'application/octet-stream',
      Body = Blob.valueOf('TEST LICENSE CONTENT'),
      ParentId = testKey.Id
    );
    insert att;
  }

  @isTest
  static void testGetAttachmentSuccess() {
    License_Key__c testKey = [SELECT Id FROM License_Key__c WHERE Name = 'TEST-001' LIMIT 1];

    Test.startTest();
    Messaging.EmailFileAttachment result = EmailAttachmentService.getAttachmentForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify attachment was found and created correctly
    System.assertNotEquals(null, result, 'Should return an EmailFileAttachment');
    System.assertEquals('test-license.lic', result.getFileName(), 'File name should match');
    System.assertEquals(Blob.valueOf('TEST LICENSE CONTENT'), result.getBody(), 'Body should match');
    System.assertEquals('application/octet-stream', result.getContentType(), 'Content type should match');
  }

  /**
   * Test getting attachment when ContentType is blank
   */
  @isTest
  static void testGetAttachmentWithoutContentType() {
    License_Key__c testKey = [SELECT Id FROM License_Key__c WHERE Name = 'TEST-001' LIMIT 1];

    Test.startTest();
    Messaging.EmailFileAttachment result = EmailAttachmentService.getAttachmentForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify attachment was found
    System.assertNotEquals(null, result, 'Should return an EmailFileAttachment');
    System.assertEquals('test-license.lic', result.getFileName(), 'File name should match');
    System.assertEquals(Blob.valueOf('TEST LICENSE CONTENT'), result.getBody(), 'Body should match');
    System.assertEquals('application/octet-stream', result.getContentType(), 'Content type should match');
  }

  /**
   * Test when no attachment exists
   */
  @isTest
  static void testNoAttachmentFound() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id FROM Contact LIMIT 1];

    // Create a new License Key WITHOUT any attachment
    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-NO-ATTACHMENT',
      License_Key__c = 'TEST-KEY-789',
      Create_License_Key_File__c = true,
      Send_Email__c = false,
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert testKey;

    Test.startTest();
    Messaging.EmailFileAttachment result = EmailAttachmentService.getAttachmentForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify null is returned when no file exists
    System.assertEquals(null, result, 'Should return null when no attachment exists');
  }

  /**
   * Test that most recent attachment is returned when multiple exist
   */
  @isTest
  static void testGetMostRecentAttachment() {
    License_Key__c testKey = [SELECT Id FROM License_Key__c WHERE Name = 'TEST-001' LIMIT 1];

    // Create multiple attachments with slight delay between them
    Attachment att1 = new Attachment(Name = 'old-file.lic', Body = Blob.valueOf('OLD CONTENT'), ParentId = testKey.Id);
    insert att1;

    // Small delay to ensure different CreatedDate
    Attachment att2 = new Attachment(Name = 'new-file.lic', Body = Blob.valueOf('NEW CONTENT'), ParentId = testKey.Id);
    insert att2;

    Test.startTest();
    Messaging.EmailFileAttachment result = EmailAttachmentService.getAttachmentForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify the most recent attachment was returned
    System.assertNotEquals(null, result, 'Should return an EmailFileAttachment');
    System.assertEquals('test-license.lic', result.getFileName(), 'Should return the most recently created attachment');
  }

  /**
   * Test getting attachment IDs for License Key
   */
  @isTest
  static void testGetAttachmentIdsSuccess() {
    License_Key__c testKey = [SELECT Id FROM License_Key__c WHERE Name = 'TEST-001' LIMIT 1];

    Test.startTest();
    List<String> result = EmailAttachmentService.getAttachmentIdsForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify attachment IDs were returned
    System.assertNotEquals(null, result, 'Should return a list');
    System.assertEquals(1, result.size(), 'Should have one attachment ID');

    // Verify the ID is valid
    Attachment att = [SELECT Id FROM Attachment WHERE ParentId = :testKey.Id LIMIT 1];
    System.assertEquals(att.Id, result[0], 'Should return the correct attachment ID');
  }

  /**
   * Test getting attachment IDs when multiple attachments exist
   */
  @isTest
  static void testGetMultipleAttachmentIds() {
    License_Key__c testKey = [SELECT Id FROM License_Key__c WHERE Name = 'TEST-001' LIMIT 1];

    // Create additional attachments
    Attachment att2 = new Attachment(
      Name = 'second-file.lic',
      Body = Blob.valueOf('SECOND CONTENT'),
      ParentId = testKey.Id
    );
    insert att2;

    Test.startTest();
    List<String> result = EmailAttachmentService.getAttachmentIdsForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify multiple attachment IDs were returned
    System.assertNotEquals(null, result, 'Should return a list');
    System.assertEquals(2, result.size(), 'Should have two attachment IDs');
  }

  /**
   * Test getting attachment IDs when no attachments exist
   */
  @isTest
  static void testGetAttachmentIdsNoAttachments() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id FROM Contact LIMIT 1];

    // Create a new License Key WITHOUT any attachment
    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-NO-ATTACH-2',
      License_Key__c = 'TEST-KEY-999',
      Create_License_Key_File__c = true,
      Send_Email__c = false,
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert testKey;

    Test.startTest();
    List<String> result = EmailAttachmentService.getAttachmentIdsForLicenseKey(testKey.Id);
    Test.stopTest();

    // Verify empty list is returned
    System.assertNotEquals(null, result, 'Should return a list');
    System.assertEquals(0, result.size(), 'Should have no attachment IDs');
  }
}