public with sharing class LkgRequestBuilderAccessAuth extends LkgRequestBuilderBase {
  public enum AccessAuthParameters {
    productCode,
    version,
    hardwareIdNumber,
    tierCode,
    licenseKeyType,
    expirationDate
  }

  public class AccessAuthKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
  }

  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    AccessAuthKeyData siloKeyData = (AccessAuthKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    dynamicParameters.put(
      LkgRequestBuilderAccessAuth.AccessAuthParameters.productCode.ordinal(),
      siloKeyData.ProductCode
    );
    dynamicParameters.put(LkgRequestBuilderAccessAuth.AccessAuthParameters.version.ordinal(), getVersion(siloKeyData));
    dynamicParameters.put(
      LkgRequestBuilderAccessAuth.AccessAuthParameters.hardwareIdNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.HardwareId, '')
    );
    dynamicParameters.put(
      LkgRequestBuilderAccessAuth.AccessAuthParameters.tierCode.ordinal(),
      getTierCode(siloKeyData)
    );
    dynamicParameters.put(
      LkgRequestBuilderAccessAuth.AccessAuthParameters.licenseKeyType.ordinal(),
      getKeyType(siloKeyData)
    );
    dynamicParameters.put(
      LkgRequestBuilderAccessAuth.AccessAuthParameters.expirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );

    return dynamicParameters;
  }

  private string getVersion(LkgRequestBuilderAccessAuth.AccessAuthKeyData keyData) {
    string version = '';

    if (String.isNotBlank(keyData.release)) {
      version = keyData.release;

      if (String.isNotBlank(keyData.modification)) {
        version += '.' + keyData.modification;
      } else {
        version += '.0';
      }
    }

    return version;
  }

  private string getTierCode(LkgRequestBuilderAccessAuth.AccessAuthKeyData keyData) {
    string tierCode = 'S1';
    string keyType = getKeyType(keyData);

    if (keyData.Silo == 'accessauth') {
      string extraUsersString = '0';

      if (keyData.NumberOfUsers > 99999)
        extraUsersString = (keyData.NumberOfUsers - 99999).toString();

      tierCode += 'U' + keyData.NumberOfUsers.toString() + 'T' + extraUsersString;
    } else if (keyData.Silo == 'securityscan') {
      tierCode += 'U99999U99999';
    }

    tierCode += 'L' + getLicenseKeyType(keyType);

    return tierCode;
  }

  private string getKeyType(LkgRequestBuilderAccessAuth.AccessAuthKeyData keyData) {
    if (keyData.KeyType == 'Permanent')
      return 'P';
    if (keyData.KeyType == 'Generic' || keyData.KeyType == 'Specific_Temporary')
      return 'T';
    if (keyData.KeyType == 'Subscription')
      return 'E';
    return '';
  }

  private string getLicenseKeyType(string keyType) {
    if (keyType == 'T')
      return '1';
    if (keyType == 'P')
      return '2';
    if (keyType == 'E')
      return '3';
    return '';
  }
}