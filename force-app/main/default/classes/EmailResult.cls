/**
 * Wrapper class to hold email sending result information
 * Used to communicate success/failure and error details between email service and handlers
 */
public class EmailResult {
  public Boolean isSuccess { get; set; }
  public String errorMessage { get; set; }
  public String errorDetails { get; set; }
  public String userFriendlyMessage { get; set; }

  /**
   * Constructor for successful email send
   */
  public EmailResult(Boolean success) {
    this.isSuccess = success;
    if (success) {
      this.userFriendlyMessage = 'License Key Email sent successfully!';
    }
  }

  /**
   * Constructor for failed email send with error details
   */
  public EmailResult(Boolean success, String errorMessage, String errorDetails) {
    this.isSuccess = success;
    this.errorMessage = errorMessage;
    this.errorDetails = errorDetails;
    this.userFriendlyMessage = formatUserFriendlyMessage(errorMessage);
  }

  /**
   * Format technical error messages into user-friendly messages
   */
  private String formatUserFriendlyMessage(String technicalError) {
    if (String.isBlank(technicalError)) {
      return 'An error occurred while sending the license key email. Please try again or contact your administrator.';
    }

    // Convert common technical errors to user-friendly messages
    if (technicalError.containsIgnoreCase('email address')) {
      return 'Email could not be sent: Invalid or missing email address. Please verify contact information.';
    } else if (technicalError.containsIgnoreCase('template')) {
      return 'Email could not be sent: Email template configuration issue. Please contact your administrator.';
    } else if (technicalError.containsIgnoreCase('contact')) {
      return 'Email could not be sent: Contact information is missing or incomplete. Please add a contact with valid email.';
    } else if (technicalError.containsIgnoreCase('permission') || technicalError.containsIgnoreCase('access')) {
      return 'Email could not be sent: You do not have permission to send emails. Please contact your administrator.';
    }

    // Default user-friendly message with hint that more details are available
    return 'An error occurred while sending the license key email. Please try again or contact your administrator for more details.';
  }

  /**
   * Get complete error information for logging or detailed display
   */
  public String getFullErrorInfo() {
    if (String.isBlank(errorDetails)) {
      return errorMessage;
    }
    return errorMessage + '\n\nDetails:\n' + errorDetails;
  }
}