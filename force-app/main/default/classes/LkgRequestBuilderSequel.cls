public with sharing class LkgRequestBuilderSequel extends LkgRequestBuilderBase {
  private final string MIN_RELEASE_OF_QUERY_AND_REPORT_WRITER = '25';

  // This enum defines the parameter keys for the Sequel brand, which will be used to map the dynamic parameters in the request.
  public enum SequelParameters {
    ProductCode,
    Version,
    LicenseKeyType,
    ExpirationDate,
    LParSerialNumber,
    ModelNumber,
    FeatureCode,
    LParNumber,
    LParEnd,
    NumberOfUsers,
    NumberOfProcessors,
    ProcessorType,
    IAspGroup
  }

  // This inner class is used to hold the key data specific to Sequel brand, extending the base KeyData class.
  public class SequelKeyData extends LkgRequestBuilderBase.KeyData {
    public String Modification;
    public String LParSerialNumber;
    public String ModelNumber;
    public String FeatureCode;
    public String LParNumber;
    public String LParEnd;
    public Integer NumberOfProcessors;
    public String ProcessorType;
    public String IAspGroup;
    public String LParName;
    public String PermTermVersionRange;
  }

  // This method is used to get the dynamic parameters for Sequel brand based on the input key data.
  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    // Cast the base KeyData to SequelKeyData to access Sequel-specific fields.
    SequelKeyData brandKeyData = (SequelKeyData) keyData;

    // Initialize a map to hold the dynamic parameters that will be sent in the license key request.
    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    // set Product Code.
    dynamicParameters.put(SequelParameters.ProductCode.ordinal(), brandKeyData.ProductCode);

    // set Version Index based on Product Code.
    dynamicParameters.put(SequelParameters.Version.ordinal(), getVersionIndex(brandKeyData));

    //set License Key Type
    dynamicParameters.put(SequelParameters.LicenseKeyType.ordinal(), getLicenseKeyType(brandKeyData));

    // set Expiration Date with default value if not provided.
    dynamicParameters.put(
      SequelParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(brandKeyData.ExpirationDate)
    );

    // set Serial Number with default value if not provided.
    dynamicParameters.put(
      SequelParameters.LParSerialNumber.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.LParSerialNumber, '')
    );

    // set Model Number with default value if not provided.
    dynamicParameters.put(
      SequelParameters.ModelNumber.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.ModelNumber, '')
    );

    // set Feature Code with default value if not provided.
    dynamicParameters.put(
      SequelParameters.FeatureCode.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.FeatureCode, '')
    );

    // set LPar Number with default value if not provided.
    dynamicParameters.put(SequelParameters.LParNumber.ordinal(), getStringOrDefaultIfNull(brandKeyData.LParNumber, ''));

    // set LPar End with default value if not provided.
    dynamicParameters.put(SequelParameters.LParEnd.ordinal(), getStringOrDefaultIfNull(brandKeyData.LParEnd, ''));
    // set Number Of Users with default value if not provided.
    dynamicParameters.put(
      SequelParameters.NumberOfUsers.ordinal(),
      getIntegerStringOrDefaultIfNull(brandKeyData.NumberOfUsers, '0')
    );
    // set Number Of Processors with default value if not provided.
    dynamicParameters.put(
      SequelParameters.NumberOfProcessors.ordinal(),
      getIntegerStringOrDefaultIfNull(brandKeyData.NumberOfProcessors, '0')
    );
    // set Processor Type with default value if not provided.
    dynamicParameters.put(
      SequelParameters.ProcessorType.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.ProcessorType, '')
    );
    // set IAsp Group with default value if not provided.
    dynamicParameters.put(SequelParameters.IAspGroup.ordinal(), getStringOrDefaultIfNull(brandKeyData.IAspGroup, ''));

    return dynamicParameters;
  }

  // Get Version
  private string getVersionIndex(SequelKeyData keyData) {
    if (keyData.release == null || keyData.release == '')
      return '';

    string modification = '00';

    if (keyData.Modification != null && keyData.Modification != '') {
      modification = keyData.Modification;
    }

    // For Product Code 915, if the release is less than 25,
    // set modification to minimum release of query and report writer to ensure the correct version is picked in license key generation.
    if (
      keyData.ProductCode == '915' &&
      keyData.lkgProductIdentifierName != null &&
      keyData.lkgProductIdentifierName == 'SQ915_QRWriter'
    ) {
      if (modification < MIN_RELEASE_OF_QUERY_AND_REPORT_WRITER) {
        modification = MIN_RELEASE_OF_QUERY_AND_REPORT_WRITER;
      }
    }

    return 'R' + keyData.release + 'M' + modification;
  }

  private string getLicenseKeyType(SequelKeyData brandKeyData) {
    string keyTypeAPICode = '';
    string KEYTYPE_APICODE_GENERIC = '1';
    string KEYTYPE_APICODE_PERMENANT = '0';
    string KEYTYPE_APICODE_SPECIFIC_TERM = '5';

    if (brandKeyData.KeyType == KEYTYPE_PERMANENT) {
      keyTypeAPICode = KEYTYPE_APICODE_PERMENANT;
    } else if (brandKeyData.KeyType == KEYTYPE_GENERIC) {
      keyTypeAPICode = KEYTYPE_APICODE_GENERIC;
    } else if (brandKeyData.KeyType == KEYTYPE_SPECIFIC_TEMPORARY) {
      keyTypeAPICode = LkgTermPermRangeChecker.shouldConvertTermToPerm(
          brandKeyData.release,
          brandKeyData.Modification,
          brandKeyData.PermTermVersionRange
        )
        ? KEYTYPE_APICODE_PERMENANT
        : KEYTYPE_APICODE_SPECIFIC_TERM;
    }

    return keyTypeAPICode;
  }
}