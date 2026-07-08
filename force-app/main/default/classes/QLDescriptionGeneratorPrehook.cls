/**
 * @description Apex Prehook for Revenue Cloud Quote pricing that auto-generates
 *              QuoteLineItem.Description from a fixed, hardcoded list of
 *              configuration attributes.
 *
 *              Output format (per "Text Population in the Line Description.pdf"):
 *
 *                Combine a list of values using " | " as a separator, ignoring
 *                empty ones. Single-line. No labels (except the special-case
 *                Unit Type segment described below).
 *
 *              The output is the Product Name followed by up to 10
 *              attribute segments, all joined by " | ":
 *
 *                  0.  Product Name (Product2.Name on the line)
 *                  1.  Unit Type    (special logic, depends on Unit Quantity attribute)
 *                  2.  License Type
 *                  3.  PS Service Type
 *                  4.  Feature      (UAT attribute label "Feature Options")
 *                  5.  Maintenance Type (UAT label "Maintenance Type Defn")
 *                  6.  Deployment Type  (UAT label "Deployment Option")
 *                  7.  Server Location Type
 *                  8.  Power License Type
 *                  9.  Server Type
 *                  10. Group Number
 *
 *              Unit Type rules:
 *                - If Unit Type is blank → skip the segment entirely.
 *                - If Unit Type = "Per Users":
 *                    - With Unit Quantity attribute value → "Users: <qty>"
 *                    - Without Unit Quantity attribute       → "Per User"
 *                - Any other Unit Type value (e.g., "Flat Fee", "Devices"):
 *                    - With Unit Quantity attribute value → "<Unit Type>: <qty>"
 *                    - Without Unit Quantity attribute       → "<Unit Type>" as-is
 *
 *              The Unit Quantity used in the rendering above is the value of
 *              a configuration attribute on the line — NOT the standard
 *              QuoteLineItem.Quantity field. Attribute_Volume is preferred;
 *              when absent, Number_of_Units is used (e.g. beSECURE device
 *              ranges). Either is consulted for ANY Unit Type value (not only
 *              "Per Users"); the "Per Users" branch is a special case that
 *              translates to a "Users:" prefix and the "Per User" wording
 *              for the no-quantity case. Lines whose product exposes neither
 *              attribute simply omit the count.
 *
 *              Behavior:
 *              - Overwrites Description on every Quote pricing run for any line
 *                that produces at least one non-empty segment. The Product Name
 *                is always the leading segment, so every line with a product
 *                gets at least a product-name description.
 *              - Lines with no SalesTransactionItemAttribute records still
 *                receive a product-name-only Description (attribute-less
 *                products such as flat license fees no longer land blank).
 *                Only a line with neither a product name nor any attribute
 *                segment is skipped.
 *              - Description is written via Context.IndustriesContext
 *                .updateContextAttributes targeting the SalesTrxnItemDescription
 *                hydration-mapped attribute. Direct DML is FORBIDDEN inside
 *                the pricing prehook context (the runtime DML limit is 0
 *                — any DML throws "Too many DML statements: 1").
 *
 * @note Quote pricing only. Orders do not allow product/configuration
 *       changes after conversion, so Description is fixed at conversion time
 *       and does not need regeneration in the Order pricing context. If the
 *       prehook is somehow invoked from a non-Quote context, it bails safely.
 *
 * @note Register LAST in the Quote pricing prehook chain.
 *
 * @note OPEN ITEMS to confirm with Fortra before go-live:
 *       - Confirm exact AttributeDefinition.DeveloperName for each of the 10
 *         attributes (the deck shows display labels, not API names — the
 *         constants below are best-guess and need verification).
 *       - Confirm the literal value emitted by the configurator for the
 *         Unit Type "Per Users" case ("Per Users" vs "Users").
 *       - Confirm the deck's sample output discrepancy: page 4 logic says
 *         "Users: 10" but page 8 sample shows "User: 15" — the code uses
 *         "Users:" (plural, matching the logic).
 *
 * @author Marc DeBrey
 * @date April 2026
 * @version 8.0 — Product Name prepended as the leading segment. Adds a
 *                bulk SOQL on QuoteLineItem to read each line's Product Name.
 *                SOQL is permitted in prehooks (only DML is forbidden).
 *
 *                v7.0 — Description writeback via updateContextAttributes;
 *                direct DML rejected with "Too many DML statements: 1".
 *                v6.0 — Unit Quantity attribute applies to ANY Unit Type.
 *                v5.0 — Unit Quantity from configuration attribute.
 */
