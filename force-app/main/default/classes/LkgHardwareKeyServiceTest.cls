@isTest
private class LkgHardwareKeyServiceTest {

  // ─── Guard / null-safety tests ────────────────────────────────────────────

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenAssetDataIsNull() {
    // Given null assetData — all null-guards should fire gracefully
    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();

    // When
    Test.startTest();
    LkgHardwareKeyService.addKeyDataFromAsset(null, keyData);
    Test.stopTest();

    // Then — no exception; keyData is unchanged
    System.Assert.isNull(
      keyData.Silo,
      'Silo should remain null when assetData is null.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenProductDataIsNull() {
    // Given assetData with null productData
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = null;
    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();

    // When
    Test.startTest();
    LkgHardwareKeyService.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then
    System.Assert.isNull(
      keyData.Silo,
      'Silo should remain null when productData is null.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldNotThrowWhenKeyDataIsNull() {
    // Given valid assetData but null keyData
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'automate';

    // When
    Test.startTest();
    LkgHardwareKeyService.addKeyDataFromAsset(assetData, null);
    Test.stopTest();

    // Then — no exception thrown
    System.Assert.isTrue(
      true,
      'addKeyDataFromAsset() should not throw when keyData is null.'
    );
  }

  // ─── Happy-path tests ─────────────────────────────────────────────────────

  @isTest
  static void addKeyDataFromAsset_shouldSetCommonFieldsForAutomate() {
    // Given valid assetData for the automate silo
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'automate';
    assetData.productData.productCode = 'AUTOMATE_CODE';
    assetData.productData.externalName = 'Automate Product';
    assetData.productData.internalName = 'Automate Internal';
    assetData.hardwareId = '001000000000001AAA';
    assetData.serialNumber = 'SN-001';
    assetData.productVersion = '11';

    LkgRequestBuilderAutomate.AutomateKeyData keyData =
      new LkgRequestBuilderAutomate.AutomateKeyData();

    // When
    Test.startTest();
    LkgHardwareKeyService.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — common fields set by addCommonKeyDataFromAsset
    System.Assert.areEqual(
      'automate',
      keyData.Silo,
      'Silo should be mapped from assetData.productData.silo.'
    );
    System.Assert.areEqual(
      'AUTOMATE_CODE',
      keyData.ProductCode,
      'ProductCode should be mapped from productData.productCode.'
    );
  }

  @isTest
  static void addKeyDataFromAsset_shouldApplyNoSiloSpecificFieldsForUnknownSilo() {
    // Given assetData with an unregistered silo (no param builder registered)
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'unknown_silo';
    assetData.productData.productCode = 'UNKNOWN_CODE';

    LkgRequestBuilderBase.KeyData keyData = new LkgRequestBuilderBase.KeyData();

    // When
    Test.startTest();
    LkgHardwareKeyService.addKeyDataFromAsset(assetData, keyData);
    Test.stopTest();

    // Then — common fields are still set by the base mapping
    System.Assert.areEqual(
      'unknown_silo',
      keyData.Silo,
      'Silo should still be set via common mapping even for an unknown silo.'
    );
  }
}