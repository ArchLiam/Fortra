@isTest
public with sharing class AutomateTierDPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static AutomateTierDPointsBuilder pointsBuilder = new AutomateTierDPointsBuilder();
  private static final String EXPECTED_POINTS = 'S3K13858L1636M64N128P44Q16387T32819';

  @isTest
  static void buildLt11_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    context.isGte11 = false;

    // When we build points using the Tier D points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }

  @isTest
  static void buildGte11_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    context.isGte11 = true;

    // When we build points using the Tier D points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }

  @isTest
  static void buildWithRelease_ShouldNotIncludeVersionTier() {
    // Given a context with release 24
    context.isGte11 = true;
    context.release = 24;

    // When we build points using the Tier D points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should not include the version tier in the points string
    System.assertEquals(EXPECTED_POINTS + 'V24', points, 'The points string should not include the version tier');
  }
}