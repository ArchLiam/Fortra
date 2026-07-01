@isTest
private class LkgRequestBuilderVitylTest {
  private static LkgRequestBuilderVityl.VitylKeyData keyData;
  private static LkgRequestBuilderVityl builder;
  static final String productCode = 'VCI';
  static final String release = '02';
  static final String modification = '01';
  static final String hardwareId = 'HW12345';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final String tier = 'Gold';
  static final Integer count = 100;
  static final String flag = 'A';

  static {
    keyData = new LkgRequestBuilderVityl.VitylKeyData();
    keyData.ProductCode = productCode;
    keyData.release = release;
    keyData.modification = modification;
    keyData.HardwareId = hardwareId;
    keyData.KeyType = 'Specific_Temporary';
    keyData.ExpirationDate = expirationDate.date();
    keyData.Tier = tier;
    keyData.Count = count;
    keyData.Flag = flag;
    builder = new LkgRequestBuilderVityl();
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given Vityl license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given Vityl license key data with release and modification
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be set on request
    String expectedVersion = release + '.' + modification;
    System.Assert.areEqual(
      expectedVersion,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestNoModification_ShouldSetVersionWithReleaseOnly() {
    // Given Vityl license key data with release but no modification
    keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be set to release only
    System.Assert.areEqual(
      release,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Version.ordinal()),
      'Version should be set to release only.'
    );
  }

  @isTest
  static void buildRequestNoRelease_ShouldSetVersionBlank() {
    // Given Vityl license key data with no release
    keyData.release = null;
    keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Version.ordinal()),
      'Version should be blank.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetHardwareId() {
    // Given Vityl license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then hardware id should be set on request
    System.Assert.areEqual(
      hardwareId,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.HardwareId.ordinal()),
      'Hardware id should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetPointsForVCI() {
    // Given Vityl license key data with VCI product code
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then points should be tier + S1 for VCI
    String expectedPoints = tier + 'S1';
    System.Assert.areEqual(
      expectedPoints,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Points.ordinal()),
      'Points should be set for VCI.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetPointsForNonVCI() {
    // Given Vityl license key data with non-VCI product code
    keyData.ProductCode = 'VCM';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then points should be S1C{count} for non-VCI
    String expectedPoints = 'S1C' + count;
    System.Assert.areEqual(
      expectedPoints,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Points.ordinal()),
      'Points should be set for non-VCI.'
    );
  }

  @isTest
  static void buildRequestGenericKey_ShouldSetPointsTo99999() {
    // Given Vityl license key data with Generic key type
    keyData.ProductCode = 'VCM';
    keyData.KeyType = 'Generic';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then points should be S1C99999 for generic key
    String expectedPoints = 'S1C99999';
    System.Assert.areEqual(
      expectedPoints,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Points.ordinal()),
      'Points should be set to 99999 for generic key.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLicenseKeyTypeForGeneric() {
    // Given Vityl generic license key data
    keyData.KeyType = 'Generic';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then license key type should be 'T'
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.LicenseKeyType.ordinal()),
      'License key type should be T for generic.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLicenseKeyTypeForPermanent() {
    // Given Vityl permanent license key data
    keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then license key type should be 'P'
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.LicenseKeyType.ordinal()),
      'License key type should be P for permanent.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLicenseKeyTypeForSpecificTemp() {
    // Given Vityl specific/temporary license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then license key type should be 'T'
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.LicenseKeyType.ordinal()),
      'License key type should be T for specific/temporary.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given Vityl license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetFlags() {
    // Given Vityl license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then flags should be set on request
    System.Assert.areEqual(
      flag,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderVityl.VitylParameters.Flags.ordinal()),
      'Flags should be set.'
    );
  }
}