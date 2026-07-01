/**
 * Default email sender implementation
 * Uses Salesforce Messaging API for actual email sending
 * Used in production and when emailSender is not explicitly set
 */
public class DefaultEmailSender implements IEmailSender {
  /**
   * Send emails using Salesforce Messaging API
   * @param emails List of email messages to send
   * @return Wrapped send result
   */
  public IEmailSenderResult sendEmail(List<Messaging.SingleEmailMessage> emails) {
    // Use allOrNone=false to return results even when email sending fails
    // This is important for test coverage in orgs with Email Deliverability restrictions
    List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
    return new RealEmailSenderResult(results[0]);
  }
}