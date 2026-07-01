public with sharing class LkgRequestBuilderPtMulti extends LkgRequestBuilderBase {
  public enum PtMultiParameters {
    productCode,
    version,
    hardwareIdentifier,
    points,
    licenseKeyType,
    expirationDate,
    paramFlagPlaceHolderRequiredForAPI
  }

  public class PtMultiKeyData extends LkgRequestBuilderBase.KeyData {
    public String modification;
    public String points;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    PtMultiKeyData siloKeyData = (PtMultiKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(PtMultiParameters.productCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(PtMultiParameters.version.ordinal(), getVersion(siloKeyData));
    dynamicParameters.put(
      PtMultiParameters.hardwareIdentifier.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.HardwareId, '0000000000')
    );
    dynamicParameters.put(PtMultiParameters.points.ordinal(), getPoints(siloKeyData));
    dynamicParameters.put(PtMultiParameters.licenseKeyType.ordinal(), getKeyType(siloKeyData));
    dynamicParameters.put(
      PtMultiParameters.expirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(PtMultiParameters.paramFlagPlaceHolderRequiredForAPI.ordinal(), '');
    return dynamicParameters;
  }

  private static String getVersion(PtMultiKeyData siloKeyData) {
    if (String.isNotBlank(siloKeyData.release)) {
      string modification = '0';

      if (String.isNotBlank(siloKeyData.modification)) {
        modification = siloKeyData.modification;
      }
      return siloKeyData.release + '.' + modification;
    }

    return '';
  }

  private String getPoints(PtMultiKeyData siloKeyData) {
    String points = '';
    if (siloKeyData.ProductCode != 'PEM' && siloKeyData.ProductCode != 'VBM')
      points = 'S1';
    if (String.isNotBlank(siloKeyData.points)) {
      points += 'P' + siloKeyData.points;
    }
    return points;
  }

  private String getKeyType(PtMultiKeyData siloKeyData) {
    String keyType = '';

    if (siloKeyData.KeyType == KEYTYPE_GENERIC || siloKeyData.KeyType == KEYTYPE_SPECIFIC_TEMPORARY) {
      keyType = 'T';
    } else if (siloKeyData.KeyType == KEYTYPE_PERMANENT) {
      keyType = 'P';
    }

    return keyType;
  }
}