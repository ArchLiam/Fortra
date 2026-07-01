@isTest
public with sharing class LkgMapperTQSurveyorTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperTQSurveyor lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'tqjava';
    testPayload.productData.name = 'TQSurveyor_Product';
    testPayload.productData.identifierName = 'TQSurveyor_Product';
    testPayload.productData.productCode = 'surveyor';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'tqjava_Company_Name' => 'Test Company Inc.',
      'tqjava_Server_Name' => 'TestServer01',
      'TQSurveyor_Product_Number_of_Licenses' => '50'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperTQSurveyor();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData result = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped TQSurveyorKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetAccountName() {
    // Given a UI payload with Account Name
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData result = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Account Name should be set
    System.assertEquals('Test Company Inc.', result.accountName, 'accountName should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModelNumber() {
    // Given a UI payload with Model Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData result = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Model Number should be set
    System.assertEquals('TestServer01', result.modelNumber, 'modelNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfLicenses() {
    // Given a UI payload with Number of Licenses
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData result = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Licenses should be set
    System.assertEquals(50, result.numberOfLicenses, 'numberOfLicenses should match');
  }
}