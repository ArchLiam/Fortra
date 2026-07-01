@IsTest
private class AssetContractLinkerActionTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'ACR Test Account');
        insert acc;

        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        // Use the Standard price book
        Id stdPbId = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = prod.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe;

        Contract con = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.newInstance(2025, 6, 1),
            ContractTerm = 12
        );
        insert con;
        con.Status = 'Activated';
        update con;
    }

    @IsTest
    static void testLinkAssetsToContract_NoContract() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACR Test Account'];

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        AssetContractLinkerAction.ActionInput input = new AssetContractLinkerAction.ActionInput();
        input.orderId = ord.Id;

        Test.startTest();
        List<AssetContractLinkerAction.ActionOutput> outputs =
            AssetContractLinkerAction.linkAssetsToContract(new List<AssetContractLinkerAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(1, outputs.size());
        System.assertEquals(true, outputs[0].success);
        System.assertEquals(0, outputs[0].acrsCreated);
    }

    @IsTest
    static void testLinkAssetsToContract_WithContractNoAssets() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACR Test Account'];
        Contract con = [SELECT Id FROM Contract WHERE AccountId = :acc.Id LIMIT 1];

        Order ord = new Order(
            AccountId = acc.Id,
            ContractId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        AssetContractLinkerAction.ActionInput input = new AssetContractLinkerAction.ActionInput();
        input.orderId = ord.Id;

        Test.startTest();
        List<AssetContractLinkerAction.ActionOutput> outputs =
            AssetContractLinkerAction.linkAssetsToContract(new List<AssetContractLinkerAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success);
        System.assertEquals(0, outputs[0].acrsCreated);
    }

    @IsTest
    static void testLinkAssetsToContract_WithExistingAssets() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACR Test Account'];
        Contract con = [SELECT Id, StartDate, EndDate FROM Contract WHERE AccountId = :acc.Id LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Test Product'];

        // Create Order with Contract
        Order ord = new Order(
            AccountId = acc.Id,
            ContractId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 1000
        );
        insert oi;

        // Create Asset manually (simulating what createOrUpdateAssetFromOrder would do)
        Asset ast = new Asset(
            Name = 'Test Asset',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            CurrentQuantity = 1
        );
        insert ast;

        // Create the AssetAction and AssetActionSource chain to link Asset → OrderItem
        AssetAction aa = new AssetAction(
            AssetId = ast.Id,
            Type = 'Generate',
            CategoryEnum = 'Initial Sale',
            ActionDate = DateTime.now(),
            Amount = 1000,
            QuantityChange = 1,
            MrrChange = 0
        );
        insert aa;

        AssetActionSource aas = new AssetActionSource(
            AssetActionId = aa.Id,
            ReferenceEntityItemId = oi.Id,
            StartDate = DateTime.newInstance(con.StartDate, Time.newInstance(0, 0, 0, 0)),
            EndDate = DateTime.newInstance(con.EndDate, Time.newInstance(0, 0, 0, 0))
        );
        insert aas;

        // Create AUA on Contract (prerequisite)
        AppUsageAssignment aua = new AppUsageAssignment(
            RecordId = con.Id,
            AppUsageType = 'RevenueLifecycleManagement'
        );
        insert aua;

        AssetContractLinkerAction.ActionInput input = new AssetContractLinkerAction.ActionInput();
        input.orderId = ord.Id;

        Test.startTest();
        List<AssetContractLinkerAction.ActionOutput> outputs =
            AssetContractLinkerAction.linkAssetsToContract(new List<AssetContractLinkerAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success);
        System.assertEquals(1, outputs[0].acrsCreated);

        // Verify ACR was created
        List<AssetContractRelationship> acrs = [
            SELECT Id, AssetId, ContractId
            FROM AssetContractRelationship
            WHERE AssetId = :ast.Id AND ContractId = :con.Id
        ];
        System.assertEquals(1, acrs.size());
    }

    @IsTest
    static void testLinkAssetsToContract_SkipsExistingACR() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACR Test Account'];
        Contract con = [SELECT Id, StartDate, EndDate FROM Contract WHERE AccountId = :acc.Id LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Test Product'];

        Order ord = new Order(
            AccountId = acc.Id,
            ContractId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 1000
        );
        insert oi;

        Asset ast = new Asset(
            Name = 'Test Asset',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            CurrentQuantity = 1
        );
        insert ast;

        AssetAction aa = new AssetAction(
            AssetId = ast.Id,
            Type = 'Generate',
            CategoryEnum = 'Initial Sale',
            ActionDate = DateTime.now(),
            Amount = 1000,
            QuantityChange = 1,
            MrrChange = 0
        );
        insert aa;

        AssetActionSource aas = new AssetActionSource(
            AssetActionId = aa.Id,
            ReferenceEntityItemId = oi.Id,
            StartDate = DateTime.newInstance(con.StartDate, Time.newInstance(0, 0, 0, 0)),
            EndDate = DateTime.newInstance(con.EndDate, Time.newInstance(0, 0, 0, 0))
        );
        insert aas;

        // Create AUA on Contract
        AppUsageAssignment aua = new AppUsageAssignment(
            RecordId = con.Id,
            AppUsageType = 'RevenueLifecycleManagement'
        );
        insert aua;

        // Pre-create ACR (simulating it already exists)
        AssetContractRelationship existingAcr = new AssetContractRelationship(
            AssetId = ast.Id,
            ContractId = con.Id,
            StartDate = DateTime.newInstance(con.StartDate, Time.newInstance(0, 0, 0, 0)),
            EndDate = DateTime.newInstance(con.EndDate, Time.newInstance(0, 0, 0, 0))
        );
        insert existingAcr;

        AssetContractLinkerAction.ActionInput input = new AssetContractLinkerAction.ActionInput();
        input.orderId = ord.Id;

        Test.startTest();
        List<AssetContractLinkerAction.ActionOutput> outputs =
            AssetContractLinkerAction.linkAssetsToContract(new List<AssetContractLinkerAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success);
        System.assertEquals(0, outputs[0].acrsCreated, 'Should skip assets with existing ACR');

        // Verify only 1 ACR exists (the pre-existing one)
        Integer acrCount = [SELECT COUNT() FROM AssetContractRelationship
                            WHERE AssetId = :ast.Id AND ContractId = :con.Id];
        System.assertEquals(1, acrCount);
    }

    @IsTest
    static void testEnsuresContractAUA() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACR Test Account'];
        Contract con = [SELECT Id, StartDate, EndDate FROM Contract WHERE AccountId = :acc.Id LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'Test Product'];

        // Verify no AUA exists on contract initially
        Integer auaCount = [SELECT COUNT() FROM AppUsageAssignment
                            WHERE RecordId = :con.Id AND AppUsageType = 'RevenueLifecycleManagement'];
        System.assertEquals(0, auaCount, 'No AUA should exist initially');

        Order ord = new Order(
            AccountId = acc.Id,
            ContractId = con.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        OrderItem oi = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 1000
        );
        insert oi;

        Asset ast = new Asset(
            Name = 'Test Asset',
            AccountId = acc.Id,
            Product2Id = prod.Id,
            CurrentQuantity = 1
        );
        insert ast;

        AssetAction aa = new AssetAction(
            AssetId = ast.Id,
            Type = 'Generate',
            CategoryEnum = 'Initial Sale',
            ActionDate = DateTime.now(),
            Amount = 1000,
            QuantityChange = 1,
            MrrChange = 0
        );
        insert aa;

        AssetActionSource aas = new AssetActionSource(
            AssetActionId = aa.Id,
            ReferenceEntityItemId = oi.Id,
            StartDate = DateTime.newInstance(con.StartDate, Time.newInstance(0, 0, 0, 0)),
            EndDate = DateTime.newInstance(con.EndDate, Time.newInstance(0, 0, 0, 0))
        );
        insert aas;

        AssetContractLinkerAction.ActionInput input = new AssetContractLinkerAction.ActionInput();
        input.orderId = ord.Id;

        Test.startTest();
        List<AssetContractLinkerAction.ActionOutput> outputs =
            AssetContractLinkerAction.linkAssetsToContract(new List<AssetContractLinkerAction.ActionInput>{ input });
        Test.stopTest();

        System.assertEquals(true, outputs[0].success);
        System.assertEquals(1, outputs[0].acrsCreated);

        // Verify AUA was auto-created on the contract
        auaCount = [SELECT COUNT() FROM AppUsageAssignment
                    WHERE RecordId = :con.Id AND AppUsageType = 'RevenueLifecycleManagement'];
        System.assertEquals(1, auaCount, 'AUA should have been auto-created');
    }
}