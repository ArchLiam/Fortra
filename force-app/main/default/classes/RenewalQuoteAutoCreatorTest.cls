/**
 * Tests for RenewalQuoteAutoCreator — auto-creates renewal quotes at the configured
 * lead time. Unit tests cover the pure asset-selection logic (exclude bundle components
 * and non-term items) and the date helper; the headless initiateRenewal orchestration is
 * verified end-to-end against the org (managed action not unit-testable).
 * @author Marc DeBrey
 */
@isTest
private class RenewalQuoteAutoCreatorTest {

    @isTest
    static void selectRenewableAssets_topLevelTermBasedOnly() {
        Account acc = new Account(Name = 'RQAC Test');
        insert acc;
        Asset topMonths = new Asset(Name = 'Top Months', AccountId = acc.Id, RenewalTerm = 12, RenewalTermUnit = 'Months');
        Asset component = new Asset(Name = 'Component',  AccountId = acc.Id, RenewalTerm = 12, RenewalTermUnit = 'Months');
        Asset noTerm    = new Asset(Name = 'No Term',    AccountId = acc.Id);
        Asset topAnnual = new Asset(Name = 'Top Annual', AccountId = acc.Id, RenewalTerm = 1,  RenewalTermUnit = 'Annual');
        insert new List<Asset>{ topMonths, component, noTerm, topAnnual };

        Set<Id> componentIds = new Set<Id>{ component.Id };
        List<Id> result = RenewalQuoteAutoCreator.selectRenewableAssets(
            new List<Asset>{ topMonths, component, noTerm, topAnnual }, componentIds);

        System.assertEquals(2, result.size(), 'only top-level term-based assets');
        System.assert(result.contains(topMonths.Id), 'top-level monthly-term asset included');
        System.assert(result.contains(topAnnual.Id), 'top-level annual-term asset included');
        System.assert(!result.contains(component.Id), 'bundle component excluded');
        System.assert(!result.contains(noTerm.Id), 'no-term (one-time) asset excluded');
    }

    @isTest
    static void selectRenewableAssets_handlesNullAndEmpty() {
        System.assertEquals(0, RenewalQuoteAutoCreator.selectRenewableAssets(null, null).size());
        System.assertEquals(0, RenewalQuoteAutoCreator.selectRenewableAssets(new List<Asset>(), new Set<Id>()).size());
    }

    @isTest
    static void toIso_formatsDateAsMidnightIso() {
        System.assertEquals('2028-03-30T00:00:00', RenewalQuoteAutoCreator.toIso(Date.newInstance(2028, 3, 30)));
    }

    @isTest
    static void run_noEligibleContracts_completesQuietly() {
        // No Activated auto-renew contracts in the lead-time window exist in test context -> no-op, no exception.
        Test.startTest();
        RenewalQuoteAutoCreator.run();
        Test.stopTest();
        System.assert(true, 'run completed without error when nothing is eligible');
    }
}