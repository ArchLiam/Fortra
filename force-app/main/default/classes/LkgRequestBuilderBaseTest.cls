@isTest
private class LkgRequestBuilderBaseTest {
  private class ExposedRequestBuilder extends LkgRequestBuilderBase {
    public String formatExpirationDate(Date expirationDate) {
      return getFormattedExpirationDate(expirationDate);
    }

    public String stringOrDefault(String value, String defaultValue) {
      return getStringOrDefaultIfNull(value, defaultValue);
    }

    public String integerStringOrDefault(Integer value, String defaultValue) {
      return getIntegerStringOrDefaultIfNull(value, defaultValue);
    }

    public String binaryString(Integer value) {
      return toBinaryString(value);
    }
  }

  private static LkgRequestBuilderBase.KeyData keyData;
  private static LkgRequestBuilderBase builder;
  private static ExposedRequestBuilder exposedBuilder;
  static final String silo = 'powertech';
  static final String productCode = '24';
  static final String lkgProductIdentifierName = 'CCSS069_QSystem_Monitor_Legacy';
  static final String internalProductName = 'QSystem Monitor-Legacy';
  static final String externalProductName = 'QSystem Monitor';

  static {
    LkgRequestBuilderBaseTest.keyData = new LkgRequestBuilderBase.KeyData();
    LkgRequestBuilderBaseTest.keyData.ProductCode = productCode;
    LkgRequestBuilderBaseTest.keyData.Silo = silo;
    LkgRequestBuilderBaseTest.keyData.subSilo = null;
    LkgRequestBuilderBaseTest.keyData.lkgProductIdentifierName = lkgProductIdentifierName;
    LkgRequestBuilderBaseTest.keyData.internalProductName = internalProductName;
    LkgRequestBuilderBaseTest.keyData.externalProductName = externalProductName;

    LkgRequestBuilderBaseTest.builder = new LkgRequestBuilderBase();
    LkgRequestBuilderBaseTest.exposedBuilder = new ExposedRequestBuilder();
  }

  @isTest
  static void buildRequest_ShouldNotReturnNull() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then a request should be returned
    System.Assert.isNotNull(licenseKeyRequest, 'Request should not be null.');
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(productCode, licenseKeyRequest.productCode, 'Product code should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetLkgProductIdentifierName() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then license key product identifier name should be set on request
    System.Assert.areEqual(
      lkgProductIdentifierName,
      licenseKeyRequest.lkgProductIdentifierName,
      'License key product identifier name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetInternalProductName() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then internal product name should be set on request
    System.Assert.areEqual(
      internalProductName,
      licenseKeyRequest.internalProductName,
      'Internal product name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExternalProductName() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then external product name should be set on request
    System.Assert.areEqual(
      externalProductName,
      licenseKeyRequest.externalProductName,
      'External product name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSubSilo() {
    // Given license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderBaseTest.builder.buildRequest(
      LkgRequestBuilderBaseTest.keyData
    );
    Test.stopTest();

    // Then subsilo should be set on request
    System.Assert.areEqual(null, licenseKeyRequest.subSilo, 'SubSilo should be set.');
  }

  @isTest
  static void getFormattedExpirationDate_ShouldReturnFormattedDate() {
    Test.startTest();
    String result = exposedBuilder.formatExpirationDate(Date.newInstance(2026, 4, 17));
    Test.stopTest();

    System.assertEquals('20260417', result, 'Expiration date should be formatted as yyyyMMdd.');
  }

  @isTest
  static void getFormattedExpirationDate_ShouldReturnEmptyStringForNull() {
    Test.startTest();
    String result = exposedBuilder.formatExpirationDate(null);
    Test.stopTest();

    System.assertEquals('', result, 'Null expiration dates should return an empty string.');
  }

  @isTest
  static void getStringOrDefaultIfNull_ShouldReturnExpectedValue() {
    Test.startTest();
    String originalValue = exposedBuilder.stringOrDefault('value', 'fallback');
    String fallbackValue = exposedBuilder.stringOrDefault(null, 'fallback');
    Test.stopTest();

    System.assertEquals('value', originalValue, 'Non-null strings should be returned as-is.');
    System.assertEquals('fallback', fallbackValue, 'Null strings should return the default value.');
  }

  @isTest
  static void getIntegerStringOrDefaultIfNull_ShouldReturnExpectedValue() {
    Test.startTest();
    String originalValue = exposedBuilder.integerStringOrDefault(1234567, 'fallback');
    String fallbackValue = exposedBuilder.integerStringOrDefault(null, 'fallback');
    Test.stopTest();

    System.assertEquals('1234567', originalValue, 'Integers should be converted without separators.');
    System.assertEquals('fallback', fallbackValue, 'Null integers should return the default value.');
  }

  @isTest
  static void toBinaryString_ShouldReturnExpectedValues() {
    Test.startTest();
    String zeroResult = exposedBuilder.binaryString(0);
    String nonZeroResult = exposedBuilder.binaryString(10);
    Test.stopTest();

    System.assertEquals('', zeroResult, 'Zero currently returns an empty binary string.');
    System.assertEquals('1010', nonZeroResult, 'Positive integers should be converted to binary.');
  }
}