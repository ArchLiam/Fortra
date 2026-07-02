// setupSC3502Contract.apex
// Builds a fresh, fully-linked Contract for end-to-end SC-3502 testing.
// It populates the Source Opportunity, Source Order, and Standing Renewal 
// Opportunity so the async Flow can successfully stamp Legal Entity, Bill-To, 
// and Ship-To onto the generated Renewal Quote.

Id ACCT = '001WC00000XiZP4YAN';         // Fortra, LLC - Test
Id PB   = '01sWC0000022GHFYA2';         // Fortra Price Book
Id LE   = '0fwWC000000034LYAQ';         // Legal Entity
Id PLC  = 'a0lWC000004cO79YAE';         // Standard Place (Bill To / Ship To)
Id PROD = '01tWC00000DD2SlYAL';         // Cobalt Strike (Software)

String TAG = Datetime.now().format('yyyy-MM-dd HH:mm');

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;
dml.DuplicateRuleHeader.RunAsCurrentUser = true;

Savepoint sp = Database.setSavepoint();
try {
    // 1. Get a Contact for the Order's BillToContactId
    Contact conRec = [SELECT Id FROM Contact WHERE AccountId = :ACCT LIMIT 1];

    // 2. Create Source Opportunity (Provides Amount, Bill-To, Ship-To to the Flow)
    Opportunity srcOpp = new Opportunity(
        Name = 'SC-3502 Source Opp ' + TAG,
        AccountId = ACCT,
        StageName = 'Closed Won',
        CloseDate = Date.today().addDays(-365),
        Amount = 50000,
        Bill_To_Place__c = PLC,
        Ship_To_Place__c = PLC,
        Legal_Entity__c = LE,
        CurrencyIsoCode = 'USD',
        Pricebook2Id = PB
    );
    Database.insert(srcOpp, dml);

    // 3. Create Source Order (Provides BillToContactId to the Flow)
    Order srcOrder = new Order(
        AccountId = ACCT,
        EffectiveDate = Date.today().addDays(-365),
        Status = 'Draft',
        Pricebook2Id = PB,
        OpportunityId = srcOpp.Id,
        BillToContactId = conRec.Id,
        CurrencyIsoCode = 'USD'
    );
    Database.insert(srcOrder, dml);

    // 4. Create Standing Renewal Opportunity (Provides Stage, Dates to the Flow)
    Opportunity renOpp = new Opportunity(
        Name = 'Renewal Forecast SC-3502 ' + TAG,
        AccountId = ACCT,
        StageName = 'Renewal Forecast',
        Type = 'Renewal',
        CloseDate = Date.today().addDays(30),
        Expected_Renewal_Date__c = Date.today().addDays(30),
        Pricebook2Id = PB,
        Amount = 52500,
        CurrencyIsoCode = 'USD'
    );
    Database.insert(renOpp, dml);

    // 5. Create the Contract and link all the lineage records
    Contract con = new Contract(
        AccountId = ACCT,
        StartDate = Date.today().addDays(-365),
        ContractTerm = 12,
        SourceOpportunityId = srcOpp.Id,
        SourceOrderId = srcOrder.Id,
        Renewal_Opportunity__c = renOpp.Id,
        Legal_Entity__c = LE,
        Status = 'Draft'
    );
    Database.insert(con, dml);
    
    // Activate the contract
    con.Status = 'Activated';
    Database.update(con, dml);

    // 6. Create a ready-to-renew Asset linked to the Account/Contract
    // (Lifecycle dates removed to prevent Execute Anonymous Error)
    Asset ast = new Asset(
        Name = 'Cobalt Strike - SC3502 Test',
        AccountId = ACCT,
        Product2Id = PROD,
        Quantity = 1,
        Price = 50000,
        InstallDate = Date.today().addDays(-365),
        PurchaseDate = Date.today().addDays(-365),
        RenewalTerm = 12,
        RenewalTermUnit = 'Months',
        CurrencyIsoCode = 'USD'
    );
    Database.insert(ast, dml);

    String base = URL.getOrgDomainUrl().toExternalForm();
    System.debug(LoggingLevel.ERROR, '✅ SC-3502 END-TO-END CONTRACT CREATED'
        + '\n  Contract     : ' + base + '/' + con.Id
        + '\n  Asset        : ' + base + '/' + ast.Id
        + '\n  Source Opp   : ' + base + '/' + srcOpp.Id
        + '\n  Source Order : ' + base + '/' + srcOrder.Id
        + '\n  Renewal Opp  : ' + base + '/' + renOpp.Id
        + '\n  NEXT STEP    : Open the Contract, select the Asset in Managed Assets, and click Renew.');

} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, '❌ SCRIPT FAILED (rolled back) [' 
        + e.getTypeName() + ' @ line ' + e.getLineNumber() + ']: ' + e.getMessage());
    throw e;
}