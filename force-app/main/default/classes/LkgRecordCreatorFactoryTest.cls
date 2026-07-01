@isTest
public with sharing class LkgRecordCreatorFactoryTest {
  private static LkgRecordCreatorFactory factory;

  static {
    factory = new LkgRecordCreatorFactory();
  }

  @isTest
  static void getRecordCreator_shouldReturnNullForUnknownSilo() {
    // Given an unknown silo
    String silo = 'unknown';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then the result should be null
    System.Assert.isNull(creator, 'Record creator should be null for unknown silo.');
  }

  @isTest
  static void getRecordCreatorClearswift_shouldReturnClearswiftCreator() {
    // Given a clearswift silo
    String silo = 'clearswift';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Clearswift record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorClearswift,
      'Clearswift record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorPowertech_shouldReturnPowertechCreator() {
    // Given a powertech silo
    String silo = 'powertech';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Powertech record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorPowerTech, 'Powertech record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorSafestone_shouldReturnPowertechCreator() {
    // Given a safestone silo
    String silo = 'safestone';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Powertech record creator should be returned for Safestone silo
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorPowerTech,
      'Powertech record creator should be returned for Safestone silo.'
    );
  }

  @isTest
  static void getRecordCreatorSgav_shouldReturnPowertechCreator() {
    // Given a SGAV silo
    String silo = 'sgav';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Powertech record creator should be returned for SGAV silo
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorPowerTech,
      'Powertech record creator should be returned for SGAV silo.'
    );
  }

  @isTest
  static void getRecordCreatorBytware_shouldReturnPowertechCreator() {
    // Given a Bytware silo
    String silo = 'bytware';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Powertech record creator should be returned for Bytware silo
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorPowerTech,
      'Powertech record creator should be returned for Bytware silo.'
    );
  }

  @isTest
  static void getRecordCreatorCcss_shouldReturnPowertechCreator() {
    // Given a ccss silo
    String silo = 'ccss';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Powertech record creator should be returned for CCSS silo
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorPowerTech,
      'Powertech record creator should be returned for CCSS silo.'
    );
  }

  @isTest
  static void getRecordCreatorAccessAuth_shouldReturnAccessAuthCreator() {
    // Given an accessauth silo
    String silo = 'accessauth';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a AccessAuth record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorAccessAuth,
      'AccessAuth record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorSecurityScan_shouldReturnAccessAuthCreator() {
    // Given a securityscan silo
    String silo = 'securityscan';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a AccessAuth record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorAccessAuth,
      'AccessAuth record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorLegacyIbm_shouldReturnLegacyIbmCreator() {
    // Given a legacyibm silo
    String silo = 'legacyibm';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a LegacyIbm record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorLegacyIbm, 'LegacyIbm record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorSgavx_shouldReturnSgavxCreator() {
    // Given a sgavx silo
    String silo = 'sgavx';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Sgavx record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorSgavx, 'Sgavx record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorRobot_shouldReturnRobotCreator() {
    // Given a robot silo
    String silo = 'robot';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Robot record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorRobot, 'Robot record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorRsf_shouldReturnRSFCreator() {
    // Given a rsf silo
    String silo = 'rsf';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a RSF record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorRSF, 'RSF record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorDocM_shouldReturnDocMCreator() {
    // Given a docm silo
    String silo = 'docm';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a DocM record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorDocM, 'DocM record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorSequel_shouldReturnSequelCreator() {
    // Given a sequel silo
    String silo = 'sequel';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Sequel record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorSequel, 'Sequel record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorSequelWeb_shouldReturnSequelWebCreator() {
    // Given a sequelweb silo
    String silo = 'sequelweb';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a SequelWeb record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorSequelWeb, 'SequelWeb record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorQueryBuilder_shouldReturnSequelQueryBuilderCreator() {
    // Given a querybuilder silo
    String silo = 'querybuilder';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a SequelQueryBuilder record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorSequelQueryBuilder,
      'SequelQueryBuilder record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorIntermapper_shouldReturnIntermapperCreator() {
    // Given an intermapper silo
    String silo = 'intermapper';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then an Intermapper record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorIntermapper,
      'Intermapper record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorVityl_shouldReturnVitylCreator() {
    // Given a vityl silo
    String silo = 'vityl';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Vityl record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorVityl, 'Vityl record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorTqJava_shouldReturnTQSurveyorCreator() {
    // Given a tqjava silo
    String silo = 'tqjava';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a TQSurveyor record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorTQSurveyor,
      'TQSurveyor record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorPtMulti_shouldReturnPtMultiCreator() {
    // Given a ptmulti silo
    String silo = 'ptmulti';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a PtMulti record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorPtMulti, 'PtMulti record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorHalcyonIbm_shouldReturnHalcyonIbmCreator() {
    // Given a halcyon silo with ibm sub-silo
    String silo = 'halcyon';
    String subSilo = 'ibm';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo, subSilo);
    Test.stopTest();

    // Then a Halcyon IBM record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(
      creator instanceof LkgRecordCreatorHalcyonIbm,
      'Halcyon IBM record creator should be returned.'
    );
  }

  @isTest
  static void getRecordCreatorHalcyonUnknownSubSilo_shouldReturnNull() {
    // Given a halcyon silo with unsupported sub-silo
    String silo = 'halcyon';
    String subSilo = 'cod';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo, subSilo);
    Test.stopTest();

    // Then null should be returned
    System.Assert.isNull(creator, 'Record creator should be null for unsupported Halcyon sub-silo.');
  }

  @isTest
  static void getRecordCreatorAutomate_shouldReturnAutomateCreator() {
    // Given an automate silo
    String silo = 'automate';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then an Automate record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorAutomate, 'Automate record creator should be returned.');
  }

  @isTest
  static void getRecordCreatorFortra_shouldReturnFortraCreator() {
    // Given a fortra silo
    String silo = 'fortra';

    // When getRecordCreator is called
    Test.startTest();
    ILkgRecordCreator creator = factory.getRecordCreator(silo);
    Test.stopTest();

    // Then a Fortra record creator should be returned
    System.Assert.isNotNull(creator, 'Record creator should not be null.');
    System.Assert.isTrue(creator instanceof LkgRecordCreatorFortra, 'Fortra record creator should be returned.');
  }
}