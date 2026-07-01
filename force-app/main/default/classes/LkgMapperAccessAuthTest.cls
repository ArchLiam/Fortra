@isTest
public with sharing class LkgMapperAccessAuthTest {
  private static LkgMapperAccessAuth lkgMapper;
  private static LkgMapperBase.UiPayload testPayload;
  private static String payloadJson;

  static {
    lkgMapper = new LkgMapperAccessAuth();
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'accessauth';
    testPayload.productData.name = 'AccessAuth_Product';
    testPayload.productData.productCode = 'AAM';
    testPayload.productData.identifierName = 'PTAAM_MFA_IBMi';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'accessauth_Hardware_Id' => 'HW12345',
      'accessauth_Modification' => '01',
      'accessauth_Release' => '02',
      'PTAAM_MFA_IBMi_Number_of_Users' => '100'
    };
    payloadJson = JSON.serialize(testPayload);
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAccessAuth.AccessAuthKeyData result = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();
    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped AccessAuthKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware ID
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAccessAuth.AccessAuthKeyData result = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Hardware ID should be set
    System.assertEquals('HW12345', result.HardwareId, 'HardwareId should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAccessAuth.AccessAuthKeyData result = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Modification should be set
    System.assertEquals('01', result.Modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAccessAuth.AccessAuthKeyData result = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Release should be set
    System.assertEquals('02', result.Release, 'Release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfUsers() {
    // Given a UI payload with Number of Users
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAccessAuth.AccessAuthKeyData result = (LkgRequestBuilderAccessAuth.AccessAuthKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Users should be set
    System.assertEquals(100, result.NumberOfUsers, 'NumberOfUsers should match');
  }
}