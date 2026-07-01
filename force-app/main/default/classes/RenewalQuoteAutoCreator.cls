/**
 * Auto-creates renewal quotes for contracts entering the configured lead-time window
 * (default 90 days), in the background. For each eligible contract it selects the
 * top-level term-based assets from the contract's OWN assets (precise link — not the
 * "most recent order for this product" heuristic the button flow uses), fires the
 * renewal engine headlessly (the mechanism proven in the Phase 0 spike) against the
 * contract's standing renewal Opportunity, and marks Renewal_Status__c = 'Quoted'.
 *
 * Bundle components are excluded (the engine renews them via their parent) and one-time
 * items (no renewal term) are excluded. Per-contract failures are logged, never silent,
 * and never abort the rest of the run.
 *
 * @author Marc DeBrey
 */
public with sharing class RenewalQuoteAutoCreator implements Schedulable {

    @TestVisible private static final Integer DEFAULT_LEAD_DAYS = 90;
    @TestVisible private static final Integer MAX_CONTRACTS_PER_RUN = 50;

    public void execute(SchedulableContext sc) {
        run();
    }

    public static void run() {
        Renewal_Automation_Settings__mdt cfg = getConfig();
        if (cfg == null || cfg.Is_Enabled__c != true) {
            return;
        }
        Integer leadDays = (cfg.Auto_Create_Lead_Days__c != null) ? cfg.Auto_Create_Lead_Days__c.intValue() : DEFAULT_LEAD_DAYS;
        Date today = Date.today();
        Date cutoff = today.addDays(leadDays);

        List<Contract> contracts = [
            SELECT Id, EndDate, Renewal_Opportunity__c
            FROM Contract
            WHERE Status = 'Activated'
              AND Auto_Renew__c = true
              AND EndDate != null
              AND EndDate >= :today
              AND EndDate <= :cutoff
              AND Renewal_Status__c != 'Quoted'
              AND Renewal_Status__c != 'Accepted'
              AND Renewal_Status__c != 'Declined'
            LIMIT :MAX_CONTRACTS_PER_RUN
        ];

        for (Contract c : contracts) {
            try {
                createRenewalForContract(c);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'RenewalQuoteAutoCreator|contract=' + c.Id + ' EXCEPTION ' + e.getTypeName() + ': ' + e.getMessage());
            }
        }
    }

    /**
     * Manually create the renewal for a single contract (admin trigger / retry),
     * bypassing the lead-time window. Still respects the master on/off switch and
     * the Activated + Auto_Renew gate.
     */
    public static void runForContract(Id contractId) {
        Renewal_Automation_Settings__mdt cfg = getConfig();
        if (cfg == null || cfg.Is_Enabled__c != true) {
            return;
        }
        for (Contract c : [
            SELECT Id, EndDate, Renewal_Opportunity__c
            FROM Contract
            WHERE Id = :contractId AND Status = 'Activated' AND Auto_Renew__c = true
        ]) {
            try {
                createRenewalForContract(c);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'RenewalQuoteAutoCreator|runForContract contract=' + c.Id + ' EXCEPTION ' + e.getMessage());
            }
        }
    }

    private static void createRenewalForContract(Contract c) {
        // The contract's OWN assets via the precise AssetContractRelationship link.
        List<Asset> assets = [
            SELECT Id, RenewalTerm, RenewalTermUnit
            FROM Asset
            WHERE Id IN (SELECT AssetId FROM AssetContractRelationship WHERE ContractId = :c.Id)
        ];
        if (assets.isEmpty()) {
            return;
        }
        Set<Id> assetIds = (new Map<Id, Asset>(assets)).keySet();

        // Bundle components = assets that are the RelatedAsset of a bundle relationship within this contract.
        Set<Id> componentIds = new Set<Id>();
        for (AssetRelationship ar : [
            SELECT RelatedAssetId FROM AssetRelationship
            WHERE AssetId IN :assetIds AND RelatedAssetId IN :assetIds
        ]) {
            componentIds.add(ar.RelatedAssetId);
        }

        List<Id> renewableAssetIds = selectRenewableAssets(assets, componentIds);
        if (renewableAssetIds.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'RenewalQuoteAutoCreator|contract=' + c.Id + ' has no renewable top-level term-based assets — skipped');
            return;
        }

        List<String> assetIdStrings = new List<String>();
        for (Id aid : renewableAssetIds) {
            assetIdStrings.add(String.valueOf(aid));
        }

        Invocable.Action action = Invocable.Action.createStandardAction('initiateRenewal');
        action.setInvocationParameter('renewAssetIds', assetIdStrings);
        action.setInvocationParameter('renewOutputType', 'Quote');
        action.setInvocationParameter('renewContractId', String.valueOf(c.Id));
        if (c.Renewal_Opportunity__c != null) {
            action.setInvocationParameter('renewOpportunityId', String.valueOf(c.Renewal_Opportunity__c));
        }
        action.setInvocationParameter('renewStartDate', toIso(c.EndDate.addDays(1)));
        action.setInvocationParameter('renewEndDate', toIso(c.EndDate.addYears(1)));

        List<Invocable.Action.Result> results = action.invoke();
        Boolean ok = results != null && !results.isEmpty() && results[0].isSuccess();
        if (!ok) {
            String err = (results == null || results.isEmpty()) ? 'no result' : String.valueOf(results[0].getErrors());
            System.debug(LoggingLevel.ERROR,
                'RenewalQuoteAutoCreator|initiateRenewal FAILED contract=' + c.Id + ' err=' + err);
            return;
        }

        // Stamp the new renewal quote synchronously — set Quote_Type__c='Renewal' and pin it to the
        // standing Opportunity. This mirrors the button flow and prevents Fortra_RCA_Renewal_Enhancement
        // (which fires on Quote create when Quote_Type__c is null) from creating a DUPLICATE opportunity.
        Id renewalQuoteId = extractQuoteId(results[0]);
        if (renewalQuoteId != null) {
            Quote q = new Quote(Id = renewalQuoteId, Quote_Type__c = 'Renewal', Renewal_Contract__c = c.Id);
            if (c.Renewal_Opportunity__c != null) {
                q.OpportunityId = c.Renewal_Opportunity__c;
            }
            update q;
        }

        update new Contract(Id = c.Id, Renewal_Status__c = 'Quoted');

        // Graduate the standing renewal Opportunity into the active forecast now that a quote exists.
        if (c.Renewal_Opportunity__c != null) {
            update new Opportunity(Id = c.Renewal_Opportunity__c, StageName = 'Pricing & Approval');
        }
    }

    private static Id extractQuoteId(Invocable.Action.Result result) {
        if (result == null) {
            return null;
        }
        Map<String, Object> outputs = result.getOutputParameters();
        Object v = (outputs != null) ? outputs.get('renewRecordId') : null;
        return (v != null) ? (Id) String.valueOf(v) : null;
    }

    /**
     * Pure selection: the top-level, term-based asset Ids to feed the renewal engine.
     * Excludes bundle components (renewed via their parent) and items with no renewal
     * term (one-time purchases don't renew).
     */
    @TestVisible
    static List<Id> selectRenewableAssets(List<Asset> contractAssets, Set<Id> bundleComponentAssetIds) {
        List<Id> result = new List<Id>();
        if (contractAssets == null) {
            return result;
        }
        for (Asset a : contractAssets) {
            if (bundleComponentAssetIds != null && bundleComponentAssetIds.contains(a.Id)) {
                continue; // bundle component — renewed via its parent
            }
            if (a.RenewalTerm == null || a.RenewalTermUnit == null) {
                continue; // one-time / no renewal term
            }
            result.add(a.Id);
        }
        return result;
    }

    /** Renewal date format expected by initiateRenewal: yyyy-MM-dd'T'HH:mm:ss at midnight. */
    @TestVisible
    static String toIso(Date d) {
        Datetime dt = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        return dt.format('yyyy-MM-dd\'T\'HH:mm:ss');
    }

    @TestVisible
    static Renewal_Automation_Settings__mdt getConfig() {
        return Renewal_Automation_Settings__mdt.getInstance('Default');
    }
}