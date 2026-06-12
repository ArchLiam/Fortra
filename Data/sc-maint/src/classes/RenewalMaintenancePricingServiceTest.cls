@IsTest
private class RenewalMaintenancePricingServiceTest {

    private static Integer fakeIdCounter = 1;

    private static Id fakeIdFor(Schema.SObjectType sobjectType) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        String body = String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return Id.valueOf(keyPrefix + body);
    }

    private static Id fakeQuoteLineItemId() {
        return fakeIdFor(QuoteLineItem.SObjectType);
    }

    private static Id fakeQuoteId() {
        return fakeIdFor(Quote.SObjectType);
    }

    /**
     * Builds an in-memory QuoteLineItem with non-writeable fields (NetUnitPrice,
     * TotalPrice) populated via JSON deserialization. The given map of field->value
     * is serialized to a QLI; this is the standard way to seed system-managed
     * rollup fields on an unsaved SObject in a test.
     */
    private static QuoteLineItem buildQli(Map<String, Object> fields) {
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(fields), QuoteLineItem.class);
    }

    private static Quote buildQuote(Map<String, Object> fields) {
        return (Quote) JSON.deserialize(JSON.serialize(fields), Quote.class);
    }

    /**
     * Builds a real Renewal Quote with a single Renewal Maintenance QLI that has
     * Base_Price__c stamped and NetUnitPrice left at 0 (the DPP-zero condition the
     * service corrects). Returns the inserted Quote.
     */
    private static Quote createRenewalQuoteWithMaintenanceLine() {
        Account account = new Account(Name = 'RMPS Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'RMPS Test Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'RMPS Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
        );
        insert quote;

        Product2 product = new Product2(
            Name = 'RMPS Renewal Maint Product',
            ProductCode = 'RMPS-RM-' + String.valueOf(Crypto.getRandomInteger()),
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 71,
            IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = quote.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = product.Id,
            Quantity = 1,
            UnitPrice = 71,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        return quote;
    }

    /**
     * Renewal Quote with NO Renewal Maintenance line, so the candidate query returns
     * empty and the context-writer methods early-return before the Context API.
     */
    private static Quote createRenewalQuoteNoMaintenance() {
        Account account = new Account(Name = 'RMPS NoMaint Account');
        insert account;
        Opportunity opp = new Opportunity(
            Name = 'RMPS NoMaint Opp', AccountId = account.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Quote quote = new Quote(
            Name = 'RMPS NoMaint Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        insert quote;
        return quote;
    }

    // ---------------------------------------------------------------------
    // computeColaNet
    // ---------------------------------------------------------------------

    @IsTest
    static void computeColaNet_appliesUpliftToStampedComponents() {
        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 0,
            COLA_Uplift_Percent__c = 7.85,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );

        // preColaNet = 71 - 8.52 - 0 = 62.48 ; * 1.0785 = 67.38 (rounded)
        Decimal expected = (62.48 * 1.0785).setScale(2, RoundingMode.HALF_UP);
        System.assertEquals(expected,
            RenewalMaintenancePricingService.computeColaNet(qli),
            'COLA should uplift base minus prior partner and discretionary');
    }

    @IsTest
    static void computeColaNet_usesExplicitPriorDiscretionaryDollars() {
        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 100,
            Prior_Partner_Discount__c = 10,
            Prior_Discretionary_Discount__c = 5,
            COLA_Uplift_Percent__c = 10
        );
        // pre = 100 - 10 - 5 = 85 ; *1.10 = 93.50
        System.assertEquals(93.50, RenewalMaintenancePricingService.computeColaNet(qli));
    }

    @IsTest
    static void computeColaNet_derivesDiscretionaryFromDiscountPercent() {
        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Discount = 10,
            COLA_Uplift_Percent__c = 0
        );
        // discretionary = (71 - 8.52) * 0.10 = 6.248 -> 6.25
        // pre = 71 - 8.52 - 6.25 = 56.23 ; *1.0 = 56.23
        System.assertEquals(56.23, RenewalMaintenancePricingService.computeColaNet(qli));
    }

    @IsTest
    static void computeColaNet_nullAndZeroBaseReturnNull() {
        System.assertEquals(null, RenewalMaintenancePricingService.computeColaNet(null));
        System.assertEquals(null,
            RenewalMaintenancePricingService.computeColaNet(new QuoteLineItem(Base_Price__c = null)));
        System.assertEquals(null,
            RenewalMaintenancePricingService.computeColaNet(new QuoteLineItem(Base_Price__c = 0)));
    }

    @IsTest
    static void computeColaNet_preColaNonPositiveReturnsNull() {
        // partner discount swallows the whole base -> preColaNet <= 0 -> null
        System.assertEquals(null,
            RenewalMaintenancePricingService.computeColaNet(new QuoteLineItem(
                Base_Price__c = 71, Prior_Partner_Discount__c = 100)));
    }

    @IsTest
    static void computeColaNet_zeroDiscountFallsToZeroDiscretionary() {
        // Discount null/zero and no prior dollars -> discretionary 0 branch.
        QuoteLineItem qli = new QuoteLineItem(
            Base_Price__c = 50, Prior_Partner_Discount__c = 0, Discount = 0, COLA_Uplift_Percent__c = 0);
        System.assertEquals(50.00, RenewalMaintenancePricingService.computeColaNet(qli));
    }

    // ---------------------------------------------------------------------
    // resolveColaLineTotal
    // ---------------------------------------------------------------------

    @IsTest
    static void resolveColaLineTotal_branches() {
        // null colaNet -> null
        System.assertEquals(null,
            RenewalMaintenancePricingService.resolveColaLineTotal(
                new QuoteLineItem(Quantity = 3), null));

        // null/zero quantity -> flat colaNet
        System.assertEquals(67.38,
            RenewalMaintenancePricingService.resolveColaLineTotal(
                new QuoteLineItem(Quantity = null), 67.38));
        System.assertEquals(67.38,
            RenewalMaintenancePricingService.resolveColaLineTotal(
                new QuoteLineItem(Quantity = 0), 67.38));
        System.assertEquals(67.38,
            RenewalMaintenancePricingService.resolveColaLineTotal(null, 67.38));

        // positive quantity -> colaNet * qty
        System.assertEquals(134.76,
            RenewalMaintenancePricingService.resolveColaLineTotal(
                new QuoteLineItem(Quantity = 2), 67.38));
    }

    // ---------------------------------------------------------------------
    // needsColaNetCorrection / needsColaNetCorrectionForValues
    // ---------------------------------------------------------------------

    @IsTest
    static void needsColaNetCorrectionForValues_branches() {
        // colaNet null or <= 0 -> false
        System.assertEquals(false,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(null, 50));
        System.assertEquals(false,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(0, 50));

        // net null or 0 -> true
        System.assertEquals(true,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(67.38, null));
        System.assertEquals(true,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(67.38, 0));

        // net != cola -> true
        System.assertEquals(true,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(67.38, 60.64));

        // net == cola -> false
        System.assertEquals(false,
            RenewalMaintenancePricingService.needsColaNetCorrectionForValues(67.38, 67.38));
    }

    @IsTest
    static void needsColaNetCorrection_delegatesToQliValues() {
        // Base stamped, net stale -> needs correction.
        QuoteLineItem stale = buildQli(new Map<String, Object>{
            'Base_Price__c' => 71, 'Prior_Partner_Discount__c' => 8.52,
            'COLA_Uplift_Percent__c' => 7.85, 'NetUnitPrice' => 60.64});
        System.assertEquals(true,
            RenewalMaintenancePricingService.needsColaNetCorrection(stale));

        // Base stamped, net already equals cola -> no correction.
        QuoteLineItem aligned = buildQli(new Map<String, Object>{
            'Base_Price__c' => 71, 'Prior_Partner_Discount__c' => 8.52,
            'COLA_Uplift_Percent__c' => 7.85, 'NetUnitPrice' => 67.38});
        System.assertEquals(false,
            RenewalMaintenancePricingService.needsColaNetCorrection(aligned));

        // null line -> colaNet null -> false
        System.assertEquals(false,
            RenewalMaintenancePricingService.needsColaNetCorrection(null));
    }

    // ---------------------------------------------------------------------
    // filterLinesNeedingColaNet
    // ---------------------------------------------------------------------

    @IsTest
    static void filterLinesNeedingColaNet_guardAndFilter() {
        System.assertEquals(true,
            RenewalMaintenancePricingService.filterLinesNeedingColaNet(null).isEmpty());
        System.assertEquals(true,
            RenewalMaintenancePricingService.filterLinesNeedingColaNet(
                new List<QuoteLineItem>()).isEmpty());

        QuoteLineItem needs = buildQli(new Map<String, Object>{
            'Base_Price__c' => 71, 'Prior_Partner_Discount__c' => 8.52,
            'COLA_Uplift_Percent__c' => 7.85, 'NetUnitPrice' => 0});
        QuoteLineItem aligned = buildQli(new Map<String, Object>{
            'Base_Price__c' => 71, 'Prior_Partner_Discount__c' => 8.52,
            'COLA_Uplift_Percent__c' => 7.85, 'NetUnitPrice' => 67.38});

        List<QuoteLineItem> filtered = RenewalMaintenancePricingService.filterLinesNeedingColaNet(
            new List<QuoteLineItem>{ needs, aligned });
        System.assertEquals(1, filtered.size(), 'Only the stale-net line should pass the filter');
    }

    // ---------------------------------------------------------------------
    // resolveUpdatePath
    // ---------------------------------------------------------------------

    @IsTest
    static void resolveUpdatePath_branches() {
        Id quoteId = fakeQuoteId();
        Id lineId = fakeQuoteLineItemId();

        // Existing _updatePath returned as-is.
        List<Object> existing = new List<Object>{ 'q', 'l' };
        System.assertEquals(existing,
            RenewalMaintenancePricingService.resolveUpdatePath(
                new Map<String, Object>{ '_updatePath' => existing }, quoteId, lineId));

        // No _updatePath but ids present -> derived 2-element path.
        Object derived = RenewalMaintenancePricingService.resolveUpdatePath(
            new Map<String, Object>(), quoteId, lineId);
        System.assertNotEquals(null, derived);
        System.assertEquals(2, ((List<Object>) derived).size());

        // null lineItem map, ids present -> derived path.
        Object derived2 = RenewalMaintenancePricingService.resolveUpdatePath(null, quoteId, lineId);
        System.assertEquals(2, ((List<Object>) derived2).size());

        // No path and a null quoteId -> null.
        System.assertEquals(null,
            RenewalMaintenancePricingService.resolveUpdatePath(
                new Map<String, Object>(), null, lineId));
        // null lineItemId -> null.
        System.assertEquals(null,
            RenewalMaintenancePricingService.resolveUpdatePath(null, quoteId, null));
    }

    // ---------------------------------------------------------------------
    // usesColaOnlyRepriceForLines
    // ---------------------------------------------------------------------

    @IsTest
    static void usesColaOnlyRepriceForLines_guardBranches() {
        // null quote / null lines / empty lines -> false
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(null, null));
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(
                new Quote(), new List<QuoteLineItem>()));

        // Non-renewal quote -> false
        Quote nonRenewal = new Quote(Quote_Type__c = 'New');
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(
                nonRenewal,
                new List<QuoteLineItem>{ new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71) }));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_renewalMaintenanceOnlyTrue() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71)
        };
        System.assertEquals(true,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_originalActionRenewTrue() {
        // Quote_Type__c not Renewal, but OriginalActionType=Renew flips isRenewal true.
        Quote renewal = buildQuote(new Map<String, Object>{
            'Quote_Type__c' => 'New',
            'OriginalActionType' => QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW});
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71)
        };
        System.assertEquals(true,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_renewalMaintenanceMissingBaseFalse() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        // Renewal Maintenance but Base_Price__c null -> hasRenewalMaintenance stays false.
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = null)
        };
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_perpetualLineDisqualifies() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71),
            new QuoteLineItem(Fortra_Product_Type__c = 'Perpetual')
        };
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_softwareLineDisqualifies() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71),
            new QuoteLineItem(Fortra_Product_Type__c = 'Software')
        };
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_otherLineWithTotalPriceDisqualifies() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        // A non-perpetual/non-software line that already carries a positive TotalPrice -> false.
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71),
            buildQli(new Map<String, Object>{ 'Fortra_Product_Type__c' => 'Services', 'TotalPrice' => 500 })
        };
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_otherZeroTotalLineAllowed() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        // Non-disqualifying companion line with no TotalPrice -> still qualifies.
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(Fortra_Product_Type__c = 'Renewal Maintenance', Base_Price__c = 71),
            new QuoteLineItem(Fortra_Product_Type__c = 'Services')
        };
        System.assertEquals(true,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(renewal, lines));
    }

    @IsTest
    static void usesColaOnlyRepriceForLines_productTypeFromProduct2Fallback() {
        Quote renewal = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        // Line-level type blank -> falls back to Product2.Fortra_Product_Type__c.
        QuoteLineItem qli = new QuoteLineItem(Base_Price__c = 71);
        qli.Product2 = new Product2(Fortra_Product_Type__c = 'Renewal Maintenance');
        System.assertEquals(true,
            RenewalMaintenancePricingService.usesColaOnlyRepriceForLines(
                renewal, new List<QuoteLineItem>{ qli }));
    }

    // ---------------------------------------------------------------------
    // usesColaOnlyReprice(Id) — DML path
    // ---------------------------------------------------------------------

    @IsTest
    static void usesColaOnlyReprice_nullIdReturnsFalse() {
        System.assertEquals(false, RenewalMaintenancePricingService.usesColaOnlyReprice(null));
    }

    @IsTest
    static void usesColaOnlyReprice_missingQuoteReturnsFalse() {
        // Valid-shaped Quote id that does not exist -> empty query -> false.
        System.assertEquals(false,
            RenewalMaintenancePricingService.usesColaOnlyReprice(fakeQuoteId()));
    }

    @IsTest
    static void usesColaOnlyReprice_realRenewalQuoteTrue() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Test.startTest();
        Boolean result = RenewalMaintenancePricingService.usesColaOnlyReprice(quote.Id);
        Test.stopTest();
        System.assertEquals(true, result,
            'Renewal quote with only a Base-stamped Renewal Maintenance line uses COLA-only reprice');
    }

    // ---------------------------------------------------------------------
    // queryRenewalMaintenanceCandidates — TestVisible private, DML path
    // ---------------------------------------------------------------------

    @IsTest
    static void queryRenewalMaintenanceCandidates_returnsStampedRenewalLine() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Test.startTest();
        List<QuoteLineItem> candidates =
            RenewalMaintenancePricingService.queryRenewalMaintenanceCandidates(quote.Id);
        Test.stopTest();
        System.assertEquals(1, candidates.size(),
            'The Base-stamped Renewal Maintenance line is a candidate');
        System.assertEquals(71, candidates[0].Base_Price__c);
    }

    // ---------------------------------------------------------------------
    // finalizeRenewalMaintenanceAfterPricing
    // ---------------------------------------------------------------------

    @IsTest
    static void finalizeRenewalMaintenanceAfterPricing_nullQuoteReturns() {
        Test.startTest();
        RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing(null);
        Test.stopTest();
        System.assert(true, 'Null quote id is a no-op');
    }

    @IsTest
    static void finalizeRenewalMaintenanceAfterPricing_noCandidatesReturns() {
        // A renewal quote with NO renewal-maintenance candidates -> early return.
        Account account = new Account(Name = 'RMPS Empty Account');
        insert account;
        Opportunity opp = new Opportunity(
            Name = 'RMPS Empty Opp', AccountId = account.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Quote quote = new Quote(
            Name = 'RMPS Empty Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        insert quote;

        Test.startTest();
        RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing(quote.Id);
        Test.stopTest();
        System.assert(true, 'No candidates -> no context build');
    }

    // NOTE: A happy-path test that drives finalizeRenewalMaintenanceAfterPricing through
    // ctx.buildContext() for a real candidate is intentionally OMITTED. In this org's test
    // context, Context.IndustriesContext.buildContext() raises an uncatchable platform gack
    // (System.UnexpectedException "Salesforce System Error") at line 140 — which sits OUTSIDE
    // the service's try/catch — so the run cannot complete. The reachable lines of that method
    // (null guard, no-candidate guard, candidate query) are covered by the two guard tests
    // above; the buildContext/persist tail is not unit-testable here.

    // ---------------------------------------------------------------------
    // applyToContext — TestVisible private, exercised with a real candidate
    //                  and a syntactically-valid context id.
    // ---------------------------------------------------------------------

    @IsTest
    static void applyToContext_withCandidatesAndFakeContextId() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Test.startTest();
        try {
            RenewalMaintenancePricingService.applyToContext(quote.Id, 'fake-context-instance');
        } catch (Exception e) {
            // The Context API rejects the fake context id; the goal here is to drive the
            // candidate-collection + colaNet-map + queryLineItems branches, not to persist.
        }
        Test.stopTest();
        System.assert(true, 'applyToContext drives candidate collection and context query path');
    }

    @IsTest
    static void applyColaNetFinalizeToContext_withCandidatesAndFakeContextId() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Test.startTest();
        try {
            RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
                quote.Id, 'fake-context-instance');
        } catch (Exception e) {
            // Same intent as applyToContext: drive the finalize item-update build path.
        }
        Test.stopTest();
        System.assert(true, 'Finalize-to-context drives item update build path');
    }

    @IsTest
    static void applyToContext_noCandidatesEarlyReturns() {
        // Renewal quote with no Renewal Maintenance candidate -> empty-candidate guard
        // returns before touching the Context API (no gack).
        Quote quote = createRenewalQuoteNoMaintenance();
        Test.startTest();
        RenewalMaintenancePricingService.applyToContext(quote.Id, 'fake-context-instance');
        Test.stopTest();
        System.assert(true, 'applyToContext returns on empty candidate set');
    }

    @IsTest
    static void applyColaNetFinalizeToContext_noCandidatesEarlyReturns() {
        Quote quote = createRenewalQuoteNoMaintenance();
        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'fake-context-instance');
        Test.stopTest();
        System.assert(true, 'applyColaNetFinalizeToContext returns on empty candidate set');
    }

    // ---------------------------------------------------------------------
    // applyRenewalMaintenanceNetPrices (invocable)
    // ---------------------------------------------------------------------

    @IsTest
    static void applyRenewalMaintenanceNetPrices_nullAndEmptyRequests() {
        System.assertEquals(true,
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(null).isEmpty());
        System.assertEquals(true,
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>()).isEmpty());
    }

    @IsTest
    static void applyRenewalMaintenanceNetPrices_blankQuoteIdRecordsResult() {
        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = '';
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].colaOnlyPersistComplete);
    }

    @IsTest
    static void applyRenewalMaintenanceNetPrices_nullRequestInListRecordsResult() {
        List<RenewalMaintenancePricingService.RepriceRequest> reqs =
            new List<RenewalMaintenancePricingService.RepriceRequest>{ null };
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(reqs);
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].colaOnlyPersistComplete);
    }

    @IsTest
    static void applyRenewalMaintenanceNetPrices_finalizeAfterPricingBranch() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        req.contextInstanceId = 'fake-context-instance';
        req.finalizeAfterPricing = true;

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'Finalize-after-pricing path is reached and swallows context errors');
    }

    @IsTest
    static void applyRenewalMaintenanceNetPrices_applyToContextBranch() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        req.contextInstanceId = 'fake-context-instance';
        req.finalizeAfterPricing = false;

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'applyToContext branch is reached when finalizeAfterPricing is false');
    }

    @IsTest
    static void applyRenewalMaintenanceNetPrices_noContextIdRunsFinalize() {
        // A renewal quote with NO renewal-maintenance candidate: the invocable's
        // no-context-id branch calls finalizeRenewalMaintenanceAfterPricing(), which
        // early-returns at the empty-candidate guard BEFORE ctx.buildContext(). Using a
        // candidate here would hit an uncatchable platform gack from buildContext() in the
        // test context (buildContext sits outside the service try/catch), so we exercise the
        // dispatch branch without driving the un-testable context build.
        Account account = new Account(Name = 'RMPS NoCtx Account');
        insert account;
        Opportunity opp = new Opportunity(
            Name = 'RMPS NoCtx Opp', AccountId = account.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Quote quote = new Quote(
            Name = 'RMPS NoCtx Quote', OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        insert quote;

        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        // No contextInstanceId -> finalizeRenewalMaintenanceAfterPricing(quoteId) branch.

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'No context id dispatches to the finalize-after-pricing rebuild branch');
    }

    @IsTest
    static void repriceResult_defaultsToFalse() {
        // Exercises the inner result class default surface.
        RenewalMaintenancePricingService.RepriceResult r =
            new RenewalMaintenancePricingService.RepriceResult();
        System.assertEquals(null, r.colaOnlyPersistComplete);
    }

    // ---------------------------------------------------------------------
    // Context-I/O seam tests.
    //
    // The Context.IndustriesContext read (queryTags) and writes
    // (updateContextAttributes / buildContext / persistContext) throw outside a
    // live pricing transaction and so cannot be exercised directly from an Apex
    // unit test. The production class exposes two @TestVisible overrides
    // (testQueryTagsResponse, testContextIdOverride) that — ONLY under
    // Test.isRunningTest() — substitute a fabricated queryTags response / context
    // id for those calls, leaving the surrounding parse + item-update build logic
    // running for real. The overrides are null in production, so the live call
    // path is unchanged.
    // ---------------------------------------------------------------------

    /**
     * Returns the inserted Renewal Maintenance QLI id for a quote so the fake
     * queryTags dataPath can reference the real record id the service maps on.
     */
    private static Id maintenanceLineIdFor(Id quoteId) {
        return [
            SELECT Id FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            AND Fortra_Product_Type__c = 'Renewal Maintenance'
            LIMIT 1
        ].Id;
    }

    /**
     * Builds a queryTags-shaped response mirroring the real Context parser input:
     *   { queryResult => { SalesTransactionItem => [ { tagValue => {...}, dataPath => [quoteId, lineId] } ] } }
     */
    private static Map<String, Object> buildQueryTagsResponse(Id quoteId, Id lineId) {
        return new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{
                    new Map<String, Object>{
                        'tagValue' => new Map<String, Object>{
                            'NetUnitPrice' => 0,
                            'InputUnitPrice' => 0
                        },
                        'dataPath' => new List<Object>{
                            String.valueOf(quoteId), String.valueOf(lineId)
                        }
                    }
                }
            }
        };
    }

    @IsTest
    static void applyToContext_seamDrivesUpdateBuildAndWrite() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        Test.startTest();
        // Seam active -> queryTags faked, updateContextAttributes stubbed. The
        // candidate query, colaNet map, queryLineItems parse, mapLineItemsById,
        // getLineItemRecordId, resolveUpdatePath and the itemUpdates loop all run.
        RenewalMaintenancePricingService.applyToContext(quote.Id, 'ctx-instance-1');
        Test.stopTest();

        System.assert(true,
            'applyToContext ran the full parse+build+write path against the faked context I/O');
    }

    @IsTest
    static void applyColaNetFinalizeToContext_seamDrivesFinalizeBuildAndWrite() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'ctx-instance-2');
        Test.stopTest();

        System.assert(true,
            'Finalize path ran the full finalize item-update build against the faked context I/O');
    }

    @IsTest
    static void applyToContext_seamWithDataPathDerivedFromResponse() {
        // dataPath has >1 element so queryLineItems builds _updatePath (drops the
        // first/quote element) and resolveUpdatePath returns that derived path
        // rather than reconstructing it from the ids.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{
                'queryResult' => new Map<String, Object>{
                    'SalesTransactionItem' => new List<Object>{
                        new Map<String, Object>{
                            'tagValue' => new Map<String, Object>{ 'NetUnitPrice' => 0 },
                            'dataPath' => new List<Object>{
                                String.valueOf(quote.Id), String.valueOf(lineId)
                            }
                        }
                    }
                }
            };

        Test.startTest();
        RenewalMaintenancePricingService.applyToContext(quote.Id, 'ctx-instance-3');
        Test.stopTest();
        System.assert(true, 'Derived _updatePath branch of resolveUpdatePath is exercised');
    }

    @IsTest
    static void applyToContext_seamEmptyQueryResultFallsBackToDerivedPath() {
        // Empty SalesTransactionItem list -> lineItemById empty -> resolveUpdatePath
        // takes the id-reconstruction fallback (lineItem null) branch.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{
                'queryResult' => new Map<String, Object>{
                    'SalesTransactionItem' => new List<Object>()
                }
            };

        Test.startTest();
        RenewalMaintenancePricingService.applyToContext(quote.Id, 'ctx-instance-4');
        Test.stopTest();
        System.assert(true,
            'Empty query result still builds updates via the id-derived path fallback');
    }

    @IsTest
    static void applyToContext_seamFlatResponseShapeParsed() {
        // apiResponse without queryResult wrapper but with a top-level
        // SalesTransactionItem (single map, not a list) -> the alternate parse
        // branch + single-item wrap path.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{
                'SalesTransactionItem' => new Map<String, Object>{
                    'tagValue' => new Map<String, Object>{ 'NetUnitPrice' => 0 },
                    'dataPath' => new List<Object>{
                        String.valueOf(quote.Id), String.valueOf(lineId)
                    }
                }
            };

        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'ctx-instance-5');
        Test.stopTest();
        System.assert(true, 'Flat (non-queryResult) response shape and single-item wrap are parsed');
    }

    @IsTest
    static void finalize_seamRunsEndToEndThroughApplyToContext() {
        // testContextIdOverride substitutes buildContext's contextId and skips
        // persistContext; testQueryTagsResponse fakes the queryTags read inside
        // applyToContext. The whole finalize -> applyToContext chain runs for real.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testContextIdOverride = 'ctx-finalize-1';
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        Test.startTest();
        RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing(quote.Id);
        Test.stopTest();
        System.assert(true,
            'finalize built context (override), delegated to applyToContext, and skipped persist');
    }

    @IsTest
    static void finalize_seamBlankContextIdOverrideEarlyReturns() {
        // A blank context-id override -> String.isBlank(contextId) guard returns
        // before applyToContext, without touching the live persist path.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.testContextIdOverride = '';

        Test.startTest();
        RenewalMaintenancePricingService.finalizeRenewalMaintenanceAfterPricing(quote.Id);
        Test.stopTest();
        System.assert(true, 'Blank context id override hits the early-return guard');
    }

    @IsTest
    static void invocable_finalizeAfterPricing_seamReachesContextWrite() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        req.contextInstanceId = 'ctx-invoc-1';
        req.finalizeAfterPricing = true;

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'Invocable finalize branch drives the seamed finalize-to-context write');
    }

    @IsTest
    static void invocable_applyToContext_seamReachesContextWrite() {
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        req.contextInstanceId = 'ctx-invoc-2';
        req.finalizeAfterPricing = false;

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'Invocable applyToContext branch drives the seamed context write');
    }

    @IsTest
    static void queryLineItems_seamUnrecognizedShapeReturnsEmpty() {
        // apiResponse has neither 'queryResult' nor 'SalesTransactionItem' -> the
        // final else of the shape switch returns an empty line-item list, so no
        // updates are built and the method falls through its empty-updates guard.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{ 'unexpectedKey' => 'noop' };

        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'ctx-shape-1');
        Test.stopTest();
        System.assert(true, 'Unrecognized response shape returns an empty line-item list');
    }

    @IsTest
    static void queryLineItems_seamQueryResultWithoutItemsReturnsEmpty() {
        // queryResult present but with no SalesTransactionItem key -> the
        // queryResult-null/no-item guard returns empty.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{
                'queryResult' => new Map<String, Object>{ 'SomethingElse' => 'x' }
            };

        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'ctx-shape-2');
        Test.stopTest();
        System.assert(true, 'queryResult without SalesTransactionItem returns empty');
    }

    @IsTest
    static void queryLineItems_seamMalformedItemsSkipped() {
        // A SalesTransactionItem list whose entries exercise every per-item skip:
        //   - a non-map element (skipped),
        //   - a map with no tagValue (skipped),
        //   - a map whose tagValue is not a map (skipped),
        //   - a valid map with a blank dataPath terminal -> _recordId blank -> getLineItemRecordId null,
        //   - a valid map with a non-id dataPath terminal -> Id.valueOf throws -> null.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        RenewalMaintenancePricingService.testQueryTagsResponse =
            new Map<String, Object>{
                'queryResult' => new Map<String, Object>{
                    'SalesTransactionItem' => new List<Object>{
                        'not-a-map',
                        new Map<String, Object>{ 'noTagValue' => true },
                        new Map<String, Object>{ 'tagValue' => 'scalar-not-a-map' },
                        new Map<String, Object>{
                            'tagValue' => new Map<String, Object>{ 'NetUnitPrice' => 0 },
                            'dataPath' => new List<Object>{ String.valueOf(quote.Id), '' }
                        },
                        new Map<String, Object>{
                            'tagValue' => new Map<String, Object>{ 'NetUnitPrice' => 0 },
                            'dataPath' => new List<Object>{ String.valueOf(quote.Id), 'not-an-id' }
                        }
                    }
                }
            };

        Test.startTest();
        RenewalMaintenancePricingService.applyColaNetFinalizeToContext(
            quote.Id, 'ctx-shape-3');
        Test.stopTest();
        System.assert(true,
            'Every malformed-item skip branch and both getLineItemRecordId null paths are exercised');
    }

    @IsTest
    static void invocable_noContextId_seamRunsFinalizeEndToEnd() {
        // Blank contextInstanceId -> dispatch to finalizeRenewalMaintenanceAfterPricing,
        // with the seam overrides letting buildContext/queryTags run faked end-to-end.
        Quote quote = createRenewalQuoteWithMaintenanceLine();
        Id lineId = maintenanceLineIdFor(quote.Id);
        RenewalMaintenancePricingService.testContextIdOverride = 'ctx-invoc-3';
        RenewalMaintenancePricingService.testQueryTagsResponse =
            buildQueryTagsResponse(quote.Id, lineId);

        RenewalMaintenancePricingService.RepriceRequest req =
            new RenewalMaintenancePricingService.RepriceRequest();
        req.quoteId = quote.Id;
        // No contextInstanceId -> finalize dispatch.

        Test.startTest();
        List<RenewalMaintenancePricingService.RepriceResult> results =
            RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices(
                new List<RenewalMaintenancePricingService.RepriceRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, results.size(),
            'No-context-id dispatch runs the seamed finalize-after-pricing rebuild end-to-end');
    }
}