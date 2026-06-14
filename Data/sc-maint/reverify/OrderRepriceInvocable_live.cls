/**
 * @description Reprices an Order in place via the RCA order pricing engine
 * (commerceorders.PlaceOrderExecutor with PricingPreferenceEnum.Force — the programmatic
 * "Reprice All") so it is CompletedWithPricing before activation. Invocable for the
 * Quote-to-Order flow: call it before Activate_Order, then gate activation on the returned
 * Calculation Status / Validation Result.
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

    @InvocableMethod(label='Reprice Order (RCA Force)'
        description='Reprices an order in place via PlaceOrderExecutor so it is CompletedWithPricing before activation')
    public static List<Result> reprice(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(repriceOne(req.orderId));
        }
        return out;
    }

    private static Result repriceOne(Id orderId) {
        Result res = new Result();
        try {
            MaintenanceOrderDecompositionService.OrderMaintenanceWork work =
                MaintenanceOrderDecompositionService.prepareForReprice(orderId);
            MaintenanceOrderDecompositionService.persistFromWork(work);

            Decimal quoteTotal = resolveQuoteTotal(orderId);
            Decimal orderTotal = resolveOrderTotal(orderId);
            Boolean totalsAlreadyMatch = quoteTotal != null && orderTotal == quoteTotal;

            if (!totalsAlreadyMatch) {
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
            return quoteTotal != null && o.TotalAmount == quoteTotal;
        }
        return false;
    }

    @TestVisible
    private static Decimal resolveQuoteTotal(Id orderId) {
        for (Order o : [SELECT Quote.TotalPrice FROM Order WHERE Id = :orderId LIMIT 1]) {
            return o.Quote != null ? o.Quote.TotalPrice : null;
        }
        return null;
    }

    @TestVisible
    private static Decimal resolveOrderTotal(Id orderId) {
        for (Order o : [SELECT TotalAmount FROM Order WHERE Id = :orderId LIMIT 1]) {
            return o.TotalAmount;
        }
        return null;
    }

    @TestVisible
    private static void clearOrderValidationResult(Id orderId) {
        if (orderId == null) {
            return;
        }
        update new Order(Id = orderId, ValidationResult = null);
    }
}