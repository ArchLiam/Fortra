@isTest
private class LkgRequestBuilderRobotTest {
  private static LkgRequestBuilderRobot.RobotKeyData keyData;
  private static LkgRequestBuilderRobot builder;
  static final String silo = 'robot';
  static final String productCode = '24';
  static final String lparSerialNumber = '780BBB0';
  static final String modelNumber = '41A';
  static final String featureCode = 'EP12';
  static final String lparNumber = '99999';
  static final String lparEnd = '99999';
  static final String release = '11';
  static final String modification = '05';
  static final String version = 'R11M05';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer numberOfUsers = 50;
  static final Integer numberOfProcessors = 3;

  static {
    LkgRequestBuilderRobotTest.keyData = new LkgRequestBuilderRobot.RobotKeyData();
    keyData.Silo = silo;
    keyData.ProductCode = productCode;
    keyData.KeyType = 'Generic';
    keyData.ExpirationDate = expirationDate.date();
    keyData.LParSerialNumber = lparSerialNumber;
    keyData.ModelNumber = modelNumber;
    keyData.FeatureCode = featureCode;
    keyData.LParNumber = lparNumber;
    keyData.LParEnd = lparEnd;
    keyData.NumberOfUsers = numberOfUsers;
    keyData.NumberOfProcessors = numberOfProcessors;
    keyData.release = release;
    keyData.Modification = modification;

    LkgRequestBuilderRobotTest.builder = new LkgRequestBuilderRobot();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.Assert.areEqual(LkgRequestBuilderRobotTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      LkgRequestBuilderRobotTest.productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region version

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    System.Assert.areEqual(
      version,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.Version.ordinal()),
      'Version should be set.'
    );
  }

  @isTest
  static void buildRequestWithoutVersion_ShouldSetVersionAsNull() {
    // Given robot license key data without release and modification
    LkgRequestBuilderRobotTest.keyData.release = null;
    LkgRequestBuilderRobotTest.keyData.Modification = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then version should be empty when Release is null
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.Version.ordinal()),
      'Version should be empty when Release is null.'
    );
  }

  @isTest
  static void buildRequestWithEmptyVersion_ShouldSetVersionAsEmpty() {
    // Given robot license key data with empty release and modification
    LkgRequestBuilderRobotTest.keyData.release = '';
    LkgRequestBuilderRobotTest.keyData.Modification = '';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then version should be empty on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.Version.ordinal()),
      'Version should be empty for empty release.'
    );
  }

  //#endregion

  //#region key type

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given a generic robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetKeyType() {
    // Given a permanent robot license key data
    LkgRequestBuilderRobotTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldSetKeyType() {
    // Given a specific temporary robot license key data
    LkgRequestBuilderRobotTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      '5',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LicenseKeyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldConvertToPermWhenInRange() {
    // Given a specific temporary robot license key data with version in range
    LkgRequestBuilderRobot.RobotKeyData termKeyData = new LkgRequestBuilderRobot.RobotKeyData();
    termKeyData.ProductCode = productCode;
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '5';
    termKeyData.Modification = '20';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(termKeyData);
    Test.stopTest();

    // Then key type should be '0' (Permanent) because version 5.20 is in range 4.07-10.12
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LicenseKeyType.ordinal()),
      'Key type should be 0 (Permanent) when version is in range.'
    );
  }

  @isTest
  static void buildRequestSpecificTemp_ShouldKeepTermWhenOutOfRange() {
    // Given a specific temporary robot license key data with version out of range
    LkgRequestBuilderRobot.RobotKeyData termKeyData = new LkgRequestBuilderRobot.RobotKeyData();
    termKeyData.ProductCode = productCode;
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '11';
    termKeyData.Modification = '5';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(termKeyData);
    Test.stopTest();

    // Then key type should be '5' (Term) because version 11.05 is out of range 4.07-10.12
    System.Assert.areEqual(
      '5',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LicenseKeyType.ordinal()),
      'Key type should be 5 (Term) when version is out of range.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.ExpirationDate.ordinal()),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetSerialNumber() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then LPar serial number should be set
    System.Assert.areEqual(
      lparSerialNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.LParSerialNumber.ordinal()),
      'LPar serial number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetModelNumber() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then model number should be set
    System.Assert.areEqual(
      modelNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.ModelNumber.ordinal()),
      'Model number should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetNumberOfUsers() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then number of users should be set
    System.Assert.areEqual(
      numberOfUsers.format(),
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.NumberOfUsers.ordinal()),
      'Number of users should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetNumberOfProcessors() {
    // Given robot license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderRobotTest.builder.buildRequest(
      LkgRequestBuilderRobotTest.keyData
    );
    Test.stopTest();

    // Then number of processors should be set
    System.Assert.areEqual(
      numberOfProcessors.format(),
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderRobot.RobotParameters.NumberOfProcessors.ordinal()),
      'Number of processors should be set.'
    );
  }
}