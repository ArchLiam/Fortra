public with sharing class LkgRequestBuilderRobot extends LkgRequestBuilderBase {
  // This enum defines the parameter keys for the Robot brand, which will be used to map the dynamic parameters in the request.
  public enum RobotParameters {
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

  // This inner class is used to hold the key data specific to Robot brand, extending the base KeyData class.
  public class RobotKeyData extends LkgRequestBuilderBase.KeyData {
    public String Version;
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

  // This method is used to get the dynamic parameters for Robot brand based on the input key data.
  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    // Cast the base KeyData to RobotKeyData to access Robot-specific fields.
    RobotKeyData brandKeyData = (RobotKeyData) keyData;

    // Initialize a map to hold the dynamic parameters that will be sent in the license key request.
    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    // set Product Code.
    dynamicParameters.put(RobotParameters.ProductCode.ordinal(), brandKeyData.ProductCode);

    // set Version Index based on Product Code.
    dynamicParameters.put(RobotParameters.Version.ordinal(), getVersion(brandKeyData));

    //set License Key Type
    dynamicParameters.put(RobotParameters.LicenseKeyType.ordinal(), getLicenseKeyType(brandKeyData));

    // set Expiration Date with default value if not provided.
    dynamicParameters.put(
      RobotParameters.ExpirationDate.ordinal(),
      getFormattedExpirationDate(brandKeyData.ExpirationDate)
    );

    // set LPar Serial Number with default value if not provided.
    dynamicParameters.put(
      RobotParameters.LParSerialNumber.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.LParSerialNumber, '')
    );

    // set Model Number with default value if not provided.
    dynamicParameters.put(
      RobotParameters.ModelNumber.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.ModelNumber, '')
    );

    // set Feature Code with default value if not provided.
    dynamicParameters.put(
      RobotParameters.FeatureCode.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.FeatureCode, '')
    );

    // set LPar Number with default value if not provided.
    dynamicParameters.put(RobotParameters.LParNumber.ordinal(), getStringOrDefaultIfNull(brandKeyData.LParNumber, ''));

    // set LPar End with default value if not provided.
    dynamicParameters.put(RobotParameters.LParEnd.ordinal(), getStringOrDefaultIfNull(brandKeyData.LParEnd, ''));
    // set Number Of Users with default value if not provided.
    dynamicParameters.put(
      RobotParameters.NumberOfUsers.ordinal(),
      getIntegerStringOrDefaultIfNull(brandKeyData.NumberOfUsers, '0')
    );
    // set Number Of Processors with default value if not provided.
    dynamicParameters.put(
      RobotParameters.NumberOfProcessors.ordinal(),
      getIntegerStringOrDefaultIfNull(brandKeyData.NumberOfProcessors, '0')
    );
    // set Processor Type with default value if not provided.
    dynamicParameters.put(
      RobotParameters.ProcessorType.ordinal(),
      getStringOrDefaultIfNull(brandKeyData.ProcessorType, '')
    );
    // set IAsp Group with default value if not provided.
    dynamicParameters.put(RobotParameters.IAspGroup.ordinal(), getStringOrDefaultIfNull(brandKeyData.IAspGroup, ''));

    System.debug(LoggingLevel.DEBUG, 'Dynamic Parameters: ' + dynamicParameters);

    return dynamicParameters;
  }

  private string getLicenseKeyType(RobotKeyData brandKeyData) {
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

  private string getElements(string productCode) {
    string elements = '1';

    if (productCode == '5') {
      elements = '3';
    } else if (productCode == '11') {
      elements = '7';
    }

    return elements;
  }

  private string getVersion(LkgRequestBuilderRobot.RobotKeyData brandKeyData) {
    if (brandKeyData.release == null || brandKeyData.release == '')
      return '';

    string modification = '00';
    if (brandKeyData.Modification != null && brandKeyData.Modification != '') {
      modification = brandKeyData.Modification;
    }
    string version = 'R' + brandKeyData.release + 'M' + modification;
    return version;
  }
}