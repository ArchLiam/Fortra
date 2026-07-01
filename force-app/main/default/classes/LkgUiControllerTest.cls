@isTest
public with sharing class LkgUiControllerTest {
  @isTest
  static void testGetSolutionGroups() {
    List<LKG_Solution_Group__mdt> groups = LkgUiController.getSolutionGroups();
    System.assertNotEquals(null, groups);
  }

  @isTest
  static void testGetSolutionCategoriesByGroup() {
    List<LKG_Solution_Category__mdt> categories = LkgUiController.getSolutionCategoriesByGroup('Defensive Security');
    System.assertNotEquals(null, categories);
  }

  @isTest
  static void testGetSolutionsByCategory() {
    List<LKG_Solution__mdt> solutions = LkgUiController.getSolutionsByCategory('Email Security');
    System.assertNotEquals(null, solutions);
  }

  @isTest
  static void testGetProductsBySolution() {
    List<LKG_Product__mdt> products = LkgUiController.getProductsBySolution('Secure Email Gateway');
    System.assertNotEquals(null, products);
  }

  @isTest
  static void testGetLkgProductByName() {
    LKG_Product__mdt product = LkgUiController.getLkgProductByName('SECURE_Email_Gateway');
    System.assertNotEquals(null, product);
  }

  @isTest
  static void testGetLkgProductByName_NotFound() {
    LKG_Product__mdt product = LkgUiController.getLkgProductByName('Non_Existent_Product');
    System.assertEquals(null, product);
  }

  @isTest
  static void testGetKeyTypesBySilo() {
    List<LKG_Key_Type__mdt> keyTypes = LkgUiController.getKeyTypesBySilo('Clearswift');
    System.assertNotEquals(null, keyTypes);
  }

  @isTest
  static void testGetUIFieldsByProduct() {
    LKG_Product__mdt product = LkgUiController.getLkgProductByName('MIMEsweeper_SMTP');
    List<LKG_UI_Field__mdt> uiFields = LkgUiController.getUIFieldsByProduct(product);
    System.assertNotEquals(null, uiFields);
  }

  @isTest
  static void testGetContactsByAccountId() {
    // Create test account and contacts
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    Contact contact1 = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = testAccount.Id);
    Contact contact2 = new Contact(FirstName = 'Jane', LastName = 'Smith', AccountId = testAccount.Id);
    insert new List<Contact>{ contact1, contact2 };

    List<Contact> contacts = LkgUiController.getContactsByAccountId(testAccount.Id);
    System.assertEquals(2, contacts.size());
  }

  @isTest
  static void testgetUIFieldOptions() {
    List<LKG_UI_Field_Option__mdt> options = LkgUiController.getUIFieldOptions(
      new List<String>{ 'automate_Hardware_Id' },
      'Generic'
    );
    System.assertNotEquals(null, options);
  }

  @isTest
  static void testSearchContacts_ByName() {
    Account acc = new Account(Name = 'Acme Corp');
    insert acc;

    Contact c = new Contact(FirstName = 'Alice', LastName = 'Walker', Email = 'alice@acme.com', AccountId = acc.Id);
    insert c;

    List<Contact> results = LkgUiController.searchContacts('Alice');
    System.assert(results.size() > 0, 'Expected at least one result when searching by name');
    System.assertEquals('Alice Walker', results[0].Name);
  }

  @isTest
  static void testSearchContacts_ByEmail() {
    Account acc = new Account(Name = 'Globex');
    insert acc;

    Contact c = new Contact(FirstName = 'Bob', LastName = 'Jones', Email = 'bob@globex.com', AccountId = acc.Id);
    insert c;

    List<Contact> results = LkgUiController.searchContacts('bob@globex');
    System.assert(results.size() > 0, 'Expected at least one result when searching by email');
  }

  @isTest
  static void testSearchContacts_ExcludesContactsWithNoEmail() {
    Account acc = new Account(Name = 'No Email Corp');
    insert acc;

    Contact c = new Contact(FirstName = 'Charlie', LastName = 'Noemail', AccountId = acc.Id);
    insert c;

    List<Contact> results = LkgUiController.searchContacts('Charlie');
    for (Contact result : results) {
      System.assertNotEquals(null, result.Email, 'Results should never include contacts without an email');
    }
  }

  @isTest
  static void testSearchContacts_NoMatch() {
    List<Contact> results = LkgUiController.searchContacts('zzznomatchxxx');
    System.assertEquals(0, results.size(), 'Expected no results for a term that matches nothing');
  }

  // ─── getHideHardwareKeyTabSetting ─────────────────────────────────────────

  @isTest
  static void getHideHardwareKeyTabSetting_shouldReturnNonNullString() {
    // Given the LKG_Setting__mdt record may or may not exist in the org;
    // the method always falls back to 'false' when absent.

    // When
    Test.startTest();
    String result = LkgUiController.getHideHardwareKeyTabSetting();
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'getHideHardwareKeyTabSetting() must never return null.');
  }

  // ─── getHideReadOnlyFieldsSetting ─────────────────────────────────────────

  @isTest
  static void getHideReadOnlyFieldsSetting_shouldReturnNonNullString() {
    // Given the LKG_Setting__mdt record may or may not exist in the org;
    // the method always falls back to 'true' when absent.

    // When
    Test.startTest();
    String result = LkgUiController.getHideReadOnlyFieldsSetting();
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'getHideReadOnlyFieldsSetting() must never return null.');
  }

  // ─── generateKey ──────────────────────────────────────────────────────────

  @isTest
  static void generateKey_shouldReturnErrorResponseForInvalidPayload() {
    // Given a payload that cannot be parsed to a valid key-gen request
    // (malformed JSON — the processor will catch and return an error response)
    String badPayload = 'NOT_VALID_JSON';

    // When
    Test.startTest();
    LkgKeyGenResponse result = LkgUiController.generateKey(badPayload);
    Test.stopTest();

    // Then — the method must not throw; it should return an error response
    System.Assert.isNotNull(result, 'generateKey() must return a non-null response even for invalid input.');
    System.Assert.isFalse(
      result.isSuccess,
      'generateKey() should return isSuccess=false when the payload cannot be processed.'
    );
  }
}