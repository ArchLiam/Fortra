public with sharing class LkgRecordCreatorSequel extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderSequel.SequelKeyData sequelKeyData = (LkgRequestBuilderSequel.SequelKeyData) keyData;

    licenseKey.IASP_Name__c = sequelKeyData.IAspGroup;
    licenseKey.LPAR_End_Number__c = sequelKeyData.LParEnd;
    licenseKey.LPAR_Feature_Code__c = sequelKeyData.FeatureCode;
    licenseKey.LPAR_Model_Number__c = sequelKeyData.ModelNumber;
    licenseKey.LPAR_Number__c = sequelKeyData.LParNumber;
    licenseKey.LPAR_Serial_Number__c = sequelKeyData.LParSerialNumber;
    licenseKey.Number_of_Processors__c = String.valueOf(sequelKeyData.NumberOfProcessors);
    licenseKey.Processor_Type__c = sequelKeyData.ProcessorType;
    licenseKey.Release__c = sequelKeyData.release;
    licenseKey.Modification__c = sequelKeyData.Modification;
    licenseKey.LPAR_System_Name__c = sequelKeyData.LParName;
  }
}