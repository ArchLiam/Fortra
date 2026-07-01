@isTest
private class LkgRequestBuilderSequelQueryBuilderTest {
  private static LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData keyData;
  private static LkgRequestBuilderSequelQueryBuilder builder;
  static final String productCode = '910';
  static final String silo = 'sequel';
  static final String hardwareId = 'HW123456';
  static final String release = '10';
  static final String modification = '30';
  static final DateTime expirationDate = Date.today().addDays(90);
  static final Integer numberOfConnectors = 5;
  static final Integer numberOfDesigners = 10;

  static {
    LkgRequestBuilderSequelQueryBuilderTest.keyData = new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
    LkgRequestBuilderSequelQueryBuilderTest.keyData.Silo = silo;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.ProductCode = productCode;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.Release = release;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.Modification = modification;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.HardwareId = hardwareId;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.KeyType = 'Generic';
    LkgRequestBuilderSequelQueryBuilderTest.keyData.ExpirationDate = expirationDate.date();
    LkgRequestBuilderSequelQueryBuilderTest.keyData.NumberOfConnectors = numberOfConnectors;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.NumberOfDesigners = numberOfDesigners;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.HasDataDecorations = 1;

    LkgRequestBuilderSequelQueryBuilderTest.builder = new LkgRequestBuilderSequelQueryBuilder();
  }

  @isTest
  static void getDynamicParameters_ShouldNotReturnNull() {
    // Given SequelQueryBuilder license key data
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(
      LkgRequestBuilderSequelQueryBuilderTest.keyData
    );
    Test.stopTest();

    // Then the result should not be null
    System.Assert.isNotNull(result, 'Dynamic parameters map should not be null');
  }

  @isTest
  static void getDynamicParameters_ShouldSetBasicParameters() {
    // Given SequelQueryBuilder license key data
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(
      LkgRequestBuilderSequelQueryBuilderTest.keyData
    );
    Test.stopTest();

    // Then basic parameters should be set correctly
    System.Assert.areEqual(
      productCode,
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.ProductCode.ordinal()),
      'Product code should be set.'
    );
    System.Assert.areEqual(
      release + '.' + modification,
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.Version.ordinal()),
      'Version should be formatted as Release.Modification'
    );
    System.Assert.areEqual(
      hardwareId,
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.HardwareId.ordinal()),
      'Hardware ID should be set.'
    );
  }

  @isTest
  static void getDynamicParameters_ShouldHandleNullValues() {
    // Given SequelQueryBuilder license key data with null values
    LkgRequestBuilderSequelQueryBuilderTest.keyData.Release = null;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.HardwareId = null;
    LkgRequestBuilderSequelQueryBuilderTest.keyData.ExpirationDate = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(
      LkgRequestBuilderSequelQueryBuilderTest.keyData
    );
    Test.stopTest();

    // Then null values should be handled with defaults
    System.Assert.areEqual(
      '',
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.Version.ordinal()),
      'Version should be empty when Release is null'
    );
    System.Assert.areEqual(
      '',
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.HardwareId.ordinal()),
      'Hardware ID should default to empty string'
    );
    System.Assert.areEqual(
      '',
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.ExpirationDate.ordinal()),
      'Expiration date should be empty when null'
    );
  }

  @isTest
  static void getDynamicParameters_ShouldFormatTierPoints() {
    // Given SequelQueryBuilder license key data
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(
      LkgRequestBuilderSequelQueryBuilderTest.keyData
    );
    Test.stopTest();

    // Then tier points should be formatted correctly
    String expectedTierPoints =
      'S1C' +
      numberOfConnectors +
      'U' +
      numberOfDesigners +
      'D' +
      numberOfDesigners +
      'W' +
      numberOfDesigners +
      'T1';
    System.Assert.areEqual(
      expectedTierPoints,
      result.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.TierPoints.ordinal()),
      'Tier points should be formatted correctly'
    );
  }

  @isTest
  static void getDynamicParameters_ShouldMapAllKeyTypes() {
    // Test Generic, Permanent, and Specific_Temporary key types
    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData genericData = new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
    genericData.ProductCode = productCode;
    genericData.KeyType = 'Generic';
    genericData.Release = release;

    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData permData = new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
    permData.ProductCode = productCode;
    permData.KeyType = 'Permanent';
    permData.Release = release;

    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData tempData = new LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData();
    tempData.ProductCode = productCode;
    tempData.KeyType = 'Specific_Temporary';
    tempData.Release = release;

    Test.startTest();
    Map<Integer, Object> genericResult = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(
      genericData
    );
    Map<Integer, Object> permResult = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(permData);
    Map<Integer, Object> tempResult = LkgRequestBuilderSequelQueryBuilderTest.builder.GetDynamicParameters(tempData);
    Test.stopTest();

    // Then license key types should be mapped correctly
    System.Assert.areEqual(
      'T',
      genericResult.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.LicenseKeyType.ordinal()),
      'Generic should be T'
    );
    System.Assert.areEqual(
      'P',
      permResult.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.LicenseKeyType.ordinal()),
      'Permanent should be P'
    );
    System.Assert.areEqual(
      'T',
      tempResult.get(LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderParameters.LicenseKeyType.ordinal()),
      'Specific_Temporary should be T'
    );
  }
}