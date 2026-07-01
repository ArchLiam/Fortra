public with sharing class LkgKeyGenResult {
  public String licenseKey { get; private set; }
  public String serialNumber { get; private set; }
  public String requestParameters { get; private set; }
  public String responseMessage { get; private set; }

  public LkgKeyGenResult(String licenseKey, String serialNumber, String requestParameters, String responseMessage) {
    this.licenseKey = licenseKey;
    this.serialNumber = serialNumber;
    this.requestParameters = requestParameters;
    this.responseMessage = responseMessage;
  }

  public void applyTo(LkgRequestBuilderBase.KeyData keyData) {
    keyData.LicenseKey = this.licenseKey;
    keyData.SerialNumber = this.serialNumber;
    keyData.requestParameters = this.requestParameters;
    keyData.responseMessage = this.responseMessage;
  }
}