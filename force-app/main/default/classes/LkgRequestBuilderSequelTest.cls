@isTest
public with sharing class LkgRequestBuilderSequelTest {
  private static LkgRequestBuilderSequel.SequelKeyData testKeyData;
  private static LkgRequestBuilderSequel requestBuilder;

  static {
    testKeyData = new LkgRequestBuilderSequel.SequelKeyData();
    testKeyData.ProductCode = '915';
    testKeyData.KeyType = 'Specific_Temporary';
    testKeyData.ExpirationDate = Date.newInstance(2025, 12, 31);
    testKeyData.release = '10';
    testKeyData.Modification = '30';
    testKeyData.LParSerialNumber = 'SN123456';
    testKeyData.ModelNumber = 'Model1';
    testKeyData.FeatureCode = 'FT1234';
    testKeyData.LParNumber = '12345';
    testKeyData.LParEnd = '99999';
    testKeyData.NumberOfUsers = 100;
    testKeyData.NumberOfProcessors = 4;
    testKeyData.ProcessorType = 'TypeA';
    testKeyData.IAspGroup = 'GroupA';
    testKeyData.Silo = 'sequel';

    requestBuilder = new LkgRequestBuilderSequel();
  }

  @isTest
  static void getDynamicParameters_shouldNotReturnNull() {
    // Given a SequelKeyData
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Dynamic parameters map should not be null');
  }

  @isTest
  static void getDynamicParameters_shouldSetProductCode() {
    // Given a SequelKeyData with Product Code
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Product Code should be set
    System.assertEquals(
      '915',
      result.get(LkgRequestBuilderSequel.SequelParameters.ProductCode.ordinal()),
      'ProductCode should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetVersion() {
    // Given a SequelKeyData with Release and Modification
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Version should be formatted as R10M30
    System.assertEquals(
      'R10M30',
      result.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'Version should be formatted correctly'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLicenseKeyType() {
    // Given a SequelKeyData with KeyType
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // License Key Type should be set to '5' for Specific_Temporary
    System.assertEquals(
      '5',
      result.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be 5 for Specific_Temporary'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetExpirationDate() {
    // Given a SequelKeyData with Expiration Date
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Expiration Date should be formatted as yyyyMMdd
    System.assertEquals(
      '20251231',
      result.get(LkgRequestBuilderSequel.SequelParameters.ExpirationDate.ordinal()),
      'ExpirationDate should be formatted correctly'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetSerialNumber() {
    // Given a SequelKeyData with Serial Number
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Serial Number should be set
    System.assertEquals(
      'SN123456',
      result.get(LkgRequestBuilderSequel.SequelParameters.LParSerialNumber.ordinal()),
      'SerialNumber should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetModelNumber() {
    // Given a SequelKeyData with Model Number
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Model Number should be set
    System.assertEquals(
      'Model1',
      result.get(LkgRequestBuilderSequel.SequelParameters.ModelNumber.ordinal()),
      'ModelNumber should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetFeatureCode() {
    // Given a SequelKeyData with Feature Code
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Feature Code should be set
    System.assertEquals(
      'FT1234',
      result.get(LkgRequestBuilderSequel.SequelParameters.FeatureCode.ordinal()),
      'FeatureCode should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLParNumber() {
    // Given a SequelKeyData with LPar Number
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // LPar Number should be set
    System.assertEquals(
      '12345',
      result.get(LkgRequestBuilderSequel.SequelParameters.LParNumber.ordinal()),
      'LParNumber should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetLParEnd() {
    // Given a SequelKeyData with LPar End
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // LPar End should be set
    System.assertEquals(
      '99999',
      result.get(LkgRequestBuilderSequel.SequelParameters.LParEnd.ordinal()),
      'LParEnd should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetNumberOfUsers() {
    // Given a SequelKeyData with Number of Users
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Number of Users should be set
    System.assertEquals(
      '100',
      result.get(LkgRequestBuilderSequel.SequelParameters.NumberOfUsers.ordinal()),
      'NumberOfUsers should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetNumberOfProcessors() {
    // Given a SequelKeyData with Number of Processors
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Number of Processors should be set
    System.assertEquals(
      '4',
      result.get(LkgRequestBuilderSequel.SequelParameters.NumberOfProcessors.ordinal()),
      'NumberOfProcessors should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetProcessorType() {
    // Given a SequelKeyData with Processor Type
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // Processor Type should be set
    System.assertEquals(
      'TypeA',
      result.get(LkgRequestBuilderSequel.SequelParameters.ProcessorType.ordinal()),
      'ProcessorType should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldSetIAspGroup() {
    // Given a SequelKeyData with IAsp Group
    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(testKeyData);
    Test.stopTest();

    // IAsp Group should be set
    System.assertEquals(
      'GroupA',
      result.get(LkgRequestBuilderSequel.SequelParameters.IAspGroup.ordinal()),
      'IAspGroup should match'
    );
  }

  @isTest
  static void getDynamicParameters_shouldConvertTermToPermWhenInRange() {
    // Given a SequelKeyData with Specific_Temporary KeyType and version in range
    LkgRequestBuilderSequel.SequelKeyData termKeyData = new LkgRequestBuilderSequel.SequelKeyData();
    termKeyData.ProductCode = '915';
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '5';
    termKeyData.Modification = '20';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(termKeyData);
    Test.stopTest();

    // License Key Type should be '0' (Permanent) because version 5.20 is in range 4.07-10.12
    System.assertEquals(
      '0',
      result.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be 0 (Permanent) when version is in range'
    );
  }

  @isTest
  static void getDynamicParameters_shouldKeepTermWhenOutOfRange() {
    // Given a SequelKeyData with Specific_Temporary KeyType and version out of range
    LkgRequestBuilderSequel.SequelKeyData termKeyData = new LkgRequestBuilderSequel.SequelKeyData();
    termKeyData.ProductCode = '915';
    termKeyData.KeyType = 'Specific_Temporary';
    termKeyData.release = '11';
    termKeyData.Modification = '5';
    termKeyData.PermTermVersionRange = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(termKeyData);
    Test.stopTest();

    // License Key Type should be '5' (Term) because version 11.05 is out of range 4.07-10.12
    System.assertEquals(
      '5',
      result.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be 5 (Term) when version is out of range'
    );
  }

  @isTest
  static void getDynamicParameters_shouldHandleNullRelease() {
    // Given a SequelKeyData with null Release
    LkgRequestBuilderSequel.SequelKeyData nullReleaseData = new LkgRequestBuilderSequel.SequelKeyData();
    nullReleaseData.ProductCode = '100';
    nullReleaseData.KeyType = 'Generic';
    nullReleaseData.release = null;

    // When GetDynamicParameters is called
    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(nullReleaseData);
    Test.stopTest();

    // Version should be empty string when Release is null
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'Version should be empty when Release is null'
    );
  }

  @isTest
  static void getDynamicParameters_shouldHandleQRWriterModificationUpgrade() {
    // Test 1: QRWriter with modification < 25 should be upgraded to M25
    LkgRequestBuilderSequel.SequelKeyData qrWriterLow = new LkgRequestBuilderSequel.SequelKeyData();
    qrWriterLow.ProductCode = '915';
    qrWriterLow.release = '10';
    qrWriterLow.Modification = '20';
    qrWriterLow.lkgProductIdentifierName = 'SQ915_QRWriter';
    qrWriterLow.KeyType = 'Generic';

    // Test 2: QRWriter with modification >= 25 should not be upgraded
    LkgRequestBuilderSequel.SequelKeyData qrWriterHigh = new LkgRequestBuilderSequel.SequelKeyData();
    qrWriterHigh.ProductCode = '915';
    qrWriterHigh.release = '10';
    qrWriterHigh.Modification = '30';
    qrWriterHigh.lkgProductIdentifierName = 'SQ915_QRWriter';
    qrWriterHigh.KeyType = 'Generic';

    // Test 3: Non-QRWriter should not be upgraded
    LkgRequestBuilderSequel.SequelKeyData nonQRWriter = new LkgRequestBuilderSequel.SequelKeyData();
    nonQRWriter.ProductCode = '915';
    nonQRWriter.release = '10';
    nonQRWriter.Modification = '20';
    nonQRWriter.lkgProductIdentifierName = 'SQ915_Other';
    nonQRWriter.KeyType = 'Generic';

    Test.startTest();
    Map<Integer, Object> result1 = requestBuilder.GetDynamicParameters(qrWriterLow);
    Map<Integer, Object> result2 = requestBuilder.GetDynamicParameters(qrWriterHigh);
    Map<Integer, Object> result3 = requestBuilder.GetDynamicParameters(nonQRWriter);
    Test.stopTest();

    System.assertEquals(
      'R10M25',
      result1.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'QRWriter < M25 should upgrade'
    );
    System.assertEquals(
      'R10M30',
      result2.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'QRWriter >= M25 should not upgrade'
    );
    System.assertEquals(
      'R10M20',
      result3.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'Non-QRWriter should not upgrade'
    );
  }

  @isTest
  static void getDynamicParameters_shouldHandleNullFieldsWithDefaults() {
    // Given a SequelKeyData with various null fields
    LkgRequestBuilderSequel.SequelKeyData nullFieldsData = new LkgRequestBuilderSequel.SequelKeyData();
    nullFieldsData.ProductCode = '100';
    nullFieldsData.KeyType = 'Permanent';
    nullFieldsData.release = '5';
    nullFieldsData.Modification = null; // Should default to '00'
    nullFieldsData.SerialNumber = null;
    nullFieldsData.ProcessorType = null; // Should default to '1'

    Test.startTest();
    Map<Integer, Object> result = requestBuilder.GetDynamicParameters(nullFieldsData);
    Test.stopTest();

    System.assertEquals(
      'R5M00',
      result.get(LkgRequestBuilderSequel.SequelParameters.Version.ordinal()),
      'Version should default to M00'
    );
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequel.SequelParameters.LParSerialNumber.ordinal()),
      'SerialNumber should default to empty'
    );
    System.assertEquals(
      '',
      result.get(LkgRequestBuilderSequel.SequelParameters.ProcessorType.ordinal()),
      'ProcessorType should default to empty string'
    );
    System.assertEquals(
      '0',
      result.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'LicenseKeyType should be 0 for Permanent'
    );
  }

  @isTest
  static void getDynamicParameters_shouldMapAllKeyTypes() {
    // Test Permanent, Generic, and Specific_Temporary key types
    LkgRequestBuilderSequel.SequelKeyData permData = new LkgRequestBuilderSequel.SequelKeyData();
    permData.ProductCode = '100';
    permData.KeyType = 'Permanent';
    permData.release = '5';

    LkgRequestBuilderSequel.SequelKeyData genericData = new LkgRequestBuilderSequel.SequelKeyData();
    genericData.ProductCode = '100';
    genericData.KeyType = 'Generic';
    genericData.release = '5';

    Test.startTest();
    Map<Integer, Object> permResult = requestBuilder.GetDynamicParameters(permData);
    Map<Integer, Object> genericResult = requestBuilder.GetDynamicParameters(genericData);
    Test.stopTest();

    System.assertEquals(
      '0',
      permResult.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'Permanent should be 0'
    );
    System.assertEquals(
      '1',
      genericResult.get(LkgRequestBuilderSequel.SequelParameters.LicenseKeyType.ordinal()),
      'Generic should be 1'
    );
  }
}