@isTest
private class LkgRequestBuilderLegacyIbmTest {
  private static LkgRequestBuilderLegacyIbm.LegacyIbmKeyData keyData;
  private static LkgRequestBuilderLegacyIbm builder;
  static final String productCode = 'S1';
  static final String silo = 'legacyibm';
  static final String release = '03';
  static final String modification = '00010';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final String serialNumber = '7888A00';
  static final String processorGroup = 'P20';
  static final Integer usageLimit = 5;
  static final String model = '42A';
  static final String featureCode = 'EP1E';

  static {
    LkgRequestBuilderLegacyIbmTest.keyData = new LkgRequestBuilderLegacyIbm.LegacyIbmKeyData();
    LkgRequestBuilderLegacyIbmTest.keyData.Silo = silo;
    LkgRequestBuilderLegacyIbmTest.keyData.ProductCode = productCode;
    LkgRequestBuilderLegacyIbmTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderLegacyIbmTest.keyData.HardwareId = serialNumber;
    LkgRequestBuilderLegacyIbmTest.keyData.processorGroup = processorGroup;
    LkgRequestBuilderLegacyIbmTest.keyData.usageLimit = usageLimit;
    LkgRequestBuilderLegacyIbmTest.keyData.model = model;
    LkgRequestBuilderLegacyIbmTest.keyData.featureCode = featureCode;
    LkgRequestBuilderLegacyIbmTest.keyData.supportKey = false;
    LkgRequestBuilderLegacyIbmTest.keyData.release = release;
    LkgRequestBuilderLegacyIbmTest.keyData.modification = modification;

    LkgRequestBuilderLegacyIbmTest.builder = new LkgRequestBuilderLegacyIbm();
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.productCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    System.Assert.areEqual(
      '310',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestDifferentReleaseAndModification_ShouldSetVersion() {
    // Given legacy IBM license key data
    LkgRequestBuilderLegacyIbmTest.keyData.release = '06';
    LkgRequestBuilderLegacyIbmTest.keyData.modification = '00011';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    System.Assert.areEqual(
      '611',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestNoRelease_ShouldDefaultVersion() {
    // Given legacy IBM license key data with no release
    LkgRequestBuilderLegacyIbmTest.keyData.release = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then version should be defaulted on request
    Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.version.ordinal()),
      'Version should be defaulted.'
    );
  }

  @isTest
  static void buildRequestNoModification_ShouldDefaultVersion() {
    // Given legacy IBM license key data with no modification
    LkgRequestBuilderLegacyIbmTest.keyData.modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    String expectedResult = '300';
    Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.version.ordinal()),
      'Version should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = LkgRequestBuilderLegacyIbmTest.expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.expirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSerialNumber() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then serial number should be set on request
    System.Assert.areEqual(
      serialNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.hardwareId.ordinal()),
      'Hardware ID should be set.'
    );
  }

  //#region processor group

  @isTest
  static void buildRequest_ShouldSetProcessGroup() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then process group should be set on request
    System.Assert.areEqual(
      processorGroup,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.processorGroup.ordinal()),
      'Processor group should be set.'
    );
  }

  @isTest
  static void buildRequestBlankProcessGroup_ShouldSetDefault() {
    // Given legacy IBM license key data
    LkgRequestBuilderLegacyIbmTest.keyData.ProcessorGroup = '';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then process group should be defaulted on request
    System.Assert.areEqual(
      LkgRequestBuilderLegacyIbm.processorGroupDefault,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.processorGroup.ordinal()),
      'Processor group should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetUsageLimit() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then usage limit should be set on request
    System.Assert.areEqual(
      usageLimit.toString(),
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.usageLimit.ordinal()),
      'Usage limit should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetModel() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then model should be set on request
    System.Assert.areEqual(
      model,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.model.ordinal()),
      'Model should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetFeatureCode() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then feature code should be set on request
    System.Assert.areEqual(
      featureCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.featureCode.ordinal()),
      'Feature code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetBlank() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then blank parameter should be set on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.blank.ordinal()),
      'Blank should be set.'
    );
  }

  //#region support key

  @isTest
  static void buildRequest_ShouldSetSupportKey() {
    // Given legacy IBM license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then support key should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.supportKey.ordinal()),
      'Support key should be set.'
    );
  }

  @isTest
  static void buildRequestSupportKey_ShouldSetSupportKey() {
    // Given legacy IBM support license key data
    LkgRequestBuilderLegacyIbmTest.keyData.SupportKey = true;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderLegacyIbmTest.builder.buildRequest(
      LkgRequestBuilderLegacyIbmTest.keyData
    );
    Test.stopTest();

    // Then support key should be set on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderLegacyIbm.LegacyIbmParameters.supportKey.ordinal()),
      'Support key should be set.'
    );
  }

  //#endregion
}