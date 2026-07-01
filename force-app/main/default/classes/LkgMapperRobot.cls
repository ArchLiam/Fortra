public with sharing class LkgMapperRobot extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderRobot.RobotKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String productIdentifierName = uiPayload.productData.identifierName;

    LkgRequestBuilderRobot.RobotKeyData robotKeyData = (LkgRequestBuilderRobot.RobotKeyData) keyData;

    robotKeyData.Modification = uiPayload.attributes.get(silo + '_Modification');
    robotKeyData.LParSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');
    robotKeyData.ModelNumber = uiPayload.attributes.get(silo + '_Model_Number');
    robotKeyData.FeatureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    robotKeyData.LParNumber = uiPayload.attributes.get(silo + '_LPAR_Num');
    robotKeyData.LParEnd = uiPayload.attributes.get(silo + '_End_LPAR_Num');
    robotKeyData.NumberOfProcessors = safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Processors'));
    robotKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get(productIdentifierName + '_Number_of_Users'));
    robotKeyData.ProcessorType = uiPayload.attributes.get(silo + '_Processor_Type');
    robotKeyData.IAspGroup = uiPayload.attributes.get(silo + '_iAsp_Group');
    robotKeyData.FeatureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    robotKeyData.LParName = uiPayload.attributes.get(silo + '_LPAR_Name');
    robotKeyData.PermTermVersionRange = uiPayload.attributes.get(productIdentifierName + '_Version_Range');

    if (robotKeyData.FeatureCode == null || robotKeyData.FeatureCode == '') {
      if (uiPayload.productData.name == 'RB069_Robot_Monitor')
        // robot_OS_Type is a picklist
        robotKeyData.FeatureCode = uiPayload.attributes.get(silo + '_OS_Type');
    }
  }
}