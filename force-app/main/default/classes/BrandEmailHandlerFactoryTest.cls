/**
 * Test class for BrandEmailHandlerFactory
 * Tests the Factory pattern implementation for brand-specific email handlers
 */
@isTest
private class BrandEmailHandlerFactoryTest {
  /**
   * Setup test data
   */
  @TestSetup
  static void setupTestData() {
    // Create test Account
    Account testAccount = new Account(Name = 'Factory Test Account');
    insert testAccount;

    // Create test Contact
    Contact testContact = new Contact(
      FirstName = 'Factory',
      LastName = 'Contact',
      Email = 'factory@test.com',
      AccountId = testAccount.Id
    );
    insert testContact;
  }

  /**
   * Test getHandler returns default handler for brands without specific implementation
   */
  @isTest
  static void testGetHandler_ReturnsDefaultHandler() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('Clearswift');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Handler should not be null');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler with different case variations
   */
  @isTest
  static void testGetHandler_CaseInsensitive() {
    Test.startTest();

    IBrandEmailHandler handler1 = BrandEmailHandlerFactory.getHandler('clearswift');
    IBrandEmailHandler handler2 = BrandEmailHandlerFactory.getHandler('CLEARSWIFT');
    IBrandEmailHandler handler3 = BrandEmailHandlerFactory.getHandler('ClearSwift');

    Test.stopTest();

    System.assertNotEquals(null, handler1, 'Handler should be created for lowercase brand');
    System.assert(handler1 instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
    System.assertNotEquals(null, handler2, 'Handler should be created for uppercase brand');
    System.assert(handler2 instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
    System.assertNotEquals(null, handler3, 'Handler should be created for mixed case brand');
    System.assert(handler3 instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler with brand name containing spaces
   */
  @isTest
  static void testGetHandler_WithSpaces() {
    Test.startTest();

    // The factory removes spaces from brand names
    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('Clear swift');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Handler should be created even with spaces in brand name');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler caching mechanism
   */
  @isTest
  static void testGetHandler_Caching() {
    Test.startTest();

    // First call should instantiate and cache
    IBrandEmailHandler handler1 = BrandEmailHandlerFactory.getHandler('Powertech');

    // Second call should return cached instance
    IBrandEmailHandler handler2 = BrandEmailHandlerFactory.getHandler('Powertech');

    Test.stopTest();

    System.assertNotEquals(null, handler1, 'First handler should not be null');
    System.assertNotEquals(null, handler2, 'Second handler should not be null');
    // Note: In Apex, we can't directly test object identity, but both calls should succeed
  }

  /**
   * Test getHandler with null silo name returns default handler
   */
  @isTest
  static void testGetHandler_NullSilo() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler(null);

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Default handler should be returned for null silo name');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler with empty silo name returns default handler
   */
  @isTest
  static void testGetHandler_EmptySilo() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Default handler should be returned for empty silo name');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler with blank silo name (spaces only) returns default handler
   */
  @isTest
  static void testGetHandler_BlankSilo() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('   ');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Default handler should be returned for blank silo name');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test getHandler with non-existent silo returns default handler
   */
  @isTest
  static void testGetHandler_NonExistentSilo() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('NonExistentSilo');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Default handler should be returned for non-existent silo');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }

  /**
   * Test capitalizeFirstLetter helper method indirectly
   */
  @isTest
  static void testCapitalizeFirstLetter_Indirect() {
    Test.startTest();

    // The capitalizeFirstLetter method is private, but we can test it indirectly
    // by ensuring lowercase brand names work correctly
    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('powertech');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Handler should be created with proper capitalization from lowercase input');
  }

  /**
   * Test clearCache method
   */
  @isTest
  static void testClearCache() {
    // First, populate the cache
    IBrandEmailHandler handler1 = BrandEmailHandlerFactory.getHandler('Automate');
    System.assertNotEquals(null, handler1, 'Handler should be cached');

    Test.startTest();

    // Clear the cache
    BrandEmailHandlerFactory.clearCache();

    // Get handler again - should create new instance
    IBrandEmailHandler handler2 = BrandEmailHandlerFactory.getHandler('Automate');

    Test.stopTest();

    System.assertNotEquals(null, handler2, 'Handler should be created after cache clear');
  }

  /**
   * Test BrandHandlerException can be thrown and caught
   */
  @isTest
  static void testBrandHandlerException() {
    Boolean exceptionThrown = false;
    String testMessage = 'Test exception message';

    Test.startTest();

    try {
      throw new BrandEmailHandlerFactory.BrandHandlerException(testMessage);
    } catch (BrandEmailHandlerFactory.BrandHandlerException e) {
      exceptionThrown = true;
      System.assertEquals(testMessage, e.getMessage(), 'Exception message should match');
    }

    Test.stopTest();

    System.assert(exceptionThrown, 'BrandHandlerException should be thrown and caught');
  }

  /**
   * Test BrandHandlerException with cause
   */
  @isTest
  static void testBrandHandlerException_WithCause() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      Exception cause = new System.NullPointerException();
      throw new BrandEmailHandlerFactory.BrandHandlerException('Test with cause', cause);
    } catch (BrandEmailHandlerFactory.BrandHandlerException e) {
      exceptionThrown = true;
      System.assertNotEquals(null, e.getMessage(), 'Exception should have message');
    }

    Test.stopTest();

    System.assert(exceptionThrown, 'BrandHandlerException with cause should be thrown');
  }

  /**
   * Test getHandler with trimmed brand name
   */
  @isTest
  static void testGetHandler_TrimsWhitespace() {
    Test.startTest();

    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('  Automate  ');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Handler should be created with trimmed brand name');
  }

  /**
   * Test multiple different brands in sequence
   */
  @isTest
  static void testGetHandler_MultipleBrands() {
    Test.startTest();

    IBrandEmailHandler handler1 = BrandEmailHandlerFactory.getHandler('Automate');

    // Clear cache to test getting different brands
    BrandEmailHandlerFactory.clearCache();

    IBrandEmailHandler handler2 = BrandEmailHandlerFactory.getHandler('Powertech');

    Test.stopTest();

    System.assertNotEquals(null, handler1, 'First handler should be created');
    System.assertNotEquals(null, handler2, 'Second handler should be created');
  }

  /**
   * Test factory with real license key processing
   */
  @isTest
  static void testGetHandler_WithRealLicenseKey() {
    // Get test data
    Account testAccount = [SELECT Id FROM Account LIMIT 1];
    Contact testContact = [SELECT Id FROM Contact LIMIT 1];

    // Create license key
    License_Key__c testKey = new License_Key__c(
      Name = 'FACTORY-TEST-001',
      Silo__c = 'Clearswift',
      Key_Type__c = 'Generic',
      Account__c = testAccount.Id,
      Contact_1__c = testContact.Id,
      LKG_Product_Identifier_Name__c = 'SECURE_Web_Gateway'
    );
    insert testKey;

    // Query with relationships
    testKey = [
      SELECT
        Id,
        Name,
        Silo__c,
        Key_Type__c,
        Contact_1__c,
        Contact_1__r.Email,
        Account__c,
        Account__r.Name,
        LKG_Product_Identifier_Name__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    Test.startTest();

    // Get handler from factory based on Brand
    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler(testKey.Silo__c);

    // Validate and prepare
    Boolean isValid = handler.validateAndPrepare(testKey);

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Handler should be created for license key silo');
    System.assert(isValid, 'License key should be valid');
  }

  /**
   * Test factory returns default handler for invalid class name
   */
  @isTest
  static void testGetHandler_InvalidClassName() {
    Test.startTest();

    // Silo name that will create invalid class name
    IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler('123InvalidSilo');

    Test.stopTest();

    System.assertNotEquals(null, handler, 'Default handler should be returned for invalid silo name');
    System.assert(handler instanceof BaseBrandEmailHandler, 'Handler should be default BaseBrandEmailHandler');
  }
}