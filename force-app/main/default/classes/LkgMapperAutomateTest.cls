@isTest
public with sharing class LkgMapperAutomateTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperAutomate lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'automate';
    testPayload.productData.name = 'Automate_Product';
    testPayload.productData.identifierName = 'Automate_Product';
    testPayload.productData.productCode = 'BPA';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'automate_Hardware_Id' => 'HW12345',
      'Automate_Product_Tier' => 'C',
      'automate_Release' => '11',
      'Automate_Product_Actions_T' => '["10", "20"]',
      'Automate_Product_Actions_M' => '20',
      'Automate_Product_Actions_N' => '30',
      'Automate_Product_Actions_P' => '40',
      'Automate_Product_Number_of_Bots' => '5',
      'Automate_Product_Number_of_Studios' => '3',
      'Automate_Product_Number_of_BPA_WebSMCs' => '2',
      'automate_Modification' => '01'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperAutomate();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAutomate.AutomateKeyData result = (LkgRequestBuilderAutomate.AutomateKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped AutomateKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetHardwareId() {
    // Given a UI payload with Hardware_Id
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAutomate.AutomateKeyData result = (LkgRequestBuilderAutomate.AutomateKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the HardwareId field should be set correctly
    System.assertEquals('HW12345', result.HardwareId, 'HardwareId should be set to HW12345');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAutomate.AutomateKeyData result = (LkgRequestBuilderAutomate.AutomateKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the Modification field should be set correctly
    System.assertEquals('01', result.modification, 'Modification should be set to 01');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetPoints() {
    // Given a UI payload with specific attributes
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderAutomate.AutomateKeyData result = (LkgRequestBuilderAutomate.AutomateKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the points field should be set correctly based on the context
    String expectedPoints = 'S3K524287L16383M1023N262143P524287Q32767T65533E5F3G2V11';
    System.assertEquals(expectedPoints, result.points, 'Points should be calculated correctly based on the context');
  }
}