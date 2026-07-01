public with sharing class LkgUiRobotCcssController {
  /**
   * Fetches License_Key__c records for Robot and CCSS silos linked to an Account.
   * Base filter: Silo__c IN ('robot','ccss'), End_Date__c >= TODAY or null.
   * Optional filters: silo, keyType, hardwareId, licenseKeySearch.
   */
  @AuraEnabled
  public static List<License_Key__c> getRobotCcssLicenseKeys(Id accountId, String siloFilter) {
    try {
      List<String> silos = new List<String>{ 'robot', 'ccss' };

      String whereClause =
        'Account__c = :accountId' +
        ' AND Silo__c IN :silos' +
        ' AND (End_Date__c = null OR End_Date__c >= TODAY)';

      if (String.isNotBlank(siloFilter)) {
        whereClause += ' AND Silo__c = :siloFilter';
      }

      String query =
        'SELECT Id, Name, Key_Type__c, End_Date__c, Silo__c, License_Key_Product_Name__c,' +
        ' License_Key__c, LPAR_Number__c, LPAR_System_Name__c, LPAR_Serial_Number__c,' +
        ' Hardware_ID__c' +
        ' FROM License_Key__c' +
        ' WHERE ' +
        whereClause +
        ' ORDER BY Name' +
        ' LIMIT 500';

      List<License_Key__c> records = Database.query(query);
      SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, records);
      return (List<License_Key__c>) decision.getRecords();
    } catch (Exception e) {
      throw new AuraHandledException('Error fetching Robot/CCSS License Keys: ' + e.getMessage());
    }
  }

  /**
   * Generates a .HSL license key file for the selected Robot or CCSS keys,
   * attaches it to the Account, and optionally emails it to the contacts.
   * @param payload JSON: { keyIds, accountId, contact1Id, contact2Id, sendEmail }
   * @return JSON: { success, message }
   */
  @AuraEnabled
  public static String generateFile(String payload) {
    try {
      GenerateFilePayload parsed = (GenerateFilePayload) JSON.deserialize(payload, GenerateFilePayload.class);

      LkgFileGenerateResult result = LkgLicenseKeysFileService.generateFile(
        parsed.keyIds,
        parsed.accountId,
        parsed.contact1Id,
        parsed.contact2Id,
        parsed.sendEmail
      );

      Map<String, Object> response = new Map<String, Object>{
        'success' => result.success,
        'message' => result.message
      };
      return JSON.serialize(response);
    } catch (Exception e) {
      throw new AuraHandledException('Error generating file: ' + e.getMessage());
    }
  }

  public class GenerateFilePayload {
    public List<Id> keyIds;
    public Id accountId;
    public Id contact1Id;
    public Id contact2Id;
    public Boolean sendEmail;
  }
}