@isTest
private class LkgRequestBuilderRSFTest {
  private static LkgRequestBuilderRSF.RSFKeyData keyData;
  private static LkgRequestBuilderRSF builder;
  static final String silo = 'rsf';
  static final String productCode = '100';
  static final String serialNumber = 'SN12345';
  static final String flag = 'TestFlag';
  static final DateTime expirationDate = Date.today().addDays(90);

  static {
    LkgRequestBuilderRSFTest.keyData = new LkgRequestBuilderRSF.RSFKeyData();
    keyData.Silo = silo;
    keyData.ProductCode = productCode;
    keyData.KeyType = 'Generic';
    keyData.ExpirationDate = expirationDate.date();
    keyData.LParSerialNumber = serialNumber;
    keyData.Flag = flag;

    LkgRequestBuilderRSFTest.builder = new LkgRequestBuilderRSF();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given RSF license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(LkgRequestBuilderRSFTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given RSF license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderRSFTest.productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given RSF license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSerialNumber() {
    // Given RSF license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then serial number should be set
    System.Assert.areEqual(
      serialNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.LParSerialNumber.ordinal()),
      'Serial number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetFlag() {
    // Given RSF license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then flag should be set
    System.Assert.areEqual(
      flag,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.Flag.ordinal()),
      'Flag should be set.'
    );
  }

  @isTest
  static void buildRequestWithoutSerialNumber_ShouldSetDefaultValue() {
    // Given RSF license key data without serial number
    LkgRequestBuilderRSFTest.keyData.LParSerialNumber = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then serial number should be set with default value
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.LParSerialNumber.ordinal()),
      'Serial number should be set with default value.'
    );
  }

  @isTest
  static void buildRequestWithoutFlag_ShouldSetDefaultValue() {
    // Given RSF license key data without flag
    LkgRequestBuilderRSFTest.keyData.Flag = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRSFTest.builder.buildRequest(
      LkgRequestBuilderRSFTest.keyData
    );
    Test.stopTest();

    // Then flag should be set with default value
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRSF.RSFParameters.Flag.ordinal()),
      'Flag should be set with default value.'
    );
  }
}