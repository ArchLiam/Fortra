public with sharing class LkgRequestBuilderTQSurveyor extends LkgRequestBuilderBase {
  public enum TQSurveyorParameters {
    productCode,
    keyType,
    expirationDate,
    accountName,
    modelNumber,
    numberOfLicenses
  }

  public class TQSurveyorKeyData extends LkgRequestBuilderBase.KeyData {
    public string accountName;
    public string modelNumber;
    public Integer numberOfLicenses;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    TQSurveyorKeyData siloKeyData = (TQSurveyorKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(TQSurveyorParameters.productCode.ordinal(), siloKeyData.ProductCode);
    dynamicParameters.put(TQSurveyorParameters.keyType.ordinal(), getLicenseKeyType(siloKeyData.KeyType));
    dynamicParameters.put(
      TQSurveyorParameters.expirationDate.ordinal(),
      getFormattedExpirationDate(siloKeyData.ExpirationDate)
    );
    dynamicParameters.put(
      TQSurveyorParameters.accountName.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.accountName, '')
    );
    dynamicParameters.put(
      TQSurveyorParameters.modelNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.modelNumber, '')
    );
    dynamicParameters.put(
      TQSurveyorParameters.numberOfLicenses.ordinal(),
      getIntegerStringOrDefaultIfNull(siloKeyData.numberOfLicenses, '0')
    );

    return dynamicParameters;
  }

  private String getLicenseKeyType(String keyType) {
    string keyTypeString = '';

    if (keyType == 'Generic') {
      keyTypeString = 'E';
    }
    if (keyType == 'Permanent') {
      keyTypeString = 'P';
    }
    if (keyType == 'Specific_Temporary') {
      keyTypeString = 'E';
    }

    return keyTypeString;
  }
}