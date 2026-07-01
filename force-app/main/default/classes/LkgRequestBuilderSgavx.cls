public with sharing class LkgRequestBuilderSgavx extends LkgRequestBuilderBase {
  public enum SgavxParameters {
    productCode,
    version,
    licenseKeyType,
    expirationDate,
    hardwareIdNumber,
    userCount,
    accountNumber
  }

  public class SgavxKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
    public String accountNumber;
    public String lparSerialNumber;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    SgavxKeyData siloKeyData = (SgavxKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(SgavxParameters.productCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(
      SgavxParameters.version.ordinal(),
      LkgRequestBuilderPowerTech.getVersion(siloKeyData.release, siloKeyData.modification)
    );
    dynamicParameters.put(SgavxParameters.licenseKeyType.ordinal(), getLicenseKeyType(siloKeyData.KeyType));
    dynamicParameters.put(
      SgavxParameters.expirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(
      SgavxParameters.hardwareIdNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.HardwareId, '')
    );
    dynamicParameters.put(
      SgavxParameters.userCount.ordinal(),
      getIntegerStringOrDefaultIfNull(siloKeyData.NumberOfUsers, '')
    );
    dynamicParameters.put(SgavxParameters.accountNumber.ordinal(), siloKeyData.accountNumber);

    return dynamicParameters;
  }

  public static String getLicenseKeyType(String keyType) {
    if (keyType == 'Generic') {
      return '1';
    }
    if (keyType == 'Permanent') {
      return '0';
    }
    if (keyType == 'Specific_Temporary') {
      return '5';
    }
    return '';
  }
}