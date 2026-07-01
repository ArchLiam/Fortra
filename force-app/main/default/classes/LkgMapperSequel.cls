public with sharing class LkgMapperSequel extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderSequel.SequelKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String productIdentifierName = uiPayload.productData.identifierName;
    LkgRequestBuilderSequel.SequelKeyData sequelKeyData = (LkgRequestBuilderSequel.SequelKeyData) keyData;

    sequelKeyData.release = uiPayload.attributes.get(productIdentifierName + '_Release');
    sequelKeyData.Modification = uiPayload.attributes.get(productIdentifierName + '_Modification');
    sequelKeyData.LParSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');
    sequelKeyData.ModelNumber = uiPayload.attributes.get(silo + '_Model_Number');
    sequelKeyData.FeatureCode = uiPayload.attributes.get(silo + '_Feature_Code');
    sequelKeyData.LParNumber = uiPayload.attributes.get(silo + '_LPAR_Num');
    sequelKeyData.LParEnd = uiPayload.attributes.get(silo + '_End_LPAR_Num');
    sequelKeyData.NumberOfProcessors = safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Processors'));
    sequelKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get(productIdentifierName + '_Number_of_Users'));
    sequelKeyData.ProcessorType = uiPayload.attributes.get(silo + '_Processor_Type');
    sequelKeyData.IAspGroup = uiPayload.attributes.get(silo + '_iAsp_Group');
    sequelKeyData.LParName = uiPayload.attributes.get(silo + '_LPAR_Name');
    sequelKeyData.PermTermVersionRange = uiPayload.attributes.get(productIdentifierName + '_Version_Range');
  }
}