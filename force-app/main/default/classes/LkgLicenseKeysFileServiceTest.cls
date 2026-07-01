@isTest
private class LkgLicenseKeysFileServiceTest {
  @TestSetup
  static void setupTestData() {
    // Email templates require System.runAs to avoid mixed-DML errors (same pattern as EmailServiceTest)
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new EmailTemplate(
        DeveloperName = 'Fortra_LK_Robot_License_Keys_File',
        FolderId = UserInfo.getUserId(),
        TemplateType = 'text',
        Name = 'Fortra | LK | Robot License Keys File',
        Subject = 'Robot License Key File',
        Body = 'Dear {!Contact.FirstName} {!Contact.LastName}, please find your file attached.',
        IsActive = true
      );
    }

    Account acc = new Account(Name = 'File Service Test Account');
    insert acc;

    insert new Contact(
      FirstName = 'File',
      LastName = 'FileServiceContact',
      Email = 'file.service@example.com',
      AccountId = acc.Id
    );

    insert new List<License_Key__c>{
      // Robot key — used for success, mixed-silo, and validation tests
      new License_Key__c(
        Name = 'ROBOT-SVC-001',
        Account__c = acc.Id,
        Silo__c = 'robot',
        Key_Type__c = 'Generic',
        Brand__c = 'Test Brand'
      ),
      // CCSS key — used for success and mixed-silo tests
      new License_Key__c(
        Name = 'CCSS-SVC-001',
        Account__c = acc.Id,
        Silo__c = 'ccss',
        Key_Type__c = 'Generic',
        Brand__c = 'Test Brand'
      ),
      // Unsupported-silo key — used for the unsupported-silo failure test
      new License_Key__c(
        Name = 'UNKNOWN-SVC-001',
        Account__c = acc.Id,
        Silo__c = 'halcyon',
        Key_Type__c = 'Generic',
        Brand__c = 'Test Brand'
      )
    };
  }

  // ─── Pure-validation tests (fail before any SOQL) ─────────────────────────

  @isTest
  static void generateFile_shouldReturnFailureWhenKeyIdsIsNull() {
    // Given a valid account but a null key ID list
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(null, acc.Id, null, null, false);
    Test.stopTest();

    // Then
    System.Assert.isFalse(result.success, 'generateFile() should return failure when keyIds is null.');
    System.Assert.areEqual(
      'No License Keys selected.',
      result.message,
      'Failure message should state no keys were selected.'
    );
  }

  @isTest
  static void generateFile_shouldReturnFailureWhenKeyIdsIsEmpty() {
    // Given a valid account but an empty key ID list
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(new List<Id>(), acc.Id, null, null, false);
    Test.stopTest();

    // Then
    System.Assert.isFalse(result.success, 'generateFile() should return failure when keyIds is empty.');
    System.Assert.areEqual(
      'No License Keys selected.',
      result.message,
      'Failure message should state no keys were selected.'
    );
  }

  @isTest
  static void generateFile_shouldReturnFailureWhenAccountIdIsNull() {
    // Given a non-empty key ID list but a null accountId
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id },
      null,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isFalse(result.success, 'generateFile() should return failure when accountId is null.');
    System.Assert.areEqual(
      'Account is required.',
      result.message,
      'Failure message should state that an account is required.'
    );
  }

  @isTest
  static void generateFile_shouldReturnFailureWhenSendEmailTrueButNoContactsProvided() {
    // Given sendEmail=true with both contact IDs null
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id },
      acc.Id,
      null,
      null,
      true
    );
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      result.success,
      'generateFile() should return failure when email is requested but no contacts are provided.'
    );
    System.Assert.areEqual(
      'At least one contact is required to send an email.',
      result.message,
      'Failure message should indicate a contact is required to send email.'
    );
  }

  // ─── SOQL / DML tests ─────────────────────────────────────────────────────

  @isTest
  static void generateFile_shouldReturnFailureWhenNoMatchingKeysFoundForAccount() {
    // Given a Robot key that belongs to the setup account,
    // but the call is made with a different account ID (key will not match)
    Account wrongAccount = new Account(Name = 'Wrong Account');
    insert wrongAccount;
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id },
      wrongAccount.Id,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isFalse(result.success, 'generateFile() should return failure when no keys match the given account.');
    System.Assert.areEqual(
      'No matching License Key records found for this Account.',
      result.message,
      'Failure message should indicate no matching keys were found.'
    );
  }

  @isTest
  static void generateFile_shouldReturnFailureWhenMixedSilosAreSelected() {
    // Given one Robot key and one CCSS key selected together (different silos)
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];
    License_Key__c ccssKey = [SELECT Id FROM License_Key__c WHERE Name = 'CCSS-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id, ccssKey.Id },
      acc.Id,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      result.success,
      'generateFile() should return failure when keys from multiple silos are selected.'
    );
    System.Assert.areEqual(
      'All selected keys must belong to the same Silo (Robot or CCSS).',
      result.message,
      'Failure message should indicate a silo mismatch.'
    );
  }

  @isTest
  static void generateFile_shouldReturnFailureForUnsupportedSilo() {
    // Given a key whose silo is neither 'robot' nor 'ccss'
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c badKey = [SELECT Id FROM License_Key__c WHERE Name = 'UNKNOWN-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ badKey.Id },
      acc.Id,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isFalse(result.success, 'generateFile() should return failure for an unrecognised silo.');
    System.Assert.isTrue(
      result.message.contains('Unsupported silo'),
      'Failure message should mention the unsupported silo.'
    );
  }

  @isTest
  static void generateFile_shouldReturnSuccessForRobotKeysWithoutEmail() {
    // Given a valid Robot key and sendEmail=false (no email template lookup required)
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id },
      acc.Id,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.success, 'generateFile() should succeed for a valid Robot key without email.');
    System.Assert.isTrue(
      result.message.contains('.HSL'),
      'Success message should reference the generated .HSL filename.'
    );
  }

  @isTest
  static void generateFile_shouldReturnSuccessForCcssKeysWithoutEmail() {
    // Given a valid CCSS key and sendEmail=false
    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c ccssKey = [SELECT Id FROM License_Key__c WHERE Name = 'CCSS-SVC-001' LIMIT 1];

    // When
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ ccssKey.Id },
      acc.Id,
      null,
      null,
      false
    );
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.success, 'generateFile() should succeed for a valid CCSS key without email.');
    System.Assert.isTrue(
      result.message.contains('.HSL'),
      'Success message should reference the generated .HSL filename.'
    );
  }

  @isTest
  static void generateFile_shouldSendEmailAndReturnSuccessWhenContactProvided() {
    // Given: inject MockEmailSender so no real email is dispatched
    MockEmailSender mockSender = new MockEmailSender();
    LkgLicenseKeysFileService.emailSender = mockSender;

    Account acc = [SELECT Id FROM Account WHERE Name = 'File Service Test Account' LIMIT 1];
    License_Key__c robotKey = [SELECT Id FROM License_Key__c WHERE Name = 'ROBOT-SVC-001' LIMIT 1];
    Contact cont = [SELECT Id FROM Contact WHERE LastName = 'FileServiceContact' LIMIT 1];

    // When: sendEmail=true with a valid contact
    Test.startTest();
    LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
      new List<Id>{ robotKey.Id },
      acc.Id,
      cont.Id,
      null,
      true
    );
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      result.success,
      'generateFile() should succeed when a contact is provided and email is requested. Error: ' + result.message
    );
    System.Assert.isTrue(
      result.message.contains('emailed'),
      'Success message should indicate the file was emailed.'
    );
    System.Assert.areEqual(
      1,
      mockSender.sentEmails.size(),
      'MockEmailSender should have captured exactly one email.'
    );
  }
}