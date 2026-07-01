public with sharing class LkgMapperSequelWeb extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderSequelWeb.SequelWebKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    LkgRequestBuilderSequelWeb.SequelWebKeyData sequelWebKeyData = (LkgRequestBuilderSequelWeb.SequelWebKeyData) keyData;
    sequelWebKeyData.Release = uiPayload.attributes.get(silo + '_Release');
    sequelWebKeyData.Modification = uiPayload.attributes.get(silo + '_Modification');
    sequelWebKeyData.NumberOfViewers = Integer.valueOf(uiPayload.attributes.get(silo + '_Number_of_Viewers'));
    sequelWebKeyData.NumberOfDesigners = Integer.valueOf(uiPayload.attributes.get(silo + '_Number_of_Designers'));
    sequelWebKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
  }
}