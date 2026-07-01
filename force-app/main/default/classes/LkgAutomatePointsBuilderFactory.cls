public with sharing class LkgAutomatePointsBuilderFactory {
  private static final Map<String, ILkgAutomatePointsBuilder> pointsBuilderMap = new Map<String, ILkgAutomatePointsBuilder>{
    'AUT_A_GTE11' => new AutomateTierAPointsBuilder(),
    'AUT_A_LT11' => new AutomateTierALegacyPointsBuilder(),
    'AUT_B_GTE11' => new AutomateTierBPointsBuilder(),
    'AUT_B_LT11' => new AutomateTierBLegacyPointsBuilder(),
    'AUT_C_GTE11' => new AutomateTierCPointsBuilder(),
    'AUT_C_LT11' => new AutomateTierCLegacyPointsBuilder(),
    'AUT_D_GTE11' => new AutomateTierDPointsBuilder(),
    'AUT_D_LT11' => new AutomateTierDPointsBuilder(),
    'BPA_A_GTE11' => new BpaTierAPointsBuilder(),
    'BPA_A_LT11' => new BpaTierALegacyPointsBuilder(),
    'BPA_C_GTE11' => new BpaTierCPointsBuilder(),
    'BPA_C_LT11' => new BpaTierCLegacyPointsBuilder()
  };

  public static ILkgAutomatePointsBuilder getBuilder(AutomatePointsBuilderContext context) {
    if (String.isBlank(context.productCode) || String.isBlank(context.tier)) {
      return new AutomateDefaultPointsBuilder();
    }

    String key = context.productCode + '_' + context.tier + '_' + (context.isGte11 ? 'GTE11' : 'LT11');
    ILkgAutomatePointsBuilder builder = pointsBuilderMap.get(key);
    if (builder == null)
      throw new IllegalArgumentException('No points builder found for key: ' + key);
    return builder;
  }
}