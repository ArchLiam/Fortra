/**
 * @description Dedicated coverage class for COLAUpliftPrehook seams that depend on
 *              org config visible only under SeeAllData=true (the MyCAP PS_Service_Type
 *              AttributeDefinition / Prepaid picklist lookup) plus the
 *              itemSubscriptionTerm multi-year clause. Kept separate because the main
 *              COLAUpliftTest has a @testSetup, which forbids SeeAllData methods.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest(SeeAllData=true)
private class COLAUpliftPrehookCovTest {

    /**
     * @description Verifies that COLAUpliftPrehook.processMyCAPEligibility evaluates a
     *              multi-year renewal (driven by ItemSubscriptionTerm) with a
     *              below-minimum COLA percent, exercising the MyCAP sub-term and Prepaid
     *              picklist lookup seams that require SeeAllData=true org config.
     */
    @isTest
    static void testMyCAP_SubTerm_And_PrepaidLookup() {
        MyCAP_Rules__mdt rule = MyCAP_Rules__mdt.getInstance('Global');
        if (rule == null) return;

        Account acct = new Account(Name = 'COLA Cov Account');
        insert acct;
        Opportunity opp = new Opportunity(Name = 'COLA Cov Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPb = Test.getStandardPricebookId();
        Quote q = new Quote(Name = 'COLA Cov Quote', OpportunityId = opp.Id, Mycap__c = false, Pricebook2Id = stdPb);
        insert q;
        Product2 prod = new Product2(Name = 'COLA Cov Product', ProductCode = 'COLA-COV', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPb, Product2Id = prod.Id, UnitPrice = 1000, IsActive = true);
        insert pbe;
        QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Renew');
        insert qa;
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Quantity = 1, UnitPrice = 1000, QuoteActionId = qa.Id);
        insert qli;

        // Build the parsed SalesTransactionItem shape the prehook consumes:
        // a multi-year renewal (via ItemSubscriptionTerm) with below-minimum COLA%.
        Map<String, Object> raw = new Map<String, Object>{
            'SalesTransactionActionType' => 'Renew',
            'PricingTermUnit' => 'Annual',
            'ItemSubscriptionTerm' => 3,
            'COLA_Uplift_Percent__c' => 1,
            'UnitPrice' => 1000 };
        Map<String, Object> tv = new Map<String, Object>();
        for (String k : raw.keySet()) {
            tv.put(k, new Map<String, Object>{ 'tagValue' => raw.get(k) });
        }
        List<Object> items = new List<Object>{
            new Map<String, Object>{ 'tagValue' => tv,
                'dataPath' => new List<Object>{ '0Q0ROOT', q.Id, qli.Id } } };

        Test.startTest();
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();
        Integer evaluated = prehook.processMyCAPEligibility(items, rule);
        Test.stopTest();

        System.assert(evaluated >= 1, 'one multi-year (sub-term) renewal quote evaluated');
    }
}