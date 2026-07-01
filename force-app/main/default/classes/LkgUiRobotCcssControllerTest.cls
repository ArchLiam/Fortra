@isTest
public with sharing class LkgUiRobotCcssControllerTest {
  // ─── Test data setup ────────────────────────────────────────────────────────

  static Account createAccount() {
    Account acc = new Account(Name = 'Robot CCSS Test Account');
    insert acc;
    return acc;
  }

  static License_Key__c createLicenseKey(Id accountId, String silo, String keyType, Date endDate) {
    License_Key__c lk = new License_Key__c(
      Account__c = accountId,
      Silo__c = silo,
      Key_Type__c = keyType,
      End_Date__c = endDate,
      License_Key__c = 'TEST-KEY-' + silo.toUpperCase(),
      License_Key_Product_Name__c = silo + ' Product',
      Hardware_ID__c = 'HW-001',
      LPAR_Number__c = 'LP01',
      LPAR_System_Name__c = 'SYS01',
      LPAR_Serial_Number__c = 'SER001'
    );
    insert lk;
    return lk;
  }

  // ─── getRobotCcssLicenseKeys ─────────────────────────────────────────────────

  @isTest
  static void testGetKeys_ReturnsBothSilos() {
    Account acc = createAccount();
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', Date.today().addDays(30));
    createLicenseKey(acc.Id, 'ccss', 'Permanent', null);

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, null);
    Test.stopTest();

    System.assertEquals(2, results.size(), 'Expected both robot and ccss keys');
  }

  @isTest
  static void testGetKeys_FilterBySilo_Robot() {
    Account acc = createAccount();
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', Date.today().addDays(30));
    createLicenseKey(acc.Id, 'ccss', 'Permanent', null);

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, 'robot');
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Expected only robot keys');
    System.assertEquals('robot', results[0].Silo__c);
  }

  @isTest
  static void testGetKeys_FilterBySilo_Ccss() {
    Account acc = createAccount();
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', Date.today().addDays(30));
    createLicenseKey(acc.Id, 'ccss', 'Permanent', null);

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, 'ccss');
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Expected only ccss keys');
    System.assertEquals('ccss', results[0].Silo__c);
  }

  @isTest
  static void testGetKeys_ExcludesExpiredKeys() {
    Account acc = createAccount();
    // Expired key — should be excluded
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', Date.today().addDays(-1));
    // Valid key with no expiry — should be included
    createLicenseKey(acc.Id, 'ccss', 'Permanent', null);

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, null);
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Expired keys should be excluded');
    System.assertEquals('ccss', results[0].Silo__c);
  }

  @isTest
  static void testGetKeys_ExcludesOtherSilos() {
    Account acc = createAccount();
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', null);
    // A key on a different silo — should never appear
    License_Key__c other = new License_Key__c(
      Account__c = acc.Id,
      Silo__c = 'clearswift',
      Key_Type__c = 'Permanent',
      License_Key__c = 'OTHER-KEY'
    );
    insert other;

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, null);
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Only robot/ccss keys should be returned');
    System.assertEquals('robot', results[0].Silo__c);
  }

  @isTest
  static void testGetKeys_ExpiryToday_IsIncluded() {
    Account acc = createAccount();
    createLicenseKey(acc.Id, 'robot', 'Specific/Temporary', Date.today());

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, null);
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Key expiring today should still be included');
  }

  @isTest
  static void testGetKeys_NoRecords_ReturnsEmptyList() {
    Account acc = createAccount();

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc.Id, null);
    Test.stopTest();

    System.assertEquals(0, results.size(), 'Expected empty list when no keys exist');
  }

  @isTest
  static void testGetKeys_WrongAccount_ReturnsNothing() {
    Account acc1 = createAccount();
    Account acc2 = new Account(Name = 'Other Account');
    insert acc2;
    createLicenseKey(acc1.Id, 'robot', 'Specific/Temporary', null);

    Test.startTest();
    List<License_Key__c> results = LkgUiRobotCcssController.getRobotCcssLicenseKeys(acc2.Id, null);
    Test.stopTest();

    System.assertEquals(0, results.size(), 'Keys from a different account should not be returned');
  }

  // ─── generateFile ─────────────────────────────────────────────────────────

  @isTest
  static void generateFile_shouldReturnFailureJsonWhenKeyIdsListIsEmpty() {
    // Given a payload with an empty keyIds array
    Account acc = createAccount();
    String payload = JSON.serialize(
      new Map<String, Object>{
        'keyIds' => new List<Id>(),
        'accountId' => acc.Id,
        'contact1Id' => null,
        'contact2Id' => null,
        'sendEmail' => false
      }
    );

    // When
    Test.startTest();
    String jsonResponse = LkgUiRobotCcssController.generateFile(payload);
    Test.stopTest();

    // Then
    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
    System.Assert.isFalse(
      (Boolean) response.get('success'),
      'generateFile() should return success=false when no key IDs are provided.'
    );
  }

  @isTest
  static void generateFile_shouldReturnSuccessJsonForValidRobotKeyPayload() {
    // Given a valid Robot key with sendEmail=false (no email template lookup required)
    Account acc = createAccount();
    License_Key__c robotKey = createLicenseKey(acc.Id, 'robot', 'Generic', null);
    String payload = JSON.serialize(
      new Map<String, Object>{
        'keyIds' => new List<Id>{ robotKey.Id },
        'accountId' => acc.Id,
        'contact1Id' => null,
        'contact2Id' => null,
        'sendEmail' => false
      }
    );

    // When
    Test.startTest();
    String jsonResponse = LkgUiRobotCcssController.generateFile(payload);
    Test.stopTest();

    // Then
    Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
    System.Assert.isTrue(
      (Boolean) response.get('success'),
      'generateFile() should return success=true for a valid Robot key without email.'
    );
  }

  @isTest
  static void generateFile_shouldThrowAuraHandledExceptionForMalformedJson() {
    // Given a payload string that cannot be deserialized to GenerateFilePayload

    // When
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      LkgUiRobotCcssController.generateFile('NOT_VALID_JSON');
    } catch (AuraHandledException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      exceptionThrown,
      'generateFile() should throw an AuraHandledException when given malformed JSON.'
    );
  }
}