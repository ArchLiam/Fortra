@isTest
private class LkgRequestBuilderPowerTechTest {
  private static LkgRequestBuilderPowerTech.PowerTechKeyData keyData;
  private static LkgRequestBuilderPowerTech builder;
  static final String productCode = '24';
  static final String silo = 'powertech';
  static final String release = '11';
  static final String lparNumberDefault = '99999';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer userCount = 10;
  static final Integer numberOfProcessors = 3;
  static {
    LkgRequestBuilderPowerTechTest.keyData = new LkgRequestBuilderPowerTech.PowerTechKeyData();
    LkgRequestBuilderPowerTechTest.keyData.Silo = silo;
    LkgRequestBuilderPowerTechTest.keyData.ProductCode = productCode;
    LkgRequestBuilderPowerTechTest.keyData.release = release;
    LkgRequestBuilderPowerTechTest.keyData.KeyType = 'Generic';
    LkgRequestBuilderPowerTechTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderPowerTechTest.keyData.LparNumber = lparNumberDefault;
    LkgRequestBuilderPowerTechTest.keyData.EndLparNumber = lparNumberDefault;
    LkgRequestBuilderPowerTechTest.keyData.NumberOfUsers = userCount;
    LkgRequestBuilderPowerTechTest.keyData.NumberOfProcessors = numberOfProcessors;

    LkgRequestBuilderPowerTechTest.builder = new LkgRequestBuilderPowerTech();
  }

