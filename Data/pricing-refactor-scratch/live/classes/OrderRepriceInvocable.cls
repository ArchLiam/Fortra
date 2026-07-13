/**
 * @description Reprices an Order in place via the RCA order pricing engine
 * (commerceorders.PlaceOrderExecutor with PricingPreferenceEnum.Force — the programmatic
 * "Reprice All") so it is CompletedWithPricing before activation. Invocable for the
 * Quote-to-Order flow: call it before Activate_Order, then gate activation on the returned
 * Calculation Status / Validation Result.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public without sharing class OrderRepriceInvocable {

    public class Request {
        @InvocableVariable(required=true label='Order Id')
        public Id orderId;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success = false;
        @InvocableVariable(label='Calculation Status') public String calculationStatus;
        @InvocableVariable(label='Validation Result') public String validationResult;
        @InvocableVariable(label='Pricing Ready') public Boolean pricingReady = false;
        @InvocableVariable(label='Error Message') public String errorMessage;
    }

    /**
     * @description Invocable entry point that reprices each requested Order in place, returning
     * one Result per Request describing success, calculation status, validation result and
     * pricing readiness.
     * @param requests The list of Requests, each carrying the Id of an Order to reprice
     * @return A list of Results, one per input Request, in the same order
     */
    @InvocableMethod(label='Reprice Order (RCA Force)'
        description='Reprices an order in place via PlaceOrderExecutor so it is CompletedWithPricing before activation')
    public static List<Result> reprice(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(repriceOne(req.orderId));
        }
        return out;
    }

    /**
     * @description Reprices a single Order: decomposes and persists maintenance work, patches
     * commercial unit prices, and — only when the order total does not already match the quote
     * total — applies partner net prices and runs a Force reprice through PlaceOrderExecutor,
     * then clears the validation result and reports the resulting pricing state.
     * @param orderId The Id of the Order to reprice
     * @return A Result capturing success, calculation status, validation result, pricing
     * readiness and any error message
     */
    private static Result repriceOne(Id orderId) {
        Result res = new Result();
        try {
            MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
                MaintenanceOrderDecompositionService.prepareForReprice(orderId);
            MaintenanceOrderDecompositionService.persistFromWork(work);
            if (work != null && work.allOrderItems != null && !work.allOrderItems.isEmpty()) {
                OrderCommercialNetService.patchOrderItemCommercialUnitPrices(orderId);
            }

            Decimal quoteTotal = resolveQuoteTotal(orderId);
            Decimal orderTotal = resolveOrderTotal(orderId);
            Boolean totalsAlreadyMatch = totalsMatch(quoteTotal, orderTotal);

            // Quote commercial nets are already on the order — skip RCA context posthook and
            // Force reprice (the original stamp-without-reprice path).
            if (!totalsAlreadyMatch && work != null && work.allOrderItems != null && !work.allOrderItems.isEmpty()) {
                PartnerNetPricePosthook.applyNetPricesToOrder(orderId);

                List<commerceorders.RecordWithReferenceRequest> records =
                    new List<commerceorders.RecordWithReferenceRequest>();
                records.add(new commerceorders.RecordWithReferenceRequest('refOrder',
                    new commerceorders.RecordResource(Order.getSObjectType(), 'PATCH', orderId)));

                Integer i = 0;
                for (OrderItem oi : work.allOrderItems) {
                    records.add(new commerceorders.RecordWithReferenceRequest('refOI' + (i++),
                        new commerceorders.RecordResource(OrderItem.getSObjectType(), 'PATCH', oi.Id)));
                }
                commerceorders.GraphRequest graph = new commerceorders.GraphRequest('SC3308_Reprice', records);

                commerceorders.PlaceOrderResult r = commerceorders.PlaceOrderExecutor.execute(
                    graph,
                    commerceorders.PricingPreferenceEnum.Force,
                    commerceorders.ConfigurationInputEnum.Skip,
                    new commerceorders.ConfigurationOptionsInput());

                res.success = (r != null && r.success == true);
                if (!res.success && r != null) {
                    res.errorMessage = String.valueOf(r.responseError);
                    populateResultFromOrder(orderId, res);
                    return res;
                }

                MaintenanceOrderDecompositionService.persistFromWork(work);
            } else {
                res.success = true;
            }

            clearOrderValidationResult(orderId);
            populateResultFromOrder(orderId, res);
            res.pricingReady = isPricingReady(orderId, quoteTotal);
        } catch (Exception e) {
            res.success = false;
            res.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            populateResultFromOrder(orderId, res);
        }
        return res;
    }

    /**
     * @description Loads the Order's calculation status and validation result and copies them
     * onto the given Result.
     * @param orderId The Id of the Order to read
     * @param res The Result to populate with the order's calculation status and validation result
     */
    @TestVisible
    private static void populateResultFromOrder(Id orderId, Result res) {
        for (Order o : [
            SELECT CalculationStatus, ValidationResult, TotalAmount
            FROM Order
            WHERE Id = :orderId
        ]) {
            res.calculationStatus = o.CalculationStatus;
            res.validationResult = o.ValidationResult;
        }
    }

    /**
     * @description Determines whether the Order is ready for activation: false if a validation
     * result is present, true if the calculation status is CompletedWithPricing, otherwise true
     * only when the order total matches the quote total.
     * @param orderId The Id of the Order to evaluate
     * @param quoteTotal The originating quote total used as a fallback comparison
     * @return True when the order is priced and ready for activation, false otherwise
     */
    @TestVisible
    private static Boolean isPricingReady(Id orderId, Decimal quoteTotal) {
        for (Order o : [
            SELECT CalculationStatus, ValidationResult, TotalAmount
            FROM Order
            WHERE Id = :orderId
        ]) {
            if (o.ValidationResult != null) {
                return false;
            }
            if (o.CalculationStatus == 'CompletedWithPricing') {
                return true;
            }
            return quoteTotal != null && totalsMatch(quoteTotal, o.TotalAmount);
        }
        return false;
    }

    /**
     * @description Returns the total price of the quote associated with the given Order, or null
     * when no quote is linked.
     * @param orderId The Id of the Order whose related quote total is requested
     * @return The related Quote's TotalPrice, or null when there is no quote
     */
    @TestVisible
    private static Decimal resolveQuoteTotal(Id orderId) {
        for (Order o : [SELECT Quote.TotalPrice FROM Order WHERE Id = :orderId LIMIT 1]) {
            return o.Quote != null ? o.Quote.TotalPrice : null;
        }
        return null;
    }

    /**
     * @description Returns the TotalAmount of the given Order, or null when the order is not found.
     * @param orderId The Id of the Order whose total amount is requested
     * @return The Order's TotalAmount, or null when the order is not found
     */
    @TestVisible
    private static Decimal resolveOrderTotal(Id orderId) {
        for (Order o : [SELECT TotalAmount FROM Order WHERE Id = :orderId LIMIT 1]) {
            return o.TotalAmount;
        }
        return null;
    }

    /**
     * @description Compares a quote total and an order total for equality at two-decimal
     * precision (HALF_UP rounding), treating null on either side as not matching.
     * @param quoteTotal The quote total to compare
     * @param orderTotal The order total to compare
     * @return True when both values are non-null and equal at two decimal places, false otherwise
     */
    @TestVisible
    private static Boolean totalsMatch(Decimal quoteTotal, Decimal orderTotal) {
        return quoteTotal != null && orderTotal != null
            && quoteTotal.setScale(2, RoundingMode.HALF_UP) == orderTotal.setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Clears the Order's ValidationResult by updating it to null; does nothing when
     * the supplied Id is null.
     * @param orderId The Id of the Order whose validation result should be cleared
     */
    @TestVisible
    private static void clearOrderValidationResult(Id orderId) {
        if (orderId == null) {
            return;
        }
        update new Order(Id = orderId, ValidationResult = null);
    }
}