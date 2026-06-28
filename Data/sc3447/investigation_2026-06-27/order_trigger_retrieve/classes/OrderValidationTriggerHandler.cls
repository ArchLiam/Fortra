public class OrderValidationTriggerHandler {

    // Bypass flag for migration scenarios where legacy Quotes lack checklist items
    public static Boolean bypassValidation = false;

    /**
     * Handles before insert logic for Order records
     * Validates that Operations Checklist is complete before allowing Order creation
     */
    public static void handleBeforeInsert(List<Order> newOrders) {
        if (bypassValidation) {
            return;
        }

        // Collect Quote IDs that need validation
        Set<Id> quoteIds = new Set<Id>();
        Map<Id, Order> quoteIdToOrder = new Map<Id, Order>();

        for (Order ord : newOrders) {
            if (ord.QuoteId != null) {
                quoteIds.add(ord.QuoteId);
                quoteIdToOrder.put(ord.QuoteId, ord);
            }
        }

        // If no Orders have Quotes, skip validation
        if (quoteIds.isEmpty()) {
            return;
        }

        // Validate checklist for each Quote
        for (Id quoteId : quoteIds) {
            ChecklistValidationService.ValidationResult result =
                ChecklistValidationService.validateChecklistForQuote(quoteId);

            if (!result.isComplete) {
                Order ord = quoteIdToOrder.get(quoteId);
                ord.addError(result.errorMessage);
            }
        }
    }
}