/**
 * Service class for Order Migration Tool.
 * Provides utility methods for analyzing, previewing, and transforming
 * legacy CPQ Quote/QuoteLineItem data into Revenue Cloud Orders/OrderItems.
 * Handles Contract/RLC prerequisites and explicit asset creation via REST API.
 *
 * @author Marc DeBrey
 * @date 2026-03-06
 */
public with sharing class OrderMigrationService {

    // ── Inner Classes / Wrappers ──────────────────────────────────────

    public class OrderMigrationPreview {
        @AuraEnabled public Integer quoteCount;
        @AuraEnabled public Integer orderItemCount;
        @AuraEnabled public Integer itemsMissingDates;
        @AuraEnabled public List<FieldGapInfo> fieldGaps;
    }

    public class FieldGapInfo {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer nullCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Decimal percentPopulated;
    }

    public class ResolvedDefaults {
        public Map<String, String> orderStringDefaults;
        public Map<String, Id> orderIdDefaults;
        public Map<String, String> oiStringDefaults;
        public Map<String, Id> oiIdDefaults;
        public Map<String, String> quoteStringDefaults;
        public Map<String, Id> quoteIdDefaults;

        public ResolvedDefaults() {
            this.orderStringDefaults = new Map<String, String>();
            this.orderIdDefaults = new Map<String, Id>();
            this.oiStringDefaults = new Map<String, String>();
            this.oiIdDefaults = new Map<String, Id>();
            this.quoteStringDefaults = new Map<String, String>();
            this.quoteIdDefaults = new Map<String, Id>();
        }
    }

    public class AssetCreationResult {
        public Boolean isSuccess;
        public String errorMessage;
        public String responseBody;

        public AssetCreationResult(Boolean isSuccess, String errorMessage, String responseBody) {
            this.isSuccess = isSuccess;
            this.errorMessage = errorMessage;
            this.responseBody = responseBody;
        }
    }

    public class ContractResult {
        public Id contractId;
        public Boolean wasCreated;
        public String errorMessage;
        // True when an existing Contract was found by Legacy_Id__c but its
        // AccountId disagreed with the requested accountId. Lets the caller
        // route to a dedicated 'ContractAccountMismatch' category instead of
        // letting the platform throw a cryptic FIELD_INTEGRITY_EXCEPTION at
        // Order-insert time.
        public Boolean accountMismatch;

        public ContractResult(Id contractId, Boolean wasCreated, String errorMessage) {
            this.contractId = contractId;
            this.wasCreated = wasCreated;
            this.errorMessage = errorMessage;
            this.accountMismatch = false;
        }
    }

    // ── Constants ─────────────────────────────────────────────────────

    private static final String BASE_QLI_FILTER =
        ' AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = \'Closed Won\') OR Quote.LegacyRenewalQuote__c = true)';

    // Whole-word "FROM QUOTE" match. Negative lookahead rejects FROM QUOTELINEITEM,
    // QUOTEDOCUMENT, QUOTESHARE, etc. so the safety guards (which use Quote-specific
    // field paths) can't be silently injected into a query against a different object.
    private static final Pattern FROM_QUOTE_PATTERN =
        Pattern.compile('FROM\\s+QUOTE(?![A-Z0-9_])');

    // ── Public Methods ────────────────────────────────────────────────

    /**
     * Returns true if the filter is a full SOQL SELECT statement.
     * Auto-detected by checking if the trimmed input starts with 'SELECT' (case-insensitive).
     */
    public static Boolean isSoqlMode(String filterClause) {
        return filterClause != null && filterClause.trim().toUpperCase().startsWith('SELECT');
    }

    /**
     * Injects safety guard conditions into a user-provided SOQL query.
     * Always appends: ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
     * Validates that the query targets FROM Quote (case-insensitive).
     * Handles WHERE, ORDER BY, GROUP BY, and LIMIT positioning.
     *
     * @param userSoql The user-provided SOQL SELECT statement
     * @return The guarded SOQL with safety conditions injected
     */
    public static String injectSafetyGuards(String userSoql) {
        if (String.isBlank(userSoql)) {
            throw new AuraHandledException('SOQL query is required');
        }

        String trimmed = userSoql.trim();
        if (trimmed.endsWith(';')) {
            trimmed = trimmed.substring(0, trimmed.length() - 1).trim();
        }

        // Normalize <> to != (Database.query() doesn't support <> operator)
        trimmed = trimmed.replace('<>', '!=');

        // Normalize all Unicode whitespace (NBSP, newlines, tabs, etc.) to regular spaces,
        // then collapse runs of multiple spaces. Textarea/browser input may contain
        // non-breaking spaces (U+00A0) that \s doesn't match.
        trimmed = trimmed.replace('\u00A0', ' ');
        trimmed = trimmed.replace('\u2007', ' ');
        trimmed = trimmed.replace('\u202F', ' ');
        trimmed = trimmed.replaceAll('\\s+', ' ');

        String upper = trimmed.toUpperCase();
        if (findFromQuoteIndex(upper) == -1) {
            String msg = 'SOQL query must select FROM Quote (not QuoteLineItem or another object).';
            AuraHandledException ahe = new AuraHandledException(msg);
            ahe.setMessage(msg);
            throw ahe;
        }

        String guards = '((IsPrimary__c = true AND Opportunity.StageName = \'Closed Won\') OR LegacyRenewalQuote__c = true)';

        // Find the position of trailing clauses (ORDER BY, GROUP BY, LIMIT, etc.)
        String[] trailingKeywords = new String[]{ 'ORDER BY', 'GROUP BY', 'LIMIT', 'OFFSET', 'FOR UPDATE', 'FOR REFERENCE', 'FOR VIEW' };
        Integer insertBeforePos = trimmed.length();
        for (String kw : trailingKeywords) {
            Integer pos = upper.indexOf(' ' + kw);
            if (pos != -1 && pos < insertBeforePos) {
                insertBeforePos = pos;
            }
        }

        Integer wherePos = upper.indexOf(' WHERE ');
        String result;
        if (wherePos != -1) {
            String beforeTrailing = trimmed.substring(0, insertBeforePos).trim();
            String afterTrailing = insertBeforePos < trimmed.length()
                ? ' ' + trimmed.substring(insertBeforePos).trim()
                : '';
            result = beforeTrailing + ' AND ' + guards + afterTrailing;
        } else {
            String beforeTrailing = trimmed.substring(0, insertBeforePos).trim();
            String afterTrailing = insertBeforePos < trimmed.length()
                ? ' ' + trimmed.substring(insertBeforePos).trim()
                : '';
            result = beforeTrailing + ' WHERE ' + guards + afterTrailing;
        }

        System.debug(LoggingLevel.INFO, 'SOQL with guards: ' + result);
        return result;
    }

    /**
     * Executes a guarded SOQL query and returns preview results.
     * Capped at 200 rows for LWC performance.
     *
     * @param filterClause The user-provided SOQL SELECT statement
     * @return List of maps, each containing field name to value pairs
     */
    public static List<Map<String, Object>> executeSoqlPreview(String filterClause) {
        String guardedSoql = injectSafetyGuards(filterClause);

        String upper = guardedSoql.toUpperCase();
        if (!upper.contains(' LIMIT ')) {
            guardedSoql += ' LIMIT 200';
        }

        List<SObject> records;
        try {
            records = Database.query(guardedSoql);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[executeSoqlPreview] SOQL: ' + guardedSoql);
            throw e;
        }
        List<Map<String, Object>> results = new List<Map<String, Object>>();

        for (SObject record : records) {
            Map<String, Object> row = new Map<String, Object>();
            Map<String, Object> populated = record.getPopulatedFieldsAsMap();
            for (String fieldName : populated.keySet()) {
                Object val = populated.get(fieldName);
                if (val instanceof SObject) {
                    continue;
                }
                row.put(fieldName, val);
            }
            results.add(row);
        }

        return results;
    }

    /**
     * Parses a QNUM: filter string into a Set of QuoteNumbers.
     * Returns null if the filter is not in QNUM: format (i.e., it's a LIKE pattern).
     */
    private static Set<String> parseQuoteNumbers(String filterClause) {
        if (filterClause == null || !filterClause.startsWith('QNUM:')) {
            return null;
        }
        Set<String> quoteNumbers = new Set<String>();
        for (String qn : filterClause.removeStart('QNUM:').split(',')) {
            String trimmed = qn.trim();
            if (String.isNotBlank(trimmed)) {
                quoteNumbers.add(trimmed);
            }
        }
        return quoteNumbers;
    }

    /**
     * Returns record counts and high-level stats for the order migration scope.
     * Queries from QuoteLineItem (source data) since OrderItems don't exist yet.
     *
     * @param filterClause LIKE pattern for Legacy_Id__c (e.g. 'DY_%') or
     *                     'QNUM:' prefix with comma-separated QuoteNumbers
     * @return OrderMigrationPreview with counts and gap analysis
     */
    public static OrderMigrationPreview getRecordCounts(String filterClause) {
        OrderMigrationPreview preview = new OrderMigrationPreview();

        // ── SOQL mode: run guarded query to collect Quote IDs, then count QLIs ──
        if (isSoqlMode(filterClause)) {
            String guardedSoql = injectSafetyGuards(filterClause);
            // Replace user's SELECT columns with SELECT Id for counting
            String upper = guardedSoql.toUpperCase();
            Integer fromPos = findFromQuoteIndex(upper);
            String countSoql = 'SELECT Id ' + guardedSoql.substring(fromPos);

            Set<Id> quoteIds = new Set<Id>();
            for (SObject rec : Database.query(countSoql)) {
                quoteIds.add(rec.Id);
            }

            preview.quoteCount = quoteIds.size();

            preview.orderItemCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c > ''
                AND QuoteId IN :quoteIds
            ];

            preview.itemsMissingDates = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c > ''
                AND QuoteId IN :quoteIds
                AND (StartDate = NULL OR EndDate = NULL)
            ];

            preview.fieldGaps = getFieldGapAnalysis(filterClause, quoteIds);
            return preview;
        }

        Set<String> quoteNumbers = parseQuoteNumbers(filterClause);

        if (quoteNumbers != null) {
            // ── QNUM mode: filter by QuoteNumber ──
            preview.orderItemCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c > ''
                AND Quote.QuoteNumber IN :quoteNumbers
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
            ];

            preview.quoteCount = [
                SELECT COUNT()
                FROM Quote
                WHERE QuoteNumber IN :quoteNumbers
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ];

            preview.itemsMissingDates = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c > ''
                AND Quote.QuoteNumber IN :quoteNumbers
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                AND (StartDate = NULL OR EndDate = NULL)
            ];
        } else {
            // ── LIKE mode: filter by Legacy_Id__c pattern ──
            preview.orderItemCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
            ];

            preview.quoteCount = [
                SELECT COUNT()
                FROM Quote
                WHERE Id IN (
                    SELECT QuoteId
                    FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                )
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ];

            preview.itemsMissingDates = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                AND (StartDate = NULL OR EndDate = NULL)
            ];
        }

        preview.fieldGaps = getFieldGapAnalysis(filterClause);

        return preview;
    }

    /**
     * Analyses field population rates for key order migration fields.
     * Queries from QuoteLineItem (source data) but labels gaps with
     * "OrderItem" objectName since that's the target object.
     *
     * @param filterClause LIKE pattern for Legacy_Id__c
     * @return List of FieldGapInfo records
     */
    public static List<FieldGapInfo> getFieldGapAnalysis(String filterClause) {
        return getFieldGapAnalysis(filterClause, null);
    }

    // Overload: SOQL-mode callers (getRecordCounts) pass the already-collected
    // quoteIds so we don't re-query the same Quote rows and double the row-limit
    // consumption. Pass null in LIKE/QNUM modes — those don't have the duplication.
    public static List<FieldGapInfo> getFieldGapAnalysis(String filterClause, Set<Id> precomputedQuoteIds) {
        List<FieldGapInfo> gaps = new List<FieldGapInfo>();

        // ── SOQL mode: collect Quote IDs from guarded query, then analyze ──
        if (isSoqlMode(filterClause)) {
            Set<Id> quoteIds;
            if (precomputedQuoteIds != null) {
                quoteIds = precomputedQuoteIds;
            } else {
                String guardedSoql = injectSafetyGuards(filterClause);
                String upper = guardedSoql.toUpperCase();
                Integer fromPos = findFromQuoteIndex(upper);
                String idSoql = 'SELECT Id ' + guardedSoql.substring(fromPos);

                quoteIds = new Set<Id>();
                for (SObject rec : Database.query(idSoql)) {
                    quoteIds.add(rec.Id);
                }
            }

            List<AggregateResult> qliAgg = [
                SELECT COUNT(Id) total, COUNT(ServiceDate) serviceDateCount,
                    COUNT(SubscriptionTerm) subTermCount, COUNT(PricingTermCount) pricingTermCount,
                    COUNT(ProrationPolicyId) prorationCount
                FROM QuoteLineItem
                WHERE Legacy_Id__c > '' AND QuoteId IN :quoteIds
            ];

            if (!qliAgg.isEmpty()) {
                Integer qliTotal = (Integer) qliAgg[0].get('total');
                gaps.add(buildGapInfo('ServiceDate', 'OrderItem', qliTotal, (Integer) qliAgg[0].get('serviceDateCount')));
                gaps.add(buildGapInfo('SubscriptionTerm', 'OrderItem', qliTotal, (Integer) qliAgg[0].get('subTermCount')));
                gaps.add(buildGapInfo('PricingTermCount', 'OrderItem', qliTotal, (Integer) qliAgg[0].get('pricingTermCount')));
                gaps.add(buildGapInfo('ProrationPolicyId', 'OrderItem', qliTotal, (Integer) qliAgg[0].get('prorationCount')));

                Integer billingFreqCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND QuoteId IN :quoteIds AND BillingFrequency != NULL];
                gaps.add(buildGapInfo('BillingFrequency2', 'OrderItem', qliTotal, billingFreqCount));

                Integer periodBoundaryCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND QuoteId IN :quoteIds AND PeriodBoundary != NULL];
                gaps.add(buildGapInfo('PeriodBoundary', 'OrderItem', qliTotal, periodBoundaryCount));

                Integer periodBoundaryDayCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND QuoteId IN :quoteIds AND PeriodBoundaryDay != NULL];
                gaps.add(buildGapInfo('PeriodBoundaryDay', 'OrderItem', qliTotal, periodBoundaryDayCount));

                Integer periodBoundaryStartMonthCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND QuoteId IN :quoteIds AND PeriodBoundaryStartMonth != NULL];
                gaps.add(buildGapInfo('PeriodBoundaryStartMonth', 'OrderItem', qliTotal, periodBoundaryStartMonthCount));
            }

            // Order-relevant field analysis
            List<AggregateResult> quoteAgg = [
                SELECT COUNT(Id) total, COUNT(SalesTransactionTypeId) sttCount
                FROM Quote WHERE Id IN :quoteIds
            ];
            if (!quoteAgg.isEmpty()) {
                Integer quoteTotal = (Integer) quoteAgg[0].get('total');
                gaps.add(buildGapInfo('SalesTransactionTypeId', 'Order', quoteTotal, (Integer) quoteAgg[0].get('sttCount')));
            }

            return gaps;
        }

        Set<String> quoteNumbers = parseQuoteNumbers(filterClause);

        // ── OrderItem-relevant field analysis (from QLI source data) ──
        List<AggregateResult> qliAgg;
        if (quoteNumbers != null) {
            qliAgg = [
                SELECT COUNT(Id) total, COUNT(ServiceDate) serviceDateCount,
                    COUNT(SubscriptionTerm) subTermCount, COUNT(PricingTermCount) pricingTermCount,
                    COUNT(ProrationPolicyId) prorationCount
                FROM QuoteLineItem
                WHERE Legacy_Id__c > '' AND Quote.QuoteNumber IN :quoteNumbers
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
            ];
        } else {
            qliAgg = [
                SELECT COUNT(Id) total, COUNT(ServiceDate) serviceDateCount,
                    COUNT(SubscriptionTerm) subTermCount, COUNT(PricingTermCount) pricingTermCount,
                    COUNT(ProrationPolicyId) prorationCount
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
            ];
        }

        if (!qliAgg.isEmpty()) {
            Integer qliTotal = (Integer) qliAgg[0].get('total');

            gaps.add(buildGapInfo('ServiceDate', 'OrderItem',
                qliTotal, (Integer) qliAgg[0].get('serviceDateCount')));
            gaps.add(buildGapInfo('SubscriptionTerm', 'OrderItem',
                qliTotal, (Integer) qliAgg[0].get('subTermCount')));
            gaps.add(buildGapInfo('PricingTermCount', 'OrderItem',
                qliTotal, (Integer) qliAgg[0].get('pricingTermCount')));
            gaps.add(buildGapInfo('ProrationPolicyId', 'OrderItem',
                qliTotal, (Integer) qliAgg[0].get('prorationCount')));

            // BillingFrequency on QLI maps to BillingFrequency2 on OrderItem.
            Integer billingFreqCount;
            if (quoteNumbers != null) {
                billingFreqCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND Quote.QuoteNumber IN :quoteNumbers
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND BillingFrequency != NULL];
            } else {
                billingFreqCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND BillingFrequency != NULL];
            }
            gaps.add(buildGapInfo('BillingFrequency2', 'OrderItem',
                qliTotal, billingFreqCount));

            Integer periodBoundaryCount;
            if (quoteNumbers != null) {
                periodBoundaryCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND Quote.QuoteNumber IN :quoteNumbers
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundary != NULL];
            } else {
                periodBoundaryCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundary != NULL];
            }
            gaps.add(buildGapInfo('PeriodBoundary', 'OrderItem',
                qliTotal, periodBoundaryCount));

            Integer periodBoundaryDayCount;
            if (quoteNumbers != null) {
                periodBoundaryDayCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND Quote.QuoteNumber IN :quoteNumbers
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundaryDay != NULL];
            } else {
                periodBoundaryDayCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundaryDay != NULL];
            }
            gaps.add(buildGapInfo('PeriodBoundaryDay', 'OrderItem',
                qliTotal, periodBoundaryDayCount));

            Integer periodBoundaryStartMonthCount;
            if (quoteNumbers != null) {
                periodBoundaryStartMonthCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c > '' AND Quote.QuoteNumber IN :quoteNumbers
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundaryStartMonth != NULL];
            } else {
                periodBoundaryStartMonthCount = [SELECT COUNT() FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                    AND ((Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = 'Closed Won') OR Quote.LegacyRenewalQuote__c = true)
                    AND PeriodBoundaryStartMonth != NULL];
            }
            gaps.add(buildGapInfo('PeriodBoundaryStartMonth', 'OrderItem',
                qliTotal, periodBoundaryStartMonthCount));
        }

        // ── Order-relevant field analysis (from Quote source data) ──
        List<AggregateResult> quoteAgg;
        if (quoteNumbers != null) {
            quoteAgg = [
                SELECT COUNT(Id) total, COUNT(SalesTransactionTypeId) sttCount
                FROM Quote
                WHERE QuoteNumber IN :quoteNumbers
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ];
        } else {
            quoteAgg = [
                SELECT COUNT(Id) total, COUNT(SalesTransactionTypeId) sttCount
                FROM Quote
                WHERE Id IN (
                    SELECT QuoteId FROM QuoteLineItem WHERE Legacy_Id__c LIKE :filterClause
                )
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ];
        }

        if (!quoteAgg.isEmpty()) {
            Integer quoteTotal = (Integer) quoteAgg[0].get('total');

            gaps.add(buildGapInfo('SalesTransactionTypeId', 'Order',
                quoteTotal, (Integer) quoteAgg[0].get('sttCount')));
        }

        return gaps;
    }

    /**
     * Resolves default values from Migration_Field_Default__mdt custom metadata.
     * Filters for Target_Object__c IN ('Order', 'OrderItem').
     * For lookup-type defaults, queries the referenced object to resolve the Id.
     * Non-updateable fields are automatically filtered out via Schema.describe
     * to prevent DML errors.
     *
     * @return ResolvedDefaults containing both string and Id defaults
     */
    public static ResolvedDefaults resolveDefaults() {
        ResolvedDefaults defaults = new ResolvedDefaults();

        // Cache field describe maps to validate updateability.
        Map<String, Schema.SObjectField> orderFieldMap =
            Schema.SObjectType.Order.fields.getMap();
        Map<String, Schema.SObjectField> oiFieldMap =
            Schema.SObjectType.OrderItem.fields.getMap();
        Map<String, Schema.SObjectField> quoteFieldMap =
            Schema.SObjectType.Quote.fields.getMap();

        List<Migration_Field_Default__mdt> mdtRecords = [
            SELECT Target_Object__c, Target_Field__c, Default_Value__c,
                   Lookup_Object__c, Lookup_Name_Filter__c
            FROM Migration_Field_Default__mdt
            WHERE Is_Active__c = true
            AND Target_Object__c IN ('Order', 'OrderItem', 'Quote')
        ];

        for (Migration_Field_Default__mdt mdt : mdtRecords) {
            String targetObject = mdt.Target_Object__c;
            String targetField = mdt.Target_Field__c;

            // Validate field exists and is updateable before adding to defaults
            Map<String, Schema.SObjectField> fieldMap;
            if (targetObject == 'Order') {
                fieldMap = orderFieldMap;
            } else if (targetObject == 'Quote') {
                fieldMap = quoteFieldMap;
            } else {
                fieldMap = oiFieldMap;
            }
            Schema.SObjectField fieldToken = fieldMap.get(targetField);

            if (fieldToken == null || !fieldToken.getDescribe().isUpdateable()) {
                System.debug(LoggingLevel.WARN,
                    'Skipping non-updateable or missing field: ' +
                    targetObject + '.' + targetField);
                continue;
            }

            // Resolve lookup-based defaults
            if (String.isNotBlank(mdt.Lookup_Object__c)) {
                Id resolvedId = resolveLookupId(
                    mdt.Lookup_Object__c, mdt.Lookup_Name_Filter__c
                );
                if (resolvedId != null) {
                    if (targetObject == 'Order') {
                        defaults.orderIdDefaults.put(targetField, resolvedId);
                    } else if (targetObject == 'Quote') {
                        defaults.quoteIdDefaults.put(targetField, resolvedId);
                    } else {
                        defaults.oiIdDefaults.put(targetField, resolvedId);
                    }
                }
            }
            // Resolve string defaults
            else if (String.isNotBlank(mdt.Default_Value__c)) {
                if (targetObject == 'Order') {
                    defaults.orderStringDefaults.put(targetField, mdt.Default_Value__c);
                } else if (targetObject == 'Quote') {
                    defaults.quoteStringDefaults.put(targetField, mdt.Default_Value__c);
                } else {
                    defaults.oiStringDefaults.put(targetField, mdt.Default_Value__c);
                }
            }
        }

        return defaults;
    }

    /**
     * Calculates and populates migration fields on an OrderItem in-place.
     * - ServiceDate from StartDate
     * - SubscriptionTerm from months between StartDate and EndDate
     * - PeriodBoundaryDay/PeriodBoundaryStartMonth from StartDate (when DayOfPeriod)
     * - String/Id defaults from CMT for remaining null fields
     *
     * Note: PricingTermCount (=1) is set programmatically in the batch,
     * NOT via this method.
     *
     * @param oi The OrderItem to modify (mutated in-place)
     * @param defaults Resolved default values from CMT
     */
    public static void calculateOrderItemFields(OrderItem oi, ResolvedDefaults defaults) {
        // SubscriptionTerm = months between ServiceDate and EndDate (inclusive)
        // EndDate is the last day of service, so add 1 day to get the exclusive boundary
        // e.g. Jan 1 → Dec 31 = 12 months (not 11)
        // Note: OrderItem uses ServiceDate (not StartDate) as the service start field.
        if (oi.SubscriptionTerm == null && oi.ServiceDate != null && oi.EndDate != null) {
            Integer months = oi.ServiceDate.monthsBetween(oi.EndDate.addDays(1));
            if (months <= 0) {
                months = 1;
            }
            oi.SubscriptionTerm = months;
        }

        // Apply CMT string defaults BEFORE PeriodBoundaryDay calculation.
        // PeriodBoundary must be set first because it determines which companion
        // fields are valid: "Anniversary" only allows PeriodBoundaryDay,
        // while "DayOfPeriod" requires both PeriodBoundaryDay + PeriodBoundaryStartMonth.
        if (defaults != null && defaults.oiStringDefaults != null) {
            for (String fieldName : defaults.oiStringDefaults.keySet()) {
                if (oi.get(fieldName) == null) {
                    oi.put(fieldName, defaults.oiStringDefaults.get(fieldName));
                }
            }
        }

        // Apply Id defaults for null OrderItem fields
        if (defaults != null && defaults.oiIdDefaults != null) {
            for (String fieldName : defaults.oiIdDefaults.keySet()) {
                if (oi.get(fieldName) == null) {
                    oi.put(fieldName, defaults.oiIdDefaults.get(fieldName));
                }
            }
        }

        // PeriodBoundaryDay + PeriodBoundaryStartMonth are only valid when
        // PeriodBoundary = "DayOfPeriod". With "Anniversary", the platform uses
        // ServiceDate as the billing anchor — PeriodBoundaryDay is NOT allowed.
        // Setting PeriodBoundaryDay without PeriodBoundaryStartMonth causes
        // REQUIRED_FIELD_MISSING; setting PeriodBoundaryStartMonth with Anniversary
        // causes FIELD_INTEGRITY_EXCEPTION.
        String periodBoundary = (String) oi.get('PeriodBoundary');
        if (periodBoundary == 'DayOfPeriod'
            && oi.PeriodBoundaryDay == null && oi.ServiceDate != null) {
            oi.PeriodBoundaryDay = oi.ServiceDate.day();
            oi.PeriodBoundaryStartMonth = String.valueOf(oi.ServiceDate.month());
        }
    }

    /**
     * Applies CMT-resolved Order-level defaults to null fields on the Order.
     * Called after the Order header fields are set from the source Quote
     * but before DML insert, so CMT defaults fill any remaining gaps.
     *
     * @param ord The Order to modify (mutated in-place)
     * @param defaults Resolved default values from CMT
     */
    public static void applyOrderDefaults(Order ord, ResolvedDefaults defaults) {
        if (defaults == null) {
            return;
        }
        // Apply string defaults for null Order fields
        if (defaults.orderStringDefaults != null) {
            for (String fieldName : defaults.orderStringDefaults.keySet()) {
                if (ord.get(fieldName) == null) {
                    ord.put(fieldName, defaults.orderStringDefaults.get(fieldName));
                }
            }
        }
        // Apply Id (lookup) defaults for null Order fields
        if (defaults.orderIdDefaults != null) {
            for (String fieldName : defaults.orderIdDefaults.keySet()) {
                if (ord.get(fieldName) == null) {
                    ord.put(fieldName, defaults.orderIdDefaults.get(fieldName));
                }
            }
        }
    }

    /**
     * Applies CMT-resolved Quote-level defaults to null fields on the source Quote.
     * Called during migration to set SalesTransactionTypeId and other fields
     * so the Quote can be repriced in Revenue Cloud after migration.
     *
     * @param q The Quote to modify (mutated in-place, caller must DML update)
     * @param defaults Resolved default values from CMT
     * @return true if any field was changed, false if no updates needed
     */
    public static Boolean applyQuoteDefaults(Quote q, ResolvedDefaults defaults) {
        if (defaults == null) {
            return false;
        }
        Boolean changed = false;
        if (defaults.quoteStringDefaults != null) {
            for (String fieldName : defaults.quoteStringDefaults.keySet()) {
                if (q.get(fieldName) == null) {
                    q.put(fieldName, defaults.quoteStringDefaults.get(fieldName));
                    changed = true;
                }
            }
        }
        if (defaults.quoteIdDefaults != null) {
            for (String fieldName : defaults.quoteIdDefaults.keySet()) {
                if (q.get(fieldName) == null) {
                    q.put(fieldName, defaults.quoteIdDefaults.get(fieldName));
                    changed = true;
                }
            }
        }
        return changed;
    }

    /**
     * Resolves or creates a Contract with RLC AppUsageAssignment for the
     * given Account. Reuses an existing migration-created Contract if one
     * has the same Legacy_Id__c (1-Quote → 1-Contract by external ID);
     * otherwise creates a new Draft Contract + AUA.
     *
     * @param accountId The Account to associate the Contract with
     * @param startDate The start date for the new Contract
     * @param additionalFields Optional map of field API names to values to set
     *        on newly created Contracts (e.g., Name, Pricebook2Id, Deal_Type__c,
     *        Legal_Entity__c, billing/shipping address fields). Ignored for
     *        reused Contracts. The Legacy_Id__c entry, if present, is also
     *        used as the lookup key for reuse. Pass null to skip.
     * @param forceNew If true, bypass the Legacy_Id__c lookup and always
     *        create a new Contract.
     * @return ContractResult with contract Id and creation status
     */
    public static ContractResult resolveOrCreateContract(
        Id accountId, Date startDate, Map<String, Object> additionalFields,
        Boolean forceNew
    ) {
        try {
            // Lookup existing migration-created Contract by Legacy_Id__c.
            // Skipped when forceNew=true or when no Legacy_Id__c was supplied.
            String legacyId = additionalFields != null && additionalFields.containsKey('Legacy_Id__c')
                ? (String) additionalFields.get('Legacy_Id__c') : null;

            if (forceNew != true && legacyId != null) {
                List<Contract> existing = [
                    SELECT Id, AccountId
                    FROM Contract
                    WHERE Legacy_Id__c = :legacyId
                    AND Migration_Created__c = true
                    LIMIT 1
                ];

                if (!existing.isEmpty()) {
                    // Reuse only when the existing Contract's AccountId matches
                    // the requested accountId. A mismatch happens when a Quote's
                    // QuoteAccountId disagrees with the Account used by the prior
                    // migration run (typically a pre-2026-04-29 Contract built
                    // off Opportunity.AccountId). Inserting an Order against a
                    // mismatched Contract would crash the platform with
                    // FIELD_INTEGRITY_EXCEPTION; route to a clear category instead.
                    if (existing[0].AccountId != accountId) {
                        ContractResult mismatch = new ContractResult(null, false,
                            'Existing migration Contract ' + existing[0].Id +
                            ' has AccountId=' + existing[0].AccountId +
                            ' but Quote.QuoteAccountId=' + accountId +
                            '. Delete the prior Contract (it has no Order) and re-run.');
                        mismatch.accountMismatch = true;
                        return mismatch;
                    }
                    return new ContractResult(existing[0].Id, false, null);
                }
            }

            // Create new Contract
            Contract c = new Contract(
                AccountId = accountId,
                ContractTerm = 12,
                StartDate = startDate,
                Status = 'Draft',
                Migration_Created__c = true
            );

            // Apply additional fields from the source Quote (only for new Contracts)
            if (additionalFields != null) {
                for (String fieldName : additionalFields.keySet()) {
                    Object val = additionalFields.get(fieldName);
                    if (val != null) {
                        c.put(fieldName, val);
                    }
                }
            }

            insert c;

            // Create AppUsageAssignment for Revenue Lifecycle Management
            AppUsageAssignment aua = new AppUsageAssignment(
                RecordId = c.Id,
                AppUsageType = 'RevenueLifecycleManagement'
            );
            insert aua;

            return new ContractResult(c.Id, true, null);
        } catch (Exception e) {
            return new ContractResult(null, false, e.getMessage());
        }
    }

    /**
     * Invokes the createOrUpdateAssetFromOrder REST API to create
     * lifecycle-managed Assets from an activated Order's OrderItems.
     *
     * Prerequisites:
     * - Order must be Activated
     * - Order must have an AppUsageAssignment with AppUsageType='RevenueLifecycleManagement'
     * - Each OrderItem becomes exactly 1 Asset
     *
     * The API is asynchronous — it returns an AsyncOperationTracker URL.
     * Asset creation completes within seconds but cannot be confirmed
     * synchronously within the same batch execution.
     *
     * @param orderId The activated Order to create Assets from
     * @return AssetCreationResult with success status and response details
     */
    public static AssetCreationResult invokeCreateAssetsFromOrder(Id orderId) {
        try {
            HttpRequest req = new HttpRequest();
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            req.setEndpoint(baseUrl +
                '/services/data/v62.0/actions/standard/createOrUpdateAssetFromOrder');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setTimeout(60000);

            // Build request body — single input with orderId
            Map<String, Object> input = new Map<String, Object>{
                'orderId' => String.valueOf(orderId)
            };
            Map<String, Object> body = new Map<String, Object>{
                'inputs' => new List<Object>{ input }
            };
            req.setBody(JSON.serialize(body));

            Http http = new Http();
            HttpResponse res = http.send(req);
            String responseBody = res.getBody();

            if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                // Check for isSuccess in response body
                if (responseBody != null && responseBody.contains('"isSuccess":true')) {
                    return new AssetCreationResult(true, null, responseBody);
                } else if (responseBody != null && responseBody.contains('"isSuccess":false')) {
                    return new AssetCreationResult(false,
                        'createOrUpdateAssetFromOrder returned isSuccess=false: ' + responseBody,
                        responseBody);
                }
                return new AssetCreationResult(true, null, responseBody);
            } else {
                return new AssetCreationResult(false,
                    'Asset creation API returned status ' + res.getStatusCode() + ': ' + responseBody,
                    responseBody);
            }
        } catch (Exception e) {
            return new AssetCreationResult(false, e.getMessage(), null);
        }
    }

    /**
     * Creates AssetContractRelationship records for Assets that belong to
     * migrated Accounts but don't yet have a relationship to their Contract.
     *
     * The createOrUpdateAssetFromOrder REST API creates Assets on the Account
     * but does NOT create the AssetContractRelationship junction record.
     * This method fills that gap by querying lifecycle-managed Assets on each
     * Account and linking them to the migration Contract.
     *
     * @param accountToContractMap Map of AccountId to ContractId
     * @return Number of AssetContractRelationship records created
     */
    public static Integer createAssetContractRelationships(Map<Id, Id> accountToContractMap) {
        if (accountToContractMap == null || accountToContractMap.isEmpty()) {
            return 0;
        }

        Set<Id> accountIds = accountToContractMap.keySet();

        // Find all lifecycle-managed Assets on these Accounts
        List<Asset> assets = [
            SELECT Id, AccountId
            FROM Asset
            WHERE AccountId IN :accountIds
            AND HasLifecycleManagement = true
        ];

        if (assets.isEmpty()) {
            return 0;
        }

        // Find existing AssetContractRelationship records to avoid duplicates
        Set<Id> contractIds = new Set<Id>(accountToContractMap.values());
        Set<String> existingKeys = new Set<String>();
        for (AssetContractRelationship acr : [
            SELECT AssetId, ContractId
            FROM AssetContractRelationship
            WHERE ContractId IN :contractIds
        ]) {
            existingKeys.add(String.valueOf(acr.AssetId) + ':' + String.valueOf(acr.ContractId));
        }

        // Create missing AssetContractRelationship records
        List<AssetContractRelationship> newAcrs = new List<AssetContractRelationship>();
        for (Asset a : assets) {
            Id contractId = accountToContractMap.get(a.AccountId);
            if (contractId == null) {
                continue;
            }
            String key = String.valueOf(a.Id) + ':' + String.valueOf(contractId);
            if (!existingKeys.contains(key)) {
                newAcrs.add(new AssetContractRelationship(
                    AssetId = a.Id,
                    ContractId = contractId
                ));
                existingKeys.add(key); // prevent duplicates within same batch
            }
        }

        if (!newAcrs.isEmpty()) {
            Database.SaveResult[] results = Database.insert(newAcrs, false);
            Integer successCount = 0;
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'AssetContractRelationship insert failed: ' + err.getMessage());
                    }
                }
            }
            return successCount;
        }

        return 0;
    }

    // ── Private Helpers ───────────────────────────────────────────────

    /**
     * Returns the 0-based index of a whole-word "FROM QUOTE" match at paren
     * depth 0 (i.e., the outer FROM clause) in the already-uppercased SOQL.
     * Returns -1 if the outer FROM is not Quote.
     *
     * Scoping to paren depth 0 matters: a semi-join subquery like
     * "... FROM Quote WHERE Id IN (SELECT QuoteId FROM QuoteLineItem ...)"
     * must be accepted, while "... FROM QuoteLineItem WHERE Id IN (SELECT Id
     * FROM Quote ...)" must be rejected — the inner "FROM Quote" is a subquery,
     * not the target of the safety guards.
     */
    private static Integer findFromQuoteIndex(String upperSoql) {
        Matcher m = FROM_QUOTE_PATTERN.matcher(upperSoql);
        while (m.find()) {
            Integer pos = m.start();
            Integer depth = 0;
            for (Integer i = 0; i < pos; i++) {
                String c = upperSoql.substring(i, i + 1);
                if (c == '(') {
                    depth++;
                } else if (c == ')') {
                    depth--;
                }
            }
            if (depth == 0) {
                return pos;
            }
        }
        return -1;
    }

    /**
     * Builds a FieldGapInfo from total and populated counts.
     */
    private static FieldGapInfo buildGapInfo(
        String fieldName, String objectName,
        Integer totalCount, Integer populatedCount
    ) {
        FieldGapInfo info = new FieldGapInfo();
        info.fieldName = fieldName;
        info.objectName = objectName;
        info.totalCount = totalCount;
        info.nullCount = totalCount - populatedCount;
        info.percentPopulated = totalCount > 0
            ? ((Decimal) populatedCount / totalCount * 100).setScale(1)
            : 0;
        return info;
    }

    /**
     * Resolves a lookup Id by querying the specified object by Name.
     * Supports SalesTransactionType and ProrationPolicy.
     */
    private static Id resolveLookupId(String lookupObject, String lookupNameFilter) {
        if (String.isBlank(lookupNameFilter)) {
            return null;
        }

        if (lookupObject == 'SalesTransactionType') {
            List<SalesTransactionType> stts = [
                SELECT Id FROM SalesTransactionType
                WHERE Name = :lookupNameFilter
                LIMIT 1
            ];
            return stts.isEmpty() ? null : stts[0].Id;
        }
        else if (lookupObject == 'ProrationPolicy') {
            List<ProrationPolicy> pps = [
                SELECT Id FROM ProrationPolicy
                WHERE Name = :lookupNameFilter
                LIMIT 1
            ];
            return pps.isEmpty() ? null : pps[0].Id;
        }

        return null;
    }

    // ══════════════════════════════════════════════════════════════════
    // ── PRICEBOOK OVERRIDE + PRESET HELPERS ───────────────────────────
    // ══════════════════════════════════════════════════════════════════

    public class CoverageAnalysis {
        @AuraEnabled public Integer totalQuotes;
        @AuraEnabled public Integer coveredQuotes;
        @AuraEnabled public Integer skippedQuotes;
        @AuraEnabled public List<ProductCoverageRow> rows;
        @AuraEnabled public Id targetPricebookId;
        @AuraEnabled public String targetPricebookName;
    }

    public class ProductCoverageRow {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Integer quotesTouching;
        @AuraEnabled public Boolean hasEntryInTarget;
    }

    public class AutoCreateResult {
        @AuraEnabled public Integer created;
        @AuraEnabled public List<Id> createdPbeIds;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<Id> productsMissingStandardPbe;

        public AutoCreateResult() {
            this.created = 0;
            this.createdPbeIds = new List<Id>();
            this.errors = new List<String>();
            this.productsMissingStandardPbe = new List<Id>();
        }
    }

    public class PbeAutoCreateRequest {
        public Id productId;
        public String currencyIsoCode;
        public Decimal seedPrice;

        public PbeAutoCreateRequest(Id productId, String currencyIsoCode, Decimal seedPrice) {
            this.productId = productId;
            this.currencyIsoCode = currencyIsoCode;
            this.seedPrice = seedPrice;
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // ── RUN DETAIL CATEGORY CATALOG ───────────────────────────────────
    // ══════════════════════════════════════════════════════════════════

    public class CategoryMetadata {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String meaning;
        @AuraEnabled public Boolean cleanupRequired;

        public CategoryMetadata(String apiName, String label, String meaning, Boolean cleanupRequired) {
            this.apiName = apiName;
            this.label = label;
            this.meaning = meaning;
            this.cleanupRequired = cleanupRequired;
        }
    }

    private static Map<String, CategoryMetadata> CATEGORY_CATALOG;

    public static Map<String, CategoryMetadata> getCategoryCatalog() {
        if (CATEGORY_CATALOG != null) return CATEGORY_CATALOG;
        CATEGORY_CATALOG = new Map<String, CategoryMetadata>();
        addCategory('NoMatchingQlis', 'No matching Quote Lines',
            'Quote was in scope but had no Quote Line Items with a populated Legacy Id.', false);
        addCategory('MissingPbeCoverage', 'Missing PricebookEntry coverage',
            'One or more products on the Quote do not have a PricebookEntry in the target pricebook. Add coverage (or enable Auto-create PBEs) and re-run.', false);
        addCategory('QuoteDefaultUpdateFailed', 'Quote default update failed',
            'Could not apply the org’s CMT defaults to the source Quote (e.g., SalesTransactionTypeId).', false);
        addCategory('NoAccountId', 'Quote has no QuoteAccountId',
            'The Quote is missing QuoteAccountId. Set the Account on the Quote, then re-run.', false);
        addCategory('DuplicateSkipped', 'Duplicate Order skipped',
            'A migration-created Order already exists for this Quote (created in the last hour). The Quote was skipped to avoid creating a second Order. Linked Order is the existing one.', false);
        addCategory('ContractResolutionFailed', 'Contract resolution failed',
            'Could not resolve or create the Contract for this Quote. Reason text shows the platform error.', false);
        addCategory('ContractAccountMismatch', 'Contract Account mismatch',
            'A prior migration Contract for this Quote exists but its AccountId disagrees with Quote.QuoteAccountId. Delete the prior Contract (it has no Order) and re-run.', true);
        addCategory('QliMissingDates', 'Quote Line missing dates',
            'Subscription Quote Line is missing StartDate or EndDate. Other lines on the same Quote may still have succeeded.', false);
        addCategory('OrderItemDmlFailed', 'OrderItem insert failed',
            'One or more OrderItems failed platform validation. The parent Order may be in Draft.', true);
        addCategory('OiaInsertFailed', 'Attribute copy failed (OIA)',
            'An attribute on a successful OrderItem could not be copied — most often because the source picklist value has been deactivated.', true);
        addCategory('AttributeCopyFailed', 'Attribute copy failed (catch-all)',
            'Bulk failure during the QuoteLineItemAttribute → OrderItemAttribute copy step.', true);
        addCategory('ContractActivationFailed', 'Contract activation failed',
            'Could not activate the migration-created Contract. The Contract is in Draft.', true);
        addCategory('OrderActivationFailed', 'Order activation failed',
            'Could not activate the Order. Most common downstream cause: zero successful OrderItems.', true);
        addCategory('AuaInsertionFailed', 'AUA insertion failed',
            'Could not add the AppUsageAssignment that triggers Asset auto-creation. Order is activated but no Assets.', true);
        addCategory('AutoCreatePbeError', 'Auto-create PBE error',
            'A PricebookEntry could not be auto-created in the target pricebook.', false);
        addCategory('Unhandled', 'Unhandled exception',
            'An unexpected exception escaped the per-Quote try/catch. Investigate the Reason text.', true);
        return CATEGORY_CATALOG;
    }

    private static void addCategory(String apiName, String label, String meaning, Boolean cleanupRequired) {
        CATEGORY_CATALOG.put(apiName, new CategoryMetadata(apiName, label, meaning, cleanupRequired));
    }

    public static Boolean isCleanupRequiredForCategory(String apiName) {
        CategoryMetadata m = getCategoryCatalog().get(apiName);
        return m != null && m.cleanupRequired == true;
    }

    /**
     * Returns all Pricebook2 records, no IsActive/IsStandard filter.
     * Used by the LWC to populate the target-pricebook combobox.
     */
    public static List<Pricebook2> getAvailablePricebooks() {
        return [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            ORDER BY Name ASC
        ];
    }

    /**
     * Builds a product-to-PBE map for the given scope against a target pricebook.
     * One SOQL. Absence of a productId from the returned map means no coverage.
     */
    public static Map<Id, PricebookEntry> buildPbeRemapForScope(
        Set<Id> productIds, Id targetPricebookId, String currencyIsoCode
    ) {
        Map<Id, PricebookEntry> remap = new Map<Id, PricebookEntry>();
        if (productIds == null || productIds.isEmpty() || targetPricebookId == null
            || String.isBlank(currencyIsoCode)) {
            return remap;
        }
        // Filter by currency: OrderItem inherits PBE.CurrencyIsoCode and must
        // match parent Order. Multi-currency target pricebooks otherwise return
        // the wrong-currency PBE and platform rejects on insert.
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, UnitPrice, CurrencyIsoCode, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :targetPricebookId
            AND Product2Id IN :productIds
            AND CurrencyIsoCode = :currencyIsoCode
            AND IsActive = true
        ]) {
            remap.put(pbe.Product2Id, pbe);
        }
        return remap;
    }

    /**
     * Resolves the set of in-scope Quote Ids from any supported filter form
     * (SOQL / QNUM / LIKE). Shared helper extracted to support coverage analysis.
     */
    public static Set<Id> resolveQuoteIdsFromFilter(String filterClause) {
        Set<Id> quoteIds = new Set<Id>();

        if (isSoqlMode(filterClause)) {
            String guardedSoql = injectSafetyGuards(filterClause);
            String upper = guardedSoql.toUpperCase();
            Integer fromPos = findFromQuoteIndex(upper);
            String idSoql = 'SELECT Id ' + guardedSoql.substring(fromPos);
            for (SObject rec : Database.query(idSoql)) {
                quoteIds.add(rec.Id);
            }
            return quoteIds;
        }

        Set<String> quoteNumbers = parseQuoteNumbers(filterClause);
        if (quoteNumbers != null) {
            for (Quote q : [
                SELECT Id FROM Quote
                WHERE QuoteNumber IN :quoteNumbers
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ]) {
                quoteIds.add(q.Id);
            }
        } else {
            for (Quote q : [
                SELECT Id FROM Quote
                WHERE Id IN (
                    SELECT QuoteId FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                )
                AND ((IsPrimary__c = true AND Opportunity.StageName = 'Closed Won') OR LegacyRenewalQuote__c = true)
            ]) {
                quoteIds.add(q.Id);
            }
        }
        return quoteIds;
    }

    /**
     * Analyses PBE coverage for the selected scope against a target pricebook.
     * Returns per-product coverage + totals (total / covered / skipped Quotes).
     */
    public static CoverageAnalysis analyzeCoverage(
        String filterClause, Id targetPricebookId
    ) {
        CoverageAnalysis analysis = new CoverageAnalysis();
        analysis.rows = new List<ProductCoverageRow>();
        analysis.targetPricebookId = targetPricebookId;
        analysis.totalQuotes = 0;
        analysis.coveredQuotes = 0;
        analysis.skippedQuotes = 0;

        if (targetPricebookId == null) {
            return analysis;
        }

        List<Pricebook2> pbs = [
            SELECT Name FROM Pricebook2 WHERE Id = :targetPricebookId LIMIT 1
        ];
        if (!pbs.isEmpty()) {
            analysis.targetPricebookName = pbs[0].Name;
        }

        Set<Id> quoteIds = resolveQuoteIdsFromFilter(filterClause);
        analysis.totalQuotes = quoteIds.size();
        if (quoteIds.isEmpty()) {
            return analysis;
        }

        Map<Id, Set<Id>> productToQuoteIds = new Map<Id, Set<Id>>();
        Map<Id, Product2> productMap = new Map<Id, Product2>();
        for (QuoteLineItem qli : [
            SELECT QuoteId, Product2Id, Product2.Name, Product2.ProductCode
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
            AND Legacy_Id__c > ''
        ]) {
            if (qli.Product2Id == null) continue;
            if (!productToQuoteIds.containsKey(qli.Product2Id)) {
                productToQuoteIds.put(qli.Product2Id, new Set<Id>());
            }
            productToQuoteIds.get(qli.Product2Id).add(qli.QuoteId);
            if (!productMap.containsKey(qli.Product2Id) && qli.Product2 != null) {
                productMap.put(qli.Product2Id, qli.Product2);
            }
        }

        Set<Id> coveredProductIds = new Set<Id>();
        if (!productToQuoteIds.isEmpty()) {
            for (PricebookEntry pbe : [
                SELECT Product2Id
                FROM PricebookEntry
                WHERE Pricebook2Id = :targetPricebookId
                AND Product2Id IN :productToQuoteIds.keySet()
                AND IsActive = true
            ]) {
                coveredProductIds.add(pbe.Product2Id);
            }
        }

        Set<Id> uncoveredQuoteIds = new Set<Id>();
        for (Id pid : productToQuoteIds.keySet()) {
            ProductCoverageRow row = new ProductCoverageRow();
            row.productId = pid;
            Product2 p = productMap.get(pid);
            row.productName = (p != null && p.Name != null) ? p.Name : 'Unknown';
            row.productCode = (p != null) ? p.ProductCode : null;
            row.quotesTouching = productToQuoteIds.get(pid).size();
            row.hasEntryInTarget = coveredProductIds.contains(pid);
            analysis.rows.add(row);
            if (!row.hasEntryInTarget) {
                uncoveredQuoteIds.addAll(productToQuoteIds.get(pid));
            }
        }

        analysis.skippedQuotes = uncoveredQuoteIds.size();
        analysis.coveredQuotes = analysis.totalQuotes - analysis.skippedQuotes;
        return analysis;
    }

    /**
     * Auto-creates PricebookEntry records in targetPricebookId for any productIds
     * that don't already have coverage. Seeds new PBEs at seedPrices[productId].
     *
     * Platform prerequisite: each product must already have a Standard PricebookEntry.
     * Products missing a Standard PBE are surfaced via productsMissingStandardPbe
     * rather than causing a DML error.
     *
     * Uses allOrNone=false so one bad product doesn't sink the batch.
     */
    public static AutoCreateResult autoCreateMissingPbes(
        List<PbeAutoCreateRequest> requests, Id targetPricebookId
    ) {
        AutoCreateResult result = new AutoCreateResult();
        if (requests == null || requests.isEmpty() || targetPricebookId == null) {
            return result;
        }

        Boolean isMultiCurrency =
            Schema.getGlobalDescribe().containsKey('CurrencyType');

        // Dedupe requests by (product, currency). In single-currency orgs the
        // currency component is irrelevant, so we collapse on product alone.
        Map<String, PbeAutoCreateRequest> deduped =
            new Map<String, PbeAutoCreateRequest>();
        Set<Id> scopeProductIds = new Set<Id>();
        for (PbeAutoCreateRequest r : requests) {
            if (r == null || r.productId == null) continue;
            String key = isMultiCurrency
                ? r.productId + '|' + r.currencyIsoCode
                : String.valueOf(r.productId);
            if (!deduped.containsKey(key)) {
                deduped.put(key, r);
                scopeProductIds.add(r.productId);
            }
        }
        if (deduped.isEmpty()) return result;

        // Existing target-pricebook coverage by composite key
        Set<String> existingKeys = new Set<String>();
        if (isMultiCurrency) {
            for (PricebookEntry pbe : [
                SELECT Product2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Pricebook2Id = :targetPricebookId
                AND Product2Id IN :scopeProductIds
            ]) {
                existingKeys.add(
                    pbe.Product2Id + '|' + (String) pbe.get('CurrencyIsoCode'));
            }
        } else {
            for (PricebookEntry pbe : [
                SELECT Product2Id
                FROM PricebookEntry
                WHERE Pricebook2Id = :targetPricebookId
                AND Product2Id IN :scopeProductIds
            ]) {
                existingKeys.add(String.valueOf(pbe.Product2Id));
            }
        }

        Map<String, PbeAutoCreateRequest> neededMap =
            new Map<String, PbeAutoCreateRequest>();
        Set<Id> neededProductIds = new Set<Id>();
        for (String k : deduped.keySet()) {
            if (!existingKeys.contains(k)) {
                neededMap.put(k, deduped.get(k));
                neededProductIds.add(deduped.get(k).productId);
            }
        }
        if (neededMap.isEmpty()) return result;

        Id stdPbId;
        if (Test.isRunningTest()) {
            stdPbId = Test.getStandardPricebookId();
        } else {
            List<Pricebook2> stdList = [
                SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1
            ];
            if (stdList.isEmpty()) {
                result.errors.add('No Standard Pricebook found in org.');
                return result;
            }
            stdPbId = stdList[0].Id;
        }

        // Standard PBE coverage check is per (product, currency) in
        // multi-currency orgs — the platform requires a same-currency Standard
        // PBE before allowing a Custom PBE in that currency.
        Set<String> standardCoverageKeys = new Set<String>();
        if (isMultiCurrency) {
            for (PricebookEntry stdPbe : [
                SELECT Product2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Pricebook2Id = :stdPbId
                AND Product2Id IN :neededProductIds
                AND IsActive = true
            ]) {
                standardCoverageKeys.add(
                    stdPbe.Product2Id + '|' + (String) stdPbe.get('CurrencyIsoCode'));
            }
        } else {
            for (PricebookEntry stdPbe : [
                SELECT Product2Id
                FROM PricebookEntry
                WHERE Pricebook2Id = :stdPbId
                AND Product2Id IN :neededProductIds
                AND IsActive = true
            ]) {
                standardCoverageKeys.add(String.valueOf(stdPbe.Product2Id));
            }
        }

        List<PricebookEntry> toInsert = new List<PricebookEntry>();
        for (String key : neededMap.keySet()) {
            PbeAutoCreateRequest req = neededMap.get(key);
            if (!standardCoverageKeys.contains(key)) {
                if (!result.productsMissingStandardPbe.contains(req.productId)) {
                    result.productsMissingStandardPbe.add(req.productId);
                }
                continue;
            }
            PricebookEntry newPbe = new PricebookEntry();
            newPbe.Pricebook2Id = targetPricebookId;
            newPbe.Product2Id = req.productId;
            newPbe.UnitPrice = (req.seedPrice != null) ? req.seedPrice : 0;
            newPbe.IsActive = true;
            if (isMultiCurrency && String.isNotBlank(req.currencyIsoCode)) {
                newPbe.put('CurrencyIsoCode', req.currencyIsoCode);
            }
            toInsert.add(newPbe);
        }

        if (toInsert.isEmpty()) return result;

        Database.SaveResult[] saveResults = Database.insert(toInsert, false);
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            if (sr.isSuccess()) {
                result.createdPbeIds.add(sr.getId());
            } else {
                String productId = String.valueOf(toInsert[i].Product2Id);
                String iso = isMultiCurrency
                    ? (String) toInsert[i].get('CurrencyIsoCode') : '';
                String msg = sr.getErrors().isEmpty()
                    ? 'Unknown error'
                    : sr.getErrors()[0].getMessage();
                result.errors.add('Product ' + productId
                    + (String.isNotBlank(iso) ? ' [' + iso + ']' : '')
                    + ': ' + msg);
            }
        }
        result.created = result.createdPbeIds.size();
        return result;
    }

    // ── Saved filter presets (server-shared) ──────────────────────────

    public static List<Migration_Saved_Filter__c> listSavedFilters() {
        return [
            SELECT Id, Name, Filter_Mode__c, Filter_Value__c, Description__c,
                   Last_Used_By__c, Last_Used_By__r.Name, Last_Used_Date__c,
                   CreatedById, CreatedBy.Name, CreatedDate,
                   LastModifiedDate
            FROM Migration_Saved_Filter__c
            ORDER BY Last_Used_Date__c DESC NULLS LAST, Name ASC
            LIMIT 500
        ];
    }

    public static Migration_Saved_Filter__c saveFilter(
        Id recordId, String name, String filterMode,
        String filterValue, String description
    ) {
        Migration_Saved_Filter__c rec;
        if (recordId != null) {
            rec = [
                SELECT Id FROM Migration_Saved_Filter__c WHERE Id = :recordId LIMIT 1
            ];
            rec.Name = name;
            rec.Filter_Mode__c = filterMode;
            rec.Filter_Value__c = filterValue;
            rec.Description__c = description;
            update rec;
        } else {
            rec = new Migration_Saved_Filter__c(
                Name = name,
                Filter_Mode__c = filterMode,
                Filter_Value__c = filterValue,
                Description__c = description
            );
            insert rec;
        }
        return rec;
    }

    public static void deleteSavedFilter(Id recordId) {
        if (recordId == null) return;
        delete [SELECT Id FROM Migration_Saved_Filter__c WHERE Id = :recordId LIMIT 1];
    }

    public static void touchSavedFilter(Id recordId) {
        if (recordId == null) return;
        update new Migration_Saved_Filter__c(
            Id = recordId,
            Last_Used_By__c = UserInfo.getUserId(),
            Last_Used_Date__c = System.now()
        );
    }

    // ── Saved pricebook presets (server-shared) ───────────────────────

    public static List<Migration_Saved_Pricebook_Preset__c> listSavedPricebookPresets() {
        return [
            SELECT Id, Name, Pricebook__c, Pricebook__r.Name,
                   Auto_Create_Missing_PBEs__c, Description__c,
                   Last_Used_By__c, Last_Used_By__r.Name, Last_Used_Date__c,
                   CreatedById, CreatedBy.Name, CreatedDate,
                   LastModifiedDate
            FROM Migration_Saved_Pricebook_Preset__c
            ORDER BY Last_Used_Date__c DESC NULLS LAST, Name ASC
            LIMIT 500
        ];
    }

    public static Migration_Saved_Pricebook_Preset__c savePricebookPreset(
        Id recordId, String name, Id pricebookId,
        Boolean autoCreate, String description
    ) {
        Migration_Saved_Pricebook_Preset__c rec;
        if (recordId != null) {
            rec = [
                SELECT Id FROM Migration_Saved_Pricebook_Preset__c
                WHERE Id = :recordId LIMIT 1
            ];
            rec.Name = name;
            rec.Pricebook__c = pricebookId;
            rec.Auto_Create_Missing_PBEs__c = autoCreate == true;
            rec.Description__c = description;
            update rec;
        } else {
            rec = new Migration_Saved_Pricebook_Preset__c(
                Name = name,
                Pricebook__c = pricebookId,
                Auto_Create_Missing_PBEs__c = autoCreate == true,
                Description__c = description
            );
            insert rec;
        }
        return rec;
    }

    public static void deleteSavedPricebookPreset(Id recordId) {
        if (recordId == null) return;
        delete [
            SELECT Id FROM Migration_Saved_Pricebook_Preset__c
            WHERE Id = :recordId LIMIT 1
        ];
    }

    public static void touchSavedPricebookPreset(Id recordId) {
        if (recordId == null) return;
        update new Migration_Saved_Pricebook_Preset__c(
            Id = recordId,
            Last_Used_By__c = UserInfo.getUserId(),
            Last_Used_Date__c = System.now()
        );
    }

    /**
     * One-time migration: LWC uploads entries from browser localStorage
     * so historical per-user presets become team-shared server records.
     *
     * Entries shape: List of Maps with keys 'name', 'filterMode', 'filterValue',
     * optional 'description'. Duplicate names (case-insensitive) are skipped.
     */
    public static Integer migrateLocalStorageFilters(List<Map<String, Object>> entries) {
        if (entries == null || entries.isEmpty()) return 0;

        Set<String> existingNamesLower = new Set<String>();
        for (Migration_Saved_Filter__c existing : [
            SELECT Name FROM Migration_Saved_Filter__c LIMIT 500
        ]) {
            if (existing.Name != null) {
                existingNamesLower.add(existing.Name.toLowerCase());
            }
        }

        List<Migration_Saved_Filter__c> toInsert = new List<Migration_Saved_Filter__c>();
        for (Map<String, Object> entry : entries) {
            String name = (String) entry.get('name');
            String mode = (String) entry.get('filterMode');
            String value = (String) entry.get('filterValue');
            String descriptionText = (String) entry.get('description');
            if (String.isBlank(name) || String.isBlank(mode) || String.isBlank(value)) {
                continue;
            }
            if (existingNamesLower.contains(name.toLowerCase())) {
                continue;
            }
            existingNamesLower.add(name.toLowerCase());
            toInsert.add(new Migration_Saved_Filter__c(
                Name = name.left(80),
                Filter_Mode__c = mode,
                Filter_Value__c = value,
                Description__c = descriptionText
            ));
        }
        if (toInsert.isEmpty()) return 0;
        insert toInsert;
        return toInsert.size();
    }
}