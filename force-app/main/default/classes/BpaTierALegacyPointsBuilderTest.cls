@IsTest
public with sharing class BpaTierALegacyPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static BpaTierALegacyPointsBuilder pointsBuilder = new BpaTierALegacyPointsBuilder();

  static {
    context.isGte11 = false;
    context.release = null;
    context.bots = 5;
    context.studios = 3;
    context.websmcs = 2;
  }
  private static final String EXPECTED_POINTS =
    'S2A1B1K524287L16383M1023N262143P2047Q16383E' +
    context.bots +
    'F' +
    context.studios +
    'G' +
    context.websmcs;

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // When we build points using the Tier A Legacy points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }
}