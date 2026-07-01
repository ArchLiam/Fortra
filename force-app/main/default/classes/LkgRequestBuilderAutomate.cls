public with sharing class LkgRequestBuilderAutomate extends LkgRequestBuilderBase {
  public enum AutomateParameters {
    ProductCode,
    Version,
    HardwareId,
    Points,
    LicenseKeyType,
    ExpirationDate
  }

  public class AutomateKeyData extends LkgRequestBuilderBase.KeyData {
    public String points;
    public String modification;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    AutomateKeyData automateKeyData = (AutomateKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    dynamicParameters.put(AutomateParameters.ProductCode.ordinal(), automateKeyData.ProductCode);
    dynamicParameters.put(
      AutomateParameters.Version.ordinal(),
      getVersion(automateKeyData.release, automateKeyData.modification)
    );
    dynamicParameters.put(
      AutomateParameters.HardwareId.ordinal(),
      getStringOrDefaultIfNull(automateKeyData.HardwareId, '')
    );
    dynamicParameters.put(AutomateParameters.Points.ordinal(), getStringOrDefaultIfNull(automateKeyData.points, ''));
    dynamicParameters.put(AutomateParameters.LicenseKeyType.ordinal(), getLicenseKeyType(automateKeyData.KeyType));
    dynamicParameters.put(
      AutomateParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(automateKeyData.ExpirationDate)
    );

    return dynamicParameters;
  }

  public static String getVersion(String release, String modification) {
    if (String.isNotBlank(release)) {
      string releaseCode = '0';

      if (String.isNotBlank(modification)) {
        releaseCode = modification;
      }

      return release + '.' + releaseCode;
    }
    return '';
  }

  public static String getLicenseKeyType(String keyType) {
    if (keyType == 'Generic') {
      return 'T';
    } else if (keyType == 'Permanent') {
      return 'P';
    } else if (keyType == 'Specific_Temporary') {
      return 'T';
    } else if (keyType == 'Subscription') {
      return 'E';
    }

    return '0';
  }
}