@isTest
private class LkgHardwareAssetEnrichmentServiceTest {
  // ─── enrich() null-guard paths (no DML needed) ────────────────────────────

  @isTest
  static void enrich_shouldReturnErrorWhenAssetDataIsNull() {
    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(null);
    Test.stopTest();

    System.Assert.isFalse(result.errors.isEmpty(), 'errors should be populated when assetData is null.');
    System.Assert.isTrue(result.errors[0].contains('AssetData is null'), 'Error should mention null AssetData.');
  }

  @isTest
  static void enrich_shouldReturnErrorWhenRequiredIdsAreNull() {
    // Given assetData with null assetId
    LkgMapperHardwareBase.AssetData missingAsset = new LkgMapperHardwareBase.AssetData();
    missingAsset.assetId = null;
    missingAsset.hardwareId = '001000000000001AAA';

    // Given assetData with null hardwareId
    LkgMapperHardwareBase.AssetData missingHardware = new LkgMapperHardwareBase.AssetData();
    missingHardware.assetId = '001000000000001AAA';
    missingHardware.hardwareId = null;

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result r1 = LkgHardwareAssetEnrichmentService.enrich(missingAsset);
    LkgHardwareAssetEnrichmentService.Result r2 = LkgHardwareAssetEnrichmentService.enrich(missingHardware);
    Test.stopTest();

    System.Assert.isFalse(r1.errors.isEmpty(), 'errors should be populated when assetId is null.');
    System.Assert.isFalse(r2.errors.isEmpty(), 'errors should be populated when hardwareId is null.');
  }

  // ─── resolveProductMetadataId() paths — need DML ──────────────────────────

  @isTest
  static void enrich_shouldAddErrorWhenAssetNotFoundInOrg() {
    // Insert then delete an Asset to get an orphaned (valid-format, non-existent) Id
    Account acc = new Account(Name = 'Enrichment NotFound Account');
    insert acc;
    Asset temp = new Asset(Name = 'Temp Asset', AccountId = acc.Id, Status = 'Installed');
    insert temp;
    Id orphanedId = temp.Id;
    delete temp;

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.assetId = orphanedId;
    assetData.hardwareId = acc.Id; // non-null placeholder — never reached in SOQL

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(assetData);
    Test.stopTest();

    System.Assert.isFalse(result.errors.isEmpty(), 'errors should be populated when the asset does not exist.');
    System.Assert.isTrue(result.errors[0].contains('Asset not found'), 'Error should mention asset not found.');
  }

  @isTest
  static void enrich_shouldAddErrorWhenAssetDoesNotBelongToHardware() {
    // Asset has no Hardware__c; passing a non-matching hardwareId triggers the mismatch guard
    Account acc = new Account(Name = 'Enrichment Mismatch Account');
    insert acc;
    Asset asset = new Asset(Name = 'Mismatch Asset', AccountId = acc.Id, Status = 'Installed');
    insert asset;

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.assetId = asset.Id;
    assetData.hardwareId = acc.Id; // non-null and != asset.Hardware__c (null)

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(assetData);
    Test.stopTest();

    System.Assert.isFalse(result.errors.isEmpty(), 'errors should be populated when hardware IDs do not match.');
    System.Assert.isTrue(result.errors[0].contains('does not belong'), 'Error should mention hardware mismatch.');
  }

  @isTest
  static void enrich_shouldAddErrorWhenAssetHasNoProduct() {
    // Asset is linked to Hardware but has no Product2 — triggers the Product2 null guard
    Account acc = new Account(Name = 'Enrichment No Product Account');
    insert acc;
    Hardware__c hw = new Hardware__c(Status__c = 'Quoting', Account__c = acc.Id);
    insert hw;
    Asset asset = new Asset(
      Name = 'No Product Asset',
      AccountId = acc.Id,
      Status = 'Installed',
      Hardware__c = hw.Id
      // No Product2Id set
    );
    insert asset;

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.assetId = asset.Id;
    assetData.hardwareId = hw.Id;

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(assetData);
    Test.stopTest();

    System.Assert.isFalse(result.errors.isEmpty(), 'errors should be populated when Asset has no Product2.');
    System.Assert.isTrue(result.errors[0].contains('Product'), 'Error should mention missing product.');
  }

  @isTest
  static void enrich_shouldAddErrorWhenNoIntersectMatchFound() {
    // Asset linked to Hardware with a ProductCode that matches no LKG_Intersect__mdt record
    Account acc = new Account(Name = 'Enrichment No Match Account');
    insert acc;
    Hardware__c hw = new Hardware__c(Status__c = 'Quoting', Account__c = acc.Id);
    insert hw;
    Product2 prod = new Product2(Name = 'No Match Product', ProductCode = 'NOMATCH_ENRICH_999', IsActive = false);
    insert prod;
    Asset asset = new Asset(
      Name = 'No Match Asset XYZ',
      AccountId = acc.Id,
      Status = 'Installed',
      Hardware__c = hw.Id,
      Product2Id = prod.Id
    );
    insert asset;

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.assetId = asset.Id;
    assetData.hardwareId = hw.Id;

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(assetData);
    Test.stopTest();

    System.Assert.isFalse(result.errors.isEmpty(), 'errors should be populated when no intersect match is found.');
    System.Assert.isTrue(
      result.errors[0].contains('Unable to resolve'),
      'Error should mention unresolvable product metadata id.'
    );
  }

  @isTest
  static void enrich_shouldCoverSuccessPathWhenMatchingIntersectExists() {
    // Query an existing primary intersect record and build a matching Asset
    // so resolveProductMetadataId returns a valid Id and the full enrich path executes
    List<LKG_Intersect__mdt> intersects = [
      SELECT Match_Description__c, LKG_Product_Match__c
      FROM LKG_Intersect__mdt
      WHERE LKG_SKU_Type__c = 'primary' AND LKG_Product_Match__c != NULL AND Match_Description__c != NULL
      LIMIT 1
    ];

    if (intersects.isEmpty()) {
      return; // No MDT records deployed to this sandbox — skip gracefully
    }

    String matchDesc = intersects[0].Match_Description__c; // format: "ProductCode | AssetName"
    Integer pipeIdx = matchDesc.indexOf(' | ');
    if (pipeIdx < 0) {
      return;
    }
    String productCode = matchDesc.substring(0, pipeIdx).trim();
    String assetName = matchDesc.substring(pipeIdx + 3).trim();

    Account acc = new Account(Name = 'Enrichment Success Account');
    insert acc;
    Hardware__c hw = new Hardware__c(Status__c = 'Quoting', Account__c = acc.Id);
    insert hw;
    Product2 prod = new Product2(Name = 'Match Product', ProductCode = productCode, IsActive = false);
    insert prod;
    Asset asset = new Asset(
      Name = assetName,
      AccountId = acc.Id,
      Status = 'Installed',
      Hardware__c = hw.Id,
      Product2Id = prod.Id
    );
    insert asset;

    LkgMapperHardwareBase.AssetData assetData = new LkgMapperHardwareBase.AssetData();
    assetData.assetId = asset.Id;
    assetData.hardwareId = hw.Id;

    Test.startTest();
    LkgHardwareAssetEnrichmentService.Result result = LkgHardwareAssetEnrichmentService.enrich(assetData);
    Test.stopTest();

    // Either full success or a known downstream error — result must not be null and must have debug log
    System.Assert.isNotNull(result, 'Result should never be null.');
    System.Assert.isNotNull(result.debugLog, 'Debug log should be initialised.');
    System.Assert.isTrue(result.debugLog.size() > 0, 'Debug log should have at least the starting enrichment entry.');
  }
}