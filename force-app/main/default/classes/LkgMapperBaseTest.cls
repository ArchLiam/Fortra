@isTest
private class LkgMapperBaseTest {
  private class ExposedMapper extends LkgMapperBase {
    public Integer parseInteger(String value) {
      return safeParseInt(value);
    }
  }

  private static final ExposedMapper mapper = new ExposedMapper();

  @isTest
  static void mapPayloadToKeyData_shouldMapBaseFieldsAndDefaults() {
    Account account = new Account(Name = 'Mapper Base Account');
    insert account;

    Contact contact1 = new Contact(FirstName = 'Mapper', LastName = 'Contact1', AccountId = account.Id);
    Contact contact2 = new Contact(FirstName = 'Mapper', LastName = 'Contact2', AccountId = account.Id);
    insert new List<Contact>{ contact1, contact2 };

    LkgMapperBase.UiPayload payload = new LkgMapperBase.UiPayload();
    payload.accountId = account.Id;
    payload.contact1Id = contact1.Id;
    payload.contact2Id = contact2.Id;
    payload.expirationDate = '2026-12-31';
    payload.keyType = LkgRequestBuilderBase.KEYTYPE_GENERIC;
    payload.sendEmail = true;
    payload.productData = new LkgMapperBase.ProductData();
    payload.productData.silo = 'powertech';
    payload.productData.subSilo = 'pt';
    payload.productData.brandName = 'CCSS';
    payload.productData.productCode = 'PT001';
    payload.productData.identifierName = 'PT_PRODUCT';
    payload.productData.externalName = 'External Product';
    payload.productData.internalName = 'Internal Product';
    payload.attributes = new Map<String, String>{ 'powertech_Release' => '7.5', 'Notes' => 'Mapper test notes' };

    Test.startTest();
    LkgRequestBuilderBase.KeyData result = mapper.mapPayloadToKeyData(JSON.serialize(payload));
    Test.stopTest();

    System.assertEquals(account.Id, result.AccountId, 'Account should be mapped.');
    System.assertEquals(contact1.Id, result.Contact1Id, 'Contact 1 should be mapped.');
    System.assertEquals(contact2.Id, result.Contact2Id, 'Contact 2 should be mapped.');
    System.assertEquals(Date.newInstance(2026, 12, 31), result.ExpirationDate, 'Expiration date should be parsed.');
    System.assertEquals(LkgRequestBuilderBase.KEYTYPE_GENERIC, result.KeyType, 'Key type should be mapped.');
    System.assertEquals(true, result.SendEmail, 'Send email should be mapped.');
    System.assertEquals('powertech', result.Silo, 'Silo should be mapped.');
    System.assertEquals('pt', result.subSilo, 'Sub-silo should be mapped.');
    System.assertEquals('CCSS', result.Brand, 'Brand should be mapped.');
    System.assertEquals('PT001', result.ProductCode, 'Product code should be mapped.');
    System.assertEquals('PT_PRODUCT', result.lkgProductIdentifierName, 'Identifier name should be mapped.');
    System.assertEquals('External Product', result.externalProductName, 'External name should be mapped.');
    System.assertEquals('Internal Product', result.internalProductName, 'Internal name should be mapped.');
    System.assertEquals('7.5', result.release, 'Release should be read from silo-specific attributes.');
    System.assertEquals('Mapper test notes', result.Notes, 'Notes should be mapped when provided.');
    System.assertEquals(false, result.createLicenseKeyFile, 'Create license key file should default to false.');
    System.assertEquals(Date.today(), result.StartDate, 'Start date should default to today.');
  }

  @isTest
  static void mapPayloadToKeyData_shouldDefaultNotesToEmptyString() {
    LkgMapperBase.UiPayload payload = new LkgMapperBase.UiPayload();
    payload.expirationDate = '2026-01-15';
    payload.keyType = LkgRequestBuilderBase.KEYTYPE_PERMANENT;
    payload.sendEmail = false;
    payload.productData = new LkgMapperBase.ProductData();
    payload.productData.silo = 'robot';
    payload.productData.subSilo = null;
    payload.productData.brandName = 'Robot';
    payload.productData.productCode = 'ROB001';
    payload.productData.identifierName = 'ROB_PRODUCT';
    payload.productData.externalName = 'Robot External';
    payload.productData.internalName = 'Robot Internal';
    payload.attributes = new Map<String, String>{ 'robot_Release' => '1.0' };

    Test.startTest();
    LkgRequestBuilderBase.KeyData result = mapper.mapPayloadToKeyData(JSON.serialize(payload));
    Test.stopTest();

    System.assertEquals('', result.Notes, 'Notes should default to an empty string.');
    System.assertEquals(false, result.createLicenseKeyFile, 'Create license key file should remain false.');
  }

  @isTest
  static void safeParseInt_shouldReturnParsedIntegerForValidValue() {
    Test.startTest();
    Integer result = mapper.parseInteger('42');
    Test.stopTest();

    System.assertEquals(42, result, 'Valid integer input should be parsed.');
  }

  @isTest
  static void safeParseInt_shouldReturnNullForInvalidValue() {
    Test.startTest();
    Integer result = mapper.parseInteger('not-a-number');
    Test.stopTest();

    System.assertEquals(null, result, 'Invalid integer input should return null.');
  }
}