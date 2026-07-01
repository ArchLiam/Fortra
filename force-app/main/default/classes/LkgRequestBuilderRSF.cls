public with sharing class LkgRequestBuilderRSF extends LkgRequestBuilderBase {
  // This enum defines the parameter keys for the RSF brand, which will be used to map the dynamic parameters in the request.
  public enum RSFParameters {
    ProductCode,
    ExpirationDate,
    LParSerialNumber,
    Flag
  }

  // This inner class is used to hold the key data specific to RSF brand, extending the base KeyData class.
  public class RSFKeyData extends LkgRequestBuilderBase.KeyData {
    public String Flag;
    public String Release;
    public String Modification;
    public String LParSerialNumber;
  }

  // This method is used to get the dynamic parameters for RSF brand based on the input key data.
  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    // Cast the base KeyData to RSFKeyData to access RSF-specific fields.
    RSFKeyData brandKeyData = (RSFKeyData) keyData;

    // Initialize a map to hold the dynamic parameters that will be sent in the license key request.
    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    // set Product Code.
    dynamicParameters.put(RSFParameters.ProductCode.ordinal(), brandKeyData.ProductCode);

    // set Expiration Date with default value if not provided.
    dynamicParameters.put(
      RSFParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(brandKeyData.ExpirationDate)
    );

    // set Serial Number with default value if not provided.
    dynamicParameters.put(
      RSFParameters.LParSerialNumber.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.LParSerialNumber, '')
    );

    // set Flag with default value.
    dynamicParameters.put(RSFParameters.Flag.ordinal(), getStringOrDefaultIfNull(brandKeyData.Flag, '0'));

    return dynamicParameters;
  }
}