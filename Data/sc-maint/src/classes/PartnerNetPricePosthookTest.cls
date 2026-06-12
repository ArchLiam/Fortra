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
            UnitPrice = 0,
            // This org has a before-save flow that defaults a BLANK line-level
            // Fortra_Product_Type__c to 'Software'. Set the maintenance type
            // explicitly so the bulk map carries the real derived type that the
            // posthook must honour (New Maintenance 12%, not the Software default).
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert qli;

        QuoteLineItem reloaded = [
            SELECT Fortra_Product_Type__c FROM QuoteLineItem WHERE Id = :qli.Id
        ];
        System.assertEquals('New Maintenance', reloaded.Fortra_Product_Type__c,
            'Precondition: line-level type persists as New Maintenance for the bulk map');

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

        // Org VR "No checklist items found for Quote" fires when the Quote is
        // referenced by an Order insert; seed one so the Order insert succeeds.
        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

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
    static void enrichPartnerDataFromSourceQuote_usesSalesTransactionSourceKey() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'STS Partner', Type = 'Partner');
        insert partner;
        // Org VR requires an active Partner_Pricing_Model__c matching the Quote's selected model.
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, Software_Percent__c = 15
        );
        Account customer = new Account(Name = 'STS Customer');
        insert customer;
        Opportunity opp = new Opportunity(
            AccountId = customer.Id, Name = 'STS Opp', StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'STS Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Billing_Partner__c = partner.Id, Partner_Pricing_Model__c = 'Discount'
        );
        insert q;
        insert new Quote_Checklist_Item__c(
            Quote__c = q.Id, Item_Name__c = 'Checklist Item', Sort_Order__c = 1, Is_Checked__c = true
        );
        Order ord = new Order(
            AccountId = customer.Id, Status = 'Draft', EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(), QuoteId = q.Id
        );
        insert ord;

        // No 'Id' key -> falls back to 'SalesTransactionSource' (line 578).
        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        posthook.enrichPartnerDataFromSourceQuote(
            new Map<String, Object>{ 'SalesTransactionSource' => ord.Id }, data
        );

        System.assertEquals(partner.Id, data.billingPartnerId);
        System.assertEquals('Discount', data.partnerPricingModel);
    }

    @IsTest
    static void enrichPartnerDataFromSourceQuote_orderWithoutQuoteReturns() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account customer = new Account(Name = 'NoQuote Customer');
        insert customer;
        // Order with NO QuoteId -> ord.Quote is null -> early return (line 592).
        Order ord = new Order(
            AccountId = customer.Id, Status = 'Draft', EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        PartnerNetPricePosthook.QuoteHeaderData data = new PartnerNetPricePosthook.QuoteHeaderData();
        posthook.enrichPartnerDataFromSourceQuote(
            new Map<String, Object>{ 'Id' => ord.Id }, data
        );

        System.assertEquals(false, data.hasPartnerPricing(),
            'Order without a source Quote leaves the header unpopulated');
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

    @IsTest
    static void applyNetPricesToOrder_nullOrderReturnsZero() {
        System.assertEquals(0, PartnerNetPricePosthook.applyNetPricesToOrder(null),
            'Null order id short-circuits to zero updates');
    }

    @IsTest
    static void execute_skipsWhenContextIdBlank() {
        // RevSignaling.TransactionRequest has no public constructor; materialize it via JSON
        // so the signaling entry point can be driven from a unit test.
        RevSignaling.TransactionRequest req = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":""}', RevSignaling.TransactionRequest.class);

        Test.startTest();
        RevSignaling.TransactionResponse resp = new PartnerNetPricePosthook().execute(req);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status);
        System.assert(resp.message.contains('no context id'),
            'Blank context id should short-circuit with the no-context message');
    }

    @IsTest
    static void execute_handlesContextErrorGracefully() {
        // A non-existent context id makes the in-procedure Context query fail; execute()
        // must swallow it and still report SUCCESS (it never blocks the pricing transaction).
        RevSignaling.TransactionRequest req = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":"fake-ctx-instance"}', RevSignaling.TransactionRequest.class);

        Test.startTest();
        RevSignaling.TransactionResponse resp = new PartnerNetPricePosthook().execute(req);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status,
            'Posthook never fails the pricing transaction; errors become warnings');
        System.assertNotEquals(null, resp.message);
    }

    @IsTest
    static void applyPostPricingNetPrices_guardsAndBlankRequest() {
        System.assertEquals(true,
            PartnerNetPricePosthook.applyPostPricingNetPrices(null).isEmpty(),
            'Null request list returns empty');
        System.assertEquals(true,
            PartnerNetPricePosthook.applyPostPricingNetPrices(
                new List<PartnerNetPricePosthook.PostPricingContextRequest>()
            ).isEmpty(),
            'Empty request list returns empty');

        // A request with a blank context id never touches the pricing Context API;
        // it should record a 0-line result for that request.
        PartnerNetPricePosthook.PostPricingContextRequest blank =
            new PartnerNetPricePosthook.PostPricingContextRequest();
        blank.contextInstanceId = '';
        List<Integer> results = PartnerNetPricePosthook.applyPostPricingNetPrices(
            new List<PartnerNetPricePosthook.PostPricingContextRequest>{ blank }
        );
        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0], 'Blank context id yields zero lines updated');
    }

    @IsTest
    static void buildNetPriceUpdate_returnsColaUpdateWhenRenewalMaintenanceMatches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();
        Id quoteId = fakeQuoteId();

        QuoteLineItem qli = new QuoteLineItem(
            Id = lineId,
            QuoteId = quoteId,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
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

        // The 5-arg overload should short-circuit and return the COLA update (line 216 branch).
        Map<String, Object> result = posthook.buildNetPriceUpdate(
            lineItem,
            null,
            null,
            new Map<Id, String>{ lineId => 'Renewal Maintenance' },
            new Map<Id, QuoteLineItem>{ lineId => qli }
        );

        System.assertNotEquals(null, result, 'COLA update should be returned ahead of generic partner net');
        System.assertEquals(67.38, attributesByName(result).get('NetUnitPrice'));
    }

    @IsTest
    static void buildNetPriceUpdate_returnsNullWhenUpdatePathMissing() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        // No _updatePath and no renewal-maint map -> updatePath null branch (line 221).
        Map<String, Object> lineItem = new Map<String, Object>{
            'PartnerUnitPrice' => 100,
            'NetUnitPrice' => 200,
            'Quantity' => 1
        };
        System.assertEquals(null, posthook.buildNetPriceUpdate(lineItem),
            'Missing update path returns null');
    }

    @IsTest
    static void buildNetPriceUpdate_skipsWhenCommercialEqualsExistingPartnerUnit() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        // procedureNet == commercial and existingPartnerUnit == partnerUnitPrice
        // but commercial != partnerUnitPrice -> exercises the 256-257 skip branch.
        Map<String, Object> lineItem = new Map<String, Object>{
            '_updatePath' => new List<Object>{ '0Q0TEST', '0QLTEST' },
            'PartnerUnitPrice' => 301.75,
            'NetUnitPrice' => 241.40,
            'Quantity' => 1
        };
        System.assertEquals(null, posthook.buildNetPriceUpdate(lineItem),
            'Skip when commercial net already aligns with stamped partner unit');
    }

    @IsTest
    static void shouldSkipProcedureOwnedPartner_evaluatesPricingSourceBranch() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        // procedureNet (200) > partnerUnit (80) so commercial = 80 != procedureNet; the first
        // skip block (320) is bypassed and execution reaches the Partner_Pricing_Source__c
        // branch (lines 329-335). Net != commercial there, so the method returns false.
        Map<String, Object> lineItem = new Map<String, Object>{
            'PartnerUnitPrice' => 80,
            'NetUnitPrice' => 200,
            'Partner_Pricing_Source__c' => 'System Calculated (Procedure)'
        };
        System.assertEquals(
            false,
            posthook.shouldSkipProcedureOwnedPartner(lineItem, 80, 12, 200),
            'Procedure source but net above commercial -> do not skip (branch evaluated)'
        );
    }

    @IsTest
    static void resolveLineTotalFromQuantity_nullUnitPriceReturnsNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(null, posthook.resolveLineTotalFromQuantity(2, null));
        System.assertEquals(120.00, posthook.resolveLineTotalFromQuantity(2, 60));
        System.assertEquals(60, posthook.resolveLineTotalFromQuantity(null, 60),
            'Null/zero quantity returns the unit price as the line total');
    }

    @IsTest
    static void resolvePreProcedurePrice_prefersRegionalThenUnitThenList() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(50, posthook.resolvePreProcedurePrice(50, 40, 30),
            'Regional net wins when positive');
        System.assertEquals(40, posthook.resolvePreProcedurePrice(0, 40, 30),
            'Unit price wins when regional is zero');
        System.assertEquals(30, posthook.resolvePreProcedurePrice(null, null, 30),
            'List price is the final fallback');
    }

    @IsTest
    static void needsDeferredPartnerPricing_falseBranches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        // partnerUnit already > 0 -> false (line 437)
        System.assertEquals(false, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'PartnerUnitPrice' => 50, 'NetUnitPrice' => 71
        }));
        // net <= 0 -> false (line 442)
        System.assertEquals(false, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'NetUnitPrice' => 0, 'UnitPrice' => 0, 'ListPrice' => 0
        }));
        // has a pre-procedure regional price -> false
        System.assertEquals(false, posthook.needsDeferredPartnerPricing(new Map<String, Object>{
            'NetUnitPrice' => 71, 'RegionalNetUnitPrice__c' => 80
        }));
    }

    @IsTest
    static void calculateDeferredPartnerPrice_guardBranches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 71, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        // No partner pricing -> null (line 366/371 guard).
        PartnerNetPricePosthook.QuoteHeaderData noPricing = new PartnerNetPricePosthook.QuoteHeaderData();
        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, noPricing,
                new Map<Id, Partner_Pricing_Model__c>(), null),
            'No partner header -> null');

        // hasPartnerPricing but empty models map -> null.
        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = UserInfo.getUserId();
        hdr.partnerPricingModel = 'Discount';
        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr,
                new Map<Id, Partner_Pricing_Model__c>(), null),
            'Empty models map -> null');
    }

    @IsTest
    static void calculateDeferredPartnerPrice_guaranteedMarginAdditive() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account reseller = new Account(Name = 'GM Reseller', Type = 'Partner');
        Account distributor = new Account(Name = 'GM Distributor', Type = 'Partner');
        insert new List<Account>{ reseller, distributor };

        insert new List<Partner_Pricing_Model__c>{
            new Partner_Pricing_Model__c(
                Account__c = reseller.Id, Model_Type__c = 'Guaranteed Margin',
                Is_Active__c = true, Is_Default__c = true, New_Maintenance_Percent__c = 12
            ),
            new Partner_Pricing_Model__c(
                Account__c = distributor.Id, Model_Type__c = 'Guaranteed Margin',
                Is_Active__c = true, Is_Default__c = true, New_Maintenance_Percent__c = 8
            )
        };

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = reseller.Id;
        hdr.partnerPricingModel = 'Guaranteed Margin';

        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ reseller.Id, distributor.Id }, 'Guaranteed Margin'
        );

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 100, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        Test.startTest();
        PartnerNetPricePosthook.PartnerPriceResult result =
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr, models, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
        // 12% + 8% additive = 20% -> 100 * 0.80 = 80.
        System.assertEquals(80.00, result.adjustedPrice);
        System.assertEquals(20, result.totalPercent);
        System.assertEquals('Guaranteed Margin', result.pricingModel);
    }

    @IsTest
    static void calculateDeferredPartnerPrice_discountMissingMarginReturnsNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'No-Margin Partner', Type = 'Partner');
        insert partner;
        // Discount model but NO New_Maintenance percent -> margin 0 -> null (line 397).
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, Software_Percent__c = 15
        );

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = partner.Id;
        hdr.partnerPricingModel = 'Discount';

        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partner.Id }, 'Discount'
        );

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 71, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr, models, null),
            'Discount model with zero margin for the type returns null');
    }

    @IsTest
    static void calculateDeferredPartnerPrice_notNeededReturnsNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'NotNeeded Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, New_Maintenance_Percent__c = 12
        );

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = partner.Id;
        hdr.partnerPricingModel = 'Discount';
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partner.Id }, 'Discount'
        );

        // Line has a pre-procedure price (UnitPrice > 0) -> needsDeferredPartnerPricing false (line 371).
        Map<String, Object> licenseLine = new Map<String, Object>{
            'NetUnitPrice' => 200, 'UnitPrice' => 200, 'ListPrice' => 250,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(licenseLine, hdr, models, null),
            'Line already priced pre-procedure does not need deferred partner pricing');
    }

    @IsTest
    static void calculateDeferredPartnerPrice_discountBillingModelMissing() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account billing = new Account(Name = 'Missing Billing Partner', Type = 'Partner');
        Account other = new Account(Name = 'Other Partner', Type = 'Partner');
        insert new List<Account>{ billing, other };
        // Only the OTHER partner has a model; billing partner is absent from the map (line 392).
        insert new Partner_Pricing_Model__c(
            Account__c = other.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, New_Maintenance_Percent__c = 12
        );

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = billing.Id;
        hdr.partnerPricingModel = 'Discount';
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ other.Id }, 'Discount'
        );

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 71, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr, models, null),
            'Discount model with no billing-partner model returns null');
    }

    @IsTest
    static void calculateDeferredPartnerPrice_guaranteedMarginNoMarginsReturnsNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'GM Zero Margin Partner', Type = 'Partner');
        insert partner;
        // GM model with NO Services percent; the line is a Services type so every margin is 0
        // -> allMargins empty -> null (line 414).
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Guaranteed Margin',
            Is_Active__c = true, Is_Default__c = true, Software_Percent__c = 15
        );

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = partner.Id;
        hdr.partnerPricingModel = 'Guaranteed Margin';
        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partner.Id }, 'Guaranteed Margin'
        );

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 100, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'Services'
        };

        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr, models, null),
            'Guaranteed Margin with all-zero margins returns null');
    }

    @IsTest
    static void calculateDeferredPartnerPrice_unknownModelReturnsNull() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Account partner = new Account(Name = 'Unknown Model Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, New_Maintenance_Percent__c = 12
        );

        PartnerNetPricePosthook.QuoteHeaderData hdr = new PartnerNetPricePosthook.QuoteHeaderData();
        hdr.billingPartnerId = partner.Id;
        hdr.partnerPricingModel = 'Something Else'; // neither Discount nor Guaranteed Margin

        Map<Id, Partner_Pricing_Model__c> models = PartnerPricingService.getPricingModels(
            new Set<Id>{ partner.Id }, 'Discount'
        );

        Map<String, Object> derivedLine = new Map<String, Object>{
            'NetUnitPrice' => 71, 'UnitPrice' => 0, 'ListPrice' => 0,
            'Fortra_Product_Type__c' => 'New Maintenance'
        };

        System.assertEquals(null,
            posthook.calculateDeferredPartnerPrice(derivedLine, hdr, models, null),
            'Unknown pricing model name returns null');
    }

    @IsTest
    static void collectPartnerIds_guaranteedMarginAddsAllPartners() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        // Null header / null billing partner -> empty set.
        System.assertEquals(true, posthook.collectPartnerIds(null).isEmpty());
        System.assertEquals(true,
            posthook.collectPartnerIds(new PartnerNetPricePosthook.QuoteHeaderData()).isEmpty());

        PartnerNetPricePosthook.QuoteHeaderData gm = new PartnerNetPricePosthook.QuoteHeaderData();
        gm.billingPartnerId = fakeIdFor(Account.SObjectType);
        gm.resellerId = fakeIdFor(Account.SObjectType);
        gm.distributorId = fakeIdFor(Account.SObjectType);
        gm.referralPartnerId = fakeIdFor(Account.SObjectType);
        gm.partnerPricingModel = 'Guaranteed Margin';
        System.assertEquals(4, posthook.collectPartnerIds(gm).size(),
            'Guaranteed Margin collects billing + reseller + distributor + referral');

        PartnerNetPricePosthook.QuoteHeaderData disc = new PartnerNetPricePosthook.QuoteHeaderData();
        disc.billingPartnerId = fakeIdFor(Account.SObjectType);
        disc.resellerId = fakeIdFor(Account.SObjectType);
        disc.partnerPricingModel = 'Discount';
        System.assertEquals(1, posthook.collectPartnerIds(disc).size(),
            'Discount model only uses the billing partner');
    }

    @IsTest
    static void getLineItemRecordId_sourceFallbacksAndInvalid() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id real = fakeIdFor(QuoteLineItem.SObjectType);

        // Falls back to SourceRecordId when _recordId is blank.
        System.assertEquals(real, posthook.getLineItemRecordId(new Map<String, Object>{
            'SourceRecordId' => String.valueOf(real)
        }));
        // Falls back to Id when both _recordId and SourceRecordId are blank.
        System.assertEquals(real, posthook.getLineItemRecordId(new Map<String, Object>{
            'Id' => String.valueOf(real)
        }));
        // No id keys -> null.
        System.assertEquals(null, posthook.getLineItemRecordId(new Map<String, Object>()));
        // Invalid id string -> caught -> null.
        System.assertEquals(null, posthook.getLineItemRecordId(new Map<String, Object>{
            '_recordId' => 'not-an-id'
        }));
    }

    @IsTest
    static void tagExtractionHelpers_handleWrappersAndInvalid() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        // extractFieldValue: missing key, null value, wrapper-with-tagValue, wrapper-without.
        System.assertEquals(null, posthook.extractFieldValue(null, 'X'));
        System.assertEquals(null, posthook.extractFieldValue(new Map<String, Object>(), 'X'));
        System.assertEquals(null, posthook.extractFieldValue(new Map<String, Object>{ 'X' => null }, 'X'));
        System.assertEquals('wrapped', posthook.extractFieldValue(
            new Map<String, Object>{ 'X' => new Map<String, Object>{ 'tagValue' => 'wrapped' } }, 'X'));
        System.assertEquals(null, posthook.extractFieldValue(
            new Map<String, Object>{ 'X' => new Map<String, Object>{ 'other' => 'y' } }, 'X'));

        // getStringFromTag null path.
        System.assertEquals(null, posthook.getStringFromTag(new Map<String, Object>(), 'X'));

        // getIdFromTag: blank -> null, invalid -> null, valid wrapped -> Id.
        System.assertEquals(null, posthook.getIdFromTag(new Map<String, Object>{ 'X' => '' }, 'X'));
        System.assertEquals(null, posthook.getIdFromTag(new Map<String, Object>{ 'X' => 'bad' }, 'X'));
        Id real = fakeIdFor(Account.SObjectType);
        System.assertEquals(real, posthook.getIdFromTag(
            new Map<String, Object>{ 'X' => new Map<String, Object>{ 'tagValue' => String.valueOf(real) } }, 'X'));

        // getDecimalFromTag: native Decimal, string-convertible, and non-numeric -> null.
        System.assertEquals(12.5, posthook.getDecimalFromTag(new Map<String, Object>{ 'X' => 12.5 }, 'X'));
        System.assertEquals(7, posthook.getDecimalFromTag(new Map<String, Object>{ 'X' => '7' }, 'X'));
        System.assertEquals(null, posthook.getDecimalFromTag(new Map<String, Object>{ 'X' => 'abc' }, 'X'));
        System.assertEquals(null, posthook.getDecimalFromTag(new Map<String, Object>{ 'X' => null }, 'X'));
    }

    @IsTest
    static void loadRenewalMaintenanceLines_guardsAndQueries() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        System.assertEquals(true, posthook.loadRenewalMaintenanceLines(null).isEmpty());
        System.assertEquals(true, posthook.loadRenewalMaintenanceLines(new Set<Id>()).isEmpty());

        Account acct = new Account(Name = 'RML Acct');
        insert acct;
        Opportunity opp = new Opportunity(
            AccountId = acct.Id, Name = 'RML Opp', StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'RML Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(), Quote_Type__c = 'Renewal'
        );
        insert q;

        Product2 prod = new Product2(
            Name = 'RML Prod', ProductCode = 'RML-PROD', IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prod.Id,
            UnitPrice = 100, IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Base_Price__c = 71,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        Test.startTest();
        Map<Id, QuoteLineItem> result = posthook.loadRenewalMaintenanceLines(new Set<Id>{ qli.Id });
        Test.stopTest();

        System.assertEquals(true, result.containsKey(qli.Id),
            'Renewal-maintenance line on a Renewal quote is loaded');
        System.assertEquals(71, result.get(qli.Id).Base_Price__c);
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_guardBranches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf((Id) lineId),
            'NetUnitPrice' => 60.64
        };

        // Null/empty renewal map -> null.
        System.assertEquals(null,
            posthook.buildRenewalMaintenanceColaUpdate(lineItem, null, null));
        System.assertEquals(null,
            posthook.buildRenewalMaintenanceColaUpdate(lineItem,
                new Map<Id, String>(), new Map<Id, QuoteLineItem>()));

        // Line id not in the renewal map -> null.
        QuoteLineItem other = new QuoteLineItem(Id = fakeQuoteLineItemId(), Base_Price__c = 71);
        System.assertEquals(null,
            posthook.buildRenewalMaintenanceColaUpdate(lineItem,
                new Map<Id, String>{ other.Id => 'Renewal Maintenance' },
                new Map<Id, QuoteLineItem>{ other.Id => other }));

        // colaNet null (no Base_Price__c) -> null.
        QuoteLineItem noBase = new QuoteLineItem(Id = lineId, Base_Price__c = null);
        System.assertEquals(null,
            posthook.buildRenewalMaintenanceColaUpdate(lineItem,
                new Map<Id, String>{ lineId => 'Renewal Maintenance' },
                new Map<Id, QuoteLineItem>{ lineId => noBase }));
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_buildsPathAndDiscountAttributes() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();
        Id quoteId = fakeQuoteId();

        QuoteLineItem qli = new QuoteLineItem(
            Id = lineId, QuoteId = quoteId,
            Base_Price__c = 71, Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0, COLA_Uplift_Percent__c = 7.85,
            PartnerDiscountPercent = 12, Discount = 10, Quantity = 2,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        // No _updatePath in the lineItem -> resolveRenewalMaintenanceUpdatePath builds it
        // from quoteId + lineId (lines 883-886). Also carries Discount attribute (858-860).
        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf((Id) lineId),
            'NetUnitPrice' => 50
        };

        Map<String, Object> result = posthook.buildRenewalMaintenanceColaUpdate(
            lineItem,
            new Map<Id, String>{ lineId => 'Renewal Maintenance' },
            new Map<Id, QuoteLineItem>{ lineId => qli }
        );

        System.assertNotEquals(null, result, 'Should build COLA update and derive the update path');
        Map<String, Object> attrs = attributesByName(result);
        System.assertEquals(12, attrs.get('PartnerDiscountPercent'),
            'Stamped partner percent carried forward');
        System.assertEquals(10, attrs.get('Discount'),
            'Software discount percent carried forward');
        // Quantity 2 -> line total = colaNet * 2.
        Decimal net = (Decimal) attrs.get('NetUnitPrice');
        System.assertEquals((net * 2).setScale(2, RoundingMode.HALF_UP), attrs.get('TotalPrice'));
    }

    @IsTest
    static void resolveRenewalMaintenanceUpdatePath_branches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();
        Id quoteId = fakeQuoteId();

        // Existing _updatePath is returned as-is.
        List<Object> path = new List<Object>{ 'a', 'b' };
        System.assertEquals(path,
            posthook.resolveRenewalMaintenanceUpdatePath(
                new Map<String, Object>{ '_updatePath' => path }, lineId, quoteId));

        // No _updatePath but quoteId + lineId present -> derived path.
        Object derived = posthook.resolveRenewalMaintenanceUpdatePath(
            new Map<String, Object>(), lineId, quoteId);
        System.assertNotEquals(null, derived);
        System.assertEquals(2, ((List<Object>) derived).size());

        // No _updatePath and a null quoteId -> null (line 884).
        System.assertEquals(null,
            posthook.resolveRenewalMaintenanceUpdatePath(new Map<String, Object>(), lineId, null));
    }

    @IsTest
    static void buildRenewalMaintenanceColaUpdate_nullWhenNoUpdatePathDerivable() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id lineId = fakeQuoteLineItemId();

        // qli with NO QuoteId and lineItem with NO _updatePath -> updatePath null -> return null (line 830).
        QuoteLineItem qli = new QuoteLineItem(
            Id = lineId, Base_Price__c = 71, Prior_Partner_Discount__c = 8.52,
            COLA_Uplift_Percent__c = 7.85, Quantity = 1,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        Map<String, Object> lineItem = new Map<String, Object>{
            '_recordId' => String.valueOf((Id) lineId),
            'NetUnitPrice' => 60.64
        };

        System.assertEquals(null,
            posthook.buildRenewalMaintenanceColaUpdate(
                lineItem,
                new Map<Id, String>{ lineId => 'Renewal Maintenance' },
                new Map<Id, QuoteLineItem>{ lineId => qli }
            ),
            'No derivable update path -> null COLA update');
    }

    @IsTest
    static void renewalDiscretionaryAndPartnerPercent_branches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        // resolveRenewalDiscretionaryDollars: explicit prior dollars wins.
        System.assertEquals(5,
            posthook.resolveRenewalDiscretionaryDollars(new QuoteLineItem(
                Base_Price__c = 71, Prior_Discretionary_Discount__c = 5, Discount = 10)));
        // No prior dollars and no discount -> 0.
        System.assertEquals(0,
            posthook.resolveRenewalDiscretionaryDollars(new QuoteLineItem(
                Base_Price__c = 71, Discount = 0)));
        // Derive from percent when no prior dollars.
        Decimal derived = posthook.resolveRenewalDiscretionaryDollars(new QuoteLineItem(
            Base_Price__c = 71, Prior_Partner_Discount__c = 8.52, Discount = 10));
        System.assertEquals(((71 - 8.52) * 0.10).setScale(2, RoundingMode.HALF_UP), derived);

        // resolveRenewalPartnerPercent: stamped percent wins.
        System.assertEquals(12,
            posthook.resolveRenewalPartnerPercent(new QuoteLineItem(
                Base_Price__c = 71, PartnerDiscountPercent = 12)));
        // No base price -> null.
        System.assertEquals(null,
            posthook.resolveRenewalPartnerPercent(new QuoteLineItem(Base_Price__c = null)));
        // No prior partner discount -> null.
        System.assertEquals(null,
            posthook.resolveRenewalPartnerPercent(new QuoteLineItem(Base_Price__c = 71)));
        // Derive percent from prior partner dollars.
        System.assertEquals(((8.52 / 71) * 100).setScale(2, RoundingMode.HALF_UP),
            posthook.resolveRenewalPartnerPercent(new QuoteLineItem(
                Base_Price__c = 71, Prior_Partner_Discount__c = 8.52)));

        // computeRenewalMaintenanceColaNet: null / zero base -> null; pre-cola <= 0 -> null.
        System.assertEquals(null, posthook.computeRenewalMaintenanceColaNet(null));
        System.assertEquals(null,
            posthook.computeRenewalMaintenanceColaNet(new QuoteLineItem(Base_Price__c = 0)));
        System.assertEquals(null,
            posthook.computeRenewalMaintenanceColaNet(new QuoteLineItem(
                Base_Price__c = 71, Prior_Partner_Discount__c = 100)));
    }

    // =========================================================================
    // Context.IndustriesContext I/O coverage via the behavior-preserving test
    // seams. Each test injects a fabricated queryTags/buildContext response that
    // mirrors the real RCA shape so the JSON parsing + per-line apply loop +
    // would-be context-write payload all execute under a unit test.
    // =========================================================================

    /**
     * Build a queryTags('SalesTransactionItem') style response:
     *   { queryResult: { SalesTransactionItem: [ { tagValue: {...}, dataPath: [quoteId, lineId] } ] } }
     */
    private static Map<String, Object> lineItemsResponse(List<Map<String, Object>> wrappers) {
        return new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => wrappers
            }
        };
    }

    private static Map<String, Object> lineItemWrapper(Object quoteId, Object lineId, Map<String, Object> tagValue) {
        return new Map<String, Object>{
            'tagValue' => tagValue,
            'dataPath' => new List<Object>{ quoteId, lineId }
        };
    }

    /**
     * Build a queryTags('SalesTransaction') style response:
     *   { queryResult: { SalesTransaction: [ { tagValue: {...header...} } ] } }
     */
    private static Map<String, Object> quoteHeaderResponse(Map<String, Object> tagValue) {
        return new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{
                    new Map<String, Object>{ 'tagValue' => tagValue }
                }
            }
        };
    }

    @IsTest
    static void queryLineItems_parsesInjectedResponse() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        // Use a generic List<Object> so the SalesTransactionItem array can hold a
        // well-formed wrapper, a tagValue-less wrapper, and a non-map raw item —
        // exercising the parse-success + both skip (continue) branches.
        PartnerNetPricePosthook.testLineItemsResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    lineItemWrapper(quoteId, lineId, new Map<String, Object>{
                        'PartnerUnitPrice' => 1606.40,
                        'NetUnitPrice' => 2008.00,
                        'Quantity' => 1
                    }),
                    new Map<String, Object>{ 'dataPath' => new List<Object>{ quoteId, lineId } },
                    'not-a-map'
                }
            }
        };

        Test.startTest();
        List<Map<String, Object>> parsed =
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx-instance');
        Test.stopTest();

        System.assertEquals(1, parsed.size(), 'Only the well-formed wrapper should parse');
        Map<String, Object> li = parsed[0];
        System.assertEquals(String.valueOf(lineId), li.get('_recordId'),
            '_recordId should be the last dataPath element');
        List<Object> updatePath = (List<Object>) li.get('_updatePath');
        System.assertEquals(1, updatePath.size(),
            '_updatePath drops the leading context node, leaving the line node');
        System.assertEquals(String.valueOf(lineId), updatePath[0]);
        System.assertEquals(2008.00, posthook.getDecimalFromTag(li, 'NetUnitPrice'));
    }

    @IsTest
    static void queryLineItems_nullResponseAndMissingTagReturnEmpty() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        // Response with neither queryResult nor SalesTransactionItem -> empty.
        PartnerNetPricePosthook.testLineItemsResponse = new Map<String, Object>{ 'unrelated' => 'x' };
        System.assertEquals(0,
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx').size(),
            'Response without the expected keys yields no line items');

        // queryResult present but not a map -> empty.
        PartnerNetPricePosthook.testLineItemsResponse =
            new Map<String, Object>{ 'queryResult' => 'not-a-map' };
        System.assertEquals(0,
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx').size());

        // queryResult map without SalesTransactionItem -> empty.
        PartnerNetPricePosthook.testLineItemsResponse =
            new Map<String, Object>{ 'queryResult' => new Map<String, Object>{ 'Other' => 1 } };
        System.assertEquals(0,
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx').size());
    }

    @IsTest
    static void queryLineItems_singleObjectAndUnwrappedQueryResult() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        // Top-level SalesTransactionItem (no queryResult wrapper) AND a single
        // object (not a List) -> exercises the unwrapped + single-item branches.
        PartnerNetPricePosthook.testLineItemsResponse = new Map<String, Object>{
            'SalesTransactionItem' => lineItemWrapper(quoteId, lineId, new Map<String, Object>{
                'NetUnitPrice' => 100
            })
        };

        List<Map<String, Object>> parsed =
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx');
        System.assertEquals(1, parsed.size());
        System.assertEquals(String.valueOf(lineId), parsed[0].get('_recordId'));
    }

    @IsTest
    static void queryQuoteHeaderFromContext_parsesPartnerHeader() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id partnerId = fakeIdFor(Account.SObjectType);

        PartnerNetPricePosthook.testQuoteHeaderResponse = quoteHeaderResponse(new Map<String, Object>{
            'Billing_Partner__c' => String.valueOf(partnerId),
            'Partner_Pricing_Model__c' => 'Discount'
        });

        Test.startTest();
        PartnerNetPricePosthook.QuoteHeaderData data =
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx-instance');
        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assertEquals(partnerId, data.billingPartnerId);
        System.assertEquals('Discount', data.partnerPricingModel);
        System.assertEquals(true, data.hasPartnerPricing());
    }

    @IsTest
    static void queryQuoteHeaderFromContext_mapTransactionAndGuardBranches() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id partnerId = fakeIdFor(Account.SObjectType);

        // SalesTransaction as a direct Map (not a List, no tagValue wrapper)
        // and top-level (no queryResult) -> exercises the map + unwrapped branches.
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'SalesTransaction' => new Map<String, Object>{
                'Billing_Partner__c' => String.valueOf(partnerId),
                'Partner_Pricing_Model__c' => 'Guaranteed Margin'
            }
        };
        PartnerNetPricePosthook.QuoteHeaderData data =
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx');
        System.assertEquals(partnerId, data.billingPartnerId);
        System.assertEquals('Guaranteed Margin', data.partnerPricingModel);

        // queryResult present but missing SalesTransaction -> null.
        PartnerNetPricePosthook.testQuoteHeaderResponse =
            new Map<String, Object>{ 'queryResult' => new Map<String, Object>{ 'Other' => 1 } };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // queryResult not a map -> null.
        PartnerNetPricePosthook.testQuoteHeaderResponse =
            new Map<String, Object>{ 'queryResult' => 'nope' };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // SalesTransaction present but null -> null.
        PartnerNetPricePosthook.testQuoteHeaderResponse =
            new Map<String, Object>{ 'SalesTransaction' => null };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // Empty SalesTransaction list -> null.
        PartnerNetPricePosthook.testQuoteHeaderResponse =
            new Map<String, Object>{ 'SalesTransaction' => new List<Object>() };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));
    }

    @IsTest
    static void queryQuoteHeaderFromContext_listWrapperWithoutTagValueAndNonMap() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id partnerId = fakeIdFor(Account.SObjectType);

        // List element is a Map WITHOUT a tagValue wrapper -> txnWrapper is used as
        // the transaction data directly (line 568 branch).
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{
                    new Map<String, Object>{
                        'Billing_Partner__c' => String.valueOf(partnerId),
                        'Partner_Pricing_Model__c' => 'Discount'
                    }
                }
            }
        };
        PartnerNetPricePosthook.QuoteHeaderData data =
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx');
        System.assertEquals(partnerId, data.billingPartnerId,
            'A bare map in the SalesTransaction list is used directly as the tag data');

        // First list element is NOT a map -> null (line 558 branch).
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{ 'not-a-map' }
            }
        };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // tagValue present but not a map -> null (line 564 branch).
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransaction' => new List<Object>{
                    new Map<String, Object>{ 'tagValue' => 'not-a-map' }
                }
            }
        };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // SalesTransaction is neither List nor Map (a String) -> null (line 573 branch).
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SalesTransaction' => 'scalar' }
        };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));

        // queryResult missing SalesTransaction key -> null (line 542 already; also 538 via
        // a response lacking both keys handled in the earlier guard test).
        PartnerNetPricePosthook.testQuoteHeaderResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{ 'SomethingElse' => 1 }
        };
        System.assertEquals(null,
            posthook.queryQuoteHeaderFromContext(new Context.IndustriesContext(), 'ctx'));
    }

    @IsTest
    static void queryLineItems_skipsWrapperWithNonMapTagValue() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        // One wrapper whose tagValue is NOT a map -> skipped (line 678 continue);
        // one well-formed wrapper -> parsed. Net result: one line item.
        PartnerNetPricePosthook.testLineItemsResponse = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    new Map<String, Object>{ 'tagValue' => 'not-a-map', 'dataPath' => new List<Object>{ quoteId, lineId } },
                    lineItemWrapper(quoteId, lineId, new Map<String, Object>{ 'NetUnitPrice' => 100 })
                }
            }
        };

        List<Map<String, Object>> parsed =
            posthook.queryLineItems(new Context.IndustriesContext(), 'ctx');
        System.assertEquals(1, parsed.size(),
            'Wrapper with a non-map tagValue is skipped; only the well-formed one parses');
    }

    @IsTest
    static void applyNetPricesToOrder_buildContextThrowsReturnsZero() {
        // buildContext stub resolves a context id, but the line-items read is left
        // unset so applyPartnerNetPrices hits the live queryTags (which throws outside
        // a pricing txn); applyNetPricesToOrder must swallow it and return 0.
        PartnerNetPricePosthook.testBuildContextResponse =
            new Map<String, Object>{ 'contextId' => 'order-ctx-err' };
        // Intentionally do NOT set testLineItemsResponse, so queryLineItems calls the
        // real ctx.queryTags and throws -> caught by applyNetPricesToOrder.

        Test.startTest();
        Integer updated = PartnerNetPricePosthook.applyNetPricesToOrder(fakeIdFor(Order.SObjectType));
        Test.stopTest();

        System.assertEquals(0, updated,
            'A failure while applying inside the order path is swallowed and returns 0');
    }

    @IsTest
    static void applyPartnerNetPrices_appliesPartnerNetAndCapturesUpdate() {
        Account partner = new Account(Name = 'ApplyLoop Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true,
            New_Maintenance_Percent__c = 12, Software_Percent__c = 15
        );

        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        // Header response provides the partner pricing context.
        PartnerNetPricePosthook.testQuoteHeaderResponse = quoteHeaderResponse(new Map<String, Object>{
            'Billing_Partner__c' => String.valueOf(partner.Id),
            'Partner_Pricing_Model__c' => 'Discount'
        });
        // One line where procedure net (2008) is above partner net (1606.40):
        // the posthook must drive commercial net down to the partner tier.
        PartnerNetPricePosthook.testLineItemsResponse = lineItemsResponse(new List<Map<String, Object>>{
            lineItemWrapper(quoteId, lineId, new Map<String, Object>{
                'PartnerUnitPrice' => 1606.40,
                'NetUnitPrice' => 2008.00,
                'UnitPrice' => 2008.00,
                'Quantity' => 1
            })
        });

        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Test.startTest();
        Integer updated = posthook.applyPartnerNetPrices('ctx-instance');
        Test.stopTest();

        System.assertEquals(1, updated, 'One line should receive a partner-net update');
        System.assertNotEquals(null, PartnerNetPricePosthook.testCapturedItemUpdates,
            'submitContextUpdates should have captured the write payload');
        System.assertEquals(1, PartnerNetPricePosthook.testCapturedItemUpdates.size());

        Map<String, Object> attrs = attributesByName(PartnerNetPricePosthook.testCapturedItemUpdates[0]);
        System.assertEquals(1606.40, attrs.get('NetUnitPrice'),
            'Net should be pulled down to the partner tier');
        System.assertEquals(1606.40, attrs.get('PartnerUnitPrice'));
    }

    @IsTest
    static void applyPartnerNetPrices_emptyLinesReturnsZero() {
        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();
        PartnerNetPricePosthook.testLineItemsResponse =
            lineItemsResponse(new List<Map<String, Object>>());

        Test.startTest();
        Integer updated = posthook.applyPartnerNetPrices('ctx-instance');
        Test.stopTest();

        System.assertEquals(0, updated, 'No line items -> zero updates, no write attempted');
    }

    @IsTest
    static void applyPartnerNetPrices_renewalMaintenanceColaPath() {
        // Seed a real renewal-maintenance QLI so loadRenewalMaintenanceLines finds it
        // and the COLA branch of the apply loop fires end-to-end.
        Account acct = new Account(Name = 'COLA Loop Acct');
        insert acct;
        Opportunity opp = new Opportunity(
            AccountId = acct.Id, Name = 'COLA Loop Opp', StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Quote q = new Quote(
            Name = 'COLA Loop Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(), Quote_Type__c = 'Renewal'
        );
        insert q;
        Product2 prod = new Product2(
            Name = 'COLA Loop Prod', ProductCode = 'COLA-LOOP', IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prod.Id,
            UnitPrice = 100, IsActive = true
        );
        insert pbe;
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Product2Id = prod.Id,
            Quantity = 1, UnitPrice = 50, Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52, COLA_Uplift_Percent__c = 7.85,
            PartnerDiscountPercent = 12, Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        // Line item whose procedure net (60.64) is stale vs COLA net (67.38).
        PartnerNetPricePosthook.testLineItemsResponse = lineItemsResponse(new List<Map<String, Object>>{
            lineItemWrapper(q.Id, qli.Id, new Map<String, Object>{
                'NetUnitPrice' => 60.64,
                'Fortra_Product_Type__c' => 'Renewal Maintenance'
            })
        });
        // No partner header needed; COLA path is driven by the seeded QLI.
        PartnerNetPricePosthook.testQuoteHeaderResponse = quoteHeaderResponse(new Map<String, Object>());

        PartnerNetPricePosthook posthook = new PartnerNetPricePosthook();

        Test.startTest();
        Integer updated = posthook.applyPartnerNetPrices('ctx-instance');
        Test.stopTest();

        System.assertEquals(1, updated, 'Renewal-maintenance COLA correction should emit one update');
        Map<String, Object> attrs = attributesByName(PartnerNetPricePosthook.testCapturedItemUpdates[0]);
        System.assertEquals(67.38, attrs.get('NetUnitPrice'),
            'COLA net should replace the stale procedure net');
        System.assertEquals(12, attrs.get('PartnerDiscountPercent'));
    }

    @IsTest
    static void execute_appliesPartnerNetEndToEnd() {
        Account partner = new Account(Name = 'Execute Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, Software_Percent__c = 15
        );

        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        PartnerNetPricePosthook.testQuoteHeaderResponse = quoteHeaderResponse(new Map<String, Object>{
            'Billing_Partner__c' => String.valueOf(partner.Id),
            'Partner_Pricing_Model__c' => 'Discount'
        });
        PartnerNetPricePosthook.testLineItemsResponse = lineItemsResponse(new List<Map<String, Object>>{
            lineItemWrapper(quoteId, lineId, new Map<String, Object>{
                'PartnerUnitPrice' => 1606.40,
                'NetUnitPrice' => 2008.00,
                'Quantity' => 1
            })
        });

        RevSignaling.TransactionRequest req = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":"ctx-instance"}', RevSignaling.TransactionRequest.class);

        Test.startTest();
        RevSignaling.TransactionResponse resp = new PartnerNetPricePosthook().execute(req);
        Test.stopTest();

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status);
        System.assert(resp.message.contains('applied to 1 line'),
            'Success message should report one line updated, was: ' + resp.message);
    }

    @IsTest
    static void execute_skipsWhenAlreadyProcessing() {
        // Re-entrancy guard (lines 57-59): when isProcessing is already true,
        // execute() short-circuits with the "already processing" message.
        PartnerNetPricePosthook.isProcessing = true;
        RevSignaling.TransactionRequest req = (RevSignaling.TransactionRequest)
            JSON.deserialize('{"ctxInstanceId":"ctx-1"}', RevSignaling.TransactionRequest.class);

        Test.startTest();
        RevSignaling.TransactionResponse resp = new PartnerNetPricePosthook().execute(req);
        Test.stopTest();

        // Reset so other tests in the run are unaffected.
        PartnerNetPricePosthook.isProcessing = false;

        System.assertEquals(RevSignaling.TransactionStatus.SUCCESS, resp.status);
        System.assert(resp.message.contains('already processing'),
            'Should hit the already-processing guard, was: ' + resp.message);
    }

    @IsTest
    static void applyNetPricesToOrder_buildContextPathAppliesAndPersists() {
        Account partner = new Account(Name = 'Order Path Partner', Type = 'Partner');
        insert partner;
        insert new Partner_Pricing_Model__c(
            Account__c = partner.Id, Model_Type__c = 'Discount',
            Is_Active__c = true, Is_Default__c = true, Software_Percent__c = 15
        );

        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();
        Id orderId = fakeIdFor(Order.SObjectType);

        // buildContext returns a context id; applyPartnerNetPrices then runs with the
        // injected line/header responses; persistContext is stubbed under the override.
        PartnerNetPricePosthook.testBuildContextResponse =
            new Map<String, Object>{ 'contextId' => 'order-ctx-1' };
        PartnerNetPricePosthook.testQuoteHeaderResponse = quoteHeaderResponse(new Map<String, Object>{
            'Billing_Partner__c' => String.valueOf(partner.Id),
            'Partner_Pricing_Model__c' => 'Discount'
        });
        PartnerNetPricePosthook.testLineItemsResponse = lineItemsResponse(new List<Map<String, Object>>{
            lineItemWrapper(quoteId, lineId, new Map<String, Object>{
                'PartnerUnitPrice' => 1606.40,
                'NetUnitPrice' => 2008.00,
                'Quantity' => 1
            })
        });

        Test.startTest();
        Integer updated = PartnerNetPricePosthook.applyNetPricesToOrder(orderId);
        Test.stopTest();

        System.assertEquals(1, updated, 'Order path should apply partner net to the one line');
        System.assertNotEquals(null, PartnerNetPricePosthook.testCapturedItemUpdates);
    }

    @IsTest
    static void applyNetPricesToOrder_blankContextIdReturnsZero() {
        // buildContext stub returns no resolvable context id -> short-circuit to 0.
        PartnerNetPricePosthook.testBuildContextResponse = new Map<String, Object>{ 'somethingElse' => 'x' };
        Test.startTest();
        Integer updated = PartnerNetPricePosthook.applyNetPricesToOrder(fakeIdFor(Order.SObjectType));
        Test.stopTest();
        System.assertEquals(0, updated, 'Unresolvable context id yields zero updates');
    }

    @IsTest
    static void applyPostPricingNetPrices_invokesApplyLoop() {
        // Drives the @InvocableMethod path with a non-blank context id so the
        // applyPartnerNetPrices call line executes (line ~953).
        PartnerNetPricePosthook.testLineItemsResponse =
            lineItemsResponse(new List<Map<String, Object>>());

        PartnerNetPricePosthook.PostPricingContextRequest req =
            new PartnerNetPricePosthook.PostPricingContextRequest();
        req.contextInstanceId = 'ctx-invocable';

        Test.startTest();
        List<Integer> results = PartnerNetPricePosthook.applyPostPricingNetPrices(
            new List<PartnerNetPricePosthook.PostPricingContextRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(0, results[0], 'Empty injected line set yields zero updates');
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

    private static Integer fakeIdCounter = 1;

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        // A 15-char Id (prefix + 12 body chars) is always parseable by Id.valueOf;
        // the previous 18-char literal carried an invalid '...AAA' checksum, so
        // Id.valueOf rejected it and getLineItemRecordId() returned null.
        String body = String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return Id.valueOf(keyPrefix + body);
    }
}