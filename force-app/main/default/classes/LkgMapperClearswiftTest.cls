@isTest
public with sharing class LkgMapperClearswiftTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperClearswift lkgMapper;
  private static String payloadJson;

  static {
    LkgMapperClearswiftTest.testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'clearswift';
    testPayload.productData.name = 'SECURE_Email_Gateway';
    testPayload.productData.productCode = '012';
    testPayload.keyType = 'Clearswift_Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'clearswift_Hardware_Id' => 'HW12345',
      'Clearswift_Company_Name' => 'Test Company',
      'Clearswift_User_Count' => '50',
      'Clearswift_Instances' => '1'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperClearswift();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderClearswift.ClearswiftKeyData result = (LkgRequestBuilderClearswift.ClearswiftKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped ClearswiftKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware ID
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderClearswift.ClearswiftKeyData result = (LkgRequestBuilderClearswift.ClearswiftKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Hardware ID should be set
    System.assertEquals('HW12345', result.HardwareId, 'HardwareId should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetAccountName() {
    // Given a UI payload with Account Name
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderClearswift.ClearswiftKeyData result = (LkgRequestBuilderClearswift.ClearswiftKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Account name should be set
    System.assertEquals('Test Company', result.AccountName, 'AccountName should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetInstances() {
    // Given a UI payload with Instances
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderClearswift.ClearswiftKeyData result = (LkgRequestBuilderClearswift.ClearswiftKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Instances should be set
    System.assertEquals(1, result.Instances, 'Instances should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfUsers() {
    // Given a UI payload with Number of Users
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderClearswift.ClearswiftKeyData result = (LkgRequestBuilderClearswift.ClearswiftKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of users should be set
    System.assertEquals(50, result.NumberOfUsers, 'NumberOfUsers should match');
  }
}