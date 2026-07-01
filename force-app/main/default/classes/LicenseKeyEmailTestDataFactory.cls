/**
 * Test data factory for License Key email testing
 * Provides centralized methods to create test data for all email-related test classes
 */
@isTest
public class LicenseKeyEmailTestDataFactory {
  // Constants for test data
  public static final String TEST_ACCOUNT_NAME = 'Test Account';
  public static final String TEST_BRAND_CLEARSWIFT = 'Clearswift';
  public static final String TEST_SILO_CLEARSWIFT = 'Clearswift';
  public static final String TEST_PRODUCTCODE_CLEARSWIFT = '12';
  public static final String TEST_EMAIL_TEMPLATE = 'Fortra_License_Key_Clearswift_Default_Email_Template';

  /**
   * Creates an Email Template for testing
   * Must be called within System.runAs(new User(Id = UserInfo.getUserId()))
   */
  public static EmailTemplate createEmailTemplate() {
    return createEmailTemplate(TEST_EMAIL_TEMPLATE);
  }

  /**
   * Creates an Email Template with custom developer name
   */
  public static EmailTemplate createEmailTemplate(String developerName) {
    EmailTemplate template = new EmailTemplate(
      DeveloperName = developerName,
      FolderId = UserInfo.getUserId(),
      TemplateType = 'text',
      Name = 'Test Handler Template',
      Subject = 'Test Subject',
      Body = 'Test Body',
      HtmlValue = '<html><body>Test</body></html>',
      IsActive = true
    );
    insert template;
    return template;
  }

  /**
   * Creates a test Account
   */
  public static Account createAccount() {
    return createAccount(TEST_ACCOUNT_NAME);
  }

  /**
   * Creates a test Account with custom name
   */
  public static Account createAccount(String accountName) {
    Account acc = new Account(
      Name = accountName,
      AccountNumber = 'ACC-' + String.valueOf(Math.random()).substring(2, 10)
    );
    insert acc;
    return acc;
  }

  /**
   * Creates a Hardware record for testing
   */
  public static Hardware__c createHardware(Id accountId) {
    Hardware__c hardware = new Hardware__c(
      Account__c = accountId,
      Serial_Number__c = '1234567890',
      Hardware_Type__c = 'Production'
    );
    insert hardware;
    return hardware;
  }

  /**
   * Creates test Contacts
   * Returns a list of 2 contacts by default
   */
  public static List<Contact> createContacts(Id accountId) {
    return createContacts(accountId, 2);
  }

  /**
   * Creates specified number of test Contacts
   */
  public static List<Contact> createContacts(Id accountId, Integer count) {
    List<Contact> contacts = new List<Contact>();
    for (Integer i = 1; i <= count; i++) {
      contacts.add(
        new Contact(
          FirstName = 'Contact',
          LastName = 'Test' + i,
          Email = 'contact' + i + '@test.com',
          AccountId = accountId
        )
      );
    }
    insert contacts;
    return contacts;
  }

  /**
   * Creates a test Contact with custom details
   */
  public static Contact createContact(Id accountId, String firstName, String lastName, String email) {
    Contact contact = new Contact(FirstName = firstName, LastName = lastName, Email = email, AccountId = accountId);
    insert contact;
    return contact;
  }

  /**
   * Creates a basic License Key with required fields
   */
  public static License_Key__c createLicenseKey(Id accountId, String name, String brand, String keyType) {
    License_Key__c key = new License_Key__c(
      Name = name,
      Brand__c = brand,
      Key_Type__c = keyType,
      Account__c = accountId,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Send_Email__c = false
    );
    insert key;
    return key;
  }

  /**
   * Creates a License Key with contacts
   */
  public static License_Key__c createLicenseKeyWithContacts(
    Id accountId,
    String name,
    String brand,
    String keyType,
    Id contact1Id,
    Id contact2Id
  ) {
    License_Key__c key = new License_Key__c(
      Name = name,
      Brand__c = brand,
      Key_Type__c = keyType,
      Account__c = accountId,
      Contact_1__c = contact1Id,
      Contact_2__c = contact2Id,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Send_Email__c = false
    );
    insert key;
    return key;
  }

  /**
   * Creates a Clearswift License Key with full details
   */
  public static License_Key__c createClearswiftLicenseKey(
    Id accountId,
    Id contact1Id,
    Id contact2Id,
    String name,
    String keyType,
    String licenseKey,
    String productCode
  ) {
    License_Key__c key = new License_Key__c(
      Name = name,
      Brand__c = TEST_BRAND_CLEARSWIFT,
      Key_Type__c = keyType,
      License_Key__c = licenseKey,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Account__c = accountId,
      Contact_1__c = contact1Id,
      Contact_2__c = contact2Id,
      Send_Email__c = false
    );
    insert key;
    return key;
  }

