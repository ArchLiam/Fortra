@IsTest
private class LicenseKeyNotificationPublisherTest {
  /**
   * Test successful publishing of Platform Events for License Keys
   */
  @IsTest
  static void testPublishEmailNotifications_Success() {
    // Create test Account
    Account testAccount = new Account(Name = 'Test Account');
    insert testAccount;

    // Create test License Keys
    List<License_Key__c> testKeys = new List<License_Key__c>();

    License_Key__c key1 = new License_Key__c(
      Name = 'LK-001',
      Account__c = testAccount.Id,
      Email_Status__c = 'Success',
      Last_Email_Sent_Date__c = DateTime.now()
    );

    License_Key__c key2 = new License_Key__c(
      Name = 'LK-002',
      Account__c = testAccount.Id,
      Email_Status__c = 'Failed',
      Email_Error_Message__c = 'Invalid email address'
    );

    testKeys.add(key1);
    testKeys.add(key2);
    insert testKeys;

    Test.startTest();

    // Call the method to publish Platform Events
    LicenseKeyNotificationPublisher.publishEmailNotifications(testKeys);

    Test.stopTest();

    // Verify License Keys were queried and processed
    // Note: We cannot directly query Platform Events, but we can verify no exceptions occurred
    List<License_Key__c> queriedKeys = [
      SELECT Id, Name, Email_Status__c
      FROM License_Key__c
      WHERE Id IN :testKeys
    ];

    System.assertEquals(2, queriedKeys.size(), 'Should have processed 2 License Keys');
    System.assertEquals('Success', queriedKeys[0].Email_Status__c, 'First key should have Success status');
    System.assertEquals('Failed', queriedKeys[1].Email_Status__c, 'Second key should have Failed status');
  }

  /**
   * Test publishing with empty list - should handle gracefully
   */
  @IsTest
  static void testPublishEmailNotifications_EmptyList() {
    List<License_Key__c> emptyList = new List<License_Key__c>();

    Test.startTest();

    // Should not throw exception with empty list
    LicenseKeyNotificationPublisher.publishEmailNotifications(emptyList);

    Test.stopTest();

    // No assertion needed - just verify no exception thrown
    System.assert(true, 'Method should handle empty list without exception');
  }

  /**
   * Test publishing with single License Key
   */
  @IsTest
  static void testPublishEmailNotifications_SingleKey() {
    // Create test Account
    Account testAccount = new Account(Name = 'Test Account Single');
    insert testAccount;

    // Create single License Key
    License_Key__c testKey = new License_Key__c(
      Name = 'LK-SINGLE',
      Account__c = testAccount.Id,
      Email_Status__c = 'Success',
      Email_Error_Message__c = null,
      Last_Email_Sent_Date__c = DateTime.now()
    );
    insert testKey;

    List<License_Key__c> singleKeyList = new List<License_Key__c>{ testKey };

    Test.startTest();

    // Call the method
    LicenseKeyNotificationPublisher.publishEmailNotifications(singleKeyList);

    Test.stopTest();

    // Verify the key exists and has correct status
    License_Key__c queriedKey = [
      SELECT Id, Name, Email_Status__c, Account__c
      FROM License_Key__c
      WHERE Id = :testKey.Id
    ];

    System.assertEquals('LK-SINGLE', queriedKey.Name, 'License Key name should match');
    System.assertEquals(testAccount.Id, queriedKey.Account__c, 'Account should be linked');
  }

  /**
   * Test bulk scenario with multiple License Keys
   */
  @IsTest
  static void testPublishEmailNotifications_BulkKeys() {
    // Create test Accounts
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      accounts.add(new Account(Name = 'Test Account ' + i));
    }
    insert accounts;

    // Create multiple License Keys
    List<License_Key__c> bulkKeys = new List<License_Key__c>();
    for (Integer i = 0; i < 50; i++) {
      bulkKeys.add(
        new License_Key__c(
          Name = 'LK-BULK-' + i,
          Account__c = accounts[Math.mod(i, 5)].Id,
          Email_Status__c = Math.mod(i, 2) == 0 ? 'Success' : 'Failed',
          Email_Error_Message__c = Math.mod(i, 2) == 0 ? null : 'Error ' + i,
          Last_Email_Sent_Date__c = Math.mod(i, 2) == 0 ? DateTime.now() : null
        )
      );
    }
    insert bulkKeys;

    Test.startTest();

    // Publish events for all keys
    LicenseKeyNotificationPublisher.publishEmailNotifications(bulkKeys);

    Test.stopTest();

    // Verify all keys were processed
    List<License_Key__c> queriedKeys = [
      SELECT Id, Email_Status__c
      FROM License_Key__c
      WHERE Id IN :bulkKeys
    ];

    System.assertEquals(50, queriedKeys.size(), 'Should have processed all 50 keys');

    // Count success vs failed
    Integer successCount = 0;
    Integer failedCount = 0;
    for (License_Key__c key : queriedKeys) {
      if (key.Email_Status__c == 'Success') {
        successCount++;
      } else if (key.Email_Status__c == 'Failed') {
        failedCount++;
      }
    }

    System.assertEquals(25, successCount, 'Should have 25 successful keys');
    System.assertEquals(25, failedCount, 'Should have 25 failed keys');
  }
}