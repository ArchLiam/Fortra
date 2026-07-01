@isTest
private class LkgHardwareKeyParamBuilderFactoryTest {

  @isTest
  static void getBuilder_shouldReturnNullWhenSiloIsNull() {
    // Given a null silo string

    // When
    Test.startTest();
    ILkgHardwareKeyParamBuilder result = LkgHardwareKeyParamBuilderFactory.getBuilder(null);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'getBuilder() should return null when silo is null.');
  }

  @isTest
  static void getBuilder_shouldReturnNullWhenSiloIsBlank() {
    // Given a blank silo string

    // When
    Test.startTest();
    ILkgHardwareKeyParamBuilder result = LkgHardwareKeyParamBuilderFactory.getBuilder('');
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'getBuilder() should return null when silo is blank.');
  }

  @isTest
  static void getBuilder_shouldReturnAutomateBuilderForAutomateSilo() {
    // Given the 'automate' silo name

    // When
    Test.startTest();
    ILkgHardwareKeyParamBuilder result = LkgHardwareKeyParamBuilderFactory.getBuilder('automate');
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'getBuilder() should return a builder for the automate silo.');
    System.Assert.isTrue(
      result instanceof LkgHardwareAutomateKeyParamBuilder,
      'getBuilder() should return a LkgHardwareAutomateKeyParamBuilder for the automate silo.'
    );
  }

  @isTest
  static void getBuilder_shouldBeCaseInsensitiveForAutomateSilo() {
    // Given the 'AUTOMATE' silo name (uppercase)

    // When
    Test.startTest();
    ILkgHardwareKeyParamBuilder result = LkgHardwareKeyParamBuilderFactory.getBuilder('AUTOMATE');
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'getBuilder() should handle uppercase silo names case-insensitively.');
    System.Assert.isTrue(
      result instanceof LkgHardwareAutomateKeyParamBuilder,
      'getBuilder() should return a LkgHardwareAutomateKeyParamBuilder regardless of case.'
    );
  }

  @isTest
  static void getBuilder_shouldReturnNullForUnknownSilo() {
    // Given an unknown silo name that is not registered in the factory

    // When
    Test.startTest();
    ILkgHardwareKeyParamBuilder result = LkgHardwareKeyParamBuilderFactory.getBuilder('unknown_silo');
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'getBuilder() should return null for an unregistered silo.');
  }
}