@isTest
private class QuoteToOrderFieldMapperTest {

    private static final List<String> CHECKLIST_NAMES = new List<String>{
        'Quote Start/End Dates', 'Upsell/Addon Co-Termed', 'Currency', 'Legal Entity',
        'Total Amount', 'Confirm AE', 'Accurate Ship To/Bill To', 'Net Terms',
        'MYCAP', 'Billing Frequency', 'Fortra Quote Approvals',
        'Quote/License/Invoice Contacts', 'Distributor/Reseller',
        'Customer Order Acceptance', 'Hold Invoice?', 'Payment Portal'
    };

    @TestSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Test Mapper Account');
        insert acct;

        Product2 prod = new Product2(
            Name = 'Test Power Product',
            ProductCode = 'TEST-MAP-001',
            IsActive = true,
            Solution_Group__c = 'Power',
            Power_Split_Type__c = 'Order Line Only',
            QuantityUnitOfMeasure = 'Each'
        );
        insert prod;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = prod.Id,
            UnitPrice = 1000.00,
            IsActive = true
        );
        insert pbe;

        Hardware__c hw = new Hardware__c(
            Account__c = acct.Id,
            Serial_Number__c = 'SN-MAP-TEST-001'
        );
        insert hw;

        Partition__c part = new Partition__c(
            Hardware__c = hw.Id,
            Partition_Name__c = 'Mapper Test Partition',
            Partition_Number__c = '1',
            Partition_ID__c = 'MAP-TEST-PART-001',
            Status__c = 'Active'
        );
        insert part;
    }

    private static void createChecklistItems(Id quoteId) {
        List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
        for (Integer i = 0; i < CHECKLIST_NAMES.size(); i++) {
            items.add(new Quote_Checklist_Item__c(
                Quote__c = quoteId,
                Item_Name__c = CHECKLIST_NAMES[i],
                Is_Checked__c = true,
                Sort_Order__c = i + 1
            ));
        }
        insert items;
    }

    // Builds a Quote (+ checklist) linked to an Opportunity on the given account.
    private static Quote buildQuote(Id acctId, String name) {
        Opportunity opp = new Opportunity(
            AccountId = acctId,
            Name = name + ' Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = name,
            OpportunityId = opp.Id,
            QuoteAccountId = acctId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert q;
        createChecklistItems(q.Id);
        return q;
    }

    private static Places__c buildPlace(Id accountId, String streetSuffix) {
        return new Places__c(
            Account__c = accountId,
            Address__Street__s = streetSuffix + ' Test Street',
            Address__City__s = streetSuffix + 'ville',
            Address__PostalCode__s = '0000' + streetSuffix
        );
    }

    // ---------------------------------------------------------------------
    // Existing OrderItem (line-level) mapping behaviour
    // ---------------------------------------------------------------------

    @isTest
    static void testMapsFieldsFromQLIToOrderItem() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'TEST-MAP-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        Hardware__c hw = [SELECT Id FROM Hardware__c LIMIT 1];
        Partition__c part = [SELECT Id FROM Partition__c LIMIT 1];
        Id stdPBId = Test.getStandardPricebookId();

        Quote q = buildQuote(acct.Id, 'Test Mapper Quote');

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 3,
            UnitPrice = 1000.00,
            Hardware__c = hw.Id,
            Partition_Reference__c = part.Id
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 3,
            UnitPrice = 1000.00,
            QuoteLineItemId = qli.Id
        );
        insert oi;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Mapping should succeed');
        System.assertEquals(1, results[0].itemsMapped, 'Should map 1 OrderItem');

        OrderItem postPatch = [SELECT Hardware__c, Partition_Record__c FROM OrderItem WHERE Id = :oi.Id];
        System.assertEquals(hw.Id, postPatch.Hardware__c, 'Hardware should be mapped from QLI');
        System.assertEquals(part.Id, postPatch.Partition_Record__c, 'Partition should be mapped from QLI');
    }

    @isTest
    static void testSkipsWhenNoQuoteLineItemId() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'TEST-MAP-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 1000.00
        );
        insert oi;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(0, results[0].itemsMapped, 'Should map 0 items when no QuoteLineItemId');
    }

    @isTest
    static void testNullOrderId() {
        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = null;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('required'), 'Should report Order ID required');
    }

    // ---------------------------------------------------------------------
    // New Order header Bill To / Ship To carryover
    // ---------------------------------------------------------------------

    @isTest
    static void testMapsHeaderBillShipFromQuotePlaces() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Test Mapper Account' LIMIT 1];

        Quote q = buildQuote(customer.Id, 'Header Quote');
        q = [SELECT Id, AccountId, QuoteAccountId FROM Quote WHERE Id = :q.Id];
        Id placeAccountId = q.QuoteAccountId != null ? q.QuoteAccountId : q.AccountId;

        Places__c billPlace = buildPlace(placeAccountId, 'Bill');
        Places__c shipPlace = buildPlace(placeAccountId, 'Ship');
        insert new List<Places__c>{ billPlace, shipPlace };

        q.Bill_To_Place__c = billPlace.Id;
        q.Ship_To_Place__c = shipPlace.Id;
        update q;

        Order ord = new Order(
            AccountId = customer.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Mapping should succeed');
        System.assertEquals(true, results[0].headerMapped, 'Header should be mapped');

        Order result = [
            SELECT Bill_To_Account__c, Ship_To_Account__c, Bill_To_Address__c,
                   Ship_To_Address__c, BillToContactId, ShipToContactId
            FROM Order WHERE Id = :ord.Id
        ];
        System.assertEquals(q.AccountId, result.Bill_To_Account__c,
            'Bill To Account must be derived from the bill-to place account');
        System.assertEquals(q.AccountId, result.Ship_To_Account__c,
            'Ship To Account must be the ship-to place account');
        System.assertNotEquals(result.Bill_To_Address__c, result.Ship_To_Address__c,
            'Different place records should map to distinct order addresses');
        System.assertEquals(billPlace.Id, result.Bill_To_Address__c, 'Bill To Address (Place)');
        System.assertEquals(shipPlace.Id, result.Ship_To_Address__c, 'Ship To Address (Place)');
    }

    @isTest
    static void testHeaderLeavesAccountNullWhenNoPlace() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Test Mapper Account' LIMIT 1];
        Quote q = buildQuote(customer.Id, 'No Place Quote'); // no Bill/Ship place set

        Order ord = new Order(
            AccountId = customer.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId(),
            QuoteId = q.Id
        );
        insert ord;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        Order result = [SELECT Bill_To_Account__c, Ship_To_Account__c FROM Order WHERE Id = :ord.Id];
        System.assertEquals(null, result.Bill_To_Account__c, 'No Bill_To_Place -> Bill To Account left null');
        System.assertEquals(null, result.Ship_To_Account__c, 'No Ship_To_Place -> Ship To Account left null');
    }

    @isTest
    static void testHeaderBulkMultipleOrdersStaysWithinSoqlBudget() {
        Account customer = [SELECT Id FROM Account WHERE Name = 'Test Mapper Account' LIMIT 1];

        List<QuoteToOrderFieldMapper.MapRequest> requests = new List<QuoteToOrderFieldMapper.MapRequest>();
        List<Id> orderIds = new List<Id>();
        for (Integer i = 0; i < 3; i++) {
            Quote q = buildQuote(customer.Id, 'Bulk Quote ' + i);

            Order ord = new Order(
                AccountId = customer.Id,
                Status = 'Draft',
                EffectiveDate = Date.today(),
                Pricebook2Id = Test.getStandardPricebookId(),
                QuoteId = q.Id
            );
            insert ord;
            orderIds.add(ord.Id);

            QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
            req.orderId = ord.Id;
            requests.add(req);
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        List<QuoteToOrderFieldMapper.MapResult> results = QuoteToOrderFieldMapper.mapFields(requests);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        // loadWorkBulk + header mapping per order; budget scales sub-linearly with order count.
        System.assert(soqlUsed <= 12, 'Expected <=12 SOQL for 3 header-only orders, got ' + soqlUsed);
        System.assert(dmlUsed <= 4, 'Expected <=4 DML for 3 header-only orders, got ' + dmlUsed);

        for (QuoteToOrderFieldMapper.MapResult r : results) {
            System.assertEquals(true, r.success, 'Each order should map successfully');
        }
    }

    @isTest
    static void testMapsRenewalCarryForwardFieldsFromQLIToOrderItem() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Product2 maintProd = new Product2(
            Name = 'Mapper Renewal Maint Product',
            ProductCode = 'MAP-RRM-CARRY',
            IsActive = true,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 0,
            IsActive = true
        );
        insert pbe;

        Opportunity opp = new Opportunity(
            AccountId = acct.Id,
            Name = 'Mapper Renewal Opp',
            StageName = 'Pre-Qualified',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Quote q = new Quote(
            Name = 'Mapper Renewal Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPBId,
            Quote_Type__c = 'Renewal'
        );
        insert q;
        createChecklistItems(q.Id);

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 60.64,
            Base_Price__c = 71,
            Prior_Partner_Discount__c = 8.52,
            Prior_Discretionary_Discount__c = 6.25,
            Fortra_Product_Type__c = 'Renewal Maintenance'
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 0,
            Base_Price__c = 355
        );
        insert oi;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Mapping should succeed');
        System.assertEquals(1, results[0].itemsMapped, 'Should patch renewal carry-forward fields');

        OrderItem patched = [
            SELECT Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   UnitPrice, NetUnitPrice
            FROM OrderItem
            WHERE Id = :oi.Id
        ];
        System.assertEquals(71, patched.Base_Price__c, 'Should overwrite license base with maintenance base');
        System.assertEquals(8.52, patched.Prior_Partner_Discount__c);
        System.assertEquals(6.25, patched.Prior_Discretionary_Discount__c);
        System.assertEquals(60.64, patched.UnitPrice);
        System.assertEquals(60.64, patched.NetUnitPrice);
    }

    @isTest
    static void testMapsNewBusinessDecompositionOverwritesLicenseBase() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Product2 maintProd = new Product2(
            Name = 'Mapper NB Maint Product',
            ProductCode = 'MAP-NB-DECOMP',
            IsActive = true,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert maintProd;

        Id stdPBId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPBId,
            Product2Id = maintProd.Id,
            UnitPrice = 355,
            IsActive = true
        );
        insert pbe;

        Quote q = buildQuote(acct.Id, 'Mapper NB Decomp Quote');
        q.Quote_Type__c = 'New';
        update q;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 62.48,
            PartnerUnitPrice = 62.48,
            Base_Price__c = 355,
            Fortra_Product_Type__c = 'New Maintenance'
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = maintProd.Id,
            Quantity = 1,
            UnitPrice = 62.48,
            Base_Price__c = 355
        );
        insert oi;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        List<QuoteToOrderFieldMapper.MapResult> results =
            QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Mapping should succeed');

        OrderItem patched = [
            SELECT Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   UnitPrice, NetUnitPrice
            FROM OrderItem
            WHERE Id = :oi.Id
        ];
        System.assertEquals(71, patched.Base_Price__c, 'Q2O should persist maintenance base, not license base');
        System.assertEquals(8.52, patched.Prior_Partner_Discount__c);
        System.assertEquals(62.48, patched.UnitPrice);
        System.assertEquals(62.48, patched.NetUnitPrice);
    }

    @isTest
    static void testMapsSourceListPriceFromQLIToOrderItem() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'TEST-MAP-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        Id stdPBId = Test.getStandardPricebookId();

        Quote q = buildQuote(acct.Id, 'Source List Price Quote');
        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100,
            Source_List_Price__c = 355
        );
        insert qli;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPBId,
            QuoteId = q.Id
        );
        insert ord;

        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            QuoteLineItemId = qli.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = prod.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert oi;

        Test.startTest();
        QuoteToOrderFieldMapper.MapRequest req = new QuoteToOrderFieldMapper.MapRequest();
        req.orderId = ord.Id;
        QuoteToOrderFieldMapper.mapFields(new List<QuoteToOrderFieldMapper.MapRequest>{ req });
        Test.stopTest();

        OrderItem patched = [
            SELECT Source_List_Price__c FROM OrderItem WHERE Id = :oi.Id
        ];
        System.assertEquals(355, patched.Source_List_Price__c,
            'Q2O should copy stamped Source_List_Price__c for reprice context hydration');
    }
}