public with sharing class LkgRequestBuilderPowerTech extends LkgRequestBuilderBase {
  public enum PowerTechParameters {
    ProductCode,
    Version,
    LicenseKeyType,
    ExpirationDate,
    LParSerialNumber,
    ModelNumber,
    FeatureCode,
    LparNumber,
    EndLparNumber,
    UserCount,
    NumberOfProcessors,
    ProcessorType,
    IAspGroup
  }

  public class PowerTechKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
    public String LParSerialNumber;
    public String ModelNumber;
    public String FeatureCode;
    public String LparNumber;
    public String EndLparNumber;
    public Integer NumberOfProcessors;
    //public String CheckType;
    public String IAspGroup;
    public String LparName;
    public String Notes;
    public String ProcessorType;
    public String PermTermVersionRange;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    PowerTechKeyData siloKeyData = (PowerTechKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(PowerTechParameters.ProductCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(
      PowerTechParameters.Version.ordinal(),
      getVersion(siloKeyData.release, siloKeyData.modification)
    );
    dynamicParameters.put(PowerTechParameters.LicenseKeyType.ordinal(), getLicenseKeyType(siloKeyData));
    dynamicParameters.put(
      PowerTechParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(
      PowerTechParameters.LParSerialNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.LParSerialNumber, '')
    );
    dynamicParameters.put(
      PowerTechParameters.ModelNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.ModelNumber, '')
    );
    dynamicParameters.put(
      PowerTechParameters.FeatureCode.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.FeatureCode, '')
    );
    dynamicParameters.put(PowerTechParameters.LparNumber.ordinal(), siloKeyData.LparNumber);
    dynamicParameters.put(PowerTechParameters.EndLparNumber.ordinal(), siloKeyData.EndLparNumber);
    dynamicParameters.put(
      PowerTechParameters.UserCount.ordinal(),
      getIntegerStringOrDefaultIfNull(siloKeyData.NumberOfUsers, '0')
    );
    dynamicParameters.put(
      PowerTechParameters.NumberOfProcessors.ordinal(),
      getIntegerStringOrDefaultIfNull(siloKeyData.NumberOfProcessors, '0')
    );
    dynamicParameters.put(
      PowerTechParameters.ProcessorType.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.ProcessorType, '')
    );
    dynamicParameters.put(PowerTechParameters.IAspGroup.ordinal(), getStringOrDefaultIfNull(siloKeyData.IAspGroup, ''));

    return dynamicParameters;
  }

  public override virtual String GetSiloName(KeyData keyData) {
    return keyData.silo;
  }

  public static String getVersion(String release, String modification) {
    if (String.isNotBlank(release)) {
      string releaseCode = '0';

      if (String.isNotBlank(modification)) {
        releaseCode = modification;
      }

      return 'R' + release + 'M' + releaseCode;
    }
    return '';
  }

  private String getLicenseKeyType(PowerTechKeyData keyData) {
    string keyTypeAPICode = '';
    string KEYTYPE_APICODE_GENERIC = '1';
    string KEYTYPE_APICODE_PERMENANT = '0';
    string KEYTYPE_APICODE_SPECIFIC_TERM = '5';

    if (keyData.KeyType == KEYTYPE_PERMANENT) {
      keyTypeAPICode = KEYTYPE_APICODE_PERMENANT;
    } else if (keyData.KeyType == KEYTYPE_GENERIC) {
      keyTypeAPICode = KEYTYPE_APICODE_GENERIC;
    } else if (keyData.KeyType == KEYTYPE_SPECIFIC_TEMPORARY) {
      keyTypeAPICode = LkgTermPermRangeChecker.shouldConvertTermToPerm(
          keyData.release,
          keyData.modification,
          keyData.PermTermVersionRange
        )
        ? KEYTYPE_APICODE_PERMENANT
        : KEYTYPE_APICODE_SPECIFIC_TERM;
    }

    return keyTypeAPICode;
  }
}