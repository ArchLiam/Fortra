@isTest
public with sharing class AutomateTierCLegacyPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static AutomateTierCLegacyPointsBuilder pointsBuilder = new AutomateTierCLegacyPointsBuilder();
  private static final String EXPECTED_POINTS = 'S1C1';

  static {
    context.isGte11 = false;
  }

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    // When we build points using the Tier C Legacy points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }
}