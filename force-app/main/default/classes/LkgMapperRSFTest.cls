@isTest
public with sharing class LkgMapperRSFTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperRSF lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'rsf';
    testPayload.productData.name = 'RSF_Product';
    testPayload.productData.identifierName = 'RSF001_RSF_Save';
    testPayload.productData.productCode = '100';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'rsf_Serial_Number' => 'SN123456',
      'rsf_Release' => '10',
      'rsf_Modification' => '00'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperRSF();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRSF.RSFKeyData result = (LkgRequestBuilderRSF.RSFKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped RSFKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetSerialNumber() {
    // Given a UI payload with Serial Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRSF.RSFKeyData result = (LkgRequestBuilderRSF.RSFKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Serial Number should be set
    System.assertEquals('SN123456', result.LParSerialNumber, 'serialNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRSF.RSFKeyData result = (LkgRequestBuilderRSF.RSFKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('10', result.Release, 'Release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRSF.RSFKeyData result = (LkgRequestBuilderRSF.RSFKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('00', result.Modification, 'Modification should match');
  }
}