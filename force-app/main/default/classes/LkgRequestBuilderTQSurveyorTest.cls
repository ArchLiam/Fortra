@isTest
private class LkgRequestBuilderTQSurveyorTest {
  private static LkgRequestBuilderTQSurveyor.TQSurveyorKeyData keyData;
  private static LkgRequestBuilderTQSurveyor builder;
  static final String productCode = 'surveyor';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final String accountName = 'Test Inc.';
  static final String modelNumber = 'cbp-surveyor';
  static final Integer userCount = 10;

  static {
    keyData = new LkgRequestBuilderTQSurveyor.TQSurveyorKeyData();
    keyData.ProductCode = productCode;
    keyData.KeyType = 'Generic';
    keyData.ExpirationDate = expirationDate.date();
    keyData.accountName = accountName;
    keyData.modelNumber = modelNumber;
    keyData.numberOfLicenses = userCount;

    builder = new LkgRequestBuilderTQSurveyor();
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.productCode.ordinal()),
      'Product code should be set.'
    );
  }

  //#region key type

  @isTest
  static void buildRequest_ShouldSetKeyType() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'E',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.keyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetKeyType() {
    // Given TeamQuest surveyor key data
    keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'P',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.keyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestSpecificTemporary_ShouldSetKeyType() {
    // Given TeamQuest surveyor key data
    keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be set on request
    System.Assert.areEqual(
      'E',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.keyType.ordinal()),
      'Key type should be set.'
    );
  }

  @isTest
  static void buildRequestInvalidType_ShouldDefaultKeyType() {
    // Given TeamQuest surveyor key data
    keyData.KeyType = 'badKeyType';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then key type should be defaulted on request
    System.Assert.areEqual(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.keyType.ordinal()),
      'Key type should be set.'
    );
  }

  //#endregion

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then expiration date should be set on request
    String expectedResult = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedResult,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderTQSurveyor.TQSurveyorParameters.expirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetAccountName() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then account name should be set on request
    System.Assert.areEqual(
      accountName,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.accountName.ordinal()),
      'Account name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetModelNumber() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then model number should be set on request
    System.Assert.areEqual(
      modelNumber,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderTQSurveyor.TQSurveyorParameters.modelNumber.ordinal()),
      'Model number should be set.'
    );
  }

  //#region user count

  @isTest
  static void buildRequest_ShouldSetUserCount() {
    // Given TeamQuest surveyor key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then user count should be set on request
    System.Assert.areEqual(
      userCount.toString(),
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderTQSurveyor.TQSurveyorParameters.numberOfLicenses.ordinal()
      ),
      'User count should be set.'
    );
  }

  @isTest
  static void buildRequestNoUserCount_ShouldDefaultUserCount() {
    // Given TeamQuest surveyor key data
    keyData.numberOfLicenses = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = builder.buildRequest(keyData);
    Test.stopTest();

    // Then user count should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderTQSurveyor.TQSurveyorParameters.numberOfLicenses.ordinal()
      ),
      'User count should be set.'
    );
  }

  //#endregion
}