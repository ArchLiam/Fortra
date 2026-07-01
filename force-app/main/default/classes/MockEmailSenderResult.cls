/**
 * Mock implementation for testing
 * Used by MockEmailSender to simulate email results without sending
 */
@isTest
public class MockEmailSenderResult implements IEmailSenderResult {
  private Boolean success;
  private String errMsg;

  public MockEmailSenderResult(Boolean success, String errMsg) {
    this.success = success;
    this.errMsg = errMsg;
  }

  public Boolean isSuccess() {
    return success;
  }

  public String getErrorMessage() {
    return success ? null : errMsg;
  }
}