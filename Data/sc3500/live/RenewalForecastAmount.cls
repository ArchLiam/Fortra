/**
 * Calculates the standing renewal-forecast Opportunity Amount for a Contract:
 * the sum of the contract's TERM-BASED (recurring) assets' annual recurring revenue
 * (Asset.CurrentMrr x 12), uplifted by the contract's COLA — the contract override
 * percent when valid, otherwise the standard default.
 *
 * Only recurring items renew: assets with no monthly recurring revenue (one-time
 * purchases) are excluded. The value is read live from the assets, not a stored field.
 * This is a far-future forecast estimate; the precise per-product/CMDT COLA is applied
 * by COLAUpliftHandler when the actual renewal quote is built near expiry.
 *
 * @author Marc DeBrey
 */
public with sharing class RenewalForecastAmount {

    @TestVisible
    private static final Decimal STANDARD_DEFAULT_COLA_PCT = 3;

    public class Request {
        @InvocableVariable(required=true label='Contract Id')
        public Id contractId;
    }
    public class Response {
        @InvocableVariable(label='Renewal Forecast Amount')
        public Decimal amount;
    }

    @InvocableMethod(label='Calculate Renewal Forecast Amount'
        description='Sum of the contract\'s recurring (term-based) asset ARR, COLA-uplifted')
    public static List<Response> calculate(List<Request> requests) {
        List<Response> results = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> contractIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.contractId != null) {
                contractIds.add(r.contractId);
            }
        }

        // Contract-level COLA overrides (validity decided by persist-until date)
        Map<Id, Contract> contractsById = new Map<Id, Contract>([
            SELECT Id, COLA_Override_Percent__c, COLA_Override_Persist_Until__c
            FROM Contract
            WHERE Id IN :contractIds
        ]);

        // Each contract's assets' monthly recurring revenue, via AssetContractRelationship
        Map<Id, List<Decimal>> mrrsByContractId = new Map<Id, List<Decimal>>();
        for (AssetContractRelationship acr : [
            SELECT ContractId, Asset.CurrentMrr
            FROM AssetContractRelationship
            WHERE ContractId IN :contractIds
        ]) {
            if (!mrrsByContractId.containsKey(acr.ContractId)) {
                mrrsByContractId.put(acr.ContractId, new List<Decimal>());
            }
            mrrsByContractId.get(acr.ContractId).add(
                acr.Asset != null ? acr.Asset.CurrentMrr : null
            );
        }

        Decimal defaultColaPct = resolveDefaultColaPct();

        for (Request r : requests) {
            Response resp = new Response();
            if (r != null && r.contractId != null) {
                Decimal contractColaPct = resolveContractColaPct(contractsById.get(r.contractId));
                resp.amount = computeAmount(mrrsByContractId.get(r.contractId), contractColaPct, defaultColaPct);
            } else {
                resp.amount = 0;
            }
            results.add(resp);
        }
        return results;
    }

    /**
     * Pure calculation: sum the term-based (recurring) assets' annual recurring revenue
     * (MRR x 12; one-time items have MRR <= 0 and are excluded) and apply the COLA uplift —
     * the contract override percent when present, otherwise the standard default.
     */
    @TestVisible
    static Decimal computeAmount(List<Decimal> assetMonthlyRecurring, Decimal contractColaPct, Decimal defaultColaPct) {
        Decimal annualRecurring = 0;
        if (assetMonthlyRecurring != null) {
            for (Decimal mrr : assetMonthlyRecurring) {
                if (mrr != null && mrr > 0) {            // term-based only; one-time has no recurring revenue
                    annualRecurring += mrr * 12;
                }
            }
        }
        Decimal colaPct = (contractColaPct != null) ? contractColaPct : defaultColaPct;
        if (colaPct == null) {
            colaPct = 0;
        }
        return (annualRecurring * (1 + (colaPct / 100))).setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * The contract's COLA override percent if set and not expired (null persist date =
     * valid for the next renewal; future date = valid; past = expired). Mirrors
     * COLAUpliftHandler's persist-date validity. Returns null when no valid override.
     */
    @TestVisible
    static Decimal resolveContractColaPct(Contract c) {
        if (c == null || c.COLA_Override_Percent__c == null) {
            return null;
        }
        Date persistUntil = c.COLA_Override_Persist_Until__c;
        if (persistUntil == null || persistUntil >= Date.today()) {
            return c.COLA_Override_Percent__c;
        }
        return null;
    }

    /**
     * The standard fallback uplift when a contract has no override: the active MyCAP
     * global default (the same source COLAUpliftHandler uses), or 3% if unavailable.
     */
    @TestVisible
    static Decimal resolveDefaultColaPct() {
        MyCAP_Rules__mdt globalRule = MyCAP_Rules__mdt.getInstance('Global');
        if (globalRule != null && globalRule.Is_Active__c == true
            && globalRule.Default_Out_Year_Uplift_Percent__c != null) {
            return globalRule.Default_Out_Year_Uplift_Percent__c;
        }
        return STANDARD_DEFAULT_COLA_PCT;
    }
}
