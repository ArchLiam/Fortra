public virtual with sharing class LkgRequestBuilderBase implements ILkgRequestBuilder {
  public static final String KEYTYPE_PERMANENT = 'Permanent';
  public static final String KEYTYPE_GENERIC = 'Generic';
  public static final String KEYTYPE_SPECIFIC_TEMPORARY = 'Specific_Temporary';

  public virtual class KeyData {
    public String KeyType;
    public Date ExpirationDate;
    public String ProductCode;
    public Integer Instances;
    public String lkgProductIdentifierName;
    public String internalProductName;
    public String externalProductName;
    public Boolean SendEmail;
    public String Silo;
    public String subSilo;
    public Id AccountId;
    public String Brand;
    public Id Contact1Id;
    public Id Contact2Id;
    public Date StartDate;
    public String HardwareId;
    public String LicenseKey;
    public Integer NumberOfUsers;
    public String serialNumber;
    public String requestParameters;
    public String responseMessage;
    public Boolean createLicenseKeyFile;
    public String Notes;
    public String release;
  }

  public LkgProcessor.LicenseKeyRequest buildRequest(KeyData keyData) {
    LkgProcessor.LicenseKeyRequest licenseKeyRequest = new LkgProcessor.LicenseKeyRequest();

    licenseKeyRequest.silo = GetSiloName(keyData);
    licenseKeyRequest.subSilo = keyData.subSilo;
    licenseKeyRequest.productCode = keyData.ProductCode;
    licenseKeyRequest.hardwareId = keyData.HardwareId;
    licenseKeyRequest.lkgProductIdentifierName = keyData.lkgProductIdentifierName;
    licenseKeyRequest.internalProductName = keyData.internalProductName;
    licenseKeyRequest.externalProductName = keyData.externalProductName;

    licenseKeyRequest.dynamicParameters = GetDynamicParameters(keyData);

    return licenseKeyRequest;
  }

  public virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    return null;
  }

  public virtual String GetSiloName(KeyData keyData) {
    return keyData.silo;
  }

  protected String getFormattedExpirationDate(Date expirationDate) {
    string expirationDateString = '';
    if (expirationDate != null) {
      Datetime expirationDateTime = Datetime.newInstance(expirationDate, Time.newInstance(0, 0, 0, 0));
      expirationDateString = expirationDateTime.format('yyyyMMdd');
    }
    return expirationDateString;
  }

  protected String getStringOrDefaultIfNull(String value, String defaultValue) {
    if (value != null) {
      return value;
    }
    return defaultValue;
  }

  protected String getIntegerStringOrDefaultIfNull(Integer value, String defaultValue) {
    if (value != null) {
      // Remove any commas from the integer value
      String valueStr = String.valueOf(value);
      valueStr = valueStr.replace(',', '');
      return valueStr;
    }
    return defaultValue;
  }

  protected String toBinaryString(Integer value) {
    Integer binaryBase = 2;
    String binaryString = '';

    while (value > 0) {
      Integer remainder = Math.mod(value, binaryBase);

      value = value / binaryBase;

      binaryString = remainder.toString() + binaryString;
    }

    return binaryString;
  }
}