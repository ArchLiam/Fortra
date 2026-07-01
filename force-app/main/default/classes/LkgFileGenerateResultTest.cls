@isTest
private class LkgFileGenerateResultTest {
  @isTest
  static void constructor_shouldSetSuccessToTrue() {
    // Given success=true and a message
    Boolean expectedSuccess = true;
    String expectedMessage = 'File generated successfully.';

    // When
    Test.startTest();
    LkgFileGenerateResult result = new LkgFileGenerateResult(expectedSuccess, expectedMessage);
    Test.stopTest();

    // Then
    System.Assert.isTrue(result.success, 'success field should be set to true when true is passed to the constructor.');
  }

  @isTest
  static void constructor_shouldSetSuccessToFalse() {
    // Given success=false and a failure message
    Boolean expectedSuccess = false;
    String expectedMessage = 'No License Keys selected.';

    // When
    Test.startTest();
    LkgFileGenerateResult result = new LkgFileGenerateResult(expectedSuccess, expectedMessage);
    Test.stopTest();

    // Then
    System.Assert.isFalse(
      result.success,
      'success field should be set to false when false is passed to the constructor.'
    );
  }

  @isTest
  static void constructor_shouldSetMessageCorrectly() {
    // Given a known message string
    String expectedMessage = 'Account is required.';

    // When
    Test.startTest();
    LkgFileGenerateResult result = new LkgFileGenerateResult(false, expectedMessage);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      expectedMessage,
      result.message,
      'message field should match the value passed to the constructor.'
    );
  }

  @isTest
  static void constructor_shouldAcceptNullMessage() {
    // Given a null message (edge case — callers may pass null)

    // When
    Test.startTest();
    LkgFileGenerateResult result = new LkgFileGenerateResult(true, null);
    Test.stopTest();

    // Then
    System.Assert.isNull(result.message, 'message field should be null when null is passed to the constructor.');
  }
}