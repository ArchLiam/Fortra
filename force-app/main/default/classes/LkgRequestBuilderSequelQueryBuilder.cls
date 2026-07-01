public with sharing class LkgRequestBuilderSequelQueryBuilder extends LkgRequestBuilderBase {
  // This enum defines the parameter keys for the Sequel Query Builder, which will be used to map the dynamic parameters in the request.
  public enum SequelQueryBuilderParameters {
    ProductCode,
    Version,
    HardwareId,
    TierPoints,
    LicenseKeyType,
    ExpirationDate
  }

  // This inner class is used to hold the key data specific to Sequel Query Builder, extending the base KeyData class.
  public class SequelQueryBuilderKeyData extends LkgRequestBuilderBase.KeyData {
    public String Modification;
    public String Release;
    public Integer NumberOfConnectors;
    public Integer NumberOfDesigners;
    public Integer HasDataDecorations;
  }

  // This method is used to get the dynamic parameters for Sequel Query Builder based on the input key data.
  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    // Cast the base KeyData to SequelQueryBuilderKeyData to access Sequel Query Builder-specific fields.
    SequelQueryBuilderKeyData brandKeyData = (SequelQueryBuilderKeyData) keyData;

    // Initialize a map to hold the dynamic parameters that will be sent in the license key request.
    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    // set Product Code.
    dynamicParameters.put(SequelQueryBuilderParameters.ProductCode.ordinal(), brandKeyData.ProductCode);

    // set Version Index based on Product Code.
    dynamicParameters.put(SequelQueryBuilderParameters.Version.ordinal(), getVersionIndex(brandKeyData));

    // Set Hardware ID with default value if not provided.
    dynamicParameters.put(
      SequelQueryBuilderParameters.HardwareId.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.HardwareId, '')
    );

    // Set Tier Points with default value if not provided.
    dynamicParameters.put(SequelQueryBuilderParameters.TierPoints.ordinal(), getTierPoints(brandKeyData));

    //set License Key Type
    dynamicParameters.put(
      SequelQueryBuilderParameters.LicenseKeyType.ordinal(),
      getLicenseKeyType(brandKeyData.KeyType)
    );

    // set Expiration Date with default value if not provided.
    dynamicParameters.put(
      SequelQueryBuilderParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(brandKeyData.ExpirationDate)
    );
    return dynamicParameters;
  }

  // Get Version based on the input key data, with a specific format for the version index string.
  private string getVersionIndex(SequelQueryBuilderKeyData keyData) {
    if (keyData.Release == null || keyData.Release == '')
      return '';

    string modification = '00';

    if (keyData.Modification != null && keyData.Modification != '') {
      modification = keyData.Modification;
    }

    return keyData.Release + '.' + modification;
  }

  // Get License Key Type based on the input key type, with a default mapping to API codes.
  private string getLicenseKeyType(string keyType) {
    string keyTypeAPICode = '';
    string KEYTYPE_APICODE_GENERIC = 'T';
    string KEYTYPE_APICODE_PERMENANT = 'P';
    string KEYTYPE_APICODE_SPECIFIC_TERM = 'T';

    if (keyType == KEYTYPE_PERMANENT)
      keyTypeAPICode = KEYTYPE_APICODE_PERMENANT;
    if (keyType == KEYTYPE_GENERIC)
      keyTypeAPICode = KEYTYPE_APICODE_GENERIC;
    if (keyType == KEYTYPE_SPECIFIC_TEMPORARY)
      keyTypeAPICode = KEYTYPE_APICODE_SPECIFIC_TERM;

    return keyTypeAPICode;
  }

  // Get Tier Points based on the input key data, with a specific format for the tier points string.
  private string getTierPoints(SequelQueryBuilderKeyData brandKeyData) {
    String tier = 'S1';
    tier += 'C' + brandKeyData.NumberOfConnectors;
    tier += 'U' + brandKeyData.NumberOfDesigners;
    tier += 'D' + brandKeyData.NumberOfDesigners;
    tier += 'W' + brandKeyData.NumberOfDesigners;
    tier += 'T' + brandKeyData.HasDataDecorations;
    return tier;
  }
}