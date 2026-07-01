@IsTest
private class RenewalQuoteHeaderHandlerTest {

    private static Quote buildRenewalQuote(Id contractId) {
        return new Quote(
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL,
            ContractId = contractId
        );
    }

    private static Quote createSourceQuote() {
        Account account = new Account(Name = 'Renewal Header Source Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Renewal Header Source Opp',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote quote = new Quote(
            Name = 'Renewal Header Source Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = 'New',
            Deal_Type__c = 'Fortra Originated',
            Net_Terms__c = 'Net_30',
            Language__c = 'English',
            BillingStreet = '11095 Viking Drive',
            BillingCity = 'Eden Prairie',
            BillingState = 'Minnesota',
            BillingPostalCode = '55344',
            BillingCountry = 'United States'
        );
        insert quote;

        insert new Quote_Checklist_Item__c(
            Quote__c = quote.Id,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );

        return quote;
    }

    private static void insertRenewalChecklist(Id quoteId) {
        insert new Quote_Checklist_Item__c(
            Quote__c = quoteId,
            Item_Name__c = 'Checklist Item',
            Sort_Order__c = 1,
            Is_Checked__c = true
        );
    }

    @IsTest
    static void applyRenewalQuoteHeaders_noOpWhenNullOrEmpty() {
        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(null);
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>());
        Test.stopTest();

        System.assert(true, 'Null and empty inputs should return without error');
    }

