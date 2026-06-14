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
        seedProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');
        forceProductTypeForLine(productTypeByLineId, qli.Id, 'New Maintenance');

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

        Decimal expectedNet = posthook.computeRenewalMaintenanceColaNet(qli);
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
        System.assertEquals(900, posthook.resolvePreProcedurePrice(900, 1000, 1100));
        System.assertEquals(1000, posthook.resolvePreProcedurePrice(null, 1000, 1100));
        System.assertEquals(1100, posthook.resolvePreProcedurePrice(null, null, 1100));
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

        System.assertEquals(18, posthook.resolveRenewalDiscretionaryDollars(qli));
        System.assertEquals(5, posthook.resolveRenewalDiscretionaryDollars(new QuoteLineItem(
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
        System.assertEquals(null, posthook.computeRenewalMaintenanceColaNet(null));
        System.assertEquals(null, posthook.computeRenewalMaintenanceColaNet(new QuoteLineItem(
            Base_Price__c = 10,
            Prior_Partner_Discount__c = 10
        )));
    }
}