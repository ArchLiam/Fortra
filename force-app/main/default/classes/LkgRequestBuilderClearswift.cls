public with sharing class LkgRequestBuilderClearswift extends LkgRequestBuilderBase {
  static public final DateTime expirationDefault = Datetime.newInstance(3000, 1, 1);

  public enum ClearswiftParameters {
    CompanyName,
    ExpirationType,
    ExpirationDate,
    ProductCode,
    LanguageIndex,
    VersionIndex,
    ServerCount,
    UserCount,
    Elements
  }

  public class ClearswiftKeyData extends LkgRequestBuilderBase.KeyData {
    public String accountName;
  }

  public override Map<Integer, Object> GetDynamicParameters(LkgRequestBuilderBase.KeyData keyData) {
    ClearswiftKeyData brandKeyData = (ClearswiftKeyData) keyData;

    Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

    dynamicParameters.put(ClearswiftParameters.CompanyName.ordinal(), brandKeyData.accountName);

    Date expirationDate = null;

    if (brandKeyData.KeyType == 'Permanent') {
      dynamicParameters.put(ClearswiftParameters.ExpirationType.ordinal(), '0');
      expirationDate = expirationDefault.date();
    } else if (
      brandKeyData.KeyType == 'Generic' ||
      brandKeyData.KeyType == 'Specific_Temporary' ||
      brandKeyData.KeyType == 'Subscription'
    ) {
      dynamicParameters.put(ClearswiftParameters.ExpirationType.ordinal(), '1');
      expirationDate = brandKeyData.ExpirationDate;
    }

    dynamicParameters.put(ClearswiftParameters.ExpirationDate.ordinal(), getFormattedExpirationDate(expirationDate));
    dynamicParameters.put(ClearswiftParameters.ProductCode.ordinal(), brandKeyData.ProductCode);
    dynamicParameters.put(ClearswiftParameters.LanguageIndex.ordinal(), '0');
    dynamicParameters.put(ClearswiftParameters.VersionIndex.ordinal(), getVersionIndex(brandKeyData.ProductCode));
    dynamicParameters.put(ClearswiftParameters.ServerCount.ordinal(), '0');
    dynamicParameters.put(ClearswiftParameters.UserCount.ordinal(), brandKeyData.NumberOfUsers);
    dynamicParameters.put(ClearswiftParameters.Elements.ordinal(), getElements(brandKeyData.ProductCode));

    return dynamicParameters;
  }

  private string getVersionIndex(string productCode) {
    String versionIndex = '0';

    if (productCode == '5' || productCode == '11') {
      versionIndex = '4';
    } else if (productCode == '13') {
      versionIndex = '2';
    }

    return versionIndex;
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
}