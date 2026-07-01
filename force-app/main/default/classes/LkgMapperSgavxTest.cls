@isTest
public with sharing class LkgMapperSgavxTest {
  private static LkgMapperSgavx lkgMapper;
  private static LkgMapperBase.UiPayload testPayload;
  private static String payloadJson;

  static {
    lkgMapper = new LkgMapperSgavx();

    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'sgavx';
    testPayload.productData.name = 'SGAVX_Product';
    testPayload.productData.identifierName = 'sgavx';
    testPayload.productData.productCode = '';
    testPayload.expirationDate = '2025-12-31';
    testPayload.keyType = 'Specific/Temporary';
    testPayload.accountId = '001000000000001';
    testPayload.attributes = new Map<String, String>{
      'sgavx_Number_of_Users' => '10',
      'sgavx_MAC_Address' => '00:1A:2B:3C:4D:5E',
      'sgavx_Modification' => '01',
      'sgavx_Release' => '02'
    };

    payloadJson = JSON.serialize(testPayload);
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped SgavxKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfUsers() {
    // Given a UI payload with User Count
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then NumberOfUsers should be set
    System.assertEquals(10, result.NumberOfUsers, 'NumberOfUsers should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with MAC Address
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then HardwareId should be set
    System.assertEquals('00:1A:2B:3C:4D:5E', result.HardwareId, 'HardwareId should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Modification should be set
    System.assertEquals('01', result.Modification, 'Modification should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then Release should be set
    System.assertEquals('02', result.release, 'Release should match the value in the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetCreateLicenseKeyFile() {
    // Given a UI payload with Version
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderSgavx.SgavxKeyData result = (LkgRequestBuilderSgavx.SgavxKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then create license key file should be set
    Assert.isTrue(result.createLicenseKeyFile, 'Create license key file flag should be set to true.');
  }
}