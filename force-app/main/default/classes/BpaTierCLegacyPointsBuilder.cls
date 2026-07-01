public with sharing class BpaTierCLegacyPointsBuilder extends AutomatePointsBuilderBase {
  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 2);
    pointsMap.put('C', 1);
    pointsMap.put('D', 1);
    pointsMap.put('K', 524287);
    pointsMap.put('L', 16383);
    pointsMap.put('M', 1023);
    pointsMap.put('N', 262143);
    pointsMap.put('P', 2047);
    pointsMap.put('Q', 16383);
    pointsMap.put('E', context.bots);
    pointsMap.put('F', context.studios);
    pointsMap.put('G', context.websmcs);
  }
}