// createAccountLJsCompany.apex
// ---------------------------------------------------------------------------
// Purpose: Create (or reuse) a clean customer Account "LJ's Company" as the
//          starting point for an end-to-end RLM walkthrough:
//          Account -> Opportunity -> Quote -> Order -> Asset -> Renew/Amend/Cancel.
//
// Idempotent: if an Account named "LJ's Company" already exists it is reused,
// so re-running never creates duplicates.
//
// Run:
//   sf apex run --target-org FortraUAT --file scripts/apex/createAccountLJsCompany.apex
// ---------------------------------------------------------------------------

String acctName = 'LJ\'s Company';

List<Account> existing = [SELECT Id, Name FROM Account WHERE Name = :acctName LIMIT 1];

Account acc;
if (!existing.isEmpty()) {
    acc = existing[0];
    System.debug('>> Account already exists — reusing: ' + acc.Id);
} else {
    acc = new Account(
        Name            = acctName,
        Type            = 'Customer',   // valid picklist value in FortraUAT
        CurrencyIsoCode = 'USD'         // per-currency pricing — USD is load-bearing
    );
    insert acc;
    System.debug('>> Created Account: ' + acc.Id);
}

System.debug('==================================================');
System.debug('   Account Id   : ' + acc.Id);
System.debug('   Account Name : ' + acc.Name);
System.debug('==================================================');
