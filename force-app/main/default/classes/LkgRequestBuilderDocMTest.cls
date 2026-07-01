@isTest
private class LkgRequestBuilderDocMTest {
  private static LkgRequestBuilderDocM.DocMKeyData keyData;
  private static LkgRequestBuilderDocM builder;
  static final String silo = 'docm';
  static final String productCode = 'IFM';
  static final String hardwareId = '0000000000';
  static final String release = '100';
  static final String modification = '05';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer numberOfUsers = 50;

  static {
    LkgRequestBuilderDocMTest.keyData = new LkgRequestBuilderDocM.DocMKeyData();
    keyData.Silo = silo;
    keyData.ProductCode = productCode;
    keyData.ExpirationDate = expirationDate.date();
    keyData.HardwareId = hardwareId;
    keyData.KeyType = 'Generic';
    keyData.NumberOfUsers = numberOfUsers;
    keyData.Release = release;
    keyData.Modification = modification;

    LkgRequestBuilderDocMTest.builder = new LkgRequestBuilderDocM();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given docm license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(LkgRequestBuilderDocMTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given docm license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderDocMTest.productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given docm license key data
    LkgRequestBuilderDocM.DocMKeyData testKeyData = new LkgRequestBuilderDocM.DocMKeyData();
    testKeyData.Silo = silo;
    testKeyData.ProductCode = productCode;
    testKeyData.ExpirationDate = expirationDate.date();
    testKeyData.HardwareId = hardwareId;
    testKeyData.KeyType = 'Generic';
    testKeyData.NumberOfUsers = numberOfUsers;
    testKeyData.Release = release;
    testKeyData.Modification = modification;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(testKeyData);
    Test.stopTest();

    // Then version should be set on request
    string expectedResult = LkgRequestBuilderDocMTest.release + '.' + LkgRequestBuilderDocMTest.modification;
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestWithoutModification_ShouldSetVersionWithDefault() {
    // Given docm license key data without modification
    LkgRequestBuilderDocM.DocMKeyData testKeyData = new LkgRequestBuilderDocM.DocMKeyData();
    testKeyData.Silo = silo;
    testKeyData.ProductCode = productCode;
    testKeyData.ExpirationDate = expirationDate.date();
    testKeyData.HardwareId = hardwareId;
    testKeyData.KeyType = 'Generic';
    testKeyData.NumberOfUsers = numberOfUsers;
    testKeyData.Release = release;
    testKeyData.Modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(testKeyData);
    Test.stopTest();

    // Then version should be set with default modification
    string expectedResult = LkgRequestBuilderDocMTest.release + '.00';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Version.ordinal()),
      'Version should be set with default modification.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetHardware() {
    // Given docm license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then hardware should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderDocMTest.hardwareId,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Hardware.ordinal()),
      'Hardware should be set.'
    );
  }

  //#region tier code / points

  @isTest
  static void buildRequest_ShouldSetPointsWithNumberOfUsers() {
    // Given docm license key data with number of users
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then points should be set with tier and users
    String expectedResult = 'S2A' + LkgRequestBuilderDocMTest.numberOfUsers;
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Points.ordinal()),
      'Points should be set.'
    );
  }

  @isTest
  static void buildRequestWithTier_ShouldSetPointsWithTier() {
    // Given docm license key data with explicit tier
    LkgRequestBuilderDocMTest.keyData.Tier = 'S3B100';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then points should be set with tier value
    String expectedResult = 'S3B100';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Points.ordinal()),
      'Points should be set with tier.'
    );
  }

  @isTest
  static void buildRequestWithoutUsersOrTier_ShouldSetDefaultPoints() {
    // Given docm license key data without tier or users
    LkgRequestBuilderDocMTest.keyData.Tier = null;
    LkgRequestBuilderDocMTest.keyData.NumberOfUsers = 0;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then points should be set to default tier
    String expectedResult = 'S2';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.Points.ordinal()),
      'Points should be set to default.'
    );
  }

  //#endregion

  //#region key type

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given a generic docm license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.KeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestTempKey_ShouldSetKeyType() {
    // Given a temporary docm license key data
    LkgRequestBuilderDocMTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.KeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermKey_ShouldSetKeyType() {
    // Given a permanent docm license key data
    LkgRequestBuilderDocMTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.KeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestInvalidKeyType_ShouldSetKeyTypeToBlank() {
    // Given a docm license key data with invalid key type
    LkgRequestBuilderDocMTest.keyData.KeyType = 'Invalid';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then key type should be set to blank on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.KeyType.ordinal()),
      'Key type should be blank for invalid type.'
    );
  }

  //#endregion

  //#region expiration date

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given docm license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderDocMTest.builder.buildRequest(
      LkgRequestBuilderDocMTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set and formatted correctly
    string expectedResult = LkgRequestBuilderDocMTest.expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderDocM.DocMParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  //#endregion
}