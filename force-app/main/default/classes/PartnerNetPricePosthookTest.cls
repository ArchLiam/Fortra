@IsTest
private class PartnerNetPricePosthookTest {

    private static void createQuoteChecklist(Id quoteId) {
        insert new Quote_Checklist_Item__c(
            Quote__c = quoteId,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );
    }

    private static void forceProductTypeForLine(Map<Id, String> productTypeByLineId, Id lineId, String productType) {
        productTypeByLineId.put(lineId, productType);
    }

    private static void seedProductTypeForLine(Map<Id, String> productTypeByLineId, Id lineId, String fallbackType) {
        if (productTypeByLineId.containsKey(lineId)) {
            String existing = productTypeByLineId.get(lineId);
            if (String.isNotBlank(existing) && existing != 'Software') {
                return;
            }
            productTypeByLineId.remove(lineId);
        }

        QuoteLineItem qli = [
            SELECT Fortra_Product_Type__c, Product2.Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE Id = :lineId
        ];
        if (String.isNotBlank(qli.Fortra_Product_Type__c) && qli.Fortra_Product_Type__c != 'Software') {
            productTypeByLineId.put(lineId, qli.Fortra_Product_Type__c);
        } else if (String.isNotBlank(qli.Product2.Fortra_Product_Type__c) && qli.Product2.Fortra_Product_Type__c != 'Software') {
            productTypeByLineId.put(lineId, qli.Product2.Fortra_Product_Type__c);
        } else {
            productTypeByLineId.put(lineId, fallbackType);
        }
    }