  /**
   * Creates a Clearswift License Key with Hardware reference
   */
  public static License_Key__c createClearswiftLicenseKeyWithHardware(
    Id accountId,
    Id hardwareId,
    Id contact1Id,
    Id contact2Id,
    String name,
    String keyType,
    String licenseKey,
    String productCode
  ) {
    License_Key__c key = new License_Key__c(
      Name = name,
      Brand__c = TEST_BRAND_CLEARSWIFT,
      Key_Type__c = keyType,
      License_Key__c = licenseKey,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Hardware__c = hardwareId,
      Account__c = accountId,
      Contact_1__c = contact1Id,
      Contact_2__c = contact2Id,
      Send_Email__c = false
    );
    insert key;
    return key;
  }

  /**
   * Creates a subscription License Key with dates
   */
  public static License_Key__c createSubscriptionLicenseKey(
    Id accountId,
    Id contact1Id,
    String name,
    String brand,
    String licenseKey,
    String productCode,
    Date startDate,
    Date endDate
  ) {
    License_Key__c key = new License_Key__c(
      Name = name,
      Brand__c = brand,
      Key_Type__c = 'Subscription',
      License_Key__c = licenseKey,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Start_Date__c = startDate,
      End_Date__c = endDate,
      Account__c = accountId,
      Contact_1__c = contact1Id,
      Send_Email__c = false
    );
    insert key;
    return key;
  }

  /**
   * Complete setup for BaseBrandEmailHandler tests
   */
  public static Map<String, Object> setupBaseBrandEmailHandlerData() {
    Account testAccount = createAccount('Test Account');
    List<Contact> contacts = createContacts(testAccount.Id);

    List<License_Key__c> testKeys = new List<License_Key__c>();

    // License Key with both contacts
    testKeys.add(
      new License_Key__c(
        Name = 'TEST-KEY-WITH-CONTACTS',
        Brand__c = 'Test Brand',
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Contact_2__c = contacts[1].Id,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Send_Email__c = false
      )
    );

    // License Key with only Contact 1
    testKeys.add(
      new License_Key__c(
        Name = 'TEST-KEY-CONTACT1-ONLY',
        Brand__c = 'Test Brand',
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Send_Email__c = false
      )
    );

    // License Key with only Contact 2
    testKeys.add(
      new License_Key__c(
        Name = 'TEST-KEY-CONTACT2-ONLY',
        Brand__c = 'Test Brand',
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Contact_2__c = contacts[1].Id,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Send_Email__c = false
      )
    );

    // License Key without contacts
    testKeys.add(
      new License_Key__c(
        Name = 'TEST-KEY-NO-CONTACTS',
        Brand__c = 'Test Brand',
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Send_Email__c = false
      )
    );

    insert testKeys;

    return new Map<String, Object>{ 'account' => testAccount, 'contacts' => contacts, 'licenseKeys' => testKeys };
  }

