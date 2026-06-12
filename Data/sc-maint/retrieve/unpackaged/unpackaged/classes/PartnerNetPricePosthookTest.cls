@IsTest
private class PartnerNetPricePosthookTest {

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

        Decimal commercial = posthook.resolveCommercialUnitPrice(241.40, 301.75);
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

        System.assertEquals(241.40, posthook.resolveCommercialUnitPrice(241.40, 301.75));
        System.assertEquals(301.75, posthook.resolveCommercialUnitPrice(301.75, 301.75));
        System.assertEquals(301.75, posthook.resolveCommercialUnitPrice(355, 301.75));
        System.assertEquals(62.48, posthook.resolveCommercialUnitPrice(71, 62.48));
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

        System.assertNotEquals(null, result);
        System.assertEquals(71, result.currentPrice);
        System.assertEquals(62.48, result.adjustedPrice);
        System.assertEquals(12, result.totalPercent);
    }

    @IsTest
    static void testBuildNetPriceUpdate_ComputesDeferredMaintenancePartnerPrice() {
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

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'NetUnitPrice' => 71,
            'UnitPrice' => 0,
            'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance',
            'Quantity' => 1
        };

        Test.startTest();
        Map<String, Object> result = posthook.buildNetPriceUpdate(lineItem, quoteData, partnerModels);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should compute deferred partner pricing for derived maintenance');

        Map<String, Object> valuesByName = attributesByName(result);
        System.assertEquals(62.48, valuesByName.get('NetUnitPrice'));
        System.assertEquals(62.48, valuesByName.get('PartnerUnitPrice'));
        System.assertEquals(71, valuesByName.get('Pre_Partner_Price__c'));
        System.assertEquals(62.48, valuesByName.get('Partner_Adjusted_Price__c'));
        System.assertEquals('Discount', valuesByName.get('Partner_Pricing_Model_Applied__c'));
        System.assertEquals(12, valuesByName.get('PartnerDiscountPercent'));
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
        Map<Id, String> productTypeByLineId = PartnerPricingService.loadProductTypesForLines(new Set<Id>{ qli.Id });

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ q.Id, qli.Id },
            '_recordId' => qli.Id,
            'NetUnitPrice' => 71,
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
        System.assertEquals(12, valuesByName.get('PartnerDiscountPercent'), 'Should use New Maintenance 12%, not Software 15%');
        System.assertEquals(62.48, valuesByName.get('NetUnitPrice'));
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

        Decimal priorDisc = posthook.resolveRenewalDiscretionaryDollars(qli);
        Decimal expectedPreCola = 71 - 8.52 - priorDisc;
        Decimal expectedNet = (expectedPreCola * 1.0785).setScale(2, RoundingMode.HALF_UP);

        System.assertEquals(
            expectedNet,
            posthook.computeRenewalMaintenanceColaNet(qli),
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
    static void buildRenewalMaintenanceColaUpdate_correctsStaleLastTransactionNet() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();
        Id quoteId = fakeQuoteId();

        QuoteLineItem qli = new QuoteLineItem(
            Id = lineId,
            QuoteId = quoteId,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0,
            COLA_Uplift_Percent__c = 7.85,
            PartnerDiscountPercent = 12,
            Quantity = 1,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ String.valueOf(quoteId), String.valueOf(lineId) },
            '_recordId' => String.valueOf((Id) lineId),
            'NetUnitPrice' => 60.64
        };

        Map<String, Object> updatePayload = posthook.buildRenewalMaintenanceColaUpdate(
            lineItem,
            new Map<Id, String>{ lineId => 'Renewal Maintenance' },
            new Map<Id, QuoteLineItem>{ lineId => qli }
        );

        System.assertNotEquals(null, updatePayload, 'Should correct net when procedure used stale asset price');
        Map<String, Object> attrs = attributesByName(updatePayload);
        System.assertEquals(67.38, attrs.get('NetUnitPrice'));
        System.assertEquals(67.38, attrs.get('TotalPrice'));
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
}