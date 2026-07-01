public with sharing class LkgRequestBuilderLegacyIbm extends LkgRequestBuilderBase {
  static public final string processorGroupDefault = '*ANY';

  public enum LegacyIbmParameters {
    productCode,
    version,
    expirationDate,
    hardwareId,
    processorGroup,
    usageLimit,
    model,
    featureCode,
    blank,
    supportKey
  }

  public class LegacyIbmKeyData extends LkgRequestBuilderBase.KeyData {
    public String processorGroup;
    public Integer usageLimit;
    public String model;
    public String featureCode;
    public Boolean supportKey;
    public String modification;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    LegacyIbmKeyData siloKeyData = (LegacyIbmKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(
      LegacyIbmParameters.productCode.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.ProductCode, '')
    );
    dynamicParameters.put(LegacyIbmParameters.version.ordinal(), getVersion(siloKeyData));
    dynamicParameters.put(
      LegacyIbmParameters.expirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(
      LegacyIbmParameters.hardwareId.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.HardwareId, '')
    );
    dynamicParameters.put(LegacyIbmParameters.processorGroup.ordinal(), getProcessorGroup(siloKeyData));
    dynamicParameters.put(
      LegacyIbmParameters.usageLimit.ordinal(),
      getIntegerStringOrDefaultIfNull(siloKeyData.usageLimit, '0')
    );
    dynamicParameters.put(LegacyIbmParameters.model.ordinal(), getStringOrDefaultIfNull(siloKeyData.model, ''));
    dynamicParameters.put(
      LegacyIbmParameters.featureCode.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.featureCode, '')
    );
    dynamicParameters.put(LegacyIbmParameters.blank.ordinal(), '');
    dynamicParameters.put(LegacyIbmParameters.supportKey.ordinal(), getSupportKeyText(siloKeyData.supportKey));

    return dynamicParameters;
  }

  private string getVersion(LegacyIbmKeyData siloKeyData) {
    string version = '';
    if (string.isNotBlank(siloKeyData.release)) {
      string modification = '00';

      if (string.isNotBlank(siloKeyData.modification)) {
        modification = siloKeyData.modification.right(2);
      }

      version = siloKeyData.release.replace('0', '') + modification;
    }
    return version;
  }

  private string getProcessorGroup(LegacyIbmKeyData siloKeyData) {
    string processorGroup = processorGroupDefault;
    if (String.isNotBlank(siloKeyData.processorGroup)) {
      processorGroup = siloKeyData.processorGroup;
    }
    return processorGroup;
  }

  private string getSupportKeyText(Boolean supportKey) {
    string supportKeyText = '0';
    if (supportKey) {
      supportKeyText = '1';
    }
    return supportKeyText;
  }
}