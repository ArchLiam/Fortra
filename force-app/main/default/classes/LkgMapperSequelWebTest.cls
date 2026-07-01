@isTest
public with sharing class LkgMapperSequelWebTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperSequelWeb lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'sequelweb';
    testPayload.productData.name = 'SequelWeb_Product';
    testPayload.productData.identifierName = 'SequelWeb_Product';
    testPayload.productData.productCode = '920';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'sequelweb_Release' => '10',
      'sequelweb_Modification' => '5',
      'sequelweb_Number_of_Viewers' => '50',
      'sequelweb_Number_of_Designers' => '10',
      'sequelweb_Hardware_Id' => 'HW12345'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperSequelWeb();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped SequelWebKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('10', result.Release, 'Release should match');
    System.assertEquals('10', result.release, 'release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('5', result.Modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfViewers() {
    // Given a UI payload with Number of Viewers
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Viewers should be set
    System.assertEquals(50, result.NumberOfViewers, 'NumberOfViewers should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfDesigners() {
    // Given a UI payload with Number of Designers
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Designers should be set
    System.assertEquals(10, result.NumberOfDesigners, 'NumberOfDesigners should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware Id
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSequelWeb.SequelWebKeyData result = (LkgRequestBuilderSequelWeb.SequelWebKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Hardware Id should be set
    System.assertEquals('HW12345', result.HardwareId, 'HardwareId should match');
  }
}