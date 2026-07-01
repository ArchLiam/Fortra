public with sharing class LkgRequestBuilderIntermapper extends LkgRequestBuilderBase {
  public enum IntermapperParameters {
    ProductCode,
    Version,
    HardwareId,
    Points,
    LicenseKeyType,
    ExpirationDate,
    Flags
  }

  public class IntermapperKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
    public Integer ServerDevices;
    public Integer ServerFlows;
    public Integer Remotes;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    IntermapperKeyData siloKeyData = (IntermapperKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(IntermapperParameters.ProductCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(
      IntermapperParameters.Version.ordinal(),
      getVersion(siloKeyData.release, siloKeyData.modification)
    );
    dynamicParameters.put(
      IntermapperParameters.HardwareId.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.HardwareId, '')
    );
    dynamicParameters.put(IntermapperParameters.Points.ordinal(), getTierKey(siloKeyData));
    dynamicParameters.put(IntermapperParameters.LicenseKeyType.ordinal(), getLicenseKeyType(siloKeyData.KeyType));
    dynamicParameters.put(
      IntermapperParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(IntermapperParameters.Flags.ordinal(), '');

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
    if (keyType == 'Subscription') {
      return 'E';
    }
    return '';
  }

  public static String getTierKey(IntermapperKeyData keyData) {
    Integer serverDevices = keyData.ServerDevices != null ? keyData.ServerDevices : 0;
    Integer serverFlows = keyData.ServerFlows != null ? keyData.ServerFlows : 0;
    Integer remotes = keyData.Remotes != null ? keyData.Remotes : 0;
    String tierKey =
      'S1' +
      'D' +
      String.valueOf(serverDevices) +
      'F' +
      String.valueOf(serverFlows) +
      'R' +
      String.valueOf(remotes);

    return tierKey;
  }
}