@isTest
public with sharing class LkgMapperFortraTest {
  private static LkgMapperFortra lkgMapper;
  private static LkgMapperBase.UiPayload testPayload;
  private static String payloadJson;

  static {
    lkgMapper = new LkgMapperFortra();
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.silo = 'fortra';
    testPayload.productData.name = 'FTFVM_Fortra_VM';
    testPayload.productData.identifierName = 'FTFVM_Fortra_VM';
    testPayload.productData.productCode = 'FVM';
    testPayload.keyType = 'Generic';
    testPayload.expirationDate = '2025-12-31';
    testPayload.attributes = new Map<String, String>{
      'fortra_Hardware_Id' => 'HW12345',
      'fortra_Number_of_Ips' => '10'
    };
    payloadJson = JSON.serialize(testPayload);
  }

  @isTest
  static void mapPayloadToKeyData_shouldNotReturnNull() {
    // Given a UI payload
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderFortra.FortraKeyData result = (LkgRequestBuilderFortra.FortraKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the result should not be null
    System.assertNotEquals(null, result, 'Mapped FortraKeyData should not be null');
  }

  @isTest
  static void mapPayloadToKeyData_shouldMapTiersBasedOnIps() {
    // Given a UI payload with Number_of_Ips attribute
    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderFortra.FortraKeyData result = (LkgRequestBuilderFortra.FortraKeyData) lkgMapper.mapPayloadToKeyData(
      payloadJson
    );
    Test.stopTest();

    // Then the tiers field in the result should be set based on the Number_of_Ips and default values
    String expectedTiers =
      'A10' +
      LkgMapperFortra.WEBAPPS_DEFAULT +
      LkgMapperFortra.CONTAINERS_DEFAULT +
      LkgMapperFortra.CAPABILITIES_DEFAULT +
      LkgMapperFortra.RNA_COUNT_DEFAULT +
      LkgMapperFortra.LICENSE_FORMAT_VERSION_DEFAULT;
    System.assertEquals(expectedTiers, result.tiers, 'Tiers should be set based on Number_of_Ips and default values.');
  }

  @isTest
  static void mapPayloadToKeyData_shouldHandleMissingNumberOfIps() {
    // Given a UI payload without Number_of_Ips attribute
    testPayload.attributes.remove('fortra_Number_of_Ips');
    String payloadWithoutIps = JSON.serialize(testPayload);

    // When mapPayloadToKeyData is called
    Test.startTest();
    LkgRequestBuilderFortra.FortraKeyData result = (LkgRequestBuilderFortra.FortraKeyData) lkgMapper.mapPayloadToKeyData(
      payloadWithoutIps
    );
    Test.stopTest();

    // Then the tiers field in the result should be set with 'A0' for IPs and default values for other tiers
    String expectedTiers =
      'A0' +
      LkgMapperFortra.WEBAPPS_DEFAULT +
      LkgMapperFortra.CONTAINERS_DEFAULT +
      LkgMapperFortra.CAPABILITIES_DEFAULT +
      LkgMapperFortra.RNA_COUNT_DEFAULT +
      LkgMapperFortra.LICENSE_FORMAT_VERSION_DEFAULT;
    System.assertEquals(
      expectedTiers,
      result.tiers,
      'Tiers should default to A0 for IPs when Number_of_Ips is missing, with default values for other tiers.'
    );
  }
}