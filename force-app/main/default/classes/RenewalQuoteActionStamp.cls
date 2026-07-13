/**
 * @description Before-insert handler that mints a Type='Renew' QuoteAction for configurator-auto-added
 *              renewal-maintenance quote lines that lack one, anchoring it to the customer's owned
 *              New Maintenance (or Perpetual) asset and stamping QuoteActionId on the in-memory line so
 *              the line is born a priced Renew node and commits the correct COLA net instead of freezing.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalQuoteActionStamp {

    public static Boolean bypass = false;                 // admin/test/experiment kill-switch
    private static Boolean isProcessing = false;          // recursion guard

    private static final String FPT_RENEWAL_MAINT  = 'Renewal Maintenance';
    private static final String FPT_NEW_MAINT       = 'New Maintenance';
    private static final String FPT_PERPETUAL       = 'Perpetual';
    private static final String QUOTE_TYPE_RENEWAL  = 'Renewal';
    private static final String QA_TYPE_RENEW       = 'Renew';

    /**
     * @description BEFORE-insert entry point. Synthesizes a Renew QuoteAction for QA-less
     *              renewal-maintenance lines and sets QLI.QuoteActionId on the in-memory record,
     *              so the line is born a priced "Renew" node (handleBeforeInsert prices it born-net).
     * @param newLines The QuoteLineItem records being inserted, mutated in place with QuoteActionId.
     */
    public static void synthesizeRenewQuoteActions(List<QuoteLineItem> newLines) {
        if (bypass || isProcessing || newLines == null || newLines.isEmpty()) {
            return;
        }

        // Collect QA-less candidates + their product/quote keys (before insert: no Ids yet).
        List<QuoteLineItem> candidates = new List<QuoteLineItem>();
        Set<Id> pbeIds = new Set<Id>();
        Set<Id> product2Ids = new Set<Id>();
        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem qli : newLines) {
            if (qli.QuoteActionId == null && qli.QuoteId != null) {
                candidates.add(qli);
                if (qli.PricebookEntryId != null) pbeIds.add(qli.PricebookEntryId);
                if (qli.Product2Id != null) product2Ids.add(qli.Product2Id);
                quoteIds.add(qli.QuoteId);
            }
        }
        if (candidates.isEmpty()) {
            return;
        }

        // Resolve Product2 (Fortra_Product_Type__c, Solution_Category__c) via Product2Id and/or PBE.
        Map<Id, Product2> prodById = new Map<Id, Product2>([
            SELECT Id, Fortra_Product_Type__c, Solution_Category__c
            FROM Product2 WHERE Id IN :product2Ids
        ]);
        Map<Id, Product2> prodByPbe = new Map<Id, Product2>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2.Id, Product2.Fortra_Product_Type__c, Product2.Solution_Category__c
            FROM PricebookEntry WHERE Id IN :pbeIds
        ]) {
            prodByPbe.put(pbe.Id, pbe.Product2);
        }

        // Resolve renewal quotes (account + type).
        Map<Id, Quote> quoteById = new Map<Id, Quote>([
            SELECT Id, AccountId, Quote_Type__c FROM Quote WHERE Id IN :quoteIds
        ]);

        // Which candidates are renewal-maintenance on a renewal quote? Gather accounts + categories.
        // NOTE: never key a Map by the QuoteLineItem sObject — identical before-insert rows are
        // value-equal and collapse to one entry. Keep `eligible` as a List and recompute per line.
        List<QuoteLineItem> eligible = new List<QuoteLineItem>();
        Set<Id> accountIds = new Set<Id>();
        Set<String> categories = new Set<String>();
        for (QuoteLineItem qli : candidates) {
            Product2 prod = resolveProduct(qli, prodById, prodByPbe);
            Quote q = quoteById.get(qli.QuoteId);
            if (prod == null || q == null) continue;
            if (prod.Fortra_Product_Type__c != FPT_RENEWAL_MAINT) continue;
            if (q.Quote_Type__c != QUOTE_TYPE_RENEWAL) continue;
            if (q.AccountId == null || prod.Solution_Category__c == null) continue;
            eligible.add(qli);
            accountIds.add(q.AccountId);
            categories.add(prod.Solution_Category__c);
        }
        if (eligible.isEmpty()) {
            return;
        }

        // Resolve the source asset per (account, solution category): prefer New Maintenance, else Perpetual.
        Map<String, Asset> sourceByAcctCat = resolveSourceAssets(accountIds, categories);
        if (sourceByAcctCat.isEmpty()) {
            return;
        }

        // Reuse existing Renew QuoteActions per (quote, asset); plan new ones.
        Map<String, Id> qaByQuoteAsset = new Map<String, Id>();
        for (QuoteAction qa : [
            SELECT Id, QuoteId, SourceAssetId
            FROM QuoteAction
            WHERE QuoteId IN :quoteIds AND Type = :QA_TYPE_RENEW AND SourceAssetId != NULL
        ]) {
            qaByQuoteAsset.put(qa.QuoteId + '|' + qa.SourceAssetId, qa.Id);
        }
        Map<String, QuoteAction> toCreate = new Map<String, QuoteAction>();
        for (QuoteLineItem qli : eligible) {
            Asset src = resolveAssetForLine(qli, prodById, prodByPbe, quoteById, sourceByAcctCat);
            if (src == null) continue;
            String key = qli.QuoteId + '|' + src.Id;
            if (!qaByQuoteAsset.containsKey(key) && !toCreate.containsKey(key)) {
                toCreate.put(key, new QuoteAction(
                    QuoteId = qli.QuoteId, Type = QA_TYPE_RENEW, SourceAssetId = src.Id));
            }
        }

        isProcessing = true;
        try {
            if (!toCreate.isEmpty()) {
                insert toCreate.values();
                for (QuoteAction qa : toCreate.values()) {
                    qaByQuoteAsset.put(qa.QuoteId + '|' + qa.SourceAssetId, qa.Id);
                }
            }
            // Set QuoteActionId on each in-memory before-insert record (no QLI DML needed).
            for (QuoteLineItem qli : eligible) {
                Asset src = resolveAssetForLine(qli, prodById, prodByPbe, quoteById, sourceByAcctCat);
                if (src == null) continue;
                Id qaId = qaByQuoteAsset.get(qli.QuoteId + '|' + src.Id);
                if (qaId != null) {
                    qli.QuoteActionId = qaId;
                }
            }
        } finally {
            isProcessing = false;
        }
    }

    /**
     * @description Resolves the source asset for a line's (account, solution category) pairing, or null.
     * @param qli The quote line item to resolve the source asset for.
     * @param byId Product2 records keyed by Product2Id.
     * @param byPbe Product2 records keyed by PricebookEntryId.
     * @param quoteById Quote records keyed by QuoteId, supplying account context.
     * @param sourceByAcctCat Preferred source assets keyed by accountId|solutionCategory.
     * @return The preferred owned Asset for the line, or null when it cannot be resolved.
     */
    private static Asset resolveAssetForLine(QuoteLineItem qli, Map<Id, Product2> byId, Map<Id, Product2> byPbe,
                                             Map<Id, Quote> quoteById, Map<String, Asset> sourceByAcctCat) {
        Product2 prod = resolveProduct(qli, byId, byPbe);
        Quote q = quoteById.get(qli.QuoteId);
        if (prod == null || q == null || q.AccountId == null || prod.Solution_Category__c == null) {
            return null;
        }
        return sourceByAcctCat.get(q.AccountId + '|' + prod.Solution_Category__c);
    }

    /**
     * @description Resolves the Product2 for a line, preferring Product2Id and falling back to its PricebookEntry.
     * @param qli The quote line item to resolve the product for.
     * @param byId Product2 records keyed by Product2Id.
     * @param byPbe Product2 records keyed by PricebookEntryId.
     * @return The resolved Product2, or null when neither lookup matches.
     */
    private static Product2 resolveProduct(QuoteLineItem qli, Map<Id, Product2> byId, Map<Id, Product2> byPbe) {
        if (qli.Product2Id != null && byId.containsKey(qli.Product2Id)) {
            return byId.get(qli.Product2Id);
        }
        if (qli.PricebookEntryId != null && byPbe.containsKey(qli.PricebookEntryId)) {
            return byPbe.get(qli.PricebookEntryId);
        }
        return null;
    }

    /**
     * @description Per (accountId|solutionCategory), the preferred owned asset to anchor the renewal:
     *              New Maintenance (RNM) if owned, else Perpetual. Both must have a Price.
     * @param accountIds The account Ids whose owned assets to consider.
     * @param categories The solution categories to match on.
     * @return Preferred source Assets keyed by accountId|solutionCategory.
     */
    private static Map<String, Asset> resolveSourceAssets(Set<Id> accountIds, Set<String> categories) {
        Map<String, Asset> newMaint = new Map<String, Asset>();
        Map<String, Asset> perpetual = new Map<String, Asset>();
        for (Asset a : [
            SELECT Id, AccountId, Price, Product2.Fortra_Product_Type__c, Product2.Solution_Category__c
            FROM Asset
            WHERE AccountId IN :accountIds
              AND Product2.Solution_Category__c IN :categories
              AND Product2.Fortra_Product_Type__c IN (:FPT_NEW_MAINT, :FPT_PERPETUAL)
              AND Price != NULL
            ORDER BY CreatedDate DESC
        ]) {
            String key = a.AccountId + '|' + a.Product2.Solution_Category__c;
            if (a.Product2.Fortra_Product_Type__c == FPT_NEW_MAINT) {
                if (!newMaint.containsKey(key)) newMaint.put(key, a);
            } else {
                if (!perpetual.containsKey(key)) perpetual.put(key, a);
            }
        }
        Map<String, Asset> preferred = new Map<String, Asset>(perpetual);
        preferred.putAll(newMaint);
        return preferred;
    }
}