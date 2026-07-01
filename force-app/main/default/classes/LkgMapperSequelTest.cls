@isTest
public with sharing class LkgMapperSequelTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperSequel lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'sequel';
    testPayload.productData.name = 'sequel_Product';
    testPayload.productData.identifierName = 'sequel_Product';
    testPayload.productData.productCode = '915';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'sequel_Product_Release' => '10',
      'sequel_Product_Modification' => '15',
      'sequel_Serial_Number' => 'SN123456',
      'sequel_Model_Number' => 'Model1',
      'sequel_Feature_Code' => 'FT1234',
      'sequel_LPAR_Num' => '12345',
      'sequel_End_LPAR_Num' => '99999',
      'sequel_Number_of_Processors' => '4',
      'sequel_Product_Number_of_Users' => '10',
      'sequel_Processor_Type' => 'TypeA',
      'sequel_iAsp_Group' => 'GroupA',
      'sequel_LPAR_Name' => 'LPAR1',
      'sequel_Product_Version_Range' => '{"minVersion":10,"minModification":7,"maxVersion":10,"maxModification":31,"isPermTerm":true}'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperSequel();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped SequelKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('10', result.release, 'release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('15', result.Modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetSerialNumber() {
    // Given a UI payload with Serial Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Serial Number should be set
    System.assertEquals('SN123456', result.LParSerialNumber, 'LParSerialNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfProcessors() {
    // Given a UI payload with Number of Processors
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Processors should be set
    System.assertEquals(4, result.NumberOfProcessors, 'NumberOfProcessors should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetAllAdditionalFields() {
    // Given a UI payload with all additional fields
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequel.SequelKeyData result = (LkgRequestBuilderSequel.SequelKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // All additional fields should be correctly mapped
    System.assertEquals('Model1', result.ModelNumber, 'ModelNumber should match');
    System.assertEquals('FT1234', result.FeatureCode, 'FeatureCode should match');
    System.assertEquals('12345', result.LParNumber, 'LParNumber should match');
    System.assertEquals('99999', result.LParEnd, 'LParEnd should match');
    System.assertEquals('TypeA', result.ProcessorType, 'ProcessorType should match');
    System.assertEquals('GroupA', result.IAspGroup, 'IAspGroup should match');
    System.assertEquals('LPAR1', result.LParName, 'LParName should match');
    System.assertNotEquals(null, result.PermTermVersionRange, 'PermTermVersionRange should not be null');
  }
}