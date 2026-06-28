/**
 * @description Service class for validating Operations Checklist completion
 * Contains invocable method for Flow automation
 */
public with sharing class ChecklistValidationService {

    /**
     * @description Validate checklist for a single Quote ID (for trigger use)
     * @param quoteId ID of the Quote to validate
     * @return ValidationResult containing completion status and incomplete items
     */
    public static ValidationResult validateChecklistForQuote(Id quoteId) {
        ValidationResult result = new ValidationResult();
        result.isComplete = false;
        result.incompleteItems = new List<String>();

        try {
            // Get all checklist items for the Quote
            List<Quote_Checklist_Item__c> allItems = [
                SELECT Id, Item_Name__c, Is_Checked__c, Sort_Order__c
                FROM Quote_Checklist_Item__c
                WHERE Quote__c = :quoteId
                WITH SECURITY_ENFORCED
                ORDER BY Sort_Order__c ASC
            ];

            if (allItems.isEmpty()) {
                result.errorMessage = 'No checklist items found for Quote';
                return result;
            }

            // Check for incomplete items
            for (Quote_Checklist_Item__c item : allItems) {
                if (!item.Is_Checked__c) {
                    result.incompleteItems.add(item.Item_Name__c);
                }
            }

            // Set completion status
            result.isComplete = result.incompleteItems.isEmpty();
            result.totalItems = allItems.size();
            result.completedItems = allItems.size() - result.incompleteItems.size();

            if (!result.isComplete) {
                result.errorMessage = 'Cannot convert Quote to Order. The following Operations Checklist items are incomplete: ' +
                                    String.join(result.incompleteItems, ', ');
            }

        } catch (Exception e) {
            result.errorMessage = 'Error validating checklist: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Validate that all checklist items are complete for a Quote
     * @param requests List of ValidationRequest containing Quote IDs
     * @return List of ValidationResult containing completion status and incomplete items
     */
    @InvocableMethod(label='Validate Checklist Complete'
                     description='Checks if all checklist items are complete for Quote'
                     category='Operations Checklist')
    public static List<ValidationResult> validateChecklistComplete(List<ValidationRequest> requests) {
        List<ValidationResult> results = new List<ValidationResult>();

        for (ValidationRequest request : requests) {
            results.add(validateChecklistForQuote(request.quoteId));
        }

        return results;
    }

    // Inner classes for invocable method parameters and results

    public class ValidationRequest {
        @InvocableVariable(label='Quote ID' description='ID of the Quote to validate' required=true)
        public Id quoteId;
    }

    public class ValidationResult {
        @InvocableVariable(label='Is Complete' description='Whether all checklist items are complete')
        public Boolean isComplete;

        @InvocableVariable(label='Total Items' description='Total number of checklist items')
        public Integer totalItems;

        @InvocableVariable(label='Completed Items' description='Number of completed checklist items')
        public Integer completedItems;

        @InvocableVariable(label='Incomplete Items' description='List of incomplete item names')
        public List<String> incompleteItems;

        @InvocableVariable(label='Error Message' description='Detailed error message for validation failures')
        public String errorMessage;
    }
}