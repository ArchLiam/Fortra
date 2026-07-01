/**
 * Builds .HSL file content for Robot license keys.
 * Key rows do NOT include SYSTEM_NAME=.
 * PRODUCT_CODE uses JavaProductCode from LKG_UI_Field__mdt when available,
 * falling back to Product_Code__c on the License Key record.
 */
public with sharing class LkgRobotFileBuilder extends LkgISeriesFileBuilder {
  // Populated once in buildFile() — keyed by LKG_Product_Identifier_Name__c value
  private Map<String, String> javaProductCodeMap = new Map<String, String>();

  public override String buildFile(List<License_Key__c> keys) {
    // Collect unique product identifiers from this batch of keys
    Set<String> developerNames = new Set<String>();
    for (License_Key__c k : keys) {
      if (String.isNotBlank(k.LKG_Product_Identifier_Name__c)) {
        developerNames.add(k.LKG_Product_Identifier_Name__c + '_JavaProductCode');
      }
    }

    // Single MDT query — does not count against SOQL row governor limits
    if (!developerNames.isEmpty()) {
      for (LKG_UI_Field__mdt rec : [
        SELECT DeveloperName, Default_Value__c
        FROM LKG_UI_Field__mdt
        WHERE DeveloperName IN :developerNames
      ]) {
        // Strip the '_JavaProductCode' suffix to get back the product identifier key
        String productId = rec.DeveloperName.removeEnd('_JavaProductCode');
        if (String.isNotBlank(rec.Default_Value__c)) {
          javaProductCodeMap.put(productId, rec.Default_Value__c);
        }
      }
    }

    return super.buildFile(keys);
  }

  protected override String buildKeyRow(License_Key__c k, String hwKey) {
    String licenseCode = safe(k.License_Key__c);
    Integer keyLen = licenseCode.length();
    String licenseFmt = keyLen == 75 ? '4' : (keyLen == 55 ? '1' : '');

    // Use JavaProductCode from MDT if available, otherwise fall back to Product_Code__c
    String productCode = javaProductCodeMap.containsKey(k.LKG_Product_Identifier_Name__c)
      ? javaProductCodeMap.get(k.LKG_Product_Identifier_Name__c)
      : safe(k.Product_Code__c);

    return 'PRODUCT=' +
      safe(k.License_Key_Product_Name__c) +
      '\n' +
      'PRODUCT_CODE=' +
      productCode +
      '\n' +
      'HARDWARE_KEY=' +
      hwKey +
      '\n' +
      'LICENSE_FMT=' +
      licenseFmt +
      '\n' +
      'LICENSE_TYPE=' +
      resolveLicenseType(k.Key_Type__c) +
      '\n' +
      'LICENSE_CODE=' +
      licenseCode +
      '\n' +
      'EXPIRES=' +
      resolveExpires(k.End_Date__c) +
      '\n';
  }
}