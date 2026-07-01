@isTest
private class LkgRequestBuilderAccessAuthTest {
  private static LkgRequestBuilderAccessAuth.AccessAuthKeyData keyData;
  private static LkgRequestBuilderAccessAuth builder;
  static final String silo = 'accessauth';
  static final String productCode = 'AAM';
  static final String hardwareId = '0000000000';
  static final String type = 'T';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer numberOfUsers = 99998;
  static final String release = '100';

  static {
    LkgRequestBuilderAccessAuthTest.keyData = new LkgRequestBuilderAccessAuth.AccessAuthKeyData();
    keyData.Silo = silo;
    keyData.ProductCode = productCode;
    keyData.ExpirationDate = expirationDate.date();
    keyData.HardwareId = hardwareId;
    keyData.KeyType = 'Generic';
    keyData.NumberOfUsers = numberOfUsers;
    keyData.release = release;

    LkgRequestBuilderAccessAuthTest.builder = new LkgRequestBuilderAccessAuth();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(LkgRequestBuilderAccessAuthTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderAccessAuthTest.productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.productCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    string expectedResult = LkgRequestBuilderAccessAuthTest.release + '.0';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestWithModification_ShouldSetVersion() {
    // Given accessauth license key data with a modification
    LkgRequestBuilderAccessAuthTest.keyData.modification = '5';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then version with release should be set on request
    string expectedResult =
      LkgRequestBuilderAccessAuthTest.release +
      '.' +
      LkgRequestBuilderAccessAuthTest.keyData.modification;
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestMissingRelease_ShouldSetBlank() {
    // Given accessauth license key data with a release
    LkgRequestBuilderAccessAuthTest.keyData.release = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then version should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetHardwareIdNumber() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then hardware id number should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderAccessAuthTest.hardwareId,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.hardwareIdNumber.ordinal()
      ),
      'Hardware Id number should be set.'
    );
  }

  //#region tier code

  @isTest
  static void buildRequest_ShouldSetTierCodes() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U99998T0L1';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  @isTest
  static void buildRequestPermKey_ShouldSetTierCodes() {
    // Given permanent accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U99998T0L2';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  @isTest
  static void buildRequestSubscriptionKey_ShouldSetTierCodes() {
    // Given subscription accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U99998T0L3';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  @isTest
  static void buildRequestNoKeyType_ShouldSetTierCodes() {
    // Given accessauth with missing key type license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = '';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U99998T0L';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  @isTest
  static void buildRequestHighUserCount_ShouldSetTierCodes() {
    // Given accessauth license key data with high user count
    LkgRequestBuilderAccessAuthTest.keyData.NumberOfUsers = 123456;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U123456T23457L1';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  @isTest
  static void buildRequestSecurityScan_ShouldSetTierCodes() {
    // Given securityscan license key data
    LkgRequestBuilderAccessAuthTest.keyData.Silo = 'securityscan';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then tier code should be set on request
    String expectedResult = 'S1U99999U99999L1';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal()),
      'Tier code should be set.'
    );
  }

  //#endregion

  //#region key type

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given a generic accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal()
      ),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestTempKey_ShouldSetKeyType() {
    // Given a temporary accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal()
      ),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermKey_ShouldSetKeyType() {
    // Given a permanent accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal()
      ),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSubscriptionKey_ShouldSetKeyType() {
    // Given a permanent accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'E',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal()
      ),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestInvalidKeyType_ShouldSetKeyTypeToBlank() {
    // Given a accessauth license key data
    LkgRequestBuilderAccessAuthTest.keyData.KeyType = '';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then key type should be set to blank on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal()
      ),
      'Key type should be set.'
    );
  }

  //#endregion

  //#region expiration date

  @isTest
  static void buildRequest_ShouldSetExpritationDate() {
    // Given accessauth license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    string expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.expirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequestNoExpirationDate_ShouldSetExpritationDate() {
    // Given accessauth license key data with no expiration date
    LkgRequestBuilderAccessAuthTest.keyData.ExpirationDate = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAccessAuthTest.builder.buildRequest(
      LkgRequestBuilderAccessAuthTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set to blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderAccessAuth.AccessAuthParameters.expirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  //#endregion
}