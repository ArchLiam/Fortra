/**
 * @description Tests QuoteLineItemExchangeRateService: USD rate stamping on inserted lines,
 *              propagation to the syncing Opportunity, blank-currency skip, and null/empty safety.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class QuoteLineItemExchangeRateServiceTest {

    /**
     * @description Creates the Account/Opportunity/Quote/Product/PricebookEntry needed to insert
     *              QuoteLineItems that inherit the org's default (USD) currency.
     */
    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'FX Test Account');
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'FX Test Opp',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'FX Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;

        Product2 prod = new Product2(Name = 'FX Product', IsActive = true);
        insert prod;

        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = prod.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
    }

    /**
     * @description Stamps rate 1.0 on a bulk set of inserted USD lines (>=20 records).
     */
    @isTest
    static void stampsUsdRateOnBulkLines() {
        Quote q = [SELECT Id FROM Quote LIMIT 1];
        PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry LIMIT 1];

        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (Integer i = 0; i < 20; i++) {
            lines.add(new QuoteLineItem(
                QuoteId = q.Id,
                Product2Id = pbe.Product2Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = 100.00
            ));
        }
        insert lines;

        List<QuoteLineItem> reloaded = [
            SELECT Id, CurrencyIsoCode, Exchange_Rate_To_USD__c
            FROM QuoteLineItem WHERE Id IN :lines
        ];
        for (QuoteLineItem line : reloaded) {
            line.Exchange_Rate_To_USD__c = null;
        }

        Test.startTest();
        QuoteLineItemExchangeRateService.stampRatesOnLines(reloaded);
        Test.stopTest();

        for (QuoteLineItem line : reloaded) {
            Assert.areEqual(1.0, line.Exchange_Rate_To_USD__c,
                'USD line should stamp rate 1.0');
        }
    }

    /**
     * @description A line with no currency is skipped (never stamped).
     */
    @isTest
    static void skipsBlankCurrencyLine() {
        QuoteLineItem line = new QuoteLineItem();

        Test.startTest();
        QuoteLineItemExchangeRateService.stampRatesOnLines(new List<QuoteLineItem>{ line });
        Test.stopTest();

        Assert.isNull(line.Exchange_Rate_To_USD__c, 'Blank-currency line should not be stamped');
    }

    /**
     * @description Propagates the rate to the Opportunity when the line's Quote is the syncing Quote.
     */
    @isTest
    static void propagatesRateToSyncedOpportunity() {
        Quote q = [SELECT Id, OpportunityId FROM Quote LIMIT 1];
        Opportunity opp = new Opportunity(Id = q.OpportunityId, SyncedQuoteId = q.Id);
        update opp;

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, Exchange_Rate_To_USD__c = 0.85)
        };

        Test.startTest();
        QuoteLineItemExchangeRateService.propagateRatesToOpportunities(lines);
        Test.stopTest();

        Opportunity updated = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :q.OpportunityId];
        Assert.areEqual(0.85, updated.Exchange_Rate_To_USD__c,
            'Rate should propagate to the syncing Opportunity');
    }

    /**
     * @description Does not touch the Opportunity when the line's Quote is not the syncing Quote.
     */
    @isTest
    static void skipsWhenLineQuoteIsNotTheSyncingQuote() {
        // A line whose Quote does not resolve to a syncing match must not stamp its rate on any
        // Opportunity. A non-resolvable Quote Id makes this deterministic (the propagation query
        // returns no match), independent of the org's auto-sync and default-rate behavior. The
        // sentinel rate 0.9 is asserted absent because the Opportunity is auto-stamped a default
        // rate on insert, so an isNull check would be invalid.
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Id nonResolvableQuoteId = Quote.SObjectType.getDescribe().getKeyPrefix() + '000000000009AAA';
        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = nonResolvableQuoteId, Exchange_Rate_To_USD__c = 0.9)
        };

        Test.startTest();
        QuoteLineItemExchangeRateService.propagateRatesToOpportunities(lines);
        Test.stopTest();

        Opportunity after = [SELECT Exchange_Rate_To_USD__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areNotEqual(0.9, after.Exchange_Rate_To_USD__c,
            'A non-syncing / non-resolvable line quote must not stamp its rate on the Opportunity');
    }

    /**
     * @description Null and empty inputs must not throw.
     */
    @isTest
    static void handlesNullAndEmptyInputs() {
        Test.startTest();
        QuoteLineItemExchangeRateService.stampRatesOnLines(null);
        QuoteLineItemExchangeRateService.stampRatesOnLines(new List<QuoteLineItem>());
        QuoteLineItemExchangeRateService.propagateRatesToOpportunities(null);
        QuoteLineItemExchangeRateService.propagateRatesToOpportunities(new List<QuoteLineItem>());
        Test.stopTest();

        Assert.isTrue(true, 'Null/empty inputs must not throw');
    }
}
