public with sharing class LkgRequestBuilderHalcyonIbm extends LkgRequestBuilderBase {
  public static final Datetime maxDate = Datetime.newInstance(4000, 12, 31, 0, 0, 0);

  public enum HalcyonIbmParameters {
    subsilo,
    productCode,
    apiKeyType,
    expirationDate,
    lparSystemName,
    lparSerialNumber,
    modelNumber,
    featureCode,
    lparNumber,
    performanceGroup,
    cores,
    productSuiteCode
  }

  public class HalcyonIbmKeyData extends LkgRequestBuilderBase.KeyData {
    public String featureCode;
    public String modelNumber;
    public String cores;
    public String performanceGroup;
    public String lparSystemName;
    public String lparSerialNumber;
    public String lparNumber;
    public String individualMonitors;
    public String individualProducts;
  }

  public override virtual Map<Integer, Object> GetDynamicParameters(KeyData keyData) {
    HalcyonIbmKeyData siloKeyData = (HalcyonIbmKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();
    dynamicParameters.put(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.subsilo.ordinal(), siloKeyData.subsilo);

    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.productCode.ordinal(),
      getProductCode(siloKeyData)
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.apiKeyType.ordinal(),
      getApiKeyType(siloKeyData.KeyType)
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.expirationDate.ordinal(),
      getExpirationDateString(siloKeyData)
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparSystemName.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.lparSystemName, '')
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparSerialNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.lparSerialNumber, '')
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.modelNumber.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.modelNumber, '')
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.featureCode.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.featureCode, '')
    );
    dynamicParameters.put(LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.lparNumber.ordinal(), '0');
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.performanceGroup.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.performanceGroup, '')
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.cores.ordinal(),
      getStringOrDefaultIfNull(siloKeyData.cores, '0')
    );
    dynamicParameters.put(
      LkgRequestBuilderHalcyonIbm.HalcyonIbmParameters.productSuiteCode.ordinal(),
      siloKeyData.internalProductName
    );
    return dynamicParameters;
  }

  private String getApiKeyType(String keyType) {
    if (
      keyType == LkgRequestBuilderBase.KEYTYPE_GENERIC ||
      keyType == LkgRequestBuilderBase.KEYTYPE_SPECIFIC_TEMPORARY
    ) {
      return 'D';
    }
    if (keyType == LkgRequestBuilderBase.KEYTYPE_PERMANENT) {
      return 'P';
    }

    return '';
  }

  private String getExpirationDateString(HalcyonIbmKeyData siloKeyData) {
    Date expirationDate = siloKeyData.ExpirationDate;

    if (siloKeyData.KeyType == LkgRequestBuilderBase.KEYTYPE_PERMANENT && siloKeyData.ExpirationDate == null) {
      expirationDate = maxDate.date();
    }

    return getFormattedExpirationDate(expirationDate);
  }

  private String getProductCode(LkgRequestBuilderHalcyonIbm.HalcyonIbmKeyData siloKeyData) {
    Set<String> productCodes = new Set<String>();

    addProductCodes(productCodes, siloKeyData.individualProducts);
    addProductCodes(productCodes, siloKeyData.individualMonitors);

    String sortedProduct = JSON.serialize(sortProductCodes(productCodes));

    Integer bitLength = 36;
    String productCode = '';
    List<String> sortedMonitors = sortProductCodes(productCodes);
    for (Integer i = 1; i <= bitLength; i++) {
      if (sortedMonitors.contains(String.valueOf(i))) {
        productCode += '1';
      } else {
        productCode += '0';
      }
    }

    return productCode;
  }

  private void addProductCodes(Set<String> productCodes, String rawJsonArray) {
    if (String.isBlank(rawJsonArray)) {
      return;
    }

    for (Object rawValue : (List<Object>) JSON.deserializeUntyped(rawJsonArray)) {
      if (rawValue != null) {
        productCodes.add(String.valueOf(rawValue));
      }
    }
  }

  private List<String> sortProductCodes(Set<String> productCodes) {
    List<Integer> numericCodes = new List<Integer>();

    for (String productCode : productCodes) {
      try {
        numericCodes.add(Integer.valueOf(productCode));
      } catch (Exception e) {
        List<String> sortedProductCodes = new List<String>(productCodes);
        sortedProductCodes.sort();
        return sortedProductCodes;
      }
    }

    numericCodes.sort();

    List<String> sortedProductCodes = new List<String>();
    for (Integer numericCode : numericCodes) {
      sortedProductCodes.add(String.valueOf(numericCode));
    }

    return sortedProductCodes;
  }
}