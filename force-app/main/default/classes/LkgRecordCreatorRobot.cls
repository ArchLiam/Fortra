public with sharing class LkgRecordCreatorRobot extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderRobot.RobotKeyData robotKeyData = (LkgRequestBuilderRobot.RobotKeyData) keyData;

    licenseKey.IASP_Name__c = robotKeyData.IAspGroup;
    licenseKey.LPAR_End_Number__c = robotKeyData.LParEnd;
    licenseKey.LPAR_Feature_Code__c = robotKeyData.FeatureCode;
    licenseKey.LPAR_Model_Number__c = robotKeyData.ModelNumber;
    licenseKey.LPAR_Number__c = robotKeyData.LParNumber;
    licenseKey.LPAR_Serial_Number__c = robotKeyData.LParSerialNumber;
    licenseKey.Number_of_Processors__c = String.valueOf(robotKeyData.NumberOfProcessors);
    licenseKey.Number_of_Users__c = robotKeyData.NumberOfUsers;
    licenseKey.Processor_Type__c = robotKeyData.ProcessorType;
    licenseKey.Release__c = robotKeyData.release;
    licenseKey.Modification__c = robotKeyData.Modification;
    licenseKey.LPAR_System_Name__c = robotKeyData.LParName;
  }
}