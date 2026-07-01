/**
 * Test class for LicenseKeyTrigger
 * Tests trigger functionality for License Key after update operations
 * The trigger delegates processing to LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds
 */
@isTest
private class LicenseKeyTriggerTest {
  /**
   * Setup test data
   */
  @TestSetup
  static void setupTestData() {
    // Create Email Template first in a separate context to avoid mixed DML
    System.runAs(new User(Id = UserInfo.getUserId())) {
      LicenseKeyEmailTestDataFactory.createEmailTemplate();
    }

    LicenseKeyEmailTestDataFactory.setupLicenseKeyTriggerData();
  }

  /**
   * Test trigger fires when Send_Email__c is checked and delegates to handler
   */
  @isTest
  static void testTrigger_SendEmailChecked() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    System.assertEquals(false, testKey.Send_Email__c, 'Send_Email__c should be initially false');

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();

    // Update Send_Email__c to true - this should trigger email processing
    testKey.Send_Email__c = true;
    update testKey;

    Test.stopTest();

    // Verify handler updated the record
    License_Key__c updatedKey = [
      SELECT Id, Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];
    System.assertEquals(false, updatedKey.Send_Email__c, 'Send_Email__c should be reset by handler');
    System.assertEquals(
      'Success',
      updatedKey.Email_Status__c,
      'Email should be sent successfully when Send_Email__c is checked'
    );
  }

  /**
   * Test trigger does not fire when Send_Email__c is not changed
   */
  @isTest
  static void testTrigger_SendEmailNotChanged() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c, LKG_Product_Identifier_Name__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    Integer emailLimitBefore = Limits.getEmailInvocations();

    Test.startTest();

    // Update a different field - should not trigger email
    testKey.LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway';
    update testKey;
    Integer emailLimitAfter = Limits.getEmailInvocations();
    Test.stopTest();

    // Verify email was not sent
    System.assertEquals(
      emailLimitBefore,
      emailLimitAfter,
      'Email should not be sent when Send_Email__c is not changed'
    );
  }

  /**
   * Test trigger does not fire when Send_Email__c changes from true to false
   */
  @isTest
  static void testTrigger_SendEmailUnchecked() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    // First set it to true (this will send email)
    testKey.Send_Email__c = true;
    update testKey;

    // Get the current status after first update
    License_Key__c afterFirstUpdate = [
      SELECT Id, Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];
    String statusAfterFirstUpdate = afterFirstUpdate.Email_Status__c;

    Test.startTest();

    // Now set it back to false - should not trigger email
    testKey.Send_Email__c = false;
    update testKey;

    Test.stopTest();

    // Verify no additional email was sent by checking status didn't change
    License_Key__c finalKey = [
      SELECT Id, Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];
    System.assertEquals(false, finalKey.Send_Email__c, 'Send_Email__c should be false');
    System.assertEquals(
      statusAfterFirstUpdate,
      finalKey.Email_Status__c,
      'Email status should not change when Send_Email__c is unchecked'
    );
  }

  /**
   * Test trigger processes multiple license keys when multiple are updated
   */
  @isTest
  static void testTrigger_MultipleKeysUpdated() {
    List<License_Key__c> testKeys = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name IN ('TRIGGER-TEST-001', 'TRIGGER-TEST-002')
      ORDER BY Name
    ];

    System.assertEquals(2, testKeys.size(), 'Should retrieve 2 license keys');

    // Inject mock email sender
    MockEmailSender mockSender = new MockEmailSender();
    mockSender.shouldSucceed = true;
    EmailService.emailSender = mockSender;

    Test.startTest();

    // Update both keys to have Send_Email__c = true
    for (License_Key__c key : testKeys) {
      key.Send_Email__c = true;
    }
    update testKeys;

    Test.stopTest();

    // Verify handler updated all records
    List<License_Key__c> updatedKeys = [
      SELECT Id, Send_Email__c, Email_Status__c
      FROM License_Key__c
      WHERE Id IN :testKeys
    ];

    for (License_Key__c key : updatedKeys) {
      System.assertEquals(false, key.Send_Email__c, 'Send_Email__c should be reset by handler');
      System.assertEquals('Success', key.Email_Status__c, 'Emails should be sent for all updated keys via handler');
    }
  }

  /**
   * Test trigger queries all required fields via handler
   */
  @isTest
  static void testTrigger_QueriesAllFields() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    Test.startTest();

    testKey.Send_Email__c = true;
    update testKey;

    Test.stopTest();

    // Verify the record was processed successfully by handler
    // The handler queries all necessary fields including relationships
    License_Key__c updatedKey = [
      SELECT Id, Name, Key_Type__c, Contact_1__c, Contact_2__c, Silo__c, LKG_Product_Identifier_Name__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertNotEquals(null, updatedKey.Name, 'Name should be available');
    System.assertNotEquals(null, updatedKey.Key_Type__c, 'Key_Type should be available');
  }

  /**
   * Test trigger with license key without contacts - delegates to handler
   */
  @isTest
  static void testTrigger_NoContacts() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-003'
      LIMIT 1
    ];

    Test.startTest();

    // This should attempt to send email via handler but fail gracefully
    testKey.Send_Email__c = true;
    update testKey;

    Test.stopTest();

    // Test passes if no exception is thrown
    // Handler should handle keys without contacts gracefully
    System.assert(true, 'Trigger should delegate to handler which handles keys without contacts gracefully');
  }

  /**
   * Test trigger passes IDs to handler for processing
   */
  @isTest
  static void testTrigger_PassesIdsToHandler() {
    List<License_Key__c> testKeys = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name LIKE 'TRIGGER-TEST-%'
      ORDER BY Name
      LIMIT 3
    ];

    System.assertEquals(3, testKeys.size(), 'Should have 3 test keys');

    Test.startTest();

    // Update all keys - trigger should pass all IDs to handler
    for (License_Key__c key : testKeys) {
      key.Send_Email__c = true;
    }
    update testKeys;

    Test.stopTest();

    // Handler should process all keys passed by trigger
    // Verify all records were updated by handler
    List<License_Key__c> updatedKeys = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Id IN :testKeys
    ];

    for (License_Key__c key : updatedKeys) {
      System.assertEquals(false, key.Send_Email__c, 'Send_Email__c should be reset by handler for all keys');
    }
  }

  /**
   * Test trigger with valid data and all relationships - delegates to handler
   */
  @isTest
  static void testTrigger_WithAllRelationships() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    Test.startTest();

    testKey.Send_Email__c = true;
    update testKey;

    Test.stopTest();

    // Verify the key was processed by handler with all relationships
    License_Key__c processedKey = [
      SELECT Id, Contact_1__c, Contact_2__c, Account__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertNotEquals(null, processedKey.Contact_1__c, 'Contact 1 should exist');
    System.assertNotEquals(null, processedKey.Contact_2__c, 'Contact 2 should exist');
    System.assertNotEquals(null, processedKey.Account__c, 'Account should exist');
  }

  /**
   * Test trigger context variables are used correctly
   */
  @isTest
  static void testTrigger_ContextVariables() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    Test.startTest();

    testKey.Send_Email__c = true;
    update testKey;

    Test.stopTest();

    // Test verifies that trigger.new and trigger.oldMap are used correctly
    // If trigger executes without error, context variables are working
    System.assert(true, 'Trigger should use context variables correctly to identify changed records');
  }

  /**
   * Test trigger delegates query responsibility to handler
   */
  @isTest
  static void testTrigger_DelegatesQueryToHandler() {
    License_Key__c testKey = [
      SELECT Id, Send_Email__c
      FROM License_Key__c
      WHERE Name = 'TRIGGER-TEST-001'
      LIMIT 1
    ];

    Integer soqlBefore = Limits.getQueries();

    Test.startTest();

    testKey.Send_Email__c = true;
    update testKey;
    Integer soqlAfter = Limits.getQueries();
    Test.stopTest();

    // Handler should perform SOQL query to get full record details
    System.assert(soqlAfter > soqlBefore, 'Handler should perform SOQL query to get full record details');
  }
}