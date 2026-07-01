@isTest
private class LkgMapperHalcyonIbmTest {
  private static final LkgMapperHalcyonIbm mapper = new LkgMapperHalcyonIbm();
  private static final String payloadJson;

  static {
    LkgMapperBase.UiPayload payload = new LkgMapperBase.UiPayload();
    payload.productData = new LkgMapperBase.ProductData();
    payload.productData.silo = 'halcyon';
    payload.productData.subSilo = 'ibm';
    payload.productData.brandName = 'Halcyon';
    payload.productData.externalName = 'Halcyon IBM';
    payload.productData.internalName = 'HalcyonSuite';
    payload.productData.identifierName = 'Halcyon_IBM';
    payload.productData.productCode = 'IBM001';
    payload.expirationDate = '2026-12-31';
    payload.keyType = LkgRequestBuilderBase.KEYTYPE_GENERIC;
    payload.sendEmail = true;
    payload.attributes = new Map<String, String>{
      'halcyon_System_Name' => 'MEEMIC2',
      'halcyon_Serial_Number' => '780B530',
      'halcyon_Model_Number' => '42A',
      'halcyon_Feature_Code' => 'FC123',
      'halcyon_Number_of_Cores' => '8',
      'halcyon_Performance_Group' => 'PG1',
      'Halcyon_IBM_Individual_Products' => '["15","14","12","21"]',
      'Halcyon_IBM_Individual_Monitors' => '["3","5","9","14"]'
    };

    payloadJson = JSON.serialize(payload);
  }

  @isTest
  static void mapPayloadToKeyData_shouldReturnHalcyonIbmKeyData() {
    Test.startTest();
    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData result = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) mapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Mapped Halcyon IBM key data should not be null');
    System.assertEquals('ibm', result.subSilo, 'Sub silo should be mapped from the payload');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetSystemNameAndModelNumber() {
    Test.startTest();
    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData result = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) mapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    System.assertEquals('MEEMIC2', result.lparSystemName, 'System name should match');
    System.assertEquals('42A', result.modelNumber, 'Model number should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetSerialNumber() {
    Test.startTest();
    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData result = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) mapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    System.assertEquals('780B530', result.lparSerialNumber, 'Serial number should match');
  }

  @isTest
  static void mapPayloadToKeyData_shouldSetAdditionalHalcyonFields() {
    Test.startTest();
    LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData result = (LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData) mapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    System.assertEquals('FC123', result.featureCode, 'Feature code should match');
    System.assertEquals('8', result.cores, 'Cores should match');
    System.assertEquals('PG1', result.performanceGroup, 'Performance group should match');
  }
}