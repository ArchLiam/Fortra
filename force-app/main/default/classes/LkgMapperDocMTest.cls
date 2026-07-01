@isTest
public with sharing class LkgMapperDocMTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperDocM lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'docm';
    testPayload.productData.name = 'DocM_Product';
    testPayload.productData.identifierName = 'DocM_Product';
    testPayload.productData.productCode = 'IFM';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'docm_Hardware_Id' => '1234567890',
      'docm_Release' => '100',
      'docm_Modification' => '05',
      'DocM_Product_Number_of_Users' => '50',
      'DocM_Product_Tier' => 'S3B100'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperDocM();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped DocMKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware Id
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Hardware Id should be set
    System.assertEquals('1234567890', result.HardwareId, 'HardwareId should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('100', result.Release, 'Release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('05', result.Modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfUsers() {
    // Given a UI payload with Number of Users
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Users should be set
    System.assertEquals(50, result.NumberOfUsers, 'NumberOfUsers should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetTier() {
    // Given a UI payload with Tier
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderDocM.DocMKeyData result = (LkgRequestBuilderDocM.DocMKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Tier should be set
    System.assertEquals('S3B100', result.Tier, 'Tier should match');
  }
}