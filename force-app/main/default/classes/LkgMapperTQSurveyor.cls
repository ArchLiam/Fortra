public with sharing class LkgMapperTQSurveyor extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderTQSurveyor.TQSurveyorKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData tqSurveyorKeyData = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) keyData;

    tqSurveyorKeyData.accountName = uiPayload.attributes.get(silo + '_Company_Name');
    tqSurveyorKeyData.modelNumber = uiPayload.attributes.get(silo + '_Server_Name');
    tqSurveyorKeyData.numberOfLicenses = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Licenses'));
  }
}