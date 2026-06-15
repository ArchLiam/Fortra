/**
 * @description Applies COLA uplift net price to renewal maintenance quote lines when DPP
 *              leaves NetUnitPrice at zero. Updates pricing context before persist.
 */
public with sharing class RenewalMaintenancePricingService {

    private static final String CONTEXT_DEFINITION_NAME = 'SalesTransactionContextExt_v2';

    // ---------------------------------------------------------------------
    // Test seams. These are inert in production: every guard additionally
    // requires Test.isRunningTest(), and each override defaults to null, so a
    // production execution takes the exact same Context.IndustriesContext call
    // path as before. They exist only so a unit test can substitute a fabricated
    // queryTags response / context id for the live pricing-context I/O, which
    // throws (NoDataFoundException / UnexpectedException gack) outside a real
    // pricing transaction and is otherwise unreachable from an Apex test.
    @TestVisible
    private static Map<String, Object> testQueryTagsResponse;
    @TestVisible
    private static String testContextIdOverride;

    public class RepriceRequest {
        @InvocableVariable(required=true label='Quote Id')
        public String quoteId;

        @InvocableVariable(label='Context Instance Id')
        public String contextInstanceId;

        @InvocableVariable(label='Finalize COLA Net After DPP')
        public Boolean finalizeAfterPricing;
    }

    public class RepriceResult {
        @InvocableVariable(label='COLA-Only Persist Completed')
        public Boolean colaOnlyPersistComplete;
    }

    @TestVisible
    public static Boolean usesColaOnlyReprice(Id quoteId) {
        if (quoteId == null) {
            return false;
        }

        List<Quote> quotes = [
            SELECT Id, Quote_Type__c, OriginalActionType
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];
        if (quotes.isEmpty()) {
            return false;
        }

        List<QuoteLineItem> lines = [
            SELECT Id, Fortra_Product_Type__c, Product2.Fortra_Product_Type__c,
                   Base_Price__c, NetUnitPrice, TotalPrice
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
        ];

        return usesColaOnlyRepriceForLines(quotes[0], lines);
    }

    @TestVisible
    public static Boolean usesColaOnlyRepriceForLines(Quote quote, List<QuoteLineItem> lines) {
        if (quote == null || lines == null || lines.isEmpty()) {
            return false;
        }

        Boolean isRenewal = quote.Quote_Type__c == QuoteRenewalTypeHandler.QUOTE_TYPE_RENEWAL
            || quote.OriginalActionType == QuoteRenewalTypeHandler.ORIGINAL_ACTION_RENEW;
        if (!isRenewal) {
            return false;
        }

        Boolean hasRenewalMaintenance = false;
        for (QuoteLineItem qli : lines) {
            String productType = qli.Fortra_Product_Type__c != null
                ? qli.Fortra_Product_Type__c
                : qli.Product2?.Fortra_Product_Type__c;

            if (productType == 'Renewal Maintenance') {
                hasRenewalMaintenance = qli.Base_Price__c != null && qli.Base_Price__c > 0;
                continue;
            }

            if (productType == 'Perpetual' || productType == 'Software') {
                return false;
            }

            if (qli.TotalPrice != null && qli.TotalPrice > 0) {
                return false;
            }
        }

        return hasRenewalMaintenance;
    }

    @InvocableMethod(
        label='Apply Renewal Maintenance COLA Net'
        description='Writes COLA net into pricing context for renewal maintenance lines before persist'
    )
    public static List<RepriceResult> applyRenewalMaintenanceNetPrices(List<RepriceRequest> requests) {
        List<RepriceResult> results = new List<RepriceResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (RepriceRequest request : requests) {
            RepriceResult result = new RepriceResult();
            result.colaOnlyPersistComplete = false;

            if (request == null || String.isBlank(request.quoteId)) {
                results.add(result);
                continue;
            }

            Id quoteId = Id.valueOf(request.quoteId);
            try {
                if (String.isNotBlank(request.contextInstanceId)) {
                    if (request.finalizeAfterPricing == true) {
                        applyColaNetFinalizeToContext(quoteId, request.contextInstanceId);
                    } else {
                        applyToContext(quoteId, request.contextInstanceId);
                    }
                } else {
                    finalizeRenewalMaintenanceAfterPricing(quoteId);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Renewal maintenance COLA net skipped: ' + e.getMessage());
            }

            results.add(result);
        }

        return results;
    }

    /**
     * @description Rebuild context after main pricing persist and write COLA net for renewal maintenance.
     */
    public static void finalizeRenewalMaintenanceAfterPricing(Id quoteId) {
        if (quoteId == null) {
            return;
        }

        List<QuoteLineItem> candidates = queryRenewalMaintenanceCandidates(quoteId);
        if (candidates.isEmpty()) {
            return;
        }

        Context.IndustriesContext ctx = new Context.IndustriesContext();
        String contextId;
        if (Test.isRunningTest() && testContextIdOverride != null) {
            contextId = testContextIdOverride;
        } else {
            Map<String, Object> buildResult = ctx.buildContext(new Map<String, Object>{
                'contextDefinitionName' => CONTEXT_DEFINITION_NAME,
                'sourceRecordId' => quoteId
            });
            contextId = buildResult != null ? String.valueOf(buildResult.get('contextId')) : null;
        }
        if (String.isBlank(contextId)) {
            return;
        }

        applyToContext(quoteId, contextId);
        try {
            if (!(Test.isRunningTest() && testContextIdOverride != null)) {
                ctx.persistContext(new Map<String, Object>{ 'contextId' => contextId });
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Renewal maintenance context persist failed: ' + e.getMessage());
        }
    }

    @TestVisible
    private static void applyToContext(Id quoteId, String contextInstanceId) {
        List<QuoteLineItem> candidates = filterLinesNeedingColaNet(queryRenewalMaintenanceCandidates(quoteId));

        if (candidates.isEmpty()) {
            return;
        }

        Map<Id, Decimal> colaNetByLineId = new Map<Id, Decimal>();
        for (QuoteLineItem qli : candidates) {
            Decimal colaNet = computeColaNet(qli);
            if (colaNet != null && colaNet > 0) {
                colaNetByLineId.put(qli.Id, colaNet);
            }
        }

        if (colaNetByLineId.isEmpty()) {
            return;
        }

        Context.IndustriesContext ctx = new Context.IndustriesContext();
        Map<Id, Map<String, Object>> lineItemById = mapLineItemsById(
            queryLineItems(ctx, contextInstanceId)
        );

        System.debug(LoggingLevel.INFO, 'RenewalMaintenancePricingService updating ' + colaNetByLineId.size() + ' line(s)');

        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();
        for (QuoteLineItem qli : candidates) {
            if (!colaNetByLineId.containsKey(qli.Id)) {
                continue;
            }

            Map<String, Object> lineItem = lineItemById.get(qli.Id);
            Object updatePath = resolveUpdatePath(lineItem, qli.QuoteId, qli.Id);
            if (updatePath == null) {
                continue;
            }

            Decimal colaNet = colaNetByLineId.get(qli.Id);

            itemUpdates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
                'attributes' => new List<Map<String, Object>>{
                    new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'InputUnitPrice', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'SalesTransactionActionType', 'attributeValue' => 'Renew' }
                }
            });
        }

        if (itemUpdates.isEmpty()) {
            return;
        }

        Map<String, Object> updateResult = (Test.isRunningTest() && testQueryTagsResponse != null)
            ? new Map<String, Object>{ 'isSuccess' => true }
            : ctx.updateContextAttributes(new Map<String, Object>{
                'contextId' => contextInstanceId,
                'nodePathAndAttributes' => itemUpdates
            });
        System.debug(LoggingLevel.INFO, 'RenewalMaintenancePricingService update result=' + updateResult);
    }

    /**
     * @description After DPP, write stamped COLA net into pricing context so persist
     *              does not keep a stale Last Transaction asset price on renewal maintenance.
     */
    @TestVisible
    private static void applyColaNetFinalizeToContext(Id quoteId, String contextInstanceId) {
        List<QuoteLineItem> candidates = filterLinesNeedingColaNet(queryRenewalMaintenanceCandidates(quoteId));
        if (candidates.isEmpty()) {
            return;
        }

        Context.IndustriesContext ctx = new Context.IndustriesContext();
        Map<Id, Map<String, Object>> lineItemById = mapLineItemsById(
            queryLineItems(ctx, contextInstanceId)
        );

        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();
        for (QuoteLineItem qli : candidates) {
            Decimal colaNet = computeColaNet(qli);
            if (colaNet == null || colaNet <= 0) {
                continue;
            }

            Map<String, Object> lineItem = lineItemById.get(qli.Id);
            Object updatePath = resolveUpdatePath(lineItem, qli.QuoteId, qli.Id);
            if (updatePath == null) {
                continue;
            }

            Decimal lineTotal = resolveColaLineTotal(qli, colaNet);
            itemUpdates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
                'attributes' => new List<Map<String, Object>>{
                    new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'InputUnitPrice', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'NetUnitPrice', 'attributeValue' => colaNet },
                    new Map<String, Object>{ 'attributeName' => 'NetTotalPrice', 'attributeValue' => lineTotal },
                    new Map<String, Object>{ 'attributeName' => 'TotalPrice', 'attributeValue' => lineTotal },
                    new Map<String, Object>{ 'attributeName' => 'PartnerUnitPrice', 'attributeValue' => colaNet }
                }
            });
        }

        if (itemUpdates.isEmpty()) {
            return;
        }

        System.debug(LoggingLevel.INFO, 'RenewalMaintenancePricingService finalizing ' + itemUpdates.size() + ' line(s)');

        Map<String, Object> updateResult = (Test.isRunningTest() && testQueryTagsResponse != null)
            ? new Map<String, Object>{ 'isSuccess' => true }
            : ctx.updateContextAttributes(new Map<String, Object>{
                'contextId' => contextInstanceId,
                'nodePathAndAttributes' => itemUpdates
            });
        System.debug(LoggingLevel.INFO, 'RenewalMaintenancePricingService finalize result=' + updateResult);
    }

    public static Decimal computeColaNet(QuoteLineItem qli) {
        if (qli == null || qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        Decimal priorDisc = resolveDiscretionaryDollars(qli);
        Decimal colaPercent = qli.COLA_Uplift_Percent__c != null ? qli.COLA_Uplift_Percent__c : 0;
        Decimal preColaNet = qli.Base_Price__c - priorPartner - priorDisc;

        if (preColaNet <= 0) {
            return null;
        }

        return (preColaNet * (1 + (colaPercent / 100))).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @description Platform No Change asset-renew lines keep Quantity 0 on the record.
     *              Pricing context uses flat COLA net as the line total in that case.
     */
    @TestVisible
    public static Decimal resolveColaLineTotal(QuoteLineItem qli, Decimal colaNet) {
        if (colaNet == null) {
            return null;
        }
        Decimal quantity = qli != null ? qli.Quantity : null;
        if (quantity == null || quantity <= 0) {
            return colaNet;
        }
        return (colaNet * quantity).setScale(2, RoundingMode.HALF_UP);
    }

    @TestVisible
    private static List<QuoteLineItem> queryRenewalMaintenanceCandidates(Id quoteId) {
        return [
            SELECT Id, QuoteId, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, Quantity, NetUnitPrice
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            AND Fortra_Product_Type__c = 'Renewal Maintenance'
            AND Base_Price__c > 0
        ];
    }

    @TestVisible
    private static List<QuoteLineItem> filterLinesNeedingColaNet(List<QuoteLineItem> lines) {
        List<QuoteLineItem> results = new List<QuoteLineItem>();
        if (lines == null || lines.isEmpty()) {
            return results;
        }

        for (QuoteLineItem qli : lines) {
            if (needsColaNetCorrection(qli)) {
                results.add(qli);
            }
        }
        return results;
    }

    @TestVisible
    private static Boolean needsColaNetCorrection(QuoteLineItem qli) {
        return needsColaNetCorrectionForValues(computeColaNet(qli), qli?.NetUnitPrice);
    }

    @TestVisible
    private static Boolean needsColaNetCorrectionForValues(Decimal colaNet, Decimal netUnitPrice) {
        if (colaNet == null || colaNet <= 0) {
            return false;
        }
        if (netUnitPrice == null || netUnitPrice == 0) {
            return true;
        }
        return netUnitPrice.setScale(2, RoundingMode.HALF_UP) != colaNet;
    }

    private static Decimal resolveDiscretionaryDollars(QuoteLineItem qli) {
        if (qli.Prior_Discretionary_Discount__c != null && qli.Prior_Discretionary_Discount__c > 0) {
            return qli.Prior_Discretionary_Discount__c;
        }
        if (qli.Discount == null || qli.Discount <= 0) {
            return 0;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        return ((qli.Base_Price__c - priorPartner) * (qli.Discount / 100)).setScale(2, RoundingMode.HALF_UP);
    }

    private static Map<Id, Map<String, Object>> mapLineItemsById(List<Map<String, Object>> lineItems) {
        Map<Id, Map<String, Object>> lineItemById = new Map<Id, Map<String, Object>>();
        if (lineItems == null || lineItems.isEmpty()) {
            return lineItemById;
        }

        for (Map<String, Object> lineItem : lineItems) {
            Id lineItemId = getLineItemRecordId(lineItem);
            if (lineItemId != null) {
                lineItemById.put(lineItemId, lineItem);
            }
        }
        return lineItemById;
    }

    private static List<Map<String, Object>> queryLineItems(Context.IndustriesContext ctx, String contextInstanceId) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
        Map<String, Object> apiResponse = (Test.isRunningTest() && testQueryTagsResponse != null)
            ? testQueryTagsResponse
            : ctx.queryTags(new Map<String, Object>{
                'contextId' => contextInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            });
        if (apiResponse == null) {
            return lineItems;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        } else {
            return lineItems;
        }

        if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) {
            return lineItems;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawLineItems = (itemsObj instanceof List<Object>)
            ? (List<Object>) itemsObj
            : new List<Object>{ itemsObj };

        for (Object rawItem : rawLineItems) {
            if (!(rawItem instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
            if (!itemWrapper.containsKey('tagValue')) {
                continue;
            }
            Object tagValue = itemWrapper.get('tagValue');
            if (!(tagValue instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> lineItemData = new Map<String, Object>();
            lineItemData.putAll((Map<String, Object>) tagValue);
            if (itemWrapper.containsKey('dataPath') && itemWrapper.get('dataPath') instanceof List<Object>) {
                List<Object> pathParts = (List<Object>) itemWrapper.get('dataPath');
                if (!pathParts.isEmpty()) {
                    lineItemData.put('_recordId', String.valueOf(pathParts[pathParts.size() - 1]));
                    List<Object> updatePath = pathParts.clone();
                    if (!updatePath.isEmpty()) {
                        updatePath.remove(0);
                    }
                    lineItemData.put('_updatePath', updatePath);
                }
            }
            lineItems.add(lineItemData);
        }

        return lineItems;
    }

    @TestVisible
    private static Object resolveUpdatePath(Map<String, Object> lineItem, Id quoteId, Id lineItemId) {
        if (lineItem != null && lineItem.get('_updatePath') != null) {
            return lineItem.get('_updatePath');
        }
        if (quoteId == null || lineItemId == null) {
            return null;
        }
        return new List<Object>{ String.valueOf(quoteId), String.valueOf(lineItemId) };
    }

    private static Id getLineItemRecordId(Map<String, Object> lineItem) {
        String lineItemId = (String) lineItem.get('_recordId');
        if (String.isBlank(lineItemId)) {
            return null;
        }
        try {
            return Id.valueOf(lineItemId);
        } catch (Exception e) {
            return null;
        }
    }
}
