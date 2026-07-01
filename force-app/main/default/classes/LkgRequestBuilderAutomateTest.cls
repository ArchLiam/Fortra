@isTest
public class LkgRequestBuilderAutomateTest {
  private static LkgRequestBuilderAutomate.AutomateKeyData keyData;
  private static LkgRequestBuilderAutomate builder;
  static final String silo = 'automate';
  static final String release = '24';
  static final String hardwareId = 'ABC123';
  static final String points = 'K128L256';
  static final String licenseKeyType = 'Generic';
  static final DateTime expirationDate = Date.today().addDays(30);
  static {
    LkgRequestBuilderAutomateTest.keyData = new LkgRequestBuilderAutomate.AutomateKeyData();
    LkgRequestBuilderAutomateTest.keyData.Silo = silo;
    LkgRequestBuilderAutomateTest.keyData.release = release;
    LkgRequestBuilderAutomateTest.keyData.HardwareId = hardwareId;
    LkgRequestBuilderAutomateTest.keyData.points = points;
    LkgRequestBuilderAutomateTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderAutomateTest.keyData.KeyType = licenseKeyType;

    LkgRequestBuilderAutomateTest.builder = new LkgRequestBuilderAutomate();
  }

  @isTest
  static void buildRequest_ShouldSetSilo() {
    // Given Automate license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then silo should be set on request
    System.assertEquals(LkgRequestBuilderAutomateTest.silo, licenseKeyRequest.silo, 'Silo should be set.');
  }

  @isTest
  static void buildRequest_ShouldSetProductCode() {
    // Given Automate license key data
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then product code should be set on request
    System.assertEquals(
      LkgRequestBuilderAutomateTest.keyData.ProductCode,
      licenseKeyRequest.productCode,
      'Product code should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetVersion() {
    // Given Automate license key data with release
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then version should be set on request
    String expectedVersion = release + '.0';
    System.assertEquals(
      expectedVersion,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.Version.ordinal()),
      'Version should be set based on release and modification.'
    );
  }

  @isTest
  static void buildRequestNoRelease_ShouldLeaveVersionBlank() {
    // Given Automate license key data without release
    LkgRequestBuilderAutomateTest.keyData.release = null;

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then version should be blank
    System.assertEquals(
      '',
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.Version.ordinal()),
      'Version should be blank when release is not provided.'
    );
  }

  @isTest
  static void buildRequestReleaseAndModification_ShouldSetVersion() {
    // Given Automate license key data with release and modification
    LkgRequestBuilderAutomateTest.keyData.modification = '2';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then version should be set based on release and modification
    String expectedVersion = release + '.2';
    System.assertEquals(
      expectedVersion,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.Version.ordinal()),
      'Version should be set based on release and modification.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetHardwareId() {
    // Given Automate license key data with HardwareId
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then HardwareId should be set on request
    System.assertEquals(
      LkgRequestBuilderAutomateTest.keyData.HardwareId,
      licenseKeyRequest.hardwareId,
      'HardwareId should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetPoints() {
    // Given Automate license key data with Points
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then Points should be set on request
    System.assertEquals(
      LkgRequestBuilderAutomateTest.keyData.points,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.Points.ordinal()),
      'Points should be set.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetLicenseKeyType() {
    // Given Automate license key data with LicenseKeyType
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then LicenseKeyType should be set on request
    String expectedLicenseKeyType = 'T'; // 'Generic' maps to 'T'
    System.assertEquals(
      expectedLicenseKeyType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be set based on key type.'
    );
  }

  @isTest
  static void buildRequestPermanent_ShouldSetLicenseKeyType() {
    // Given Automate license key data with KeyType 'Permanent'
    LkgRequestBuilderAutomateTest.keyData.KeyType = 'Permanent';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then LicenseKeyType should be set to 'P' for 'Permanent'
    String expectedLicenseKeyType = 'P';
    System.assertEquals(
      expectedLicenseKeyType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be set to P for Permanent key type.'
    );
  }

  @isTest
  static void buildRequestSpecificTemporary_ShouldSetLicenseKeyType() {
    // Given Automate license key data with KeyType 'Specific_Temporary'
    LkgRequestBuilderAutomateTest.keyData.KeyType = 'Specific_Temporary';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then LicenseKeyType should be set to 'T' for 'Specific_Temporary'
    String expectedLicenseKeyType = 'T';
    System.assertEquals(
      expectedLicenseKeyType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be set to T for Specific_Temporary key type.'
    );
  }

  @isTest
  static void buildRequestAutomateSubscription_ShouldSetLicenseKeyType() {
    // Given Automate license key data with KeyType 'Subscription'
    LkgRequestBuilderAutomateTest.keyData.KeyType = 'Subscription';

    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then LicenseKeyType should be set to 'T' for 'Automate_Subscription'
    String expectedLicenseKeyType = 'E';
    System.assertEquals(
      expectedLicenseKeyType,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be set to T for Subscription key type.'
    );
  }

  @isTest
  static void buildRequest_ShouldSetExpirationDate() {
    // Given Automate license key data with ExpirationDate
    // When the request builder is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = LkgRequestBuilderAutomateTest.builder.buildRequest(
      LkgRequestBuilderAutomateTest.keyData
    );
    Test.stopTest();

    // Then ExpirationDate should be set on request in 'yyyyMMdd' format
    String expectedExpirationDate = expirationDate.format('yyyyMMdd');
    System.assertEquals(
      expectedExpirationDate,
      licenseKeyRequest.dynamicParameters.get(LkgRequestBuilderAutomate.AutomateParameters.ExpirationDate.ordinal()),
      'ExpirationDate should be set in yyyyMMdd format.'
    );
  }
}