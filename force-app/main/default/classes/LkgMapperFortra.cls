public with sharing class LkgMapperFortra extends LkgMapperBase {
  @TestVisible
  private static final String WEBAPPS_DEFAULT = 'B0';
  @TestVisible
  private static final String CONTAINERS_DEFAULT = 'C0';
  @TestVisible
  private static final String CAPABILITIES_DEFAULT = 'D1';
  @TestVisible
  private static final String RNA_COUNT_DEFAULT = 'E5';
  @TestVisible
  private static final String LICENSE_FORMAT_VERSION_DEFAULT = 'S2';

  protected override LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderFortra.FortraKeyData();
  }

  protected override void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    String product = uiPayload.productData.identifierName;
    LkgRequestBuilderFortra.FortraKeyData fortraKeyData = (LkgRequestBuilderFortra.FortraKeyData) keyData;

    fortraKeyData.ProductCode = uiPayload.productData.productCode;
    fortraKeyData.HardwareId = uiPayload.attributes.get(silo + '_Hardware_Id');
    fortraKeyData.tiers = getTiers(safeParseInt(uiPayload.attributes.get(silo + '_Number_of_Ips')));
  }

  private String getTiers(Integer ips) {
    String result = '';
    result += getIps(ips);
    result += getWebApps();
    result += getContainers();
    result += getCapabilities();
    result += getRnaCount();
    result += getLicenseFormatVersion();
    return result;
  }

  private String getIps(Integer ips) {
    String result = 'A';
    String ipsStr;
    if (ips != null) {
      ipsStr = String.valueOf(ips);
      ipsStr = ipsStr.replace(',', '');
    } else {
      ipsStr = '0';
    }
    result += ipsStr;

    return result;
  }

  private String getWebApps() {
    return WEBAPPS_DEFAULT;
  }

  private String getContainers() {
    return CONTAINERS_DEFAULT;
  }

  private String getCapabilities() {
    return CAPABILITIES_DEFAULT;
  }

  private String getRnaCount() {
    return RNA_COUNT_DEFAULT;
  }

  private String getLicenseFormatVersion() {
    return LICENSE_FORMAT_VERSION_DEFAULT;
  }
}