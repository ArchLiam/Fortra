@isTest
public with sharing class BpaTierAPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static BpaTierAPointsBuilder pointsBuilder = new BpaTierAPointsBuilder();
  private static final Integer T_BASE_POINTS = 3635;

  static {
    context.isGte11 = true;
    context.bots = 5;
    context.studios = 3;
    context.websmcs = 2;
    context.TActions = 10;
  }

  private static final String EXPECTED_POINTS =
    'S3K524287L16383M1023N262143P524287Q32767' +
    'T' +
    (T_BASE_POINTS + context.TActions) +
    'E' +
    context.bots +
    'F' +
    context.studios +
    'G' +
    context.websmcs;

  @isTest
  static void build_ShouldReturnCorrectPoints() {
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