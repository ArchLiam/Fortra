@isTest
private class LkgUiHardwareControllerTest {
  // ─── Test data helpers ────────────────────────────────────────────────────

  private static Account createAccount() {
    Account acc = new Account(Name = 'Hardware Controller Test Account');
    insert acc;
    return acc;
  }

  private static Hardware__c createHardware(Id accountId) {
    Hardware__c hw = new Hardware__c(
      Account__c = accountId,
      Serial_Number__c = 'SN-HW-TEST-001',
      Hardware_Type__c = 'Production'
    );
    insert hw;
    return hw;
  }

  private static Asset createAsset(Id accountId, Id hardwareId) {
    Asset a = new Asset(Name = 'Test Asset', AccountId = accountId, Hardware__c = hardwareId);
    insert a;
    return a;
  }

  // ─── getHardwareKeyTypes() ────────────────────────────────────────────────

  @isTest
  static void getHardwareKeyTypes_shouldReturnNonNullList() {
    // Given MDT records for Global-scoped, non-Generic key types may exist in the org

    // When
    Test.startTest();
    List<LKG_Key_Type__mdt> results = LkgUiHardwareController.getHardwareKeyTypes();
    Test.stopTest();

    // Then
    System.Assert.isNotNull(results, 'getHardwareKeyTypes() must never return null.');
  }

  // ─── getHardware() ────────────────────────────────────────────────────────

  @isTest
  static void getHardware_shouldReturnHardwareRecordsForAccount() {
    // Given an account with one Hardware__c record
    Account acc = createAccount();
    createHardware(acc.Id);

    // When
    Test.startTest();
    List<Hardware__c> results = LkgUiHardwareController.getHardware(acc.Id, null, null, null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      1,
      results.size(),
      'getHardware() should return the one hardware record linked to the account.'
    );
  }

  @isTest
  static void getHardware_shouldReturnEmptyListWhenNoHardwareExistsForAccount() {
    // Given an account with no Hardware__c records
    Account acc = createAccount();

    // When
    Test.startTest();
    List<Hardware__c> results = LkgUiHardwareController.getHardware(acc.Id, null, null, null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      0,
      results.size(),
      'getHardware() should return an empty list when no hardware records exist.'
    );
  }

  @isTest
  static void getHardware_shouldFilterBySerialNumberWhenFilterIsProvided() {
    // Given two hardware records with different serial numbers
    Account acc = createAccount();
    Hardware__c hw1 = new Hardware__c(
      Account__c = acc.Id,
      Serial_Number__c = 'SERIAL-MATCH-99',
      Hardware_Type__c = 'Production'
    );
    Hardware__c hw2 = new Hardware__c(
      Account__c = acc.Id,
      Serial_Number__c = 'DIFFERENT-SERIAL',
      Hardware_Type__c = 'Production'
    );
    insert new List<Hardware__c>{ hw1, hw2 };

    // When — filter by partial serial number that matches only hw1
    Test.startTest();
    List<Hardware__c> results = LkgUiHardwareController.getHardware(acc.Id, null, 'MATCH-99', null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      1,
      results.size(),
      'getHardware() should return only the hardware records whose serial number matches the filter.'
    );
    System.Assert.areEqual(
      hw1.Id,
      results[0].Id,
      'The returned record should be the one whose serial number contains the filter string.'
    );
  }

