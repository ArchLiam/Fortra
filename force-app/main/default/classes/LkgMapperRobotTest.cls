@isTest
public with sharing class LkgMapperRobotTest {
  private static LkgMapperBase.UiPayload testPayload;
  private static LkgMapperRobot lkgMapper;
  private static String payloadJson;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'robot';
    testPayload.productData.name = 'Robot_Product';
    testPayload.productData.identifierName = 'RB001_Robot_Save';
    testPayload.productData.productCode = 'RB001';
    testPayload.keyType = 'Specific_Temporary';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'robot_Hardware_Id' => 'HW12345',
      'robot_Release' => '10',
      'robot_Modification' => '00',
      'robot_End_LPAR_Num' => '99999',
      'robot_Feature_Code' => 'FT1234',
      'robot_iAsp_Group' => 'GroupA',
      'robot_LPAR_Name' => 'LPAR1',
      'robot_LPAR_Num' => '12345',
      'robot_Model_Number' => 'Model1',
      'Notes' => 'Test Notes',
      'robot_Number_of_Processors' => '4',
      'RB001_Robot_Save_Number_of_Users' => '100',
      'robot_Processor_Type' => 'TypeA',
      'robot_Serial_Number' => 'SN123456',
      'RB001_Robot_Save_Version_Range' => '{"minVersion":10,"minModification":7,"maxVersion":10,"maxModification":31,"isPermTerm":true}'
    };
    payloadJson = JSON.serialize(testPayload);
    lkgMapper = new LkgMapperRobot();
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped RobotKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetRelease() {
    // Given a UI payload with Release
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Release should be set
    System.assertEquals('10', result.release, 'Release should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModification() {
    // Given a UI payload with Modification
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Modification should be set
    System.assertEquals('00', result.Modification, 'Modification should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetEndLPARNumber() {
    // Given a UI payload with End LPAR Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // End LPAR Number should be set
    System.assertEquals('99999', result.LParEnd, 'LParEnd should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetFeatureCode() {
    // Given a UI payload with Feature Code
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Feature Code should be set
    System.assertEquals('FT1234', result.FeatureCode, 'FeatureCode should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetIaspGroup() {
    // Given a UI payload with iAsp Group
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // iAsp Group should be set
    System.assertEquals('GroupA', result.IAspGroup, 'IAspGroup should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetLParNumber() {
    // Given a UI payload with LPAR Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // LPAR Number should be set
    System.assertEquals('12345', result.LParNumber, 'LParNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetModelNumber() {
    // Given a UI payload with Model Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Model Number should be set
    System.assertEquals('Model1', result.ModelNumber, 'ModelNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNotes() {
    // Given a UI payload with Notes
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Notes should be set
    System.assertEquals('Test Notes', result.Notes, 'Notes should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfProcessors() {
    // Given a UI payload with Number of Processors
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Processors should be set
    System.assertEquals(4, result.NumberOfProcessors, 'NumberOfProcessors should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetNumberOfUsers() {
    // Given a UI payload with Number of Users
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Number of Users should be set
    System.assertEquals(100, result.NumberOfUsers, 'NumberOfUsers should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetProcessorType() {
    // Given a UI payload with Processor Type
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Processor Type should be set
    System.assertEquals('TypeA', result.ProcessorType, 'ProcessorType should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetLParSerialNumber() {
    // Given a UI payload with LPar Serial Number
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // LPar Serial Number should be set
    System.assertEquals('SN123456', result.LParSerialNumber, 'LParSerialNumber should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetPermTermVersionRange() {
    // Given a UI payload with Version Range
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderRobot.RobotKeyData result = (LkgRequestBuilderRobot.RobotKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // PermTermVersionRange should be set
    System.assertNotEquals(null, result.PermTermVersionRange, 'PermTermVersionRange should not be null');
  }
}