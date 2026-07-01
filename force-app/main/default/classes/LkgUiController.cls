public with sharing class LkgUiController {
  @AuraEnabled(cacheable=true)
  public static List<LKG_Solution_Group__mdt> getSolutionGroups() {
    return [
      SELECT MasterLabel, DeveloperName
      FROM LKG_Solution_Group__mdt
      WHERE Is_Hidden__c = FALSE
      ORDER BY MasterLabel
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_Solution_Category__mdt> getSolutionCategoriesByGroup(string groupName) {
    return [
      SELECT MasterLabel, DeveloperName
      FROM LKG_Solution_Category__mdt
      WHERE LKG_Solution_Group__r.DeveloperName = :groupName AND Is_Hidden__c = FALSE
      ORDER BY MasterLabel
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_Solution__mdt> getSolutionsByCategory(string categoryName) {
    return [
      SELECT MasterLabel, DeveloperName
      FROM LKG_Solution__mdt
      WHERE LKG_Solution_Category__r.DeveloperName = :categoryName AND Is_Hidden__c = FALSE
      ORDER BY MasterLabel
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_Product__mdt> getProductsBySolution(string solutionName) {
    return [
      SELECT MasterLabel, DeveloperName, Internal_Product_Name__c
      FROM LKG_Product__mdt
      WHERE LKG_Solution__r.DeveloperName = :solutionName AND Is_Hidden__c = FALSE
      ORDER BY MasterLabel
    ];
  }

  @AuraEnabled(cacheable=true)
  public static LKG_Product__mdt getLkgProductByName(string productName) {
    List<LKG_Product__mdt> products = [
      SELECT
        Id,
        DeveloperName,
        Product_Code__c,
        LKG_Silo__c,
        LKG_Silo__r.DeveloperName,
        LKG_Silo__r.LKG_Brand__r.DeveloperName,
        License_Key_Product_Name__c,
        Internal_Product_Name__c,
        Is_Support_Product__c,
        Sub_Silo__c
      FROM LKG_Product__mdt
      WHERE DeveloperName = :productName
      LIMIT 1
    ];
    if (!products.isEmpty()) {
      return products[0];
    }
    return null;
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_Key_Type__mdt> getKeyTypesBySilo(string siloName) {
    List<LKG_Key_Type__mdt> keyTypes = new List<LKG_Key_Type__mdt>();
    List<LKG_Key_Type__mdt> globalKeyTypes = [
      SELECT MasterLabel, DeveloperName, Scope__c, LKG_Silo__c
      FROM LKG_Key_Type__mdt
      WHERE Scope__c = 'Global' AND Type__c != 'Permament'
      ORDER BY MasterLabel
    ];
    List<LKG_Key_Type__mdt> siloKeyTypes = [
      SELECT MasterLabel, DeveloperName, Scope__c, LKG_Silo__c
      FROM LKG_Key_Type__mdt
      WHERE Scope__c = 'Silo' AND LKG_Silo__r.DeveloperName = :siloName AND Type__c != 'Permament'
      ORDER BY MasterLabel
    ];

    keyTypes.addAll(globalKeyTypes);
    keyTypes.addAll(siloKeyTypes);
    return keyTypes;
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_UI_Field__mdt> getUIFieldsByProduct(LKG_Product__mdt product) {
    List<LKG_UI_Field__mdt> allFields = [
      SELECT
        MasterLabel,
        DeveloperName,
        Scope__c,
        LKG_Silo__c,
        LKG_Product__c,
        Type__c,
        Display_Order__c,
        Picklist_JSON__c,
        Default_Value__c,
        Is_Hidden__c
      FROM LKG_UI_Field__mdt
      WHERE Scope__c IN ('Global', 'Silo', 'Product')
    ];

    List<LKG_UI_Field__mdt> filteredFields = new List<LKG_UI_Field__mdt>();
    for (LKG_UI_Field__mdt field : allFields) {
      switch on field.Scope__c {
        when 'Global' {
          filteredFields.add(field);
        }
        when 'Silo' {
          if (field.LKG_Silo__c != null && field.LKG_Silo__c == product.LKG_Silo__c) {
            filteredFields.add(field);
          }
        }
        when 'Product' {
          if (field.LKG_Product__c != null && field.LKG_Product__c == product.Id) {
            filteredFields.add(field);
          }
        }
      }
    }

    filteredFields.sort(new LkgFieldSortComparator());

    return filteredFields;
  }

  @AuraEnabled(cacheable=true)
  public static List<LKG_UI_Field_Option__mdt> getUIFieldOptions(String[] fieldNames, String keyType) {
    return [
      SELECT MasterLabel, DeveloperName, Default_Value__c, Is_Hidden__c, LKG_UI_Field__r.DeveloperName
      FROM LKG_UI_Field_Option__mdt
      WHERE LKG_UI_Field__r.DeveloperName IN :fieldNames AND LKG_Key_Type__r.DeveloperName = :keyType
      ORDER BY MasterLabel
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<Contact> getContactsByAccountId(Id accountId) {
    return [
      SELECT Id, Name
      FROM Contact
      WHERE AccountId = :accountId
      ORDER BY Name
    ];
  }

  @AuraEnabled(cacheable=true)
  public static List<Contact> searchContacts(String searchTerm) {
    String term = '%' + searchTerm + '%';
    return [
      SELECT Id, Name, Email, Account.Name
      FROM Contact
      WHERE Email != NULL AND (Name LIKE :term OR Email LIKE :term)
      ORDER BY Name
      LIMIT 20
    ];
  }

  @AuraEnabled(cacheable=true)
  public static String getHideHardwareKeyTabSetting() {
    List<LKG_Setting__mdt> settings = [
      SELECT Value__c
      FROM LKG_Setting__mdt
      WHERE DeveloperName = 'Hide_Generate_Hardware_Key_Tab'
      LIMIT 1
    ];
    if (!settings.isEmpty()) {
      return settings[0].Value__c;
    }
    return 'false';
  }

  @AuraEnabled(cacheable=true)
  public static String getHideReadOnlyFieldsSetting() {
    List<LKG_Setting__mdt> settings = [
      SELECT Value__c
      FROM LKG_Setting__mdt
      WHERE DeveloperName = 'Hide_Read_Only_Fields'
      LIMIT 1
    ];
    if (!settings.isEmpty()) {
      return settings[0].Value__c;
    }
    return 'true';
  }

  public class LkgFieldSortComparator implements Comparator<LKG_UI_Field__mdt> {
    public Integer compare(LKG_UI_Field__mdt a, LKG_UI_Field__mdt b) {
      Integer orderA = a.Display_Order__c != null ? a.Display_Order__c.intValue() : 999;
      Integer orderB = b.Display_Order__c != null ? b.Display_Order__c.intValue() : 999;

      return orderA - orderB;
    }
  }

  @AuraEnabled
  public static LkgKeyGenResponse generateKey(string payload) {
    try {
      LkgMapperFactory mapperFactory = new LkgMapperFactory();
      LkgRequestBuilderFactory requestBuilderFactory = new LkgRequestBuilderFactory();
      LkgRequestController requestController = new LkgRequestController();
      LkgRecordCreatorFactory recordCreatorFactory = new LkgRecordCreatorFactory();
      LkgProcessor processor = new LkgProcessor(
        mapperFactory,
        requestBuilderFactory,
        requestController,
        recordCreatorFactory
      );

      return processor.Execute(payload);
    } catch (LkgKeyGenResponse.KeyGenException e) {
      return LkgKeyGenResponse.error(e.getMessage());
    } catch (Exception e) {
      return LkgKeyGenResponse.error('An unexpected error occurred: ' + e.getMessage());
    }
  }
}