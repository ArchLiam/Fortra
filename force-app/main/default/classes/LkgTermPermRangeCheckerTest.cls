@isTest
public with sharing class LkgTermPermRangeCheckerTest {
  @isTest
  static void getPermTermVersionRange_shouldParseValidJson() {
    // Given valid JSON
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When getPermTermVersionRange is called
    Test.startTest();
    LkgTermPermRangeChecker.PermTermVersionRange result = LkgTermPermRangeChecker.getPermTermVersionRange(json);
    Test.stopTest();

    // Then all fields should be parsed correctly
    System.assertEquals(4, result.minVersion, 'minVersion should be 4');
    System.assertEquals(7, result.minModification, 'minModification should be 7');
    System.assertEquals(10, result.maxVersion, 'maxVersion should be 10');
    System.assertEquals(12, result.maxModification, 'maxModification should be 12');
  }

  @isTest
  static void getPermTermVersionRange_shouldReturnNullForBlankJson() {
    // Given blank JSON
    String json = '';

    // When getPermTermVersionRange is called
    Test.startTest();
    LkgTermPermRangeChecker.PermTermVersionRange result = LkgTermPermRangeChecker.getPermTermVersionRange(json);
    Test.stopTest();

    // Then result should be null
    System.assertEquals(null, result, 'Result should be null for blank JSON');
  }

  @isTest
  static void getPermTermVersionRange_shouldReturnNullForInvalidJson() {
    // Given invalid JSON
    String json = '{invalid json}';

    // When getPermTermVersionRange is called
    Test.startTest();
    LkgTermPermRangeChecker.PermTermVersionRange result = LkgTermPermRangeChecker.getPermTermVersionRange(json);
    Test.stopTest();

    // Then result should be null
    System.assertEquals(null, result, 'Result should be null for invalid JSON');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnTrueWhenInRange() {
    // Given version in range
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with version 5.10 (in range)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('5', '10', json);
    Test.stopTest();

    // Then should return true
    System.assertEquals(true, result, 'Should convert when version is in range');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnFalseWhenBelowMin() {
    // Given version below minimum
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with version 4.05 (below 4.07)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('4', '5', json);
    Test.stopTest();

    // Then should return false
    System.assertEquals(false, result, 'Should not convert when version is below minimum');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnFalseWhenAboveMax() {
    // Given version above maximum
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with version 10.15 (above 10.12)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('10', '15', json);
    Test.stopTest();

    // Then should return false
    System.assertEquals(false, result, 'Should not convert when version is above maximum');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnTrueAtMinBoundary() {
    // Given version at minimum boundary
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with version 4.07
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('4', '7', json);
    Test.stopTest();

    // Then should return true
    System.assertEquals(true, result, 'Should convert when version is at minimum boundary');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnTrueAtMaxBoundary() {
    // Given version at maximum boundary
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with version 10.12
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('10', '12', json);
    Test.stopTest();

    // Then should return true
    System.assertEquals(true, result, 'Should convert when version is at maximum boundary');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnFalseForNullJson() {
    // Given null JSON
    String json = null;

    // When shouldConvertTermToPerm is called
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('5', '10', json);
    Test.stopTest();

    // Then should return false
    System.assertEquals(false, result, 'Should return false for null JSON');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldHandleNullRelease() {
    // Given null release
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with null release
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm(null, '10', json);
    Test.stopTest();

    // Then should return false (termVersionMod is null, max_Version_Mod is not null)
    System.assertEquals(false, result, 'Should return false for null release when max is defined');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldHandleNullModification() {
    // Given null modification (defaults to 0)
    String json = '{"minVersion":4,"minModification":7,"maxVersion":10,"maxModification":12}';

    // When shouldConvertTermToPerm is called with null modification (version 5.00)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('5', null, json);
    Test.stopTest();

    // Then should return true (5.00 is in range 4.07 to 10.12)
    System.assertEquals(true, result, 'Should return true when modification is null and version is in range');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldHandleNoMaxVersion() {
    // Given JSON without max version (open-ended range)
    String json = '{"minVersion":5,"minModification":18}';

    // When shouldConvertTermToPerm is called with version above min (6.00)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('6', '0', json);
    Test.stopTest();

    // Then should return true (no upper limit, and 6.00 >= 5.18)
    System.assertEquals(true, result, 'Should return true when no max version and above min');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnTrueWhenBothNull() {
    // Given JSON without max version and invalid release/modification
    String json = '{"minVersion":5,"minModification":18}';

    // When shouldConvertTermToPerm is called with blank inputs
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('', '', json);
    Test.stopTest();

    // Then should return true (termVersionMod is null, max_Version_Mod is null)
    System.assertEquals(true, result, 'Should return true when both term and max versions are null');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnFalseWhenBelowMinOpenRange() {
    // Given JSON without max version (open-ended range)
    String json = '{"minVersion":5,"minModification":18}';

    // When shouldConvertTermToPerm is called with version below min (5.10 < 5.18)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('5', '10', json);
    Test.stopTest();

    // Then should return false (below minimum)
    System.assertEquals(false, result, 'Should return false when below min in open-ended range');
  }

  @isTest
  static void shouldConvertTermToPerm_shouldReturnTrueAtMinBoundaryOpenRange() {
    // Given JSON without max version (open-ended range)
    String json = '{"minVersion":5,"minModification":18}';

    // When shouldConvertTermToPerm is called with version at min (5.18)
    Test.startTest();
    Boolean result = LkgTermPermRangeChecker.shouldConvertTermToPerm('5', '18', json);
    Test.stopTest();

    // Then should return true (at minimum boundary)
    System.assertEquals(true, result, 'Should return true when at min boundary in open-ended range');
  }
}