@isTest
private class LkgRequestBuilderClearswiftTest {
  private static LkgRequestBuilderClearswift.ClearswiftKeyData keyData;
  private static LkgRequestBuilderClearswift builder;
  static final String silo = 'clearswift';
  static final String productCode = '24';
  static final String accountName = 'Test Co.';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer numberOfUsers = 10;

  static {
    LkgRequestBuilderClearswiftTest.keyData = new LkgRequestBuilderClearswift.ClearswiftKeyData();
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = productCode;
    LkgRequestBuilderClearswiftTest.keyData.KeyType = 'Permanent';
    LkgRequestBuilderClearswiftTest.keyData.accountName = accountName;
    LkgRequestBuilderClearswiftTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderClearswiftTest.keyData.NumberOfUsers = numberOfUsers;
    LkgRequestBuilderClearswiftTest.keyData.Silo = silo;

    LkgRequestBuilderClearswiftTest.builder = new LkgRequestBuilderClearswift();
  }

  //#region permanent key, product code 24

  @isTest
  static void buildRequest_ShouldSetAccountName() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then account name should be set on request
    System.Assert.areEqual(
      accountName,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.CompanyName.ordinal()),
      'Account name should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationType() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration type should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationType.ordinal()
      ),
      'Expiration type should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given Clearswift license key data for a permanent key
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    string expectedDateString = LkgRequestBuilderClearswift.expirationDefault.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedDateString,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetProductCodeInParameters() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.Assert.areEqual(
      productCode,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLanguageIndex() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then language index should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.LanguageIndex.ordinal()),
      'Language index should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetVersionIndex() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then version index should be set on request
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.VersionIndex.ordinal()),
      'Version index should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetServerCount() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then server count should be set to default (zero)
    System.Assert.areEqual(
      '0',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.ServerCount.ordinal()),
      'Server count should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetUserCount() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then user count should be set to default (zero)
    System.Assert.areEqual(
      numberOfUsers,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.UserCount.ordinal()),
      'User count should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetElements() {
    // Given Clearswift license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then elements should be set
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.Elements.ordinal()),
      'Elements should be set.'
    );
  }

  //#endregion

  //#region different key types

  @isTest
  static void buildRequestTempKey_ShouldSetExpirationType() {
    // Given Clearswift license key data and a temp key request
    LkgRequestBuilderClearswiftTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration type should be set correclty on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationType.ordinal()
      ),
      'Expiration type should be set.'
    );
  }

  @isTest
  static void buildRequestTempKey_ShouldSetExpirationDate() {
    // Given Clearswift license key data and a temp key request
    LkgRequestBuilderClearswiftTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    string expectedDate = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedDate,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  @isTest
  static void buildRequestSubscriptionKey_ShouldSetExpirationType() {
    // Given Clearswift license key data and a subscription key request
    LkgRequestBuilderClearswiftTest.keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration type should be set correclty on request
    System.Assert.areEqual(
      '1',
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationType.ordinal()
      ),
      'Expiration type should be set.'
    );
  }

  @isTest
  static void buildRequestSubscriptionKey_ShouldSetExpirationDate() {
    // Given Clearswift license key data and a subscription key request
    LkgRequestBuilderClearswiftTest.keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then expiration date should be set on request
    string expectedDate = expirationDate.format('yyyyMMdd');
    System.Assert.areEqual(
      expectedDate,
      licenseKeyRequest.dynamicParameters.get(
        LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationDate.ordinal()
      ),
      'Expiration date should be set.'
    );
  }

  //#endregion

  //#region different product codes

  @isTest
  static void buildRequestProductCode5_ShouldSetVersionIndex() {
    // Given Clearswift license key data with a product code of 5
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = '5';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then version index should be set correctly on request
    System.Assert.areEqual(
      '4',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.VersionIndex.ordinal()),
      'Version index should be set.'
    );
  }

  @isTest
  static void buildRequestProductCode11_ShouldSetVersionIndex() {
    // Given Clearswift license key data with a product code of 11
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = '11';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then version index should be set correctly on request
    System.Assert.areEqual(
      '4',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.VersionIndex.ordinal()),
      'Version index should be set.'
    );
  }

  @isTest
  static void buildRequestProductCode13_ShouldSetVersionIndex() {
    // Given Clearswift license key data with a product code of 13
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = '13';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then version index should be set correctly on request
    System.Assert.areEqual(
      '2',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.VersionIndex.ordinal()),
      'Version index should be set.'
    );
  }

  @isTest
  static void buildRequestProductCode5_ShouldSetElements() {
    // Given Clearswift license key data with a product code of 5
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = '5';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then elements should be set correctly
    System.Assert.areEqual(
      '3',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.Elements.ordinal()),
      'Elements should be set.'
    );
  }

  @isTest
  static void buildRequestProductCode11_ShouldSetElements() {
    // Given Clearswift license key data with a product code of 11
    LkgRequestBuilderClearswiftTest.keyData.ProductCode = '11';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderClearswiftTest.builder.buildRequest(
      LkgRequestBuilderClearswiftTest.keyData
    );
    Test.stopTest();

    // Then elements should be set correctly
    System.Assert.areEqual(
      '7',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderClearswift.ClearswiftParameters.Elements.ordinal()),
      'Elements should be set.'
    );
  }

  //#endregion
}