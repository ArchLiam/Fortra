@isTest
public with sharing class AutomateTierBPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static ILkgAutomatePointsBuilder pointsBuilder = new AutomateTierBPointsBuilder();

  static {
    context.isGte11 = true;
  }

  private static final String EXPECTED_POINTS = 'S3K524287L16383M1023N262143P524287Q32767T65523';

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    // When we build points using the Tier B points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }

  @isTest
  static void buildWithRelease_ShouldNotIncludeVersionTier() {
    // Given a context with release 24
    context.release = 24;

    // When we build points using the Tier B points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should not include the version tier in the points string
    System.assertEquals(EXPECTED_POINTS + 'V24', points, 'The points string should not include the version tier');
  }
}