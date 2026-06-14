/**
 * @description Apex Prehook for Revenue Cloud pricing that applies COLA (Cost of Living Adjustment)
 *              uplift pricing to renewal quote lines. This prehook replaces the trigger-based
 *              COLAUpliftHandler for Revenue Cloud integration.
 *
 *              COLA Pricing Hierarchy:
 *              1. Line Override - Manual edit on QuoteLineItem (highest priority)
 *              2. Contract Override - Active Contract COLA override (if valid)
 *              3. CMDT Lookup - Default from COLA_Uplift_Rules__mdt by Solution Category
 *
 *              Writes to Context (for Pricing Procedure waterfall visibility):
 *              - COLACalculatedPrice__c - The COLA-adjusted price
 *              - COLAUpliftPercent__c - The percentage applied
 *              - COLAExplainer__c - Human-readable explainer text
 *              - COLAApplied__c - Boolean flag for conditional assignment
 *
 * @author Marc DeBrey
 * @date January 2026
 * @version 1.1 - Renewal maintenance COLA from stamped Base/Partner/Software discount components
 */
global class COLAUpliftPrehook implements RevSignaling.SignalingApexProcessor {

    // Recursion prevention flag
    private static Boolean isProcessing = false;

    /**
     * @description Execute method called by Revenue Cloud pricing orchestration
     * @param request The transaction request containing context ID
     * @return TransactionResponse indicating success or failure
     */
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        // Recursion prevention
        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'COLA prehook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;

            String ctxInstanceId = request.ctxInstanceId;

            System.debug(LoggingLevel.INFO, '========================================');
            System.debug(LoggingLevel.INFO, 'COLAUpliftPrehook v1.0: Starting execution');
            System.debug(LoggingLevel.INFO, 'Context Instance ID: ' + ctxInstanceId);
            System.debug(LoggingLevel.INFO, '========================================');

            if (String.isBlank(ctxInstanceId)) {
                response.status = RevSignaling.TransactionStatus.FAILED;
                response.message = 'Context instance ID is required';
                return response;
            }

            // SCOPE GUARD: COLA prehook applies only to Quote transactions.
            // The context attributes this prehook reads and writes (Pre_COLA_Price__c,
            // COLA_Source__c, COLA_Applied_Date__c, COLA_Solution_Category__c,
            // COLA_Uplift_Percent__c) are mapped only on the Quote side of
            // SalesTransactionContextExt. Running on an Order transaction causes
            // "Invalid tag attribute name key" errors when the engine tries to
            // resolve Quote-only attributes against an Order-scoped context.
            if (isOrderTransaction(ctxInstanceId)) {
                System.debug(LoggingLevel.INFO, 'COLAUpliftPrehook: skipped — Order transaction detected');
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'COLA prehook skipped - Order transaction';
                return response;
            }

            // Load COLA rules from Custom Metadata
            Map<String, COLA_Uplift_Rules__mdt> colaRulesMap = getCOLARulesMap();
            System.debug(LoggingLevel.INFO, 'Loaded ' + colaRulesMap.size() + ' COLA rules from CMDT');

            // Load MyCAP rule before processLineItems so it can apply the 3% default
            MyCAP_Rules__mdt mycapRule = MyCAP_Rules__mdt.getInstance('Global');

            // Process line items (applies COLA pricing + MyCAP defaulting)
            Integer processedCount = processLineItems(ctxInstanceId, colaRulesMap, mycapRule);
            Integer mycapFlaggedQuotes = 0;
            if (mycapRule != null && mycapRule.Is_Active__c == true) {
                mycapFlaggedQuotes = processMyCAPEligibility(ctxInstanceId, mycapRule);
            } else {
                System.debug(LoggingLevel.INFO, 'MyCAP rule missing or inactive - skipping MyCAP branch');
            }

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'COLA pricing applied to ' + processedCount + ' renewal items; MyCAP evaluated ' + mycapFlaggedQuotes + ' quote(s)';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'COLAUpliftPrehook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

            // Return SUCCESS even on error to avoid blocking pricing
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'COLA pricing completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    /**
     * @description Detect whether the current context is an Order transaction
     *              by inspecting the root entity Id at dataPath[0] of any
     *              SalesTransactionItem. Order records start with "801",
     *              Quotes with "0Q0". Fails open (returns false) on any
     *              detection failure so we preserve existing behavior on Quote.
     * @param ctxInstanceId The context instance ID
     * @return true if any item's root entity Id has the Order prefix (801)
     */
    private Boolean isOrderTransaction(String ctxInstanceId) {
        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };
            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            if (apiResponse == null) return false;

            Map<String, Object> queryResult;
            if (apiResponse.containsKey('queryResult')) {
                Object qrObj = apiResponse.get('queryResult');
                queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
            } else if (apiResponse.containsKey('SalesTransactionItem')) {
                queryResult = apiResponse;
            }
            if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) return false;

            Object itemsObj = queryResult.get('SalesTransactionItem');
            List<Object> items = (itemsObj instanceof List<Object>)
                ? (List<Object>) itemsObj
                : new List<Object>{ itemsObj };
            if (items.isEmpty()) return false;

            // Peek at the first item's dataPath[0] — the root entity Id
            Map<String, Object> firstItem = (Map<String, Object>) items.get(0);
            Object dpObj = firstItem.get('dataPath');
            if (!(dpObj instanceof List<Object>)) return false;
            List<Object> dp = (List<Object>) dpObj;
            if (dp.isEmpty()) return false;

            String rootId = String.valueOf(dp.get(0));
            return rootId != null && rootId.startsWith('801');
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'isOrderTransaction detection failed - assuming Quote: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Process line items and apply COLA pricing
     * @param ctxInstanceId Context instance ID
     * @param colaRulesMap Map of COLA rules by Solution Category
     * @return Number of items processed
     */
    private Integer processLineItems(String ctxInstanceId, Map<String, COLA_Uplift_Rules__mdt> colaRulesMap, MyCAP_Rules__mdt mycapRule) {
        Integer processedCount = 0;

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Query line items from context
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };

            Map<String, Object> apiResponse = ctx.queryTags(queryInput);

            if (apiResponse == null) {
                System.debug(LoggingLevel.WARN, 'queryTags for SalesTransactionItem returned null');
                return 0;
            }

            // Handle nested response structure
            Map<String, Object> queryResult;
            if (apiResponse.containsKey('queryResult')) {
                Object qrObj = apiResponse.get('queryResult');
                if (qrObj instanceof Map<String, Object>) {
                    queryResult = (Map<String, Object>) qrObj;
                } else {
                    return 0;
                }
            } else if (apiResponse.containsKey('SalesTransactionItem')) {
                queryResult = apiResponse;
            } else {
                return 0;
            }

            if (!queryResult.containsKey('SalesTransactionItem')) {
                return 0;
            }

            Object itemsObj = queryResult.get('SalesTransactionItem');
            List<Object> rawLineItems;

            if (itemsObj instanceof List<Object>) {
                rawLineItems = (List<Object>) itemsObj;
            } else {
                rawLineItems = new List<Object>{ itemsObj };
            }

            System.debug(LoggingLevel.INFO, 'Found ' + rawLineItems.size() + ' line items');

            // Extract QLI record IDs from dataPath (QuoteActionId is not
            // available in context tags at runtime — confirmed via debug log).
            // Then query QLI→QuoteAction→Asset to get renewal and pricing data.
            Set<Id> qliIds = new Set<Id>();
            Map<Id, Map<String, Object>> qliIdToWrapper = new Map<Id, Map<String, Object>>();
            for (Object rawItem : rawLineItems) {
                Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
                Object dpObj = itemWrapper.get('dataPath');
                if (dpObj instanceof List<Object>) {
                    List<Object> dp = (List<Object>) dpObj;
                    if (!dp.isEmpty()) {
                        try {
                            Id qliId = Id.valueOf(String.valueOf(dp.get(dp.size() - 1)));
                            qliIds.add(qliId);
                            qliIdToWrapper.put(qliId, itemWrapper);
                        } catch (Exception e) {
                            // Not a valid Id, skip
                        }
                    }
                }
            }

            // Query renewal QuoteActions via QLI relationship
            Map<Id, QuoteLineItem> renewalQlis = new Map<Id, QuoteLineItem>();
            if (!qliIds.isEmpty()) {
                for (QuoteLineItem qli : [
                    SELECT Id, QuoteActionId, QuoteAction.Type, QuoteAction.SourceAssetId,
                           QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Product2Id,
                           QuoteAction.SourceAsset.Product2.Solution_Category__c,
                           Default_COLA_Uplift_Percent__c
                    FROM QuoteLineItem
                    WHERE Id IN :qliIds
                    AND QuoteAction.Type = 'Renew'
                ]) {
                    renewalQlis.put(qli.Id, qli);
                }
            }

            System.debug(LoggingLevel.INFO, 'Found ' + renewalQlis.size() + ' renewal QLIs from ' + qliIds.size() + ' total');

            // Collect Asset IDs for Contract override lookup
            Set<Id> assetIds = new Set<Id>();
            for (QuoteLineItem rqli : renewalQlis.values()) {
                if (rqli.QuoteAction?.SourceAssetId != null) {
                    assetIds.add(rqli.QuoteAction.SourceAssetId);
                }
            }

            // Get Contract overrides
            Map<Id, ContractOverride> contractOverrides = getContractOverrides(assetIds);

            // Build updates for line items
            List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();

            for (Id qliId : renewalQlis.keySet()) {
                QuoteLineItem renewalQli = renewalQlis.get(qliId);
                Map<String, Object> itemWrapper = qliIdToWrapper.get(qliId);
                if (itemWrapper == null) continue;

                Map<String, Object> lineItem = extractLineItemData(itemWrapper);
                if (lineItem == null) continue;

                QuoteAction qa = renewalQli.QuoteAction;
                if (qa == null) continue;

                // Get Asset price as base
                Decimal assetPrice = qa.SourceAsset?.Price;
                if (assetPrice == null || assetPrice <= 0) {
                    System.debug(LoggingLevel.INFO, 'Skipping QLI ' + qliId + ' - no valid asset price');
                    continue;
                }

                // Get Solution Category
                String solutionCategory = null;
                if (qa.SourceAsset?.Product2 != null) {
                    solutionCategory = qa.SourceAsset.Product2.Solution_Category__c;
                }

                // Determine COLA percentage using override hierarchy
                Decimal colaPercent = 0;
                String colaSource = 'CMDT Lookup';

                // Look up known system rates for override detection
                Decimal cmdtDefault = 0;
                if (String.isNotBlank(solutionCategory) && colaRulesMap.containsKey(solutionCategory)) {
                    COLA_Uplift_Rules__mdt rule = colaRulesMap.get(solutionCategory);
                    if (rule.Is_Active__c) {
                        cmdtDefault = rule.Default_Uplift_Percent__c != null ? rule.Default_Uplift_Percent__c : 0;
                    }
                }
                // Determine the Contract Override percent if one applies to
                // this line's Asset.
                Decimal contractOverridePct = null;
                if (qa.SourceAssetId != null && contractOverrides.containsKey(qa.SourceAssetId)) {
                    ContractOverride colaOverride = contractOverrides.get(qa.SourceAssetId);
                    if (colaOverride.isValid) {
                        contractOverridePct = colaOverride.overridePercent;
                    }
                }

                // Detect line override: a true YEAR-1 override differs from the
                // CMDT default AND the Contract Override. MyCAP is NOT included —
                // it is an OUTYEAR concept (COLA_Outyear_Uplift_Percent__c), never
                // a year-1 system value (confirmed by live data: 0 of 7 real
                // 'MyCAP Default' lines carry the MyCAP value in year-1), so a
                // year-1 value equal to the MyCAP rate (e.g. 3%) is a genuine
                // manual override.
                Decimal lineOverridePercent = getDecimalFromTag(lineItem, 'COLA_Uplift_Percent__c');
                // Single shared predicate with the trigger handler so the two
                // override-detection paths can never drift (see
                // COLAUpliftHandler.isManualLineOverride). MyCAP arg is null:
                // year-1 detection excludes the outyear rate.
                Boolean isEffectivelyOverridden = COLAUpliftHandler.isManualLineOverride(
                    lineOverridePercent, cmdtDefault, null, contractOverridePct);

                if (isEffectivelyOverridden) {
                    // Tier 1: Line Override (highest priority)
                    colaPercent = lineOverridePercent;
                    colaSource = 'Line Override';
                } else if (contractOverridePct != null) {
                    // Tier 2: Contract Override
                    colaPercent = contractOverridePct;
                    colaSource = 'Contract Override';
                }

                // Tier 3: CMDT Lookup (default)
                if (colaSource == 'CMDT Lookup') {
                    colaPercent = cmdtDefault;
                }

                // MyCAP: for multi-year annual lines that aren't manually overridden,
                // flag the source as 'MyCAP Default'. Year-1 COLA% stays at the
                // CMDT rate; the out-year rate (3%) is applied by the
                // Final_Year_COLA_Calculated_Price__c formula field.
                Decimal pricingTermCount = getDecimalFromTag(lineItem, 'PricingTermCount');
                if (mycapRule != null && mycapRule.Is_Active__c == true && colaSource == 'CMDT Lookup') {
                    String pricingTermUnit = getStringFromTag(lineItem, 'PricingTermUnit');
                    Decimal itemSubTerm = getDecimalFromTag(lineItem, 'ItemSubscriptionTerm');
                    Boolean isAnnual = pricingTermUnit == 'Annual';
                    Boolean isMultiYear = isAnnual
                        && ((pricingTermCount != null && pricingTermCount > 1)
                            || (itemSubTerm != null && itemSubTerm > 1));
                    if (isMultiYear) {
                        colaSource = 'MyCAP Default';
                    }
                }

                // Calculate COLA-adjusted price (year-1 only).
                // Final-year compounded price is derived via formula field
                // Final_Year_COLA_Calculated_Price__c on QuoteLineItem.
                Decimal colaAdjustedPrice = assetPrice * (1 + (colaPercent / 100));
                colaAdjustedPrice = colaAdjustedPrice.setScale(2, System.RoundingMode.HALF_UP);

                System.debug(LoggingLevel.INFO, 'Line item: AssetPrice=' + assetPrice +
                    ', COLA%=' + colaPercent + ', Source=' + colaSource +
                    ', AdjustedPrice=' + colaAdjustedPrice);

                // Build explainer text for waterfall display
                String explainerText = buildExplainerText(colaPercent, solutionCategory, colaSource);

                // Build context update
                Map<String, Object> itemUpdate = buildItemUpdate(itemWrapper, colaAdjustedPrice, colaPercent, explainerText, colaSource, assetPrice, solutionCategory);
                if (itemUpdate != null) {
                    itemUpdates.add(itemUpdate);
                    processedCount++;
                }
            }

            // Submit context updates
            if (!itemUpdates.isEmpty()) {
                submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
            }

            processedCount += appendStampedRenewalMaintenanceUpdates(
                ctx,
                ctxInstanceId,
                qliIds,
                qliIdToWrapper
            );

            System.debug(LoggingLevel.INFO, 'processLineItems submitted ' + itemUpdates.size() + ' asset-renewal context updates');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error processing line items: ' + e.getMessage());
        }

        return processedCount;
    }

    /**
     * @description Renewal maintenance lines without a renew asset use stamped prior-year
     *              components. Writes COLACalculatedPrice__c for the DPP COLA formula.
     */
    @TestVisible
    private Integer appendStampedRenewalMaintenanceUpdates(
        Context.IndustriesContext ctx,
        String ctxInstanceId,
        Set<Id> qliIds,
        Map<Id, Map<String, Object>> qliIdToWrapper
    ) {
        if (qliIds == null || qliIds.isEmpty()) {
            return 0;
        }

        List<Map<String, Object>> itemUpdates = new List<Map<String, Object>>();
        for (QuoteLineItem qli : [
            SELECT Id, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                   PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, Fortra_Product_Type__c,
                   Quote.QuoteTypeText__c
            FROM QuoteLineItem
            WHERE Id IN :qliIds
            AND Fortra_Product_Type__c = 'Renewal Maintenance'
            AND Quote.QuoteTypeText__c = 'Renewal'
            AND Base_Price__c > 0
        ]) {
            Map<String, Object> itemWrapper = qliIdToWrapper.get(qli.Id);
            if (itemWrapper == null) {
                continue;
            }

            Decimal colaNet = computeStampedMaintenanceColaNet(qli);
            if (colaNet == null || colaNet <= 0) {
                continue;
            }

            Map<String, Object> itemUpdate = buildMaintenanceColaItemUpdate(itemWrapper, qli, colaNet);
            if (itemUpdate != null) {
                itemUpdates.add(itemUpdate);
            }
        }

        if (!itemUpdates.isEmpty()) {
            submitContextUpdates(ctx, ctxInstanceId, itemUpdates);
        }

        return itemUpdates.size();
    }

    @TestVisible
    private Decimal computeStampedMaintenanceColaNet(QuoteLineItem qli) {
        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        Decimal priorDisc = qli.Prior_Discretionary_Discount__c != null && qli.Prior_Discretionary_Discount__c > 0
            ? qli.Prior_Discretionary_Discount__c
            : (qli.Discount != null && qli.Discount > 0
                ? ((qli.Base_Price__c - priorPartner) * (qli.Discount / 100)).setScale(2, System.RoundingMode.HALF_UP)
                : 0);
        Decimal colaPercent = qli.COLA_Uplift_Percent__c != null ? qli.COLA_Uplift_Percent__c : 0;
        Decimal preColaNet = qli.Base_Price__c - priorPartner - priorDisc;
        if (preColaNet <= 0) {
            return null;
        }
        return (preColaNet * (1 + (colaPercent / 100))).setScale(2, System.RoundingMode.HALF_UP);
    }

    @TestVisible
    private Map<String, Object> buildMaintenanceColaItemUpdate(
        Map<String, Object> itemWrapper,
        QuoteLineItem qli,
        Decimal colaNet
    ) {
        List<Object> dataPath;
        if (itemWrapper.containsKey('dataPath')) {
            dataPath = (List<Object>) itemWrapper.get('dataPath');
        } else {
            return null;
        }
        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }

        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        // SC-3346 renewal-maintenance priced-node seed (experiment v1, 2026-06-13):
        // The derived renewal-maintenance line (DerivedPricingAttribute=true, ListPrice=0) is NOT a
        // priced node, so the engine never commits the COLA net (it leaves a stale ListPrice*x value
        // or 0). Seed the line as a NON-derived priced node with ListPrice/InputUnitPrice/UnitPrice =
        // colaNet (which is already fully net of prior partner + discretionary discount) and zero the
        // discount context so the standard pricing path does not re-apply any discount.
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'DerivedPricingAttribute', 'attributeValue' => false },
            new Map<String, Object>{ 'attributeName' => 'ListPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'InputUnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'UnitPrice', 'attributeValue' => colaNet },
            new Map<String, Object>{ 'attributeName' => 'PartnerDiscountPercent', 'attributeValue' => 0 },
            new Map<String, Object>{ 'attributeName' => 'Discount', 'attributeValue' => 0 }
        };

        System.debug(LoggingLevel.INFO, 'RENEWAL MAINT COLA PREHOOK SEED v1: QLI ' + qli.Id + ' -> ' + colaNet);

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
    }

    /**
     * @description Build explainer text for waterfall display
     * @param colaPercent The COLA percentage
     * @param solutionCategory The product's solution category
     * @param colaSource The source of the COLA value
     * @return Formatted explainer text
     */
    @TestVisible
    private String buildExplainerText(Decimal colaPercent, String solutionCategory, String colaSource) {
        String explainer = 'COLA Uplift: ' + colaPercent.setScale(1) + '%';

        if (String.isNotBlank(solutionCategory)) {
            explainer += ' (' + solutionCategory + ')';
        }

        if (colaSource != 'CMDT Lookup') {
            explainer += ' [' + colaSource + ']';
        }

        return explainer;
    }

    /**
     * @description Build context update for a line item
     * @param itemWrapper The raw item wrapper from context
     * @param colaPrice The COLA-adjusted price
     * @param colaPercent The COLA percentage
     * @param explainer The explainer text
     * @param source The COLA source
     * @param preCOLAPrice The original price before COLA
     * @param solutionCategory The product's solution category
     * @return Map for context update or null
     */
    private Map<String, Object> buildItemUpdate(
        Map<String, Object> itemWrapper,
        Decimal colaPrice,
        Decimal colaPercent,
        String explainer,
        String source,
        Decimal preCOLAPrice,
        String solutionCategory
    ) {
        // Get dataPath from wrapper
        List<Object> dataPath;
        if (itemWrapper.containsKey('dataPath')) {
            dataPath = (List<Object>) itemWrapper.get('dataPath');
        } else {
            return null;
        }

        if (dataPath == null || dataPath.isEmpty()) {
            return null;
        }

        // Build update path (dataPath minus first element)
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }

        // Build attributes for context update.
        // Only hydration-mapped attributes — COLAExplainer__c and COLAApplied__c
        // have no contextAttrHydrationDetails and poison the entire batch.
        // COLAUpliftPercent__c now has a hydration mapping (added 2026-04-16).
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();

        attributes.add(new Map<String, Object>{
            'attributeName' => 'COLACalculatedPrice__c',
            'attributeValue' => colaPrice
        });

        // NOTE: COLA_Uplift_Percent__c / COLAUpliftPercent__c CANNOT be included
        // in this batch — it poisons the entire updateContextAttributes call
        // despite having a hydration mapping. The field is synced by the
        // COLAUpliftHandler trigger in handleBeforeUpdate instead.

        attributes.add(new Map<String, Object>{
            'attributeName' => 'Pre_COLA_Price__c',
            'attributeValue' => preCOLAPrice
        });

        attributes.add(new Map<String, Object>{
            'attributeName' => 'COLA_Source__c',
            'attributeValue' => source
        });

        attributes.add(new Map<String, Object>{
            'attributeName' => 'COLA_Applied_Date__c',
            'attributeValue' => Datetime.now()
        });

        if (String.isNotBlank(solutionCategory)) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'COLA_Solution_Category__c',
                'attributeValue' => solutionCategory
            });
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });
        result.put('attributes', attributes);

        return result;
    }

    /**
     * @description Submit context attribute updates
     * @param ctx Context API instance
     * @param ctxInstanceId Context instance ID
     * @param itemUpdates List of item updates
     */
    private void submitContextUpdates(
        Context.IndustriesContext ctx,
        String ctxInstanceId,
        List<Map<String, Object>> itemUpdates
    ) {
        try {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => ctxInstanceId,
                'nodePathAndAttributes' => itemUpdates
            };

            System.debug(LoggingLevel.INFO, 'Submitting ' + itemUpdates.size() + ' COLA context updates');
            Map<String, Object> updateResult = ctx.updateContextAttributes(updateInput);
            System.debug(LoggingLevel.INFO, 'Update result: ' + JSON.serializePretty(updateResult));

        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state - skipping updates');
            } else {
                System.debug(LoggingLevel.ERROR, 'Error updating context: ' + e.getMessage());
            }
        }
    }

    /**
     * @description Extract line item data from raw context object
     * @param rawItem The raw item from context
     * @return Map of line item data or null
     */
    private Map<String, Object> extractLineItemData(Object rawItem) {
        if (rawItem == null || !(rawItem instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;

        if (itemWrapper.containsKey('tagValue')) {
            Object tagValue = itemWrapper.get('tagValue');
            if (tagValue instanceof Map<String, Object>) {
                return (Map<String, Object>) tagValue;
            }
        }

        return itemWrapper;
    }

    /**
     * @description Gets COLA rules from Custom Metadata Type, indexed by Solution Category
     * @return Map of COLA rules keyed by Solution Category name
     */
    @TestVisible
    private Map<String, COLA_Uplift_Rules__mdt> getCOLARulesMap() {
        Map<String, COLA_Uplift_Rules__mdt> rulesMap = new Map<String, COLA_Uplift_Rules__mdt>();

        for (COLA_Uplift_Rules__mdt rule : [
            SELECT MasterLabel, Solution_Category__c, Default_Uplift_Percent__c, Is_Active__c,
                   Effective_Start_Date__c, Effective_End_Date__c, Description__c
            FROM COLA_Uplift_Rules__mdt
            WHERE Is_Active__c = true
        ]) {
            if (String.isNotBlank(rule.Solution_Category__c)) {
                // Check effective dates if specified
                Date today = Date.today();
                Boolean isEffective = true;

                if (rule.Effective_Start_Date__c != null && today < rule.Effective_Start_Date__c) {
                    isEffective = false;
                }
                if (rule.Effective_End_Date__c != null && today > rule.Effective_End_Date__c) {
                    isEffective = false;
                }

                if (isEffective) {
                    rulesMap.put(rule.Solution_Category__c, rule);
                }
            }
        }

        return rulesMap;
    }

    /**
     * @description Gets Contract-level COLA overrides for Assets via AssetContractRelationship
     * @param assetIds Set of Asset IDs to query
     * @return Map of ContractOverride wrappers keyed by Asset Id
     */
    @TestVisible
    private Map<Id, ContractOverride> getContractOverrides(Set<Id> assetIds) {
        Map<Id, ContractOverride> overrideMap = new Map<Id, ContractOverride>();

        if (assetIds == null || assetIds.isEmpty()) {
            return overrideMap;
        }

        List<SObject> relationships;
        try {
            String query = 'SELECT Id, AssetId, ContractId, ' +
                           'Contract.COLA_Override_Percent__c, ' +
                           'Contract.COLA_Override_Persist_Until__c, ' +
                           'Contract.Status ' +
                           'FROM AssetContractRelationship ' +
                           'WHERE AssetId IN :assetIds ' +
                           'AND Contract.Status = \'Activated\'';
            relationships = Database.query(query);
        } catch (System.QueryException e) {
            System.debug('AssetContractRelationship not available: ' + e.getMessage());
            return overrideMap;
        }

        Date today = Date.today();

        for (SObject acr : relationships) {
            SObject relatedContract = acr.getSObject('Contract');

            if (relatedContract == null || relatedContract.get('COLA_Override_Percent__c') == null) {
                continue;
            }

            Boolean isValid = false;
            Date persistUntil = (Date)relatedContract.get('COLA_Override_Persist_Until__c');

            if (persistUntil == null) {
                isValid = true;
            } else if (persistUntil >= today) {
                isValid = true;
            }

            if (isValid) {
                ContractOverride colaOverride = new ContractOverride();
                colaOverride.contractId = (Id)acr.get('ContractId');
                colaOverride.overridePercent = (Decimal)relatedContract.get('COLA_Override_Percent__c');
                colaOverride.persistUntil = persistUntil;
                colaOverride.isValid = true;

                Id assetId = (Id)acr.get('AssetId');
                if (!overrideMap.containsKey(assetId)) {
                    overrideMap.put(assetId, colaOverride);
                }
            }
        }

        return overrideMap;
    }

    // ============================================
    // Helper Methods
    // ============================================

    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
    }

    private Decimal getDecimalFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Decimal) {
            return (Decimal) val;
        }
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }

    private Boolean getBooleanFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        if (val == null) {
            return null;
        }
        if (val instanceof Boolean) {
            return (Boolean) val;
        }
        String strVal = String.valueOf(val).toLowerCase();
        return strVal == 'true' || strVal == '1';
    }

    private Object extractFieldValue(Map<String, Object> tagData, String fieldName) {
        if (tagData == null || !tagData.containsKey(fieldName)) {
            return null;
        }
        Object fieldObj = tagData.get(fieldName);
        if (fieldObj == null) {
            return null;
        }

        if (fieldObj instanceof Map<String, Object>) {
            Map<String, Object> fieldWrapper = (Map<String, Object>) fieldObj;
            if (fieldWrapper.containsKey('tagValue')) {
                return fieldWrapper.get('tagValue');
            }
            return null;
        }

        return fieldObj;
    }

    /**
     * @description Wrapper class for Contract COLA override information
     */
    @TestVisible
    private class ContractOverride {
        public Id contractId;
        public Decimal overridePercent;
        public Date persistUntil;
        public Boolean isValid;
    }

    // ============================================
    // MyCAP Out-Year Uplift Enforcement
    // ============================================

    /**
     * @description Apply MyCAP out-year uplift defaulting and Deal Desk approval flagging.
     *              Runs only on RENEWAL quote lines (QuoteAction.Type = 'Renew').
     *              COLA uplift is a renewal-time concept; MyCAP only modifies COLA uplift
     *              values, so new-business quotes are not affected.
     *
     *              Qualifying line: on a renewal QuoteAction
     *              AND multi-year (PricingTerm > 1 OR SubscriptionTerm > 1)
     *              AND annually billed (BillingFrequency = 'Annual')
     *              AND NOT fully prepaid (QLI attribute PS_Service_Type != 'Prepaid').
     *
     *              For qualifying lines that are not already overridden, defaults
     *              COLAUpliftPercent__c to the CMDT-configured value (default 3%).
     *
     *              If any qualifying line's effective uplift is below the CMDT minimum
     *              threshold, sets Quote.Mycap__c = true (triggering the existing
     *              Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered flow).
     *              Otherwise sets Quote.Mycap__c = false.
     *
     * @param ctxInstanceId Context instance ID
     * @param rule Global MyCAP rule CMDT record (already null/active checked)
     * @return Number of distinct Quotes evaluated
     */
    @TestVisible
    private Integer processMyCAPEligibility(String ctxInstanceId, MyCAP_Rules__mdt rule) {
        Decimal defaultUplift = rule.Default_Out_Year_Uplift_Percent__c != null
            ? rule.Default_Out_Year_Uplift_Percent__c : 3;
        Decimal minimumUplift = rule.Minimum_Out_Year_Uplift_Percent__c != null
            ? rule.Minimum_Out_Year_Uplift_Percent__c : 3;

        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();
            List<Object> rawLineItems = fetchSalesTransactionItems(ctx, ctxInstanceId);
            if (rawLineItems == null || rawLineItems.isEmpty()) {
                return 0;
            }

            // First pass: collect qualifying lines (renewal + multi-year + annual).
            // Renewal gate uses SalesTransactionActionType per-line context tag
            // (verified key in pricing context as of 2026-04-15). The legacy
            // QuoteActionId tag isn't hydrated, so we can't query QuoteAction by Id.
            // Track ALL renewal QLIs (for audit-field context writes) and the
            // subset that qualifies for MyCAP defaulting (multi-year + annual).
            Set<Id> qliIds = new Set<Id>();                   // qualifying only (for prepaid lookup)
            Set<Id> allRenewalQliIds = new Set<Id>();          // all renewal lines
            Set<Id> quoteIds = new Set<Id>();
            List<Map<String, Object>> allRenewalWrappers = new List<Map<String, Object>>();
            Set<Object> qualifyingWrapperSet = new Set<Object>(); // identity-based set
            Map<Map<String, Object>, Id> wrapperToQliId = new Map<Map<String, Object>, Id>();
            Map<Map<String, Object>, Id> wrapperToQuoteId = new Map<Map<String, Object>, Id>();
            Map<Map<String, Object>, Decimal> wrapperCurrentUplift = new Map<Map<String, Object>, Decimal>();
            Map<Map<String, Object>, Decimal> wrapperDefaultUplift = new Map<Map<String, Object>, Decimal>();
            Map<Map<String, Object>, Decimal> wrapperUnitPrice = new Map<Map<String, Object>, Decimal>();
            Map<Map<String, Object>, String> wrapperSolCat = new Map<Map<String, Object>, String>();
            Map<Map<String, Object>, Boolean> wrapperIsOverridden = new Map<Map<String, Object>, Boolean>();
            Map<Map<String, Object>, Decimal> wrapperPricingTermCount = new Map<Map<String, Object>, Decimal>();

            for (Object rawItem : rawLineItems) {
                Map<String, Object> itemWrapper = (rawItem instanceof Map<String, Object>)
                    ? (Map<String, Object>) rawItem : null;
                if (itemWrapper == null) continue;

                Map<String, Object> lineItem = extractLineItemData(rawItem);
                if (lineItem == null) continue;

                // Renewal gate
                String stActionType = getStringFromTag(lineItem, 'SalesTransactionActionType');
                if (stActionType != 'Renew') continue;

                // Extract QLI / Quote Ids from dataPath
                Id qliId;
                Id quoteId;
                Object dpObj = itemWrapper.get('dataPath');
                if (dpObj instanceof List<Object>) {
                    List<Object> dp = (List<Object>) dpObj;
                    if (dp.size() >= 1) {
                        try { qliId = Id.valueOf(String.valueOf(dp.get(dp.size() - 1))); } catch (Exception e) {}
                    }
                    if (dp.size() >= 2) {
                        try { quoteId = Id.valueOf(String.valueOf(dp.get(dp.size() - 2))); } catch (Exception e) {}
                    }
                }
                if (qliId == null) continue;

                // Read pricing context tags
                Decimal pricingTermCount = getDecimalFromTag(lineItem, 'PricingTermCount');
                String pricingTermUnit = getStringFromTag(lineItem, 'PricingTermUnit');
                Decimal itemSubscriptionTerm = getDecimalFromTag(lineItem, 'ItemSubscriptionTerm');
                Boolean isAnnualUnit = pricingTermUnit == 'Annual';
                Boolean isMultiYearAnnual = isAnnualUnit
                    && ((pricingTermCount != null && pricingTermCount > 1)
                        || (itemSubscriptionTerm != null && itemSubscriptionTerm > 1));

                allRenewalQliIds.add(qliId);
                if (quoteId != null) quoteIds.add(quoteId);
                allRenewalWrappers.add(itemWrapper);
                wrapperToQliId.put(itemWrapper, qliId);
                wrapperToQuoteId.put(itemWrapper, quoteId);
                wrapperCurrentUplift.put(itemWrapper, getDecimalFromTag(lineItem, 'COLA_Uplift_Percent__c'));
                wrapperDefaultUplift.put(itemWrapper, getDecimalFromTag(lineItem, 'Default_COLA_Uplift_Percent__c'));
                wrapperUnitPrice.put(itemWrapper, getDecimalFromTag(lineItem, 'UnitPrice'));
                wrapperSolCat.put(itemWrapper, getStringFromTag(lineItem, 'COLA_Solution_Category__c'));
                wrapperIsOverridden.put(itemWrapper, getBooleanFromTag(lineItem, 'IsCOLAOverridden__c'));
                wrapperPricingTermCount.put(itemWrapper, pricingTermCount);

                if (isMultiYearAnnual) {
                    qliIds.add(qliId);
                    qualifyingWrapperSet.add(itemWrapper);
                }
            }

            if (allRenewalWrappers.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'MyCAP: no renewal lines found');
                return 0;
            }

            // Fill in missing Quote Ids and get Default_COLA_Uplift_Percent__c
            // for override detection. The IsCOLAOverridden__c context tag has a
            // timing gap: users edit COLA% in the TLE but the flag isn't set until
            // the COLAUpliftHandler trigger fires AFTER pricing write-back.
            // So we compare context COLA% against the persisted default to detect
            // overrides that the boolean flag hasn't caught yet.
            Map<Id, Id> qliIdToQuoteId = new Map<Id, Id>();
            Map<Id, Decimal> qliIdToDefaultPct = new Map<Id, Decimal>();
            Map<Id, Decimal> qliIdToOutyearPct = new Map<Id, Decimal>();
            for (QuoteLineItem qli : [SELECT Id, QuoteId, Default_COLA_Uplift_Percent__c, COLA_Outyear_Uplift_Percent__c FROM QuoteLineItem WHERE Id IN :allRenewalQliIds]) {
                qliIdToQuoteId.put(qli.Id, qli.QuoteId);
                qliIdToDefaultPct.put(qli.Id, qli.Default_COLA_Uplift_Percent__c);
                qliIdToOutyearPct.put(qli.Id, qli.COLA_Outyear_Uplift_Percent__c);
                quoteIds.add(qli.QuoteId);
            }

            // Bulk prepaid lookup via QuoteLineItemAttribute.
            // Two-step: resolve the PS_Service_Type AttributeDefinition and the
            // 'Prepaid' AttributePicklistValue Ids, then filter QLAs by Id.
            // AttributeValue is not reliably filterable in WHERE clauses on this
            // entity, and AttributeName stores the display label ("PS Service Type")
            // rather than the DeveloperName. Id-based filtering is portable.
            Set<Id> prepaidQliIds = new Set<Id>();
            Id psAdId;
            Id psPicklistId;
            for (AttributeDefinition ad : [
                SELECT Id, PicklistId FROM AttributeDefinition
                WHERE DeveloperName = 'PS_Service_Type' LIMIT 1
            ]) {
                psAdId = ad.Id;
                psPicklistId = ad.PicklistId;
            }
            Id prepaidApvId;
            if (psPicklistId != null) {
                for (AttributePicklistValue apv : [
                    SELECT Id FROM AttributePicklistValue
                    WHERE PicklistId = :psPicklistId AND Value = 'Prepaid' LIMIT 1
                ]) {
                    prepaidApvId = apv.Id;
                }
            }
            if (psAdId != null && prepaidApvId != null) {
                for (QuoteLineItemAttribute qla : [
                    SELECT QuoteLineItemId FROM QuoteLineItemAttribute
                    WHERE QuoteLineItemId IN :qliIds
                      AND AttributeDefinitionId = :psAdId
                      AND AttributePicklistValueId = :prepaidApvId
                ]) {
                    prepaidQliIds.add(qla.QuoteLineItemId);
                }
            } else {
                System.debug(LoggingLevel.INFO, 'MyCAP: PS_Service_Type/Prepaid not found in org - skipping prepaid bypass');
            }
            System.debug(LoggingLevel.INFO, 'MyCAP: ' + prepaidQliIds.size() + ' of ' + qliIds.size() + ' qualifying lines are Prepaid (bypassed)');

            // Second pass: for EACH renewal QLI, build a context update so
            // RC pricing's write-back populates the audit fields correctly.
            // MyCAP-qualifying lines get COLA% defaulted to 3; others keep
            // their current COLA%. All lines get Pre-COLA / CalcPrice /
            // Source / Category / AppliedDate written via hydrated context
            // attributes so they survive the reprice cycle.
            Map<Id, Decimal> qliCOLADefaults = new Map<Id, Decimal>();
            Set<Id> quotesToFlagTrue = new Set<Id>();
            Set<Id> quotesToFlagFalse = new Set<Id>();
            List<Map<String, Object>> allContextUpdates = new List<Map<String, Object>>();

            for (Map<String, Object> itemWrapper : allRenewalWrappers) {
                Id qliId = wrapperToQliId.get(itemWrapper);
                Id quoteId = wrapperToQuoteId.get(itemWrapper);
                if (quoteId == null) quoteId = qliIdToQuoteId.get(qliId);

                Boolean isOverridden = wrapperIsOverridden.get(itemWrapper) == true;
                Decimal currentUplift = wrapperCurrentUplift.get(itemWrapper);
                Decimal defaultPct = wrapperDefaultUplift.get(itemWrapper);
                Decimal unitPrice = wrapperUnitPrice.get(itemWrapper);
                String solCat = wrapperSolCat.get(itemWrapper);
                Decimal pricingTermCount = wrapperPricingTermCount.get(itemWrapper);
                Boolean isQualifying = qualifyingWrapperSet.contains(itemWrapper);
                Boolean isPrepaid = prepaidQliIds.contains(qliId);

                // Detect overrides: IsCOLAOverridden__c has a timing gap in the
                // TLE (flag only set by trigger AFTER pricing write-back). Also
                // compare context COLA% against the persisted Default to catch
                // edits the boolean hasn't reflected yet.
                Decimal persistedDefault = qliIdToDefaultPct.get(qliId);
                Boolean isEffectivelyOverridden = isOverridden
                    || (currentUplift != null && persistedDefault != null && currentUplift != persistedDefault);

                // Determine target uplift for this line
                Decimal targetUplift = currentUplift;
                String source = isEffectivelyOverridden ? 'Line Override' : 'CMDT Lookup';

                if (isQualifying && !isPrepaid && !isEffectivelyOverridden) {
                    // MyCAP-qualifying, not overridden -> default to 3%
                    if (currentUplift == null || currentUplift != defaultUplift) {
                        targetUplift = defaultUplift;
                        source = 'MyCAP Default';
                        qliCOLADefaults.put(qliId, defaultUplift);
                    } else {
                        targetUplift = defaultUplift; // already at 3%
                        source = 'MyCAP Default';
                    }
                }

                // Flag evaluation for MyCAP-qualifying lines.
                // Flag if EITHER year-1 COLA% OR outyear COLA% is below minimum.
                if (isQualifying && !isPrepaid && quoteId != null) {
                    Decimal effectiveUplift = isEffectivelyOverridden ? currentUplift : targetUplift;
                    Decimal outyearPct = qliIdToOutyearPct.get(qliId);
                    Boolean year1BelowMin = effectiveUplift != null && effectiveUplift < minimumUplift;
                    Boolean outyearBelowMin = outyearPct != null && outyearPct < minimumUplift;
                    if (year1BelowMin || outyearBelowMin) {
                        quotesToFlagTrue.add(quoteId);
                    }
                }

                // Build the context audit update for this line
                Map<String, Object> updatePayload = buildCOLAContextUpdate(
                    itemWrapper, targetUplift, source, unitPrice, defaultPct, solCat, pricingTermCount
                );
                if (updatePayload != null) allContextUpdates.add(updatePayload);
            }
            for (Id qId : quoteIds) {
                if (!quotesToFlagTrue.contains(qId)) quotesToFlagFalse.add(qId);
            }

            // Context writes for COLA audit fields are handled by processLineItems
            // via buildItemUpdate. A second updateContextAttributes call here
            // overwrites those values with recomputed amounts that lack Asset
            // price data, causing blank fields. MyCAP only evaluates the flag.
            System.debug(LoggingLevel.INFO, 'MyCAP: evaluated ' + allRenewalWrappers.size()
                + ' renewal lines, ' + qliCOLADefaults.size() + ' defaulted');

            // Quote.Mycap__c cannot be written from a QLI pricing context,
            // so we defer it to a Queueable. Quote-level DML does NOT trigger
            // the pricing engine, so no repricing loop.
            if (!quotesToFlagTrue.isEmpty() || !quotesToFlagFalse.isEmpty()) {
                System.enqueueJob(new MyCAPFlagApplier(quotesToFlagTrue, quotesToFlagFalse));
                System.debug(LoggingLevel.INFO, 'MyCAP: enqueued - Quotes flag=true:' + quotesToFlagTrue.size()
                    + ' flag=false:' + quotesToFlagFalse.size());
            }

            return quoteIds.size();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MyCAP processing error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            return 0;
        }
    }

    /**
     * @description Query the SalesTransactionItem raw line item list from context.
     *              Mirrors the extraction pattern in processLineItems so both branches
     *              work off the same context shape.
     */
    private List<Object> fetchSalesTransactionItems(Context.IndustriesContext ctx, String ctxInstanceId) {
        Map<String, Object> queryInput = new Map<String, Object>{
            'contextId' => ctxInstanceId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        };
        Map<String, Object> apiResponse = ctx.queryTags(queryInput);
        if (apiResponse == null) return null;

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            if (qrObj instanceof Map<String, Object>) {
                queryResult = (Map<String, Object>) qrObj;
            } else {
                return null;
            }
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        } else {
            return null;
        }

        if (!queryResult.containsKey('SalesTransactionItem')) return null;
        Object itemsObj = queryResult.get('SalesTransactionItem');
        if (itemsObj instanceof List<Object>) {
            return (List<Object>) itemsObj;
        }
        return new List<Object>{ itemsObj };
    }

    /**
     * @description Queueable that sets Quote.Mycap__c after the prehook returns.
     *              Pricing context forbids DML on Quote from inside a prehook;
     *              deferring to a Queueable lets the DML run in its own transaction.
     *              QLI field updates are handled by context writes + pricing
     *              engine write-back — no QLI DML here to avoid repricing loops.
     */
    public class MyCAPFlagApplier implements Queueable {
        private Set<Id> flagTrueIds;
        private Set<Id> flagFalseIds;

        public MyCAPFlagApplier(Set<Id> flagTrueIds, Set<Id> flagFalseIds) {
            this.flagTrueIds = flagTrueIds == null ? new Set<Id>() : flagTrueIds;
            this.flagFalseIds = flagFalseIds == null ? new Set<Id>() : flagFalseIds;
        }

        public void execute(QueueableContext ctx) {
            // QLI field updates (COLA%, audit fields) are handled entirely by
            // the prehook's context writes + the pricing engine's write-back
            // phase. Doing QLI DML here triggers a repricing cycle, which fires
            // the prehook again and creates a DML→reprice→DML loop that flashes
            // the "prices aren't up to date" banner 2-3 times before converging.
            //
            // This Queueable now ONLY handles Quote.Mycap__c — a Quote-level
            // field that cannot be written from a QLI pricing context and whose
            // DML does not trigger the pricing engine.

            // Quote.Mycap__c flag flip
            Set<Id> all = new Set<Id>();
            all.addAll(flagTrueIds);
            all.addAll(flagFalseIds);
            if (!all.isEmpty()) {
                List<Quote> toUpdate = new List<Quote>();
                for (Quote q : [SELECT Id, Mycap__c FROM Quote WHERE Id IN :all]) {
                    Boolean desired = flagTrueIds.contains(q.Id);
                    Boolean current = q.Mycap__c == true;
                    if (desired != current) {
                        toUpdate.add(new Quote(Id = q.Id, Mycap__c = desired));
                    }
                }
                if (!toUpdate.isEmpty()) {
                    Database.SaveResult[] qRes = Database.update(toUpdate, false);
                    for (Integer i = 0; i < qRes.size(); i++) {
                        if (!qRes[i].isSuccess()) {
                            for (Database.Error e : qRes[i].getErrors()) {
                                System.debug(LoggingLevel.WARN, 'MyCAP Quote update FAIL: ' + toUpdate[i].Id + ' ' + e.getStatusCode() + ' - ' + e.getMessage());
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * @description Shared builder for COLA context attribute updates. All
     *              hydration-mapped attributes only - no QLI-only fields.
     */
    private Map<String, Object> buildCOLAContextUpdate(Map<String, Object> itemWrapper, Decimal uplift, String source, Decimal unitPrice, Decimal defaultPct, String solCat, Decimal pricingTermCount) {
        List<Object> dataPath;
        if (itemWrapper.containsKey('dataPath')) {
            dataPath = (List<Object>) itemWrapper.get('dataPath');
        } else {
            return null;
        }
        if (dataPath == null || dataPath.isEmpty()) return null;

        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) updatePath.remove(0);

        // Derive Pre-COLA price: UnitPrice / (1 + defaultPct/100)
        Decimal preCOLA;
        if (unitPrice != null && defaultPct != null && defaultPct != 0) {
            preCOLA = (unitPrice / (1 + (defaultPct / 100))).setScale(2, System.RoundingMode.HALF_UP);
        } else if (unitPrice != null) {
            preCOLA = unitPrice;
        }
        // Compound COLA across pricing terms: each year's price = previous year * (1 + uplift%).
        // For single-year deals (terms <= 1), this produces the same result as flat.
        Decimal calculated;
        if (preCOLA != null && uplift != null) {
            Integer terms = (pricingTermCount != null && pricingTermCount > 1) ? pricingTermCount.intValue() : 1;
            Decimal yearPrice = preCOLA;
            for (Integer i = 0; i < terms; i++) {
                yearPrice = yearPrice * (1 + (uplift / 100));
            }
            calculated = yearPrice.setScale(2, System.RoundingMode.HALF_UP);
        }

        // IsCOLAOverridden__c is now inputoutput.
        // Only hydration-mapped attributes — COLAApplied__c and
        // COLAUpliftPercent__c are context-only and poison the batch.
        List<Map<String, Object>> attributes = new List<Map<String, Object>>();
        if (calculated != null) {
            attributes.add(new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => calculated });
        }
        if (preCOLA != null) {
            attributes.add(new Map<String, Object>{ 'attributeName' => 'Pre_COLA_Price__c', 'attributeValue' => preCOLA });
        }
        if (String.isNotBlank(source)) {
            attributes.add(new Map<String, Object>{ 'attributeName' => 'COLA_Source__c', 'attributeValue' => source });
        }
        if (String.isNotBlank(solCat)) {
            attributes.add(new Map<String, Object>{ 'attributeName' => 'COLA_Solution_Category__c', 'attributeValue' => solCat });
        }
        attributes.add(new Map<String, Object>{ 'attributeName' => 'COLA_Applied_Date__c', 'attributeValue' => Datetime.now() });

        Map<String, Object> result = new Map<String, Object>();
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });
        result.put('attributes', attributes);
        return result;
    }
}