@isTest
private class LkgProductContextServiceTest {
  // ─── getProductData ────────────────────────────────────────────────────────

  @isTest
  static void getProductData_shouldReturnEmptyDataWhenKeyIsNull() {
    // Given a null product key (blank-check guard in the service fires)

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductData(null);
    Test.stopTest();

    // Then — returns a non-null ProductData with all fields empty
    System.Assert.isNotNull(result, 'getProductData() should return a non-null ProductData even for a null key.');
    System.Assert.isNull(result.silo, 'Silo should be null when the product key is null.');
    System.Assert.isNull(result.productCode, 'ProductCode should be null when the product key is null.');
  }

  @isTest
  static void getProductData_shouldReturnEmptyDataWhenKeyIsBlank() {
    // Given a blank product key

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductData('   ');
    Test.stopTest();

    // Then
    System.Assert.isNotNull(result, 'getProductData() should return a non-null ProductData even for a blank key.');
    System.Assert.isNull(result.silo, 'Silo should be null when the product key is blank.');
  }

  @isTest
  static void getProductData_shouldReturnEmptyDataWhenProductNotFound() {
    // Given a non-blank key that will not match any LKG_Product__mdt record
    String unknownKey = 'totally_unknown_product_xyz_notreal_99999';

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductData(unknownKey);
    Test.stopTest();

    // Then — service returns an empty ProductData (no match found in MDT)
    System.Assert.isNotNull(
      result,
      'getProductData() should return a non-null ProductData even when no product is found.'
    );
    System.Assert.isNull(result.silo, 'Silo should be null when no matching product metadata is found.');
  }

  // ─── getProductDataById ───────────────────────────────────────────────────

  @isTest
  static void getProductDataById_shouldReturnNullWhenMetadataIdIsNull() {
    // Given a null metadata ID

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductDataById(null);
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'getProductDataById() should return null when metadataId is null.');
  }

  @isTest
  static void getProductDataById_shouldReturnNullWhenMetadataIdIsBlank() {
    // Given a blank metadata ID

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductDataById('');
    Test.stopTest();

    // Then
    System.Assert.isNull(result, 'getProductDataById() should return null when metadataId is blank.');
  }

  @isTest
  static void getProductDataById_shouldReturnNullWhenNoProductFoundForId() {
    // Given a non-existent metadata ID (valid format, but no matching MDT record)
    String nonExistentId = '0MPxx0000000001AAA'; // Custom metadata type fake ID

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductDataById(nonExistentId);
    Test.stopTest();

    // Then — no MDT record found, returns null
    System.Assert.isNull(
      result,
      'getProductDataById() should return null when no product metadata record exists for the given ID.'
    );
  }

  @isTest
  static void getProductData_shouldReturnPopulatedProductDataWhenKeyMatchesMetadata() {
    // Given a DeveloperName from an existing LKG_Product__mdt record
    // (MDT is readable in all test contexts; requires at least one LKG_Product__mdt record deployed)
    List<LKG_Product__mdt> products = [
      SELECT DeveloperName
      FROM LKG_Product__mdt
      LIMIT 1
    ];
    if (products.isEmpty()) {
      return; // skip gracefully if no product metadata is deployed in this org
    }
    String validKey = products[0].DeveloperName;

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductData(validKey);
    Test.stopTest();

    // Then — identifierName is always set from DeveloperName when a match is found
    System.Assert.isNotNull(
      result,
      'getProductData() should return a non-null ProductData when the key matches an MDT record.'
    );
    System.Assert.isNotNull(
      result.identifierName,
      'identifierName should be populated from DeveloperName when a product metadata match is found.'
    );
  }

  @isTest
  static void getProductDataById_shouldReturnPopulatedProductDataForValidId() {
    // Given the Id of an existing LKG_Product__mdt record
    List<LKG_Product__mdt> products = [
      SELECT Id, DeveloperName
      FROM LKG_Product__mdt
      LIMIT 1
    ];
    if (products.isEmpty()) {
      return; // skip gracefully if no product metadata is deployed in this org
    }
    String validId = String.valueOf(products[0].Id);

    // When
    Test.startTest();
    LkgMapperBase.ProductData result = LkgProductContextService.getProductDataById(validId);
    Test.stopTest();

    // Then
    System.Assert.isNotNull(
      result,
      'getProductDataById() should return non-null ProductData for a valid, existing MDT Id.'
    );
    System.Assert.isNotNull(
      result.identifierName,
      'identifierName should be populated from DeveloperName when a product is found by Id.'
    );
  }
}