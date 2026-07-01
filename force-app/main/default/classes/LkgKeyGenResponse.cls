public with sharing class LkgKeyGenResponse {
  @AuraEnabled
  public Boolean isSuccess;
  @AuraEnabled
  public String message;
  @AuraEnabled
  public String generatedKey;
  @AuraEnabled
  public Id licenseKeyId;

  public LkgKeyGenResponse() {
    this.isSuccess = false;
    this.message = '';
    this.generatedKey = '';
    this.licenseKeyId = null;
  }

  public static LkgKeyGenResponse success(String generatedKey, Id licenseKeyId) {
    LkgKeyGenResponse response = new LkgKeyGenResponse();
    response.isSuccess = true;
    response.message = 'License key generated successfully. Click {0} to view the key.';
    response.generatedKey = generatedKey;
    response.licenseKeyId = licenseKeyId;
    return response;
  }

  public static LkgKeyGenResponse error(String errorMessage) {
    LkgKeyGenResponse response = new LkgKeyGenResponse();
    response.isSuccess = false;
    response.message = errorMessage;
    return response;
  }

  public class KeyGenException extends Exception {
  }
}