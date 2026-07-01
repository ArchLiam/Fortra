public with sharing class LkgTermPermRangeChecker {
  public class PermTermVersionRange {
    public Decimal minVersion;
    public Decimal minModification;
    public Decimal maxVersion;
    public Decimal maxModification;
  }

  /**
   * Parses a JSON string into a PermTermVersionRange object.
   * Expected format: {"minVersion":10,"minModification":7,"maxVersion":10,"maxModification":31,"isPermTerm":true}
   */
  public static PermTermVersionRange getPermTermVersionRange(String permTermVersionRangeJson) {
    PermTermVersionRange range = new PermTermVersionRange();

    if (String.isBlank(permTermVersionRangeJson)) {
      return null;
    }

    try {
      Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(permTermVersionRangeJson);

      range.minVersion = jsonMap.containsKey('minVersion')
        ? Decimal.valueOf(String.valueOf(jsonMap.get('minVersion')))
        : null;
      range.minModification = jsonMap.containsKey('minModification')
        ? Decimal.valueOf(String.valueOf(jsonMap.get('minModification')))
        : null;
      range.maxVersion = jsonMap.containsKey('maxVersion')
        ? Decimal.valueOf(String.valueOf(jsonMap.get('maxVersion')))
        : null;
      range.maxModification = jsonMap.containsKey('maxModification')
        ? Decimal.valueOf(String.valueOf(jsonMap.get('maxModification')))
        : null;
    } catch (Exception e) {
      // Return empty range if parsing fails
      System.debug(
        LoggingLevel.DEBUG,
        'Failed to parse PermTermVersionRange JSON. Returning empty range. Error: ' + e.getMessage()
      );
      return null;
    }

    return range;
  }

  /**
   * Checks if a Term license should be converted to Permanent based on the release, modification, and the JSON version range.
   *
   * @param release The release version as string
   * @param modification The modification version as string
   * @param permTermVersionRangeJson JSON string with format: {"minVersion":10,"minModification":7,"maxVersion":10,"maxModification":31,"isPermTerm":true}
   * @return true if the term should be converted to permanent, false otherwise
   *
   * @example
   * String jsonConfig = '{"minVersion":10,"minModification":7,"maxVersion":10,"maxModification":31,"isPermTerm":true}';
   * Boolean shouldConvert = LkgTermPermRangeChecker.shouldConvertTermToPerm('10', '15', jsonConfig);
   */
  public static Boolean shouldConvertTermToPerm(String release, String modification, String permTermVersionRangeJson) {
    PermTermVersionRange permTermVersionRange = getPermTermVersionRange(permTermVersionRangeJson);

    if (permTermVersionRange == null) {
      return false;
    }

    Integer termVersion = parseInteger(release);
    Integer modificationInt = parseInteger(modification);

    Decimal termMod = modificationInt == null ? 0 : modificationInt * 0.01;
    Decimal termVersionMod = termVersion == null ? null : termVersion + termMod;

    Integer maxVersion = permTermVersionRange.maxVersion == null
      ? null
      : Integer.valueOf(permTermVersionRange.maxVersion);

    Integer maxModification = permTermVersionRange.maxModification == null
      ? null
      : Integer.valueOf(permTermVersionRange.maxModification);

    Decimal max_Version_Mod;
    if (maxVersion == null && maxModification == null) {
      max_Version_Mod = null;
    } else {
      max_Version_Mod = maxVersion + (maxModification * 0.01);
    }

    Integer minVersion = permTermVersionRange.minVersion == null
      ? null
      : Integer.valueOf(permTermVersionRange.minVersion);
    Integer minModification = permTermVersionRange.minModification == null
      ? null
      : Integer.valueOf(permTermVersionRange.minModification);

    Decimal min_Version_Mod;
    if (minVersion == null && minModification == null) {
      min_Version_Mod = null;
    } else {
      min_Version_Mod = minVersion + (minModification * 0.01);
    }

    if (termVersionMod == null) {
      if (max_Version_Mod == null) {
        return true;
      }
    } else {
      if (max_Version_Mod == null) {
        if (termVersionMod >= min_Version_Mod) {
          return true;
        }
      } else {
        if (termVersionMod >= min_Version_Mod && termVersionMod <= max_Version_Mod) {
          return true;
        }
      }
    }

    return false;
  }

  private static Integer parseInteger(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return Integer.valueOf(value);
    } catch (Exception e) {
      return null;
    }
  }
}