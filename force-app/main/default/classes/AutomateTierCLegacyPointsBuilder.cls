public with sharing class AutomateTierCLegacyPointsBuilder extends AutomatePointsBuilderBase {
  protected override void populatePointsMap(AutomatePointsBuilderContext context) {
    pointsMap.put('S', 1);
    pointsMap.put('C', 1);
  }
}