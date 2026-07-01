/**
 * Test class for EmailService
 * Lightweight tests focused on core email sending functionality:
 * 1. sendLicenseKeyEmail - main email sending with validations
 * 2. Helper methods - template and contact ID retrieval
 */
@isTest
private class EmailServiceTest {
  /**
   * Setup minimal test data - only what's needed for email service tests
   */
  @TestSetup
  static void setupTestData() {
    // Create Email Template in separate context to avoid mixed DML
    System.runAs(new User(Id = UserInfo.getUserId())) {
      EmailTemplate template = new EmailTemplate(
        DeveloperName = 'Test_Email_Template',
        FolderId = UserInfo.getUserId(),
        TemplateType = 'text',
        Name = 'Test Template',
        Subject = 'Test Subject: {License_Key__c.Name}',
        Body = 'Plain text: {License_Key__c.Name}',
        HtmlValue = '<html><body>HTML: {License_Key__c.Name}</body></html>',
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

    // Create license key with mandatory fields
    License_Key__c key = new License_Key__c(
      Name = 'TEST-KEY',
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert key;
  }

  // /**
  //  * Test successful email sending with single recipient
  //  * Verifies: Email sent successfully, proper EmailResult returned
  //  */
  // @isTest
  // static void testSendLicenseKeyEmail_Success_SingleRecipient() {
  //   License_Key__c testKey = [
  //     SELECT Id, Name, Contact_1__c, LKG_Product_Identifier_Name__c
  //     FROM License_Key__c
  //     LIMIT 1
  //   ];

  //   // Inject mock email sender
  //   MockEmailSender mockSender = new MockEmailSender();
  //   mockSender.shouldSucceed = true;
  //   EmailService.emailSender = mockSender;

  //   Test.startTest();
  //   EmailResult result = EmailService.sendLicenseKeyEmail(
  //     testKey,
  //     'Test_Email_Template',
  //     new List<String>{ 'test@example.com' },
  //     null,
  //     null
  //   );
  //   Test.stopTest();

  //   System.assertNotEquals(null, result, 'Result should not be null');
  //   System.assert(
  //     result.isSuccess,
  //     'Email should succeed. Error: ' + result.errorMessage + ' | Details: ' + result.errorDetails
  //   );
  //   System.assertEquals(null, result.errorMessage);
  // }

  // /**
  //  * Test successful email sending with multiple recipients
  //  * Verifies: Multiple recipients handled correctly
  //  */
  // @isTest
  // static void testSendLicenseKeyEmail_Success_MultipleRecipients() {
  //   License_Key__c testKey = [
  //     SELECT Id, Name, Contact_1__c, LKG_Product_Identifier_Name__c
  //     FROM License_Key__c
  //     LIMIT 1
  //   ];

  //   // Inject mock email sender
  //   MockEmailSender mockSender = new MockEmailSender();
  //   mockSender.shouldSucceed = true;
  //   EmailService.emailSender = mockSender;

  //   Test.startTest();
  //   EmailResult result = EmailService.sendLicenseKeyEmail(
  //     testKey,
  //     'Test_Email_Template',
  //     new List<String>{ 'test1@example.com', 'test2@example.com' },
  //     null,
  //     null
  //   );
  //   Test.stopTest();

  //   System.assert(result.isSuccess);
  // }

  // /**
  //  * Test email sending with BCC recipients
  //  * Verifies: BCC addresses handled correctly
  //  */
  // @isTest
  // static void testSendLicenseKeyEmail_WithBCC() {
  //   License_Key__c testKey = [
  //     SELECT Id, Name, Contact_1__c, LKG_Product_Identifier_Name__c
  //     FROM License_Key__c
  //     LIMIT 1
  //   ];

  //   // Inject mock email sender
  //   MockEmailSender mockSender = new MockEmailSender();
  //   mockSender.shouldSucceed = true;
  //   EmailService.emailSender = mockSender;

  //   Test.startTest();
  //   EmailResult result = EmailService.sendLicenseKeyEmail(
  //     testKey,
  //     'Test_Email_Template',
  //     new List<String>{ 'test@example.com' },
  //     new List<String>{ 'bcc@example.com' },
  //     null
  //   );
  //   Test.stopTest();

  //   System.assert(result.isSuccess);
  // }

  // /**
  //  * Test email sending with merge fields
  //  * Verifies: Custom merge fields replaced in template
  //  */
  // @isTest
  // static void testSendLicenseKeyEmail_WithMergeFields() {
  //   License_Key__c testKey = [
  //     SELECT Id, Name, Contact_1__c, LKG_Product_Identifier_Name__c
  //     FROM License_Key__c
  //     LIMIT 1
  //   ];

  //   Map<String, String> mergeFields = new Map<String, String>{
  //     'License_Key__c.Name' => testKey.Name,
  //     'License_Key__c.Account__r.Name' => 'Test Account'
  //   };

  //   // Inject mock email sender
  //   MockEmailSender mockSender = new MockEmailSender();
  //   mockSender.shouldSucceed = true;
  //   EmailService.emailSender = mockSender;

  //   Test.startTest();
  //   EmailResult result = EmailService.sendLicenseKeyEmail(
  //     testKey,
  //     'Test_Email_Template',
  //     new List<String>{ 'test@example.com' },
  //     null,
  //     mergeFields
  //   );
  //   Test.stopTest();

  //   System.assert(result.isSuccess);
  // }

  // /**
  //  * Test overloaded method (simplified signature)
  //  * Verifies: Overloaded method delegates correctly
  //  */
  // @isTest
  // static void testSendLicenseKeyEmail_OverloadedMethod() {
  //   License_Key__c testKey = [
  //     SELECT Id, Name, Contact_1__c, LKG_Product_Identifier_Name__c
  //     FROM License_Key__c
  //     LIMIT 1
  //   ];

  //   // Inject mock email sender
  //   MockEmailSender mockSender = new MockEmailSender();
  //   mockSender.shouldSucceed = true;
  //   EmailService.emailSender = mockSender;

  //   Test.startTest();
  //   EmailResult result = EmailService.sendLicenseKeyEmail(
  //     testKey,
  //     'Test_Email_Template',
  //     new List<String>{ 'test@example.com' }
  //   );
  //   Test.stopTest();

  //   System.assert(result.isSuccess);
  // }

  /**
   * Test email sending fails with blank template name
   * Verifies: Validation error returned for blank template
   */
  @isTest
  static void testSendLicenseKeyEmail_BlankTemplate() {
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
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(
      testKey,
      '',
      new List<String>{ 'test@example.com' },
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(result.errorMessage.contains('template'));
  }

  /**
   * Test email sending fails with null template name
   * Verifies: Validation error returned for null template
   */
  @isTest
  static void testSendLicenseKeyEmail_NullTemplate() {
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
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(
      testKey,
      null,
      new List<String>{ 'test@example.com' },
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(result.errorMessage.contains('template'));
  }

  /**
   * Test email sending fails with non-existent template
   * Verifies: Error returned when template not found
   */
  @isTest
  static void testSendLicenseKeyEmail_TemplateNotFound() {
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
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(
      testKey,
      'NonExistent_Template',
      new List<String>{ 'test@example.com' },
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(result.errorMessage.contains('not found'));
  }

  /**
   * Test email sending fails with null LKG_Product_Identifier_Name__c
   * Verifies: Validation error for missing License Key Product Identifier
   */
  @isTest
  static void testSendLicenseKeyEmail_NullProductCode() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact contact = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-NO-PRODUCT-IDENTIFIER',
      Key_Type__c = 'Generic',
      Account__c = acc.Id,
      Contact_1__c = contact.Id,
      LKG_Product_Identifier_Name__c = null
    );
    insert testKey;

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(
      testKey,
      'Test_Email_Template',
      new List<String>{ 'test@example.com' },
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(result.errorMessage.contains('License Key Product Identifier'));
  }

  /**
   * Test email sending fails with null recipients
   * Verifies: Validation error for null recipient list
   */
  @isTest
  static void testSendLicenseKeyEmail_NullRecipient() {
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
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(testKey, 'Test_Email_Template', null, null, null);
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
  }

  /**
   * Test email sending fails with empty recipient list
   * Verifies: Validation error for empty recipient list
   */
  @isTest
  static void testSendLicenseKeyEmail_EmptyRecipientList() {
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
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    EmailResult result = EmailService.sendLicenseKeyEmail(
      testKey,
      'Test_Email_Template',
      new List<String>(),
      null,
      null
    );
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
  }

  /**
   * Test getEmailTemplateId with valid template
   * Verifies: Template ID retrieved correctly
   */
  @isTest
  static void testGetEmailTemplateId_Valid() {
    Test.startTest();
    Id templateId = EmailService.getEmailTemplateId('Test_Email_Template');
    Test.stopTest();

    System.assertNotEquals(null, templateId);
  }

  /**
   * Test getEmailTemplateId with invalid template
   * Verifies: Returns null for non-existent template
   */
  @isTest
  static void testGetEmailTemplateId_Invalid() {
    Test.startTest();
    Id templateId = EmailService.getEmailTemplateId('NonExistent_Template');
    Test.stopTest();

    System.assertEquals(null, templateId);
  }

  /**
   * Test getContactId with valid Contact_1__c
   * Verifies: Contact ID returned correctly
   */
  @isTest
  static void testGetContactId_ValidContact() {
    License_Key__c testKey = [
      SELECT Id, Contact_1__c
      FROM License_Key__c
      LIMIT 1
    ];

    Test.startTest();
    Id contactId = EmailService.getContactId(testKey);
    Test.stopTest();

    System.assertEquals(testKey.Contact_1__c, contactId);
  }

  /**
   * Test getContactId with null contact
   * Verifies: Returns null when no contact present
   */
  @isTest
  static void testGetContactId_NullContact() {
    Account acc = [SELECT Id FROM Account LIMIT 1];

    License_Key__c testKey = new License_Key__c(
      Name = 'TEST-NO-CONTACT',
      Account__c = acc.Id,
      Contact_1__c = null,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert testKey;

    Test.startTest();
    Id contactId = EmailService.getContactId(testKey);
    Test.stopTest();

    System.assertEquals(null, contactId);
  }

  /**
   * Test template content retrieval methods
   * Verifies: HTML, plain text, and subject retrieved correctly
   */
  @isTest
  static void testGetTemplateContent_AllFields() {
    EmailTemplate template = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = 'Test_Email_Template'
      LIMIT 1
    ];

    Test.startTest();
    String htmlBody = EmailService.getTemplateHtmlBody(template.Id);
    String plainBody = EmailService.getTemplatePlainTextBody(template.Id);
    String subject = EmailService.getTemplateSubject(template.Id);
    Test.stopTest();

    System.assertNotEquals(null, htmlBody);
    System.assertNotEquals(null, plainBody);
    System.assertNotEquals(null, subject);
  }

  /**
   * Test template retrieval when HTML is null
   * Verifies: Returns null for null HTML field
   */
  @isTest
  static void testGetTemplateContent_NullHtml() {
    EmailTemplate template = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = 'Test_Email_Template'
      LIMIT 1
    ];

    template.HtmlValue = null;
    update template;

    Test.startTest();
    String htmlBody = EmailService.getTemplateHtmlBody(template.Id);
    Test.stopTest();

    System.assertEquals(null, htmlBody);
  }

  /**
   * Test template retrieval when plain text body is null
   * Verifies: Returns null for null Body field
   */
  @isTest
  static void testGetTemplateContent_NullPlainText() {
    EmailTemplate template = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = 'Test_Email_Template'
      LIMIT 1
    ];

    template.Body = null;
    update template;

    Test.startTest();
    String plainBody = EmailService.getTemplatePlainTextBody(template.Id);
    Test.stopTest();

    System.assertEquals(null, plainBody);
  }

  /**
   * Test template retrieval when subject is null
   * Verifies: Returns null for null Subject field
   */
  @isTest
  static void testGetTemplateContent_NullSubject() {
    EmailTemplate template = [
      SELECT Id
      FROM EmailTemplate
      WHERE DeveloperName = 'Test_Email_Template'
      LIMIT 1
    ];

    template.Subject = null;
    update template;

    Test.startTest();
    String subject = EmailService.getTemplateSubject(template.Id);
    Test.stopTest();

    System.assertEquals(null, subject);
  }

  /**
   * Test EmailServiceException
   * Verifies: Custom exception works correctly
   */
  @isTest
  static void testEmailServiceException() {
    String exceptionMessage = 'Test exception message';
    Boolean exceptionThrown = false;

    Test.startTest();
    try {
      throw new EmailService.EmailServiceException(exceptionMessage);
    } catch (EmailService.EmailServiceException e) {
      exceptionThrown = true;
      System.assertEquals(exceptionMessage, e.getMessage());
    }
    Test.stopTest();

    System.assert(exceptionThrown);
  }
}