@isTest
private class LkgProcessorHardwareKeysTest {

  // ─── Shared test fixtures ──────────────────────────────────────────────────
  // Reuse the same JSON format as LkgProcessorTest — the processor delegates
  // to mocked collaborators, so the payload format is opaque at this level.

  private static String payloadJson;
  private static LkgProcessorHardwareKeys processorFullMock;

  static {
    LkgMapperBase.UiPayload uiPayload = new LkgMapperBase.UiPayload();
    uiPayload.productData = new LkgMapperBase.ProductData();
    uiPayload.productData.silo = 'clearswift';
    uiPayload.productData.subSilo = null;
    payloadJson = JSON.serialize(uiPayload);

    LkgMapperFactory mapperFactoryMock = (LkgMapperFactory) Test.createStub(
      LkgMapperFactory.class,
      new LkgMapperFactoryMock()
    );
    LkgRequestBuilderFactory builderFactoryMock = (LkgRequestBuilderFactory) Test.createStub(
      LkgRequestBuilderFactory.class,
      new LkgRequestBuilderFactoryMock()
    );
    LkgRequestController requestControllerMock = (LkgRequestController) Test.createStub(
      LkgRequestController.class,
      new LkgRequestControllerMock()
    );
    LkgRecordCreatorFactory recordCreatorFactoryMock = (LkgRecordCreatorFactory) Test.createStub(
      LkgRecordCreatorFactory.class,
      new LkgRecordCreatorFactoryMock()
    );

    processorFullMock = new LkgProcessorHardwareKeys(
      mapperFactoryMock,
      builderFactoryMock,
      requestControllerMock,
      recordCreatorFactoryMock
    );
  }

  // ─── executeForAsset — factory null-guard tests ───────────────────────────

