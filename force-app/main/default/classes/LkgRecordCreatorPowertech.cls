public with sharing class LkgRecordCreatorPowertech extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderPowertech.PowertechKeyData powertechKeyData = (LkgRequestBuilderPowertech.PowertechKeyData) keyData;

    licenseKey.IASP_Name__c = powertechKeyData.IAspGroup;
    licenseKey.LPAR_End_Number__c = powertechKeyData.EndLparNumber;
    licenseKey.LPAR_Feature_Code__c = powertechKeyData.FeatureCode;
    licenseKey.LPAR_Model_Number__c = powertechKeyData.ModelNumber;
    licenseKey.LPAR_Number__c = powertechKeyData.LparNumber;
    licenseKey.LPAR_Serial_Number__c = powertechKeyData.LParSerialNumber;
    licenseKey.Modification__c = powertechKeyData.modification;
    licenseKey.Number_of_Processors__c = String.valueOf(powertechKeyData.NumberOfProcessors);
    licenseKey.Number_of_Users__c = powertechKeyData.NumberOfUsers;
    licenseKey.Processor_Type__c = powertechKeyData.ProcessorType;
  }
}