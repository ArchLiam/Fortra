/**
 * Builds .HSL file content for CCSS license keys.
 * Key rows include an extra SYSTEM_NAME= line per the CCSS file spec.
 * Uses LKG Product Code directly (no Java code mapping).
 */
public with sharing class LkgCcssFileBuilder extends LkgISeriesFileBuilder {
  protected override String buildKeyRow(License_Key__c k, String hwKey) {
    String licenseCode = safe(k.License_Key__c);
    Integer keyLen = licenseCode.length();
    String licenseFmt = keyLen == 75 ? '4' : (keyLen == 55 ? '1' : '');

    return 'PRODUCT=' +
      safe(k.License_Key_Product_Name__c) +
      '\n' +
      'PRODUCT_CODE=' +
      safe(k.Product_Code__c) +
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
      '\n' +
      'SYSTEM_NAME=' +
      safe(k.LPAR_System_Name__c) +
      '\n';
  }
}