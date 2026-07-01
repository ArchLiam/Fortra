public with sharing class LkgProcessorHardwareKeys {
  public class HardwareLicenseKeyRequest {
    public String source;
    public String silo;
    public String subSilo;
    public String productCode;
    public String version;
    public String keyType;
    public String expirationDate;
    // Hardware-level fields
    public String hardwareId;
    public String hardwareRecordName;
    public String hardwareName;
    public String hardwareSerialNumber;
    public String serverType;
    public String featureCode;
    public String hostName;
    public String modelNumber;
    public String lkgProductIdentifierName;
    public String internalProductName;
    public String externalProductName;
    public Map<Integer, Object> dynamicParameters;
    // Asset-level fields
    public Id assetId;
    public String assetProductName;
    public String assetProductDescription;
    public String assetSerialNumber;
    public Decimal assetQuantity;
    public Datetime assetLifecycleStartDate;
    public Datetime assetLifecycleEndDate;
  }

  private LkgMapperFactory mapperFactory;
  private LkgRequestBuilderFactory requestBuilderFactory;
  private LkgRequestController requestController;
  private LkgRecordCreatorFactory recordCreatorFactory;

  public LkgProcessorHardwareKeys(
    LkgMapperFactory mapperFactory,
    LkgRequestBuilderFactory requestBuilderFactory,
    LkgRequestController requestController,
    LkgRecordCreatorFactory recordCreatorFactory
  ) {
    this.mapperFactory = mapperFactory;
    this.requestBuilderFactory = requestBuilderFactory;
    this.requestController = requestController;
    this.recordCreatorFactory = recordCreatorFactory;
  }

  /**
   * Execute hardware-based key generation for a single asset
   * @param payload JSON string containing hardware-based key generation data
   * @return LkgKeyGenResponse with key generation result
   */
  public LkgKeyGenResponse executeForAsset(String payload) {
    try {
      ILkgMapper mapper = mapperFactory.getMapper(payload);

      // Check if the mapper is valid
      if (mapper == null) {
        return LkgKeyGenResponse.error('Invalid Silo Mapper or Silo is not defined in LkgMapperFactory');
      }

      System.debug(LoggingLevel.DEBUG, 'Hardware Mapper: ' + mapper);

      LkgRequestBuilderBase.KeyData keyData = mapper.mapPayloadToKeyData(payload);

      ILkgRequestBuilder builder = requestBuilderFactory.getRequestBuilder(keyData.Silo, keyData.subSilo);

      if (builder == null) {
        return LkgKeyGenResponse.error(
          'Invalid Request Builder or Request Builder is not defined in LkgRequestBuilderFactory'
        );
      }

      System.debug(LoggingLevel.DEBUG, 'Request Builder: ' + builder);

      LkgProcessor.LicenseKeyRequest request = builder.buildRequest(keyData);

      System.debug(LoggingLevel.DEBUG, 'License Key Request: ' + JSON.serializePretty(request));

      String body = 'silo=' + EncodingUtil.urlEncode(request.silo, 'UTF-8');

      for (Integer i = 0; i < request.dynamicParameters.size(); i++) {
        String paramValue = String.valueOf(request.dynamicParameters.get(i));
        body += '&argv=' + EncodingUtil.urlEncode(paramValue, 'UTF-8');
      }

      // Generate license key from keygen service
      LkgKeyGenResult keyGenResult = requestController.generateLicenseKey(body);

      System.debug(LoggingLevel.DEBUG, 'KeyGen Result: ' + JSON.serializePretty(keyGenResult));

      keyGenResult.applyTo(keyData);

      ILkgRecordCreator recordCreator = recordCreatorFactory.getRecordCreator(keyData.Silo, keyData.subSilo);

      // Check if the record creator is valid
      if (recordCreator == null) {
        return LkgKeyGenResponse.error(
          'Invalid Record Creator or Record Creator is not defined in LkgRecordCreatorFactory'
        );
      }

      System.debug(LoggingLevel.DEBUG, 'Record Creator: ' + recordCreator);

      // Generate License Key record
      License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);

      // Temporarily set Send_Email__c to false to prevent trigger from firing until AFTER the attachment is created.
      // This avoids timing issues where the email is sent before the attachment exists.
      Boolean shouldSendEmail = licenseKey.Send_Email__c;
      licenseKey.Send_Email__c = false;

      recordCreator.insertLicenseKeyRecord(licenseKey);

      System.debug(LoggingLevel.DEBUG, 'License Key Record: ' + JSON.serializePretty(licenseKey));

      if (keyData.createLicenseKeyFile != null && keyData.createLicenseKeyFile) {
        Attachment attachment = recordCreator.createAttachment(licenseKey);
        if (attachment != null) {
          recordCreator.insertLicenseKeyRecord(attachment);
          System.debug(LoggingLevel.DEBUG, 'Attachment created and inserted: ' + attachment.Name);
        }
      }

      // Attachment is created, trigger the email if it was requested
      if (shouldSendEmail) {
        licenseKey.Send_Email__c = true;
        update licenseKey;
      }

      return LkgKeyGenResponse.success(keyData.LicenseKey, licenseKey.Id);
    } catch (LkgKeyGenResponse.KeyGenException e) {
      System.debug(LoggingLevel.ERROR, 'KeyGen Exception: ' + e.getMessage());
      return LkgKeyGenResponse.error(e.getMessage());
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
      return LkgKeyGenResponse.error('An unexpected error occurred: ' + e.getMessage());
    }
  }

  /**
   * Process multiple assets across multiple hardware records
   * @param hardwarePayload Hardware payload with nested structure
   * @return HardwareKeyGenResponse with per-asset results
   */
  public HardwareKeyGenResponse executeForHardwareRecords(HardwarePayload hardwarePayload) {
    HardwareKeyGenResponse response = new HardwareKeyGenResponse();

    try {
      if (
        hardwarePayload == null ||
        hardwarePayload.hardwareRecords == null ||
        hardwarePayload.hardwareRecords.isEmpty()
      ) {
        response.overallSuccess = false;
        response.message = 'No hardware records provided';
        return response;
      }

      // Collect all hardware and asset IDs for bulk SOQL
      Set<Id> allHardwareIds = new Set<Id>();
      Set<Id> allAssetIds = new Set<Id>();
      for (HardwareRecord hwRecord : hardwarePayload.hardwareRecords) {
        if (hwRecord.hardwareId != null) {
          allHardwareIds.add(hwRecord.hardwareId);
        }
        if (hwRecord.assetIds != null) {
          allAssetIds.addAll(hwRecord.assetIds);
        }
      }

      Map<Id, Hardware__c> hwMap = new Map<Id, Hardware__c>(
        [
          SELECT
            Id,
            Name,
            Hardware_Name__c,
            Serial_Number__c,
            Server_Type__c,
            Feature_Code__c,
            Host_Name__c,
            Model_Number__c
          FROM Hardware__c
          WHERE Id IN :allHardwareIds
        ]
      );
      Map<Id, Asset> assetMap = new Map<Id, Asset>(
        [
          SELECT
            Id,
            Name,
            ProductCode,
            ProductDescription,
            SerialNumber,
            Quantity,
            LifecycleStartDate,
            LifecycleEndDate,
            Product2.Name
          FROM Asset
          WHERE Id IN :allAssetIds
        ]
      );

      // Iterate through each hardware record and its assets, producing a dummy result per asset
      for (HardwareRecord hwRecord : hardwarePayload.hardwareRecords) {
        if (hwRecord.assetIds == null) {
          continue;
        }

        for (Id assetId : hwRecord.assetIds) {
          AssetKeyResult result = new AssetKeyResult();
          result.assetId = assetId;
          result.hardwareId = hwRecord.hardwareId;
          Asset asset = assetMap.get(assetId);
          result.assetName = asset != null ? asset.Name : String.valueOf(assetId);

          // Populate hwRequest from backend-queried records
          Hardware__c hw = hwMap.get(hwRecord.hardwareId);
          HardwareLicenseKeyRequest hwRequest = new HardwareLicenseKeyRequest();
          hwRequest.source = hardwarePayload.source;
          hwRequest.keyType = hardwarePayload.keyType;
          hwRequest.expirationDate = hardwarePayload.expirationDate;
          hwRequest.hardwareId = String.valueOf(hwRecord.hardwareId);
          hwRequest.hardwareRecordName = hw != null ? hw.Name : null;
          hwRequest.hardwareName = hw != null ? hw.Hardware_Name__c : null;
          hwRequest.hardwareSerialNumber = hw != null ? hw.Serial_Number__c : null;
          hwRequest.serverType = hw != null ? hw.Server_Type__c : null;
          hwRequest.featureCode = hw != null ? hw.Feature_Code__c : null;
          hwRequest.hostName = hw != null ? hw.Host_Name__c : null;
          hwRequest.modelNumber = hw != null ? hw.Model_Number__c : null;

          // Asset-level fields
          hwRequest.assetId = assetId;
          hwRequest.productCode = asset != null ? asset.ProductCode : null;
          hwRequest.assetProductName = asset != null ? asset.Product2?.Name : null;
          hwRequest.assetProductDescription = asset != null ? asset.ProductDescription : null;
          hwRequest.assetSerialNumber = asset != null ? asset.SerialNumber : null;
          hwRequest.assetQuantity = asset != null ? asset.Quantity : null;
          hwRequest.assetLifecycleStartDate = asset != null ? asset.LifecycleStartDate : null;
          hwRequest.assetLifecycleEndDate = asset != null ? asset.LifecycleEndDate : null;

          String assetPayload = JSON.serialize(hwRequest);
          System.debug(LoggingLevel.DEBUG, 'Asset payload for executeForAsset: ' + JSON.serializePretty(hwRequest));

          // Call executeForAsset
          LkgKeyGenResponse keyGenResponse = executeForAsset(assetPayload);

          result.success = keyGenResponse.isSuccess;
          result.status = keyGenResponse.isSuccess ? 'Success' : 'Failed';
          result.message = keyGenResponse.message;
          result.licenseKey = keyGenResponse.generatedKey;
          result.licenseKeyId = keyGenResponse.licenseKeyId;

          response.assetResults.add(result);
        }
      }

      Integer successCount = 0;
      Integer failCount = 0;
      for (AssetKeyResult r : response.assetResults) {
        if (r.success) {
          successCount++;
        } else {
          failCount++;
        }
      }
      response.overallSuccess = successCount > 0;
      response.message =
        successCount +
        ' succeeded, ' +
        failCount +
        ' failed out of ' +
        response.assetResults.size() +
        ' asset(s)';

      return response;
    } catch (Exception e) {
      response.overallSuccess = false;
      response.message = 'Error processing hardware records: ' + e.getMessage();
      System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
      return response;
    }
  }

  public class HardwarePayload {
    public String source;
    public Id accountId;
    public List<HardwareRecord> hardwareRecords;
    public Id contact1Id;
    public Id contact2Id;
    public Boolean sendEmail;
    public String keyType;
    public String expirationDate;
  }

  public class HardwareRecord {
    public Id hardwareId;
    public List<Id> assetIds;
  }

  public class HardwareKeyGenResponse {
    @AuraEnabled
    public Boolean overallSuccess;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<AssetKeyResult> assetResults;

    public HardwareKeyGenResponse() {
      this.overallSuccess = false;
      this.message = '';
      this.assetResults = new List<AssetKeyResult>();
    }
  }

  public class AssetKeyResult {
    @AuraEnabled
    public Id assetId;
    @AuraEnabled
    public String assetName;
    @AuraEnabled
    public Id hardwareId;
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String status; // 'Pending', 'Success', 'Failed', 'Error'
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String licenseKey;
    @AuraEnabled
    public Id licenseKeyId;

    public AssetKeyResult() {
      this.success = false;
      this.status = 'Pending';
      this.message = '';
    }
  }
}