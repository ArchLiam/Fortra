@isTest
public with sharing class LkgMapperPtMultiTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperPtMulti lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'ptmulti';
    testPayload.productData.name = 'PtMulti_Product';
    testPayload.productData.identifierName = 'PtMulti_Product';
    testPayload.productData.productCode = 'PEM';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{ 'ptmulti_Modification' => '05', 'ptmulti_Level' => '42' };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperPtMulti();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderPtMulti.PtMultiKeyData result = (LkgRequestBuilderPtMulti.PtMultiKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped PtMultiKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderPtMulti.PtMultiKeyData result = (LkgRequestBuilderPtMulti.PtMultiKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Modification should be set
    System.assertEquals('05', result.modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetPoints() {
    // Given a UI payload with Level (points)
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderPtMulti.PtMultiKeyData result = (LkgRequestBuilderPtMulti.PtMultiKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then points should be set
    System.assertEquals('42', result.points, 'Points should match');
  }
}