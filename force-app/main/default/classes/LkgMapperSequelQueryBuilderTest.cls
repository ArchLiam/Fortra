@isTest
public with sharing class LkgMapperSequelQueryBuilderTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperSequelQueryBuilder lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'sequelquerybuilder';
    testPayload.productData.name = 'SequelQueryBuilder_Product';
    testPayload.productData.identifierName = 'SequelQueryBuilder_Product';
    testPayload.productData.productCode = '1000';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'sequelquerybuilder_Release' => '5',
      'sequelquerybuilder_Modification' => '10',
      'sequelquerybuilder_Number_of_Connectors' => '10',
      'sequelquerybuilder_Number_of_Designers' => '5',
      'sequelquerybuilder_Hardware_Id' => 'HW123456',
      'sequelquerybuilder_Has_Data_Decorations' => '1'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperSequelQueryBuilder();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData result = (LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped SequelQueryBuilderKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetAllFields() {
    // Given a UI payload with all fields
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData result = (LkgRequestBuilderSequelQueryBuilder.SequelQueryBuilderKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then all fields should be correctly mapped
    System.assertEquals('5', result.Release, 'Release should match');
    System.assertEquals('10', result.Modification, 'Modification should match');
    System.assertEquals(10, result.NumberOfConnectors, 'NumberOfConnectors should match');
    System.assertEquals(5, result.NumberOfDesigners, 'NumberOfDesigners should match');
    System.assertEquals('HW123456', result.HardwareId, 'HardwareId should match');
    System.assertEquals(1, result.HasDataDecorations, 'HasDataDecorations should match');
  }
}