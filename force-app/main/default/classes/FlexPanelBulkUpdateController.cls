/**
 * @description Controller for FlexPanel bulk update functionality
 * @author Fortra Revenue Cloud Implementation Team
 * @date 2025
 */
global with sharing class FlexPanelBulkUpdateController {
    
    /**
     * @description Remote action for bulk updating dates (for both Visualforce and LWC)
     * @param selectedLineIds List of selected quote line IDs
     * @param startDate Start date for all lines
     * @param updateMode Either DATE_AND_TERM or DATE_RANGE
     * @param term Term in months (for DATE_AND_TERM mode)
     * @param endDate End date (for DATE_RANGE mode)
     * @return Map containing success status and details
     */
    @RemoteAction
    @AuraEnabled
    global static Map<String, Object> bulkUpdateDatesRemote(List<String> selectedLineIds, 
                                                            String startDate, 
                                                            String updateMode,
                                                            Integer term,
                                                            String endDate) {
        Map<String, Object> input = new Map<String, Object>();
        input.put('selectedLineIds', selectedLineIds);
        input.put('startDate', startDate);
        input.put('updateMode', updateMode);
        input.put('term', term);
        input.put('endDate', endDate);
        
        Map<String, Object> output = new Map<String, Object>();
        FlexPanelBulkUpdateController controller = new FlexPanelBulkUpdateController();
        controller.bulkUpdateDates(input, output);
        
        return output;
    }
    
    /**
     * @description Main method called by OmniScript/FlexCard
     * @param methodName The method to invoke
     * @param input Input parameters as Map
     * @param output Output parameters as Map
     * @param options Additional options
     * @return Boolean indicating success
     */
    global Boolean invokeMethod(String methodName, Map<String, Object> input, 
                                Map<String, Object> output, Map<String, Object> options) {
        Boolean success = true;
        
        try {
            if (methodName == 'bulkUpdateDates') {
                bulkUpdateDates(input, output);
            } else if (methodName == 'getSelectedLineIds') {
                getSelectedLineIds(input, output);
            } else if (methodName == 'validateQuoteStatus') {
                validateQuoteStatus(input, output);
            } else {
                success = false;
                output.put('error', 'Method not found: ' + methodName);
            }
        } catch (Exception e) {
            success = false;
            output.put('error', e.getMessage());
            output.put('stackTrace', e.getStackTraceString());
        }
        
        return success;
    }
    
    /**
     * @description Bulk update dates for selected quote lines
     * @param input Input parameters
     * @param output Output parameters
     */
    private void bulkUpdateDates(Map<String, Object> input, Map<String, Object> output) {
        // Extract parameters
        List<String> selectedLineIds = getStringList(input, 'selectedLineIds');
        Date startDate = getDateValue(input, 'startDate');
        String updateMode = (String)input.get('updateMode');
        Integer term = getIntegerValue(input, 'term');
        Date endDate = getDateValue(input, 'endDate');
        
        // Validate inputs
        if (selectedLineIds == null || selectedLineIds.isEmpty()) {
            output.put('success', false);
            output.put('errorMessage', 'No lines selected. Please select at least one quote line item.');
            return;
        }
        
        if (startDate == null) {
            output.put('success', false);
            output.put('errorMessage', 'Start Date is required.');
            return;
        }
        
        // Calculate end date or term based on mode
        if (updateMode == 'DATE_AND_TERM') {
            if (term == null || term <= 0) {
                output.put('success', false);
                output.put('errorMessage', 'Term must be a positive number.');
                return;
            }
            endDate = startDate.addMonths(term).addDays(-1);
        } else if (updateMode == 'DATE_RANGE') {
            if (endDate == null) {
                output.put('success', false);
                output.put('errorMessage', 'End Date is required when using Date Range mode.');
                return;
            }
            if (endDate <= startDate) {
                output.put('success', false);
                output.put('errorMessage', 'End Date must be after Start Date.');
                return;
            }
            Integer daysDiff = startDate.daysBetween(endDate) + 1;
            term = (Integer)Math.ceil(daysDiff / 30.0);
        } else {
            // Default to DATE_AND_TERM with 12 months
            term = term != null ? term : 12;
            endDate = startDate.addMonths(term).addDays(-1);
        }
        
        // Query quote lines
        List<QuoteLineItem> lines = [
            SELECT Id,
                   Quote.Status,
                   Product2Id,
                   Product2.Name,
                   StartDate,
                   EndDate,
                   SubscriptionTerm
            FROM QuoteLineItem
            WHERE Id IN :selectedLineIds
            // WITH USER_MODE //SECURITY_ENFORCED
        ];
        
        if (lines.isEmpty()) {
            output.put('success', false);
            output.put('errorMessage', 'Selected quote lines could not be found or you do not have access to them.');
            return;
        }
        
        // Check quote status
        String quoteStatus = lines[0].Quote.Status;
        if (quoteStatus == 'Approved' || quoteStatus == 'Accepted' || quoteStatus == 'Presented') {
            output.put('success', false);
            output.put('errorMessage', 'Cannot update dates on a quote with status: ' + quoteStatus);
            return;
        }
        
        // Process lines
        List<QuoteLineItem> linesToUpdate = new List<QuoteLineItem>();
        List<String> skippedProducts = new List<String>();
        
        for (QuoteLineItem line : lines) {
            // Skip one-time products
            if (line.SubscriptionTerm == null || line.SubscriptionTerm == 0) {
                skippedProducts.add(line.Product2.Name);
                continue;
            }
            
            // Update dates and term
            line.StartDate = startDate;
            line.EndDate = endDate;
            line.SubscriptionTerm = term;
            
            linesToUpdate.add(line);
        }
        
        // Perform update if there are lines to update
        if (!linesToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(linesToUpdate, false);
            
            Integer successCount = 0;
            List<String> errors = new List<String>();
            
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errors.add(err.getMessage());
                    }
                }
            }
            
            output.put('success', true);
            output.put('successCount', successCount);
            output.put('totalProcessed', lines.size());
            output.put('skippedCount', skippedProducts.size());
            output.put('message', 'Successfully updated ' + successCount + ' of ' + linesToUpdate.size() + ' quote line(s).');
            
            if (!skippedProducts.isEmpty()) {
                output.put('warningMessage', 'Skipped ' + skippedProducts.size() + ' one-time product(s).');
            }
            
            if (!errors.isEmpty()) {
                output.put('errorDetails', errors);
            }
            
            // Publish platform event to trigger TLE refresh
            if (successCount > 0 && !lines.isEmpty()) {
                try {
                    Quote_Line_Update__e evt = new Quote_Line_Update__e();
                    evt.Quote_Id__c = lines[0].QuoteId;
                    evt.Update_Type__c = 'BULK_DATE_UPDATE';
                    evt.Lines_Updated__c = successCount;
                    
                    Database.SaveResult sr = EventBus.publish(evt);
                    if (sr.isSuccess()) {
                        System.debug('Platform event published for Quote: ' + lines[0].QuoteId);
                    }
                } catch (Exception e) {
                    System.debug('Error publishing platform event: ' + e.getMessage());
                    // Don't fail the operation if event publishing fails
                }
            }
        } else {
            output.put('success', false);
            output.put('errorMessage', 'No eligible lines to update. All selected lines are one-time products.');
        }
    }
    
    /**
     * @description Get selected line IDs from quote
     * @param quoteId Quote record ID
     * @return Map containing selected line IDs
     */
    @RemoteAction
    @AuraEnabled
    global static Map<String, Object> getSelectedLineIds(String quoteId) {
        Map<String, Object> output = new Map<String, Object>();
        
        if (String.isBlank(quoteId)) {
            output.put('success', false);
            output.put('errorMessage', 'Quote ID is required.');
            return output;
        }
        
        // TEMPORARY: Return all quote lines until TLE selection integration is complete
        // TODO: Integrate with TLE's actual selection mechanism
        List<QuoteLineItem> lines = [
            SELECT Id
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        
        List<String> lineIds = new List<String>();
        for (QuoteLineItem line : lines) {
            lineIds.add(line.Id);
        }
        
        output.put('success', true);
        output.put('selectedLineIds', lineIds);
        output.put('count', lineIds.size());
        output.put('message', 'Updating all quote lines. In future, this will update only selected lines.');
        return output;
    }
    
    /**
     * @description Get selected line IDs from TLE context (private method for invokeMethod)
     * @param input Input parameters
     * @param output Output parameters
     */
    private void getSelectedLineIds(Map<String, Object> input, Map<String, Object> output) {
        String quoteId = (String)input.get('quoteId');
        Map<String, Object> result = getSelectedLineIds(quoteId);
        output.putAll(result);
    }
    
    /**
     * @description Validate quote status for editing
     * @param input Input parameters
     * @param output Output parameters
     */
    private void validateQuoteStatus(Map<String, Object> input, Map<String, Object> output) {
        String quoteId = (String)input.get('quoteId');
        
        if (String.isBlank(quoteId)) {
            output.put('success', false);
            output.put('errorMessage', 'Quote ID is required.');
            return;
        }
        
        Quote quote = [
            SELECT Id, Status
            FROM Quote
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        Boolean canEdit = quote.Status == 'Draft' || quote.Status == 'In Review';
        
        output.put('success', true);
        output.put('canEdit', canEdit);
        output.put('status', quote.Status);
        
        if (!canEdit) {
            output.put('message', 'Quote cannot be edited in status: ' + quote.Status);
        }
    }
    
    /**
     * @description Helper method to get string list from input
     */
    private List<String> getStringList(Map<String, Object> input, String key) {
        Object value = input.get(key);
        if (value == null) return null;
        
        if (value instanceof List<Object>) {
            List<String> result = new List<String>();
            for (Object item : (List<Object>)value) {
                result.add(String.valueOf(item));
            }
            return result;
        } else if (value instanceof String) {
            // Handle comma-separated string
            return ((String)value).split(',');
        }
        
        return null;
    }
    
    /**
     * @description Helper method to get Date value from input
     */
    private Date getDateValue(Map<String, Object> input, String key) {
        Object value = input.get(key);
        if (value == null) return null;
        
        if (value instanceof Date) {
            return (Date)value;
        } else if (value instanceof String) {
            try {
                return Date.valueOf((String)value);
            } catch (Exception e) {
                return null;
            }
        }
        
        return null;
    }
    
    /**
     * @description Helper method to get Integer value from input
     */
	@TestVisible
    private Integer getIntegerValue(Map<String, Object> input, String key) {
        Object value = input.get(key);
        if (value == null) return null;
        
        if (value instanceof Integer) {
            return (Integer)value;
        } else if (value instanceof Decimal) {
            return ((Decimal)value).intValue();
        } else if (value instanceof String) {
            try {
                return Integer.valueOf((String)value);
            } catch (Exception e) {
                return null;
            }
        }
        
        return null;
    }
}