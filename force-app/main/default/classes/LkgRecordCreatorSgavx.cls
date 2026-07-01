public with sharing class LkgRecordCreatorSgavx extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderSgavx.SgavxKeyData sgavxKeyData = (LkgRequestBuilderSgavx.SgavxKeyData) keyData;

    licenseKey.Hardware_Id__c = sgavxKeyData.HardwareId;
    licenseKey.Modification__c = sgavxKeyData.modification;
    licenseKey.Number_of_Users__c = sgavxKeyData.NumberOfUsers;
    licenseKey.LPAR_Serial_Number__c = sgavxKeyData.lparSerialNumber;
  }

  public override Attachment createAttachment(License_Key__c licenseKey) {
    LkgRecordCreatorBase.LicenseKeyResponseMessage licenseKeyResponse = (LkgRecordCreatorBase.LicenseKeyResponseMessage) JSON.deserialize(
      licenseKey.Response_Message__c,
      LkgRecordCreatorBase.LicenseKeyResponseMessage.class
    );

    String responseString = '';
    for (String output : licenseKeyResponse.output) {
      responseString += output + '\n';
    }

    Attachment attachment = new Attachment();
    attachment.ParentId = licenseKey.Id;
    attachment.Name = 'License Key ' + Datetime.now().format('MMddyyyyHHmmss') + '.SGA';
    attachment.Body = Blob.valueOf(responseString);
    attachment.ContentType = 'text/plain';
    attachment.IsPrivate = false;
    return attachment;
  }
}