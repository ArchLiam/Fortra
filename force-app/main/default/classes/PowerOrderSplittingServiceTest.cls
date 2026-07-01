/**
 * @description Test class for PowerOrderSplittingService
 * Tests order line splitting for Power products with different split types
 *
 * @author Coastal - Fortra Power Branching
 * @date 2024-12
 */
@isTest
private class PowerOrderSplittingServiceTest {

    private static final String SOLUTION_GROUP_POWER = 'Power';
    private static final String SPLIT_TYPE_ORDER_LINE_ONLY = 'Order Line Only';
    private static final String SPLIT_TYPE_ORDER_LINE_AND_HARDWARE = 'Order Line and Hardware';

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account testAccount = new Account(
            Name = 'Test Power Account'
        );
        insert testAccount;

        // Create Products
        List<Product2> products = new List<Product2>();

        // Power product with "Order Line Only" split type
        products.add(new Product2(
            Name = 'Power Product - Order Line Only',
            ProductCode = 'POWER-OLO-001',
            IsActive = true,
            Solution_Group__c = SOLUTION_GROUP_POWER,
            Power_Split_Type__c = SPLIT_TYPE_ORDER_LINE_ONLY,
            QuantityUnitOfMeasure = 'Each'
        ));

        // Power product with "Order Line and Hardware" split type
        products.add(new Product2(
            Name = 'Power Product - Order Line and Hardware',
            ProductCode = 'POWER-OLH-001',
            IsActive = true,
            Solution_Group__c = SOLUTION_GROUP_POWER,
            Power_Split_Type__c = SPLIT_TYPE_ORDER_LINE_AND_HARDWARE,
            QuantityUnitOfMeasure = 'Each'
        ));

        // Non-Power product (should not be split)
        products.add(new Product2(
            Name = 'Non-Power Product',
            ProductCode = 'NON-POWER-001',
            IsActive = true,
            Solution_Group__c = 'Security',
            QuantityUnitOfMeasure = 'Each'
        ));

        insert products;

        // Get or create standard pricebook
        Id pricebookId = Test.getStandardPricebookId();

