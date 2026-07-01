@isTest
private class LkgRequestBuilderPtMultiTest {
  private static LkgRequestBuilderPtMulti.PtMultiKeyData keyData;
  private static LkgRequestBuilderPtMulti builder;
  static final String productCode = 'PEM';
  static final String release = '11';
  static final String modification = '05';
  static final String hardwareIdentifier = 'W-00:15:5D:45:6E:40';
  static final String points = '42';
  static final DateTime expirationDate = Date.today().addDays(90);

  static {
    LkgRequestBuilderPtMultiTest.keyData = new LkgRequestBuilderPtMulti.PtMultiKeyData();
    LkgRequestBuilderPtMultiTest.keyData.KeyType = 'Generic';
    LkgRequestBuilderPtMultiTest.keyData.ProductCode = LkgRequestBuilderPtMultiTest.productCode;
    LkgRequestBuilderPtMultiTest.keyData.release = release;
    LkgRequestBuilderPtMultiTest.keyData.modification = modification;
    LkgRequestBuilderPtMultiTest.keyData.HardwareId = hardwareIdentifier;
    LkgRequestBuilderPtMultiTest.keyData.points = points;
    LkgRequestBuilderPtMultiTest.keyData.ExpirationDate = expirationDate.date();

    LkgRequestBuilderPtMultiTest.builder = new LkgRequestBuilderPtMulti();
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    string expectedResult = release + '.' + modification;
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestNoModification_ShouldSetVersion() {
    // Given ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    string expectedResult = release + '.0';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestNoRelease_ShouldDefaultVersion() {
    // Given ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.release = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then version should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetHardwareNumber() {
    // Given ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then hardware identifier should be set on request
    System.Assert.areEqual(
      hardwareIdentifier,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.hardwareIdentifier.ordinal()),
      'Hardware identifier should be set.'
    );
  }

  //#region points

  @isTest
  static void buildRequest_ShouldSetPoints() {
    // Given ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then points should be set on request
    String expectedResults = 'P' + points;
    System.Assert.areEqual(
      expectedResults,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.points.ordinal()),
      'Points should be set.'
    );
  }

  @isTest
  static void buildRequestTierEnabled_ShouldSetPoints() {
    // Given ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.ProductCode = 'BAD';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then points should be set on request
    String expectedResults = 'S1P' + points;
    System.Assert.areEqual(
      expectedResults,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.points.ordinal()),
      'Points should be set.'
    );
  }

  @isTest
  static void buildRequestProductCodeVbm_ShouldSetPoints() {
    // Given ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.ProductCode = 'VBM';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then points should be set on request
    String expectedResults = 'P' + points;
    System.Assert.areEqual(
      expectedResults,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.points.ordinal()),
      'Points should be set.'
    );
  }

  @isTest
  static void buildRequestNoPoints_ShouldDefaultPoints() {
    // Given ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.points = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then points should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.points.ordinal()),
      'Points should be defaulted.'
    );
  }

  //#endregion

  //#region key type

  @isTest
  static void buildRequestGeneric_ShouldSetKeyType() {
    // Given generic ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.licenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetKeyType() {
    // Given permanent ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.licenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemporary_ShouldSetKeyType() {
    // Given a specific/temporary ptmulti license key data
    LkgRequestBuilderPtMultiTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'T',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.licenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestInvalidType_ShouldDefaultKeyType() {
    // Given ptmulti license key data with an invalid key type
    LkgRequestBuilderPtMultiTest.keyData.KeyType = 'Invalid_Type';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then key type should default to blank on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.licenseKeyType.ordinal()),
      'Key type should default.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given ptmulti license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPtMultiTest.builder.buildRequest(
      LkgRequestBuilderPtMultiTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPtMulti.PtMultiParameters.expirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }
}