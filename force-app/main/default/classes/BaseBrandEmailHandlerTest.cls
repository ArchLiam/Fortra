/**
 * Lightweight test class for BaseBrandEmailHandler
 * Tests individual functions without heavy test data setup
 */
@isTest
private class BaseBrandEmailHandlerTest {
  /**
   * Concrete implementation for testing
   * Only overrides getAdditionalMergeFields to add a test field
   * All other methods use default base class implementation
   */
  private class TestBrandEmailHandler extends BaseBrandEmailHandler {
    public override Map<String, String> getAdditionalMergeFields(License_Key__c licenseKey) {
      // Call base class method to get common fields
      Map<String, String> fields = super.getAdditionalMergeFields(licenseKey);
      // Add test-specific field
      fields.put('Test_Field', 'Test_Value');
      return fields;
    }
  }

  /**
   * Test getRecipient1Email extracts email correctly
   */
  @isTest
  static void testGetRecipient1Email() {
    Contact c = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com');
    License_Key__c key = new License_Key__c(Contact_1__r = c);

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    System.assertEquals('test@example.com', handler.getRecipient1Email(key));
  }

  /**
   * Test getRecipient1Email returns null when no contact
   */
  @isTest
  static void testGetRecipient1Email_Null() {
    License_Key__c key = new License_Key__c();

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    System.assertEquals(null, handler.getRecipient1Email(key));
  }

  /**
   * Test getRecipient2Email extracts email correctly
   */
  @isTest
  static void testGetRecipient2Email() {
    Contact c = new Contact(FirstName = 'Test', LastName = 'Contact2', Email = 'test2@example.com');
    License_Key__c key = new License_Key__c(Contact_2__r = c);

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    System.assertEquals('test2@example.com', handler.getRecipient2Email(key));
  }

  /**
   * Test getRecipient2Email returns null when no contact
   */
  @isTest
  static void testGetRecipient2Email_Null() {
    License_Key__c key = new License_Key__c();

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    System.assertEquals(null, handler.getRecipient2Email(key));
  }

  /**
   * Test buildRecipientList with both contacts
   */
  @isTest
  static void testBuildRecipientList_BothContacts() {
    Contact c1 = new Contact(Email = 'test1@example.com');
    Contact c2 = new Contact(Email = 'test2@example.com');
    License_Key__c key = new License_Key__c(Contact_1__r = c1, Contact_2__r = c2);

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    List<String> recipients = handler.buildRecipientList(key);

    System.assertEquals(2, recipients.size());
    System.assert(recipients.contains('test1@example.com'));
    System.assert(recipients.contains('test2@example.com'));
  }

  /**
   * Test buildRecipientList with one contact
   */
  @isTest
  static void testBuildRecipientList_OneContact() {
    Contact c1 = new Contact(Email = 'test1@example.com');
    License_Key__c key = new License_Key__c(Contact_1__r = c1);

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    List<String> recipients = handler.buildRecipientList(key);

    System.assertEquals(1, recipients.size());
    System.assertEquals('test1@example.com', recipients[0]);
  }

  /**
   * Test buildRecipientList throws exception when no contacts
   */
  @isTest
  static void testBuildRecipientList_NoContacts() {
    License_Key__c key = new License_Key__c();
    TestBrandEmailHandler handler = new TestBrandEmailHandler();

    try {
      handler.buildRecipientList(key);
      System.assert(false, 'Should have thrown exception');
    } catch (EmailService.EmailServiceException e) {
      System.assert(e.getMessage().contains('No valid contact email addresses'), 'Should throw proper exception');
    }
  }

  /**
   * Test nvl helper method
   */
  @isTest
  static void testNvl() {
    TestBrandEmailHandler handler = new TestBrandEmailHandler();

    System.assertEquals('', handler.nvl(null));
    System.assertEquals('test', handler.nvl('test'));
    System.assertEquals('', handler.nvl(''));
  }

  /**
   * Test validateAndPrepare with null Id
   */
  @isTest
  static void testValidateAndPrepare_NullId() {
    License_Key__c key = new License_Key__c();

    TestBrandEmailHandler handler = new TestBrandEmailHandler();
    System.assert(!handler.validateAndPrepare(key));
  }

  /**
   * Test validateAndPrepare with valid License Key
   */
  @isTest
  static void testValidateAndPrepare_Valid() {
    // Create test account and contact
    Account acc = new Account(Name = 'Test Account');
    insert acc;

    Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com', AccountId = acc.Id);
    insert con;

    // Create license key with all required fields
    License_Key__c key = new License_Key__c(
      Name = 'TEST-VALIDATE',
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert key;

    TestBrandEmailHandler handler = new TestBrandEmailHandler();

    Test.startTest();
    Boolean isValid = handler.validateAndPrepare(key);
    Test.stopTest();

    System.assert(isValid, 'Should validate successfully with valid License Key');
  }

  /**
   * Test getEmailTemplateForLicenseKey delegates to LicenseKeyTemplateResolver
   */
  @isTest
  static void testGetEmailTemplateForLicenseKey() {
    // Create test account and contact
    Account acc = new Account(Name = 'Test Account');
    insert acc;

    Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com', AccountId = acc.Id);
    insert con;

    // Create license key with valid product identifier
    License_Key__c key = new License_Key__c(
      Name = 'TEST-001',
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert key;

    TestBrandEmailHandler handler = new TestBrandEmailHandler();

    Test.startTest();
    String templateName = handler.getEmailTemplateForLicenseKey(key);
    Test.stopTest();

    System.assertNotEquals(null, templateName, 'Template name should not be null');
    System.assert(String.isNotBlank(templateName), 'Template name should not be blank');
  }

  /**
   * Test virtual method implementations and overrides
   */
  @isTest
  static void testVirtualMethodsAndOverrides() {
    // Create test account and contact for sendEmail
    Account acc = new Account(Name = 'Test Account', AccountNumber = 'ACC-001');
    insert acc;

    Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com', AccountId = acc.Id);
    insert con;

    License_Key__c key = new License_Key__c(
      Name = 'TEST-001',
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      CreatedById = UserInfo.getUserId()
    );
    insert key;

    // Requery with all required fields
    key = [
      SELECT
        Id,
        Name,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        Contact_1__c,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__c,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Key_Type__c,
        LKG_Product_Identifier_Name__c,
        CreatedById
      FROM License_Key__c
      WHERE Id = :key.Id
    ];

    TestBrandEmailHandler handler = new TestBrandEmailHandler();

    // Test getAdditionalMergeFields override
    Map<String, String> fields = handler.getAdditionalMergeFields(key);
    System.assert(fields.containsKey('Test_Field'), 'Should contain custom field from override');
    System.assertEquals('Test_Value', fields.get('Test_Field'));
    // Verify it also has base common fields
    System.assert(fields.containsKey('License_Key__c.Name'), 'Should contain base Name field');

    // Test validateAndPrepare with valid key
    Boolean isValid = handler.validateAndPrepare(key);
    System.assert(isValid, 'Should validate successfully with valid key');

    // Test sendEmail inherits from base class
    Test.startTest();
    EmailResult result = handler.sendEmail(key);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return EmailResult');
  }
}