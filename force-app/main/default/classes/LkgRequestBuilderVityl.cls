public with sharing class LkgRequestBuilderVityl extends LkgRequestBuilderBase {
  public enum VitylParameters {
    ProductCode,
    Version,
    HardwareId,
    Points,
    LicenseKeyType,
    ExpirationDate,
    Flags
  }

  public class VitylKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
    public String Tier;
    public Integer Count;
    public String Flag;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    VitylKeyData siloKeyData = (VitylKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(VitylParameters.ProductCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(VitylParameters.Version.ordinal(), getVersion(siloKeyData.release, siloKeyData.modification));
    dynamicParameters.put(VitylParameters.HardwareId.ordinal(), getStringOrDefaultIfNull(siloKeyData.HardwareId, ''));
    dynamicParameters.put(VitylParameters.Points.ordinal(), getTierKey(siloKeyData));
    dynamicParameters.put(VitylParameters.LicenseKeyType.ordinal(), getLicenseKeyType(siloKeyData.KeyType));
    dynamicParameters.put(
      VitylParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(VitylParameters.Flags.ordinal(), getStringOrDefaultIfNull(siloKeyData.Flag, ''));

    return dynamicParameters;
  }

  public static String getVersion(String release, String modification) {
    if (String.isNotBlank(release) && String.isNotBlank(modification)) {
      return release + '.' + modification;
    }
    if (String.isNotBlank(release)) {
      return release;
    }
    return '';
  }

  public static String getTierKey(VitylKeyData keyData) {
    String tier = keyData.Tier;
    Integer count = keyData.Count;
    String productCode = keyData.ProductCode;
    if (productCode == 'VCI') {
      tier = tier + 'S1';
    } else {
      count = keyData.KeyType == 'Generic' ? 99999 : (count != null ? count : 0);
      tier = 'S1' + 'C' + String.valueOf(count);
    }
    return tier;
  }

  public static String getLicenseKeyType(String keyType) {
    if (keyType == 'Generic') {
      return 'T';
    }
    if (keyType == 'Permanent') {
      return 'P';
    }
    if (keyType == 'Specific_Temporary') {
      return 'T';
    }
    return '';
  }
}