    @IsTest
    static void applyRenewalQuoteHeaders_skipsNonRenewalQuotes() {
        Quote quote = new Quote(
            Quote_Type__c = 'New',
            ContractId = createContract().Id
        );

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(null, quote.Renewal_Contract__c);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_setsRenewalContractFromContractId() {
        Contract contract = createContract();
        Quote quote = buildRenewalQuote(contract.Id);
        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>();

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(contract.Id, quote.Renewal_Contract__c);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_copiesBlankFieldsFromSourceQuote() {
        Quote sourceQuote = createSourceQuote();
        Contract contract = createContract();
        Quote quote = buildRenewalQuote(contract.Id);

        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>{
            contract.Id => sourceQuote.Id
        };

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(contract.Id, quote.Renewal_Contract__c);
        System.assertEquals(sourceQuote.OpportunityId, quote.OpportunityId);
        System.assertEquals('Fortra Originated', quote.Deal_Type__c);
        System.assertEquals('Net_30', quote.Net_Terms__c);
        System.assertEquals('11095 Viking Drive', quote.BillingStreet);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_doesNotOverwriteExistingValues() {
        Quote sourceQuote = createSourceQuote();
        Contract contract = createContract();
        Quote quote = buildRenewalQuote(contract.Id);
        quote.Deal_Type__c = 'Channel Originated';

        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>{
            contract.Id => sourceQuote.Id
        };

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals('Channel Originated', quote.Deal_Type__c);
        System.assertEquals(sourceQuote.OpportunityId, quote.OpportunityId);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_resolvesSourceQuoteFromOrder() {
        Quote sourceQuote = createSourceQuote();
        Contract contract = createContract();

        Date orderStartDate = Date.today().addMonths(-6);
        insert new Order(
            AccountId = contract.AccountId,
            ContractId = contract.Id,
            Status = 'Draft',
            EffectiveDate = orderStartDate,
            EndDate = orderStartDate.addMonths(12),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = sourceQuote.Id
        );

        Quote quote = buildRenewalQuote(contract.Id);
        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = null;

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(contract.Id, quote.Renewal_Contract__c);
        System.assertEquals(sourceQuote.OpportunityId, quote.OpportunityId);
        System.assertEquals('Fortra Originated', quote.Deal_Type__c);
    }

    @IsTest
    static void stampHeaderFields_isolatedCopyLogic() {
        Quote target = new Quote();
        Quote source = new Quote(
            OpportunityId = createSourceQuote().OpportunityId,
            Deal_Type__c = 'Fortra Originated',
            Partner_Pricing_Model__c = 'Discount',
            BillingStreet = '11095 Viking Drive',
            BillingCity = 'Eden Prairie',
            QuoteToStreet = '11095 Viking Drive'
        );

        RenewalQuoteHeaderHandler.stampHeaderFields(target, source);

        System.assertEquals(source.OpportunityId, target.OpportunityId);
        System.assertEquals(source.Partner_Pricing_Model__c, target.Partner_Pricing_Model__c);
        System.assertEquals(source.BillingCity, target.BillingCity);
        System.assertEquals(source.QuoteToStreet, target.QuoteToStreet);
    }

    @IsTest
    static void isRenewalQuoteContext_acceptsRenewalTypeWithoutOriginalAction() {
        Quote quote = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);
        System.assertEquals(true, RenewalQuoteHeaderHandler.isRenewalQuoteContext(quote));
    }

    @IsTest
    static void resolveContractId_prefersRenewalContractField() {
        Contract renewalContract = createContract();
        Contract platformContract = createContract();
        Quote quote = new Quote(
            Renewal_Contract__c = renewalContract.Id,
            ContractId = platformContract.Id
        );

        System.assertEquals(renewalContract.Id, RenewalQuoteHeaderHandler.resolveContractId(quote));
    }

    @IsTest
    static void quoteTrigger_stampsHeaderOnRenewalInsert() {
        Quote sourceQuote = createSourceQuote();
        Contract contract = createContract();

        Date orderStartDate = Date.today().addMonths(-6);
        insert new Order(
            AccountId = contract.AccountId,
            ContractId = contract.Id,
            Status = 'Draft',
            EffectiveDate = orderStartDate,
            EndDate = orderStartDate.addMonths(12),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = sourceQuote.Id
        );

        Quote renewalQuote = new Quote(
            Name = 'Renewal via trigger',
            OpportunityId = sourceQuote.OpportunityId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL,
            ContractId = contract.Id
        );

        Test.startTest();
        insert renewalQuote;
        Test.stopTest();

        renewalQuote = [
            SELECT Renewal_Contract__c, Deal_Type__c, BillingStreet
            FROM Quote
            WHERE Id = :renewalQuote.Id
        ];
        System.assertEquals(contract.Id, renewalQuote.Renewal_Contract__c);
        System.assertEquals('Fortra Originated', renewalQuote.Deal_Type__c);
        System.assertEquals('11095 Viking Drive', renewalQuote.BillingStreet);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_runsForOriginalActionRenewContext() {
        Contract contract = createContract();
        Quote quote = (Quote) JSON.deserialize(
            '{"OriginalActionType":"Renew","ContractId":"' + contract.Id + '"}',
            Quote.class
        );
        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>();

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(contract.Id, quote.Renewal_Contract__c);
    }

    @IsTest
    static void resolveContractId_returnsNullForNullQuote() {
        System.assertEquals(
            null,
            RenewalQuoteHeaderHandler.resolveContractId(null),
            'Null quote should resolve to a null contract Id'
        );
    }

    @IsTest
    static void resolveContractId_fallsBackToContractId() {
        Contract platformContract = createContract();
        Quote quote = new Quote(ContractId = platformContract.Id);

        System.assertEquals(
            platformContract.Id,
            RenewalQuoteHeaderHandler.resolveContractId(quote),
            'With no Renewal_Contract__c, resolveContractId should fall back to ContractId'
        );
    }

    @IsTest
    static void isRenewalQuoteContext_falseForNullAndNonRenewal() {
        System.assertEquals(
            false,
            RenewalQuoteHeaderHandler.isRenewalQuoteContext(null),
            'Null quote is not a renewal context'
        );
        System.assertEquals(
            false,
            RenewalQuoteHeaderHandler.isRenewalQuoteContext(new Quote(Quote_Type__c = 'New')),
            'A New quote is not a renewal context'
        );
    }

    @IsTest
    static void loadSourceQuotesByContractId_returnsEmptyForNullOrEmpty() {
        Test.startTest();
        Map<Id, Quote> fromNull = RenewalQuoteHeaderHandler.loadSourceQuotesByContractId(null);
        Map<Id, Quote> fromEmpty = RenewalQuoteHeaderHandler.loadSourceQuotesByContractId(new Set<Id>());
        Test.stopTest();

        System.assertEquals(true, fromNull.isEmpty(), 'Null contract Ids should yield an empty map');
        System.assertEquals(true, fromEmpty.isEmpty(), 'Empty contract Ids should yield an empty map');
    }

    @IsTest
    static void loadSourceQuotesByContractId_returnsEmptyWhenNoSourceResolved() {
        Contract contract = createContract();
        // testMap present but without an entry for this contract -> no source quote ids
        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>();

        Test.startTest();
        Map<Id, Quote> result = RenewalQuoteHeaderHandler.loadSourceQuotesByContractId(
            new Set<Id>{ contract.Id }
        );
        Test.stopTest();

        System.assertEquals(true, result.isEmpty(), 'No resolvable source quote should yield an empty map');
    }

    @IsTest
    static void stampHeaderFields_noOpForNullTargetOrSource() {
        Quote populated = new Quote(Deal_Type__c = 'Fortra Originated');

        Test.startTest();
        // null target -> early return, no exception
        RenewalQuoteHeaderHandler.stampHeaderFields(null, populated);
        // null source -> early return, target untouched
        RenewalQuoteHeaderHandler.stampHeaderFields(populated, null);
        Test.stopTest();

        System.assertEquals(
            'Fortra Originated',
            populated.Deal_Type__c,
            'A null source should leave the target unchanged'
        );
    }

    @IsTest
    static void applyRenewalQuoteHeaders_resolvesSourceQuoteFromContractSourceQuoteId() {
        Quote sourceQuote = createSourceQuote();
        Contract contract = createContract();
        contract.SourceQuoteId = sourceQuote.Id;
        update contract;

        Quote quote = buildRenewalQuote(contract.Id);
        // Force the real (non-test-map) resolution path so the Contract.SourceQuoteId query runs.
        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = null;

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(contract.Id, quote.Renewal_Contract__c);
        System.assertEquals(
            sourceQuote.OpportunityId,
            quote.OpportunityId,
            'Header should be stamped from the Contract.SourceQuoteId source quote'
        );
        System.assertEquals('Fortra Originated', quote.Deal_Type__c);
    }

    @IsTest
    static void applyRenewalQuoteHeaders_skipsRenewalQuoteWithoutContract() {
        // Renewal context but no Renewal_Contract__c and no ContractId -> contractId resolves null -> continue
        Quote quote = new Quote(Quote_Type__c = QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL);

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(new List<Quote>{ quote });
        Test.stopTest();

        System.assertEquals(
            null,
            quote.Renewal_Contract__c,
            'A renewal quote with no resolvable contract should be skipped, leaving Renewal_Contract__c null'
        );
    }

    @IsTest
    static void applyRenewalQuoteHeaders_bulkStampsMultipleRenewalQuotes() {
        Quote sourceA = createSourceQuote();
        Quote sourceB = createSourceQuote();
        Contract contractA = createContract();
        Contract contractB = createContract();

        Quote renewalA = buildRenewalQuote(contractA.Id);
        Quote renewalB = buildRenewalQuote(contractB.Id);

        RenewalQuoteHeaderHandler.testSourceQuoteIdByContractId = new Map<Id, Id>{
            contractA.Id => sourceA.Id,
            contractB.Id => sourceB.Id
        };

        Test.startTest();
        RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders(
            new List<Quote>{ renewalA, renewalB }
        );
        Test.stopTest();

        System.assertEquals(sourceA.OpportunityId, renewalA.OpportunityId, 'Quote A should stamp from source A');
        System.assertEquals(sourceB.OpportunityId, renewalB.OpportunityId, 'Quote B should stamp from source B');
        System.assertEquals(contractA.Id, renewalA.Renewal_Contract__c);
        System.assertEquals(contractB.Id, renewalB.Renewal_Contract__c);
    }

    private static Contract createContract() {
        Account account = new Account(Name = 'Renewal Header Contract Account ' + Crypto.getRandomInteger());
        insert account;

        Contract contract = new Contract(
            AccountId = account.Id,
            Status = 'Draft',
            StartDate = Date.today().addYears(-1),
            ContractTerm = 36
        );
        insert contract;
        return contract;
    }
}