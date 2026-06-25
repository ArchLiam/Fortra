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
 *              - Always overwrites Description on every Quote pricing run for
 *                any line that has at least one configured attribute AND
 *                produces at least one non-empty segment.
 *              - Lines with no SalesTransactionItemAttribute records are
 *                skipped entirely (existing Description preserved).
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

    private static Boolean isProcessing = false;

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

            // Step 2 — read configured attributes for each line.
            Map<Id, Map<String, String>> attrsByLineId = queryConfiguredAttributes(ctx, contextId);
            if (attrsByLineId.isEmpty()) {
                response.status = RevSignaling.TransactionStatus.SUCCESS;
                response.message = 'No SalesTransactionItemAttribute records — nothing to generate';
                return response;
            }

            // Step 3 — read each line's Product Name (prepended as the
            // leading description segment).
            Map<Id, String> productNameByLineId = queryProductNames(attrsByLineId.keySet());

            // Step 4 — build a context update payload per line that has both
            // configured attributes AND a non-null description.
            List<Map<String, Object>> contextUpdates =
                buildContextUpdates(attrsByLineId, dataPathByLineId, productNameByLineId);

            // Step 5 — submit all updates in one call.
            Integer updated = submitContextUpdates(ctx, contextId, contextUpdates);

            response.status = RevSignaling.TransactionStatus.SUCCESS;
            response.message = 'Generated descriptions for ' + updated + ' of ' + attrsByLineId.size() + ' configured lines';

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
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
        if (apiResponse == null) {
            return result;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItemAttribute')) {
            queryResult = apiResponse;
        }
        if (queryResult == null || !queryResult.containsKey('SalesTransactionItemAttribute')) {
            return result;
        }

        Object attrObj = queryResult.get('SalesTransactionItemAttribute');
        List<Object> attributeData = (attrObj instanceof List<Object>)
            ? (List<Object>) attrObj
            : new List<Object>{ attrObj };

        for (Object rawAttr : attributeData) {
            if (rawAttr == null || !(rawAttr instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> attrNode = (Map<String, Object>) rawAttr;
            Map<String, Object> tagMap;
            List<Object> dataPath;

            if (attrNode.containsKey('tagValue')) {
                Object tv = attrNode.get('tagValue');
                tagMap = (tv instanceof Map<String, Object>) ? (Map<String, Object>) tv : null;
                Object dp = attrNode.get('dataPath');
                dataPath = (dp instanceof List<Object>) ? (List<Object>) dp : null;
            } else {
                tagMap = attrNode;
                dataPath = new List<Object>();
            }
            if (tagMap == null) {
                continue;
            }

            String parentRef = getStringFromTag(tagMap, 'ParentReference');
            if (String.isBlank(parentRef) && dataPath != null && dataPath.size() >= 2) {
                parentRef = String.valueOf(dataPath[dataPath.size() - 2]);
            }
            if (String.isBlank(parentRef)) {
                continue;
            }

            Id parentId;
            try {
                parentId = Id.valueOf(parentRef);
            } catch (Exception e) {
                continue;
            }

            String attrName = getStringFromTag(tagMap, 'Attribute');
            if (String.isBlank(attrName)) {
                attrName = getStringFromTag(tagMap, 'AttributeKeyName');
            }
            String attrValue = getStringFromTag(tagMap, 'AttributeValue');

            if (String.isNotBlank(attrName) && attrValue != null) {
                if (!result.containsKey(parentId)) {
                    result.put(parentId, new Map<String, String>());
                }
                result.get(parentId).put(attrName, attrValue);
            }
        }
        return result;
    }

    // ============================================================
    // DESCRIPTION BUILDING
    // ============================================================

    /**
     * @description Build the pipe-separated Description for one line.
     *              Output shape: "<Product Name> | <Unit Type segment> |
     *              <attr 2> | ... | <attr 10>", with empty values skipped.
     * @return Joined string on success.
     *         null when the line has no configuration attributes —
     *         preserves the line's existing Description (no overwrite).
     */
    @TestVisible
    private String buildDescription(String productName, Map<String, String> attrs) {
        if (attrs == null || attrs.isEmpty()) {
            return null;
        }

        List<String> segments = new List<String>();

        if (String.isNotBlank(productName)) {
            segments.add(productName);
        }

        String unitTypeSegment = computeUnitTypeSegment(attrs);
        if (String.isNotBlank(unitTypeSegment)) {
            segments.add(unitTypeSegment);
        }

        for (String attrName : ATTRIBUTE_ORDER) {
            String val = attrs.get(attrName);
            if (String.isNotBlank(val)) {
                segments.add(val);
            }
        }

        if (segments.isEmpty()) {
            return null;
        }

        String joined = String.join(segments, SEPARATOR);
        if (joined.length() > DESCRIPTION_MAX_LENGTH) {
            Integer cutoff = DESCRIPTION_MAX_LENGTH - TRUNCATION_MARKER.length();
            if (cutoff < 0) {
                cutoff = 0;
            }
            joined = joined.substring(0, cutoff) + TRUNCATION_MARKER;
        }
        return joined;
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
        if (attrs == null) {
            return null;
        }
        String unitType = attrs.get(UNIT_TYPE_ATTR);
        if (String.isBlank(unitType)) {
            return null;
        }
        String trimmedQty = resolveUnitQuantity(attrs);
        Boolean hasQty = trimmedQty != null;

        if (unitType == UNIT_TYPE_PER_USERS) {
            // Special-case wording for "Per Users":
            //   - with quantity → "Users: <qty>"
            //   - without quantity → "Per User"
            return hasQty ? 'Users: ' + trimmedQty : 'Per User';
        }

        // Any other Unit Type value renders as itself, with an optional
        // ": <qty>" suffix when the Unit Quantity attribute is present.
        return hasQty ? unitType + ': ' + trimmedQty : unitType;
    }

    /**
     * @description Resolve the unit count for the Unit Type segment.
     *              Attribute_Volume wins when present; otherwise Number_of_Units.
     * @return Trimmed quantity string, or null when neither attribute has a value.
     */
    @TestVisible
    private String resolveUnitQuantity(Map<String, String> attrs) {
        if (attrs == null) {
            return null;
        }
        String volume = attrs.get(UNIT_QUANTITY_ATTR);
        if (String.isNotBlank(volume)) {
            return volume.trim();
        }
        String numberOfUnits = attrs.get(NUMBER_OF_UNITS_ATTR);
        if (String.isNotBlank(numberOfUnits)) {
            return numberOfUnits.trim();
        }
        return null;
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
        Map<Id, List<Object>> result = new Map<Id, List<Object>>();
        if (apiResponse == null) {
            return result;
        }

        Map<String, Object> queryResult;
        if (apiResponse.containsKey('queryResult')) {
            Object qrObj = apiResponse.get('queryResult');
            queryResult = (qrObj instanceof Map<String, Object>) ? (Map<String, Object>) qrObj : null;
        } else if (apiResponse.containsKey('SalesTransactionItem')) {
            queryResult = apiResponse;
        }
        if (queryResult == null || !queryResult.containsKey('SalesTransactionItem')) {
            return result;
        }

        Object itemsObj = queryResult.get('SalesTransactionItem');
        List<Object> rawItems = (itemsObj instanceof List<Object>)
            ? (List<Object>) itemsObj
            : new List<Object>{ itemsObj };

        for (Object rawItem : rawItems) {
            if (rawItem == null || !(rawItem instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> itemNode = (Map<String, Object>) rawItem;
            Object dpObj = itemNode.get('dataPath');
            if (!(dpObj instanceof List<Object>)) {
                continue;
            }
            List<Object> dataPath = (List<Object>) dpObj;
            if (dataPath.isEmpty()) {
                continue;
            }
            try {
                Id lineId = Id.valueOf(String.valueOf(dataPath[dataPath.size() - 1]));
                result.put(lineId, dataPath);
            } catch (Exception e) {
                // dataPath last element wasn't a valid Id — skip
            }
        }
        return result;
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
     *              execute()). Pure of any live-context dependency, so it can be unit-tested with
     *              hand-built parsed maps. For each configured line: skips lines absent from the
     *              dataPath map (defensive continue), builds the Description via buildDescription,
     *              skips lines whose description is null (no configuration attributes), and emits a
     *              context-update payload for the rest.
     * @param attrsByLineId Parsed line Id -> (attribute name -> value)
     * @param dataPathByLineId Parsed line Id -> dataPath
     * @param productNameByLineId Line Id -> Product2.Name
     * @return List of node-update maps (one per line that produced a non-null description)
     */
    @TestVisible
    private List<Map<String, Object>> buildContextUpdates(
        Map<Id, Map<String, String>> attrsByLineId,
        Map<Id, List<Object>> dataPathByLineId,
        Map<Id, String> productNameByLineId
    ) {
        List<Map<String, Object>> contextUpdates = new List<Map<String, Object>>();
        for (Id lineId : attrsByLineId.keySet()) {
            List<Object> dataPath = dataPathByLineId.get(lineId);
            if (dataPath == null) {
                // Configured attrs without a matching SalesTransactionItem
                // — defensive skip.
                continue;
            }
            String descriptionText = buildDescription(
                productNameByLineId.get(lineId),
                attrsByLineId.get(lineId)
            );
            if (descriptionText == null) {
                continue;
            }
            contextUpdates.add(buildContextUpdate(dataPath, descriptionText));
        }
        return contextUpdates;
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
        List<Object> updatePath = dataPath.clone();
        if (!updatePath.isEmpty()) {
            updatePath.remove(0);
        }
        return new Map<String, Object>{
            'nodePath' => new Map<String, Object>{ 'dataPath' => updatePath },
            'attributes' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'attributeName' => CONTEXT_DESCRIPTION_ATTR,
                    'attributeValue' => description
                }
            }
        };
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

    // ============================================================
    // CONTEXT TAG HELPERS — same shape as the COLA / Hardware prehooks
    // ============================================================

    private String getStringFromTag(Map<String, Object> tagData, String fieldName) {
        Object val = extractFieldValue(tagData, fieldName);
        return val != null ? String.valueOf(val) : null;
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
            Map<String, Object> wrapper = (Map<String, Object>) fieldObj;
            if (wrapper.containsKey('tagValue')) {
                return wrapper.get('tagValue');
            }
            return null;
        }
        return fieldObj;
    }
}