  /**
   * Complete setup for Clearswift email handler tests
   */
  public static Map<String, Object> setupClearswiftEmailHandlerData() {
    Account testAccount = createAccount('Clearswift Test Account');
    Hardware__c hardware = createHardware(testAccount.Id);

    List<Contact> contacts = new List<Contact>();
    contacts.add(createContact(testAccount.Id, 'Clearswift', 'Contact1', 'clearswift1@test.com'));
    contacts.add(createContact(testAccount.Id, 'Clearswift', 'Contact2', 'clearswift2@test.com'));

    List<License_Key__c> testKeys = new List<License_Key__c>();

    // Generic key type
    testKeys.add(
      new License_Key__c(
        Name = 'CLEARSWIFT-GENERIC-001',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        License_Key__c = 'GEN-1234-5678',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Hardware__c = hardware.Id,
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Contact_2__c = contacts[1].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    // Specific/Temporary key type
    testKeys.add(
      new License_Key__c(
        Name = 'CLEARSWIFT-SPECIFIC-001',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Specific/Temporary',
        License_Key__c = 'SPEC-1234-5678',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    // Subscription key type
    testKeys.add(
      new License_Key__c(
        Name = 'CLEARSWIFT-SUBSCRIPTION-001',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Subscription',
        License_Key__c = 'SUB-1234-5678',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Start_Date__c = Date.today(),
        End_Date__c = Date.today().addDays(365),
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    // Key with no contacts
    testKeys.add(
      new License_Key__c(
        Name = 'CLEARSWIFT-NO-CONTACTS',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Send_Email__c = false,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        CreatedById = UserInfo.getUserId()
      )
    );

    insert testKeys;

    return new Map<String, Object>{
      'account' => testAccount,
      'hardware' => hardware,
      'contacts' => contacts,
      'licenseKeys' => testKeys
    };
  }

  /**
   * Complete setup for Email Service tests
   */
  public static Map<String, Object> setupEmailServiceData() {
    Account testAccount = createAccount('Test Account for Email Service');

    List<Contact> contacts = new List<Contact>();
    contacts.add(createContact(testAccount.Id, 'John', 'Doe', 'john.doe@test.com'));
    contacts.add(createContact(testAccount.Id, 'Jane', 'Smith', 'jane.smith@test.com'));

    License_Key__c testLicenseKey = new License_Key__c(
      Name = 'TEST-KEY-001',
      Brand__c = TEST_BRAND_CLEARSWIFT,
      Key_Type__c = 'Generic',
      License_Key__c = 'ABCD-1234-EFGH-5678',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
      Account__c = testAccount.Id,
      Contact_1__c = contacts[0].Id,
      Contact_2__c = contacts[1].Id,
      Send_Email__c = false
    );
    insert testLicenseKey;

    return new Map<String, Object>{ 'account' => testAccount, 'contacts' => contacts, 'licenseKey' => testLicenseKey };
  }

  /**
   * Complete setup for License Key Email Handler tests
   */
  public static Map<String, Object> setupLicenseKeyEmailHandlerData() {
    Account testAccount = createAccount('Test Account for Handler');

    List<Contact> contacts = new List<Contact>();
    contacts.add(
      createContact(
        testAccount.Id,
        'Handler',
        'Contact1',
        'Handler.Contact1' + Datetime.now().getTime().toString() + '@corp.com'
      )
    );
    contacts.add(
      createContact(
        testAccount.Id,
        'Handler',
        'Contact2',
        'Handler.Contact2' + (Datetime.now().getTime() + 1).toString() + '@corp.com'
      )
    );

    List<License_Key__c> testKeys = new List<License_Key__c>();

    // Valid Clearswift key with all data
    testKeys.add(
      new License_Key__c(
        Name = 'HANDLER-TEST-001',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        License_Key__c = 'TEST-KEY-001',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Contact_2__c = contacts[1].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    // Valid key with single contact
    testKeys.add(
      new License_Key__c(
        Name = 'HANDLER-TEST-002',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Specific/Temporary',
        License_Key__c = 'TEST-KEY-002',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    // Key without contacts
    testKeys.add(
      new License_Key__c(
        Name = 'HANDLER-TEST-NO-CONTACT',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Send_Email__c = false,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        CreatedById = UserInfo.getUserId()
      )
    );

    // Key with different brand
    testKeys.add(
      new License_Key__c(
        Name = 'HANDLER-TEST-OTHER-BRAND',
        Brand__c = 'Other Brand',
        Key_Type__c = 'Generic',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Send_Email__c = false,
        CreatedById = UserInfo.getUserId()
      )
    );

    insert testKeys;

    return new Map<String, Object>{ 'account' => testAccount, 'contacts' => contacts, 'licenseKeys' => testKeys };
  }

  /**
   * Complete setup for License Key Trigger tests
   */
  public static Map<String, Object> setupLicenseKeyTriggerData() {
    Account testAccount = createAccount('Trigger Test Account');

    List<Contact> contacts = new List<Contact>();
    contacts.add(createContact(testAccount.Id, 'Trigger', 'Contact1', 'trigger1@test.com'));
    contacts.add(createContact(testAccount.Id, 'Trigger', 'Contact2', 'trigger2@test.com'));

    List<License_Key__c> testKeys = new List<License_Key__c>();

    // License Key 1 - with both contacts
    testKeys.add(
      new License_Key__c(
        Name = 'TRIGGER-TEST-001',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        License_Key__c = 'TRIG-001',
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Contact_2__c = contacts[1].Id,
        Send_Email__c = false
      )
    );

    // License Key 2 - with one contact
    testKeys.add(
      new License_Key__c(
        Name = 'TRIGGER-TEST-002',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        License_Key__c = 'TRIG-002',
        Account__c = testAccount.Id,
        Contact_1__c = contacts[0].Id,
        Send_Email__c = false,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
      )
    );

    // License Key 3 - no contacts
    testKeys.add(
      new License_Key__c(
        Name = 'TRIGGER-TEST-003',
        Brand__c = TEST_BRAND_CLEARSWIFT,
        Key_Type__c = 'Generic',
        Account__c = testAccount.Id,
        Send_Email__c = false,
        LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
      )
    );

    insert testKeys;

    return new Map<String, Object>{ 'account' => testAccount, 'contacts' => contacts, 'licenseKeys' => testKeys };
  }

  /**
   * Complete setup for Brand Email Handler Factory tests
   */
  public static Map<String, Object> setupBrandEmailHandlerFactoryData() {
    Account testAccount = createAccount('Factory Test Account');
    Contact testContact = createContact(testAccount.Id, 'Factory', 'Contact', 'factory@test.com');

    return new Map<String, Object>{ 'account' => testAccount, 'contact' => testContact };
  }
}