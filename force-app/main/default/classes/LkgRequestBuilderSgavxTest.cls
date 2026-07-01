@isTest
private class LkgRequestBuilderSgavxTest {
  private static LkgRequestBuilderSgavx.SgavxKeyData keyData;
  private static LkgRequestBuilderSgavx builder;
  static final String silo = 'sgavx';
  static final String productCode = 'AIX';
  static final String release = '11';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer userCount = 6;
  static final String hardwareIdNumber = '00:50:22:05:3a:94';
  static final string accountNumber = '00040817';
  static {
    LkgRequestBuilderSgavxTest.keyData = new LkgRequestBuilderSgavx.SgavxKeyData();
    LkgRequestBuilderSgavxTest.keyData.Silo = silo;
    LkgRequestBuilderSgavxTest.keyData.ProductCode = productCode;
    LkgRequestBuilderSgavxTest.keyData.release = release;
    LkgRequestBuilderSgavxTest.keyData.KeyType = 'Generic';
    LkgRequestBuilderSgavxTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderSgavxTest.keyData.NumberOfUsers = userCount;
    LkgRequestBuilderSgavxTest.keyData.HardwareId = hardwareIdNumber;
    LkgRequestBuilderSgavxTest.keyData.accountNumber = accountNumber;

    LkgRequestBuilderSgavxTest.builder = new LkgRequestBuilderSgavx();
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderSgavxTest.productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.productCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    String expectedResult = 'R' + LkgRequestBuilderSgavxTest.release + 'M0';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.licenseKeyType.ordinal()),
      'License key type should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  //#region hardware id number

  @isTest
  static void buildRequest_ShouldSetHardwareIdNumber() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then hardware id number should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderSgavxTest.hardwareIdNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.hardwareIdNumber.ordinal()),
      'Hardware id number should be set.'
    );
  }

  @isTest
  static void buildRequestNoHardwareId_ShouldSetToBlank() {
    // Given sgavx license key data
    LkgRequestBuilderSgavxTest.keyData.HardwareId = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then hardware id number should be set to blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.hardwareIdNumber.ordinal()),
      'Hardware id number should be set.'
    );
  }

  //#endregion

  //#region number of users

  @isTest
  static void buildRequest_ShouldSetNumberOfUsers() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then number of users should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderSgavxTest.userCount.toString(),
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.userCount.ordinal()),
      'Number of users should be set.'
    );
  }

  @isTest
  static void buildRequestNoUserCount_ShouldSetToBlank() {
    // Given sgavx license key data
    LkgRequestBuilderSgavxTest.keyData.NumberOfUsers = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then number of users should be set to blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.userCount.ordinal()),
      'User count should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetAccountNumber() {
    // Given sgavx license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderSgavxTest.builder.buildRequest(
      LkgRequestBuilderSgavxTest.keyData
    );
    Test.stopTest();

    // Then number of users should be set to blank
    System.Assert.areEqual(
      accountNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderSgavx.SgavxParameters.accountNumber.ordinal()),
      'Account number should be set.'
    );
  }
}