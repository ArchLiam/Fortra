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

    /**
     * Handles before update logic for Order records.
     *
     * When an Order transitions INTO an Activated status category, activates the linked
     * Contract if it isn't already active, so the standard "Update Status" action clears
     * the platform's FAILED_ACTIVATION gate ("This order's contract is inactive") in a
     * single step. The contract is activated via cross-object DML (committed within the
     * transaction), so the core-platform activation check re-reads it as Activated.
     *
     * Note: the related pricing gate ("...the prices aren't updated") reads the COMMITTED
     * Order.ValidationResult, not an in-trigger change, so it cannot be cleared from here;
     * that staleness (only introduced by a manual reprice) is handled outside this trigger.
     */
    public static void handleBeforeUpdate(List<Order> newOrders, Map<Id, Order> oldMap) {
        if (bypassValidation) {
            return;
        }

        Map<String, String> statusToCategory = getStatusCategoryMap();
        Set<Id> contractIdsToActivate = new Set<Id>();

        // Loop locals declared once and reused to keep per-iteration heap flat.
        Order priorOrd;
        Boolean isNowActivated;
        Boolean wasActivated;

        for (Order ord : newOrders) {
            priorOrd = oldMap.get(ord.Id);

            // Act only on the transition INTO an Activated-category status.
            isNowActivated = 'Activated'.equals(statusToCategory.get(ord.Status));
            wasActivated = priorOrd != null
                && 'Activated'.equals(statusToCategory.get(priorOrd.Status));
            if (!isNowActivated || wasActivated) {
                continue;
            }

            // Activate the linked contract if it isn't already active (FAILED_ACTIVATION gate).
            if (ord.ContractId != null) {
                contractIdsToActivate.add(ord.ContractId);
            }
        }

        activateInactiveContracts(contractIdsToActivate);
    }

    /**
     * Activates any supplied contracts that are not already Activated (Draft, InApproval,
     * etc.) so the order's activation gate passes. Idempotent and recursion-safe: the
     * WHERE Status != 'Activated' filter skips already-active contracts, so downstream
     * contract automation cannot loop.
     */
    private static void activateInactiveContracts(Set<Id> contractIds) {
        if (contractIds.isEmpty()) {
            return;
        }
        List<Contract> toActivate =
            [SELECT Id FROM Contract WHERE Id IN :contractIds AND Status != 'Activated'];
        for (Contract con : toActivate) {
            con.Status = 'Activated';
        }
        if (!toActivate.isEmpty()) {
            update toActivate;
        }
    }

    // Cached Order Status (MasterLabel) -> StatusCode category (Draft/Activated/Superseded).
    private static Map<String, String> statusCategoryCache;
    private static Map<String, String> getStatusCategoryMap() {
        if (statusCategoryCache == null) {
            statusCategoryCache = new Map<String, String>();
            for (OrderStatus os : [SELECT MasterLabel, StatusCode FROM OrderStatus]) {
                statusCategoryCache.put(os.MasterLabel, os.StatusCode);
            }
        }
        return statusCategoryCache;
    }
}