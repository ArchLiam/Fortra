@isTest
public with sharing class LkgRequestBuilderSequelWebTest {
  private static LkgRequestBuilderSequelWeb.SequelWebKeyData testKeyData;
  private static LkgRequestBuilderSequelWeb requestBuilder;

  static {
    testKeyData = new LkgRequestBuilderSequelWeb.SequelWebKeyData();
    testKeyData.ProductCode = '920';
    testKeyData.KeyType = 'Specific_Temporary';
    testKeyData.ExpirationDate = Date.newInstance(2025, 12, 31);
    testKeyData.Release = '10';
    testKeyData.Modification = '30';
    testKeyData.HardwareId = 'HW123456';
    testKeyData.NumberOfViewers = 50;
    testKeyData.NumberOfDesigners = 10;
    testKeyData.Silo = 'sequel';

    requestBuilder = new LkgRequestBuilderSequelWeb();
  }

  @isTest
  static void getDynamicParameters_shouldNotReturnNull() {
    // Given a SequelWebKeyData
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Dynamic parameters map should not be null');
  }

  @isTest
  static void getDynamicParameters_shouldSetProductCode() {
    // Given a SequelWebKeyData with Product Code
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Product Code should be set
    System.assertEquals(
      '920',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.ProductCode.ordinal()),
      'ProductCode should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetVersion() {
    // Given a SequelWebKeyData with Release and Modification
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Version should be formatted as Release.Modification
    System.assertEquals(
      '10.30',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.Version.ordinal()),
      'Version should be formatted as Release.Modification'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetVersionWithDefaultModification() {
    // Given a SequelWebKeyData with null Modification
    testKeyData.Modification = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Version should use default modification 00
    System.assertEquals(
      '10.00',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.Version.ordinal()),
      'Version should use default modification 00'
    );
  }

  @isTest
  static void getDynamicParameters_shouldReturnEmptyVersionWhenReleaseIsNull() {
    // Given a SequelWebKeyData with null Release
    testKeyData.Release = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Version should be empty when Release is null
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.Version.ordinal()),
      'Version should be empty when Release is null'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetHardwareId() {
    // Given a SequelWebKeyData with Hardware ID
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Hardware ID should be set
    System.assertEquals(
      'HW123456',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.HardwareId.ordinal()),
      'HardwareId should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldDefaultHardwareIdToEmpty() {
    // Given a SequelWebKeyData with null Hardware ID
    testKeyData.HardwareId = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Hardware ID should default to empty string
    System.assertEquals(
      '0000000000',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.HardwareId.ordinal()),
      'HardwareId should default to 0000000000'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetTierPoints() {
    // Given a SequelWebKeyData with viewers and designers
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Tier points should be formatted as S1U{viewers}D{designers}W1
    System.assertEquals(
      'S1U50D10W1',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.TierPoints.ordinal()),
      'TierPoints should be formatted correctly'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetTierPointsWithZeroValues() {
    // Given a SequelWebKeyData with zero viewers and designers
    testKeyData.NumberOfViewers = 0;
    testKeyData.NumberOfDesigners = 0;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Tier points should include zero values
    System.assertEquals(
      'S1U0D0W1',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.TierPoints.ordinal()),
      'TierPoints should include zero values'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLicenseKeyTypeGeneric() {
    // Given a SequelWebKeyData with Generic KeyType
    testKeyData.KeyType = 'Generic';

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // License Key Type should be T for Generic
    System.assertEquals(
      'T',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be T for Generic'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLicenseKeyTypePermanent() {
    // Given a SequelWebKeyData with Permanent KeyType
    testKeyData.KeyType = 'Permanent';

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // License Key Type should be P for Permanent
    System.assertEquals(
      'P',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be P for Permanent'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLicenseKeyTypeSpecificTemporary() {
    // Given a SequelWebKeyData with Specific_Temporary KeyType
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // License Key Type should be T for Specific_Temporary
    System.assertEquals(
      'T',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be T for Specific_Temporary'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetExpirationDate() {
    // Given a SequelWebKeyData with Expiration Date
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Expiration Date should be formatted as yyyyMMdd
    System.assertEquals(
      '20251231',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.ExpirationDate.ordinal()),
      'ExpirationDate should be formatted as yyyyMMdd'
    );
  }

  @isTest
  static void getDynamicParameters_shouldReturnEmptyExpirationDateWhenNull() {
    // Given a SequelWebKeyData with null Expiration Date
    testKeyData.ExpirationDate = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Expiration Date should be empty when null
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.ExpirationDate.ordinal()),
      'ExpirationDate should be empty when null'
    );
  }

  @isTest
  static void getDynamicParameters_shouldHandleNullValues() {
    // Given a SequelWebKeyData with null values
    LkgRequestBuilderSequelWeb.SequelWebKeyData nullKeyData = new LkgRequestBuilderSequelWeb.SequelWebKeyData();
    nullKeyData.ProductCode = '920';
    nullKeyData.KeyType = 'Generic';

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(nullKeyData);
    Test.stopTest();

    // Default values should be set for null fields
    System.assertEquals(
      '0000000000',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.HardwareId.ordinal()),
      'HardwareId should default to 0000000000'
    );
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequelWeb.SequelWebParameters.Version.ordinal()),
      'Version should be empty when Release is null'
    );
  }

  @isTest
  static void buildRequest_shouldSetSilo() {
    // Given a SequelWebKeyData
    // When buildRequest is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest result = requestBuilder.buildRequest(testKeyData);
    Test.stopTest();

    // Silo should be set
    System.assertEquals('sequel', result.silo, 'Silo should match');
  }

  @isTest
  static void buildRequest_shouldSetAllDynamicParameters() {
    // Given a SequelWebKeyData
    // When buildRequest is called
    Test.startTest();
    LkgProcessor.LicenseKeyRequest result = requestBuilder.buildRequest(testKeyData);
    Test.stopTest();

    // All dynamic parameters should be set
    System.assertNotEquals(null, result.dynamicParameters, 'Dynamic parameters should not be null');
    System.assertEquals(6, result.dynamicParameters.size(), 'Should have 6 dynamic parameters');
  }
}