/**
 * Wrapper interface for email send results
 * Allows mocking without stubbing Salesforce system classes
 */
public interface IEmailSenderResult {
  Boolean isSuccess();
  String getErrorMessage();
}