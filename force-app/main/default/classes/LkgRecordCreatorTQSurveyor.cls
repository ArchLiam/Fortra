public with sharing class LkgRecordCreatorTQSurveyor extends LkgRecordCreatorBase {
  protected override void mapSiloFields(LkgRequestBuilderBase.KeyData keyData, License_Key__c licenseKey) {
    LkgRequestBuilderTQSurveyor.TQSurveyorKeyData tqSurveyorKeyData = (LkgRequestBuilderTQSurveyor.TQSurveyorKeyData) keyData;
  }
}