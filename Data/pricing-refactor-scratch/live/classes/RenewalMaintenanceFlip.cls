/**
 * @description Flips owned New-Maintenance renewal carryover lines from a 'No Change' QuoteAction to
 *              'Renew' and sets the renew quantity from the source asset, so a subsequent reprice
 *              applies the COLA uplift to last year's net and commits the correct renewal-maintenance
 *              price instead of freezing at zero. Exposes a Flow-invocable entry point and a bulk-safe
 *              Apex method; the caller reprices the quote afterward to commit the net.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class RenewalMaintenanceFlip {

    @TestVisible private static final String PRODUCT_TYPE_NEW_MAINTENANCE = 'New Maintenance';
    @TestVisible private static final String QA_TYPE_NO_CHANGE = 'No Change';
    @TestVisible private static final String QA_TYPE_RENEW = 'Renew';
    private static final String QUOTE_TYPE_RENEWAL = 'Renewal';
    private static final String ORIGINAL_ACTION_RENEW = 'Renew';

    /**
     * @description Flow request wrapper (one renewal quote per call; bulk-safe across calls).
     */
    public class FlipRequest {
        @InvocableVariable(label='Renewal Quote Id' required=true)
        public Id quoteId;
    }

    /**
     * @description Flow entry point — flip the owned-maintenance carryover on the given renewal quotes
     *              to Renew so the subsequent reprice commits the COLA uplift.
     * @param requests Flow request wrappers, each naming one renewal quote to flip
     */
    @InvocableMethod(
        label='Renew Maintenance Carryover'
        description='Flip No-Change owned-maintenance renewal carryover lines to Renew so they price the COLA uplift. Reprice the quote after.'
    )
    public static void flipInvocable(List<FlipRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Id> quoteIds = new Set<Id>();
        for (FlipRequest req : requests) {
            if (req != null && req.quoteId != null) {
                quoteIds.add(req.quoteId);
            }
        }
        flipToRenew(quoteIds);
    }

    /**
     * @description Flip No-Change New-Maintenance carryover lines on renewal quotes to Renew, set the
     *              renew quantity from the source asset. Bulk-safe; idempotent (only touches No-Change).
     * @param quoteIds Ids of the renewal quotes whose carryover maintenance lines should be flipped
     */
    public static void flipToRenew(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        Set<Id> renewalQuoteIds = new Set<Id>();
        for (Quote q : [
            SELECT Id FROM Quote
            WHERE Id IN :quoteIds
              AND (Quote_Type__c = :QUOTE_TYPE_RENEWAL OR OriginalActionType = :ORIGINAL_ACTION_RENEW)
        ]) {
            renewalQuoteIds.add(q.Id);
        }
        if (renewalQuoteIds.isEmpty()) {
            return;
        }

        List<QuoteLineItem> lines = [
            SELECT Id, QuoteActionId, QuoteAction.SourceAsset.Quantity
            FROM QuoteLineItem
            WHERE QuoteId IN :renewalQuoteIds
              AND Product2.Fortra_Product_Type__c = :PRODUCT_TYPE_NEW_MAINTENANCE
              AND QuoteActionId != NULL
              AND QuoteAction.Type = :QA_TYPE_NO_CHANGE
        ];
        if (lines.isEmpty()) {
            return;
        }

        List<QuoteAction> qaUpdates = new List<QuoteAction>();
        List<QuoteLineItem> lineUpdates = new List<QuoteLineItem>();
        for (QuoteLineItem line : lines) {
            qaUpdates.add(new QuoteAction(Id = line.QuoteActionId, Type = QA_TYPE_RENEW));
            Decimal renewQty = (line.QuoteAction.SourceAsset != null
                                && line.QuoteAction.SourceAsset.Quantity != null
                                && line.QuoteAction.SourceAsset.Quantity > 0)
                ? line.QuoteAction.SourceAsset.Quantity : 1;
            // A Renew line requires StartQuantity=0/null; the renew quantity is the asset quantity.
            lineUpdates.add(new QuoteLineItem(Id = line.Id, StartQuantity = 0, Quantity = renewQty));
        }
        update qaUpdates;
        update lineUpdates;
    }
}