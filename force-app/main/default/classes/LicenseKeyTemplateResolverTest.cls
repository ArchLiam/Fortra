/**
 * Test class for LicenseKeyTemplateResolver
 */
@isTest
private class LicenseKeyTemplateResolverTest {
  /**
   * Test setup method - creates minimal test data
   */
  @TestSetup
  static void setup() {
    // Create a test Account
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    // Create test Contacts
    Contact contact1 = new Contact(
      FirstName = 'Test',
      LastName = 'Contact1',
      Email = 'test1@example.com',
      AccountId = testAccount.Id
    );
    insert contact1;
  }

  /**
   * Test getTemplateName with valid Generic key type
   */
  @isTest
  static void testGetTemplateName_Generic() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    String templateName = LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    Test.stopTest();

    System.assertNotEquals(null, templateName, 'Template name should not be null for Generic key type');
  }

  /**
   * Test getTemplateName with Specific/Temporary key type
   */
  @isTest
  static void testGetTemplateName_SpecificTemporary() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Specific/Temporary',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    String templateName = LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    Test.stopTest();

    System.assertNotEquals(null, templateName, 'Template name should not be null for Specific/Temporary key type');
  }

  /**
   * Test getTemplateName with Permanent key type
   */
  @isTest
  static void testGetTemplateName_Permanent() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Permanent',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    String templateName = LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    Test.stopTest();

    System.assertNotEquals(null, templateName, 'Template name should not be null for Permanent key type');
  }

  /**
   * Test getTemplateName with null Key Type - should throw exception
   */
  @isTest
  static void testGetTemplateName_NullKeyType() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = null,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    } catch (IllegalArgumentException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('Key Type is required'),
        'Exception message should mention Key Type requirement'
      );
    }
    Test.stopTest();

    System.assert(exceptionThrown, 'Exception should be thrown for null Key Type');
  }

  /**
   * Test getTemplateName with blank Key Type - should throw exception
   */
  @isTest
  static void testGetTemplateName_BlankKeyType() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = '',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    } catch (IllegalArgumentException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    System.assert(exceptionThrown, 'Exception should be thrown for blank Key Type');
  }

  /**
   * Test getTemplateName with null Product Identifier - should throw exception
   */
  @isTest
  static void testGetTemplateName_NullProductIdentifier() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = ''
    );
    insert licenseKey;

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    } catch (IllegalArgumentException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('LKG Product Identifier is required'),
        'Exception message should mention LKG Product Identifier requirement'
      );
    }
    Test.stopTest();

    System.assert(exceptionThrown, 'Exception should be thrown for null LKG Product Identifier');
  }

  /**
   * Test getTemplateName with invalid Product Identifier - should throw exception
   */
  @isTest
  static void testGetTemplateName_InvalidProductIdentifier() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'INVALID-999'
    );
    insert licenseKey;

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    } catch (IllegalArgumentException e) {
      exceptionThrown = true;
      System.assert(
        e.getMessage().contains('No email templates defined'),
        'Exception message should indicate missing template configuration'
      );
    }
    Test.stopTest();

    System.assert(exceptionThrown, 'Exception should be thrown for invalid Product Identifier');
  }

  /**
   * Test hasTemplateConfig method with valid product identifier
   */
  @isTest
  static void testHasTemplateConfig_Valid() {
    Test.startTest();
    Boolean hasConfig = LicenseKeyTemplateResolver.hasTemplateConfig('SECURE_Web_Gateway');
    Test.stopTest();

    System.assertEquals(true, hasConfig, 'Should return true for valid product identifier');
  }

  /**
   * Test hasTemplateConfig method with invalid product identifier
   */
  @isTest
  static void testHasTemplateConfig_Invalid() {
    Test.startTest();
    Boolean hasConfig = LicenseKeyTemplateResolver.hasTemplateConfig('INVALID-999');
    Test.stopTest();

    System.assertEquals(false, hasConfig, 'Should return false for invalid product identifier');
  }

  /**
   * Test key type normalization with variations
   */
  @isTest
  static void testKeyTypeNormalization() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    // Test with uppercase and spaces
    License_Key__c licenseKey1 = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = ' GENERIC ',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey1;

    Test.startTest();
    String templateName1 = LicenseKeyTemplateResolver.getTemplateName(licenseKey1);
    Test.stopTest();

    System.assertNotEquals(null, templateName1, 'Should handle uppercase and spaces in key type');
  }

  /**
   * Test cache functionality - repeated calls should use cached configuration
   */
  @isTest
  static void testCacheFunctionality() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    Test.startTest();
    // First call - should query and cache
    String templateName1 = LicenseKeyTemplateResolver.getTemplateName(licenseKey);

    // Second call - should use cache
    String templateName2 = LicenseKeyTemplateResolver.getTemplateName(licenseKey);

    // Third call with different key type - should use cache
    licenseKey.Key_Type__c = 'Permanent';
    String templateName3 = LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    Test.stopTest();

    System.assertNotEquals(null, templateName1, 'First template name should not be null');
    System.assertNotEquals(null, templateName2, 'Second template name should not be null');
    System.assertNotEquals(null, templateName3, 'Third template name should not be null');
  }

  /**
   * Test clearCache functionality
   */
  @isTest
  static void testClearCache() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    License_Key__c licenseKey = new License_Key__c(
      Account__c = acc.Id,
      Contact_1__c = con.Id,
      Key_Type__c = 'Generic',
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert licenseKey;

    // First call - should populate cache
    String templateName1 = LicenseKeyTemplateResolver.getTemplateName(licenseKey);

    Test.startTest();
    // Clear the cache
    LicenseKeyTemplateResolver.clearCache();

    // Call again after clearing cache - should query again
    String templateName2 = LicenseKeyTemplateResolver.getTemplateName(licenseKey);
    Test.stopTest();

    System.assertNotEquals(null, templateName1, 'Template name before cache clear should not be null');
    System.assertNotEquals(null, templateName2, 'Template name after cache clear should not be null');
    System.assertEquals(templateName1, templateName2, 'Template names should be the same after cache clear');
  }

  /**
   * Test getTemplateConfig returns proper configuration
   */
  @isTest
  static void testGetTemplateConfig() {
    Test.startTest();
    LicenseKeyTemplateResolver.TemplateConfig config = LicenseKeyTemplateResolver.getTemplateConfig(
      'SECURE_Web_Gateway'
    );
    Test.stopTest();

    System.assertNotEquals(null, config, 'Template config should not be null for valid product identifier');
    System.assertNotEquals(null, config.genericTemplate, 'Generic template should be defined');
  }

  /**
   * Test getTemplateConfig returns null for invalid product identifier
   */
  @isTest
  static void testGetTemplateConfig_Invalid() {
    Test.startTest();
    LicenseKeyTemplateResolver.TemplateConfig config = LicenseKeyTemplateResolver.getTemplateConfig('INVALID-999');
    Test.stopTest();

    System.assertEquals(null, config, 'Template config should be null for invalid product identifier');
  }
}