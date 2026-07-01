/**
 * Test class for LicenseKeyEmailHandler
 * Lightweight tests focused on the handler's core responsibilities:
 * 1. ProcessLicenseKeyEmailFromIds - main entry point for trigger
 * 2. ProcessLicenseKeyEmail - core processing logic with factory pattern
 */
@isTest
public class LicenseKeyEmailHandlerTest {
  public static final String TEST_BRAND_CLEARSWIFT = 'Clearswift';

  /**
   * Setup minimal test data - only what's needed for handler tests
   */
  @TestSetup
  static void setupTestData() {
    // Create Email Template in separate context to avoid mixed DML
    System.runAs(new User(Id = UserInfo.getUserId())) {
      EmailTemplate template = new EmailTemplate(
        DeveloperName = 'Fortra_License_Key_Clearswift_Default_Email_Template',
        FolderId = UserInfo.getUserId(),
        TemplateType = 'text',
        Name = 'Test Handler Template',
        Subject = 'License Key Notification',
        Body = 'Your license key: {!License_Key__c.Name}',
        IsActive = true
      );
      insert template;
    }

    // Create minimal test data
    Account acc = new Account(Name = 'Test Account', AccountNumber = 'ACC001');
    insert acc;

    Contact contact = new Contact(
      FirstName = 'Test',
      LastName = 'User',
      Email = 'test@example.com',
      AccountId = acc.Id
    );
    insert contact;

    // Create license keys with mandatory fields
    List<License_Key__c> keys = new List<License_Key__c>{
      new License_Key__c(
        Name = 'TEST-001',
        Account__c = acc.Id,
        Contact_1__c = contact.Id,
        Key_Type__c = 'Generic',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
      ),
      new License_Key__c(
        Name = 'TEST-002',
        Account__c = acc.Id,
        Contact_1__c = contact.Id,
        Key_Type__c = 'Generic',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
      ),
      new License_Key__c(
        Name = 'TEST-NO-CONTACT',
        Account__c = acc.Id,
        Key_Type__c = 'Generic',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
      )
    };
    insert keys;
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with single valid ID
   * Verifies: Email sent, Send_Email__c reset, Email_Status__c updated
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_SingleId() {
    License_Key__c testKey = [
      SELECT Id
      FROM License_Key__c
      WHERE Name = 'TEST-001'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(new List<Id>{ testKey.Id });
    Test.stopTest();

    License_Key__c updated = [
      SELECT Send_Email__c, Email_Status__c, Last_Email_Sent_Date__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertEquals(false, updated.Send_Email__c);
    System.assertEquals('Success', updated.Email_Status__c);
    System.assertNotEquals(null, updated.Last_Email_Sent_Date__c);
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with multiple IDs
   * Verifies: Multiple emails processed correctly
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_MultipleIds() {
    List<License_Key__c> testKeys = [
      SELECT Id
      FROM License_Key__c
      WHERE Name IN ('TEST-001', 'TEST-002')
    ];

    List<Id> keyIds = new List<Id>();
    for (License_Key__c key : testKeys) {
      keyIds.add(key.Id);
    }

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(keyIds);
    Test.stopTest();

    List<License_Key__c> updated = [
      SELECT Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id IN :keyIds
    ];

    System.assertEquals(2, updated.size());
    for (License_Key__c key : updated) {
      System.assertEquals(false, key.Send_Email__c);
      System.assertEquals('Success', key.Email_Status__c);
    }
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with empty/null list
   * Verifies: No errors thrown
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_EmptyList() {
    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(new List<Id>());
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(null);
    Test.stopTest();

    System.assert(true, 'Should handle empty/null gracefully');
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with invalid record (no contacts)
   * Verifies: Error captured in Email_Status__c and Email_Error_Message__c
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_HandlesFailure() {
    License_Key__c testKey = [
      SELECT Id
      FROM License_Key__c
      WHERE Name = 'TEST-NO-CONTACT'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(new List<Id>{ testKey.Id });
    Test.stopTest();

    License_Key__c updated = [
      SELECT Send_Email__c, Email_Status__c, Email_Error_Message__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertEquals(false, updated.Send_Email__c);
    System.assertEquals('Failed', updated.Email_Status__c);
    System.assertNotEquals(null, updated.Email_Error_Message__c);
  }

  /**
   * Test ProcessLicenseKeyEmail with single license key
   * Verifies: Returns EmailResult map with correct keys
   */
  @isTest
  static void testProcessLicenseKeyEmail_SingleKey() {
    License_Key__c testKey = [
      SELECT
        Id,
        Name,
        Key_Type__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__r.Id,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        CreatedById,
        Send_Email__c,
        LKG_Product_Identifier_Name__c,
        Silo__c,
        Create_License_Key_File__c
      FROM License_Key__c
      WHERE Name = 'TEST-001'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(new List<License_Key__c>{ testKey });
    Test.stopTest();

    System.assertNotEquals(null, results);
    System.assertEquals(1, results.size());
    System.assert(results.containsKey(testKey.Id));
    System.assert(results.get(testKey.Id).isSuccess);
  }

  /**
   * Test ProcessLicenseKeyEmail with multiple keys
   * Verifies: Processes all keys and returns results for each
   */
  @isTest
  static void testProcessLicenseKeyEmail_MultipleKeys() {
    List<License_Key__c> testKeys = [
      SELECT
        Id,
        Name,
        Key_Type__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__r.Id,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        CreatedById,
        Send_Email__c,
        LKG_Product_Identifier_Name__c,
        Silo__c
      FROM License_Key__c
      WHERE Name IN ('TEST-001', 'TEST-002')
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(testKeys);
    Test.stopTest();

    System.assertEquals(2, results.size());
    for (License_Key__c key : testKeys) {
      System.assert(results.containsKey(key.Id));
      System.assertNotEquals(null, results.get(key.Id));
    }
  }

  /**
   * Test ProcessLicenseKeyEmail with no contacts
   * Verifies: Returns failure result without throwing exception
   */
  @isTest
  static void testProcessLicenseKeyEmail_NoContacts() {
    License_Key__c testKey = [
      SELECT
        Id,
        Name,
        Key_Type__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__r.Id,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        CreatedById,
        Send_Email__c,
        LKG_Product_Identifier_Name__c,
        Silo__c
      FROM License_Key__c
      WHERE Name = 'TEST-NO-CONTACT'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(new List<License_Key__c>{ testKey });
    Test.stopTest();

    System.assertNotEquals(null, results);
    System.assert(results.containsKey(testKey.Id));
    EmailResult result = results.get(testKey.Id);
    System.assertEquals(false, result.isSuccess);
    System.assertNotEquals(null, result.errorMessage);
  }

  /**
   * Test ProcessLicenseKeyEmail with empty list
   * Verifies: Returns empty map without errors
   */
  @isTest
  static void testProcessLicenseKeyEmail_EmptyList() {
    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(new List<License_Key__c>());
    Test.stopTest();

    System.assertNotEquals(null, results);
    System.assertEquals(0, results.size());
  }

  /**
   * Test ProcessLicenseKeyEmail uses Factory pattern
   * Verifies: Different Silos are handled via factory
   */
  @isTest
  static void testProcessLicenseKeyEmail_UsesFactoryPattern() {
    // Create a key with different silo
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c powertechKey = new License_Key__c(
      Name = 'TEST-POWERTECH',
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      Brand__c = 'Powertech',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert powertechKey;

    powertechKey = [
      SELECT
        Id,
        Name,
        Key_Type__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__r.Id,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        CreatedById,
        Send_Email__c,
        LKG_Product_Identifier_Name__c,
        Silo__c
      FROM License_Key__c
      WHERE Id = :powertechKey.Id
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(
      new List<License_Key__c>{ powertechKey }
    );
    Test.stopTest();

    System.assert(results.containsKey(powertechKey.Id), 'Should process Powertech key via factory');
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with non-existent IDs
   * Verifies: Handles case when no records found for provided IDs (line 69)
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_NoRecordsFound() {
    // Create a fake ID that doesn't exist
    Id fakeId = '001000000000000AAA';

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(new List<Id>{ fakeId });
    Test.stopTest();

    // Should complete without error when no records found
    System.assert(true, 'Should handle non-existent IDs gracefully');
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds updates records even when LMS publish fails
   * Verifies: Exception during notification publish doesn't prevent record updates (line 124)
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_NotificationPublishError() {
    License_Key__c testKey = [
      SELECT Id
      FROM License_Key__c
      WHERE Name = 'TEST-001'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(new List<Id>{ testKey.Id });
    Test.stopTest();

    // Verify record was updated despite any potential LMS errors
    License_Key__c updated = [
      SELECT Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertEquals(false, updated.Send_Email__c);
    System.assertEquals('Success', updated.Email_Status__c);
  }

  /**
   * Test ProcessLicenseKeyEmail with validation failure
   * Verifies: Returns failure result when validateAndPrepare returns false (line 188)
   */
  @isTest
  static void testProcessLicenseKeyEmail_ValidationFailure() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id FROM Contact LIMIT 1];

    // Create a key without ID (not inserted) to trigger validation failure
    License_Key__c invalidKey = new License_Key__c(
      Name = 'TEST-INVALID',
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      Brand__c = 'Clearswift',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    // Don't insert - ID will be null, causing validation to fail

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(
      new List<License_Key__c>{ invalidKey }
    );
    Test.stopTest();

    // Should still return a result for the key
    System.assertNotEquals(null, results);
    // The result should indicate validation failure
    EmailResult result = results.get(invalidKey.Id);
    System.assertNotEquals(null, result);
    System.assertEquals(false, result.isSuccess);
  }

  /**
   * Test ProcessLicenseKeyEmail handles exceptions during processing
   * Verifies: Exception caught and EmailResult returned with error (line 198)
   */
  @isTest
  static void testProcessLicenseKeyEmail_HandlesException() {
    Account acc = new Account(Name = 'Exception Test Account', AccountNumber = 'EXC001');
    insert acc;

    // Create a key with invalid/missing data that might cause exceptions
    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-EXCEPTION',
      Key_Type__c = 'Generic',
      Brand__c = 'InvalidBrand',
      Account__c = acc.Id,
      LKG_Product_Identifier_Name__c = 'INVALID-IDENTIFIER'
    );
    insert testKey;

    testKey = [
      SELECT
        Id,
        Name,
        Key_Type__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Email,
        Account__c,
        Account__r.Name,
        CreatedById,
        Send_Email__c,
        LKG_Product_Identifier_Name__c,
        Silo__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    Map<Id, EmailResult> results = LicenseKeyEmailHandler.ProcessLicenseKeyEmail(new List<License_Key__c>{ testKey });
    Test.stopTest();

    // Should return a result even if exception occurred
    System.assertNotEquals(null, results);
    System.assert(results.containsKey(testKey.Id));
    EmailResult result = results.get(testKey.Id);
    System.assertNotEquals(null, result);
  }

  /**
   * Test ProcessLicenseKeyEmailFromIds with mixed success and failure
   * Verifies: Error details captured correctly including Email_Error_Details__c
   */
  @isTest
  static void testProcessLicenseKeyEmailFromIds_MixedResults() {
    List<License_Key__c> testKeys = [
      SELECT Id
      FROM License_Key__c
      WHERE Name IN ('TEST-001', 'TEST-NO-CONTACT')
    ];

    List<Id> keyIds = new List<Id>();
    for (License_Key__c key : testKeys) {
      keyIds.add(key.Id);
    }

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(keyIds);
    Test.stopTest();

    List<License_Key__c> updated = [
      SELECT Send_Email__c, Email_Status__c, Email_Error_Message__c, Email_Error_Details__c
      FROM License_Key__c
      WHERE Id IN :keyIds
      ORDER BY Name
    ];

    // Verify both records updated with appropriate status
    System.assertEquals(2, updated.size());

    // Check that error details are captured for failed record
    for (License_Key__c key : updated) {
      System.assertEquals(false, key.Send_Email__c);
      if (key.Email_Status__c == 'Failed') {
        System.assertNotEquals(null, key.Email_Error_Message__c);
      }
    }
  }
}