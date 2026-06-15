/**
 * @description Removes asset-renewal carryover lines from renewal quotes once Renewal
 *              Maintenance is present (config rule / TLE AutoAdd).
 *              Platform Asset Renew copies Year 1 license + New Maintenance assets;
 *              Year 2+ quotes should bill Renewal Maintenance only (PIA-PIA-RRM-PIAM).
 *
 *              Guard: no delete until the quote already has a Renewal Maintenance line
 *              (existing or in the same insert batch), so platform asset copy is not
 *              stripped before the Year 2 config rule runs.
 *
 *              Cleanup is enqueued (Queueable) from the trigger so deletes do not run
 *              inside the same Place Sales Transaction persist as TLE Configure + Save.
 */
public with sharing class RenewalQuoteLineHandler {

    public static final String PRODUCT_TYPE_NEW_MAINTENANCE = 'New Maintenance';
    public static final String PRODUCT_TYPE_RENEWAL_MAINTENANCE = 'Renewal Maintenance';
    public static final String PRODUCT_TYPE_PERPETUAL = 'Perpetual';

    @TestVisible
    private static final Set<String> CARRYOVER_PRODUCT_TYPES = new Set<String>{
        PRODUCT_TYPE_NEW_MAINTENANCE,
        PRODUCT_TYPE_PERPETUAL
    };

    /**
     * @description Called from QuoteLineItem after insert. Defers cleanup until PST completes.
     */
    public static void enqueueCarryoverCleanup(List<QuoteLineItem> newLines) {
        if (newLines == null || newLines.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = collectQuoteIds(newLines);
        if (quoteIds.isEmpty()) {
            return;
        }

        if (Test.isRunningTest()) {
            removeNewMaintenanceCarryoverForQuotes(quoteIds, newLines);
            return;
        }

        System.enqueueJob(new RenewalQuoteLineCleanupQueueable(quoteIds));
    }

    /**
     * @description Direct entry for tests and manual invocation.
     */
    public static void removeNewMaintenanceCarryover(List<QuoteLineItem> newLines) {
        if (newLines == null || newLines.isEmpty()) {
            return;
        }
        Set<Id> quoteIds = collectQuoteIds(newLines);
        if (!quoteIds.isEmpty()) {
            removeNewMaintenanceCarryoverForQuotes(quoteIds, newLines);
        }
    }

    /**
     * @description Removes carryover lines once Renewal Maintenance exists on the quote.
     */
    public static void removeNewMaintenanceCarryoverForQuotes(Set<Id> quoteIds) {
        removeNewMaintenanceCarryoverForQuotes(quoteIds, new List<QuoteLineItem>());
    }

    @TestVisible
    private static void removeNewMaintenanceCarryoverForQuotes(
        Set<Id> quoteIds,
        List<QuoteLineItem> insertedLines
    ) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        Set<Id> renewalQuoteIds = resolveRenewalQuoteIds(quoteIds);
        if (renewalQuoteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> contextLines = insertedLines == null
            ? new List<QuoteLineItem>()
            : insertedLines;

        Set<Id> quotesWithRenewalMaint = findQuotesWithRenewalMaintenance(
            renewalQuoteIds,
            contextLines
        );
        if (quotesWithRenewalMaint.isEmpty()) {
            return;
        }

        Set<Id> pbeIds = new Set<Id>();
        for (QuoteLineItem line : contextLines) {
            if (quotesWithRenewalMaint.contains(line.QuoteId) && line.PricebookEntryId != null) {
                pbeIds.add(line.PricebookEntryId);
            }
        }

        Map<Id, String> productTypeByPbeId = loadProductTypeByPbeId(pbeIds);
        Set<Id> deleteIds = new Set<Id>();

        for (QuoteLineItem line : contextLines) {
            if (!quotesWithRenewalMaint.contains(line.QuoteId) || line.Id == null) {
                continue;
            }
            if (isCarryoverProductType(productTypeByPbeId.get(line.PricebookEntryId))) {
                deleteIds.add(line.Id);
            }
        }

        for (QuoteLineItem existing : [
            SELECT Id
            FROM QuoteLineItem
            WHERE QuoteId IN :quotesWithRenewalMaint
              AND Product2.Fortra_Product_Type__c IN :CARRYOVER_PRODUCT_TYPES
        ]) {
            deleteIds.add(existing.Id);
        }

        if (deleteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> linesToDelete = new List<QuoteLineItem>();
        for (Id lineId : deleteIds) {
            linesToDelete.add(new QuoteLineItem(Id = lineId));
        }
        delete linesToDelete;
    }

    private static Set<Id> collectQuoteIds(List<QuoteLineItem> lines) {
        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem line : lines) {
            if (line.QuoteId != null) {
                quoteIds.add(line.QuoteId);
            }
        }
        return quoteIds;
    }

    @TestVisible
    private static Boolean isCarryoverProductType(String productType) {
        return productType != null && CARRYOVER_PRODUCT_TYPES.contains(productType);
    }

    @TestVisible
    private static Set<Id> resolveRenewalQuoteIds(Set<Id> quoteIds) {
        Set<Id> renewalQuoteIds = new Set<Id>();
        for (Quote quote : [
            SELECT Id
            FROM Quote
            WHERE Id IN :quoteIds
              AND (
                  OriginalActionType = :QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW
                  OR Quote_Type__c = :QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
              )
        ]) {
            renewalQuoteIds.add(quote.Id);
        }
        return renewalQuoteIds;
    }

    @TestVisible
    private static Set<Id> findQuotesWithRenewalMaintenance(
        Set<Id> renewalQuoteIds,
        List<QuoteLineItem> newLines
    ) {
        Set<Id> quotesWithRenewalMaint = new Set<Id>();

        Set<Id> newPbeIds = new Set<Id>();
        for (QuoteLineItem line : newLines) {
            if (renewalQuoteIds.contains(line.QuoteId) && line.PricebookEntryId != null) {
                newPbeIds.add(line.PricebookEntryId);
            }
        }

        Map<Id, String> productTypeByPbeId = loadProductTypeByPbeId(newPbeIds);
        for (QuoteLineItem line : newLines) {
            if (!renewalQuoteIds.contains(line.QuoteId)) {
                continue;
            }
            if (productTypeByPbeId.get(line.PricebookEntryId) == PRODUCT_TYPE_RENEWAL_MAINTENANCE) {
                quotesWithRenewalMaint.add(line.QuoteId);
            }
        }

        for (QuoteLineItem existing : [
            SELECT QuoteId
            FROM QuoteLineItem
            WHERE QuoteId IN :renewalQuoteIds
              AND Product2.Fortra_Product_Type__c = :PRODUCT_TYPE_RENEWAL_MAINTENANCE
        ]) {
            quotesWithRenewalMaint.add(existing.QuoteId);
        }

        return quotesWithRenewalMaint;
    }

    private static Map<Id, String> loadProductTypeByPbeId(Set<Id> pbeIds) {
        Map<Id, String> productTypeByPbeId = new Map<Id, String>();
        if (pbeIds.isEmpty()) {
            return productTypeByPbeId;
        }
        for (PricebookEntry pbe : [
            SELECT Id, Product2.Fortra_Product_Type__c
            FROM PricebookEntry
            WHERE Id IN :pbeIds
        ]) {
            productTypeByPbeId.put(pbe.Id, pbe.Product2.Fortra_Product_Type__c);
        }
        return productTypeByPbeId;
    }
}
