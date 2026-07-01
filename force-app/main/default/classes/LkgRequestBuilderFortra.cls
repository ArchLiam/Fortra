public with sharing class LkgRequestBuilderFortra extends LkgRequestBuilderBase {
  @TestVisible
  private static final String VERSION_DEFAULT = '';

  public enum FortraKeyParameters {
    ProductCode,
    Version,
    HardwareId,
    Tiers,
    LicenseKeyType,
    ExpirationDate
  }

  public class FortraKeyData extends LkgRequestBuilderBase.KeyData {
    public String tiers;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    FortraKeyData fortraKeyData = (FortraKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    dynamicParameters.put(FortraKeyParameters.ProductCode.ordinal(), fortraKeyData.ProductCode);
    dynamicParameters.put(FortraKeyParameters.Version.ordinal(), getVersion());
    dynamicParameters.put(
      FortraKeyParameters.HardwareId.ordinal(),
      getStringOrDefaultIfNull(fortraKeyData.HardwareId, '0000000000')
    );
    dynamicParameters.put(FortraKeyParameters.Tiers.ordinal(), fortraKeyData.tiers);
    dynamicParameters.put(FortraKeyParameters.LicenseKeyType.ordinal(), getLicenseKeyType(fortraKeyData.KeyType));
    dynamicParameters.put(
      FortraKeyParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(fortraKeyData.ExpirationDate)
    );

    return dynamicParameters;
  }

  private String getVersion() {
    // Always return emptry string for version
    return VERSION_DEFAULT;
  }

  private String getLicenseKeyType(String keyType) {
    if (keyType == 'Generic') {
      return 'T';
    } else if (keyType == 'Permanent') {
      return 'E';
    } else if (keyType == 'Specific_Temporary') {
      return 'T';
    }

    return '0';
  }
}