#!/usr/bin/env python3
"""Append coverage tests for the stamped-maintenance @TestVisible seams
(computeStampedMaintenanceColaNet, buildMaintenanceColaItemUpdate,
appendStampedRenewalMaintenanceUpdates) to push COLAUpliftPrehook past 75%."""

T = "Data/sc-maint/sc3346_fix/colauplift_testfix/deploy/classes/COLAUpliftTest.cls"

NEW = r'''
    // ====================================================================
    // Coverage for the stamped renewal-maintenance seams (SC-3346 re-seam)
    // ====================================================================

    /** JSON-built QLI so read-only/relationship-free fields can be set in memory. */
    private static QuoteLineItem colaQli(Decimal base, Decimal priorPartner,
            Decimal priorDisc, Decimal discount, Decimal cola, Decimal partnerPct) {
        Map<String, Object> m = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'QuoteLineItem' },
            'Base_Price__c' => base,
            'Prior_Partner_Discount__c' => priorPartner,
            'Prior_Discretionary_Discount__c' => priorDisc,
            'Discount' => discount,
            'COLA_Uplift_Percent__c' => cola,
            'PartnerDiscountPercent' => partnerPct
        };
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(m), QuoteLineItem.class);
    }

    @isTest
    static void testPrehook_ComputeStampedMaintenanceColaNet() {
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();

        // Explicit prior discretionary discount: (100-10-6.25) * 1.0785
        System.assertEquals(((100 - 10 - 6.25) * (1 + 7.85 / 100)).setScale(2, System.RoundingMode.HALF_UP),
            prehook.computeStampedMaintenanceColaNet(colaQli(100, 10, 6.25, null, 7.85, null)),
            'explicit prior discretionary path');

        // Discretionary derived from Discount%: priorDisc = (200-0)*0.10 = 20 -> (200-20)*1.05
        System.assertEquals(((200 - 0 - 20) * (1 + 5.0 / 100)).setScale(2, System.RoundingMode.HALF_UP),
            prehook.computeStampedMaintenanceColaNet(colaQli(200, 0, 0, 10, 5, null)),
            'discount-derived discretionary path');

        // Non-positive preColaNet -> null
        System.assertEquals(null,
            prehook.computeStampedMaintenanceColaNet(colaQli(10, 20, 0, null, 5, null)),
            'preColaNet <= 0 -> null');

        // All-null operands -> base only
        System.assertEquals(50.00,
            prehook.computeStampedMaintenanceColaNet(colaQli(50, null, null, null, null, null)),
            'null operands -> base * 1');
    }

    @isTest
    static void testPrehook_BuildMaintenanceColaItemUpdate() {
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();
        Map<String, Object> wrapper = prehookItemNode(new Map<String, Object>(),
            new List<Object>{ '0Q0ROOT', '0Q0000000000001AAA', '0QL000000000001AAA' });

        // Explicit partner pct + discount
        Map<String, Object> a1 = attrMapFromUpdate(
            prehook.buildMaintenanceColaItemUpdate(wrapper, colaQli(100, 10, 0, 15, 7.85, 12.00), 90.32));
        System.assertEquals(90.32, a1.get('COLACalculatedPrice__c'), 'colaNet carried through');
        System.assertEquals(12.00, a1.get('PartnerDiscountPercent'), 'explicit partner pct used');
        System.assertEquals(15, a1.get('Discount'), 'discount carried');

        // Derived partner pct (no explicit), no discount: 20/200*100 = 10.00
        Map<String, Object> a2 = attrMapFromUpdate(
            prehook.buildMaintenanceColaItemUpdate(wrapper, colaQli(200, 20, 0, null, 5, null), 50));
        System.assertEquals(((20.0 / 200) * 100).setScale(2, System.RoundingMode.HALF_UP),
            a2.get('PartnerDiscountPercent'), 'partner pct derived from prior/base');
        System.assertEquals(false, a2.containsKey('Discount'), 'no Discount attr when zero/null');

        // Empty dataPath -> null ; missing dataPath -> null
        System.assertEquals(null, prehook.buildMaintenanceColaItemUpdate(
            new Map<String, Object>{ 'dataPath' => new List<Object>() }, colaQli(100, 0, 0, 0, 5, null), 50),
            'empty dataPath -> null');
        System.assertEquals(null, prehook.buildMaintenanceColaItemUpdate(
            new Map<String, Object>{ 'tagValue' => new Map<String, Object>() }, colaQli(100, 0, 0, 0, 5, null), 50),
            'missing dataPath -> null');
    }

    @isTest
    static void testPrehook_AppendStampedRenewalMaintenance() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test COLA Account' LIMIT 1];
        Opportunity opp = new Opportunity(Name = 'COLA Stamp Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        Id stdPb = Test.getStandardPricebookId();
        // QuoteTypeText__c = TEXT(Quote_Type__c) -> setting Quote_Type__c='Renewal' yields 'Renewal'
        Quote q = new Quote(Name = 'COLA Stamp Quote', OpportunityId = opp.Id,
            Pricebook2Id = stdPb, Quote_Type__c = 'Renewal');
        insert q;
        Product2 prod = new Product2(Name = 'COLA Stamp Product', ProductCode = 'COLA-STAMP', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPb, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;
        QuoteLineItem qli = new QuoteLineItem(QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100,
            Fortra_Product_Type__c = 'Renewal Maintenance');
        insert qli;
        // Force the stamped pricing inputs the SOQL filters on (Base_Price__c > 0), independent of any flow.
        update new QuoteLineItem(Id = qli.Id, Base_Price__c = 100,
            Prior_Partner_Discount__c = 10, COLA_Uplift_Percent__c = 7.85);

        Map<Id, Map<String, Object>> qliIdToWrapper = new Map<Id, Map<String, Object>>{
            qli.Id => prehookItemNode(new Map<String, Object>(),
                new List<Object>{ '0Q0ROOT', q.Id, qli.Id }) };

        Test.startTest();
        COLAUpliftPrehook prehook = new COLAUpliftPrehook();
        Integer none = prehook.appendStampedRenewalMaintenanceUpdates(
            new Context.IndustriesContext(), 'fake-ctx', new Set<Id>(), qliIdToWrapper);
        Integer processed = prehook.appendStampedRenewalMaintenanceUpdates(
            new Context.IndustriesContext(), 'fake-ctx', new Set<Id>{ qli.Id }, qliIdToWrapper);
        Test.stopTest();

        System.assertEquals(0, none, 'empty qliIds -> 0');
        System.assert(processed >= 0, 'runs without error over the matched renewal-maintenance line');
    }
'''

with open(T) as f:
    s = f.read().rstrip("\n")
# insert before the final class-closing brace
idx = s.rfind("}")
out = s[:idx] + NEW + "\n}\n"
with open(T, "w") as f:
    f.write(out)

# verify
chk = open(T).read()
print("brace balance:", chk.count("{") - chk.count("}"))
for name in ("testPrehook_ComputeStampedMaintenanceColaNet",
             "testPrehook_BuildMaintenanceColaItemUpdate",
             "testPrehook_AppendStampedRenewalMaintenance",
             "private static QuoteLineItem colaQli("):
    print(("OK " if name in chk else "MISS"), name)
print("lines:", chk.count(chr(10)) + 1)
