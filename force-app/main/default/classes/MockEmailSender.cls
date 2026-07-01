/**
 * Mock email sender for testing
 * Simulates successful email sending without actually sending emails
 * Allows testing when Email Deliverability is set to "System Email only"
 */
@isTest
public class MockEmailSender implements IEmailSender {
  // Configuration for mock behavior
  public Boolean shouldSucceed = true;
  public String errorMessage = 'Test error message';

  // Track what was "sent" for test assertions
  public List<Messaging.SingleEmailMessage> sentEmails = new List<Messaging.SingleEmailMessage>();

  /**
   * Mock implementation of sendEmail
   * Captures email for inspection and returns mock result
   */
  public IEmailSenderResult sendEmail(List<Messaging.SingleEmailMessage> emails) {
    sentEmails.addAll(emails);
    return new MockEmailSenderResult(shouldSucceed, errorMessage);
  }
}