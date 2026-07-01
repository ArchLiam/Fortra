@isTest
private class Q2OConversionFaultHandlerTest {

    private static Q2OConversionFaultHandler.Request buildRequest(Id quoteId, String msg, Id orderId) {
        Q2OConversionFaultHandler.Request req = new Q2OConversionFaultHandler.Request();
        req.quoteId = quoteId;
        req.faultMessage = msg;
        req.attemptedOrderId = orderId;
        return req;
    }

    @isTest
    static void governorLimit_classifiesWithoutQueries() {
        Integer queriesBefore = Limits.getQueries();
        Q2OConversionFaultHandler.Request req = buildRequest('0Q0000000000000AAA', 'Too many SOQL queries: 101', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals('GOVERNOR_LIMIT', res[0].category);
        System.assert(String.isNotBlank(res[0].friendlyMessage));
        System.assertEquals(queriesBefore, Limits.getQueries(), 'Governor-limit path must not issue any SOQL');
    }

    @isTest
    static void isGovernorLimit_matchesKnownPatterns() {
        System.assert(Q2OConversionFaultHandler.isGovernorLimit('Too many SOQL queries: 101'));
        System.assert(Q2OConversionFaultHandler.isGovernorLimit('Too many query rows: 50001'));
        System.assert(Q2OConversionFaultHandler.isGovernorLimit('Too many DML statements: 151'));
        System.assert(Q2OConversionFaultHandler.isGovernorLimit('Apex CPU time limit exceeded'));
        System.assert(!Q2OConversionFaultHandler.isGovernorLimit('Select an active Legal Entity.'));
        System.assert(!Q2OConversionFaultHandler.isGovernorLimit(null));
    }

    @isTest
    static void mentionsLegalEntity_isCaseInsensitive() {
        System.assert(Q2OConversionFaultHandler.mentionsLegalEntity('Select an active Legal Entity.'));
        System.assert(Q2OConversionFaultHandler.mentionsLegalEntity('missing legal entity'));
        System.assert(!Q2OConversionFaultHandler.mentionsLegalEntity('Some other error'));
        System.assert(!Q2OConversionFaultHandler.mentionsLegalEntity(null));
    }

    @isTest
    static void classifyLegalEntity_activeVsInactive() {
        System.assertEquals('MISLEADING_LEGAL_ENTITY', Q2OConversionFaultHandler.classifyLegalEntity('Active'));
        System.assertEquals('REAL_LEGAL_ENTITY', Q2OConversionFaultHandler.classifyLegalEntity('Inactive'));
        System.assertEquals('REAL_LEGAL_ENTITY', Q2OConversionFaultHandler.classifyLegalEntity(null));
    }

    @isTest
    static void legalEntityFault_activeLE_isMisleading() {
        LegalEntity le = new LegalEntity(Name = 'Test Active LE', Status = 'Active');
        insert le;
        Quote q = new Quote(Name = 'Test Quote Active LE', LegalEntityId = le.Id);
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Select an active Legal Entity.', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals('MISLEADING_LEGAL_ENTITY', res[0].category);
        System.assert(res[0].friendlyMessage.contains('Test Active LE'));
    }

    @isTest
    static void legalEntityFault_noLE_isReal() {
        Quote q = new Quote(Name = 'Test Quote No LE');
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Select an active Legal Entity.', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals('REAL_LEGAL_ENTITY', res[0].category);
    }

    @isTest
    static void otherFault_returnsRawMessage() {
        Quote q = new Quote(Name = 'Test Quote Other');
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'INVALID_CROSS_REFERENCE_KEY: bad id', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals('OTHER', res[0].category);
        System.assertEquals('INVALID_CROSS_REFERENCE_KEY: bad id', res[0].friendlyMessage);
    }

    @isTest
    static void cleanup_deletesDraftOrderAndReportsTrue() {
        Account acc = new Account(Name = 'Test Acct Q2O');
        insert acc;
        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today());
        insert ord;
        Quote q = new Quote(Name = 'Test Quote Cleanup');
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Some non-limit error', ord.Id);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals(true, res[0].orphanCleaned);
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Id = :ord.Id]);
    }

    @isTest
    static void cleanup_nullOrderIsNoOp() {
        Quote q = new Quote(Name = 'Test Quote No Order');
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Some non-limit error', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals(false, res[0].orphanCleaned);
    }

    @isTest
    static void cleanup_governorLimitPathSkipsCleanup() {
        Account acc = new Account(Name = 'Test Acct Q2O Limit');
        insert acc;
        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today());
        insert ord;
        Q2OConversionFaultHandler.Request req = buildRequest('0Q0000000000000AAA', 'Too many SOQL queries: 101', ord.Id);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals('GOVERNOR_LIMIT', res[0].category);
        System.assertEquals(false, res[0].orphanCleaned);
        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Id = :ord.Id]);
    }

    @isTest
    static void handler_neverThrows_onBadOrderId() {
        Quote q = new Quote(Name = 'Test Quote Bad Order');
        insert q;
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Some non-limit error', '801000000000000AAA');
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        System.assertEquals(false, res[0].orphanCleaned);
        System.assert(String.isNotBlank(res[0].friendlyMessage));
    }

    @isTest
    static void handler_catchesNonLimitException_returnsOther() {
        Quote q = new Quote(Name = 'Test Quote Catch NonLimit');
        insert q;
        Q2OConversionFaultHandler.simulateThrowMessageForTest = 'boom non-limit';
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Some non-limit error', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        Q2OConversionFaultHandler.simulateThrowMessageForTest = null;
        System.assertEquals('OTHER', res[0].category);
        System.assert(String.isNotBlank(res[0].friendlyMessage));
    }

    @isTest
    static void handler_catchesLimitExceptionMidCleanup_reclassifiesToGovernorLimit() {
        Quote q = new Quote(Name = 'Test Quote Catch Limit');
        insert q;
        Q2OConversionFaultHandler.simulateThrowMessageForTest = 'Too many SOQL queries: 101';
        // Incoming fault is NOT a governor-limit message; the limit surfaces only mid-cleanup.
        Q2OConversionFaultHandler.Request req = buildRequest(q.Id, 'Select an active Legal Entity.', null);
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>{ req });
        Test.stopTest();
        Q2OConversionFaultHandler.simulateThrowMessageForTest = null;
        System.assertEquals('GOVERNOR_LIMIT', res[0].category);
        System.assert(String.isNotBlank(res[0].friendlyMessage));
    }

    @isTest
    static void handle_emptyList_returnsEmptyNonNull() {
        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res =
            Q2OConversionFaultHandler.handle(new List<Q2OConversionFaultHandler.Request>());
        Test.stopTest();
        System.assertNotEquals(null, res);
        System.assertEquals(0, res.size());
    }

    @isTest
    static void handle_mixedBatch_eachIndependent() {
        // (a) active-LE legal-entity fault
        LegalEntity le = new LegalEntity(Name = 'Mixed Active LE', Status = 'Active');
        insert le;
        Quote qLe = new Quote(Name = 'Mixed Quote LE', LegalEntityId = le.Id);
        insert qLe;

        // (c) non-limit fault with a Draft order to clean up
        Account acc = new Account(Name = 'Mixed Acct');
        insert acc;
        Order ord = new Order(AccountId = acc.Id, Status = 'Draft', EffectiveDate = Date.today());
        insert ord;
        Quote qOther = new Quote(Name = 'Mixed Quote Other');
        insert qOther;

        // (b) governor-limit fault (no quote/order touch on this branch)
        Q2OConversionFaultHandler.Request reqLimit =
            buildRequest('0Q0000000000000AAA', 'Too many SOQL queries: 101', null);

        List<Q2OConversionFaultHandler.Request> reqs = new List<Q2OConversionFaultHandler.Request>{
            buildRequest(qLe.Id, 'Select an active Legal Entity.', null),
            reqLimit,
            buildRequest(qOther.Id, 'INVALID_CROSS_REFERENCE_KEY: bad id', ord.Id)
        };

        Test.startTest();
        List<Q2OConversionFaultHandler.Response> res = Q2OConversionFaultHandler.handle(reqs);
        Test.stopTest();

        System.assertEquals(3, res.size());
        System.assertEquals('MISLEADING_LEGAL_ENTITY', res[0].category);
        System.assertEquals('GOVERNOR_LIMIT', res[1].category);
        System.assertEquals('OTHER', res[2].category);
        // Draft order cleaned only for (c).
        System.assertEquals(false, res[0].orphanCleaned);
        System.assertEquals(false, res[1].orphanCleaned);
        System.assertEquals(true, res[2].orphanCleaned);
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Id = :ord.Id]);
    }
}