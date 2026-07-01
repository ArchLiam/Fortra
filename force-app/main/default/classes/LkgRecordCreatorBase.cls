public virtual with sharing class LkgRecordCreatorBase implements ILkgRecordCreator {
  public class LicenseKeyResponseMessage {
    public String status;
    public List<String> output;
  }

  public License_Key__c createLicenseKeyRecord(LkgRequestBuilderBase.KeyData keyData) {
    License_Key__c licenseKey = new License_Key__c();

    mapBaseFields(keyData, licenseKey);
    mapSiloFields(keyData, licenseKey);

    return licenseKey;
  }

  protected void mapBaseFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    licenseKey.Account__c = keyData.AccountId;
    licenseKey.Brand__c = keyData.Brand;
    licenseKey.Key_Type__c = mapKeyType(keyData.KeyType);
    licenseKey.Contact_1__c = keyData.Contact1Id;
    licenseKey.Contact_2__c = keyData.Contact2Id;
    licenseKey.End_Date__c = keyData.ExpirationDate;
    licenseKey.License_Key_Product_Name__c = keyData.externalProductName;
    licenseKey.Internal_Product_Name__c = keyData.internalProductName;
    licenseKey.License_Key__c = keyData.LicenseKey;
    licenseKey.LKG_Product_Identifier_Name__c = keyData.lkgProductIdentifierName;
    licenseKey.Hardware_ID__c = keyData.HardwareId;
    licenseKey.Product_Code__c = keyData.ProductCode;
    licenseKey.Release__c = keyData.release;
    licenseKey.Request_Parameters__c = keyData.RequestParameters != null
      ? keyData.RequestParameters.replaceAll('&argv=', ',')
      : keyData.RequestParameters;
    licenseKey.Response_Message__c = keyData.responseMessage;
    licenseKey.Send_Email__c = keyData.SendEmail;
    licenseKey.License_Key_Serial_Number__c = keyData.serialNumber;
    licenseKey.Silo__c = keyData.Silo;
    licenseKey.Start_Date__c = keyData.StartDate;
    if (keyData.createLicenseKeyFile == null) {
      licenseKey.Create_License_Key_File__c = false;
    } else {
      licenseKey.Create_License_Key_File__c = keyData.createLicenseKeyFile;
    }
    licenseKey.Notes__c = keyData.Notes;
  }

  protected virtual void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    // To be implemented by subclasses for silo-specific fields
  }

  public virtual Attachment createAttachment(License_Key__c licenseKey) {
    // To be implemented by subclasses for silo-specific attachment creation
    return null;
  }

  public void insertLicenseKeyRecord(SObject record) {
    insert record;
  }

  @TestVisible
  private string mapKeyType(string keyType) {
    switch on keyType {
      when 'Permanent' {
        return 'Permanent';
      }
      when 'Specific_Temporary' {
        return 'Specific/Temporary';
      }
      when 'Generic' {
        return 'Generic';
      }
      when 'Subscription' {
        return 'Subscription';
      }
      when else {
        return 'Unknown Key Type';
      }
    }
  }
}