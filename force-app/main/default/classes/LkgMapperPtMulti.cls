public with sharing class LkgMapperPtMulti extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderPtMulti.PtMultiKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderPtMulti.PtMultiKeyData ptMultiKeyData = (LkgRequestBuilderPtMulti.PtMultiKeyData) keyData;

    ptMultiKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
    ptMultiKeyData.points = uiPayload.attributes.get(silo + '_Level');
  }
}