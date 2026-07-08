/**
 * @description Pure COLA calculation + payload-assembly logic extracted from
 *              COLAUpliftPrehook (Wave-2 hook-thinning). Contains only deterministic
 *              functions with NO SOQL / DML / RCA-context I/O — the 3-tier override
 *              predicate (line override > contract override > CMDT lookup), the uplift
 *              math, and the context-update payload builders. The hook retains all
 *              context marshalling, queryTags/updateContextAttributes, CMDT/SOQL loads,
 *              and the stateful orchestration (buildLineItemUpdates, processMyCAPEligibility)
 *              and delegates the pure pieces here via thin seams. Method bodies are moved
 *              byte-verbatim so the live path and the unit tests can never diverge.
 *
 *              Reuses (does not duplicate) ContextTagReader for tag extraction.
 */
public with sharing class COLAUpliftCalculator {

    /**
     * @description True when a stored line COLA% differs from the applied tier's stamped
     *              Default_COLA_Uplift_Percent__c — i.e. a genuine rep Line Override the trigger
     *              already classified (mirrors QuoteLineItem.Is_COLA_Overridden__c). A null stamped
     *              default (legacy / handler-skipped line) is NOT treated as an override, so the
     *              caller falls back to the CMDT-based detection unchanged.
     */
    public static Boolean isPersistedLineOverride(Decimal lineOverridePercent, Decimal stampedDefault) {
        return stampedDefault != null
            && lineOverridePercent != null
            && lineOverridePercent != stampedDefault;
    }

    /**
     * @description Build explainer text for waterfall display
     * @param colaPercent The COLA percentage
     * @param solutionCategory The product's solution category
     * @param colaSource The source of the COLA value
     * @return Formatted explainer text
     */
    public static String buildExplainerText(Decimal colaPercent, String solutionCategory, String colaSource) {
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
     * @description Renewal-maintenance COLA net from stamped prior-year components
     *              (Base − prior partner − prior discretionary) × (1 + COLA%).
     */
    public static Decimal computeStampedMaintenanceColaNet(QuoteLineItem qli) {
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

    /**
     * @description Parsed-payload overload of isOrderTransaction: inspects dataPath[0]
     *              of the first item (Order roots start with 801). Pure.
     */
    public static Boolean isOrderTransaction(List<Object> items) {
        if (items == null || items.isEmpty()) return false;
        Object first = items.get(0);
        if (!(first instanceof Map<String, Object>)) return false;
        Map<String, Object> firstItem = (Map<String, Object>) first;
        Object dpObj = firstItem.get('dataPath');
        if (!(dpObj instanceof List<Object>)) return false;
        List<Object> dp = (List<Object>) dpObj;
        if (dp.isEmpty()) return false;
        String rootId = String.valueOf(dp.get(0));
        return rootId != null && rootId.startsWith('801');
    }

    /**
     * @description SC-3350 net-price fix: build an ISOLATED context update that seeds
     *              NetUnitPrice = the COLA-adjusted price for a renewal line. Kept in
     *              its own batch (submitted separately by processLineItems) because a
     *              prehook-level NetUnitPrice write is the only mechanism proven live
     *              (2026-06-11) to COMMIT the net to the waterfall for a non-derived
     *              renewal line — a Formula/Assignment write from a procedure ListGroup
     *              updates only the context var and never flushes.
     */
    public static Map<String, Object> buildNetUnitPriceUpdate(
        Map<String, Object> itemWrapper,
        Decimal colaPrice
    ) {
        if (colaPrice == null || colaPrice <= 0) {
            return null;
        }
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
        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{
                'attributeName' => 'NetUnitPrice',
                'attributeValue' => colaPrice
            }
        };
        Map<String, Object> result = new Map<String, Object>();
        result.put('nodePath', new Map<String, Object>{ 'dataPath' => updatePath });
        result.put('attributes', attributes);
        return result;
    }

    /**
     * @description Renewal maintenance stamped-COLA context update: writes
     *              COLACalculatedPrice__c (+ PartnerDiscountPercent / Discount echoes).
     */
    public static Map<String, Object> buildMaintenanceColaItemUpdate(
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

        List<Map<String, Object>> attributes = new List<Map<String, Object>>{
            new Map<String, Object>{ 'attributeName' => 'COLACalculatedPrice__c', 'attributeValue' => colaNet }
        };

        if (qli.PartnerDiscountPercent != null && qli.PartnerDiscountPercent > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => qli.PartnerDiscountPercent
            });
        } else if (qli.Prior_Partner_Discount__c != null && qli.Base_Price__c > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'PartnerDiscountPercent',
                'attributeValue' => ((qli.Prior_Partner_Discount__c / qli.Base_Price__c) * 100).setScale(2, System.RoundingMode.HALF_UP)
            });
        }

        if (qli.Discount != null && qli.Discount > 0) {
            attributes.add(new Map<String, Object>{
                'attributeName' => 'Discount',
                'attributeValue' => qli.Discount
            });
        }

        System.debug(LoggingLevel.INFO, 'RENEWAL MAINT COLA PREHOOK: QLI ' + qli.Id + ' -> ' + colaNet);

        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => attributes
        };
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
    public static Map<String, Object> buildItemUpdate(
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
     * @description Extract line item data from raw context object
     * @param rawItem The raw item from context
     * @return Map of line item data or null
     */
    public static Map<String, Object> extractLineItemData(Object rawItem) {
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
     * @description Shared builder for COLA context attribute updates. All
     *              hydration-mapped attributes only - no QLI-only fields.
     */
    public static Map<String, Object> buildCOLAContextUpdate(Map<String, Object> itemWrapper, Decimal uplift, String source, Decimal unitPrice, Decimal defaultPct, String solCat, Decimal pricingTermCount) {
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
