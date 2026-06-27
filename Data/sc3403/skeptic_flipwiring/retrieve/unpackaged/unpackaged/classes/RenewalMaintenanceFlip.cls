/**
 * @description SC-3346 / SC-3404 — Renewal-maintenance pricing fix (PROVEN 2026-06-15).
 *
 *   ROOT CAUSE: new-business maintenance (PIA-PIA-RNM-PIAMBK) is a One-Time selling model, so the
 *   asset the customer owns renews via platform initiateRenewal as QuoteAction.Type='No Change',
 *   Quantity 0 — which never enters the COLA renewal price path (the gate requires
 *   SalesTransactionActionType='Renew'). The legacy design then deleted that owned-asset carryover
 *   and substituted an asset-less Renewal-Maintenance (RRM) line that can never resolve a pricing
 *   contributor, so the renewal-maintenance line froze at the wrong/zero net.
 *
 *   FIX (proven live, NetUnitPrice committed 67.38 = asset net LTP 62.48 x 1.0785 COLA): instead of
 *   deleting the owned-maintenance carryover, FLIP its QuoteAction 'No Change' -> 'Renew' and set the
 *   renew quantity (StartQuantity=0, Quantity = asset quantity). The native renewal pricing then
 *   applies the COLA uplift to last year's net and commits it. No RRM asset, no PBEDP, no
 *   selling-model change required.
 *
 *   USAGE: call after the renewal quote + carryover lines exist (e.g. from Fortra_Create_Renewal_Quote
 *   after createRenewalQuote), then reprice (Place Sales Transaction) so the engine commits the net.
 *   Pairs with disabling the Year-2 AutoAdd PCR (14OWC0000022Eyb2AE) so no asset-less RRM line is added.
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