public with sharing class LkgMapperSgavx extends LkgMapperBase {
  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderSgavx.SgavxKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    LkgRequestBuilderSgavx.SgavxKeyData sgavxKeyData = (LkgRequestBuilderSgavx.SgavxKeyData) keyData;

    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;

    sgavxKeyData.NumberOfUsers = safeParseInt(uiPayload.attributes.get(product + '_Number_of_Users'));
    sgavxKeyData.HardwareId = uiPayload.attributes.get(silo + '_MAC_Address');
    sgavxKeyData.modification = uiPayload.attributes.get(silo + '_Modification');
    sgavxKeyData.lparSerialNumber = uiPayload.attributes.get(silo + '_Serial_Number');

    String accountNumber = [SELECT AccountNumber FROM Account WHERE Id = :uiPayload.accountId LIMIT 1]?.AccountNumber;
    sgavxKeyData.accountNumber = accountNumber != null ? accountNumber : '';
    sgavxKeyData.createLicenseKeyFile = true;
  }
}