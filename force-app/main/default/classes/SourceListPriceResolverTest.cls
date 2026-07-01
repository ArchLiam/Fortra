@IsTest
private class SourceListPriceResolverTest {

    @IsTest
    static void resolve_returnsSourceLicenseUnitPrice() {
        Id pricebookId = Test.getStandardPricebookId();

        Product2 license = new Product2(Name = 'Test License', IsActive = true);
        Product2 maintenance = new Product2(Name = 'Test Maintenance', IsActive = true);
        insert new List<Product2>{ license, maintenance };

        PricebookEntry licensePbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = license.Id,
            UnitPrice = 355,
            IsActive = true,
            IsDerived = false
        );
        PricebookEntry maintenancePbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = maintenance.Id,
            UnitPrice = 0,
            IsActive = true,
            IsDerived = true
        );
        insert new List<PricebookEntry>{ licensePbe, maintenancePbe };

        insert new PriceBookEntryDerivedPrice(
            PricebookEntryId = maintenancePbe.Id,
            ContributingProductId = license.Id
        );

        SourceListPriceResolver.ResolutionResult result = SourceListPriceResolver.resolve(
            maintenancePbe.Id,
            pricebookId,
            UserInfo.getDefaultCurrency()
        );

        System.assertEquals(true, result.isResolved(), 'Expected resolved result: ' + result.skipReason);
        System.assertEquals(355, result.unitPrice);
    }

    @IsTest
    static void resolve_skipsNonDerivedPbe() {
        Id pricebookId = Test.getStandardPricebookId();
        Product2 license = new Product2(Name = 'License Only', IsActive = true);
        insert license;

        PricebookEntry licensePbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = license.Id,
            UnitPrice = 100,
            IsActive = true,
            IsDerived = false
        );
        insert licensePbe;

        SourceListPriceResolver.ResolutionResult result = SourceListPriceResolver.resolve(
            licensePbe.Id,
            pricebookId,
            UserInfo.getDefaultCurrency()
        );

        System.assertEquals(false, result.isResolved());
        System.assertEquals('Not a derived PBE', result.skipReason);
    }

    @IsTest
    static void resolve_skipsWhenNoContributors() {
        Id pricebookId = Test.getStandardPricebookId();
        Product2 maintenance = new Product2(Name = 'Maintenance Only', IsActive = true);
        insert maintenance;

        PricebookEntry maintenancePbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = maintenance.Id,
            UnitPrice = 0,
            IsActive = true,
            IsDerived = true
        );
        insert maintenancePbe;

        SourceListPriceResolver.ResolutionResult result = SourceListPriceResolver.resolve(
            maintenancePbe.Id,
            pricebookId,
            UserInfo.getDefaultCurrency()
        );

        System.assertEquals(false, result.isResolved());
        System.assertEquals('No derived price contributors', result.skipReason);
    }

    @IsTest
    static void resolve_skipsAmbiguousContributors() {
        Id pricebookId = Test.getStandardPricebookId();
        Product2 licenseA = new Product2(Name = 'License A', IsActive = true);
        Product2 licenseB = new Product2(Name = 'License B', IsActive = true);
        Product2 maintenance = new Product2(Name = 'Maintenance Ambiguous', IsActive = true);
        insert new List<Product2>{ licenseA, licenseB, maintenance };

        PricebookEntry maintenancePbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = maintenance.Id,
            UnitPrice = 0,
            IsActive = true,
            IsDerived = true
        );
        insert maintenancePbe;

        insert new List<PriceBookEntryDerivedPrice>{
            new PriceBookEntryDerivedPrice(
                PricebookEntryId = maintenancePbe.Id,
                ContributingProductId = licenseA.Id
            ),
            new PriceBookEntryDerivedPrice(
                PricebookEntryId = maintenancePbe.Id,
                ContributingProductId = licenseB.Id
            )
        };

        SourceListPriceResolver.ResolutionResult result = SourceListPriceResolver.resolve(
            maintenancePbe.Id,
            pricebookId,
            UserInfo.getDefaultCurrency()
        );

        System.assertEquals(false, result.isResolved());
        System.assertEquals('Ambiguous derived contributors', result.skipReason);
    }
}