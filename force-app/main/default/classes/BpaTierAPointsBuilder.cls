public with sharing class BpaTierAPointsBuilder extends AutomatePointsBuilderBase {
  private static final Integer T_BASE_POINTS = 3635;

  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 3);
    pointsMap.put('K', 524287);
    pointsMap.put('L', 16383);
    pointsMap.put('M', 1023);
    pointsMap.put('N', 262143);
    pointsMap.put('P', 524287);
    pointsMap.put('Q', 32767);
    pointsMap.put('T', T_BASE_POINTS + context.TActions);
    pointsMap.put('E', context.bots);
    pointsMap.put('F', context.studios);
    pointsMap.put('G', context.websmcs);
  }
}