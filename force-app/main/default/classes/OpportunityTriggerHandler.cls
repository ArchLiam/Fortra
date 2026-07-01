/**
 * @description Handler for Opportunity trigger to manage Hardware record lifecycle
 * @author Claude Code
 * @date 2025-01-25
 *
 * Manages Hardware__c Status based on Opportunity stage changes:
 * - 'Closed Lost': Delete Hardware with Status='Quoting' (if not referenced by other Opportunities)
 * - 'Order Processing': Change Status from 'Quoting' to 'Active'
 *
 * Data Model Path:
 * Opportunity → Quote (via OpportunityId) → QuoteLineGroup (via QuoteId) → Hardware__c (via Hardware__c lookup)
 */
public with sharing class OpportunityTriggerHandler {

    private static final String STAGE_CLOSED_LOST = 'Closed Lost';
    private static final String STAGE_ORDER_PROCESSING = 'Order Processing';
    private static final String STATUS_QUOTING = 'Quoting';
    private static final String STATUS_ACTIVE = 'Active';

    /**
     * @description Handle before insert — set Exchange_Rate_To_USD__c on every new Opportunity
     * Uses DatedConversionRateLookup (ACM with CurrencyType fallback), same utility as QLI trigger.
     * @param newOpportunities List of Opportunity records being inserted
     */
    public static void handleBeforeInsert(List<Opportunity> newOpportunities) {
        setExchangeRates(newOpportunities);
    }

    /**
     * @description Handle before update — refresh Exchange_Rate_To_USD__c when CurrencyIsoCode changes
     * Only processes records where CurrencyIsoCode actually changed to avoid unnecessary SOQL.
     * @param newOpportunities List of updated Opportunity records
     * @param oldOpportunityMap Map of old Opportunity records by Id
     */
    public static void handleBeforeUpdate(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldOpportunityMap) {
        List<Opportunity> currencyChangedOpps = new List<Opportunity>();
        for (Opportunity opp : newOpportunities) {
            Opportunity oldOpp = oldOpportunityMap.get(opp.Id);
            if (opp.CurrencyIsoCode != oldOpp.CurrencyIsoCode) {
                currencyChangedOpps.add(opp);
            }
        }
        if (!currencyChangedOpps.isEmpty()) {
            setExchangeRates(currencyChangedOpps);
        }
    }

    /**
     * @description Set Exchange_Rate_To_USD__c on a list of Opportunities using DatedConversionRateLookup.
     * Before-trigger context — modifies records in-place, no DML needed.
     * @param opportunities List of Opportunity records to set rates on
     */
    private static void setExchangeRates(List<Opportunity> opportunities) {
        List<DatedConversionRateLookup.Request> requests = new List<DatedConversionRateLookup.Request>();
        List<Opportunity> oppsToRate = new List<Opportunity>();

        for (Opportunity opp : opportunities) {
            if (String.isNotBlank(opp.CurrencyIsoCode)) {
                DatedConversionRateLookup.Request req = new DatedConversionRateLookup.Request();
                req.currencyIsoCode = opp.CurrencyIsoCode;
                requests.add(req);
                oppsToRate.add(opp);
            }
        }

        if (!requests.isEmpty()) {
            List<DatedConversionRateLookup.Result> results = DatedConversionRateLookup.getExchangeRates(requests);
            for (Integer i = 0; i < oppsToRate.size(); i++) {
                oppsToRate[i].Exchange_Rate_To_USD__c = results[i].exchangeRate;
            }
        }
    }

    /**
     * @description Handle after update trigger event
     * @param newOpportunities List of updated Opportunity records
     * @param oldOpportunityMap Map of old Opportunity records by Id
     */
    public static void handleAfterUpdate(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldOpportunityMap) {
        Set<Id> closedLostOpportunityIds = new Set<Id>();
        Set<Id> orderProcessingOpportunityIds = new Set<Id>();

        // Identify Opportunities with relevant stage changes
        for (Opportunity opp : newOpportunities) {
            Opportunity oldOpp = oldOpportunityMap.get(opp.Id);

            // Check if stage changed
            if (opp.StageName != oldOpp.StageName) {
                if (opp.StageName == STAGE_CLOSED_LOST) {
                    closedLostOpportunityIds.add(opp.Id);
                } else if (opp.StageName == STAGE_ORDER_PROCESSING) {
                    orderProcessingOpportunityIds.add(opp.Id);
                }
            }
        }

        // Process Closed Lost opportunities - delete Quoting hardware
        if (!closedLostOpportunityIds.isEmpty()) {
            handleClosedLost(closedLostOpportunityIds);
        }

        // Process Order Processing opportunities - activate Quoting hardware
        if (!orderProcessingOpportunityIds.isEmpty()) {
            handleOrderProcessing(orderProcessingOpportunityIds);
        }
    }

    /**
     * @description Handle Closed Lost stage - delete Hardware with Status='Quoting'
     * Only deletes hardware that is NOT referenced by QuoteLineGroups on other Opportunities
     * @param opportunityIds Set of Opportunity IDs that moved to Closed Lost
     */
    private static void handleClosedLost(Set<Id> opportunityIds) {
        // Get all Hardware IDs linked to these Opportunities via QuoteLineGroups
        Set<Id> hardwareIds = new Set<Id>();

        List<QuoteLineGroup> groups = [
            SELECT Id, Hardware__c, Quote.OpportunityId
            FROM QuoteLineGroup
            WHERE Quote.OpportunityId IN :opportunityIds
            AND Hardware__c != null
        ];

        for (QuoteLineGroup grp : groups) {
            hardwareIds.add(grp.Hardware__c);
        }

        if (hardwareIds.isEmpty()) {
            return;
        }

        // Query Hardware records directly to check their Status
        Map<Id, Hardware__c> hardwareToDelete = new Map<Id, Hardware__c>();
        for (Hardware__c hw : [
            SELECT Id, Status__c
            FROM Hardware__c
            WHERE Id IN :hardwareIds
            AND Status__c = :STATUS_QUOTING
        ]) {
            hardwareToDelete.put(hw.Id, hw);
        }

        if (hardwareToDelete.isEmpty()) {
            return;
        }

        // Check if any of these Hardware records are referenced by other Opportunities
        Set<Id> hardwareReferencedElsewhere = new Set<Id>();

        List<QuoteLineGroup> otherReferences = [
            SELECT Id, Hardware__c
            FROM QuoteLineGroup
            WHERE Hardware__c IN :hardwareToDelete.keySet()
            AND Quote.OpportunityId NOT IN :opportunityIds
        ];

        for (QuoteLineGroup grp : otherReferences) {
            hardwareReferencedElsewhere.add(grp.Hardware__c);
        }

        // Remove hardware that is referenced elsewhere from deletion list
        for (Id hwId : hardwareReferencedElsewhere) {
            hardwareToDelete.remove(hwId);
        }

        // Delete hardware records that are only referenced by the closed lost opportunities
        if (!hardwareToDelete.isEmpty()) {
            delete hardwareToDelete.values();
        }
    }

    /**
     * @description Handle Order Processing stage - change Hardware Status from 'Quoting' to 'Active'
     * @param opportunityIds Set of Opportunity IDs that moved to Order Processing
     */
    private static void handleOrderProcessing(Set<Id> opportunityIds) {
        // Get all Hardware IDs linked to these Opportunities via QuoteLineGroups
        Set<Id> hardwareIds = new Set<Id>();

        List<QuoteLineGroup> groups = [
            SELECT Id, Hardware__c
            FROM QuoteLineGroup
            WHERE Quote.OpportunityId IN :opportunityIds
            AND Hardware__c != null
        ];

        for (QuoteLineGroup grp : groups) {
            hardwareIds.add(grp.Hardware__c);
        }

        if (hardwareIds.isEmpty()) {
            return;
        }

        // Query Hardware records directly and update those with 'Quoting' status
        List<Hardware__c> hardwareToUpdate = [
            SELECT Id, Status__c
            FROM Hardware__c
            WHERE Id IN :hardwareIds
            AND Status__c = :STATUS_QUOTING
        ];

        for (Hardware__c hw : hardwareToUpdate) {
            hw.Status__c = STATUS_ACTIVE;
        }

        if (!hardwareToUpdate.isEmpty()) {
            update hardwareToUpdate;
        }
    }
}