@isTest
public with sharing class BpaTierCLegacyPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static BpaTierCLegacyPointsBuilder pointsBuilder = new BpaTierCLegacyPointsBuilder();

  static {
    context.isGte11 = false;
    context.bots = 5;
    context.studios = 3;
    context.websmcs = 2;
  }

  private static final String EXPECTED_POINTS =
    'S2C1D1K524287L16383M1023N262143P2047Q16383E' +
    context.bots +
    'F' +
    context.studios +
    'G' +
    context.websmcs;

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // When we build points using the Tier C Legacy points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }
}