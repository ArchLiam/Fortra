/**
 * Tests for RenewalForecastAmount — the standing renewal-forecast Opportunity amount:
 * sum of the contract's RECURRING (term-based) asset ARR (MRR x 12), one-time items
 * excluded, uplifted by the contract COLA override (if valid) else the standard default.
 * @author Marc DeBrey
 */
@isTest
private class RenewalForecastAmountTest {

    @isTest
    static void computeAmount_sumsRecurringAnnualized_excludesOneTime_appliesDefaultCola() {
        // Two recurring assets (MRR 1000, 500) + one one-time (MRR 0); no contract override -> default 3%.
        Decimal amount = RenewalForecastAmount.computeAmount(
            new List<Decimal>{ 1000, 500, 0 }, null, 3
        );
        // ARR = (1000 + 500) * 12 = 18000 ; * 1.03 = 18540.00
        System.assertEquals(18540.00, amount,
            'Recurring ARR uplifted by default COLA, one-time (MRR=0) excluded');
    }

    @isTest
    static void computeAmount_usesContractOverride_overDefault() {
        Decimal amount = RenewalForecastAmount.computeAmount(
            new List<Decimal>{ 1000 }, 5, 3
        );
        // ARR = 12000 ; override 5% -> * 1.05 = 12600.00
        System.assertEquals(12600.00, amount, 'Contract override COLA takes precedence over default');
    }

    @isTest
    static void computeAmount_zero_whenAllOneTime() {
        Decimal amount = RenewalForecastAmount.computeAmount(new List<Decimal>{ 0, 0 }, null, 3);
        System.assertEquals(0, amount, 'No recurring items -> zero renewal amount');
    }

    @isTest
    static void computeAmount_handlesNullAndEmpty() {
        System.assertEquals(0, RenewalForecastAmount.computeAmount(null, null, 3), 'null list -> 0');
        System.assertEquals(0, RenewalForecastAmount.computeAmount(new List<Decimal>{ null }, null, 3),
            'null MRR entry skipped -> 0');
    }

    @isTest
    static void resolveContractColaPct_validNullPersistAndExpired() {
        System.assertEquals(null, RenewalForecastAmount.resolveContractColaPct(new Contract()),
            'no override -> null');

        Contract future = new Contract(COLA_Override_Percent__c = 4,
            COLA_Override_Persist_Until__c = Date.today().addDays(30));
        System.assertEquals(4, RenewalForecastAmount.resolveContractColaPct(future),
            'future persist date -> override valid');

        Contract nullPersist = new Contract(COLA_Override_Percent__c = 4);
        System.assertEquals(4, RenewalForecastAmount.resolveContractColaPct(nullPersist),
            'null persist date -> override valid (one-time use)');

        Contract expired = new Contract(COLA_Override_Percent__c = 4,
            COLA_Override_Persist_Until__c = Date.today().addDays(-1));
        System.assertEquals(null, RenewalForecastAmount.resolveContractColaPct(expired),
            'past persist date -> override expired -> null');
    }

    @isTest
    static void invocable_contractWithNoRecurringAssets_returnsZero() {
        Account a = new Account(Name = 'TDD Renewal Co');
        insert a;
        Contract c = new Contract(AccountId = a.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12);
        insert c;

        RenewalForecastAmount.Request req = new RenewalForecastAmount.Request();
        req.contractId = c.Id;

        Test.startTest();
        List<RenewalForecastAmount.Response> resp =
            RenewalForecastAmount.calculate(new List<RenewalForecastAmount.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, resp.size(), 'one response per request');
        System.assertEquals(0, resp[0].amount, 'contract with no recurring assets -> 0');
    }
}