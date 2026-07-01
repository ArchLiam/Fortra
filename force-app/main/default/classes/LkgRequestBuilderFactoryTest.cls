@isTest
private class LkgRequestBuilderFactoryTest {
  private static LkgRequestBuilderFactory factory;

  //setup
  static {
    factory = new LkgRequestBuilderFactory();
  }

  @isTest
  static void getRequestBuilderClearswift_ShouldReturnCorrectBuilder() {
    // Given the clearswift silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('clearswift');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderClearswift, 'Clearswift builder should be returned.');
  }

  @isTest
  static void getRequestBuilderPowerTech_ShouldReturnCorrectBuilder() {
    // Given the powertech silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('powertech');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPowerTech, 'Powertech builder should be returned.');
  }

  @isTest
  static void getRequestBuilderSafestone_ShouldReturnCorrectBuilder() {
    // Given the safestone silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('safestone');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPowerTech, 'Powertech builder should be returned.');
  }

  @isTest
  static void getRequestBuilderAccessAuth_ShouldReturnCorrectBuilder() {
    // Given the accessauth silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('accessauth');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderAccessAuth, 'Accessauth builder should be returned.');
  }

  @isTest
  static void getRequestBuilderSecurityScan_ShouldReturnCorrectBuilder() {
    // Given the securityscan silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('securityscan');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderAccessAuth, 'Accessauth builder should be returned.');
  }

  @isTest
  static void getRequestBuilderSgav_ShouldReturnCorrectBuilder() {
    // Given the sgav silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('sgav');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPowerTech, 'PowerTech builder should be returned.');
  }

  @isTest
  static void getRequestBuilderSgavx_ShouldReturnCorrectBuilder() {
    // Given the sgavx silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('sgavx');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderSgavx, 'SGAVX should be returned.');
  }

  @isTest
  static void getRequestBuilderLegacyIbm_ShouldReturnCorrectBuilder() {
    // Given the sgavx silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('legacyibm');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderLegacyIbm, 'Legacy IBM should be returned.');
  }

  @isTest
  static void getRequestBuilderBytware_ShouldReturnCorrectBuilder() {
    // Given the bytware silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('bytware');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPowerTech, 'Power Tech should be returned.');
  }

  @isTest
  static void getRequestBuilderCcss_ShouldReturnCorrectBuilder() {
    // Given the ccss silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('ccss');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPowerTech, 'PowerTech builder should be returned.');
  }

  @isTest
  static void getRequestBuilderPtMulti_ShouldReturnCorrectBuilder() {
    // Given the ptmulti silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('ptmulti');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderPtMulti, 'PT Multi should be returned.');
  }

  @isTest
  static void getRequestBuilderTqJava_ShouldReturnCorrectBuilder() {
    // Given the tq silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('tqjava');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderTQSurveyor, 'TeamQuest Surveyor should be returned.');
  }

  @isTest
  static void getRequestBuilderRsf_ShouldReturnCorrectBuilder() {
    // Given the rsf silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('rsf');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderRSF, 'RSF builder should be returned.');
  }

  @isTest
  static void getRequestBuilderRobot_ShouldReturnCorrectBuilder() {
    // Given the robot silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('robot');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderRobot, 'Robot builder should be returned.');
  }

  @isTest
  static void getRequestBuilderDocM_ShouldReturnCorrectBuilder() {
    // Given the docm silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('docm');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderDocM, 'DocM builder should be returned.');
  }

  @isTest
  static void getRequestBuilderSequel_ShouldReturnCorrectBuilder() {
    // Given the sequel silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('sequel');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderSequel, 'Sequel builder should be returned.');
  }

  @isTest
  static void getRequestBuilderQueryBuilder_ShouldReturnCorrectBuilder() {
    // Given the querybuilder silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('querybuilder');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(
      builder instanceof LkgRequestBuilderSequelQueryBuilder,
      'SequelQueryBuilder builder should be returned.'
    );
  }

  @isTest
  static void getRequestBuilderSequelWeb_ShouldReturnCorrectBuilder() {
    // Given the sequelweb silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('sequelweb');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderSequelWeb, 'SequelWeb builder should be returned.');
  }

  @isTest
  static void getRequestBuilderUnknownSilo_ShouldReturnNull() {
    // Given an unknown silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('unknown');
    Test.stopTest();

    // Then null should be returned
    System.Assert.isNull(builder, 'Null should be returned for unknown silo.');
  }

  @isTest
  static void getRequestBuilderHalcyonIbm_ShouldReturnCorrectBuilder() {
    // Given the halcyon silo and ibm subsilo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('halcyon', 'ibm');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderHalcyonIbm, 'Halcyon IBM should be returned.');
  }

  @isTest
  static void getRequestBuilderHalcyonUnknownSubSilo_ShouldReturnNull() {
    // Given the halcyon silo and unsupported subsilo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('halcyon', 'unknown');
    Test.stopTest();

    // Then null should be returned
    System.Assert.isNull(builder, 'Null should be returned for unsupported Halcyon sub-silo.');
  }

  @isTest
  static void getRequestBuilderIntermapper_ShouldReturnCorrectBuilder() {
    // Given the intermapper silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('intermapper');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderIntermapper, 'Intermapper should be returned.');
  }

  @isTest
  static void getRequestBuilderVityl_ShouldReturnCorrectBuilder() {
    // Given the vityl silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('vityl');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderVityl, 'Vityl should be returned.');
  }

  @isTest
  static void getRequestBuilderAutomate_ShouldReturnCorrectBuilder() {
    // Given the automate silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('automate');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderAutomate, 'Automate should be returned.');
  }

  @isTest
  static void getRequestBuilderFortra_ShouldReturnCorrectBuilder() {
    // Given the fortra silo
    // When requesting a builder
    Test.startTest();
    ILkgRequestBuilder builder = LkgRequestBuilderFactoryTest.factory.getRequestBuilder('fortra');
    Test.stopTest();

    // Then the correct request builder should be returned
    System.Assert.isTrue(builder instanceof LkgRequestBuilderFortra, 'Fortra should be returned.');
  }
}