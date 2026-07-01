/**
 * Interface for email sending operations
 * Allows mocking in tests while keeping production code clean
 */
public interface IEmailSender {
  IEmailSenderResult sendEmail(List<Messaging.SingleEmailMessage> emails);
}