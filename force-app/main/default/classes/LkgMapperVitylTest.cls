@isTest
public with sharing class LkgMapperVitylTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperVityl lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'vityl';
    testPayload.productData.name = 'Vityl_Product';
    testPayload.productData.identifierName = 'Vityl_Product';
    testPayload.productData.productCode = 'VCI';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'vityl_Hardware_Id' => 'HW12345',
      'vityl_Modification' => '01',
      'vityl_Release' => '02',
      'Vityl_Product_Tier' => 'Gold',
      'Vityl_Product_Count' => '100',
      'Vityl_Product_Flag' => 'A'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperVityl();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped VitylKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware Id
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Hardware Id should be set
    System.assertEquals('HW12345', result.HardwareId, 'HardwareId should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('01', result.modification, 'modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('02', result.release, 'release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetTier() {
    // Given a UI payload with Tier
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Tier should be set
    System.assertEquals('Gold', result.Tier, 'Tier should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetCount() {
    // Given a UI payload with Count
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Count should be set
    System.assertEquals(100, result.Count, 'Count should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetFlag() {
    // Given a UI payload with Flag
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderVityl.VitylKeyData result = (LkgRequestBuilderVityl.VitylKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Flag should be set
    System.assertEquals('A', result.Flag, 'Flag should match');
  }
}