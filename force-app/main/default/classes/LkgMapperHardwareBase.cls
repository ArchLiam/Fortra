public virtual with sharing class LkgMapperHardwareBase implements ILkgMapper {
  /**
   * Hardware payload structure - different from UI-based payload
   * This supports both single asset and batch processing scenarios
   */
  public class HardwarePayload {
    public String source; // 'hardware' - used to identify this as hardware-based request
    public Id accountId;
    public Id contact1Id;
    public Id contact2Id;
    public Boolean sendEmail;

    // Single asset mode (for processing individual assets)
    public Id assetId;
    public Id hardwareId;

    // Batch mode (for processing multiple assets - used by generateKeysForHardware)
    public List<HardwareRecord> hardwareRecords;

    // Key type and expiration (common to all assets in the payload)
    public String keyType;
    public String expirationDate;

    // Additional attributes
    public Map<String, String> attributes;
  }

  public class HardwareRecord {
    public Id hardwareId;
    public List<Id> assetIds;
  }

  /**
   * Asset data structure - populated from Asset and related objects
   * Fields will be populated dynamically based on silo requirements
   */
  public class AssetData {
    public Id assetId;
    public Id hardwareId;
    public Id accountId;
    public String assetName;
    public String serialNumber;
    public String status;
    public String productCode;
    public String productName;
    public String productVersion;
    public String productModification;
    public LkgMapperBase.ProductData productData;
    public Map<String, String> attributes;

    // Silo-specific fields will be populated by subclass mappers
    // These fields may come from:
    // - Asset fields
    // - Hardware__c fields
    // - Product2 fields
    // - Custom metadata
  }

  /**
   * Main mapping method - implements ILkgMapper interface
   * This method orchestrates the mapping process for hardware-based payloads
   */
  public LkgRequestBuilderBase.KeyData mapPayloadToKeyData(String payload) {
    HardwarePayload hwPayload = (HardwarePayload) JSON.deserialize(payload, HardwarePayload.class);

    System.debug('---LkgMapperHardwareBase HardwarePayload:---');
    System.debug(JSON.serializePretty(hwPayload));

    // Validate that this is a hardware payload
    if (hwPayload.source != 'hardware') {
      throw new HardwareMapperException('Invalid payload source. Expected "hardware", got: ' + hwPayload.source);
    }

    // For single asset mode, assetId must be provided
    if (hwPayload.assetId == null) {
      throw new HardwareMapperException('Asset ID is required for hardware-based key generation');
    }

    // Query asset data
    AssetData assetData = queryAssetData(hwPayload.assetId, hwPayload.hardwareId);
    System.debug('---LkgMapperHardwareBase assetData:---');
    System.debug(JSON.serializePretty(assetData));
    
    LkgHardwareAssetEnrichmentService.Result result =
        LkgHardwareAssetEnrichmentService.enrich(assetData);

    System.debug('---LkgMapperHardwareBase assetData Enriched:---');
    System.debug(JSON.serializePretty(assetData));

    if (!result.errors.isEmpty()) {
        // UI-safe message
        throw new AuraHandledException(String.join(result.errors, ' | '));
    }

    // Create KeyData instance
    //LkgRequestBuilderBase.KeyData keyData = createKeyDataInstance();
    
    LkgRequestBuilderBase.KeyData keyData =
        LkgHardwareKeyDataFactory.createKeyDataInstance(assetData);

    System.debug('---LkgMapperHardwareBase KeyData before silo add:---');
    System.debug(JSON.serializePretty(keyData));


    // Map base fields from payload and asset
    mapBaseFields(hwPayload, assetData, keyData);

    // Map silo-specific fields (to be implemented by subclasses)
    LkgHardwareKeyService.addKeyDataFromAsset(assetData, keyData);

    System.debug('---LkgMapperHardwareBase KeyData:---');
    System.debug(JSON.serializePretty(keyData));

    return keyData;
  }

  /**
   * Create KeyData instance - can be overridden by subclasses for silo-specific KeyData types
   */
  // protected virtual LkgRequestBuilderBase.KeyData createKeyDataInstance() {
  //   return new LkgRequestBuilderBase.KeyData();
  // }

  /**
   * Query asset data from Salesforce
   * This base implementation queries common fields
   * Subclasses can override to add silo-specific fields
   */
  protected virtual AssetData queryAssetData(Id assetId, Id hardwareId) {
    AssetData assetData = new AssetData();

    List<Asset> assets = [
      SELECT
        Id,
        Name,
        SerialNumber,
        Status,
        AccountId,
        ProductCode,
        Product2Id,
        Product2.Name,
        Product_Version__c,
        Hardware__c,
        Hardware__r.Serial_Number__c,
        Hardware__r.Status__c
      FROM Asset
      WHERE Id = :assetId
      LIMIT 1
    ];

    if (assets.isEmpty()) {
      throw new HardwareMapperException('Asset not found: ' + assetId);
    }

    Asset asset = assets[0];

    // Validate hardware relationship if provided
    if (hardwareId != null && asset.Hardware__c != hardwareId) {
      throw new HardwareMapperException('Asset ' + assetId + ' is not associated with Hardware ' + hardwareId);
    }

    // Populate asset data
    assetData.assetId = asset.Id;
    assetData.hardwareId = asset.Hardware__c;
    assetData.accountId = asset.AccountId;
    assetData.assetName = asset.Name;
    assetData.serialNumber = asset.SerialNumber;
    assetData.status = asset.Status;
    assetData.productCode = asset.productCode;
    assetData.productName = asset.Product2?.Name;
    assetData.productVersion = asset.Product_Version__c;

    return assetData;
  }

  /**
   * Map base fields from hardware payload and asset data to KeyData
   */
  protected void mapBaseFields(HardwarePayload hwPayload, AssetData assetData, LkgRequestBuilderBase.KeyData keyData) {
    // Account and contact information
    keyData.AccountId = hwPayload.accountId != null ? hwPayload.accountId : assetData.accountId;
    keyData.Contact1Id = hwPayload.contact1Id;
    keyData.Contact2Id = hwPayload.contact2Id;
    keyData.SendEmail = hwPayload.sendEmail != null ? hwPayload.sendEmail : false;

    // Key type and dates
    keyData.KeyType = hwPayload.keyType;
    if (String.isNotBlank(hwPayload.expirationDate)) {
      keyData.ExpirationDate = Date.valueOf(hwPayload.expirationDate);
    }
    keyData.StartDate = Date.today();

    // Asset and hardware information
    keyData.HardwareId = assetData.hardwareId != null ? String.valueOf(assetData.hardwareId) : null;
    keyData.serialNumber = assetData.serialNumber;

    // Product information
    keyData.ProductCode = assetData.productData.productCode;
    keyData.externalProductName = assetData.productData.externalName;
    keyData.internalProductName = assetData.productData.internalName; // May be overridden by subclasses

    // Silo will be determined by subclass based on product/metadata
    keyData.Silo=assetData.productData.silo;
    keyData.subSilo=assetData.productData.subSilo;

    // Default settings
    keyData.createLicenseKeyFile = false; // Can be overridden by silo-specific mappers
    keyData.Notes = hwPayload.attributes?.get('Notes');
  }

  /**
   * Map silo-specific fields from asset data
   * To be implemented by subclasses
   * This is where silo-specific logic will determine:
   * - keyData.Silo
   * - keyData.subSilo
   * - keyData.Brand
   * - keyData.lkgProductIdentifierName
   * - Any other silo-specific fields
   */
  /* protected virtual void mapSiloFieldsFromAsset(
    HardwarePayload hwPayload,
    AssetData assetData,
    LkgRequestBuilderBase.KeyData keyData
  ) {
    // To be implemented by subclasses
  } */

  /**
   * Helper method for safe integer parsing
   */
  protected Integer safeParseInt(String value) {
    try {
      return Integer.valueOf(value);
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Custom exception for hardware mapper errors
   */
  public class HardwareMapperException extends Exception {
  }
}