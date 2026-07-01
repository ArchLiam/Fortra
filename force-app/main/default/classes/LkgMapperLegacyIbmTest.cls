@isTest
public with sharing class LkgMapperLegacyIbmTest {
  private static LkgMapperLegacyIbm lkgMapper;
  private static LkgMapperBase.UiPayload testPayload;
  private static String payloadJson;

  static {
    lkgMapper = new LkgMapperLegacyIbm();
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'legacyibm';
    testPayload.productData.name = 'Legacy IBM Product';
    testPayload.productData.identifierName = 'legacyibm';
    testPayload.productData.productCode = 'AS';
    testPayload.productData.isSupportProduct = true;
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'legacyibm_Processor_Group' => 'Power',
      'legacyibm_Usage_Limit' => '1000',
      'legacyibm_Model_Number' => 'ModelX',
      'legacyibm_Feature_Code' => 'FC1234',
      'legacyibm_Release' => '6',
      'legacyibm_Modification' => '11'
    };
    payloadJson = JSON.serialize(testPayload);
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped LegacyIbmKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetProcessorGroup() {
    // Given a UI payload with Processor Group
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Processor Group should be set
    System.assertEquals('Power', result.ProcessorGroup, 'ProcessorGroup should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetUsageLimit() {
    // Given a UI payload with Usage Limit
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Usage Limit should be set
    System.assertEquals(1000, result.usageLimit, 'UsageLimit should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModelNumber() {
    // Given a UI payload with Model Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Model Number should be set
    System.assertEquals('ModelX', result.model, 'ModelNumber should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetFeatureCode() {
    // Given a UI payload with Feature Code
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Feature Code should be set
    System.assertEquals('FC1234', result.featureCode, 'FeatureCode should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetIsSupportProduct() {
    // Given a UI payload with IsSupportProduct
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then IsSupportProduct should be set
    System.assertEquals(true, result.supportKey, 'IsSupportProduct should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload for a legacy IBM product
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Release field should be set to '6'
    System.assertEquals('6', result.Release, 'Release should be set to "6" for legacy IBM products');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Modification field should be set to '11'
    System.assertEquals('11', result.Modification, 'Modification should be set to "11" for legacy IBM products');
  }

  @isTest
  static void mapPayLoadToKeyDataMS_shouldSetRelease() {
    // Given a UI payload for MS product
    testPayload.productData.productCode = 'MS';
    testPayload.attributes.put('legacyibm_Release', '7');
    payloadJson = JSON.serialize(testPayload);

    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Release field should be set to '7'
    System.assertEquals('7', result.Release, 'Release should be set to "7" for MS products');
  }

  @isTest
  static void mapPayLoadToKeyDataMS_shouldSetModification() {
    // Given a UI payload for MS product
    testPayload.productData.productCode = 'MS';
    testPayload.attributes.put('legacyibm_Modification', '00');
    payloadJson = JSON.serialize(testPayload);

    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Modification field should be set to '00'
    System.assertEquals('00', result.Modification, 'Modification should be set to "00" for MS products');
  }

  @isTest
  static void mapPayLoadToKeyDataS1_shouldSetRelease() {
    // Given a UI payload for S1 product
    testPayload.productData.productCode = 'S1';
    testPayload.attributes.put('legacyibm_Release', '3');
    payloadJson = JSON.serialize(testPayload);

    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Release field should be set to '3'
    System.assertEquals('3', result.Release, 'Release should be set to "3" for S1 products');
  }

  @isTest
  static void mapPayLoadToKeyDataS1_shouldSetCorrectModification() {
    // Given a UI payload for S1 product
    testPayload.productData.productCode = 'S1';
    testPayload.attributes.put('legacyibm_Modification', '10');
    payloadJson = JSON.serialize(testPayload);

    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderLegacyIbm.LegacyIbmKeyData result = (LkgRequestBuilderLegacyIbm.LegacyIbmKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Modification field should be set to '10'
    System.assertEquals('10', result.Modification, 'Modification should be set to "10" for S1 products');
  }
}