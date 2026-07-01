@isTest
public with sharing class AutomateDefaultPointsBuilderTest {
  private static AutomatePointsBuilderContext context = new AutomatePointsBuilderContext();
  private static ILkgAutomatePointsBuilder pointsBuilder = new AutomateDefaultPointsBuilder();

  static {
    context.isGte11 = true;
  }

  @isTest
  static void buildGte11_ShouldReturnDefaultPoints() {
    // Given a context with no tier and isGte11 as true
    // When we build points using the default points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return 'S1' as the default points
    System.assertEquals('S1', points, 'The default points should be S1');
  }

  @isTest
  static void buildLt11_ShouldReturnDefaultPoints() {
    // Given a context with no tier and isGte11 as false
    context.isGte11 = false;

    // When we build points using the default points builder
    Test.startTest();
    String points = pointsBuilder.build(context);
    Test.stopTest();

    // Then it should return 'S1' as the default points
    System.assertEquals('S1', points, 'The default points should be S1');
  }
}