@isTest
private class LkgRequestBuilderIntermapperTest {
  private static LkgRequestBuilderIntermapper.IntermapperKeyData keyData;
  private static LkgRequestBuilderIntermapper builder;
  static final String productCode = '042';
  static final String silo = 'intermapper';
  static final String release = '6';
  static final String modification = '3';
  static final DateTime expirationDate = Date.today().addDays(90);

  static {
    keyData = new LkgRequestBuilderIntermapper.IntermapperKeyData();
    keyData.Silo = silo;
    keyData.ProductCode = productCode;
    keyData.release = release;
    keyData.modification = modification;
    keyData.KeyType = 'Permanent';
    keyData.ExpirationDate = expirationDate.date();
    keyData.HardwareId = 'HW98765';
    keyData.ServerDevices = 500;
    keyData.ServerFlows = 100;
    keyData.Remotes = 50;

    builder = new LkgRequestBuilderIntermapper();
  }

  @isTest
  static void buildRequest_shouldSetSilo() {
    // Given Intermapper license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_shouldSetProductCode() {
    // Given Intermapper license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then product code should be set
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_shouldSetVersion() {
    // Given Intermapper license key data with release and modification
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be release.modification
    System.Assert.areEqual(
      release + '.' + modification,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Version.ordinal()),
      'Version should be set as release.modification.'
    );
  }

  @isTest
  static void buildRequestNoModification_shouldSetVersionFromReleaseOnly() {
    // Given Intermapper license key data with release but no modification
    keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be release only
    System.Assert.areEqual(
      release,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Version.ordinal()),
      'Version should be release only when modification is null.'
    );
  }

  @isTest
  static void buildRequestNoRelease_shouldLeaveVersionBlank() {
    // Given Intermapper license key data with no release
    keyData.release = null;
    keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then version should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Version.ordinal()),
      'Version should be blank when release and modification are null.'
    );
  }

  @isTest
  static void buildRequest_shouldSetHardwareId() {
    // Given Intermapper license key data with a hardware id
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then hardware id should be set
    System.Assert.areEqual(
      'HW98765',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.HardwareId.ordinal()),
      'Hardware id should be set.'
    );
  }

  @isTest
  static void buildRequestNoHardwareId_shouldDefaultToEmpty() {
    // Given Intermapper license key data with no hardware id
    keyData.HardwareId = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then hardware id should default to empty string
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.HardwareId.ordinal()),
      'Hardware id should default to empty string.'
    );
  }

  @isTest
  static void buildRequest_shouldSetTierKey() {
    // Given Intermapper license key data with devices, flows, remotes
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then points (tier key) should encode all three values
    System.Assert.areEqual(
      'S1D500F100R50',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Points.ordinal()),
      'Tier key should be set.'
    );
  }

  @isTest
  static void buildRequestNullTierValues_shouldDefaultToZero() {
    // Given Intermapper license key data with null devices, flows, remotes
    keyData.ServerDevices = null;
    keyData.ServerFlows = null;
    keyData.Remotes = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then points should default each value to zero
    System.Assert.areEqual(
      'S1D0F0R0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Points.ordinal()),
      'Null tier values should default to zero.'
    );
  }

  //#region key type

  @isTest
  static void buildRequestPermanent_shouldSetKeyType() {
    // Given Intermapper permanent license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be 'P'
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderIntermapper.IntermapperParameters.LicenseKeyType.ordinal()
      ),
      'Permanent key type should be P.'
    );
  }

  @isTest
  static void buildRequestGeneric_shouldSetKeyType() {
    // Given Intermapper generic license key data
    keyData.KeyType = 'Generic';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be 'T'
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderIntermapper.IntermapperParameters.LicenseKeyType.ordinal()
      ),
      'Generic key type should be T.'
    );
  }

  @isTest
  static void buildRequestSubscription_shouldSetKeyType() {
    // Given Intermapper subscription license key data
    keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be 'E'
    System.Assert.areEqual(
      'E',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderIntermapper.IntermapperParameters.LicenseKeyType.ordinal()
      ),
      'Subscription key type should be E.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_shouldSetExpirationDate() {
    // Given Intermapper license key data with an expiration date
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then expiration date should be formatted yyyyMMdd
    String expectedDate = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedDate,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderIntermapper.IntermapperParameters.ExpirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_shouldSetFlagsToEmpty() {
    // Given Intermapper license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then flags should always be empty
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderIntermapper.IntermapperParameters.Flags.ordinal()),
      'Flags should always be empty.'
    );
  }
}