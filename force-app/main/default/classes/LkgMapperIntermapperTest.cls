@isTest
public with sharing class LkgMapperIntermapperTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperIntermapper lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'intermapper';
    testPayload.productData.name = 'Intermapper_Product';
    testPayload.productData.identifierName = 'Intermapper_Product';
    testPayload.productData.productCode = '042';
    testPayload.keyType = 'Permanent';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'intermapper_Hardware_Id' => 'HW98765',
      'intermapper_Modification' => '03',
      'Intermapper_Product_Devices' => '500',
      'Intermapper_Product_Flows' => '100',
      'Intermapper_Product_Remotes' => '50'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperIntermapper();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given an Intermapper UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped IntermapperKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given an Intermapper UI payload with Hardware Id
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then HardwareId should be set
    System.assertEquals('HW98765', result.HardwareId, 'HardwareId should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given an Intermapper UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Modification should be set
    System.assertEquals('03', result.modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetServerDevices() {
    // Given an Intermapper UI payload with Devices
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then ServerDevices should be set
    System.assertEquals(500, result.ServerDevices, 'ServerDevices should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetServerFlows() {
    // Given an Intermapper UI payload with Flows
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then ServerFlows should be set
    System.assertEquals(100, result.ServerFlows, 'ServerFlows should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRemotes() {
    // Given an Intermapper UI payload with Remotes
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderIntermapper.IntermapperKeyData result = (LkgRequestBuilderIntermapper.IntermapperKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Remotes should be set
    System.assertEquals(50, result.Remotes, 'Remotes should match');
  }
}