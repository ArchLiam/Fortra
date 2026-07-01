@isTest
public with sharing class AutomateTierBLegacyPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static ILkgAutomatePointsBuilder pointsBuilder = new AutomateTierBLegacyPointsBuilder();
  private static final String EXPECTED_POINTS = 'S2B1K524287L16383M1023N262143P2047Q16383';

  static {
    context.isGte11 = false;
  }

  @isTest
  static void build_ShouldReturnCorrectPoints() {
    // Given a context with specific actions and release
    // When we build points using the Tier B legacy points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return the correct points string
    System.assertEquals(EXPECTED_POINTS, points, 'The points string should match the expected value');
  }
}