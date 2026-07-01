public with sharing class AutomateTierALegacyPointsBuilder extends AutomatePointsBuilderBase {
  private static final Integer M_BASE_POINTS = 8;
  private static final Integer N_BASE_POINTS = 204672;
  private static final Integer P_BASE_POINTS = 1791;

  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 2);
    pointsMap.put('A', 1);
    pointsMap.put('K', 524287);
    pointsMap.put('L', 16383);
    pointsMap.put('Q', 8191);
    pointsMap.put('M', M_BASE_POINTS + context.MActions);
    pointsMap.put('N', N_BASE_POINTS + context.NActions);
    pointsMap.put('P', P_BASE_POINTS + context.PActions);
  }
}