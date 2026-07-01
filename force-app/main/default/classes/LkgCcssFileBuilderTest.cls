@isTest
private class LkgCcssFileBuilderTest {
  private static LkgCcssFileBuilder builder;

  static {
    builder = new LkgCcssFileBuilder();
  }

  // Helper: build an in-memory License_Key__c with fields relevant to CCSS file building (no DML)
  private static License_Key__c makeCcssKey(
    String productName,
    String productCode,
    String licenseKey,
    String systemName,
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
    k.License_Key__c = licenseKey;
    k.LPAR_System_Name__c = systemName;
    k.Key_Type__c = keyType;
    k.End_Date__c = endDate;
    k.LPAR_Serial_Number__c = serialNum;
    k.LPAR_Model_Number__c = modelNum;
    k.LPAR_Feature_Code__c = featureCode;
    k.LPAR_Number__c = lparNum;
    k.Silo__c = 'ccss';
    return k;
  }

  // ─── FILE_DATE header ─────────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldStartWithFileDateLine() {
    // Given one CCSS key record
    License_Key__c k = makeCcssKey(
      'CCSS Product',
      'CP01',
      'KEY001',
      'SYSA',
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

  // ─── CCSS-specific: SYSTEM_NAME= ─────────────────────────────────────────

  @isTest
  static void buildFile_shouldIncludeSystemNameLineForCcssKey() {
    // Given a CCSS key with a known system name
    String systemName = 'PROD-SYS-A';
    License_Key__c k = makeCcssKey(
      'CCSS Product',
      'CP01',
      'KEY001',
      systemName,
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

    // Then — CCSS-specific: SYSTEM_NAME= must appear in the output
    System.Assert.isTrue(
      result.contains('SYSTEM_NAME=' + systemName),
      'CCSS key rows must include SYSTEM_NAME= with the LPAR system name.'
    );
  }

  // ─── LICENSE_FMT logic ────────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldSetLicenseFmtFourFor75CharKey() {
    // Given a CCSS key whose license code is exactly 75 characters
    License_Key__c k = makeCcssKey('P', 'C01', 'A'.repeat(75), 'SYS', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.contains('LICENSE_FMT=4'), 'A 75-character license code should produce LICENSE_FMT=4.');
  }

  @isTest
  static void buildFile_shouldSetLicenseFmtOneFor55CharKey() {
    // Given a CCSS key whose license code is exactly 55 characters
    License_Key__c k = makeCcssKey('P', 'C01', 'B'.repeat(55), 'SYS', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.contains('LICENSE_FMT=1'), 'A 55-character license code should produce LICENSE_FMT=1.');
  }

  @isTest
  static void buildFile_shouldSetLicenseFmtEmptyForNonStandardKeyLength() {
    // Given a CCSS key whose license code length is neither 55 nor 75
    License_Key__c k = makeCcssKey('P', 'C01', 'C'.repeat(20), 'SYS', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then — the LICENSE_FMT= line should have an empty value
    System.Assert.isTrue(
      result.contains('LICENSE_FMT=\n'),
      'A license code of non-standard length should produce an empty LICENSE_FMT= value.'
    );
  }

  // ─── Hardware-key grouping ────────────────────────────────────────────────

  @isTest
  static void buildFile_shouldGroupKeysWithSameHardwareKeyUnderOneHeader() {
    // Given two CCSS keys with identical LPAR fields (same hardware key)
    License_Key__c k1 = makeCcssKey('Prod A', 'CA', 'KEY001', 'SYS1', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');
    License_Key__c k2 = makeCcssKey('Prod B', 'CB', 'KEY002', 'SYS2', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k1, k2 });
    Test.stopTest();

    // Then — hardware key header should appear exactly once
    Integer headerCount = result.split('Partition Hardware Key:').size() - 1;
    System.Assert.areEqual(
      1,
      headerCount,
      'Two keys with the same LPAR fields should be grouped under a single hardware-key header.'
    );
  }

  // ─── PRODUCT / PRODUCT_CODE lines ────────────────────────────────────────

  @isTest
  static void buildFile_shouldIncludeProductNameAndProductCode() {
    // Given a CCSS key with a known product name and product code
    License_Key__c k = makeCcssKey('CCSS Core', 'CC01', 'KEY999', 'SYS', 'Generic', null, 'SN1', 'M1', 'FC1', 'LP1');

    // When
    Test.startTest();
    String result = builder.buildFile(new List<License_Key__c>{ k });
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      result.contains('PRODUCT=CCSS Core'),
      'buildFile() output should include a PRODUCT= line with the product name.'
    );
    System.Assert.isTrue(
      result.contains('PRODUCT_CODE=CC01'),
      'buildFile() output should include a PRODUCT_CODE= line with the product code.'
    );
  }
}