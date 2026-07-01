public with sharing class LkgMapperPowertech extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderPowertech.PowertechKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderPowertech.PowertechKeyData powertechKeyData = (LkgRequestBuilderPowertech.PowertechKeyData) keyData;

    powertechKeyData.EndLparNumber = uiPayload.attributes.get(silo + '_End_LPAR_Num');
    powertechKeyData.FeatureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    powertechKeyData.IAspGroup = uiPayload.attributes.get(silo + '_iAsp_Group');
    powertechKeyData.LparName = uiPayload.attributes.get(silo + '_LPAR_Name');
    powertechKeyData.LparNumber = uiPayload.attributes.get(silo + '_LPAR_Num');
    powertechKeyData.ModelNumber = uiPayload.attributes.get(silo + '_Model_Number');
    powertechKeyData.Notes = uiPayload.attributes.get(silo + '_Notes');
    powertechKeyData.NumberOfProcessors = safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Processors'));
    powertechKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Users'));
    powertechKeyData.ProcessorType = uiPayload.attributes.get(silo + '_Processor_Type');
    powertechKeyData.LParSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');
    powertechKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
    powertechKeyData.PermTermVersionRange = uiPayload.attributes.get(product + '_Version_Range');
  }
}