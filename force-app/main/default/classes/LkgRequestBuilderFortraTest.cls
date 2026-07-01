@IsTest
public with sharing class LkgRequestBuilderFortraTest {
  private static LkgRequestBuilderFortra.FortraKeyData keyData;
  private static LkgRequestBuilderFortra builder;
  static final String silo = 'fortra';
  static final String hardwareId = 'ABC123';
  static final String tiers = 'A0B0C0D1E5S2';
  static final String licenseKeyType = 'Generic';
  static final DateTime expirationDate = Date.today().addDays(30);
  static {
    LkgRequestBuilderFortraTest.keyData = new LkgRequestBuilderFortra.FortraKeyData();
    LkgRequestBuilderFortraTest.keyData.Silo = silo;
    LkgRequestBuilderFortraTest.keyData.HardwareId = hardwareId;
    LkgRequestBuilderFortraTest.keyData.tiers = tiers;
    LkgRequestBuilderFortraTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderFortraTest.keyData.KeyType = licenseKeyType;

    LkgRequestBuilderFortraTest.builder = new LkgRequestBuilderFortra();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given Fortra license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.assertEquals(LkgRequestBuilderFortraTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given Fortra license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.assertEquals(
      LkgRequestBuilderFortraTest.keyData.ProductCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given Fortra license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    System.assertEquals(
      LkgRequestBuilderFortra.VERSION_DEFAULT,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.Version.ordinal()),
      'Version should be set to default empty string.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetHardwareId() {
    // Given Fortra license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then hardware ID should be set on request
    System.assertEquals(
      LkgRequestBuilderFortraTest.keyData.HardwareId,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.HardwareId.ordinal()),
      'Hardware ID should be set based on key data.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetTiers() {
    // Given Fortra license key data with tiers
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then tiers should be set on request
    System.assertEquals(
      LkgRequestBuilderFortraTest.keyData.tiers,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.Tiers.ordinal()),
      'Tiers should be set based on key data.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLicenseKeyType() {
    // Given Fortra license key data with license key type
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then license key type should be set on request
    String expectedLicenseKeyType = 'T'; // 'Generic' maps to 'T'
    System.assertEquals(
      expectedLicenseKeyType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be set based on key type.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given Fortra license key data with expiration date
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderFortraTest.builder.buildRequest(
      LkgRequestBuilderFortraTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedExpirationDate = expirationDate.format('yyyyMMdd');

    System.assertEquals(
      expectedExpirationDate,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderFortra.FortraKeyParameters.ExpirationDate.ordinal()),
      'Expiration date should be formatted and set based on key data.'
    );
  }
}