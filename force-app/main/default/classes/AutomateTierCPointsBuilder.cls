public with sharing class AutomateTierCPointsBuilder extends AutomatePointsBuilderBase {
  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 3);
    pointsMap.put('K', 524287);
    pointsMap.put('L', 16383);
    pointsMap.put('M', 1023);
    pointsMap.put('N', 262143);
    pointsMap.put('P', 524287);
    pointsMap.put('Q', 32767);
    pointsMap.put('T', 35);
  }
}