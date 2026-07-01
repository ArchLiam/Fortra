@isTest
private class LkgRequestBuilderHalcyonIbmTest {
  private static LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData keyData;
  private static LkgRequestBuilderHalcyonIbm builder;
  static final String subsilo = 'ibm';
  static final String mergedProductCode = '001010001001011000001000000000000000';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final String systemName = 'MEEMIC2';
  static final String serialNumber = '780B530';
  static final String modelNumber = '42A';
  static final String featureCode = 'FC123';

  static {
    keyData = new LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData();
    keyData.subsilo = subsilo;
    keyData.KeyType = LkgRequestBuilderBase.KEYTYPE_GENERIC;
    keyData.ExpirationDate = expirationDate.date();
    keyData.lparSystemName = systemName;
    keyData.lparSerialNumber = serialNumber;
    keyData.modelNumber = modelNumber;
    keyData.featureCode = featureCode;
    keyData.individualProducts = '["15","14","12","21"]';
    keyData.individualMonitors = '["3","5","9","14"]';

    builder = new LkgRequestBuilderHalcyonIbm();
  }

  @isTest
  static void buildRequest_ShouldSetSubSilo() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(
      subsilo,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.subSilo.ordinal()),
      'Subsilo should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      mergedProductCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.productCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region API key type

  @isTest
  static void buildRequestGeneric_ShouldSetApiKeyType() {
    // Given generic Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then API key type should be set on request
    System.Assert.areEqual(
      'D',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.apiKeyType.ordinal()),
      'API key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetApiKeyType() {
    // Given permanent Halcyon IBM key data
    keyData.KeyType = LkgRequestBuilderBase.KEYTYPE_PERMANENT;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then API key type should be set on request
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.apiKeyType.ordinal()),
      'API key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemporary_ShouldSetApiKeyType() {
    // Given specific/temporary Halcyon IBM key data
    keyData.KeyType = LkgRequestBuilderBase.KEYTYPE_SPECIFIC_TEMPORARY;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then API key type should be set on request
    System.Assert.areEqual(
      'D',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.apiKeyType.ordinal()),
      'API key type should be set.'
    );
  }

  @isTest
  static void buildRequestNoKeyType_ShouldDefaultApiKeyType() {
    // Given Halcyon IBM key data with no key type
    keyData.KeyType = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then API key type should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.apiKeyType.ordinal()),
      'API key type should be defaulted.'
    );
  }

  //#endregion

  //#region expiration date

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.expirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequestPermanentNoDate_ShouldDefaultExpirationDate() {
    // Given permanent Halcyon IBM key data with no expiration date
    keyData.ExpirationDate = null;
    keyData.KeyType = LkgRequestBuilderBase.KEYTYPE_PERMANENT;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then expiration date should be defaulted on request
    String expectedResult = LkgRequestBuilderHalcyonIbm.maxDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.expirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetSystemName() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then system name should be set on request
    System.Assert.areEqual(
      systemName,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparSystemName.ordinal()
      ),
      'System name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSerialNumber() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then serial number should be set on request
    System.Assert.areEqual(
      serialNumber,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparSerialNumber.ordinal()
      ),
      'Serial number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetModelNumber() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then model number should be set on request
    System.Assert.areEqual(
      modelNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.modelNumber.ordinal()),
      'Model number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetFeatureCode() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then feature code should be set on request
    System.Assert.areEqual(
      featureCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.featureCode.ordinal()),
      'Feature code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldDefaultLparNumber() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then LPAR number should be defaulted on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparNumber.ordinal()),
      'LPAR number should be defaulted.'
    );
  }

  @isTest
  static void buildRequest_ShouldDefaultPerformanceGroup() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then performance group should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.performanceGroup.ordinal()
      ),
      'Performance group should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldDefaultCores() {
    // Given Halcyon IBM key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then cores should be defaulted on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.cores.ordinal()),
      'Performance group should be defaulted.'
    );
  }
}