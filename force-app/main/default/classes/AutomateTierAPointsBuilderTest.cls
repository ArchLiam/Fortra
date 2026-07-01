@isTest
public with sharing class AutomateTierAPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static ILkgAutomatePointsBuilder pointsBuilder = new AutomateTierAPointsBuilder();

  static {
    context.isGte11 = true;
    context.MActions = 3;
    context.NActions = 2;
    context.PActions = 1;
  }

  private static final String EXPECTED_POINTS = 'S3K524287L16383Q8191T19M11N204674P521984';

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    // When we build points using the Tier A points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }

  @isTest
  static void buildWithRelease_ShouldIncludeVersionTier() {
    // Given a context with release 24
    context.release = 24;

    // When we build points using the Tier A points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should include the version tier in the points string
    System.assertEquals(EXPECTED_POINTS + 'V24', points, 'The points string should include the version tier');
  }
}