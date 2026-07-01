@isTest
private class LkgHardwareAutomateKeyParamBuilderTest {
  private static LkgHardwareAutomateKeyParamBuilder builder = new LkgHardwareAutomateKeyParamBuilder();

  // ─── Guard / null-safety tests ────────────────────────────────────────────

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenAssetDataIsNull() {
    // Given null assetData — expected safe no-op
    LkgRequestBuilderAutomate.AutomateKeyData keyData = new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(null, keyData);
    Test.stopTest();

    // Then — no exception, keyData left untouched
    System.Assert.isNull(keyData.HardwareId, 'HardwareId should remain null when assetData is null.');
  }

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenProductDataIsNull() {
    // Given assetData with null productData
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = null;
    LkgRequestBuilderAutomate.AutomateKeyData keyData = new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.isNull(keyData.HardwareId, 'HardwareId should remain null when productData is null.');
  }

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenKeyDataIsNull() {
    // Given valid assetData but null keyData — should be a safe no-op
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, null);
    Test.stopTest();

    // Then — no exception thrown (reaching here confirms the guard worked)
    System.Assert.isTrue(true, 'addKeyDataFromAsset() should not throw when keyData is null.');
  }

  @isTest
  static void addKeyDataFromAsset_shouldNotMapWhenKeyDataIsWrongType() {
    // Given a KeyData that is NOT an AutomateKeyData
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    LkgRequestBuilderBase.KeyData wrongTypeKeyData = new LkgRequestBuilderBase.KeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, wrongTypeKeyData);
    Test.stopTest();

    // Then — silo-specific fields must NOT have been applied
    System.Assert.isNull(
      wrongTypeKeyData.HardwareId,
      'HardwareId should not be set on a non-AutomateKeyData instance.'
    );
  }

  // ─── Happy-path tests ─────────────────────────────────────────────────────

  @isTest
  static void addKeyDataFromAsset_shouldSetHardwareIdAndModification() {
    // Given valid assetData with hardwareId and productModification populated
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    assetData.hardwareId = '001000000000001AAA';
    assetData.productModification = 'R3';

    LkgRequestBuilderAutomate.AutomateKeyData keyData = new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.areEqual(
      '001000000000001AAA',
      keyData.HardwareId,
      'addKeyDataFromAsset() should copy hardwareId onto AutomateKeyData.'
    );
    System.Assert.areEqual(
      'R3',
      keyData.modification,
      'addKeyDataFromAsset() should copy productModification onto AutomateKeyData.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldSetPointsWhenAttributesAreProvided() {
    // Given assetData with a valid Automate product code ('AUT'), tier 'A', and release >= 11
    // Valid keys in LkgAutomatePointsBuilderFactory use prefix 'AUT' or 'BPA'
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    assetData.productData.productCode = 'AUT'; // registered key prefix in factory
    assetData.productVersion = '11'; // isGte11 = true → key 'AUT_A_GTE11'
    assetData.attributes = new Map<String, String>{ 'Tier' => 'A', 'agents' => '10', 'studios' => '5' };
    LkgRequestBuilderAutomate.AutomateKeyData keyData = new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — points must be a non-blank string (calculated by AutomateTierAPointsBuilder)
    System.Assert.isNotNull(
      keyData.points,
      'addKeyDataFromAsset() should calculate and set points when attributes are provided.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldHandleNullAttributes() {
    // Given assetData with null attributes map (should default to empty)
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    assetData.attributes = null;
    LkgRequestBuilderAutomate.AutomateKeyData keyData = new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — no exception; points calculated with defaults
    System.Assert.isNotNull(
      keyData.points,
      'addKeyDataFromAsset() should not throw and should still set points when attributes is null.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldUseLegacyBuilderForVersionLessThan11() {
    // Given assetData with a product version < 11
    // 'AUT' + tier 'A' + version '5' → key 'AUT_A_LT11' → AutomateTierALegacyPointsBuilder
    // This exercises the second operand of: isGte11 = release >= 11 || release == null
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    assetData.productData.productCode = 'AUT';
    assetData.productVersion = '5'; // < 11 → isGte11 = false
    assetData.attributes = new Map<String, String>{ 'Tier' => 'A' };
    LkgRequestBuilderAutomate.AutomateKeyData keyData =
      new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — points set via the LT11 legacy builder
    System.Assert.isNotNull(
      keyData.points,
      'Points should be calculated using the legacy (LT11) builder when version < 11.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldParseBracketedListActions() {
    // Given T-actions supplied as a bracket-wrapped list '[1,2,3]'
    // This covers the bracket-parsing path inside parseActions (lines 66-79)
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    assetData.productData.productCode = 'AUT';
    // No Tier → AutomateDefaultPointsBuilder avoids the factory-key lookup
    assetData.attributes = new Map<String, String>{ 'T' => '[1,2,3]' };
    LkgRequestBuilderAutomate.AutomateKeyData keyData =
      new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — TActions parsed; points computed without error
    System.Assert.isNotNull(
      keyData.points,
      'Points should be calculated even when actions are supplied as a bracketed list.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldParseUnbracketedIntegerAction() {
    // Given T-actions supplied as a plain integer string '5' (no brackets)
    // This covers the safeParseInt fallback at the end of parseActions (line 82)
    LkgMapperHardwareBase.AssetData assetData = makeValidAssetData();
    // No Tier/productCode → AutomateDefaultPointsBuilder
    assetData.attributes = new Map<String, String>{ 'T' => '5' };
    LkgRequestBuilderAutomate.AutomateKeyData keyData =
      new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    builder.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.isNotNull(
      keyData.points,
      'Points should be set when an action value is supplied as an unbounded integer string.'
    );
  }

  // ─── Helper ───────────────────────────────────────────────────────────────

  private static LkgMapperHardwareBase.AssetData makeValidAssetData() {
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'automate';
    assetData.productData.productCode = 'AUTOMATE_CODE';
    assetData.productVersion = '11';
    return assetData;
  }
}