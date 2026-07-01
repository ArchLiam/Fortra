@isTest
public with sharing class LkgAutomatePointsBuilderFactoryTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();

  @isTest
  static void getBuilderNullInputs_ShouldReturnDefaultBuilder() {
    // Given null inputs
    context.productCode = null;
    context.tier = null;
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the default points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateDefaultPointsBuilder,
      'The builder should be an instance of AutomateDefaultPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutAGte11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier A, and GTE11
    context.productCode = 'AUT';
    context.tier = 'A';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier A points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierAPointsBuilder,
      'The builder should be an instance of AutomateTierAPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutALt11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier A, and LT11
    context.productCode = 'AUT';
    context.tier = 'A';
    context.isGte11 = false;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier A Legacy points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierALegacyPointsBuilder,
      'The builder should be an instance of AutomateTierALegacyPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutBGte11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier B, and GTE11
    context.productCode = 'AUT';
    context.tier = 'B';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier B points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierBPointsBuilder,
      'The builder should be an instance of AutomateTierBPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutBLt11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier B, and LT11
    context.productCode = 'AUT';
    context.tier = 'B';
    context.isGte11 = false;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier B Legacy points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierBLegacyPointsBuilder,
      'The builder should be an instance of AutomateTierBLegacyPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutCGte11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier C, and GTE11
    context.productCode = 'AUT';
    context.tier = 'C';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier C points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierCPointsBuilder,
      'The builder should be an instance of AutomateTierCPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutCLt11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier C, and LT11
    context.productCode = 'AUT';
    context.tier = 'C';
    context.isGte11 = false;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier C Legacy points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierCLegacyPointsBuilder,
      'The builder should be an instance of AutomateTierCLegacyPointsBuilder'
    );
  }

  @isTest
  static void getBuilderAutDGte11_ShouldReturnCorrectBuilder() {
    // Given an AUT product, Tier D, and GTE11
    context.productCode = 'AUT';
    context.tier = 'D';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier D points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof AutomateTierDPointsBuilder,
      'The builder should be an instance of AutomateTierDPointsBuilder'
    );
  }

  @isTest
  static void getBuilderBpaAGte11_ShouldReturnCorrectBuilder() {
    // Given a BPA product, Tier A, and GTE11
    context.productCode = 'BPA';
    context.tier = 'A';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier A points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof BpaTierAPointsBuilder,
      'The builder should be an instance of BpaTierAPointsBuilder'
    );
  }

  @isTest
  static void getBuilderBpaALt11_ShouldReturnCorrectBuilder() {
    // Given a BPA product, Tier A, and LT11
    context.productCode = 'BPA';
    context.tier = 'A';
    context.isGte11 = false;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier A legacy points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof BpaTierALegacyPointsBuilder,
      'The builder should be an instance of BpaTierALegacyPointsBuilder'
    );
  }

  @isTest
  static void getBuilderBpaCGte11_ShouldReturnCorrectBuilder() {
    // Given a BPA product, Tier C, and GTE11
    context.productCode = 'BPA';
    context.tier = 'C';
    context.isGte11 = true;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier C points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof BpaTierCPointsBuilder,
      'The builder should be an instance of BpaTierCPointsBuilder'
    );
  }

  @isTest
  static void getBuilderBpaCLt11_ShouldReturnCorrectBuilder() {
    // Given a BPA product, Tier C, and LT11
    context.productCode = 'BPA';
    context.tier = 'C';
    context.isGte11 = false;

    // When calling getBuilder
    Test.startTest();
    ILkgAutomatePointsBuilder builder = LkgAutomatePointsBuilderFactory.getBuilder(context);
    Test.stopTest();

    // Then it should return the Tier C legacy points builder
    System.assertNotEquals(null, builder, 'The builder should not be null');
    System.assert(
      builder instanceof BpaTierCLegacyPointsBuilder,
      'The builder should be an instance of BpaTierCLegacyPointsBuilder'
    );
  }
}