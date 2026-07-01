public with sharing class LkgUiHardwareController {
  /**
   * Fetches Key Types supported by hardware-based key generation (excludes Generic)
   * @return List of LKG_Key_Type__mdt records with Global scope, excluding Generic
   */
  @AuraEnabled(cacheable=true)
  public static List<LKG_Key_Type__mdt> getHardwareKeyTypes() {
    return [
      SELECT MasterLabel, DeveloperName
      FROM LKG_Key_Type__mdt
      WHERE Scope__c = 'Global' AND Type__c != 'Generic'
      ORDER BY MasterLabel
    ];
  }

  /**
   * Fetches Hardware records related to an Account with optional filters
   * @param accountId The Account ID to fetch Hardware for
   * @param statusFilter Optional Status filter value
   * @param serialNumberFilter Optional Serial Number filter (partial match)
   * @return List of Hardware__c records with FLS enforced
   */
  @AuraEnabled(cacheable=true)
  public static List<Hardware__c> getHardware(
    Id accountId,
    String statusFilter,
    String serialNumberFilter,
    Integer pageSize,
    Integer offsetValue
  ) {
    try {
      // Build dynamic WHERE clause
      String whereClause = 'Account__c = :accountId';

      if (String.isNotBlank(statusFilter)) {
        whereClause += ' AND Status__c = :statusFilter';
      }

      if (String.isNotBlank(serialNumberFilter)) {
        whereClause += ' AND Serial_Number__c LIKE :serialNumberPattern';
      }

      String serialNumberPattern = String.isNotBlank(serialNumberFilter)
        ? '%' + String.escapeSingleQuotes(serialNumberFilter) + '%'
        : null;
      Integer queryLimit = pageSize != null ? pageSize : 50;
      Integer queryOffset = offsetValue != null ? offsetValue : 0;

      // Query with FLS enforcement
      String query =
        'SELECT Id, Name, Hardware_Name__c, Status__c, Serial_Number__c, Server_Type__c, Host_Name__c, Model_Number__c, Feature_Code__c ' +
        'FROM Hardware__c ' +
        'WHERE ' +
        whereClause +
        ' ' +
        'ORDER BY Hardware_Name__c ' +
        'LIMIT :queryLimit OFFSET :queryOffset';

      List<Hardware__c> hardwareList = Database.query(query);

      // Strip inaccessible fields based on user permissions
      SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, hardwareList);

      return decision.getRecords();
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching Hardware records: ' + e.getMessage());
    }
  }

  /**
   * Fetches Asset records related to selected Hardware records with optional filters
   * @param hardwareIds List of Hardware__c record IDs
   * @param statusFilter Optional Status filter value
   * @return List of Asset records with FLS enforced
   */
  @AuraEnabled(cacheable=true)
  public static List<Asset> getAssets(
    List<Id> hardwareIds,
    String statusFilter,
    Integer pageSize,
    Integer offsetValue
  ) {
    try {
      if (hardwareIds == null || hardwareIds.isEmpty()) {
        return new List<Asset>();
      }

      // Build dynamic WHERE clause
      String whereClause = 'Hardware__c IN :hardwareIds';

      if (String.isNotBlank(statusFilter)) {
        whereClause += ' AND Status = :statusFilter';
      }

      Integer queryLimit = pageSize != null ? pageSize : 50;
      Integer queryOffset = offsetValue != null ? offsetValue : 0;

      // Query with FLS enforcement
      String query =
        'SELECT Id, Name, Status, SerialNumber, Product2Id, Product2.Name, ' +
        'ProductDescription, ProductCode, Hardware__c, LifecycleStartDate, LifecycleEndDate, Hardware__r.Name, Hardware__r.Hardware_Name__c, Quantity ' +
        'FROM Asset ' +
        'WHERE ' +
        whereClause +
        ' ' +
        'ORDER BY Name ' +
        'LIMIT :queryLimit OFFSET :queryOffset';

      List<Asset> assetList = Database.query(query);

      // Strip inaccessible fields based on user permissions
      SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, assetList);

      return decision.getRecords();
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching Asset records: ' + e.getMessage());
    }
  }

  /**
   * Generate license keys for hardware-based selections with nested payload structure
   * @param payload JSON string with nested hardware-assets structure:
   *   {
   *     "source": "hardware",
   *     "accountId": "001...",
   *     "hardwareRecords": [
   *       {"hardwareId": "a0X1...", "assetIds": ["02i1...", "02i2..."]},
   *       {"hardwareId": "a0X2...", "assetIds": ["02i3..."]}
   *     ],
   *     "contact1Id": "003...",
   *     "contact2Id": "003...",
   *     "sendEmail": false
   *   }
   * @return JSON string with HardwareKeyGenResponse containing per-asset results
   */
  @AuraEnabled
  public static String generateKeysForHardware(String payload) {
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response = new LkgProcessorHardwareKeys.HardwareKeyGenResponse();

    try {
      // Parse the hardware payload
      System.debug('===== Hardware Key Generation Started =====');

      LkgProcessorHardwareKeys.HardwarePayload hwPayload = (LkgProcessorHardwareKeys.HardwarePayload) JSON.deserialize(
        payload,
        LkgProcessorHardwareKeys.HardwarePayload.class
      );

      System.debug(JSON.serializePretty(hwPayload));

      if (!validateHardwarePayload(hwPayload, response)) {
        System.debug('Payload validation failed: ' + response.message);
        return JSON.serialize(response);
      }

      // Instantiate processor with required factories
      LkgMapperFactory mapperFactory = new LkgMapperFactory();
      LkgRequestBuilderFactory requestBuilderFactory = new LkgRequestBuilderFactory();
      LkgRequestController requestController = new LkgRequestController();
      LkgRecordCreatorFactory recordCreatorFactory = new LkgRecordCreatorFactory();

      LkgProcessorHardwareKeys processor = new LkgProcessorHardwareKeys(
        mapperFactory,
        requestBuilderFactory,
        requestController,
        recordCreatorFactory
      );

      // Process hardware records using the processor
      response = processor.executeForHardwareRecords(hwPayload);
      System.debug('Response: ' + JSON.serializePretty(response));

      return JSON.serialize(response);
    } catch (Exception e) {
      response.overallSuccess = false;
      response.message = 'Error processing payload: ' + e.getMessage();
      response.assetResults = new List<LkgProcessorHardwareKeys.AssetKeyResult>();
      System.debug('Error occurred: ' + e.getMessage());
      System.debug('Stack Trace: ' + e.getStackTraceString());
      return JSON.serialize(response);
    }
  }

  private static Boolean validateHardwarePayload(
    LkgProcessorHardwareKeys.HardwarePayload hwPayload,
    LkgProcessorHardwareKeys.HardwareKeyGenResponse response
  ) {
    if (hwPayload == null) {
      response.overallSuccess = false;
      response.message = 'Invalid payload: Payload is null';
      return false;
    }

    if (hwPayload.source != 'hardware') {
      response.overallSuccess = false;
      response.message = 'Invalid payload: Source must be "hardware"';
      return false;
    }

    if (hwPayload.accountId == null) {
      response.overallSuccess = false;
      response.message = 'Invalid payload: accountId is required';
      return false;
    }

    if (hwPayload.hardwareRecords == null || hwPayload.hardwareRecords.isEmpty()) {
      response.overallSuccess = false;
      response.message = 'Invalid payload: At least one hardware record is required';
      return false;
    }

    for (LkgProcessorHardwareKeys.HardwareRecord record : hwPayload.hardwareRecords) {
      if (record.hardwareId == null) {
        response.overallSuccess = false;
        response.message = 'Invalid payload: Each hardware record must have a hardwareId';
        return false;
      }
      if (record.assetIds == null || record.assetIds.isEmpty()) {
        response.overallSuccess = false;
        response.message = 'Invalid payload: Each hardware record must have at least one assetId';
        return false;
      }
    }

    // Additional validation logic can be added here as needed
    // Validate basic inputs
    if (hwPayload.accountId == null) {
      response.overallSuccess = false;
      response.message = 'Account ID is required';
      System.debug('Validation Failed: Account ID is required');
      return false;
    }

    // each hardware record must have at least one asset
    for (Integer i = 0; i < hwPayload.hardwareRecords.size(); i++) {
      LkgProcessorHardwareKeys.HardwareRecord hwRecord = hwPayload.hardwareRecords[i];
      if (hwRecord.assetIds == null || hwRecord.assetIds.isEmpty()) {
        response.overallSuccess = false;
        response.message =
          'Each hardware record must have at least one associated asset. Hardware ID: ' + hwRecord.hardwareId;
        System.debug('Validation Failed: Hardware record with ID ' + hwRecord.hardwareId + ' has no associated assets');
        return false;
      }
    }

    return true; // Payload is valid
  }
}