  @isTest
  static void executeForAsset_shouldReturnErrorWhenMapperFactoryReturnsNull() {
    // Given a processor whose mapper factory always returns null
    LkgProcessorHardwareKeys processor = new LkgProcessorHardwareKeys(
      (LkgMapperFactory) Test.createStub(LkgMapperFactory.class, new LkgNullReturnStub()),
      (LkgRequestBuilderFactory) Test.createStub(LkgRequestBuilderFactory.class, new LkgNullReturnStub()),
      (LkgRequestController) Test.createStub(LkgRequestController.class, new LkgNullReturnStub()),
      (LkgRecordCreatorFactory) Test.createStub(LkgRecordCreatorFactory.class, new LkgNullReturnStub())
    );

    // When
    Test.startTest();
    LkgKeyGenResponse response = processor.executeForAsset(payloadJson);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.isSuccess,
      'executeForAsset() should return a failure response when the mapper factory returns null.'
    );
    System.Assert.isTrue(
      response.message.contains('Invalid Silo Mapper'),
      'Error message should mention an invalid silo mapper.'
    );
  }

  @isTest
  static void executeForAsset_shouldReturnErrorWhenRequestBuilderFactoryReturnsNull() {
    // Given a processor where the mapper factory works but the builder factory returns null
    // (re-use existing mapper mock; clearswift mapper → KeyData.Silo='clearswift'
    //  but builder factory stub returns null for every silo)
    LkgProcessorHardwareKeys processor = new LkgProcessorHardwareKeys(
      (LkgMapperFactory) Test.createStub(LkgMapperFactory.class, new LkgMapperFactoryMock()),
      (LkgRequestBuilderFactory) Test.createStub(LkgRequestBuilderFactory.class, new LkgNullReturnStub()),
      (LkgRequestController) Test.createStub(LkgRequestController.class, new LkgNullReturnStub()),
      (LkgRecordCreatorFactory) Test.createStub(LkgRecordCreatorFactory.class, new LkgNullReturnStub())
    );

    // When
    Test.startTest();
    LkgKeyGenResponse response = processor.executeForAsset(payloadJson);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.isSuccess,
      'executeForAsset() should return a failure response when the request builder factory returns null.'
    );
    System.Assert.isTrue(
      response.message.contains('Invalid Request Builder'),
      'Error message should mention an invalid request builder.'
    );
  }

  @isTest
  static void executeForAsset_shouldReturnErrorWhenRecordCreatorFactoryReturnsNull() {
    // Given a processor where mapper + builder work but record creator factory returns null
    LkgProcessorHardwareKeys processor = new LkgProcessorHardwareKeys(
      (LkgMapperFactory) Test.createStub(LkgMapperFactory.class, new LkgMapperFactoryMock()),
      (LkgRequestBuilderFactory) Test.createStub(LkgRequestBuilderFactory.class, new LkgRequestBuilderFactoryMock()),
      (LkgRequestController) Test.createStub(LkgRequestController.class, new LkgRequestControllerMock()),
      (LkgRecordCreatorFactory) Test.createStub(LkgRecordCreatorFactory.class, new LkgNullReturnStub())
    );

    // When
    Test.startTest();
    LkgKeyGenResponse response = processor.executeForAsset(payloadJson);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.isSuccess,
      'executeForAsset() should return a failure response when the record creator factory returns null.'
    );
    System.Assert.isTrue(
      response.message.contains('Invalid Record Creator'),
      'Error message should mention an invalid record creator.'
    );
  }

  @isTest
  static void executeForAsset_shouldReturnSuccessWhenAllDependenciesAreValid() {
    // Given a fully-mocked processor where every collaborator succeeds

    // Reset mock counters; set sendEmailValueOnCreate=false so the processor does
    // NOT attempt `update licenseKey` (which would fail with no real inserted record)
    LkgMapperFactoryMock.mapperFactoryCallCount = 0;
    LkgRecordCreatorMock.reset();
    LkgRecordCreatorMock.sendEmailValueOnCreate = false;

    // When
    Test.startTest();
    LkgKeyGenResponse response = processorFullMock.executeForAsset(payloadJson);
    Test.stopTest();

    // Then
    System.Assert.isTrue(
      response.isSuccess,
      'executeForAsset() should return a success response when all dependencies are valid.'
    );
    System.Assert.areEqual(
      1,
      LkgMapperFactoryMock.mapperFactoryCallCount,
      'Mapper factory should be called exactly once.'
    );
  }

  // ─── executeForHardwareRecords — payload-validation tests ─────────────────

  @isTest
  static void executeForHardwareRecords_shouldReturnErrorWhenPayloadIsNull() {
    // Given a null hardware payload

    // When
    Test.startTest();
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response =
      processorFullMock.executeForHardwareRecords(null);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.overallSuccess,
      'executeForHardwareRecords() should report failure when payload is null.'
    );
    System.Assert.isTrue(
      response.message.contains('No hardware records provided'),
      'Error message should indicate that no hardware records were provided.'
    );
  }

  @isTest
  static void executeForHardwareRecords_shouldReturnErrorWhenHardwareRecordsListIsNull() {
    // Given a payload with null hardwareRecords list
    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.hardwareRecords = null;

    // When
    Test.startTest();
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response =
      processorFullMock.executeForHardwareRecords(payload);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.overallSuccess,
      'executeForHardwareRecords() should report failure when hardwareRecords is null.'
    );
  }

  @isTest
  static void executeForHardwareRecords_shouldReturnErrorWhenHardwareRecordsListIsEmpty() {
    // Given a payload with an empty hardwareRecords list
    LkgProcessorHardwareKeys.HardwarePayload payload = new LkgProcessorHardwareKeys.HardwarePayload();
    payload.source = 'hardware';
    payload.hardwareRecords = new List<LkgProcessorHardwareKeys.HardwareRecord>();

    // When
    Test.startTest();
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response =
      processorFullMock.executeForHardwareRecords(payload);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      response.overallSuccess,
      'executeForHardwareRecords() should report failure when hardwareRecords list is empty.'
    );
    System.Assert.isTrue(
      response.message.contains('No hardware records provided'),
      'Error message should indicate that no hardware records were provided.'
    );
  }
}