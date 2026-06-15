#!/usr/bin/env python3
"""Round 2: cover appendStamped edge continues (523/528) and the MyCAP
itemSubscriptionTerm clause + prepaid-lookup section (1057, 1107-1131)."""

T = "Data/sc-maint/sc3346_fix/colauplift_testfix/deploy/classes/COLAUpliftTest.cls"

NEW = r'''
    @isTest
    static void testPrehook_AppendStamped_EdgeContinues() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test COLA Account' LIMIT 1];
        Opportunity opp = new Opportunity(Name = 'COLA Edge Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPb = Test.getStandardPricebookId();
        Quote q = new Quote(Name = 'COLA Edge Quote', OpportunityId = opp.Id,
            Pricebook2Id = stdPb, Quote_Type__c = 'Renewal');
        insert q;
        Product2 prod = new Product2(Name = 'COLA Edge Product', ProductCode = 'COLA-EDGE', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPb, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;
        // B: matches the SOQL but gets no wrapper  -> missing-wrapper continue (523)
        QuoteLineItem qB = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1,
            UnitPrice = 100, Fortra_Product_Type__c = 'Renewal Maintenance');
        // C: matches the SOQL, has a wrapper, but preColaNet<=0 -> null colaNet continue (528)
        QuoteLineItem qC = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1,
            UnitPrice = 100, Fortra_Product_Type__c = 'Renewal Maintenance');
        insert new List<QuoteLineItem>{ qB, qC };
        update new List<QuoteLineItem>{
            new QuoteLineItem(Id = qB.Id, Base_Price__c = 100),
            new QuoteLineItem(Id = qC.Id, Base_Price__c = 5, Prior_Partner_Discount__c = 10) // 5-10 <= 0
        };

        Map<Id, Map<String, Object>> wrappers = new Map<Id, Map<String, Object>>{
            qC.Id => prehookItemNode(new Map<String, Object>(),
                new List<Object>{ '0Q0ROOT', q.Id, qC.Id }) };  // note: qB intentionally absent

        Test.startTest();
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();
        Integer processed = prehook.appendStampedRenewalMaintenanceUpdates(
            new Context.IndustriesContext(), 'fake-ctx', new Set<Id>{ qB.Id, qC.Id }, wrappers);
        Test.stopTest();

        System.assertEquals(0, processed,
            'B has no wrapper (skip) and C has non-positive preColaNet (skip) -> nothing built');
    }

    // SeeAllData so the PS_Service_Type AttributeDefinition / Prepaid picklist
    // (org config, uninsertable in tests) resolve, covering the MyCAP prepaid lookup.
    @isTest(SeeAllData=true)
    static void testPrehook_ProcessMyCAPEligibility_SubTermAndPrepaidLookup() {
        MyCAP_Rules__mdt rule = MyCAP_Rules__mdt.getInstance('Global');
        if (rule == null) return;
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = new Opportunity(Name = 'MyCAP SubTerm Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPb = Test.getStandardPricebookId();
        Quote q = new Quote(Name = 'MyCAP SubTerm Quote', OpportunityId = opp.Id, Mycap__c = false, Pricebook2Id = stdPb);
        insert q;
        Product2 prod = new Product2(Name = 'MyCAP SubTerm Product', ProductCode = 'MYCAP-SUBTERM', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPb, Product2Id = prod.Id, UnitPrice = 1000, IsActive = true);
        insert pbe;
        QuoteAction qa = new QuoteAction(QuoteId = q.Id, Type = 'Renew');
        insert qa;
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id,
            Quantity = 1, UnitPrice = 1000, QuoteActionId = qa.Id);
        insert qli;

        // Multi-year via ItemSubscriptionTerm (not PricingTermCount) -> exercises the
        // itemSubscriptionTerm clause; below-minimum COLA% -> flag-true path.
        List<Object> items = new List<Object>{
            prehookItemNode(new Map<String, Object>{
                'SalesTransactionActionType' => 'Renew',
                'PricingTermUnit' => 'Annual',
                'ItemSubscriptionTerm' => 3,
                'COLA_Uplift_Percent__c' => 1,
                'UnitPrice' => 1000
            }, new List<Object>{ '0Q0ROOT', q.Id, qli.Id }) };

        Test.startTest();
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();
        Integer evaluated = prehook.processMyCAPEligibility(items, rule);
        Test.stopTest();

        System.assert(evaluated >= 1, 'one multi-year (sub-term) renewal quote evaluated');
    }
'''

with open(T) as f:
    s = f.read().rstrip("\n")
idx = s.rfind("}")
out = s[:idx] + NEW + "\n}\n"
with open(T, "w") as f:
    f.write(out)

chk = open(T).read()
print("brace balance:", chk.count("{") - chk.count("}"))
for n in ("testPrehook_AppendStamped_EdgeContinues",
          "testPrehook_ProcessMyCAPEligibility_SubTermAndPrepaidLookup"):
    print(("OK " if n in chk else "MISS"), n)
print("lines:", chk.count(chr(10)) + 1)
