public with sharing abstract class AutomatePointsBuilderBase implements ILkgAutomatePointsBuilder {
  protected Map<String, Integer> pointsMap = new Map<String, Integer>();

  public String build(AutomatePointsBuilderContext context) {
    populatePointsMap(context);
    return buildPointsString(context);
  }

  protected abstract void populatePointsMap(AutomatePointsBuilderContext context);

  private String buildPointsString(AutomatePointsBuilderContext context) {
    String result = '';
    for (String key : pointsMap.keySet()) {
      result += key + pointsMap.get(key);
    }
    result += addVersionTier(context);
    return result;
  }

  private String addVersionTier(AutomatePointsBuilderContext context) {
    if (context.isGte11 && context.release != null) {
      return 'V' + context.release;
    } else {
      return '';
    }
  }
}