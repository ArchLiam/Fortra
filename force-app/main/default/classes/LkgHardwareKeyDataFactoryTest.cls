@isTest
private class LkgHardwareKeyDataFactoryTest {

  @isTest
  static void createKeyDataInstance_shouldReturnNullWhenAssetDataIsNull() {
    // Given a null AssetData

    // When
    Test.startTest();
    LkgRequestBuilderBase.KeyData result = LkgHardwareKeyDataFactory.createKeyDataInstance(null);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'createKeyDataInstance() should return null when assetData is null.');
  }

  @isTest
  static void createKeyDataInstance_shouldReturnNullWhenProductDataIsNull() {
    // Given an AssetData with null productData
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = null;

    // When
    Test.startTest();
    LkgRequestBuilderBase.KeyData result = LkgHardwareKeyDataFactory.createKeyDataInstance(assetData);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'createKeyDataInstance() should return null when productData is null.');
  }

  @isTest
  static void createKeyDataInstance_shouldReturnNullWhenSiloIsBlank() {
    // Given an AssetData with a blank silo
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = '';

    // When
    Test.startTest();
    LkgRequestBuilderBase.KeyData result = LkgHardwareKeyDataFactory.createKeyDataInstance(assetData);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'createKeyDataInstance() should return null when silo is blank.');
  }

  @isTest
  static void createKeyDataInstance_shouldReturnAutomateKeyDataForAutomateSilo() {
    // Given an AssetData with the 'automate' silo
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'automate';

    // When
    Test.startTest();
    LkgRequestBuilderBase.KeyData result = LkgHardwareKeyDataFactory.createKeyDataInstance(assetData);
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'createKeyDataInstance() should return a KeyData instance for the automate silo.');
    System.Assert.isTrue(
      result instanceof LkgRequestBuilderAutomate.AutomateKeyData,
      'createKeyDataInstance() should return AutomateKeyData for the automate silo.'
    );
  }

  @isTest
  static void createKeyDataInstance_shouldReturnNullForUnknownSilo() {
    // Given an AssetData with an unregistered silo name
    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.productData = new LkgMapperBase.ProductData();
    assetData.productData.silo = 'unknown_silo';

    // When
    Test.startTest();
    LkgRequestBuilderBase.KeyData result = LkgHardwareKeyDataFactory.createKeyDataInstance(assetData);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'createKeyDataInstance() should return null for an unregistered silo.');
  }
}