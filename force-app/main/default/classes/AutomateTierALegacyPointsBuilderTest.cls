@isTest
public with sharing class AutomateTierALegacyPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static AutomateTierALegacyPointsBuilder builder = new AutomateTierALegacyPointsBuilder();

  static {
    context.isGte11 = false;
    context.MActions = 5;
    context.NActions = 10;
    context.PActions = 3;
  }

  private static final String EXPECTED_POINTS =
    'S2A1K524287L16383Q8191M' +
    (8 + context.MActions) +
    'N' +
    (204672 + context.NActions) +
    'P' +
    (1791 + context.PActions);

  @isTest
  static void build_ShouldReturnPoints() {
    // Given a context for Tier A legacy
    // When we build points using the Tier A legacy points builder
    Test.startTest();
    String points = builder.build(context);
    Test.stopTest();

    // Then it should return the expected points for Tier A legacy
    System.assertEquals(EXPECTED_POINTS, points, 'The points for Tier A legacy should match the expected value');
  }
}