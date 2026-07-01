@isTest
private class LkgISeriesFileBuilderTest {
  // ─── safe() ───────────────────────────────────────────────────────────────

  @isTest
  static void safe_shouldReturnValueWhenNotNull() {
    // Given a non-null string value

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.safe('SERIAL123');
    Test.stopTest();

    // Then
    System.Assert.areEqual('SERIAL123', result, 'safe() should return the original non-null value unchanged.');
  }

  @isTest
  static void safe_shouldReturnEmptyStringWhenNull() {
    // Given a null value

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.safe(null);
    Test.stopTest();

    // Then
    System.Assert.areEqual('', result, 'safe() should return an empty string for null input.');
  }

  // ─── buildHardwareKey() ───────────────────────────────────────────────────

  @isTest
  static void buildHardwareKey_shouldCombineAllFieldsWithDashes() {
    // Given a key record with all LPAR fields populated
    License_Key__c k = new License_Key__c(
      LPAR_Serial_Number__c = 'SN001',
      LPAR_Model_Number__c = 'M400',
      LPAR_Feature_Code__c = 'FC55',
      LPAR_Number__c = 'LP01'
    );

    // When
    Test.startTest();
    String hwKey = LkgISeriesFileBuilder.buildHardwareKey(k);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      'I-SN001-M400-FC55-LP01',
      hwKey,
      'buildHardwareKey() should produce I-serial-model-feature-lpar.'
    );
  }

  @isTest
  static void buildHardwareKey_shouldHandleNullFieldsGracefully() {
    // Given a key record with all LPAR fields null
    License_Key__c k = new License_Key__c();

    // When
    Test.startTest();
    String hwKey = LkgISeriesFileBuilder.buildHardwareKey(k);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      'I----',
      hwKey,
      'buildHardwareKey() should treat null LPAR fields as empty strings, producing "I----".'
    );
  }

  // ─── buildGroupHeader() ───────────────────────────────────────────────────

  @isTest
  static void buildGroupHeader_shouldContainHardwareKeyString() {
    // Given a hardware key identifier
    String hwKey = 'I-SN001-M400-FC55-LP01';

    // When
    Test.startTest();
    String header = LkgISeriesFileBuilder.buildGroupHeader(hwKey);
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      header.contains(hwKey),
      'buildGroupHeader() should include the hardware key value inside the header block.'
    );
  }

  // ─── resolveLicenseType() ─────────────────────────────────────────────────

  @isTest
  static void resolveLicenseType_shouldReturnZeroForNull() {
    // Given a null key type

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveLicenseType(null);
    Test.stopTest();

    // Then
    System.Assert.areEqual('0', result, 'resolveLicenseType() should return "0" for a null key type.');
  }

  @isTest
  static void resolveLicenseType_shouldReturnZeroForBlankString() {
    // Given a blank key type

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveLicenseType('   ');
    Test.stopTest();

    // Then
    System.Assert.areEqual('0', result, 'resolveLicenseType() should return "0" for a blank key type.');
  }

  @isTest
  static void resolveLicenseType_shouldReturnOneForGenericKeyType() {
    // Given a key type of "Generic" (case-insensitive comparison)

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveLicenseType('Generic');
    Test.stopTest();

    // Then
    System.Assert.areEqual('1', result, 'resolveLicenseType() should return "1" for the Generic key type.');
  }

  @isTest
  static void resolveLicenseType_shouldReturnFiveForTemporaryKeyType() {
    // Given a key type that contains the word "temporary"

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveLicenseType('Temporary Evaluation');
    Test.stopTest();

    // Then
    System.Assert.areEqual('5', result, 'resolveLicenseType() should return "5" for a type that contains "temporary".');
  }

  @isTest
  static void resolveLicenseType_shouldReturnZeroForUnrecognisedKeyType() {
    // Given a key type that is neither generic nor temporary

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveLicenseType('Perpetual');
    Test.stopTest();

    // Then
    System.Assert.areEqual('0', result, 'resolveLicenseType() should return "0" for an unrecognised key type.');
  }

  // ─── resolveExpires() ─────────────────────────────────────────────────────

  @isTest
  static void resolveExpires_shouldReturnEmptyStringForNullDate() {
    // Given a null end date (permanent / perpetual licence)

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveExpires(null);
    Test.stopTest();

    // Then
    System.Assert.areEqual('', result, 'resolveExpires() should return an empty string when end date is null.');
  }

  @isTest
  static void resolveExpires_shouldReturnYyyyMmDdFormattedDate() {
    // Given a specific end date of 31 Dec 2026
    Date endDate = Date.newInstance(2026, 12, 31);

    // When
    Test.startTest();
    String result = LkgISeriesFileBuilder.resolveExpires(endDate);
    Test.stopTest();

    // Then
    System.Assert.areEqual('20261231', result, 'resolveExpires() should return the date formatted as yyyyMMdd.');
  }
}