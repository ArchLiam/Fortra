/**
 * @description Normalizes asset-renewed Renewal Maintenance lines so billing Quantity
 *              matches the source asset entitlement. Platform Asset Renew often creates
 *              No Change lines with Quantity 0 while StartQuantity/EndQuantity reflect
 *              the asset; DPP and persist require billing Quantity from the asset.
 *
 *              Runs in a Queueable after QuoteLineItem insert so updates do not conflict
 *              with Place Sales Transaction persist during Asset Renew.
 */
public with sharing class RenewalAssetQuantityHandler {

    public static final String QUOTE_ACTION_RENEW = 'Renew';
    public static final String QUOTE_ACTION_NO_CHANGE = 'No Change';
    public static final String PRODUCT_TYPE_RENEWAL_MAINTENANCE =
        RenewalQuoteLineHandler.PRODUCT_TYPE_RENEWAL_MAINTENANCE;

    /**
     * @description Called from QuoteLineItem after insert. Defers normalization until PST completes.
     */
    public static void enqueueQuantityNormalization(List<QuoteLineItem> newLines) {
        if (newLines == null || newLines.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = collectQuoteIds(newLines);
        if (quoteIds.isEmpty()) {
            return;
        }

        if (Test.isRunningTest()) {
            applyAssetQuantitiesForQuotes(quoteIds);
            return;
        }

        System.enqueueJob(new RenewalAssetQuantityQueueable(quoteIds));
    }

    /**
     * @description Direct entry for tests and manual invocation.
     */
    public static void applyAssetQuantitiesForQuotes(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        Set<Id> renewalQuoteIds = resolveRenewalQuoteIds(quoteIds);
        if (renewalQuoteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> candidates = [
            SELECT Id, QuoteId, Quantity, StartQuantity, EndQuantity, QuoteActionId,
                   QuoteAction.Type, QuoteAction.SourceAssetId, QuoteAction.SourceAsset.Quantity,
                   Fortra_Product_Type__c
            FROM QuoteLineItem
            WHERE QuoteId IN :renewalQuoteIds
              AND Fortra_Product_Type__c = :PRODUCT_TYPE_RENEWAL_MAINTENANCE
              AND QuoteActionId != null
              AND (Quantity = null OR Quantity <= 0)
        ];

        if (candidates.isEmpty()) {
            return;
        }

        applyNormalizationUpdates(buildNormalizationUpdates(candidates));
    }

    @TestVisible
    private static NormalizationUpdates buildNormalizationUpdates(List<QuoteLineItem> candidates) {
        NormalizationUpdates updates = new NormalizationUpdates();

        if (candidates == null || candidates.isEmpty()) {
            return updates;
        }

        for (QuoteLineItem qli : candidates) {
            Decimal sourceQuantity = resolveSourceQuantity(qli);
            if (!needsQuantityNormalization(qli, sourceQuantity)) {
                continue;
            }

            String actionType = qli.QuoteAction?.Type;
            if (actionType == QUOTE_ACTION_NO_CHANGE) {
                updates.quoteActionsById.put(
                    qli.QuoteActionId,
                    new QuoteAction(Id = qli.QuoteActionId, Type = QUOTE_ACTION_RENEW)
                );
            } else if (actionType != QUOTE_ACTION_RENEW) {
                continue;
            }

            updates.linesToUpdate.add(new QuoteLineItem(
                Id = qli.Id,
                Quantity = sourceQuantity,
                StartQuantity = 0
            ));
        }

        return updates;
    }

    private static void applyNormalizationUpdates(NormalizationUpdates updates) {
        if (updates == null) {
            return;
        }
        if (!updates.quoteActionsById.isEmpty()) {
            update updates.quoteActionsById.values();
        }
        if (!updates.linesToUpdate.isEmpty()) {
            update updates.linesToUpdate;
        }
    }

    @TestVisible
    private class NormalizationUpdates {
        public Map<Id, QuoteAction> quoteActionsById { get; private set; }
        public List<QuoteLineItem> linesToUpdate { get; private set; }

        private NormalizationUpdates() {
            quoteActionsById = new Map<Id, QuoteAction>();
            linesToUpdate = new List<QuoteLineItem>();
        }
    }

    @TestVisible
    private static Boolean needsQuantityNormalization(QuoteLineItem qli, Decimal sourceQuantity) {
        if (qli == null || sourceQuantity == null || sourceQuantity <= 0) {
            return false;
        }
        if (qli.Fortra_Product_Type__c != PRODUCT_TYPE_RENEWAL_MAINTENANCE) {
            return false;
        }
        if (qli.QuoteActionId == null) {
            return false;
        }

        Decimal quantity = qli.Quantity == null ? 0 : qli.Quantity;
        return quantity <= 0;
    }

    @TestVisible
    private static Decimal resolveSourceQuantity(QuoteLineItem qli) {
        if (qli == null) {
            return null;
        }

        return resolveSourceQuantity(
            qli.QuoteAction?.SourceAsset?.Quantity,
            qli.EndQuantity,
            qli.StartQuantity
        );
    }

    @TestVisible
    private static Decimal resolveSourceQuantity(
        Decimal assetQuantity,
        Decimal endQuantity,
        Decimal startQuantity
    ) {
        if (assetQuantity != null && assetQuantity > 0) {
            return assetQuantity;
        }
        if (endQuantity != null && endQuantity > 0) {
            return endQuantity;
        }
        if (startQuantity != null && startQuantity > 0) {
            return startQuantity;
        }
        return null;
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
}