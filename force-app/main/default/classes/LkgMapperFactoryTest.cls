@isTest
private class LkgMapperFactoryTest {
  private static LkgMapperFactory mapperFactory;
  static final LkgMapperBase.UiPayload testPayload;

  static {
    testPayload = new LkgMapperBase.UiPayload();
    testPayload.productData = new LkgMapperBase.ProductData();
    testPayload.productData.subSilo = null;
    mapperFactory = new LkgMapperFactory();
  }

  @isTest
  static void getMapper_shouldNotReturnNull() {
    // Given a Powertech payload
    testPayload.productData.silo = 'powertech';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a mapper should be returned
    System.Assert.isNotNull(mapper, 'Mapper should be returned.');
  }

  @isTest
  static void getMapperPowertech_shouldReturnPowertechMapper() {
    // Given a Powertech payload
    testPayload.productData.silo = 'powertech';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Powertech mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperPowertech, 'Powertech mapper should be returned.');
  }

  @isTest
  static void getMapperSafestone_shouldReturnPowertechMapper() {
    // Given a Safestone payload
    testPayload.productData.silo = 'safestone';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Powertech mapper should be returned
    System.Assert.isTrue(
      mapper instanceof LkgMapperPowertech,
      'Powertech mapper should be returned for Safestone silo.'
    );
  }

  @isTest
  static void getMapperSgav_shouldReturnPowertechMapper() {
    // Given a SGAV payload
    testPayload.productData.silo = 'sgav';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Powertech mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperPowertech, 'Powertech mapper should be returned for SGAV silo.');
  }

  @isTest
  static void getMapperBytware_shouldReturnPowertechMapper() {
    // Given a Bytware payload
    testPayload.productData.silo = 'bytware';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Powertech mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperPowertech, 'Powertech mapper should be returned for Bytware silo.');
  }

  @isTest
  static void getMapperCcss_shouldReturnPowertechMapper() {
    // Given a CCSS payload
    testPayload.productData.silo = 'ccss';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Powertech mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperPowertech, 'Powertech mapper should be returned for CCSS silo.');
  }

  @isTest
  static void getMapperClearswift_shouldReturnClearswiftMapper() {
    // Given a Clearswift payload
    testPayload.productData.silo = 'clearswift';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Clearswift mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperClearswift, 'Clearswift mapper should be returned.');
  }

  @isTest
  static void getMapperAccessAuth_shouldReturnAccessAuthMapper() {
    // Given an AccessAuth payload
    testPayload.productData.silo = 'accessauth';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then an AccessAuth mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperAccessAuth, 'AccessAuth mapper should be returned.');
  }

  @isTest
  static void getMapperSecurityScan_shouldReturnAccessAuthMapper() {
    // Given a SecurityScan payload
    testPayload.productData.silo = 'securityscan';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then an AccessAuth mapper should be returned
    System.Assert.isTrue(
      mapper instanceof LkgMapperAccessAuth,
      'AccessAuth mapper should be returned for SecurityScan silo.'
    );
  }

  @isTest
  static void getMapperLegacyIbm_shouldReturnLegacyIbmMapper() {
    // Given a Legacy IBM payload
    testPayload.productData.silo = 'legacyibm';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Legacy IBM mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperLegacyIbm, 'Legacy IBM mapper should be returned.');
  }

  @isTest
  static void getMapperSgavx_shouldReturnSgavxMapper() {
    // Given a SGAVX payload
    testPayload.productData.silo = 'sgavx';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a SGAVX mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperSgavx, 'SGAVX mapper should be returned.');
  }

  @isTest
  static void getMapperRobot_shouldReturnRobotMapper() {
    // Given a Robot payload
    testPayload.productData.silo = 'robot';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Robot mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperRobot, 'Robot mapper should be returned.');
  }

  @isTest
  static void getMapperRsf_shouldReturnRsfMapper() {
    // Given a RSF payload
    testPayload.productData.silo = 'rsf';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a RSF mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperRSF, 'RSF mapper should be returned.');
  }

  @isTest
  static void getMapperAutomate_shouldReturnAutomateMapper() {
    // Given an Automate payload
    testPayload.productData.silo = 'automate';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then an Automate mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperAutomate, 'Automate mapper should be returned.');
  }

  @isTest
  static void getMapperNoSilo_shouldReturnNull() {
    // Given a payload with no silo
    testPayload.productData.silo = null;
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then null should be returned
    System.Assert.isNull(mapper, 'Null should be returned.');
  }

  @isTest
  static void getMapperDocM_shouldReturnDocMMapper() {
    // Given a DocM payload
    testPayload.productData.silo = 'docm';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a DocM mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperDocM, 'DocM mapper should be returned.');
  }

  @isTest
  static void getMapperSequel_shouldReturnSequelMapper() {
    // Given a Sequel payload
    testPayload.productData.silo = 'sequel';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Sequel mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperSequel, 'Sequel mapper should be returned.');
  }

  @isTest
  static void getMapperSequelWeb_shouldReturnSequelWebMapper() {
    // Given a SequelWeb payload
    testPayload.productData.silo = 'sequelweb';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a SequelWeb mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperSequelWeb, 'SequelWeb mapper should be returned.');
  }

  @isTest
  static void getMapperQueryBuilder_shouldReturnSequelQueryBuilderMapper() {
    // Given a QueryBuilder payload
    testPayload.productData.silo = 'querybuilder';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a SequelQueryBuilder mapper should be returned
    System.Assert.isTrue(
      mapper instanceof LkgMapperSequelQueryBuilder,
      'SequelQueryBuilder mapper should be returned.'
    );
  }

  @isTest
  static void getMapperTqJava_shouldReturnTQSurveyorMapper() {
    // Given a TQJava payload
    testPayload.productData.silo = 'tqjava';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a TQSurveyor mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperTQSurveyor, 'TQSurveyor mapper should be returned.');
  }

  @isTest
  static void getMapperIntermapper_shouldReturnIntermapperMapper() {
    // Given an Intermapper payload
    testPayload.productData.silo = 'intermapper';
    testPayload.productData.subSilo = null;
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then an Intermapper mapper should be returned
    System.Assert.isNotNull(mapper, 'Mapper should not be null.');
    System.Assert.isTrue(mapper instanceof LkgMapperIntermapper, 'Intermapper mapper should be returned.');
  }

  @isTest
  static void getMapperVityl_shouldReturnVitylMapper() {
    // Given a Vityl payload
    testPayload.productData.silo = 'vityl';
    testPayload.productData.subSilo = null;
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Vityl mapper should be returned
    System.Assert.isNotNull(mapper, 'Mapper should not be null.');
    System.Assert.isTrue(mapper instanceof LkgMapperVityl, 'Vityl mapper should be returned.');
  }

  @isTest
  static void getMapperHalcyonIbm_shouldReturnHalcyonIbmMapper() {
    // Given a Halcyon IBM payload
    testPayload.productData.silo = 'halcyon';
    testPayload.productData.subSilo = 'ibm';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Halcyon IBM mapper should be returned
    System.Assert.isNotNull(mapper, 'Mapper should not be null.');
    System.Assert.isTrue(mapper instanceof LkgMapperHalcyonIbm, 'Halcyon IBM mapper should be returned.');
  }

  @isTest
  static void getMapperPtMulti_shouldReturnPtMultiMapper() {
    // Given a PtMulti payload
    testPayload.productData.silo = 'ptmulti';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a PtMulti mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperPtMulti, 'PtMulti mapper should be returned.');
  }

  @isTest
  static void getMapperHalcyonUnknownSubSilo_shouldReturnNull() {
    // Given a Halcyon payload with unsupported sub-silo
    testPayload.productData.silo = 'halcyon';
    testPayload.productData.subSilo = 'cod';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then null should be returned
    System.Assert.isNull(mapper, 'Null should be returned for unsupported Halcyon sub-silo.');
  }

  @isTest
  static void getMapperFortra_shouldReturnFortraMapper() {
    // Given a Fortra payload
    testPayload.productData.silo = 'fortra';
    String payloadJson = JSON.serialize(testPayload);

    // When the mapper factory is called
    Test.startTest();
    ILkgMapper mapper = mapperFactory.getMapper(payloadJson);
    Test.stopTest();

    // Then a Fortra mapper should be returned
    System.Assert.isTrue(mapper instanceof LkgMapperFortra, 'Fortra mapper should be returned.');
  }
}