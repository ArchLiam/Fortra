/**
 * @description Removes redundant Add-Assets amend-carryover New Maintenance lines from new-business
 *              quotes so exactly one native-derived maintenance line remains per license. When a New
 *              or Net-New quote pulls prior maintenance assets onto the cart, they arrive as Amend
 *              QuoteAction lines that collide with the single native-derived line (QuoteActionId
 *              null); those Amend copies are removed only when a native keeper for the same product
 *              already exists, so a quote is never left with zero maintenance. Renewal, amendment,
 *              cancellation, and upsell quotes are out of scope.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class NewMaintenanceDedupeService {

    @TestVisible
    private static final String PRODUCT_TYPE_NEW_MAINTENANCE = 'New Maintenance';
    @TestVisible
    private static final String AMEND_QUOTE_ACTION_TYPE = 'Amend';
    @TestVisible
    private static final Set<String> NEW_BUSINESS_QUOTE_TYPES = new Set<String>{ 'New', 'Net-New' };

    private static final Integer TEXT_MAX_LONG = 32768;
    private static final Integer TXN_MAX = 40;

    @TestVisible
    private static Boolean throwOnDeleteForTest = false;

    /**
     * @description Removes Amend carryover New Maintenance duplicates from the given quotes, keeping
     *              the native-derived line. No-op on renewal/amendment quotes and when no native
     *              keeper is present. Best-effort post-persist cleanup: a failure is logged as
     *              telemetry and the duplicates are left for a later event rather than aborting the
     *              sibling renewal cleanup or corrupting the cart.
     * @param quoteIds The quotes to evaluate; scope filtering is applied internally.
     */
    public static void dedupeForQuotes(Set<Id> quoteIds) {
        if (quoteIds == null || quoteIds.isEmpty()) {
            return;
        }

        try {
            Set<Id> newBusinessQuoteIds = resolveNewBusinessQuoteIds(quoteIds);
            if (newBusinessQuoteIds.isEmpty()) {
                return;
            }

            List<QuoteLineItem> maintenanceLines = [
                SELECT Id, QuoteId, Product2Id, QuoteActionId, QuoteAction.Type
                FROM QuoteLineItem
                WHERE QuoteId IN :newBusinessQuoteIds
                  AND Product2.Fortra_Product_Type__c = :PRODUCT_TYPE_NEW_MAINTENANCE
            ];
            if (maintenanceLines.isEmpty()) {
                return;
            }

            List<Id> deleteIds = collectDuplicateLineIds(maintenanceLines);
            if (deleteIds.isEmpty()) {
                return;
            }

            List<QuoteLineItem> linesToDelete = new List<QuoteLineItem>();
            for (Id lineId : deleteIds) {
                linesToDelete.add(new QuoteLineItem(Id = lineId));
            }
            if (throwOnDeleteForTest) {
                throw new MaintenanceDedupeException('Forced failure to exercise the telemetry path');
            }
            delete linesToDelete;
        } catch (Exception e) {
            publishFailure(new MaintenanceDedupeException('dedupeForQuotes failed', e), e);
        }
    }

    /**
     * @description Publishes best-effort dedupe-failure telemetry through the central publisher so
     *              the degrade stays visible without aborting the cleanup; the typed wrapper
     *              classifies the entry and the root cause supplies the stack.
     * @param dedupeError The typed wrapper exception classifying the failure.
     * @param cause The underlying exception whose stack trace is recorded.
     */
    private static void publishFailure(Exception dedupeError, Exception cause) {
        String requestId;
        try {
            requestId = System.Request.getCurrent().getRequestId();
        } catch (Exception ignore) {
            requestId = null;
        }
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c = 'NewMaintenanceDedupeService',
            Severity__c = 'Error',
            Exception_Type__c = dedupeError.getTypeName(),
            Message__c = truncate(dedupeError.getMessage(), TEXT_MAX_LONG),
            Stack_Trace__c = truncate(cause.getStackTraceString(), TEXT_MAX_LONG),
            Transaction_Id__c = truncate(requestId, TXN_MAX),
            Occurred_At__c = System.now()
        ));
    }

    /**
     * @description Clips a value to a column limit, passing null through unchanged.
     * @param value The string to clip; may be null.
     * @param maxLen The maximum number of characters to retain.
     * @return The value when null or within the limit, otherwise its leading substring.
     */
    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }

    /**
     * @description Selects the Amend carryover duplicate line Ids to delete — only where a
     *              native-derived keeper (QuoteActionId null) exists for the same quote and product.
     *              Pure: no SOQL or DML.
     * @param maintenanceLines The New Maintenance lines on the eligible quotes.
     * @return The Ids of the Amend carryover duplicates safe to delete.
     */
    @TestVisible
    private static List<Id> collectDuplicateLineIds(List<QuoteLineItem> maintenanceLines) {
        Set<String> keeperKeys = new Set<String>();
        for (QuoteLineItem line : maintenanceLines) {
            if (line.QuoteActionId == null) {
                keeperKeys.add(groupKey(line));
            }
        }

        List<Id> deleteIds = new List<Id>();
        for (QuoteLineItem line : maintenanceLines) {
            if (line.QuoteActionId == null) {
                continue; // keeper — never delete the native-derived line
            }
            Boolean isAmendCarryover = line.QuoteAction != null
                && line.QuoteAction.Type == AMEND_QUOTE_ACTION_TYPE;
            if (isAmendCarryover && keeperKeys.contains(groupKey(line))) {
                deleteIds.add(line.Id);
            }
        }
        return deleteIds;
    }

    /**
     * @description Builds the quote-and-product grouping key used to pair carryover duplicates with
     *              their native-derived keeper.
     * @param line The maintenance line to key.
     * @return The composite quote + product key.
     */
    @TestVisible
    private static String groupKey(QuoteLineItem line) {
        return String.valueOf(line.QuoteId) + '|' + String.valueOf(line.Product2Id);
    }

    /**
     * @description Narrows the candidate quotes to new-business (New / Net-New) quotes, which are the
     *              only ones eligible for dedupe.
     * @param quoteIds The candidate quote Ids.
     * @return The subset that are New or Net-New quotes.
     */
    @TestVisible
    private static Set<Id> resolveNewBusinessQuoteIds(Set<Id> quoteIds) {
        Set<Id> newBusinessQuoteIds = new Set<Id>();
        for (Quote quote : [
            SELECT Id
            FROM Quote
            WHERE Id IN :quoteIds
              AND Quote_Type__c IN :NEW_BUSINESS_QUOTE_TYPES
        ]) {
            newBusinessQuoteIds.add(quote.Id);
        }
        return newBusinessQuoteIds;
    }
}
