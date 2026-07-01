/**
 * Test class for EmailResult
 * Covers all constructors, error message formatting, and utility methods
 */
@isTest
private class EmailResultTest {
  /**
   * Test successful email result using single-parameter constructor
   */
  @isTest
  static void testSuccessConstructor() {
    EmailResult result = new EmailResult(true);

    System.assert(result.isSuccess, 'isSuccess should be true');
    System.assertEquals(
      'License Key Email sent successfully!',
      result.userFriendlyMessage,
      'Should have success message'
    );
    System.assertEquals(null, result.errorMessage, 'Should have no error message');
    System.assertEquals(null, result.errorDetails, 'Should have no error details');
  }

  /**
   * Test failed email result using single-parameter constructor
   */
  @isTest
  static void testFailureConstructor_Simple() {
    EmailResult result = new EmailResult(false);

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(null, result.userFriendlyMessage, 'Should have no user message');
    System.assertEquals(null, result.errorMessage, 'Should have no error message');
    System.assertEquals(null, result.errorDetails, 'Should have no error details');
  }

  /**
   * Test error result with email address error
   */
  @isTest
  static void testErrorConstructor_EmailAddressError() {
    String technicalError = 'Invalid email address format';
    EmailResult result = new EmailResult(false, technicalError, 'Details here');

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(technicalError, result.errorMessage, 'Should preserve technical error');
    System.assertEquals('Details here', result.errorDetails, 'Should preserve error details');
    System.assert(
      result.userFriendlyMessage.containsIgnoreCase('Invalid or missing email address'),
      'Should have email-related user message'
    );
  }

  /**
   * Test error result with template error
   */
  @isTest
  static void testErrorConstructor_TemplateError() {
    String technicalError = 'Email template not found';
    EmailResult result = new EmailResult(false, technicalError, null);

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(technicalError, result.errorMessage, 'Should preserve technical error');
    System.assert(
      result.userFriendlyMessage.containsIgnoreCase('template configuration issue'),
      'Should have template-related user message'
    );
  }

  /**
   * Test error result with contact error
   */
  @isTest
  static void testErrorConstructor_ContactError() {
    String technicalError = 'No valid contact information available';
    EmailResult result = new EmailResult(false, technicalError, 'Missing Contact_1__c');

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(technicalError, result.errorMessage, 'Should preserve technical error');
    System.assert(
      result.userFriendlyMessage.containsIgnoreCase('Contact information is missing'),
      'Should have contact-related user message'
    );
  }

  /**
   * Test error result with permission error
   */
  @isTest
  static void testErrorConstructor_PermissionError() {
    String technicalError = 'User does not have permission to send emails';
    EmailResult result = new EmailResult(false, technicalError, 'Check permissions');

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(technicalError, result.errorMessage, 'Should preserve technical error');
    System.assert(
      result.userFriendlyMessage.containsIgnoreCase('do not have permission'),
      'Should have permission-related user message'
    );
  }

  /**
   * Test error result with access error
   */
  @isTest
  static void testErrorConstructor_AccessError() {
    String technicalError = 'Access denied to email service';
    EmailResult result = new EmailResult(false, technicalError, null);

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assert(
      result.userFriendlyMessage.containsIgnoreCase('do not have permission'),
      'Should have access-related user message'
    );
  }

  /**
   * Test error result with generic error message
   */
  @isTest
  static void testErrorConstructor_GenericError() {
    String technicalError = 'Unexpected system error occurred';
    EmailResult result = new EmailResult(false, technicalError, 'Stack trace here');

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(technicalError, result.errorMessage, 'Should preserve technical error');
    System.assertEquals('Stack trace here', result.errorDetails, 'Should preserve error details');
    System.assert(
      result.userFriendlyMessage.contains('An error occurred while sending'),
      'Should have generic user message'
    );
  }

  /**
   * Test error result with blank error message
   */
  @isTest
  static void testErrorConstructor_BlankError() {
    EmailResult result = new EmailResult(false, '', null);

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals('', result.errorMessage, 'Should preserve blank error');
    System.assert(
      result.userFriendlyMessage.contains('An error occurred'),
      'Should have default user message for blank error'
    );
  }

  /**
   * Test error result with null error message
   */
  @isTest
  static void testErrorConstructor_NullError() {
    EmailResult result = new EmailResult(false, null, null);

    System.assert(!result.isSuccess, 'isSuccess should be false');
    System.assertEquals(null, result.errorMessage, 'Should preserve null error');
    System.assert(
      result.userFriendlyMessage.contains('An error occurred'),
      'Should have default user message for null error'
    );
  }

  /**
   * Test getFullErrorInfo with both message and details
   */
  @isTest
  static void testGetFullErrorInfo_WithDetails() {
    EmailResult result = new EmailResult(false, 'Main error message', 'Detailed stack trace');

    String fullInfo = result.getFullErrorInfo();

    System.assert(fullInfo.contains('Main error message'), 'Should contain error message');
    System.assert(fullInfo.contains('Detailed stack trace'), 'Should contain error details');
    System.assert(fullInfo.contains('Details:'), 'Should have details separator');
  }

  /**
   * Test getFullErrorInfo with message only (no details)
   */
  @isTest
  static void testGetFullErrorInfo_NoDetails() {
    EmailResult result = new EmailResult(false, 'Error message only', null);

    String fullInfo = result.getFullErrorInfo();

    System.assertEquals('Error message only', fullInfo, 'Should return just the error message');
  }

  /**
   * Test getFullErrorInfo with blank details
   */
  @isTest
  static void testGetFullErrorInfo_BlankDetails() {
    EmailResult result = new EmailResult(false, 'Error message', '');

    String fullInfo = result.getFullErrorInfo();

    System.assertEquals('Error message', fullInfo, 'Should return just the error message when details are blank');
  }

  /**
   * Test case-insensitive error message matching for email errors
   */
  @isTest
  static void testErrorMatching_CaseInsensitive() {
    EmailResult result1 = new EmailResult(false, 'EMAIL ADDRESS invalid', null);
    EmailResult result2 = new EmailResult(false, 'TEMPLATE missing', null);
    EmailResult result3 = new EmailResult(false, 'CONTACT not found', null);
    EmailResult result4 = new EmailResult(false, 'PERMISSION denied', null);

    System.assert(result1.userFriendlyMessage.containsIgnoreCase('email address'), 'Should match EMAIL ADDRESS');
    System.assert(result2.userFriendlyMessage.containsIgnoreCase('template'), 'Should match TEMPLATE');
    System.assert(result3.userFriendlyMessage.containsIgnoreCase('contact'), 'Should match CONTACT');
    System.assert(result4.userFriendlyMessage.containsIgnoreCase('permission'), 'Should match PERMISSION');
  }

  /**
   * Test all properties are accessible
   */
  @isTest
  static void testAllPropertiesAccessible() {
    EmailResult result = new EmailResult(false, 'Test error', 'Test details');

    // Verify all properties can be read
    Boolean success = result.isSuccess;
    String error = result.errorMessage;
    String details = result.errorDetails;
    String userMsg = result.userFriendlyMessage;

    // Verify all properties can be set
    result.isSuccess = true;
    result.errorMessage = 'Updated error';
    result.errorDetails = 'Updated details';
    result.userFriendlyMessage = 'Updated message';

    System.assertEquals(true, result.isSuccess, 'Should update isSuccess');
    System.assertEquals('Updated error', result.errorMessage, 'Should update errorMessage');
    System.assertEquals('Updated details', result.errorDetails, 'Should update errorDetails');
    System.assertEquals('Updated message', result.userFriendlyMessage, 'Should update userFriendlyMessage');
  }
}