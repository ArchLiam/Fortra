@isTest
private class LkgRobotFileBuilderTest {
  private static LkgRobotFileBuilder builder;

  static {
    builder = new LkgRobotFileBuilder();
  }

  // Helper: build an in-memory License_Key__c with fields relevant to Robot file building (no DML)
  private static License_Key__c makeRobotKey(
    String productName,
    String productCode,
    String productIdentifierName,
    String licenseKey,
    String keyType,
    Date endDate,
    String serialNum,
    String modelNum,
    String featureCode,
    String lparNum
  ) {
    License_Key__c k = new License_Key__c();
    k.License_Key_Product_Name__c = productName;
    k.Product_Code__c = productCode;
    k.LKG_Product_Identifier_Name__c = productIdentifierName;
    k.License_Key__c = licenseKey;
    k.Key_Type__c = keyType;
    k.End_Date__c = endDate;
    k.LPAR_Serial_Number__c = serialNum;
    k.LPAR_Model_Number__c = modelNum;
    k.LPAR_Feature_Code__c = featureCode;
    k.LPAR_Number__c = lparNum;
    k.Silo__c = 'robot';
    return k;
  }

  // ─── FILE_DATE header ─────────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldStartWithFileDateLine() {
    // Given one Robot key record
    License_Key__c k = makeRobotKey(
      'Robot Prod',
      'RP01',
      'ROBOT_PROD',
      'KEY001',
      'Generic',
      null,
      'SN1',
      'M1',
      'FC1',
      'LP1'
    );

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.startsWith('FILE_DATE='), 'buildFile() output must start with a FILE_DATE= line.');
  }

  // ─── Robot-specific: NO SYSTEM_NAME= ─────────────────────────────────────

  @isTest
  static void buildFile_shouldNotIncludeSystemNameForRobotKeys() {
    // Given a Robot key record
    License_Key__c k = makeRobotKey(
      'Robot Prod',
      'RP01',
      'ROBOT_PROD',
      'KEY001',
      'Generic',
      null,
      'SN1',
      'M1',
      'FC1',
      'LP1'
    );

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then — Robot key rows must NOT include a SYSTEM_NAME= line
    System.Assert.isFalse(result.contains('SYSTEM_NAME='), 'Robot key rows must not include a SYSTEM_NAME= line.');
  }

  // ─── MDT fallback for PRODUCT_CODE ────────────────────────────────────────

  @isTest
  static void buildFile_shouldFallBackToProductCodeWhenNoMdtRecordFound() {
    // Given a Robot key whose LKG_Product_Identifier_Name__c does not match any LKG_UI_Field__mdt record
    // (no MDT records exist in the test context for this identifier — builder falls back to Product_Code__c)
    License_Key__c k = makeRobotKey(
      'Robot Prod',
      'FALLBACK_CODE',
      'NONEXISTENT_PRODUCT_IDENTIFIER',
      'KEY001',
      'Generic',
      null,
      'SN1',
      'M1',
      'FC1',
      'LP1'
    );

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then — falls back to Product_Code__c field value
    System.Assert.isTrue(
      result.contains('PRODUCT_CODE=FALLBACK_CODE'),
      'Robot builder should fall back to Product_Code__c when no matching MDT record exists for the product identifier.'
    );
  }

  // ─── LICENSE_FMT logic ────────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldSetLicenseFmtFourFor75CharKey() {
    // Given a Robot key whose license code is exactly 75 characters
    License_Key__c k = makeRobotKey('P', 'RP01', 'PID', 'A'.repeat(75), 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      result.contains('LICENSE_FMT=4'),
      'A 75-character Robot license code should produce LICENSE_FMT=4.'
    );
  }

  @isTest
  static void buildFile_shouldSetLicenseFmtOneFor55CharKey() {
    // Given a Robot key whose license code is exactly 55 characters
    License_Key__c k = makeRobotKey('P', 'RP01', 'PID', 'B'.repeat(55), 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      result.contains('LICENSE_FMT=1'),
      'A 55-character Robot license code should produce LICENSE_FMT=1.'
    );
  }

  // ─── Key-row separator ────────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldAddSeparatorBetweenMultipleKeysInSameGroup() {
    // Given two Robot keys that share the same hardware key (same LPAR fields)
    License_Key__c k1 = makeRobotKey('Prod A', 'RA', 'PID_A', 'KEY001', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');
    License_Key__c k2 = makeRobotKey('Prod B', 'RB', 'PID_B', 'KEY002', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k1, k2 });
    Test.stopTest();

    // Then — a dashed separator line must appear between the two keys in the same group
    System.Assert.isTrue(
      result.contains('* - - -'),
      'Multiple keys in the same hardware group must be separated by a dashed separator line.'
    );
  }

  // ─── Edge case: null license key value ────────────────────────────────────

  @isTest
  static void buildFile_shouldHandleNullLicenseKeyValueGracefully() {
    // Given a Robot key with a null license code value
    License_Key__c k = makeRobotKey('P', 'RP01', 'PID', null, 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then — null license key treated as empty string; all expected lines still present
    System.Assert.isTrue(
      result.contains('LICENSE_CODE='),
      'A LICENSE_CODE= line must always appear, even when the license key value is null.'
    );
    System.Assert.isTrue(
      result.contains('LICENSE_FMT=\n'),
      'A null license key (0 length) should produce an empty LICENSE_FMT= value.'
    );
  }
}