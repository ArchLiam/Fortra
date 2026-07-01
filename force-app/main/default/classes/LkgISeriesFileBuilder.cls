/**
 * Abstract base class for iSeries (IBM i) .HSL license key file building.
 * Subclasses override buildKeyRow() for silo-specific differences:
 * - LkgRobotFileBuilder: standard key rows (no SYSTEM_NAME)
 * - LkgCcssFileBuilder:  adds SYSTEM_NAME= per key row
 */
public abstract class LkgISeriesFileBuilder {
  // --- Public entry point ---------------------------------------------------

  public virtual String buildFile(List<License_Key__c> keys) {
    String fileDate = Datetime.now().format('yyyy-MM-dd-HH.mm.ss') + '.000000';
    String content = 'FILE_DATE=' + fileDate + '\n';

    Map<String, List<License_Key__c>> groups = groupByHardwareKey(keys);

    Boolean firstGroup = true;
    for (String hwKey : groups.keySet()) {
      if (!firstGroup) {
        content += '\n';
      }
      firstGroup = false;

      content += buildGroupHeader(hwKey);

      List<License_Key__c> groupKeys = groups.get(hwKey);
      for (Integer i = 0; i < groupKeys.size(); i++) {
        content += buildKeyRow(groupKeys[i], hwKey);
        if (i < groupKeys.size() - 1) {
          content += '* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n';
        }
      }
    }

    return content;
  }

  // --- Abstract � subclasses implement this --------------------------------

  protected abstract String buildKeyRow(License_Key__c k, String hwKey);

  // --- Public static helpers (also used by subclasses and tests) ------------

  public static String buildHardwareKey(License_Key__c k) {
    return 'I-' +
      safe(k.LPAR_Serial_Number__c) +
      '-' +
      safe(k.LPAR_Model_Number__c) +
      '-' +
      safe(k.LPAR_Feature_Code__c) +
      '-' +
      safe(k.LPAR_Number__c);
  }

  public static String safe(String value) {
    return value != null ? value : '';
  }

  public static String buildGroupHeader(String hwKey) {
    return '* ========================================================================\n' +
      '* Partition Hardware Key: ' +
      hwKey +
      '\n' +
      '* ========================================================================\n';
  }

  public static String resolveLicenseType(String keyType) {
    if (String.isBlank(keyType)) {
      return '0';
    }
    String lower = keyType.toLowerCase();
    if (lower == 'generic') {
      return '1';
    }
    if (lower.contains('temporary')) {
      return '5';
    }
    return '0';
  }

  public static String resolveExpires(Date endDate) {
    if (endDate == null) {
      return '';
    }
    Datetime dt = Datetime.newInstance(endDate, Time.newInstance(0, 0, 0, 0));
    return dt.format('yyyyMMdd');
  }

  // --- Private -------------------------------------------------------------

  private static Map<String, List<License_Key__c>> groupByHardwareKey(List<License_Key__c> keys) {
    Map<String, List<License_Key__c>> groups = new Map<String, List<License_Key__c>>();
    for (License_Key__c k : keys) {
      String hwKey = buildHardwareKey(k);
      if (!groups.containsKey(hwKey)) {
        groups.put(hwKey, new List<License_Key__c>());
      }
      groups.get(hwKey).add(k);
    }
    return groups;
  }
}