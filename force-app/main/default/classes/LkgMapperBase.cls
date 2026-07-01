public virtual with sharing class LkgMapperBase implements ILkgMapper {
  public class UiPayload {
    public Id accountId;
    public Id contact1Id;
    public Id contact2Id;
    public String expirationDate;
    public String keyType;
    public Boolean sendEmail;
    public ProductData productData;
    public Map<String, String> attributes;
  }

  public class ProductData {
    public String silo;
    public String subSilo;
    public String brandName;
    public String productCode;
    public String name;
    public String identifierName;
    public String externalName;
    public String internalName;
    public Boolean isSupportProduct;
    public String productMetadataRecordId;
    public Map<String, String> defaultAttributes;
  }

  public LkgRequestBuilderBase.KeyData mapPayloadToKeyData(string payload) {
    LkgMapperBase.UiPayload uiPayload = (LkgMapperBase.UiPayload) JSON.deserialize(
      payload,
      LkgMapperBase.UiPayload.class
    );

    // log json format of uiPayload
    System.debug('---LkgMapperBase UiPayload:---');
    System.debug(JSON.serializePretty(uiPayload));

    LkgRequestBuilderBase.KeyData keyData = createKeyDataInstance();

    mapBaseFields(uiPayload, keyData);
    mapSiloFields(uiPayload, keyData);

    // log json format of keyData
    System.debug('---LkgMapperBase KeyData:---');
    System.debug(JSON.serializePretty(keyData));

    return keyData;
  }

  protected virtual LkgRequestBuilderBase.KeyData createKeyDataInstance() {
    return new LkgRequestBuilderBase.KeyData();
  }

  protected void mapBaseFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    String silo = uiPayload.productData.silo;
    keyData.subSilo = uiPayload.productData.subSilo;
    keyData.AccountId = uiPayload.accountId;
    keyData.Brand = uiPayload.productData.brandName;
    keyData.Contact1Id = uiPayload.contact1Id;
    keyData.Contact2Id = uiPayload.contact2Id;
    keyData.ExpirationDate = Date.valueOf(uiPayload.expirationDate);
    keyData.externalProductName = uiPayload.productData.externalName;
    keyData.internalProductName = uiPayload.productData.internalName;
    keyData.KeyType = resolveKeyType(uiPayload.keyType);
    keyData.lkgProductIdentifierName = uiPayload.productData.identifierName;
    keyData.release = uiPayload.attributes.get(silo + '_Release');
    keyData.ProductCode = uiPayload.productData.productCode;
    keyData.SendEmail = uiPayload.sendEmail;
    keyData.Silo = uiPayload.productData.silo;
    keyData.StartDate = Date.today();
    keyData.createLicenseKeyFile = false; // Default to false, can be overridden by silo-specific mappers if needed
    keyData.Notes = uiPayload.attributes.get('Notes') == null ? '' : uiPayload.attributes.get('Notes'); // Ensure Notes is not null
  }

  protected virtual void mapSiloFields(LkgMapperBase.UiPayload uiPayload, LkgRequestBuilderBase.KeyData keyData) {
    // To be implemented by subclasses
  }

  protected Integer safeParseInt(String value) {
    try {
      return Integer.valueOf(value);
    } catch (Exception e) {
      return null;
    }
  }

  private String resolveKeyType(String keyType) {
    LKG_Key_Type__mdt keyTypeMdt = LKG_Key_Type__mdt.getInstance(keyType);

    if (keyTypeMdt != null) {
      system.debug('Resolved Key Type from Metadata: ' + keyTypeMdt.Type__c.replace('/', '_'));
      return keyTypeMdt.Type__c.replace('/', '_');
    }
    return keyType;
  }
}