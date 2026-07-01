@isTest
private class LkgMapperHardwareBaseTest {
  // ─── Subclass to expose protected methods without DML ─────────────────────
  // Mirrors the ExposedMapper pattern in LkgMapperBaseTest
  private class TestableHardwareMapper extends LkgMapperHardwareBase {
    public void exposeMapBaseFields(
      LkgMapperHardwareBase.HardwarePayload p,
      LkgMapperHardwareBase.AssetData a,
      LkgRequestBuilderBase.KeyData k
    ) {
      mapBaseFields(p, a, k);
    }
  }

  // ─── mapPayloadToKeyData — pre-SOQL validation guards ────────────────────
  // LkgMapperHardwareBase is virtual (not abstract) and can be instantiated
  // directly to test validation paths that throw before any SOQL is reached.

  @isTest
  static void mapPayloadToKeyData_shouldThrowWhenSourceIsNotHardware() {
    // Given a payload whose 'source' field is NOT 'hardware'
    LkgMapperHardwareBase.HardwarePayload wrongPayload = new LkgMapperHardwareBase.HardwarePayload();
    wrongPayload.source = 'ui'; // not 'hardware'
    wrongPayload.assetId = '02i000000000001AAA';
    String payloadJson = JSON.serialize(wrongPayload);

    LkgMapperHardwareBase mapper = new LkgMapperHardwareBase();

    // When
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      mapper.mapPayloadToKeyData(payloadJson);
    } catch (LkgMapperHardwareBase.HardwareMapperException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      exceptionThrown,
      'mapPayloadToKeyData() should throw a HardwareMapperException when source is not "hardware".'
    );
  }

  @isTest
  static void mapPayloadToKeyData_shouldThrowWhenAssetIdIsNull() {
    // Given a hardware payload with a null assetId
    LkgMapperHardwareBase.HardwarePayload noAsset = new LkgMapperHardwareBase.HardwarePayload();
    noAsset.source = 'hardware';
    noAsset.assetId = null; // missing — required field
    String payloadJson = JSON.serialize(noAsset);

    LkgMapperHardwareBase mapper = new LkgMapperHardwareBase();

    // When
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      mapper.mapPayloadToKeyData(payloadJson);
    } catch (LkgMapperHardwareBase.HardwareMapperException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      exceptionThrown,
      'mapPayloadToKeyData() should throw a HardwareMapperException when assetId is null.'
    );
  }

  // ─── Inner-class structure tests ──────────────────────────────────────────

  @isTest
  static void hardwarePayload_shouldDeserialiseFromJsonCorrectly() {
    // Given a JSON string representing a HardwarePayload
    String payloadJson = '{"source":"hardware","assetId":"02i000000000001AAA","hardwareId":"a0x000000000001AAA","keyType":"Generic"}';

    // When
    Test.startTest();
    LkgMapperHardwareBase.HardwarePayload payload = (LkgMapperHardwareBase.HardwarePayload) JSON.deserialize(
      payloadJson,
      LkgMapperHardwareBase.HardwarePayload.class
    );
    Test.stopTest();

    // Then
    System.Assert.areEqual('hardware', payload.source, 'source should be deserialised correctly.');
    System.Assert.areEqual('Generic', payload.keyType, 'keyType should be deserialised correctly.');
  }

  @isTest
  static void assetData_shouldBeInstantiableWithDefaultNullFields() {
    // Given no input — just instantiate the inner DTO class

    // When
    Test.startTest();
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    Test.stopTest();

    // Then — all fields default to null
    System.Assert.isNull(assetData.assetId, 'assetId should default to null.');
    System.Assert.isNull(assetData.productData, 'productData should default to null.');
    System.Assert.isNull(assetData.attributes, 'attributes should default to null.');
  }

  @isTest
  static void mapPayloadToKeyData_shouldThrowWhenAssetNotFound() {
    // Given: insert then delete an Asset, leaving an orphaned (non-existent) Id
    Account acc = new Account(Name = 'HardwareBase NotFound Account');
    insert acc;
    Asset tempAsset = new Asset(Name = 'Temp Asset', AccountId = acc.Id, Status = 'Installed');
    insert tempAsset;
    Id orphanedId = tempAsset.Id;
    delete tempAsset;

    LkgMapperHardwareBase.HardwarePayload payload = new LkgMapperHardwareBase.HardwarePayload();
    payload.source = 'hardware';
    payload.assetId = orphanedId; // valid format, but record no longer exists
    String payloadJson = JSON.serialize(payload);

    LkgMapperHardwareBase mapper = new LkgMapperHardwareBase();

    // When
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      mapper.mapPayloadToKeyData(payloadJson);
    } catch (LkgMapperHardwareBase.HardwareMapperException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      exceptionThrown,
      'mapPayloadToKeyData() should throw a HardwareMapperException when the Asset record no longer exists.'
    );
  }

  @isTest
  static void mapPayloadToKeyData_shouldThrowWhenAssetHardwareMismatch() {
    // Given an Asset with no Hardware__c link; a non-matching hardwareId in the payload
    Account acc = new Account(Name = 'HardwareBase Mismatch Account');
    insert acc;
    Asset asset = new Asset(Name = 'Mismatch Asset', AccountId = acc.Id, Status = 'Installed');
    insert asset;

    // asset.Hardware__c = null; acc.Id is non-null and != null → triggers mismatch guard
    LkgMapperHardwareBase.HardwarePayload payload = new LkgMapperHardwareBase.HardwarePayload();
    payload.source = 'hardware';
    payload.assetId = asset.Id;
    payload.hardwareId = acc.Id; // valid non-null Id that != asset.Hardware__c (null)
    String payloadJson = JSON.serialize(payload);

    LkgMapperHardwareBase mapper = new LkgMapperHardwareBase();

    // When
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      mapper.mapPayloadToKeyData(payloadJson);
    } catch (LkgMapperHardwareBase.HardwareMapperException e) {
      exceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      exceptionThrown,
      'mapPayloadToKeyData() should throw when the Asset is not linked to the provided Hardware.'
    );
  }

  @isTest
  static void mapPayloadToKeyData_shouldThrowAuraExceptionWhenEnrichmentFails() {
    // Asset with no Hardware__c → queryAssetData succeeds, assetData.hardwareId = null
    // → enrich() returns error → AuraHandledException thrown
    // Covers: queryAssetData call, enrich call, errors-not-empty check, AuraHandledException throw
    Account acc = new Account(Name = 'HardwareBase Enrich Fail Account');
    insert acc;
    Asset asset = new Asset(Name = 'Enrich Fail Asset', AccountId = acc.Id, Status = 'Installed');
    insert asset; // Hardware__c intentionally null → assetData.hardwareId will be null after queryAssetData

    LkgMapperHardwareBase.HardwarePayload payload = new LkgMapperHardwareBase.HardwarePayload();
    payload.source = 'hardware';
    payload.assetId = asset.Id;
    payload.hardwareId = null; // no hardware in payload either
    String payloadJson = JSON.serialize(payload);

    LkgMapperHardwareBase mapper = new LkgMapperHardwareBase();

    // When
    Test.startTest();
    Boolean auraExceptionThrown = false;
    try {
      mapper.mapPayloadToKeyData(payloadJson);
    } catch (AuraHandledException e) {
      auraExceptionThrown = true;
    }
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      auraExceptionThrown,
      'mapPayloadToKeyData() should throw AuraHandledException when enrichment returns errors.'
    );
  }

  // ─── mapBaseFields — in-memory direct calls (no DML, no SOQL) ────────────

  @isTest
  static void mapBaseFields_shouldMapAllKeyDataFieldsFromInMemoryObjects() {
    // Given: fully populated in-memory payload, assetData (with productData), and keyData
    LkgMapperHardwareBase.HardwarePayload payload = new LkgMapperHardwareBase.HardwarePayload();
    payload.accountId = null; // null → falls back to assetData.accountId
    payload.contact1Id = null;
    payload.contact2Id = null;
    payload.sendEmail = true;
    payload.keyType = 'Generic';
    payload.expirationDate = '2026-12-31';
    payload.attributes = new Map<String, String>{ 'Notes' => 'hardware mapper test' };

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.hardwareId = null;
    assetData.accountId = null;
    assetData.serialNumber = 'SN-FAKE-001';
    LkgMapperBase.ProductData pd = new LkgMapperBase.ProductData();
    pd.productCode = 'HW_PROD_001';
    pd.externalName = 'HW External';
    pd.internalName = 'HW Internal';
    pd.silo = 'automate';
    pd.subSilo = 'aut';
    assetData.productData = pd;

    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();
    TestableHardwareMapper mapper = new TestableHardwareMapper();

    // When
    Test.startTest();
    mapper.exposeMapBaseFields(payload, assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.areEqual('Generic', keyData.KeyType, 'KeyType should be mapped.');
    System.Assert.areEqual(true, keyData.SendEmail, 'SendEmail should be mapped.');
    System.Assert.areEqual('SN-FAKE-001', keyData.serialNumber, 'SerialNumber should be mapped.');
    System.Assert.areEqual('HW_PROD_001', keyData.ProductCode, 'ProductCode should be mapped.');
    System.Assert.areEqual('HW External', keyData.externalProductName, 'External name should be mapped.');
    System.Assert.areEqual('HW Internal', keyData.internalProductName, 'Internal name should be mapped.');
    System.Assert.areEqual('automate', keyData.Silo, 'Silo should be mapped.');
    System.Assert.areEqual('aut', keyData.subSilo, 'SubSilo should be mapped.');
    System.Assert.areEqual(false, keyData.createLicenseKeyFile, 'createLicenseKeyFile should default to false.');
    System.Assert.areEqual('hardware mapper test', keyData.Notes, 'Notes should be mapped.');
    System.Assert.areEqual(Date.newInstance(2026, 12, 31), keyData.ExpirationDate, 'ExpirationDate should be parsed.');
    System.Assert.areEqual(Date.today(), keyData.StartDate, 'StartDate should be today.');
  }

  @isTest
  static void mapBaseFields_shouldHandleNullableFieldsGracefully() {
    // Covers: sendEmail null → false, blank expirationDate → no ExpirationDate set,
    // null attributes → Notes null, hardwareId non-null → String.valueOf branch
    LkgMapperHardwareBase.HardwarePayload payload = new LkgMapperHardwareBase.HardwarePayload();
    payload.accountId = null;
    payload.sendEmail = null; // null → ternary → false
    payload.expirationDate = null; // blank → no ExpirationDate
    payload.attributes = null; // null → attributes?.get() → null

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.hardwareId = '001000000000001AAA'; // non-null → covers String.valueOf branch
    assetData.accountId = null;
    assetData.productData = new LkgMapperBase.ProductData();

    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();
    TestableHardwareMapper mapper = new TestableHardwareMapper();

    // When
    Test.startTest();
    mapper.exposeMapBaseFields(payload, assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.areEqual(false, keyData.SendEmail, 'SendEmail should default to false when null in payload.');
    System.Assert.isNull(keyData.ExpirationDate, 'ExpirationDate should remain null when expirationDate is blank.');
    System.Assert.isNull(keyData.Notes, 'Notes should be null when attributes map is null.');
    System.Assert.isNotNull(
      keyData.HardwareId,
      'HardwareId should be set via String.valueOf when assetData.hardwareId is non-null.'
    );
  }
}