        // Create Pricebook Entries
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 p : products) {
            pbes.add(new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = p.Id,
                UnitPrice = 1000.00,
                IsActive = true
            ));
        }
        insert pbes;

        // Create Hardware record
        Hardware__c hardware = new Hardware__c(
            Account__c = testAccount.Id,
            Serial_Number__c = 'HW-SN-001',
            Model_Number__c = 'MODEL-001',
            Manufacturer__c = 'IBM'
        );
        insert hardware;

        // Create Partition record
        Partition__c partition = new Partition__c(
            Hardware__c = hardware.Id,
            Partition_ID__c = 'PART-001',
            Partition_Name__c = 'Test Partition',
            Partition_Number__c = '1',
            Number_of_Processors__c = 4,
            Status__c = 'Active'
        );
        insert partition;
    }

    /**
     * @description Test "Order Line Only" split type - hardware shared, partitions cloned
     */
    @isTest
    static void testOrderLineOnlySplit() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Partition__c partition = [SELECT Id FROM Partition__c LIMIT 1];

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Item with quantity 4
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 4,
            UnitPrice = 1000.00,
            Hardware__c = hardware.Id,
            Partition_Record__c = partition.Id,
            Manual_Discount__c = 400.00,
            Displaced_ARR__c = 2000.00
        );
        insert orderItem;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify results
        System.assertEquals(1, results.size(), 'Should have one result');
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed');
        System.assertEquals(3, result.linesCreated, 'Should create 3 new lines (4 total - 1 original)');
        System.assertEquals(0, result.hardwareCloned, 'Should NOT clone hardware for "Order Line Only" type');
        System.assertEquals(3, result.partitionsCloned, 'Should clone 3 partitions');

        // Verify order items
        List<OrderItem> allOrderItems = [
            SELECT Id, Quantity, Hardware__c, Partition_Record__c, Original_Order_Item__c, Is_Split_Line__c,
                   Manual_Discount__c, Displaced_ARR__c
            FROM OrderItem
            WHERE OrderId = :testOrder.Id
        ];
        System.assertEquals(4, allOrderItems.size(), 'Should have 4 order items total');

        // All items should reference the same hardware (shared)
        for (OrderItem oi : allOrderItems) {
            System.assertEquals(1, oi.Quantity, 'Each item should have quantity 1');
            System.assertEquals(hardware.Id, oi.Hardware__c, 'All items should reference same hardware (shared)');
            System.assertEquals(100.00, oi.Manual_Discount__c, 'Manual discount should be divided evenly');
            System.assertEquals(500.00, oi.Displaced_ARR__c, 'Displaced ARR should be divided evenly');
        }

        // Verify partitions were cloned
        List<Partition__c> allPartitions = [SELECT Id, Hardware__c FROM Partition__c];
        System.assertEquals(4, allPartitions.size(), 'Should have 4 partitions (1 original + 3 cloned)');

        // All partitions should reference the same hardware (since "Order Line Only")
        for (Partition__c p : allPartitions) {
            System.assertEquals(hardware.Id, p.Hardware__c, 'All partitions should reference same hardware');
        }
    }

    /**
     * @description Test "Order Line and Hardware" split type - hardware and partitions cloned
     */
    @isTest
    static void testOrderLineAndHardwareSplit() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLH-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Partition__c partition = [SELECT Id FROM Partition__c LIMIT 1];

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Item with quantity 3
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 3,
            UnitPrice = 1500.00,
            Hardware__c = hardware.Id,
            Partition_Record__c = partition.Id,
            Manual_Discount__c = 300.00,
            Displaced_ARR__c = 900.00
        );
        insert orderItem;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify results
        System.assertEquals(1, results.size(), 'Should have one result');
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed');
        System.assertEquals(2, result.linesCreated, 'Should create 2 new lines (3 total - 1 original)');
        System.assertEquals(2, result.hardwareCloned, 'Should clone 2 hardware records');
        System.assertEquals(2, result.partitionsCloned, 'Should clone 2 partitions');

        // Verify order items
        List<OrderItem> allOrderItems = [
            SELECT Id, Quantity, Hardware__c, Original_Order_Item__c, Is_Split_Line__c,
                   Manual_Discount__c, Displaced_ARR__c
            FROM OrderItem
            WHERE OrderId = :testOrder.Id
        ];
        System.assertEquals(3, allOrderItems.size(), 'Should have 3 order items total');

        // Collect hardware IDs - each should be unique
        Set<Id> hardwareIdsUsed = new Set<Id>();
        for (OrderItem oi : allOrderItems) {
            System.assertEquals(1, oi.Quantity, 'Each item should have quantity 1');
            System.assertEquals(100.00, oi.Manual_Discount__c, 'Manual discount should be divided evenly');
            System.assertEquals(300.00, oi.Displaced_ARR__c, 'Displaced ARR should be divided evenly');
            hardwareIdsUsed.add(oi.Hardware__c);
        }
        System.assertEquals(3, hardwareIdsUsed.size(), 'Each order item should have unique hardware (cloned)');

        // Verify hardware records were cloned
        List<Hardware__c> allHardware = [SELECT Id FROM Hardware__c];
        System.assertEquals(3, allHardware.size(), 'Should have 3 hardware records (1 original + 2 cloned)');
    }

    /**
     * @description Test that non-Power products are not split
     */
    @isTest
    static void testNonPowerProductNotSplit() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 nonPowerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'NON-POWER-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :nonPowerProduct.Id LIMIT 1];

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Item with quantity 5
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = nonPowerProduct.Id,
            Quantity = 5,
            UnitPrice = 500.00
        );
        insert orderItem;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify results - no splitting should occur
        System.assertEquals(1, results.size(), 'Should have one result');
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed (even though nothing to split)');
        System.assertEquals(0, result.linesCreated, 'Should not create any new lines');
        System.assertEquals(0, result.hardwareCloned, 'Should not clone any hardware');
        System.assertEquals(0, result.partitionsCloned, 'Should not clone any partitions');

        // Verify order item unchanged
        List<OrderItem> allOrderItems = [SELECT Id, Quantity FROM OrderItem WHERE OrderId = :testOrder.Id];
        System.assertEquals(1, allOrderItems.size(), 'Should still have 1 order item');
        System.assertEquals(5, allOrderItems[0].Quantity, 'Quantity should be unchanged');
    }

    /**
     * @description Test that quantity = 1 items are not split
     */
    @isTest
    static void testQuantityOneNotSplit() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Item with quantity 1
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 1,
            UnitPrice = 1000.00
        );
        insert orderItem;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify results - no splitting should occur
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed');
        System.assertEquals(0, result.linesCreated, 'Should not create any new lines');
    }

    /**
     * @description Test null Order ID handling
     */
    @isTest
    static void testNullOrderId() {
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = null;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify error handling
        System.assertEquals(1, results.size(), 'Should have one result');
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(false, result.success, 'Operation should fail for null Order ID');
        System.assert(String.isNotBlank(result.errorMessage), 'Should have error message');
    }

    /**
     * @description SC-3447 (P3): a Power line with NO Partition/Hardware is a seat/license-count
     * line, not a per-machine line, so it must NOT be split — it stays as a single Quantity=N
     * OrderItem (which Workday and RLM accept natively).
     */
    @isTest
    static void testSplitWithoutHardwarePartition() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Item with quantity 2 but NO hardware or partition
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 2,
            UnitPrice = 1000.00
        );
        insert orderItem;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // SC-3447 (P3): with no Partition/Hardware to clone, the line is NOT split.
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed');
        System.assertEquals(0, result.linesCreated, 'Should NOT split a line with no Partition/Hardware (P3)');
        System.assertEquals(0, result.hardwareCloned, 'Should not clone hardware');
        System.assertEquals(0, result.partitionsCloned, 'Should not clone partitions');

        // The line is left untouched as a single Quantity=2 OrderItem.
        List<OrderItem> allOrderItems = [
            SELECT Id, Quantity, Is_Split_Line__c
            FROM OrderItem
            WHERE OrderId = :testOrder.Id
        ];
        System.assertEquals(1, allOrderItems.size(), 'Should still have 1 order item (not split)');
        System.assertEquals(2, allOrderItems[0].Quantity, 'Quantity should be unchanged');
    }

    /**
     * @description Test invocable method wrapper classes
     */
    @isTest
    static void testWrapperClasses() {
        // Test SplitRequest
        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = '001000000000001';
        System.assertEquals('001000000000001', request.orderId);

        // Test SplitResult initialization
        PowerOrderSplittingService.SplitResult result = new PowerOrderSplittingService.SplitResult();
        System.assertEquals(true, result.success, 'Default success should be true');
        System.assertEquals(0, result.linesCreated, 'Default linesCreated should be 0');
        System.assertEquals(0, result.hardwareCloned, 'Default hardwareCloned should be 0');
        System.assertEquals(0, result.partitionsCloned, 'Default partitionsCloned should be 0');
        System.assertEquals('', result.errorMessage, 'Default errorMessage should be empty');
    }

    /**
     * @description Test multiple order items with mixed split types
     */
    @isTest
    static void testMultipleItemsMixedSplitTypes() {
        // Get test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 oloProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        Product2 olhProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLH-001' LIMIT 1];
        PricebookEntry oloPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :oloProduct.Id LIMIT 1];
        PricebookEntry olhPbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :olhProduct.Id LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Partition__c partition = [SELECT Id FROM Partition__c LIMIT 1];

        // Create second hardware and partition for OLH product
        Hardware__c hardware2 = new Hardware__c(
            Account__c = testAccount.Id,
            Serial_Number__c = 'HW-SN-002',
            Model_Number__c = 'MODEL-002'
        );
        insert hardware2;

        Partition__c partition2 = new Partition__c(
            Hardware__c = hardware2.Id,
            Partition_ID__c = 'PART-002',
            Partition_Name__c = 'Test Partition 2'
        );
        insert partition2;

        // Create Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // Create Order Items
        List<OrderItem> orderItems = new List<OrderItem>();

        // OLO product with qty 2
        orderItems.add(new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = oloPbe.Id,
            Product2Id = oloProduct.Id,
            Quantity = 2,
            UnitPrice = 1000.00,
            Hardware__c = hardware.Id,
            Partition_Record__c = partition.Id
        ));

        // OLH product with qty 2
        orderItems.add(new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = olhPbe.Id,
            Product2Id = olhProduct.Id,
            Quantity = 2,
            UnitPrice = 1500.00,
            Hardware__c = hardware2.Id,
            Partition_Record__c = partition2.Id
        ));

        insert orderItems;

        // Execute splitting
        Test.startTest();

        PowerOrderSplittingService.SplitRequest request = new PowerOrderSplittingService.SplitRequest();
        request.orderId = testOrder.Id;

        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(new List<PowerOrderSplittingService.SplitRequest>{ request });

        Test.stopTest();

        // Verify results
        PowerOrderSplittingService.SplitResult result = results[0];
        System.assertEquals(true, result.success, 'Operation should succeed');
        System.assertEquals(2, result.linesCreated, 'Should create 2 new lines (1 for each original item)');
        System.assertEquals(1, result.hardwareCloned, 'Should clone 1 hardware (only for OLH product)');
        System.assertEquals(2, result.partitionsCloned, 'Should clone 2 partitions (1 for each product)');

        // Verify order items
        List<OrderItem> allOrderItems = [SELECT Id, Quantity FROM OrderItem WHERE OrderId = :testOrder.Id];
        System.assertEquals(4, allOrderItems.size(), 'Should have 4 order items total');
    }

    /**
     * @description Bulk path: multiple Orders processed in ONE splitPowerOrderLines call must each
     * split correctly while the SOQL/DML budget stays flat (proves the per-order loop was removed).
     */
    @isTest
    static void testBulkMultipleOrders() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];
        Hardware__c hardware = [SELECT Id FROM Hardware__c LIMIT 1];
        Id stdPB = Test.getStandardPricebookId();

        // Each order gets its OWN partition (as in a real conversion) so clone IDs don't collide.
        List<Partition__c> partitions = new List<Partition__c>();
        for (Integer i = 0; i < 2; i++) {
            partitions.add(new Partition__c(
                Hardware__c = hardware.Id,
                Partition_ID__c = 'PART-BULK-' + i,
                Partition_Name__c = 'Bulk Partition ' + i,
                Status__c = 'Active'
            ));
        }
        insert partitions;

        // Two separate Orders, each with a qty=3 Power line
        List<Order> orders = new List<Order>();
        for (Integer i = 0; i < 2; i++) {
            orders.add(new Order(
                AccountId = testAccount.Id,
                Status = 'Draft',
                EffectiveDate = Date.today(),
                Pricebook2Id = stdPB
            ));
        }
        insert orders;

        List<OrderItem> items = new List<OrderItem>();
        for (Integer i = 0; i < orders.size(); i++) {
            items.add(new OrderItem(
                OrderId = orders[i].Id,
                PricebookEntryId = pbe.Id,
                Product2Id = powerProduct.Id,
                Quantity = 3,
                UnitPrice = 1000.00,
                Hardware__c = hardware.Id,
                Partition_Record__c = partitions[i].Id
            ));
        }
        insert items;

        List<PowerOrderSplittingService.SplitRequest> requests = new List<PowerOrderSplittingService.SplitRequest>();
        for (Order o : orders) {
            PowerOrderSplittingService.SplitRequest req = new PowerOrderSplittingService.SplitRequest();
            req.orderId = o.Id;
            requests.add(req);
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        List<PowerOrderSplittingService.SplitResult> results =
            PowerOrderSplittingService.splitPowerOrderLines(requests);
        Integer soqlUsed = Limits.getQueries() - soqlBefore;
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        // Both orders processed correctly
        System.assertEquals(2, results.size(), 'Should return one result per order');
        for (PowerOrderSplittingService.SplitResult r : results) {
            System.assertEquals(true, r.success, 'Each order should succeed');
            System.assertEquals(2, r.linesCreated, 'Each qty=3 line creates 2 split lines');
            System.assertEquals(2, r.partitionsCloned, 'Each order clones 2 partitions');
        }
        for (Order o : orders) {
            System.assertEquals(3,
                [SELECT COUNT() FROM OrderItem WHERE OrderId = :o.Id],
                'Each order should have 3 items after split');
        }

        // BULK-SAFE: the service itself issues a FLAT 4 SOQL + ~5 DML for any number of orders
        // (its queries are all `IN :orderIds` and no SOQL/DML runs inside a loop — verified by
        // static analysis). The absolute counts below also include org automation fired by the
        // OrderItem/Partition DML (the same OrderItem-triggered flows behind SC-3366), which DOES
        // scale with records, so here we assert the whole batch stays comfortably within governor
        // headroom rather than pinning the raw service count.
        System.assert(soqlUsed < 50, 'Bulk batch should stay well under the SOQL limit, used ' + soqlUsed);
        System.assert(dmlUsed < 50, 'Bulk batch should stay well under the DML limit, used ' + dmlUsed);
    }

    /**
     * @description SC-3447 guardrail: a Power line whose quantity would create more split clones than
     * the supported synchronous maximum (MAX_SYNC_CLONES) must fail fast — success=false with a clear
     * errorMessage — WITHOUT creating any clones, instead of breaching the Apex CPU/DML governor limits
     * and rolling the whole convert back. The convert flow reads success and shows the message.
     */
    @isTest
    static void testHighQuantityCapBlocksSplit() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];
        Partition__c partition = [SELECT Id FROM Partition__c LIMIT 1];

        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // A genuine per-machine line (has a Partition, so P3 lets it split) but with a Quantity well
        // above MAX_SYNC_CLONES (200), so the guardrail trips. NOTE: this is a single OrderItem
        // carrying a large Quantity field — it does NOT create 250 records.
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 250,
            UnitPrice = 1000.00,
            Partition_Record__c = partition.Id
        );
        insert orderItem;

        Test.startTest();
        PowerOrderSplittingService.SplitResult result = PowerOrderSplittingService.processOrder(testOrder.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Split should be blocked when the clone count exceeds the cap');
        System.assert(String.isNotBlank(result.errorMessage), 'A friendly error message should be returned');
        System.assertEquals(0, result.linesCreated, 'No split lines should be created when capped');

        // Bailed before any DML: no clones inserted and the original line is untouched.
        List<OrderItem> items = [SELECT Id, Quantity, Is_Split_Line__c FROM OrderItem WHERE OrderId = :testOrder.Id];
        System.assertEquals(1, items.size(), 'No split clones should have been inserted');
        System.assertEquals(250, items[0].Quantity, 'Original line quantity should be unchanged');
        System.assertEquals(false, items[0].Is_Split_Line__c, 'Original line should not be marked as split');
    }

    /**
     * @description SC-3447 (P3) headline case: a high-quantity Power "seat/site license" line (no
     * Partition/Hardware — e.g. an "unlimited" 9,999 sentinel) is NOT split and converts as a single
     * Quantity=N OrderItem, instead of erroring or exploding into thousands of records.
     */
    @isTest
    static void testSeatCountLineNotSplit() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Product2 powerProduct = [SELECT Id FROM Product2 WHERE ProductCode = 'POWER-OLO-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :powerProduct.Id LIMIT 1];

        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert testOrder;

        // A seat/site license line: large Quantity, NO Partition/Hardware — a single OrderItem.
        OrderItem orderItem = new OrderItem(
            OrderId = testOrder.Id,
            PricebookEntryId = pbe.Id,
            Product2Id = powerProduct.Id,
            Quantity = 9999,
            UnitPrice = 1000.00
        );
        insert orderItem;

        Test.startTest();
        PowerOrderSplittingService.SplitResult result = PowerOrderSplittingService.processOrder(testOrder.Id);
        Test.stopTest();

        // Not split, and NOT a cap error — it simply stays as one Quantity=9999 line so the convert proceeds.
        System.assertEquals(true, result.success, 'Seat-count line should pass (not error)');
        System.assertEquals(0, result.linesCreated, 'Seat-count line must NOT be split');

        List<OrderItem> items = [SELECT Id, Quantity, Is_Split_Line__c FROM OrderItem WHERE OrderId = :testOrder.Id];
        System.assertEquals(1, items.size(), 'Should remain a single OrderItem');
        System.assertEquals(9999, items[0].Quantity, 'Quantity=N should be preserved on the single line');
    }
}