global class QLDescriptionGeneratorPrehook implements RevSignaling.SignalingApexProcessor {

    // ============================================================
    // SPEC CONSTANTS — single source of truth for the description
    // ============================================================

    /** Separator between non-empty segments. */
    @TestVisible private static final String SEPARATOR = ' | ';

    /**
     * @description Truncation marker appended when the joined string exceeds
     *              the Description Text(4000) limit. Uses the same separator
     *              shape so the truncated output remains readable.
     */
    @TestVisible private static final String TRUNCATION_MARKER = ' | [truncated]';

    @TestVisible private static final Integer DESCRIPTION_MAX_LENGTH = 4000;

    /**
     * @description Configuration attribute DeveloperNames in render order,
     *              AFTER the special Unit Type segment. Empty values are
     *              skipped silently. NOTE: these names are best-guess from
     *              the UAT labels on page 5 of the deck and must be confirmed
     *              against AttributeDefinition.DeveloperName in fortrauat.
     */
    @TestVisible private static final List<String> ATTRIBUTE_ORDER = new List<String>{
        // PLACEHOLDER — License Type is in scope per the deck (page 7) but
        // no AttributeDefinition with this DeveloperName exists in fortrauat
        // as of 2026-04-27. The deck flagged the UAT name as "?" indicating
        // the attribute may not be created yet. Leaving the constant here is
        // forward-compatible: when the attribute is created with
        // DeveloperName "License_Type" the code will pick it up
        // automatically (missing attribute values are silently skipped).
        'License_Type',
        'PS_Service_Type',           // verified in fortrauat 2026-04-27
        'Feature_Options',           // verified in fortrauat 2026-04-27 (deck logic "Feature")
        'Maintenance_Type_Defn',     // verified in fortrauat 2026-04-27 (deck logic "Maintenance Type")
        'Deployment_Option',         // verified in fortrauat 2026-04-27 (deck logic "Deployment Type")
        'Server_Location_Type',      // verified in fortrauat 2026-04-27
        'Power_License_Type',        // verified in fortrauat 2026-04-27
        'Server_Type',               // verified in fortrauat 2026-04-27
        'Group_Number'               // verified in fortrauat 2026-04-27 (NOT the same as PGroup, which is excluded)
    };

    /** Attribute that drives the special-case Unit Type segment. */
    @TestVisible private static final String UNIT_TYPE_ATTR = 'Unit_Type';

    /**
     * @description Configuration attribute carrying the unit count used in
     *              the Unit Type segment rendering. Read from the runtime
     *              context attribute map — NOT from QuoteLineItem.Quantity.
     *              Products that don't expose this attribute simply omit
     *              the count from their Unit Type segment.
     *
     *              The deck refers to this attribute as "Unit Quantity"
     *              (its display Label). The actual AttributeDefinition
     *              DeveloperName in fortrauat is "Attribute_Volume" with
     *              Name "Unit Volume" — verified 2026-04-27.
     */
    @TestVisible private static final String UNIT_QUANTITY_ATTR = 'Attribute_Volume';

    /**
     * @description Fallback unit-count attribute when Attribute_Volume is not
     *              exposed on the product. Verified on beSECURE QLI
     *              0QLWC000003bIvV4AU (Number of Units picklist, e.g. "36-65").
     */
    @TestVisible private static final String NUMBER_OF_UNITS_ATTR = 'Number_of_Units';

    /**
     * @description Unit Type AttributeValue that triggers "Users: <qty>" /
     *              "Per User" rendering. The deck calls this value "Per Users"
     *              (plural) but the configurator actually emits "Per User"
     *              (singular) — verified in fortrauat 2026-04-27 against
     *              QLI 0QLWC00000311rZ4AQ.
     */
    @TestVisible private static final String UNIT_TYPE_PER_USERS = 'Per User';

    /**
     * @description Hydration-mapped context attribute name that writes back
     *              to QuoteLineItem.Description (verified in
     *              SalesTransactionContextExt.contextDefinition-meta.xml
     *              line 5003, fieldType=inputoutput).
     */
    @TestVisible private static final String CONTEXT_DESCRIPTION_ATTR = 'SalesTrxnItemDescription';

    @TestVisible private static final String ROLE_SEGMENT = 'Segment';
    @TestVisible private static final String ROLE_UNIT_TYPE = 'Unit Type';
    @TestVisible private static final String ROLE_UNIT_QTY = 'Unit Quantity';
    @TestVisible private static final String ROLE_UNIT_QTY_FALLBACK = 'Unit Quantity Fallback';

    /** @description Test seam: when non-null, used instead of the live SOQL. */
    @TestVisible private static List<QL_Description_Attribute__mdt> configOverride;

    private static Boolean isProcessing = false;

    // ============================================================
    // RESOLVED CONFIG
    // ============================================================

    /**
     * @description Resolved, runtime-ready description configuration. Built
     *              either from active QL_Description_Attribute__mdt rows or,
     *              when none exist, from the in-code defaults (today's list).
     */
    public class ResolvedConfig {
        // Fields are public so the extracted QLDescriptionCalculator can read them (Wave-2 thinning).
        public List<String> segmentNames = new List<String>();
        public String unitTypeAttr;
        public String unitTypeTrigger;
        public String unitQtyPrimary;
        public String unitQtyFallback;
    }

    /** @description Default config equal to the legacy hard-coded behavior. */
    @TestVisible
    private ResolvedConfig defaultConfig() {
        ResolvedConfig cfg = new ResolvedConfig();
        cfg.segmentNames = ATTRIBUTE_ORDER.clone();
        cfg.unitTypeAttr = UNIT_TYPE_ATTR;
        cfg.unitTypeTrigger = UNIT_TYPE_PER_USERS;
        cfg.unitQtyPrimary = UNIT_QUANTITY_ATTR;
        cfg.unitQtyFallback = NUMBER_OF_UNITS_ATTR;
        return cfg;
    }

    /**
     * @description Resolve runtime config: the override (tests) or active
     *              QL_Description_Attribute__mdt rows; empty -> defaults.
     */
    @TestVisible
    private ResolvedConfig loadConfig() {
        List<QL_Description_Attribute__mdt> rows = (configOverride != null)
            ? configOverride
            : queryActiveConfig();
        if (rows == null || rows.isEmpty()) {
            return defaultConfig();
        }
        return buildResolvedConfig(rows);
    }

    private List<QL_Description_Attribute__mdt> queryActiveConfig() {
        return [
            SELECT Attribute_API_Name__c, Role__c, Sort_Order__c, Match_Value__c
            FROM QL_Description_Attribute__mdt
            WHERE Active__c = true
            ORDER BY Sort_Order__c NULLS LAST
        ];
    }

    /**
     * @description Build a ResolvedConfig from rows. Segment rows are ordered
     *              by Sort_Order__c (nulls last, ties keep encounter order).
     *              The first active row of each unit role wins.
     */
    @TestVisible
    private ResolvedConfig buildResolvedConfig(List<QL_Description_Attribute__mdt> rows) {
        ResolvedConfig cfg = new ResolvedConfig();
        Map<Decimal, List<String>> segmentsByOrder = new Map<Decimal, List<String>>();

        for (QL_Description_Attribute__mdt r : rows) {
            String apiName = r.Attribute_API_Name__c;
            if (String.isBlank(apiName)) {
                continue;
            }
            String role = r.Role__c;
            if (role == ROLE_SEGMENT) {
                Decimal ord = (r.Sort_Order__c == null) ? 999999 : r.Sort_Order__c;
                if (!segmentsByOrder.containsKey(ord)) {
                    segmentsByOrder.put(ord, new List<String>());
                }
                segmentsByOrder.get(ord).add(apiName);
            } else if (role == ROLE_UNIT_TYPE && cfg.unitTypeAttr == null) {
                cfg.unitTypeAttr = apiName;
                cfg.unitTypeTrigger = r.Match_Value__c;
            } else if (role == ROLE_UNIT_QTY && cfg.unitQtyPrimary == null) {
                cfg.unitQtyPrimary = apiName;
            } else if (role == ROLE_UNIT_QTY_FALLBACK && cfg.unitQtyFallback == null) {
                cfg.unitQtyFallback = apiName;
            }
        }

        List<Decimal> orders = new List<Decimal>(segmentsByOrder.keySet());
        orders.sort();
        for (Decimal o : orders) {
            cfg.segmentNames.addAll(segmentsByOrder.get(o));
        }
        return cfg;
    }

    // ============================================================
    // ENTRY POINT
    // ============================================================

    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();

        if (isProcessing) {
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'QLDescriptionGeneratorPrehook skipped - already processing';
            return response;
        }

        try {
            isProcessing = true;
            String contextId = request != null ? request.ctxInstanceId : null;

            if (String.isBlank(contextId)) {
                response.status = RevSignaling.TransactionStatus.FAILED;
                response.message = 'Context instance ID is required';
                return response;
            }

            Context.IndustriesContext ctx = new Context.IndustriesContext();

            // Step 1 — discover line items and their dataPaths (needed for
            // updateContextAttributes node-path targeting).
            Map<Id, List<Object>> dataPathByLineId = queryLineItemDataPaths(ctx, contextId);
            if (dataPathByLineId.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No SalesTransactionItem records — nothing to generate';
                return response;
            }

            // Quote-only scope guard. If a non-QuoteLineItem context invokes
            // this prehook (e.g., a misconfigured Order pricing procedure),
            // bail safely without touching anything.
            if (!isQuoteLineSet(dataPathByLineId.keySet())) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'Non-Quote context — Description generation skipped';
                return response;
            }

            // Step 2 — read configured attributes for each line. Lines with no
            // attributes are NOT short-circuited: they still receive a
            // product-name-only description (spec: Product Name is always the
            // leading segment). Attribute-less products (e.g. flat license fees)
            // otherwise land blank on the quote, order, and asset.
            Map<Id, Map<String, String>> attrsByLineId = queryConfiguredAttributes(ctx, contextId);

            // Step 3 — read the Product Name for EVERY line in scope (not only
            // lines that have attributes), since the product name is the leading
            // description segment for every line.
            Map<Id, String> productNameByLineId = queryProductNames(dataPathByLineId.keySet());

            // Step 4 — build a context update payload for every line that
            // produces a non-null description (product name and/or attributes).
            ResolvedConfig cfg = loadConfig();
            List<Map<String, Object>> contextUpdates =
                buildContextUpdates(attrsByLineId, dataPathByLineId, productNameByLineId, cfg);

            // Step 5 — submit all updates in one call.
            Integer updated = submitContextUpdates(ctx, contextId, contextUpdates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Generated descriptions for ' + updated + ' of ' + dataPathByLineId.size() + ' lines';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'QLDescriptionGeneratorPrehook error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Description generation completed with warnings: ' + e.getMessage();
        } finally {
            isProcessing = false;
        }

        return response;
    }

    // ============================================================
    // SCOPE GUARD — Quote only
    // ============================================================

    /**
     * @description True iff the first Id in the set is a QuoteLineItem.
     *              Used to bail out safely if the prehook is invoked from a
     *              non-Quote pricing context.
     */
    @TestVisible
    private Boolean isQuoteLineSet(Set<Id> lineIds) {
        if (lineIds == null || lineIds.isEmpty()) {
            return false;
        }
        Schema.SObjectType firstType = (new List<Id>(lineIds))[0].getSObjectType();
        return firstType == QuoteLineItem.SObjectType;
    }

    // ============================================================
    // CONTEXT ATTRIBUTE QUERY
    // ============================================================

    /**
     * @description Mirror of HardwareAttributePricingPrehook.queryConfiguredAttributes
     *              (force-app/main/default/classes/HardwareAttributePricingPrehook.cls:331-444).
     */
    @TestVisible
    private Map<Id, Map<String, String>> queryConfiguredAttributes(Context.IndustriesContext ctx, String contextId) {
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItemAttribute' }
            };
            // NOTE: this live queryTags call MUST stay inside this try/catch. The original behavior
            // swallows any queryTags failure and returns an empty map (the caller then short-circuits
            // execute() with "No SalesTransactionItemAttribute records"). The response PARSE logic is
            // extracted to parseConfiguredAttributes(Map) so it can be unit-tested with a hand-built
            // response, but the swallow-and-continue contract is preserved byte-for-byte.
            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            result = parseConfiguredAttributes(apiResponse);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'queryConfiguredAttributes error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * @description Parse a queryTags(SalesTransactionItemAttribute) response into a map of
     *              line-item Id -> (attribute name -> attribute value). Pure of any live-context
     *              dependency, so it can be unit-tested with a hand-built response map. Handles the
     *              nested {queryResult:{SalesTransactionItemAttribute:[...]}} and the flatter
     *              {SalesTransactionItemAttribute:...} shapes, the nested-tagValue vs flat node
     *              layouts, the ParentReference vs dataPath-parent resolution, the Attribute vs
     *              AttributeKeyName fallback, and the bad-id Id.valueOf guard.
     * @param apiResponse Raw response map from queryTags
     * @return Map of parent line Id -> attribute map (empty when nothing parses)
     */
    @TestVisible
    private Map<Id, Map<String, String>> parseConfiguredAttributes(Map<String, Object> apiResponse) {
        return QLDescriptionCalculator.parseConfiguredAttributes(apiResponse);
    }

    // ============================================================
    // DESCRIPTION BUILDING
    // ============================================================

    /**
     * @description Build the pipe-separated Description for one line.
     *              Output shape: "<Product Name> | <Unit Type segment> |
     *              <attr 2> | ... | <attr 10>", with empty values skipped.
     *              The Product Name is always the leading segment; attribute
     *              segments are appended only when the line has attributes, so
     *              attribute-less products (e.g. flat license fees) render as
     *              the product name alone.
     * @return Joined string on success.
     *         null only when there is neither a product name nor any attribute
     *         segment to render.
     */
    @TestVisible
    private String buildDescription(String productName, Map<String, String> attrs) {
        return buildDescription(productName, attrs, defaultConfig());
    }

    @TestVisible
    private String buildDescription(String productName, Map<String, String> attrs, ResolvedConfig cfg) {
        return QLDescriptionCalculator.buildDescription(productName, attrs, cfg);
    }

    /**
     * @description Compute the leading Unit Type segment.
     *              Returns null when the segment should be omitted.
     *              The Unit Quantity used in the rendering is read from the
     *              configuration attribute map for ANY Unit Type value —
     *              never from the standard QuoteLineItem.Quantity field.
     */
    @TestVisible
    private String computeUnitTypeSegment(Map<String, String> attrs) {
        return computeUnitTypeSegment(attrs, defaultConfig());
    }

    @TestVisible
    private String computeUnitTypeSegment(Map<String, String> attrs, ResolvedConfig cfg) {
        return QLDescriptionCalculator.computeUnitTypeSegment(attrs, cfg);
    }

    /**
     * @description Resolve the unit count for the Unit Type segment.
     *              Attribute_Volume wins when present; otherwise Number_of_Units.
     * @return Trimmed quantity string, or null when neither attribute has a value.
     */
    @TestVisible
    private String resolveUnitQuantity(Map<String, String> attrs) {
        return resolveUnitQuantity(attrs, defaultConfig());
    }

    @TestVisible
    private String resolveUnitQuantity(Map<String, String> attrs, ResolvedConfig cfg) {
        return QLDescriptionCalculator.resolveUnitQuantity(attrs, cfg);
    }

    // ============================================================
    // LINE ITEM DATAPATH QUERY
    // ============================================================

    /**
     * @description Query SalesTransactionItem from the runtime context and
     *              return a map of line item Id → dataPath. The dataPath is
     *              required by updateContextAttributes to target each line's
     *              node in the context tree. Mirrors the queryTags pattern
     *              used elsewhere in this codebase.
     */
    @TestVisible
    private Map<Id, List<Object>> queryLineItemDataPaths(Context.IndustriesContext ctx, String contextId) {
        Map<Id, List<Object>> result = new Map<Id, List<Object>>();
        try {
            Map<String, Object> queryInput = new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{ 'SalesTransactionItem' }
            };
            // NOTE: this live queryTags call MUST stay inside this try/catch. The original behavior
            // swallows any queryTags failure and returns an empty map (the caller then short-circuits
            // execute() with "No SalesTransactionItem records"). The response PARSE logic is extracted
            // to parseLineItemDataPaths(Map) so it can be unit-tested with a hand-built response, but
            // the swallow-and-continue contract is preserved byte-for-byte.
            Map<String, Object> apiResponse = ctx.queryTags(queryInput);
            result = parseLineItemDataPaths(apiResponse);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'queryLineItemDataPaths error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * @description Parse a queryTags(SalesTransactionItem) response into a map of line-item Id ->
     *              dataPath. Pure of any live-context dependency, so it can be unit-tested with a
     *              hand-built response map. Handles the nested vs flat response shapes, the
     *              single-object-not-list case, and the Id.valueOf guard on the dataPath's last
     *              element (non-Id last elements are skipped).
     * @param apiResponse Raw response map from queryTags
     * @return Map of line Id -> dataPath (empty when nothing parses)
     */
    @TestVisible
    private Map<Id, List<Object>> parseLineItemDataPaths(Map<String, Object> apiResponse) {
        return QLDescriptionCalculator.parseLineItemDataPaths(apiResponse);
    }

    // ============================================================
    // PRODUCT NAME QUERY
    // ============================================================

    /**
     * @description Bulk-read Product2.Name for every line in scope. SOQL is
     *              allowed inside pricing prehooks (the runtime only forbids
     *              DML) — this is a single, governor-cheap query.
     */
    @TestVisible
    private Map<Id, String> queryProductNames(Set<Id> lineIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (lineIds == null || lineIds.isEmpty()) {
            return result;
        }
        // NOTE: this SOQL is intentionally NOT wrapped in a try/catch -- the original implementation
        // lets a query failure propagate up to execute()'s outer try/catch (which downgrades to a
        // SUCCESS-with-warnings response). That behavior is preserved; do not add a local catch here.
        for (QuoteLineItem qli : [
            SELECT Id, Product2.Name FROM QuoteLineItem WHERE Id IN :lineIds
        ]) {
            if (qli.Product2 != null) {
                result.put(qli.Id, qli.Product2.Name);
            }
        }
        return result;
    }

    // ============================================================
    // CONTEXT UPDATES — replaces direct DML
    // ============================================================

    /**
     * @description Build the full list of per-line context update payloads (the Step-4 loop of
     *              execute()). Delegates to the 4-arg overload using defaultConfig() so existing
     *              callers and tests are unaffected.
     */
    @TestVisible
    private List<Map<String, Object>> buildContextUpdates(
        Map<Id, Map<String, String>> attrsByLineId,
        Map<Id, List<Object>> dataPathByLineId,
        Map<Id, String> productNameByLineId
    ) {
        return buildContextUpdates(attrsByLineId, dataPathByLineId, productNameByLineId, defaultConfig());
    }

    /**
     * @description Build the full list of per-line context update payloads using the supplied
     *              ResolvedConfig. Pure of any live-context dependency, so it can be unit-tested
     *              with hand-built parsed maps. For each configured line: skips lines absent from
     *              the dataPath map (defensive continue), builds the Description via
     *              buildDescription(name, attrs, cfg), skips lines whose description is null (no
     *              configuration attributes), and emits a context-update payload for the rest.
     * @param attrsByLineId Parsed line Id -> (attribute name -> value)
     * @param dataPathByLineId Parsed line Id -> dataPath
     * @param productNameByLineId Line Id -> Product2.Name
     * @param cfg Runtime-resolved attribute configuration
     * @return List of node-update maps (one per line that produced a non-null description)
     */
    @TestVisible
    private List<Map<String, Object>> buildContextUpdates(
        Map<Id, Map<String, String>> attrsByLineId,
        Map<Id, List<Object>> dataPathByLineId,
        Map<Id, String> productNameByLineId,
        ResolvedConfig cfg
    ) {
        return QLDescriptionCalculator.buildContextUpdates(attrsByLineId, dataPathByLineId, productNameByLineId, cfg);
    }

    /**
     * @description Build a single line's update payload for
     *              updateContextAttributes. The nodePath is the line's
     *              dataPath with the FIRST element removed (the root entity
     *              Id is dropped — same pattern as COLAUpliftPrehook
     *              .buildItemUpdate at lines 442-447).
     */
    @TestVisible
    private Map<String, Object> buildContextUpdate(List<Object> dataPath, String description) {
        return QLDescriptionCalculator.buildContextUpdate(dataPath, description);
    }

    /**
     * @description Submit a batch of context attribute updates in a single
     *              call. Direct DML is forbidden in pricing prehooks (DML
     *              limit is 0); the context API is the only writeback path.
     * @return Count of line items successfully processed (best-effort —
     *         updateContextAttributes does not return per-line success).
     */
    @TestVisible
    private Integer submitContextUpdates(
        Context.IndustriesContext ctx,
        String contextId,
        List<Map<String, Object>> itemUpdates
    ) {
        if (itemUpdates == null || itemUpdates.isEmpty()) {
            return 0;
        }
        try {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => itemUpdates
            };
            // NOTE: this live updateContextAttributes call MUST stay inside this try/catch. The
            // original behavior swallows ALL failures (both the "not in updatable state" degrade
            // path and the generic warning path) and returns 0 -- it never re-throws. That contract
            // is preserved byte-for-byte; the catch is unchanged.
            ctx.updateContextAttributes(updateInput);
            return itemUpdates.size();
        } catch (Exception e) {
            if (e.getMessage() != null && e.getMessage().containsIgnoreCase('not in updatable state')) {
                System.debug(LoggingLevel.INFO, 'Context not in updatable state — skipping description writeback');
            } else {
                System.debug(LoggingLevel.WARN, 'submitContextUpdates error: ' + e.getMessage());
            }
            return 0;
        }
    }

    // Context tag helpers (getStringFromTag / extractFieldValue) moved to
    // QLDescriptionCalculator with parseConfiguredAttributes (Wave-2 thinning).
}