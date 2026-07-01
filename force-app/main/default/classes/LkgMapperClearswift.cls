public with sharing class LkgMapperClearswift extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderClearswift.ClearswiftKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    LkgRequestBuilderClearswift.ClearswiftKeyData clearswiftKeyData = (LkgRequestBuilderClearswift.ClearswiftKeyData) keyData;

    clearswiftKeyData.HardwareId = uiPayload.attributes.get('clearswift_Hardware_Id');
    clearswiftKeyData.accountName = uiPayload.attributes.get('Clearswift_Company_Name');
    clearswiftKeyData.Instances = safeParseInt(uiPayload.attributes.get('Clearswift_Instances'));
    clearswiftKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get('Clearswift_User_Count'));
  }
}