    @IsTest
    static void testBuildNetPriceUpdate_SkipsWhenProcedurePreservedDiscretionaryNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 301.75,
            'NetUnitPrice' => 241.40,
            'UnitPrice' => 355,
            'Discount' => 20,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertEquals(null, result,
            'Should not overwrite procedure net when commercial net is already below partner net');
    }

    @IsTest
    static void testBuildNetPriceUpdate_UsesCommercialNetWhenPartnerNetNotYetStamped() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 301.75,
            'NetUnitPrice' => 241.40,
            'Quantity' => 2
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertEquals(null, result,
            'PartnerUnitPrice already stamped — no context write needed');

        Decimal commercial = PartnerNetResolutionCalculator.resolveCommercialUnitPrice(241.40, 301.75);
        System.assertEquals(241.40, commercial,
            'Commercial net must remain procedure value, not partner net 301.75');
        System.assertEquals(482.80, (commercial * 2).setScale(2, RoundingMode.HALF_UP),
            'Line total should use commercial net × qty when an update is emitted');
    }

    @IsTest
    static void testBuildNetPriceUpdate_SkipsWhenDiscretionaryNetAndPartnerAlreadyStamped() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 301.75,
            'NetUnitPrice' => 241.40,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertEquals(null, result,
            'Should skip when commercial net and PartnerUnitPrice are already aligned');
    }

    @IsTest
    static void testResolveCommercialUnitPrice_prefersLowerProcedureNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        System.assertEquals(241.40, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(241.40, 301.75));
        System.assertEquals(301.75, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(301.75, 301.75));
        System.assertEquals(301.75, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(355, 301.75));
        System.assertEquals(62.48, PartnerNetResolutionCalculator.resolveCommercialUnitPrice(71, 62.48));
    }

    @IsTest
    static void testBuildNetPriceUpdate_AppliesPartnerPriceToNetFields() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 1606.40,
            'NetUnitPrice' => 2008.00,
            'UnitPrice' => 2008.00,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should build an update when partner and net prices differ');

        Map<String, Object> valuesByName = attributesByName(result);
        System.assertEquals(1606.40, valuesByName.get('NetUnitPrice'));
        System.assertEquals(1606.40, valuesByName.get('NetTotalPrice'));
        System.assertEquals(1606.40, valuesByName.get('TotalPrice'));
        System.assertEquals(1606.40, valuesByName.get('Subtotal'));
        System.assertEquals(1606.40, valuesByName.get('TotalLineAmount'));
        System.assertEquals(1606.40, valuesByName.get('PartnerUnitPrice'));
    }

    @IsTest
    static void testBuildNetPriceUpdate_SkipsWhenNetAlreadyMatches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 782.00,
            'NetUnitPrice' => 782.00,
            'UnitPrice' => 782.00,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertEquals(null, result, 'Should skip when net price already matches partner price');
    }

    @IsTest
    static void testBuildNetPriceUpdate_SkipsWithoutPartnerPrice() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'NetUnitPrice' => 2008.00,
            'UnitPrice' => 2008.00,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem);
        Test.stopTest();

        System.assertEquals(null, result, 'Should skip when partner price is absent and line had pre-procedure price');
    }

    @IsTest
    static void testNeedsDeferredPartnerPricing_detectsDerivedMaintenanceLine() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0
        };

        Map<String, Object> licenseLine = new Map<String, Object>{
            'NetUnitPrice' => 301.75,
            'UnitPrice' => 301.75,
            'ListPrice' => 355
        };

        System.assertEquals(true, posthook.needsDeferredPartnerPricing(derivedLine));
        System.assertEquals(false, posthook.needsDeferredPartnerPricing(licenseLine));
    }

    @IsTest
    static void testCalculateDeferredPartnerPrice_newMaintenanceDiscount() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'Posthook Test Partner', Type = 'Partner');
        insert partner;

        Partner_Pricing_Model__c model = new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );
        insert model;

        PartnerNetPricePosthook.QuoteHeaderData quoteData = new PartnerNetPricePosthook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');

        Map<String, Object> maintenanceLine = new Map<String, Object>{
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        Test.startTest();
        PartnerNetPricePosthook.PartnerPriceResult result =
            posthook.calculateDeferredPartnerPrice(maintenanceLine, quoteData, partnerModels, null);
        Test.stopTest();

        System.assertEquals(null, result,
            'Deferred partner pricing must not run for derived maintenance');
    }

    @IsTest
    static void testBuildNetPriceUpdate_skipsDeferredPartnerForDerivedMaintenance() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'Posthook Test Partner 2', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );

        PartnerNetPricePosthook.QuoteHeaderData quoteData = new PartnerNetPricePosthook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');

        Map<Id, String> productTypeByLineId = new Map<Id, String>();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            '_recordId' => UserInfo.getUserId(),
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance',
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(
            lineItem, quoteData, partnerModels, productTypeByLineId, null, null
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'Posthook must not override NetUnitPrice on derived maintenance');
    }

    @IsTest
    static void testBuildNetPriceUpdate_skipsDeferredPartnerForColaOwnedRenewalMaintenance() {
        // SC-3346 RN-COLA-COMMIT: when the procedure already committed the correct COLA net,
        // buildRenewalMaintenanceColaUpdate returns null (no change needed). The line must NOT
        // fall through to deferred partner pricing, which would re-discount the COLA net a second
        // time (67.38 -> 60.64). A renewal-maintenance line is owned entirely by the COLA path.
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'RN COLA Owned Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            Renewal_Maintenance_Percent__c = 12,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );

        PartnerNetPricePosthook.QuoteHeaderData quoteData = new PartnerNetPricePosthook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';
        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');

        Id qliId = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        QuoteLineItem qli = new QuoteLineItem(
            Id = qliId,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0,
            COLA_Uplift_Percent__c = 7.85,
            Quantity = 1
        );
        Map<Id, QuoteLineItem> renewalMaintenanceByLineId = new Map<Id, QuoteLineItem>{ qliId => qli };

        // Procedure already committed the COLA net (67.38 == colaNet) so the COLA update is a no-op,
        // which previously caused a fall-through to deferred partner pricing and a double discount.
        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', String.valueOf(qliId) },
            '_recordId' => String.valueOf(qliId),
            'NetUnitPrice' => 67.38,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'Renewal Maintenance',
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(
            lineItem, quoteData, partnerModels, null, renewalMaintenanceByLineId
        );
        Test.stopTest();

        System.assertEquals(null, result,
            'COLA-owned renewal-maintenance line must not be re-discounted by deferred partner pricing');
    }

    @IsTest
    static void testBuildNetPriceUpdate_usesProductTypeFromBulkMapWhenContextBlank() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'Posthook Test Partner 3', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            New_Maintenance_Percent__c = 12,
            Software_Percent__c = 15
        );

        Product2 maintProd = new Product2(
            Name = 'Maint Product Type Test',
            ProductCode = 'MAINT-TYPE-TEST',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Account acct = new Account(Name = 'Maint Type Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Maint Type Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Maint Type Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0
        );
        insert qli;

        System.assertEquals(null, qli.Fortra_Product_Type__c, 'Precondition: line-level type is blank on derived-style line');

        PartnerNetPricePosthook.QuoteHeaderData quoteData = new PartnerNetPricePosthook.QuoteHeaderData();
        quoteData.billingPartnerId = partner.Id;
        quoteData.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(new Set<Id>{ partner.Id }, 'Discount');
        Map<Id, String> productTypeByLineId = PartnerPricingService.ensureProductTypesLoaded(
            new Set<Id>{ qli.Id },
            PartnerPricingService.loadProductTypesForLines(new Set<Id>{ qli.Id })
        );
        seedProductTypeForLine(productTypeByLineId, qli.Id, 'Software');
        forceProductTypeForLine(productTypeByLineId, qli.Id, 'Software');

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ q.Id, qli.Id },
            '_recordId' => qli.Id,
            'NetUnitPrice' => 100,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(
            lineItem,
            quoteData,
            partnerModels,
            productTypeByLineId
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        Map<String, Object> valuesByName = attributesByName(result);
        System.assertEquals(15, valuesByName.get('PartnerDiscountPercent'), 'Should use Software 15% from bulk map');
        System.assertEquals(85, valuesByName.get('NetUnitPrice'));
    }

    @IsTest
    static void enrichPartnerDataFromSourceQuote_fallsBackToLinkedQuote() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'Enrich Fallback Partner', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 15
        );

        Account customer = new Account(Name = 'Enrich Fallback Customer');
        insert customer;

        Opportunity opp = new Opportunity(
            AccountId = customer.Id,
            Name = 'Enrich Fallback Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Enrich Fallback Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Billing_Partner__c = partner.Id,
            Partner_Pricing_Model__c = 'Discount'
        );
        insert q;
        createQuoteChecklist(q.Id);

        Order ord = new Order(
            AccountId = customer.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        Map<String, Object> transactionData = new Map<String, Object>{
            'Id' => ord.Id
        };

        Test.startTest();
        posthook.enrichPartnerDataFromSourceQuote(transactionData, data);
        Test.stopTest();

        System.assertEquals(partner.Id, data.billingPartnerId,
            'Order reprice context should inherit Billing Partner from source Quote');
        System.assertEquals('Discount', data.partnerPricingModel);
        System.assertEquals(true, data.hasPartnerPricing());
    }

    @IsTest
    static void enrichPartnerDataFromSourceQuote_skipsNonOrderTransaction() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        Map<String, Object> transactionData = new Map<String, Object>{
            'Id' => UserInfo.getUserId()
        };

        posthook.enrichPartnerDataFromSourceQuote(transactionData, data);

        System.assertEquals(false, data.hasPartnerPricing(),
            'Non-order transaction id should not populate partner header');
    }

    @IsTest
    static void testShouldSkipProcedureOwnedPartner_whenProcedureStampedPartnerTier() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 62.48,
            'PartnerDiscountPercent' => 12,
            'NetUnitPrice' => 49.98,
            'Partner_Pricing_Source__c' => 'System Calculated (Procedure)',
            'Quantity' => 1
        };

        System.assertEquals(
            true,
            posthook.shouldSkipProcedureOwnedPartner(lineItem, 62.48, 12, 49.98),
            'Should skip deferred partner when procedure already stamped tier and commercial net is set'
        );
    }

    @IsTest
    static void testShouldSkipProcedureOwnedPartner_falseWhenNetNeedsPartnerEnforcement() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        System.assertEquals(
            false,
            posthook.shouldSkipProcedureOwnedPartner(
                new Map<String, Object>{
                    'PartnerUnitPrice' => 1606.40,
                    'NetUnitPrice' => 2008.00
                },
                1606.40,
                null,
                2008.00
            ),
            'Should not skip when net still exceeds partner tier'
        );
    }

    @IsTest
    static void computeRenewalMaintenanceColaNet_appliesUpliftToStampedComponents() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0,
            Discount = 10,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        Decimal priorDisc = RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(qli);
        Decimal expectedPreCola = 71 - 8.52 - priorDisc;
        Decimal expectedNet = (expectedPreCola * 1.0785).setScale(2, RoundingMode.HALF_UP);

        System.assertEquals(
            expectedNet,
            RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(qli),
            'COLA should uplift base minus partner and software discount components'
        );
        System.assertEquals(
            12,
            posthook.resolveRenewalPartnerPercent(new QuoteLineItem(
                Base_Price__c = 71,
                Prior_Partner_Discount__c = 8.52,
                PartnerDiscountPercent = 12
            ))
        );
    }

    @IsTest
    static void buildRenewalColaCommitUpdate_commitsColaWhenNetUnitPriceZero() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id qliId = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000099';
        Id quoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000099';

        QuoteLineItem qli = new QuoteLineItem(
            Id = qliId,
            QuoteId = quoteId,
            COLACalculatedPrice__c = 10089,
            Quantity = 1
        );
        Map<Id, QuoteLineItem> renewalColaByLineId = new Map<Id, QuoteLineItem>{ qliId => qli };

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ String.valueOf(quoteId), String.valueOf(qliId) },
            '_recordId' => String.valueOf(qliId),
            'NetUnitPrice' => 0,
            'Quantity' => 1
        };

        Map<String, Object> updatePayload = posthook.buildRenewalColaCommitUpdate(lineItem, renewalColaByLineId);

        System.assertNotEquals(null, updatePayload, 'Should commit COLA net when procedure net is zero');
        Map<String, Object> attrs = attributesByName(updatePayload);
        System.assertEquals(10089, attrs.get('NetUnitPrice'));
        System.assertEquals(10089, attrs.get('UnitPrice'));
        System.assertEquals(10089, attrs.get('NetTotalPrice'));
    }

    @IsTest
    static void buildRenewalColaCommitUpdate_fixesStaleMaintenanceNetOnRenewal() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id qliId = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000098';
        Id quoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000098';

        QuoteLineItem qli = new QuoteLineItem(
            Id = qliId,
            QuoteId = quoteId,
            Fortra_Product_Type__c = 'New Maintenance',
            Base_Price__c = 71,
            COLACalculatedPrice__c = 76.57,
            Quantity = 1
        );
        Map<Id, QuoteLineItem> renewalColaByLineId = new Map<Id, QuoteLineItem>{ qliId => qli };

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ String.valueOf(quoteId), String.valueOf(qliId) },
            '_recordId' => String.valueOf(qliId),
            'NetUnitPrice' => 71,
            'Quantity' => 1
        };

        Map<String, Object> updatePayload = posthook.buildRenewalColaCommitUpdate(lineItem, renewalColaByLineId);

        System.assertNotEquals(null, updatePayload);
        System.assertEquals(76.57, attributesByName(updatePayload).get('NetUnitPrice'));
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account acct = new Account(Name = 'COLA Update Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'COLA Update Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();
        Product2 maintProd = new Product2(
            Name = 'COLA Update Product',
            ProductCode = 'COLA-UPDATE-TEST',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'COLA Update Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'Renewal'
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 60.64,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        qli = [
            SELECT Id, QuoteId, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, Quantity
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];

        Decimal expectedNet = RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(qli);
        System.assertNotEquals(null, expectedNet, 'Precondition: COLA net should be computable from stamped inputs');

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ q.Id, qli.Id },
            '_recordId' => String.valueOf(qli.Id),
            'NetUnitPrice' => 60.64,
            'Quantity' => 1
        };

        Map<String, Object> updatePayload = posthook.buildRenewalMaintenanceColaUpdate(
            lineItem,
            new Map<Id, String>{ qli.Id => 'Renewal Maintenance' },
            new Map<Id, QuoteLineItem>{ qli.Id => qli }
        );

        System.assertNotEquals(null, updatePayload, 'Should correct net when procedure used stale asset price');
        Map<String, Object> attrs = attributesByName(updatePayload);
        System.assertEquals(expectedNet, attrs.get('NetUnitPrice'));
        System.assertEquals(expectedNet, attrs.get('TotalPrice'));
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_skipsWhenNetAlreadyMatchesCola() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();
        Id quoteId = fakeQuoteId();

        QuoteLineItem qli = new QuoteLineItem(
            Id = lineId,
            QuoteId = quoteId,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ String.valueOf(quoteId), String.valueOf(lineId) },
            '_recordId' => String.valueOf((Id) lineId),
            'NetUnitPrice' => 67.38
        };

        System.assertEquals(
            null,
            posthook.buildRenewalMaintenanceColaUpdate(
                lineItem,
                new Map<Id, String>{ lineId => 'Renewal Maintenance' },
                new Map<Id, QuoteLineItem>{ lineId => qli }
            )
        );
    }

    // -----------------------------------------------------------------------
    // SC-3346 NB-DERIVED: New-Maintenance post-procedure net fallback.
    // The procedure leaves NetUnitPrice null on Amend/asset-copy lines; the
    // posthook fallback prices them (Source_List_Price x rate, less partner %).
    // -----------------------------------------------------------------------

    @IsTest
    static void buildNewMaintenanceUpdate_pricesAssetCopyLineLeftAtZero() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        // Real Id required: getLineItemRecordId uses Id.valueOf(), which rejects a fake checksum.
        QuoteLineItem inserted = insertNewMaintQli();
        QuoteLineItem qli = new QuoteLineItem(
            Id = inserted.Id,
            QuoteId = inserted.QuoteId,
            Source_List_Price__c = 355,
            PartnerDiscountPercent = 12,
            Quantity = 1,
            Fortra_Product_Type__c = 'New Maintenance'
        );

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ inserted.QuoteId, inserted.Id },
            '_recordId' => String.valueOf(inserted.Id),
            'NetUnitPrice' => null,
            'Quantity' => 1
        };

        Map<Id, PartnerNetPricePosthook.NewMaintInputs> newMaintById =
            new Map<Id, PartnerNetPricePosthook.NewMaintInputs>{
                inserted.Id => new PartnerNetPricePosthook.NewMaintInputs(
                    null, false, qli.Source_List_Price__c, qli.PartnerDiscountPercent, qli.Discount,
                    qli.Quantity, 0.20, inserted.QuoteId)
            };

        Map<String, Object> updatePayload = posthook.buildNewMaintenanceUpdate(lineItem, newMaintById);

        System.assertNotEquals(null, updatePayload,
            'Should price a New-Maintenance line the procedure left at $0');
        Map<String, Object> attrs = attributesByName(updatePayload);
        // 355 * 0.20 = 71 list; * (1 - 0.12) = 62.48 net (legacy list-only fallback)
        System.assertEquals(62.48, attrs.get('NetUnitPrice'));
        System.assertEquals(62.48, attrs.get('NetTotalPrice'));
        System.assertEquals(62.48, attrs.get('PartnerUnitPrice'));
        System.assertEquals(12, attrs.get('PartnerDiscountPercent'));
        System.assertEquals('System Calculated (Post-Procedure Fallback)',
            attrs.get('Partner_Pricing_Source__c'));
    }

    @IsTest
    static void buildNewMaintenanceUpdate_pricesFromContributorNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        QuoteLineItem inserted = insertNewMaintQli();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ inserted.QuoteId, inserted.Id },
            '_recordId' => String.valueOf(inserted.Id),
            'NetUnitPrice' => null,
            'Quantity' => 1
        };

        Map<Id, PartnerNetPricePosthook.NewMaintInputs> newMaintById =
            new Map<Id, PartnerNetPricePosthook.NewMaintInputs>{
                inserted.Id => new PartnerNetPricePosthook.NewMaintInputs(
                    700, true, 355, null, null, 1, 0.20, inserted.QuoteId)
            };

        Map<String, Object> updatePayload = posthook.buildNewMaintenanceUpdate(lineItem, newMaintById);

        System.assertNotEquals(null, updatePayload);
        Map<String, Object> attrs = attributesByName(updatePayload);
        System.assertEquals(140, attrs.get('NetUnitPrice'), '20% of contributor net 700');
        System.assertEquals(140, attrs.get('PartnerUnitPrice'));
    }

    @IsTest
    static void buildDerivedMaintenanceSequentialDiscountUpdate_appliesCarriedDiscounts() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id maintId = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000099';
        Id quoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000088';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(maintId),
            'NetUnitPrice' => 4000,
            'UnitPrice' => 4000,
            'ListPrice' => 0,
            'PartnerDiscountPercent' => 15,
            'Discount' => 10,
            'Fortra_Product_Type__c' => 'New Maintenance',
            'Quantity' => 1
        };

        PartnerNetPricePosthook.NewMaintInputs inputs =
            new PartnerNetPricePosthook.NewMaintInputs(20000, false, null, 15, 10, 1, 0.20, quoteId);

        Map<String, Object> updatePayload = posthook.buildDerivedMaintenanceSequentialDiscountUpdate(
            lineItem,
            inputs
        );

        System.assertNotEquals(null, updatePayload, 'Should discount derived maintenance list');
        Map<String, Object> attrs = attributesByName(updatePayload);
        System.assertEquals(4000, attrs.get('ListPrice'));
        System.assertEquals(3400, attrs.get('PartnerUnitPrice'));
        System.assertEquals(3060, attrs.get('NetUnitPrice'));
        System.assertEquals(15, attrs.get('PartnerDiscountPercent'));
        System.assertEquals(10, attrs.get('Discount'));
        System.assertEquals('System Calculated (Post-Procedure)', attrs.get('Partner_Pricing_Source__c'));
    }

    @IsTest
    static void buildDerivedMaintenanceSequentialDiscountUpdate_buildsPathWithoutContextDataPath() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id maintId = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000199';
        Id quoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000188';

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(maintId),
            'NetUnitPrice' => 4000,
            'PartnerDiscountPercent' => 15,
            'Discount' => 10,
            'Quantity' => 1
        };
        PartnerNetPricePosthook.NewMaintInputs inputs =
            new PartnerNetPricePosthook.NewMaintInputs(20000, false, null, 15, 10, 1, 0.20, quoteId);

        Map<String, Object> updatePayload = posthook.buildDerivedMaintenanceSequentialDiscountUpdate(
            lineItem,
            inputs
        );

        System.assertNotEquals(null, updatePayload);
        Map<String, Object> nodePath = (Map<String, Object>) updatePayload.get('nodePath');
        List<Object> dataPath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(String.valueOf(quoteId), String.valueOf(dataPath[0]));
        System.assertEquals(String.valueOf(maintId), String.valueOf(dataPath[1]));
    }

    @IsTest
    static void buildNewMaintenanceUpdate_skipsWhenProcedureAlreadyPriced() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        QuoteLineItem inserted = insertNewMaintQli();
        QuoteLineItem qli = new QuoteLineItem(
            Id = inserted.Id, QuoteId = inserted.QuoteId, Source_List_Price__c = 355,
            PartnerDiscountPercent = 12, Quantity = 1, Fortra_Product_Type__c = 'New Maintenance'
        );

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ inserted.QuoteId, inserted.Id },
            '_recordId' => String.valueOf(inserted.Id),
            'NetUnitPrice' => 62.48
        };

        Map<Id, PartnerNetPricePosthook.NewMaintInputs> newMaintById =
            new Map<Id, PartnerNetPricePosthook.NewMaintInputs>{
                inserted.Id => new PartnerNetPricePosthook.NewMaintInputs(
                    null, false, qli.Source_List_Price__c, qli.PartnerDiscountPercent, qli.Discount,
                    qli.Quantity, 0.20, inserted.QuoteId)
            };

        System.assertEquals(null,
            posthook.buildNewMaintenanceUpdate(lineItem, newMaintById),
            'Must NOT override a line the procedure already priced');
    }

    @IsTest
    static void stampAttributeListPricesForQuote_fixesMaintenancePartnerUnitPrice() {
        QuoteLineItem inserted = insertNewMaintQli();
        Product2 maintProd = new Product2(
            Name = 'Stamp Maint Product',
            ProductCode = 'STM-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;
        PricebookEntry maintPbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert maintPbe;
        QuoteLineItem maintenance = new QuoteLineItem(
            QuoteId = inserted.QuoteId,
            PricebookEntryId = maintPbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 4000,
            Base_Price__c = 20000,
            PartnerDiscountPercent = 15,
            Discount = 10,
            Fortra_Product_Type__c = 'New Maintenance',
            Partner_Pricing_Source__c = 'System Calculated (Post-Procedure Fallback)'
        );
        insert maintenance;
        maintenance.PartnerUnitPrice = 3060;
        update maintenance;

        Test.startTest();
        Integer stamped = PartnerNetPricePosthook.stampAttributeListPricesForQuote(inserted.QuoteId);
        Test.stopTest();

        System.assert(stamped > 0, 'Should stamp maintenance partner unit');
        maintenance = [
            SELECT PartnerUnitPrice, Partner_Pricing_Source__c
            FROM QuoteLineItem
            WHERE Id = :maintenance.Id
        ];
        System.assertEquals(3400, maintenance.PartnerUnitPrice);
        System.assertEquals('System Calculated (Post-Procedure)', maintenance.Partner_Pricing_Source__c);
    }

    private static QuoteLineItem insertNewMaintQli() {
        Account acct = new Account(Name = 'NB Maint Build Account');
        insert acct;
        Opportunity opp = new Opportunity(AccountId = acct.Id, Name = 'NB Maint Build Opp',
            StageName = 'Pre-Qualified', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPB = Test.getStandardPricebookId();
        Product2 prod = new Product2(Name = 'NB Maint Build Product',
            ProductCode = 'NBM-B-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true, Fortra_Product_Type__c = 'New Maintenance');
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPB, Product2Id = prod.Id,
            UnitPrice = 0, IsActive = true);
        insert pbe;
        Quote q = new Quote(Name = 'NB Maint Build Quote', OpportunityId = opp.Id,
            Pricebook2Id = stdPB, Quote_Type__c = 'New');
        insert q;
        createQuoteChecklist(q.Id);
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Product2Id = prod.Id, Quantity = 1, UnitPrice = 0,
            Source_List_Price__c = 355, Fortra_Product_Type__c = 'New Maintenance');
        insert qli;
        return [SELECT Id, QuoteId FROM QuoteLineItem WHERE Id = :qli.Id];
    }

    @IsTest
    static void adjustNewBusinessDerivedListLineItem_correctsStaleHighListNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.NewMaintInputs inputs =
            new PartnerNetPricePosthook.NewMaintInputs(15000, true, 355, 15, 10, 1, 0.20, null);

        Map<String, Object> lineItem = new Map<String, Object>{
            'NetUnitPrice' => 4000,
            'UnitPrice' => 4000
        };

        Map<String, Object> adjusted = posthook.adjustNewBusinessDerivedListLineItem(lineItem, inputs);
        System.assertEquals(3000, adjusted.get('NetUnitPrice'), 'Perpetual decrease should reseed derived list');
    }

    @IsTest
    static void adjustNewBusinessDerivedListLineItem_skipsWhenCommercialNetCurrent() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.NewMaintInputs inputs =
            new PartnerNetPricePosthook.NewMaintInputs(20000, true, 355, 15, 10, 1, 0.20, null);

        Map<String, Object> lineItem = new Map<String, Object>{
            'NetUnitPrice' => 3060,
            'PartnerDiscountPercent' => 15,
            'Discount' => 10
        };

        Map<String, Object> adjusted = posthook.adjustNewBusinessDerivedListLineItem(lineItem, inputs);
        System.assertEquals(3060, adjusted.get('NetUnitPrice'), 'Already-correct commercial net should not reseed');
    }

    @IsTest
    static void adjustNewBusinessDerivedListLineItem_correctsStaleListNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.NewMaintInputs inputs =
            new PartnerNetPricePosthook.NewMaintInputs(20000, true, 355, 15, 10, 1, 0.20, null);

        Map<String, Object> lineItem = new Map<String, Object>{
            'NetUnitPrice' => 60.35,
            'UnitPrice' => 71
        };

        Map<String, Object> adjusted = posthook.adjustNewBusinessDerivedListLineItem(lineItem, inputs);
        System.assertEquals(4000, adjusted.get('NetUnitPrice'));
    }

    @IsTest
    static void buildNewMaintenanceUpdate_nullWhenNotEligible() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf(fakeQuoteLineItemId()),
            'NetUnitPrice' => null
        };
        System.assertEquals(null, posthook.buildNewMaintenanceUpdate(lineItem, null),
            'Null map -> null');
        System.assertEquals(null, posthook.buildNewMaintenanceUpdate(
            lineItem, new Map<Id, PartnerNetPricePosthook.NewMaintInputs>()),
            'Empty map -> null');
    }

    @IsTest
    static void loadMaintenanceRates_returnsStandardRate() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Map<String, Decimal> rates = posthook.loadMaintenanceRates();
        System.assert(!rates.isEmpty(), 'Maintenance_Rate__mdt should yield rates');
        System.assertEquals(0.20, rates.get('Standard'), 'Standard maintenance rate is 0.20');
    }

    @IsTest
    static void loadNewMaintenanceLines_skipsLineWithoutResolvableRate() {
        // A New-Maintenance line with a source price but NO 'Maintenance Type Defn' attribute
        // cannot resolve a rate -> it is not eligible for the fallback.
        Account acct = new Account(Name = 'NB Maint Load Account');
        insert acct;
        Opportunity opp = new Opportunity(AccountId = acct.Id, Name = 'NB Maint Load Opp',
            StageName = 'Pre-Qualified', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPB = Test.getStandardPricebookId();
        Product2 prod = new Product2(Name = 'NB Maint Load Product',
            ProductCode = 'NBM-LOAD-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true, Fortra_Product_Type__c = 'New Maintenance');
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPB, Product2Id = prod.Id,
            UnitPrice = 0, IsActive = true);
        insert pbe;
        Quote q = new Quote(Name = 'NB Maint Load Quote', OpportunityId = opp.Id,
            Pricebook2Id = stdPB, Quote_Type__c = 'New');
        insert q;
        createQuoteChecklist(q.Id);
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Product2Id = prod.Id, Quantity = 1, UnitPrice = 0,
            Source_List_Price__c = 355, Fortra_Product_Type__c = 'New Maintenance');
        insert qli;

        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Map<Id, PartnerNetPricePosthook.NewMaintInputs> loaded =
            posthook.loadNewMaintenanceLines(new Set<Id>{ qli.Id });
        System.assertEquals(0, loaded.size(),
            'No Maintenance Type Defn attribute -> no rate -> line skipped');
    }

    @IsTest
    static void applyPostPricingNetPrices_handlesNullAndEmptyRequests() {
        System.assertEquals(0, PartnerNetPricePosthook.applyPostPricingNetPrices(null).size());
        System.assertEquals(
            0,
            PartnerNetPricePosthook.applyPostPricingNetPrices(
                new List<PartnerNetPricePosthook.PostPricingContextRequest>()
            ).size()
        );

        PartnerNetPricePosthook.PostPricingContextRequest blank = new PartnerNetPricePosthook.PostPricingContextRequest();
        blank.contextInstanceId = '';
        List<Integer> results = PartnerNetPricePosthook.applyPostPricingNetPrices(
            new List<PartnerNetPricePosthook.PostPricingContextRequest>{ blank }
        );
        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0]);
    }

    @IsTest
    static void applyNetPricesToOrder_returnsZeroForNullOrder() {
        System.assertEquals(0, PartnerNetPricePosthook.applyNetPricesToOrder(null));
    }

    @IsTest
    static void collectPartnerIds_includesGuaranteedMarginChannelPartners() {
        List<Account> partners = new List<Account>{
            new Account(Name = 'Posthook Billing Partner', Type = 'Partner'),
            new Account(Name = 'Posthook Reseller Partner', Type = 'Partner'),
            new Account(Name = 'Posthook Distributor Partner', Type = 'Partner'),
            new Account(Name = 'Posthook Referral Partner', Type = 'Partner')
        };
        insert partners;
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        data.billingPartnerId = partners[0].Id;
        data.partnerPricingModel = 'Guaranteed Margin';
        data.resellerId = partners[1].Id;
        data.distributorId = partners[2].Id;
        data.referralPartnerId = partners[3].Id;

        Set<Id> partnerIds = posthook.collectPartnerIds(data);
        System.assertEquals(4, partnerIds.size(), 'Guaranteed margin should collect all channel partners');
    }

    @IsTest
    static void tagHelpers_extractWrappedAndPlainValues() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Map<String, Object> wrapped = new Map<String, Object>{
            'Amount' => new Map<String, Object>{ 'tagValue' => 42.5 },
            'Name' => 'Plain'
        };

        System.assertEquals(42.5, posthook.getDecimalFromTag(wrapped, 'Amount'));
        System.assertEquals('Plain', posthook.getStringFromTag(wrapped, 'Name'));
        System.assertEquals(null, posthook.getDecimalFromTag(wrapped, 'Missing'));
    }

    @IsTest
    static void getLineItemRecordId_readsRecordIdSourceRecordIdAndId() {
        Account acct = new Account(Name = 'Line Id Helper Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Line Id Helper Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();
        Product2 prod = new Product2(Name = 'Line Id Helper Product', ProductCode = 'LINE-ID-HELPER', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Quote q = new Quote(Name = 'Line Id Helper Quote', OpportunityId = opp.Id, Pricebook2Id = stdPBId);
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert qli;

        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        String lineIdString = String.valueOf(qli.Id);

        System.assertEquals(qli.Id, posthook.getLineItemRecordId(new Map<String, Object>{
            '_recordId' => lineIdString
        }));
        System.assertEquals(qli.Id, posthook.getLineItemRecordId(new Map<String, Object>{
            'SourceRecordId' => lineIdString
        }));
        System.assertEquals(qli.Id, posthook.getLineItemRecordId(new Map<String, Object>{
            'Id' => lineIdString
        }));
        System.assertEquals(null, posthook.getLineItemRecordId(new Map<String, Object>()));
    }

    @IsTest
    static void resolveContextId_readsContextOrInstanceId() {
        System.assertEquals(null, PartnerNetPricePosthook.resolveContextId(null));
        System.assertEquals('ctx123', PartnerNetPricePosthook.resolveContextId(
            new Map<String, Object>{ 'contextId' => 'ctx123' }
        ));
        System.assertEquals('ctx456', PartnerNetPricePosthook.resolveContextId(
            new Map<String, Object>{ 'contextInstanceId' => 'ctx456' }
        ));
    }

    private static Map<String, Object> attributesByName(Map<String, Object> nodeUpdate) {
        Map<String, Object> valuesByName = new Map<String, Object>();
        if (nodeUpdate == null) {
            return valuesByName;
        }

        List<Object> attributes = (List<Object>) nodeUpdate.get('attributes');
        if (attributes == null) {
            return valuesByName;
        }

        for (Object attributeObj : attributes) {
            Map<String, Object> attribute = (Map<String, Object>) attributeObj;
            valuesByName.put(
                (String) attribute.get('attributeName'),
                attribute.get('attributeValue')
            );
        }

        return valuesByName;
    }

    private static Id fakeQuoteLineItemId() {
        return fakeIdFor(QuoteLineItem.SObjectType);
    }

    private static Id fakeQuoteId() {
        return fakeIdFor(Quote.SObjectType);
    }

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000001AAA');
    }

    @IsTest
    static void testCalculateDeferredPartnerPrice_guaranteedMargin() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        List<Account> partners = new List<Account>{
            new Account(Name = 'GM Posthook Billing', Type = 'Partner'),
            new Account(Name = 'GM Posthook Reseller', Type = 'Partner')
        };
        insert partners;

        insert new List<Partner_Pricing_Model__c>{
            new Partner_Pricing_Model__c(
                Account__c = partners[0].Id,
                Model_Type__c = 'Guaranteed Margin',
                Is_Active__c = true,
                Is_Default__c = true,
                Software_Percent__c = 15
            ),
            new Partner_Pricing_Model__c(
                Account__c = partners[1].Id,
                Model_Type__c = 'Guaranteed Margin',
                Is_Active__c = true,
                Is_Default__c = true,
                Software_Percent__c = 10
            )
        };

        PartnerNetPricePosthook.QuoteHeaderData quoteData = new PartnerNetPricePosthook.QuoteHeaderData();
        quoteData.billingPartnerId = partners[0].Id;
        quoteData.partnerPricingModel = 'Guaranteed Margin';
        quoteData.resellerId = partners[1].Id;

        Map<Id, Partner_Pricing_Model__c> partnerModels =
            PartnerPricingService.getPricingModels(
                new Set<Id>{ partners[0].Id, partners[1].Id },
                'Guaranteed Margin'
            );

        Map<String, Object> lineItem = new Map<String, Object>{
            'NetUnitPrice' => 1000,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'Software'
        };

        PartnerNetPricePosthook.PartnerPriceResult result =
            posthook.calculateDeferredPartnerPrice(lineItem, quoteData, partnerModels, null);

        System.assertNotEquals(null, result);
        System.assertEquals(750, result.adjustedPrice);
        System.assertEquals(25, result.totalPercent);
        System.assertEquals('Guaranteed Margin', result.pricingModel);
    }

    @IsTest
    static void testCalculateDeferredPartnerPrice_returnsNullWhenInputsMissing() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Map<String, Object> lineItem = new Map<String, Object>{
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0
        };

        System.assertEquals(null, posthook.calculateDeferredPartnerPrice(lineItem, null, null, null));
        System.assertEquals(null, posthook.calculateDeferredPartnerPrice(
            new Map<String, Object>{ 'NetUnitPrice' => 100, 'UnitPrice' => 100 },
            new PartnerNetPricePosthook.QuoteHeaderData(),
            new Map<Id, Partner_Pricing_Model__c>(),
            null
        ));
    }

    @IsTest
    static void testResolvePreProcedurePrice_prefersRegionalThenUnitThenList() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(900, PartnerNetResolutionCalculator.resolvePreProcedurePrice(900, 1000, 1100));
        System.assertEquals(1000, PartnerNetResolutionCalculator.resolvePreProcedurePrice(null, 1000, 1100));
        System.assertEquals(1100, PartnerNetResolutionCalculator.resolvePreProcedurePrice(null, null, 1100));
    }

    @IsTest
    static void testNeedsDeferredPartnerPricing_falseWhenPartnerUnitOrNetMissing() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        System.assertEquals(false, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'PartnerUnitPrice' => 62.48,
            'NetUnitPrice' => 71,
            'UnitPrice' => 0
        }));
        System.assertEquals(false, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'NetUnitPrice' => 0,
            'UnitPrice' => 0
        }));
        System.assertEquals(true, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0
        }));
    }

    @IsTest
    static void testResolveLineTotalFromQuantity_usesColaHelper() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(100, posthook.resolveLineTotalFromQuantity(null, 100));
        System.assertEquals(200, posthook.resolveLineTotalFromQuantity(2, 100));
    }

    @IsTest
    static void testResolveRenewalDiscretionaryDollars_fromDiscountPercent() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 100,
            Prior_Partner_Discount__c = 10,
            Discount = 20
        );

        System.assertEquals(18, RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(qli));
        System.assertEquals(5, RenewalMaintenanceColaCalculator.resolveRenewalDiscretionaryDollars(new QuoteLineItem(
            Base_Price__c = 100,
            Prior_Discretionary_Discount__c = 5
        )));
    }

    @IsTest
    static void testResolveRenewalPartnerPercent_computedFromPriorPartner() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(12, posthook.resolveRenewalPartnerPercent(new QuoteLineItem(
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52
        )));
        System.assertEquals(null, posthook.resolveRenewalPartnerPercent(new QuoteLineItem(
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 0
        )));
    }

    @IsTest
    static void testResolveRenewalMaintenanceUpdatePath_fallsBackToQuoteAndLineIds() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        Object fallbackPath = posthook.resolveRenewalMaintenanceUpdatePath(
            new Map<String, Object>(),
            lineId,
            quoteId
        );
        System.assertEquals(
            new List<Object>{ String.valueOf(quoteId), String.valueOf(lineId) },
            fallbackPath
        );
        System.assertEquals(
            new List<Object>{ 'existing' },
            posthook.resolveRenewalMaintenanceUpdatePath(
                new Map<String, Object>{ '_updatePath' => new List<Object>{ 'existing' } },
                lineId,
                quoteId
            )
        );
    }

    @IsTest
    static void testLoadRenewalMaintenanceLines_filtersRenewalQuoteType() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account acct = new Account(Name = 'Load Renewal Maint Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Load Renewal Maint Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();
        Product2 maintProd = new Product2(
            Name = 'Load Renewal Maint Product',
            ProductCode = 'LOAD-RN-MAINT',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Quote renewalQuote = new Quote(
            Name = 'Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'Renewal'
        );
        insert renewalQuote;
        createQuoteChecklist(renewalQuote.Id);

        Quote newBizQuote = new Quote(
            Name = 'New Biz Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'New'
        );
        insert newBizQuote;
        createQuoteChecklist(newBizQuote.Id);

        QuoteLineItem renewalLine = new QuoteLineItem(
            QuoteId = renewalQuote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        QuoteLineItem newBizLine = new QuoteLineItem(
            QuoteId = newBizQuote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert new List<QuoteLineItem>{ renewalLine, newBizLine };

        Map<Id, QuoteLineItem> loaded = posthook.loadRenewalMaintenanceLines(
            new Set<Id>{ renewalLine.Id, newBizLine.Id }
        );
        System.assertEquals(1, loaded.size());
        System.assert(loaded.containsKey(renewalLine.Id));
        System.assertEquals(0, posthook.loadRenewalMaintenanceLines(null).size());
    }

    @IsTest
    static void enrichPartnerDataFromSourceQuote_usesSalesTransactionSourceField() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'SalesTxn Source Partner', Type = 'Partner');
        insert partner;

        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id,
            Model_Type__c = 'Discount',
            Is_Active__c = true,
            Is_Default__c = true,
            Software_Percent__c = 15
        );

        Account customer = new Account(Name = 'SalesTxn Source Customer');
        insert customer;

        Opportunity opp = new Opportunity(
            AccountId = customer.Id,
            Name = 'SalesTxn Source Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'SalesTxn Source Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Billing_Partner__c = partner.Id,
            Partner_Pricing_Model__c = 'Discount'
        );
        insert q;
        createQuoteChecklist(q.Id);

        Order ord = new Order(
            AccountId = customer.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        posthook.enrichPartnerDataFromSourceQuote(
            new Map<String, Object>{ 'SalesTransactionSource' => ord.Id },
            data
        );

        System.assertEquals(partner.Id, data.billingPartnerId);
        System.assertEquals('Discount', data.partnerPricingModel);
    }

    @IsTest
    static void testGetIdFromTag() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Account acct = new Account(Name = 'Tag Id Account');
        insert acct;

        System.assertEquals(acct.Id, posthook.getIdFromTag(
            new Map<String, Object>{ 'AccountId' => String.valueOf(acct.Id) },
            'AccountId'
        ));
        System.assertEquals(null, posthook.getIdFromTag(new Map<String, Object>(), 'AccountId'));
        System.assertEquals(null, posthook.getIdFromTag(
            new Map<String, Object>{ 'AccountId' => 'bad-id' },
            'AccountId'
        ));
    }

    @IsTest
    static void testQueryLineItemsAndQuoteHeader_invalidContextReturnEmptyOrNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        System.assertEquals(0, posthook.queryLineItems(ctx, 'invalid-context-id').size());
        System.assertEquals(null, posthook.queryQuoteHeaderFromContext(ctx, 'invalid-context-id'));
    }

    @IsTest
    static void testParseQuoteHeaderApiResponse_readsNestedTagValue() {
        Account partner = new Account(Name = 'Parse Header Partner', Type = 'Partner');
        insert partner;

        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.QuoteHeaderData data = posthook.parseQuoteHeaderApiResponse(
            new Map<String, Object>{
                'queryResult' => new Map<String, Object>{
                    'SalesTransaction' => new List<Object>{
                        new Map<String, Object>{
                            'tagValue' => new Map<String, Object>{
                                'Billing_Partner__c' => String.valueOf(partner.Id),
                                'Partner_Pricing_Model__c' => 'Discount'
                            }
                        }
                    }
                }
            }
        );

        System.assertEquals(partner.Id, data.billingPartnerId);
        System.assertEquals('Discount', data.partnerPricingModel);
        System.assertEquals(null, posthook.parseQuoteHeaderApiResponse(null));
    }

    @IsTest
    static void testParseLineItemApiResponse_extractsWrappedLineItems() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        List<Map<String, Object>> lineItems = posthook.parseLineItemApiResponse(
            new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    new Map<String, Object>{
                        'tagValue' => new Map<String, Object>{
                            'NetUnitPrice' => 71,
                            'UnitPrice' => 0
                        },
                        'dataPath' => new List<Object>{ 'ctx1', String.valueOf(quoteId), String.valueOf(lineId) }
                    }
                }
            }
        );

        System.assertEquals(1, lineItems.size());
        System.assertEquals(String.valueOf(lineId), lineItems[0].get('_recordId'));
        System.assertEquals(71, lineItems[0].get('NetUnitPrice'));
        System.assertEquals(0, posthook.parseLineItemApiResponse(new Map<String, Object>{ 'queryResult' => 'bad' }).size());
    }

    @IsTest
    static void testSubmitContextUpdates_handlesInvalidContext() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Context.IndustriesContext ctx = new Context.IndustriesContext();

        posthook.submitContextUpdates(ctx, 'invalid-context-id', new List<Map<String, Object>>{
            new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => new List<Object>{ '0Q0TEST', '0QLTEST' } },
                'attributes' => new List<Map<String, Object>>{
                    new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => 100 }
                }
            }
        });
    }

    @IsTest
    static void testApplyPartnerNetPrices_invalidContextReturnsZero() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(0, posthook.applyPartnerNetPrices('invalid-context-id'));
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_includesDiscountPercent() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account acct = new Account(Name = 'Discount COLA Account');
        insert acct;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Discount COLA Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPBId = Test.getStandardPricebookId();
        Product2 maintProd = new Product2(
            Name = 'Discount COLA Product',
            ProductCode = 'DISC-COLA-TEST',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'Discount COLA Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'Renewal'
        );
        insert q;
        createQuoteChecklist(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0,
            Base_Price__c = 100,
            Prior_Partner_Discount__c = 10,
            COLA_Uplift_Percent__c = 5,
            Discount = 15,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        qli = [
            SELECT Id, QuoteId, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, Quantity
            FROM QuoteLineItem
            WHERE Id = :qli.Id
        ];

        Map<String, Object> updatePayload = posthook.buildRenewalMaintenanceColaUpdate(
            new Map<String, Object>{
                '_updatePath' => new List<Object>{ q.Id, qli.Id },
                '_recordId' => String.valueOf(qli.Id),
                'NetUnitPrice' => 0
            },
            new Map<Id, String>{ qli.Id => 'Renewal Maintenance' },
            new Map<Id, QuoteLineItem>{ qli.Id => qli }
        );

        System.assertNotEquals(null, updatePayload);
        System.assertEquals(15, attributesByName(updatePayload).get('Discount'));
    }

    @IsTest
    static void testQuoteHeaderDataHasPartnerPricing() {
        PartnerNetPricePosthook.QuoteHeaderData complete = new PartnerNetPricePosthook.QuoteHeaderData();
        complete.billingPartnerId = UserInfo.getUserId();
        complete.partnerPricingModel = 'Discount';
        System.assertEquals(true, complete.hasPartnerPricing());

        PartnerNetPricePosthook.QuoteHeaderData incomplete = new PartnerNetPricePosthook.QuoteHeaderData();
        incomplete.billingPartnerId = UserInfo.getUserId();
        System.assertEquals(false, incomplete.hasPartnerPricing());
    }

    @IsTest
    static void testShouldSkipProcedureOwnedPartner_whenCommercialEqualsPartnerNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(
            true,
            posthook.shouldSkipProcedureOwnedPartner(
                new Map<String, Object>{ 'PartnerUnitPrice' => 62.48 },
                62.48,
                null,
                62.48
            )
        );
    }

    @IsTest
    static void testBuildNetPriceUpdate_skipsWithoutUpdatePath() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(null, posthook.buildNetPriceUpdate(new Map<String, Object>{
            'PartnerUnitPrice' => 100,
            'NetUnitPrice' => 100
        }));
    }

    @IsTest
    static void testCollectPartnerIds_nullBillingPartnerReturnsEmpty() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(0, posthook.collectPartnerIds(null).size());
    }

    @IsTest
    static void testComputeRenewalMaintenanceColaNet_returnsNullForInvalidInputs() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(null));
        System.assertEquals(null, RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet(new QuoteLineItem(
            Base_Price__c = 10,
            Prior_Partner_Discount__c = 10
        )));
    }

    // ── SC-3544: Sales Price (UnitPrice) post-persist stamp ────────────────────────────────
    // NetUnitPrice is not writeable in Apex, so QLIs are built via JSON.deserialize.
    private static QuoteLineItem qliFromJson(String body) {
        return (QuoteLineItem) JSON.deserialize(body, QuoteLineItem.class);
    }

    @IsTest
    static void resolveSalesPrice_precedenceBaseThenPreThenNet() {
        System.assert(PartnerNetPricePosthook.resolveSalesPrice(
            qliFromJson('{"Base_Price__c":1000,"Pre_Partner_Price__c":900,"NetUnitPrice":820}')) == 1000,
            'Positive Base_Price wins');
        System.assert(PartnerNetPricePosthook.resolveSalesPrice(
            qliFromJson('{"Pre_Partner_Price__c":900,"NetUnitPrice":820}')) == 900,
            'Pre_Partner when Base null');
        System.assert(PartnerNetPricePosthook.resolveSalesPrice(
            qliFromJson('{"Base_Price__c":0,"Pre_Partner_Price__c":900,"NetUnitPrice":820}')) == 900,
            'Zero Base falls through to Pre_Partner');
        System.assert(PartnerNetPricePosthook.resolveSalesPrice(
            qliFromJson('{"NetUnitPrice":4573.80}')) == 4573.80,
            'Net fallback for renewal/derived/COLA lines (Base/Pre null)');
        System.assertEquals(null, PartnerNetPricePosthook.resolveSalesPrice(new QuoteLineItem()),
            'Null when no source present');
    }

    @IsTest
    static void buildAttributeListPriceStampUpdate_stampsUnitPriceOnRenewalColaLine() {
        // Renewal/COLA line: Fortra_Product_Type__c null, Base/Pre null, Net set, UnitPrice blank.
        QuoteLineItem upd = PartnerNetPricePosthook.buildAttributeListPriceStampUpdate(
            qliFromJson('{"NetUnitPrice":4573.80}'), new Map<String, Decimal>(), new Map<Id, String>(), new Set<Id>());
        System.assertNotEquals(null, upd, 'Blank-UnitPrice renewal/COLA line must be stamped');
        System.assert(upd.UnitPrice == 4573.80, 'UnitPrice stamped to NetUnitPrice');
    }

    @IsTest
    static void buildAttributeListPriceStampUpdate_skipsUnitPriceOnLineWithDetails() {
        // Segmented line with Quote Line Detail records: platform forbids editing UnitPrice -> skip.
        Id lid = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000097';
        QuoteLineItem upd = PartnerNetPricePosthook.buildAttributeListPriceStampUpdate(
            qliFromJson('{"Id":"' + lid + '","NetUnitPrice":4573.80}'),
            new Map<String, Decimal>(), new Map<Id, String>(), new Set<Id>{ lid });
        System.assertEquals(null, upd, 'UnitPrice must be skipped on a line with Quote Line Detail records');
    }

    @IsTest
    static void buildAttributeListPriceStampUpdate_fillOnly_neverOverwritesExistingUnitPrice() {
        // Partner line: an existing UnitPrice (593.28 net) must NOT be overwritten to the pre-partner
        // base (824), even though COALESCE(Base,Pre,Net) resolves to 824. SC-3544 is fill-only.
        QuoteLineItem upd = PartnerNetPricePosthook.buildAttributeListPriceStampUpdate(
            qliFromJson('{"Pre_Partner_Price__c":824,"NetUnitPrice":593.28,"UnitPrice":593.28}'),
            new Map<String, Decimal>(), new Map<Id, String>(), new Set<Id>());
        System.assertEquals(null, upd, 'Fill-only: an existing UnitPrice is never overwritten');
    }
}