  //#region silo

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(LkgRequestBuilderPowerTechTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given PowerTech license key data with release
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    string expectedResult = 'R' + release + 'M0';
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.Version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestNoRelease_ShouldLeaveVersionBlank() {
    // Given PowerTech license key data with no release
    LkgRequestBuilderPowerTechTest.keyData.release = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then version should be blank on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.Version.ordinal()),
      'Version should be blank.'
    );
  }

  @isTest
  static void buildRequestReleaseAndModification_ShouldSetVersion() {
    // Given PowerTech license key data with a release and modification
    string modification = '5';
    LkgRequestBuilderPowerTechTest.keyData.modification = modification;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    string expectedResult = 'R' + release + 'M' + modification;
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.Version.ordinal()),
      'Version should be set.'
    );
  }

  //#endregion

  //#region key type

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given PowerTech generic license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetKeyType() {
    // Given PowerTech permanent license key data
    LkgRequestBuilderPowerTechTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldSetKeyType() {
    // Given PowerTech specific/temporary license key data
    LkgRequestBuilderPowerTechTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '5',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldConvertToPermWhenInRange() {
    // Given PowerTech specific/temporary license key data with version in range
    LkgRequestBuilderPowerTech.PowerTechKeyData termKeyData = new LkgRequestBuilderPowerTech.PowerTechKeyData();
    termKeyData.ProductCode = productCode;
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '5';
    termKeyData.modification = '20';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(termKeyData);
    Test.stopTest();

    // Then key type should be '0' (Permanent) because version 5.20 is in range 4.07-10.12
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be 0 (Permanent) when version is in range.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldKeepTermWhenOutOfRange() {
    // Given PowerTech specific/temporary license key data with version out of range
    LkgRequestBuilderPowerTech.PowerTechKeyData termKeyData = new LkgRequestBuilderPowerTech.PowerTechKeyData();
    termKeyData.ProductCode = productCode;
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '11';
    termKeyData.modification = '5';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(termKeyData);
    Test.stopTest();

    // Then key type should be '5' (Term) because version 11.05 is out of range 4.07-10.12
    System.Assert.areEqual(
      '5',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be 5 (Term) when version is out of range.'
    );
  }

  @isTest
  static void buildRequestNoKeyType_ShouldDefaultKeyType() {
    // Given PowerTech license key data with no key type
    LkgRequestBuilderPowerTechTest.keyData.KeyType = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then key type should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LicenseKeyType.ordinal()),
      'Key type should be defaulted.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequestNoTermDate_ShouldSetExpirationDate() {
    // Given PowerTech license key data with no term date
    LkgRequestBuilderPowerTechTest.keyData.ExpirationDate = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ExpirationDate.ordinal()),
      'Expiration date should be blank.'
    );
  }

  //#region serial number

  @isTest
  static void buildRequestNoHardware_ShouldDefaultSerialNumber() {
    // Given PowerTech license key data with no hardware
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then serial number should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderPowerTech.PowerTechParameters.LParSerialNumber.ordinal()
      ),
      'Serial number should be blank.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSerialNumber() {
    // Given PowerTech license key data
    string lparSerialNumber = '780BBB0';
    LkgRequestBuilderPowerTechTest.keyData.LParSerialNumber = lparSerialNumber;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then serial number should be set
    System.Assert.areEqual(
      lparSerialNumber,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderPowerTech.PowerTechParameters.LParSerialNumber.ordinal()
      ),
      'Serial number should be set.'
    );
  }

  //#end region

  //#region model

  @isTest
  static void buildRequestNoModel_ShouldDefaultModel() {
    // Given PowerTech license key data with no hardware model
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then model should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ModelNumber.ordinal()),
      'Model should be blank.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetModel() {
    // Given PowerTech license key data
    String modelNumber = '41A';
    LkgRequestBuilderPowerTechTest.keyData.ModelNumber = modelNumber;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then model should be set
    System.Assert.areEqual(
      modelNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ModelNumber.ordinal()),
      'Model should be set.'
    );
  }

  //#endregion

  //#region feature code

  @isTest
  static void buildRequestNoHardware_ShouldDefaultFeatureCode() {
    // Given PowerTech license key data with no hardware
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then feature code should be blank
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.FeatureCode.ordinal()),
      'Feature code should be blank.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetFeatureCode() {
    // Given PowerTech license key data
    string featureCode = 'EP12';
    LkgRequestBuilderPowerTechTest.keyData.FeatureCode = featureCode;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then feature code should be set
    System.Assert.areEqual(
      featureCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.FeatureCode.ordinal()),
      'Feature code should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetPartitionNumber() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then partition number should be set
    System.Assert.areEqual(
      lparNumberDefault,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.LparNumber.ordinal()),
      'LPAR number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetPartitionEndNumber() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then partition end number should be set
    System.Assert.areEqual(
      lparNumberDefault,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.EndLparNumber.ordinal()),
      'LPAR end number should be set.'
    );
  }

  //#region user count

  @isTest
  static void buildRequest_ShouldSetUserCount() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then user count should be set
    System.Assert.areEqual(
      userCount.format(),
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.UserCount.ordinal()),
      'User count should be set.'
    );
  }

  @isTest
  static void buildRequestNoUserCount_ShouldDefaultUserCount() {
    // Given PowerTech license key data with no user count
    LkgRequestBuilderPowerTechTest.keyData.NumberOfUsers = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then partition end number should be set
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.UserCount.ordinal()),
      'User count should default.'
    );
  }

  //#endregion

  //#region number of processors

  @isTest
  static void buildRequest_ShouldSetNumberOfProcessors() {
    // Given PowerTech license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then number of processors should be set
    System.Assert.areEqual(
      numberOfProcessors.format(),
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderPowerTech.PowerTechParameters.NumberOfProcessors.ordinal()
      ),
      'Number of processors should be set.'
    );
  }

  @isTest
  static void buildRequestNoNumberOfProcessors_ShouldSetNumberOfProcessors() {
    // Given PowerTech license key data with no number of processors
    LkgRequestBuilderPowerTechTest.keyData.NumberOfProcessors = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then number of processors should be defaulted
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderPowerTech.PowerTechParameters.NumberOfProcessors.ordinal()
      ),
      'Number of processors should be defaulted.'
    );
  }

  //#endregion

  //#region processor type

  @isTest
  static void buildRequestNoProcessorType_ShouldDefaultProcessorType() {
    // Given PowerTech license key data with no processor type
    LkgRequestBuilderPowerTechTest.keyData.ProcessorType = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then processor type should be defaulted
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ProcessorType.ordinal()),
      'Processor type should be defaulted.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetProcessorTypeOne() {
    // Given PowerTech license key data
    String processorType = '1';
    LkgRequestBuilderPowerTechTest.keyData.ProcessorType = processorType;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then processor type should be set
    System.Assert.areEqual(
      processorType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ProcessorType.ordinal()),
      'Processor type should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetProcessorTypeFour() {
    // Given PowerTech license key data
    String processorType = '4';
    LkgRequestBuilderPowerTechTest.keyData.ProcessorType = processorType;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then processor type should be set
    System.Assert.areEqual(
      processorType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ProcessorType.ordinal()),
      'Processor type should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetProcessorTypeFive() {
    // Given PowerTech license key data
    String processorType = '5';
    LkgRequestBuilderPowerTechTest.keyData.ProcessorType = processorType;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then processor type should be set
    System.Assert.areEqual(
      processorType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.ProcessorType.ordinal()),
      'Processor type should be set.'
    );
  }

  //#endregion

  //#region iasp group

  @isTest
  static void buildRequestNoIaspGroup_ShouldSetIaspGroup() {
    // Given PowerTech license key data with no iaspGroup
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then iasp group should be defaulted
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.IAspGroup.ordinal()),
      'iasp group should be defaulted.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetIaspGroup() {
    // Given PowerTech license key data
    String iaspGroup = 'IASPDIVAL';
    LkgRequestBuilderPowerTechTest.keyData.IAspGroup = iaspGroup;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderPowerTechTest.builder.buildRequest(
      LkgRequestBuilderPowerTechTest.keyData
    );
    Test.stopTest();

    // Then check type should be set
    System.Assert.areEqual(
      iaspGroup,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderPowerTech.PowerTechParameters.IAspGroup.ordinal()),
      'Iasp group should be set.'
    );
  }

  //#endregion
}