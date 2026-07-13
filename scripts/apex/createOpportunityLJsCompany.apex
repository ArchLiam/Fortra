// createOpportunityLJsCompany.apex
// ---------------------------------------------------------------------------
// Purpose: Create (or reuse) an Opportunity for Account "LJ's Company" — the
//          commercial container the Quote will hang off in the RLM walkthrough.
//
// Idempotent: reuses an Opportunity of the same Name on the Account if present,
// so re-running never creates duplicates.
//
// Run:
//   sf apex run --target-org FortraUAT --file scripts/apex/createOpportunityLJsCompany.apex
// ---------------------------------------------------------------------------

String acctName = 'LJ\'s Company';
String oppName  = 'LJ\'s Company - New Business Deal';

// Resolve the Account created in step 1 (by name, so this is self-contained).
Account acc = [SELECT Id, CurrencyIsoCode FROM Account WHERE Name = :acctName ORDER BY CreatedDate ASC LIMIT 1];

List<Opportunity> existing = [
    SELECT Id, Name, StageName FROM Opportunity
    WHERE AccountId = :acc.Id AND Name = :oppName LIMIT 1
];

Opportunity opp;
if (!existing.isEmpty()) {
    opp = existing[0];
    System.debug('>> Opportunity already exists — reusing: ' + opp.Id);
} else {
    opp = new Opportunity(
        Name            = oppName,
        AccountId       = acc.Id,
        StageName       = 'Qualification',            // early open stage
        CloseDate       = Date.today().addDays(30),   // 30 days out
        Type            = 'Net-New',                  // brand-new business path
        CurrencyIsoCode = acc.CurrencyIsoCode         // inherit USD from the Account
    );
    insert opp;
    System.debug('>> Created Opportunity: ' + opp.Id);
}

System.debug('==================================================');
System.debug('   Opportunity Id : ' + opp.Id);
System.debug('   Name           : ' + opp.Name);
System.debug('   AccountId       : ' + acc.Id);
System.debug('==================================================');
