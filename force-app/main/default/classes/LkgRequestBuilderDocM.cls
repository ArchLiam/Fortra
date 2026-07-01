public with sharing class LkgRequestBuilderDocM extends LkgRequestBuilderBase {
  private static final String DEFAULT_TIER_KEY = 'S2';

  public enum DocMParameters {
    ProductCode,
    Version,
    Hardware,
    Points,
    KeyType,
    ExpirationDate
  }

  public class DocMKeyData extends LkgRequestBuilderBase.KeyData {
    public String Modification;
    public String Tier;
  }

  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    DocMKeyData brandKeyData = (DocMKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    // set product code
    dynamicParameters.put(DocMParameters.ProductCode.ordinal(), brandKeyData.ProductCode);

    // set version
    dynamicParameters.put(DocMParameters.Version.ordinal(), getVersion(brandKeyData));

    // set hardware id
    dynamicParameters.put(DocMParameters.Hardware.ordinal(), getStringOrDefaultIfNull(brandKeyData.HardwareId, ''));

    // set tier/points
    dynamicParameters.put(DocMParameters.Points.ordinal(), getTierCode(brandKeyData));

    // set key type
    dynamicParameters.put(DocMParameters.KeyType.ordinal(), getKeyType(brandKeyData));

    // set expiration date
    dynamicParameters.put(
      DocMParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(brandKeyData.ExpirationDate)
    );

    return dynamicParameters;
  }

  // version
  private string getVersion(DocMKeyData keyData) {
    if (keyData.release == null || keyData.release == '') {
      return '';
    }
    string modification = '00';
    if (keyData.Modification != null && keyData.Modification != '') {
      modification = keyData.Modification;
    }
    string version = keyData.release + '.' + modification;
    return version;
  }

  // Tier Code
  private string getTierCode(LkgRequestBuilderDocM.DocMKeyData keyData) {
    string tierCode = DEFAULT_TIER_KEY;

    if (keyData.Tier != null && keyData.Tier != '') {
      tierCode = keyData.Tier;
    } else if (keyData.NumberOfUsers != 0)
      tierCode += 'A' + keyData.NumberOfUsers.toString();

    return tierCode;
  }

  private string getKeyType(LkgRequestBuilderDocM.DocMKeyData keyData) {
    if (keyData.KeyType == 'Permanent')
      return 'P';
    if (keyData.KeyType == 'Generic' || keyData.KeyType == 'Specific_Temporary')
      return 'T';
    return '';
  }
}