  @isTest
  static void getHardware_shouldRespectPageSizeLimit() {
    // Given three hardware records for the same account
    Account acc = createAccount();
    insert new List<Hardware__c>{
      new Hardware__c(Account__c = acc.Id, Serial_Number__c = 'SN-P1', Hardware_Type__c = 'Production'),
      new Hardware__c(Account__c = acc.Id, Serial_Number__c = 'SN-P2', Hardware_Type__c = 'Production'),
      new Hardware__c(Account__c = acc.Id, Serial_Number__c = 'SN-P3', Hardware_Type__c = 'Production')
    };

    // When — pageSize=2 should cap results at 2
    Test.startTest();
    List<Hardware__c> results = LkgUiHardwareController.getHardware(acc.Id, null, null, 2, 0);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      2,
      results.size(),
      'getHardware() should return no more records than the pageSize parameter allows.'
    );
  }

  // ─── getAssets() ─────────────────────────────────────────────────────────

  @isTest
  static void getAssets_shouldReturnEmptyListWhenHardwareIdsIsNull() {
    // Given no hardware IDs provided

    // When
    Test.startTest();
    List<Asset> results = LkgUiHardwareController.getAssets(null, null, null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(0, results.size(), 'getAssets() should return an empty list when hardwareIds is null.');
  }

  @isTest
  static void getAssets_shouldReturnEmptyListWhenHardwareIdsIsEmpty() {
    // Given an empty hardware ID list

    // When
    Test.startTest();
    List<Asset> results = LkgUiHardwareController.getAssets(new List<Id>(), null, null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(0, results.size(), 'getAssets() should return an empty list when hardwareIds is empty.');
  }

  @isTest
  static void getAssets_shouldReturnAssetsLinkedToProvidedHardware() {
    // Given an account, one hardware record, and one asset linked to that hardware
    Account acc = createAccount();
    Hardware__c hw = createHardware(acc.Id);
    createAsset(acc.Id, hw.Id);

    // When
    Test.startTest();
    List<Asset> results = LkgUiHardwareController.getAssets(new List<Id>{ hw.Id }, null, null, null);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      1,
      results.size(),
      'getAssets() should return the asset that is linked to the provided hardware ID.'
    );
  }

  // ─── generateKeysForHardware() — validation ───────────────────────────────

  @isTest
  static void generateKeysForHardware_shouldReturnErrorForNullPayload() {
    // Given a null JSON string

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(null);
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return overallSuccess=false for a null payload.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorWhenSourceIsNotHardware() {
    // Given a payload with source="software" instead of "hardware"
    Account acc = createAccount();
    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'software';
    payload.accountId = acc.Id;
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>();

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return failure when source is not "hardware".'
    );
    System.Assert.isTrue(
      response.message.contains('Source must be'),
      'Failure message should indicate that source must be "hardware".'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorWhenAccountIdIsNull() {
    // Given a payload with source="hardware" but null accountId
    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.accountId = null;
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>();

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return failure when accountId is null.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorWhenHardwareRecordsIsEmpty() {
    // Given a payload with valid source and accountId but an empty hardware records list
    Account acc = createAccount();
    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.accountId = acc.Id;
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>();

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return failure when hardware records list is empty.'
    );
    System.Assert.isTrue(
      response.message.contains('hardware record'),
      'Failure message should indicate at least one hardware record is required.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorWhenHardwareRecordHasNullHardwareId() {
    // Given a hardware record where hardwareId is null
    Account acc = createAccount();
    LkgProcessorHardwareKeys.HardwareRecord hwRecord = new LkgProcessorHardwareKeys.HardwareRecord();
    hwRecord.hardwareId = null;
    hwRecord.assetIds = new List<Id>{ acc.Id }; // dummy asset ID — irrelevant since validation fails first

    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.accountId = acc.Id;
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>{ hwRecord };

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return failure when a hardware record has a null hardwareId.'
    );
    System.Assert.isTrue(
      response.message.contains('hardwareId'),
      'Failure message should indicate the missing hardwareId field.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorWhenHardwareRecordHasNoAssetIds() {
    // Given a hardware record with a valid hardwareId but an empty assetIds list
    Account acc = createAccount();
    Hardware__c hw = createHardware(acc.Id);

    LkgProcessorHardwareKeys.HardwareRecord hwRecord = new LkgProcessorHardwareKeys.HardwareRecord();
    hwRecord.hardwareId = hw.Id;
    hwRecord.assetIds = new List<Id>(); // empty

    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.accountId = acc.Id;
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>{ hwRecord };

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return failure when a hardware record has no assetIds.'
    );
    System.Assert.isTrue(
      response.message.contains('assetId'),
      'Failure message should indicate that at least one assetId is required per hardware record.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldReturnErrorForMalformedJson() {
    // Given a JSON string that cannot be deserialized to HardwarePayload

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware('NOT_VALID_JSON{{');
    Test.stopTest();

    // Then — must not throw; returns an error response
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isFalse(
      response.overallSuccess,
      'generateKeysForHardware() should return overallSuccess=false for malformed JSON.'
    );
  }

  @isTest
  static void generateKeysForHardware_shouldProcessValidPayloadAndReturnAssetResults() {
    // Given a fully valid payload with real Account, Hardware, and Asset records
    Account acc = createAccount();
    Hardware__c hw = createHardware(acc.Id);
    Asset a = createAsset(acc.Id, hw.Id);

    LkgProcessorHardwareKeys.HardwareRecord hwRecord = new LkgProcessorHardwareKeys.HardwareRecord();
    hwRecord.hardwareId = hw.Id;
    hwRecord.assetIds = new List<Id>{ a.Id };

    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.accountId = acc.Id;
    payload.keyType = 'Temporary';
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>{ hwRecord };

    // When
    Test.startTest();
    String jsonResponse = LkgUiHardwareController.generateKeysForHardware(JSON.serialize(payload));
    Test.stopTest();

    // Then — validation passes; simulation completes; one AssetKeyResult is returned
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = (LkgProcessorHardwareKeys.HardwareKeyGenResponse) JSON.deserialize(
      jsonResponse,
      LkgProcessorHardwareKeys.HardwareKeyGenResponse.class
    );
    System.Assert.isNotNull(response, 'generateKeysForHardware() must return a non-null response for a valid payload.');
    System.Assert.isNotNull(response.assetResults, 'The response must include an assetResults list.');
    System.Assert.areEqual(
      1,
      response.assetResults.size(),
      'One AssetKeyResult should be returned for the one asset in the payload.'
    );
  }
}