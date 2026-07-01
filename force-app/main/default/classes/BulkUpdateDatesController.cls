/**
 * @description Controller for bulk updating subscription dates on Quote Line Items
 * @author Marc DeBrey
 * @since 2026-02
 *
 * Supports two update modes:
 * - DATE_RANGE: User specifies start and end dates, term is calculated
 * - DATE_AND_TERM: User specifies start date and term, end date is calculated
 *
 * Only Term-Defined (subscription) line items are eligible for date updates.
 * One-Time and Evergreen selling models are excluded.
 */
public with sharing class BulkUpdateDatesController {

    /**
     * @description Query eligible quote lines for bulk date update
     * Only returns QuoteLineItems with SellingModelType = 'TermDefined'
     * @param quoteId The Quote record ID
     * @return List of eligible QuoteLineItem records
     */
    @AuraEnabled(cacheable=true)
    public static List<QuoteLineItem> getEligibleQuoteLines(Id quoteId) {
        try {
            return [
                SELECT Id, Product2.Name, StartDate, EndDate, SubscriptionTerm,
                       SellingModelType, QuoteLineGroupId, QuoteLineGroup.Name
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
                  AND SellingModelType = 'TermDefined'
                ORDER BY QuoteLineGroup.Name NULLS LAST, Product2.Name
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving eligible quote lines: ' + e.getMessage());
        }
    }

    /**
     * @description Update subscription dates on selected quote line items and the Quote header
     * @param quoteId The Quote record ID
     * @param lineItemIds List of QuoteLineItem IDs to update
     * @param startDate The new start date
     * @param endDate The new end date (used in DATE_RANGE mode)
     * @param term The subscription term in months (used in DATE_AND_TERM mode)
     * @param updateMode 'DATE_RANGE' or 'DATE_AND_TERM'
     * @return BulkUpdateResult with success status and details
     */
    @AuraEnabled
    public static BulkUpdateResult updateQuoteLineDates(
        Id quoteId,
        List<Id> lineItemIds,
        Date startDate,
        Date endDate,
        Integer term,
        String updateMode
    ) {
        BulkUpdateResult result = new BulkUpdateResult();
        result.errors = new List<String>();

        if (lineItemIds == null || lineItemIds.isEmpty()) {
            result.success = false;
            result.message = 'No line items selected for update';
            result.updatedCount = 0;
            result.totalCount = 0;
            return result;
        }

        result.totalCount = lineItemIds.size();

        try {
            // Calculate derived values based on update mode
            Date calculatedEndDate = endDate;
            Integer calculatedTerm = term;

            if (updateMode == 'DATE_RANGE') {
                // Calculate term from date range: months between dates
                Integer daysBetween = startDate.daysBetween(endDate) + 1;
                calculatedTerm = (Integer) Math.ceil(daysBetween / 30.0);
            } else if (updateMode == 'DATE_AND_TERM') {
                // Calculate end date from start date + term
                calculatedEndDate = startDate.addMonths(term).addDays(-1);
            }

            // Update Quote header StartDate
            Quote quoteRecord = new Quote(Id = quoteId, StartDate = startDate);
            update quoteRecord;

            // Build list of QuoteLineItems to update
            List<QuoteLineItem> itemsToUpdate = new List<QuoteLineItem>();
            for (Id lineItemId : lineItemIds) {
                QuoteLineItem item = new QuoteLineItem(
                    Id = lineItemId,
                    StartDate = startDate,
                    EndDate = calculatedEndDate,
                    SubscriptionTerm = calculatedTerm
                );
                itemsToUpdate.add(item);
            }

            // Use partial success to avoid all-or-nothing failures
            Database.SaveResult[] saveResults = Database.update(itemsToUpdate, false);

            Integer successCount = 0;
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : saveResults[i].getErrors()) {
                        result.errors.add('Line ' + (i + 1) + ': ' + err.getMessage());
                    }
                }
            }

            result.updatedCount = successCount;
            result.success = successCount > 0;

            // Recalculate Latest_Effective_End_Date__c from all quote lines
            if (successCount > 0) {
                AggregateResult[] maxEndDate = [
                    SELECT MAX(EndDate) maxEnd
                    FROM QuoteLineItem
                    WHERE QuoteId = :quoteId
                ];
                Date latestEnd = (Date) maxEndDate[0].get('maxEnd');
                Quote quoteUpdate = new Quote(
                    Id = quoteId,
                    Latest_Effective_End_Date__c = latestEnd
                );
                update quoteUpdate;
            }

            if (successCount == result.totalCount) {
                result.message = successCount + ' of ' + result.totalCount + ' lines updated successfully';
            } else if (successCount > 0) {
                result.message = successCount + ' of ' + result.totalCount + ' lines updated. Some lines had errors.';
            } else {
                result.message = 'No lines were updated due to errors';
                result.success = false;
            }

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error updating quote line dates: ' + e.getMessage();
            result.updatedCount = 0;
        }

        return result;
    }

    /**
     * @description Wrapper class for bulk update results
     */
    public class BulkUpdateResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> errors;
    }
}