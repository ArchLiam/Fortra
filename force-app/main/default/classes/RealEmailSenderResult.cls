/**
 * Real implementation wrapping Salesforce Messaging.SendEmailResult
 * Used by DefaultEmailSender for production email sending
 */
public class RealEmailSenderResult implements IEmailSenderResult {
  private Messaging.SendEmailResult result;

  public RealEmailSenderResult(Messaging.SendEmailResult result) {
    this.result = result;
  }

  public Boolean isSuccess() {
    return result.isSuccess();
  }

  public String getErrorMessage() {
    if (result.isSuccess()) {
      return null;
    }
    return result.getErrors()[0].getMessage();
  }
}