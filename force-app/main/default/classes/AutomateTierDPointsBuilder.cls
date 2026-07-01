public with sharing class AutomateTierDPointsBuilder extends AutomatePointsBuilderBase {
  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 3);
    pointsMap.put('K', 13858);
    pointsMap.put('L', 1636);
    pointsMap.put('M', 64);
    pointsMap.put('N', 128);
    pointsMap.put('P', 44);
    pointsMap.put('Q', 16387);
    pointsMap.put('T', 32819);
  }
}