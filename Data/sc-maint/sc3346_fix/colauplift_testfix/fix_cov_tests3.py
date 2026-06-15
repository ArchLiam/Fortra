#!/usr/bin/env python3
"""Round 3: remove the SeeAllData test from COLAUpliftTest (conflicts with its
@testSetup) and put it in a dedicated SeeAllData coverage class so the MyCAP
prepaid-lookup section (1107-1131) + itemSubscriptionTerm clause (1057) get covered."""
import re

BASE = "Data/sc-maint/sc3346_fix/colauplift_testfix/deploy/classes"
T = f"{BASE}/COLAUpliftTest.cls"

# --- 1. remove the SeeAllData method from COLAUpliftTest ---
s = open(T).read()
start_marker = "    // SeeAllData so the PS_Service_Type AttributeDefinition"
i = s.find(start_marker)
assert i != -1, "SeeAllData test marker not found"
# find the end: the method's closing brace at 4-space indent after the marker
j = s.find("\n    }\n", i)
assert j != -1, "method end not found"
s = s[:i].rstrip("\n") + "\n" + s[j + len("\n    }\n"):]
open(T, "w").write(s)
chk = open(T).read()
print("COLAUpliftTest brace balance:", chk.count("{") - chk.count("}"))
print("SeeAllData removed from COLAUpliftTest:", "SeeAllData" not in chk)
print("AppendStamped_EdgeContinues kept:", "testPrehook_AppendStamped_EdgeContinues" in chk)

# --- 2. new dedicated SeeAllData coverage class ---
COV = r'''/**
 * @description Dedicated coverage class for COLAUpliftPrehook seams that depend on
 *              org config visible only under SeeAllData=true (the MyCAP PS_Service_Type
 *              AttributeDefinition / Prepaid picklist lookup) plus the
 *              itemSubscriptionTerm multi-year clause. Kept separate because the main
 *              COLAUpliftTest has a @testSetup, which forbids SeeAllData methods.
 */
@isTest(SeeAllData=true)
private class COLAUpliftPrehookCovTest {

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
'''
open(f"{BASE}/COLAUpliftPrehookCovTest.cls", "w").write(COV)
open(f"{BASE}/COLAUpliftPrehookCovTest.cls-meta.xml", "w").write(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">\n'
    '    <apiVersion>65.0</apiVersion>\n    <status>Active</status>\n</ApexClass>\n')
print("new cov class brace balance:",
      open(f"{BASE}/COLAUpliftPrehookCovTest.cls").read().count("{") -
      open(f"{BASE}/COLAUpliftPrehookCovTest.cls").read().count("}"))
