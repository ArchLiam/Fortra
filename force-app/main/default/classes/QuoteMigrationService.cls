/**
 * Service class for Quote Migration Tool.
 * Provides utility methods for analyzing, previewing, and transforming
 * legacy CPQ Quote/QuoteLineItem data into Revenue Cloud format.
 *
 * @author Marc DeBrey
 * @date 2026-02-27
 */
public with sharing class QuoteMigrationService {

    // ── Inner Classes / Wrappers ──────────────────────────────────────

    public class MigrationPreview {
        @AuraEnabled public Integer quoteCount;
        @AuraEnabled public Integer qliCount;
        @AuraEnabled public List<FieldGapInfo> fieldGaps;
        @AuraEnabled public Integer qlisWithMissingDates;
    }

    public class FieldGapInfo {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer nullCount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Decimal percentPopulated;
    }

    /**
     * Wraps the result of a repricing operation for a single Quote.
     */
    public class RepricingResult {
        public Boolean isSuccess;
        public String errorMessage;
        public String executionId;

        public RepricingResult(Boolean isSuccess, String errorMessage, String executionId) {
            this.isSuccess = isSuccess;
            this.errorMessage = errorMessage;
            this.executionId = executionId;
        }
    }

    /**
     * Wraps the result of checklist creation for migration Quotes.
     */
    public class ChecklistResult {
        public Integer itemsCreated = 0;
        public Integer quotesSkipped = 0;
        public List<String> errors = new List<String>();
    }

    public class ResolvedDefaults {
        public Map<String, String> qliStringDefaults;
        public Map<String, Id> qliIdDefaults;
        public Map<String, String> quoteStringDefaults;
        public Map<String, Id> quoteIdDefaults;

        public ResolvedDefaults() {
            this.qliStringDefaults = new Map<String, String>();
            this.qliIdDefaults = new Map<String, Id>();
            this.quoteStringDefaults = new Map<String, String>();
            this.quoteIdDefaults = new Map<String, Id>();
        }
    }

    // ── Constants ─────────────────────────────────────────────────────

    private static final String BASE_QLI_FILTER =
        ' AND Quote.IsPrimary__c = true AND Quote.Opportunity.StageName = \'Closed Won\'';

    // Flow API name for the repricing Flow — used by repriceQuote().
    @TestVisible
    private static final String REPRICE_FLOW_NAME = 'Fortra_Quote_Reprice';

    // ── Public Methods ────────────────────────────────────────────────

    /**
     * Returns record counts and high-level stats for the migration scope.
     * @param filterClause LIKE pattern for Legacy_Id__c (e.g. 'DY_%')
     * @return MigrationPreview with counts and gap analysis
     */
    public static MigrationPreview getRecordCounts(String filterClause) {
        MigrationPreview preview = new MigrationPreview();

        preview.qliCount = [
            SELECT COUNT()
            FROM QuoteLineItem
            WHERE Legacy_Id__c LIKE :filterClause
            AND Quote.IsPrimary__c = true
            AND Quote.Opportunity.StageName = 'Closed Won'
        ];

        preview.quoteCount = [
            SELECT COUNT()
            FROM Quote
            WHERE Id IN (
                SELECT QuoteId
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
            )
            AND IsPrimary__c = true
            AND Opportunity.StageName = 'Closed Won'
        ];

        preview.qlisWithMissingDates = [
            SELECT COUNT()
            FROM QuoteLineItem
            WHERE Legacy_Id__c LIKE :filterClause
            AND Quote.IsPrimary__c = true
            AND Quote.Opportunity.StageName = 'Closed Won'
            AND (StartDate = NULL OR EndDate = NULL)
        ];

        preview.fieldGaps = getFieldGapAnalysis(filterClause);

        return preview;
    }

    /**
     * Analyses field population rates for key migration fields.
     * Uses aggregate COUNT(field) to efficiently determine null counts
     * in a single query per object.
     *
     * @param filterClause LIKE pattern for Legacy_Id__c
     * @return List of FieldGapInfo records
     */
    public static List<FieldGapInfo> getFieldGapAnalysis(String filterClause) {
        List<FieldGapInfo> gaps = new List<FieldGapInfo>();

        // ── QuoteLineItem field analysis (single aggregate query) ──
        List<AggregateResult> qliAgg = [
            SELECT
                COUNT(Id) total,
                COUNT(ServiceDate) serviceDateCount,
                COUNT(SubscriptionTerm) subTermCount,
                COUNT(PricingTermCount) pricingTermCount,
                COUNT(BillingFrequency) billingFreqCount,
                COUNT(ProrationPolicyId) prorationCount
            FROM QuoteLineItem
            WHERE Legacy_Id__c LIKE :filterClause
            AND Quote.IsPrimary__c = true
            AND Quote.Opportunity.StageName = 'Closed Won'
        ];

        if (!qliAgg.isEmpty()) {
            Integer qliTotal = (Integer) qliAgg[0].get('total');

            gaps.add(buildGapInfo('ServiceDate', 'QuoteLineItem',
                qliTotal, (Integer) qliAgg[0].get('serviceDateCount')));
            gaps.add(buildGapInfo('SubscriptionTerm', 'QuoteLineItem',
                qliTotal, (Integer) qliAgg[0].get('subTermCount')));
            gaps.add(buildGapInfo('PricingTermCount', 'QuoteLineItem',
                qliTotal, (Integer) qliAgg[0].get('pricingTermCount')));
            gaps.add(buildGapInfo('BillingFrequency', 'QuoteLineItem',
                qliTotal, (Integer) qliAgg[0].get('billingFreqCount')));
            gaps.add(buildGapInfo('ProrationPolicyId', 'QuoteLineItem',
                qliTotal, (Integer) qliAgg[0].get('prorationCount')));

            // PeriodBoundary and SubscriptionTermUnit may not be aggregatable
            // via COUNT() — query separately with null check
            Integer periodBoundaryCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND Quote.IsPrimary__c = true
                AND Quote.Opportunity.StageName = 'Closed Won'
                AND PeriodBoundary != NULL
            ];
            gaps.add(buildGapInfo('PeriodBoundary', 'QuoteLineItem',
                qliTotal, periodBoundaryCount));

            Integer periodBoundaryDayCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND Quote.IsPrimary__c = true
                AND Quote.Opportunity.StageName = 'Closed Won'
                AND PeriodBoundaryDay != NULL
            ];
            gaps.add(buildGapInfo('PeriodBoundaryDay', 'QuoteLineItem',
                qliTotal, periodBoundaryDayCount));

            Integer periodBoundaryStartMonthCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND Quote.IsPrimary__c = true
                AND Quote.Opportunity.StageName = 'Closed Won'
                AND PeriodBoundaryStartMonth != NULL
            ];
            gaps.add(buildGapInfo('PeriodBoundaryStartMonth', 'QuoteLineItem',
                qliTotal, periodBoundaryStartMonthCount));

            Integer subTermUnitCount = [
                SELECT COUNT()
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
                AND Quote.IsPrimary__c = true
                AND Quote.Opportunity.StageName = 'Closed Won'
                AND SubscriptionTermUnit != NULL
            ];
            gaps.add(buildGapInfo('SubscriptionTermUnit', 'QuoteLineItem',
                qliTotal, subTermUnitCount));
        }

        // ── Quote field analysis ──
        List<AggregateResult> quoteAgg = [
            SELECT
                COUNT(Id) total,
                COUNT(SalesTransactionTypeId) sttCount
            FROM Quote
            WHERE Id IN (
                SELECT QuoteId
                FROM QuoteLineItem
                WHERE Legacy_Id__c LIKE :filterClause
            )
            AND IsPrimary__c = true
            AND Opportunity.StageName = 'Closed Won'
        ];

        if (!quoteAgg.isEmpty()) {
            Integer quoteTotal = (Integer) quoteAgg[0].get('total');

            gaps.add(buildGapInfo('SalesTransactionTypeId', 'Quote',
                quoteTotal, (Integer) quoteAgg[0].get('sttCount')));

            // Status is a standard required picklist — count non-null separately
            Integer statusCount = [
                SELECT COUNT()
                FROM Quote
                WHERE Id IN (
                    SELECT QuoteId
                    FROM QuoteLineItem
                    WHERE Legacy_Id__c LIKE :filterClause
                )
                AND IsPrimary__c = true
                AND Opportunity.StageName = 'Closed Won'
                AND Status != NULL
            ];
            gaps.add(buildGapInfo('Status', 'Quote', quoteTotal, statusCount));
        }

        return gaps;
    }

    /**
     * Resolves default values from Migration_Field_Default__mdt custom metadata.
     * For lookup-type defaults, queries the referenced object to resolve the Id.
     * Non-updateable fields (e.g., SubscriptionTermUnit, PricingTermCount)
     * are automatically filtered out via Schema.describe to prevent DML errors.
     *
     * @return ResolvedDefaults containing both string and Id defaults
     */
    public static ResolvedDefaults resolveDefaults() {
        ResolvedDefaults defaults = new ResolvedDefaults();

        // Cache field describe maps to validate updateability.
        // Some Revenue Cloud fields (PricingTermCount, SubscriptionTermUnit)
        // are system-managed and not writable via DML.
        Map<String, Schema.SObjectField> qliFieldMap =
            Schema.SObjectType.QuoteLineItem.fields.getMap();
        Map<String, Schema.SObjectField> quoteFieldMap =
            Schema.SObjectType.Quote.fields.getMap();

        List<Migration_Field_Default__mdt> mdtRecords = [
            SELECT Target_Object__c, Target_Field__c, Default_Value__c,
                   Lookup_Object__c, Lookup_Name_Filter__c
            FROM Migration_Field_Default__mdt
            WHERE Is_Active__c = true
        ];

        for (Migration_Field_Default__mdt mdt : mdtRecords) {
            String targetObject = mdt.Target_Object__c;
            String targetField = mdt.Target_Field__c;

            // Validate field exists and is updateable before adding to defaults
            Map<String, Schema.SObjectField> fieldMap =
                (targetObject == 'Quote') ? quoteFieldMap : qliFieldMap;
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
                    if (targetObject == 'Quote') {
                        defaults.quoteIdDefaults.put(targetField, resolvedId);
                    } else {
                        defaults.qliIdDefaults.put(targetField, resolvedId);
                    }
                }
            }
            // Resolve string defaults
            else if (String.isNotBlank(mdt.Default_Value__c)) {
                if (targetObject == 'Quote') {
                    defaults.quoteStringDefaults.put(targetField, mdt.Default_Value__c);
                } else {
                    defaults.qliStringDefaults.put(targetField, mdt.Default_Value__c);
                }
            }
        }

        return defaults;
    }

    /**
     * Calculates and populates migration fields on a QuoteLineItem in-place.
     * - ServiceDate from StartDate
     * - SubscriptionTerm from months between StartDate and EndDate
     * - PeriodBoundaryDay from day-of-month of StartDate
     * - String/Id defaults from CMT for remaining null fields
     * Note: PricingTermCount is system-managed and set by Revenue Cloud's pricing engine.
     *
     * @param qli The QuoteLineItem to modify (mutated in-place)
     * @param defaults Resolved default values from CMT
     */
    public static void calculateQLIFields(QuoteLineItem qli, ResolvedDefaults defaults) {
        // ServiceDate = StartDate (if ServiceDate is null)
        if (qli.ServiceDate == null && qli.StartDate != null) {
            qli.ServiceDate = qli.StartDate;
        }

        // SubscriptionTerm = months between StartDate and EndDate (inclusive)
        // EndDate is the last day of service, so add 1 day to get the exclusive boundary
        // e.g. Jan 1 → Dec 31 = 12 months (not 11)
        if (qli.SubscriptionTerm == null && qli.StartDate != null && qli.EndDate != null) {
            Integer months = qli.StartDate.monthsBetween(qli.EndDate.addDays(1));
            if (months <= 0) {
                months = 1;
            }
            qli.SubscriptionTerm = months;
        }

        // NOTE: PricingTermCount is a system-managed field (not writeable via DML).
        // It gets populated by Revenue Cloud's pricing engine during Q2O conversion.

        // Apply CMT defaults BEFORE PeriodBoundaryDay calculation.
        // PeriodBoundary must be set first because it determines which companion
        // fields are valid: "Anniversary" only allows PeriodBoundaryDay,
        // while "Day of Period" requires both PeriodBoundaryDay + PeriodBoundaryStartMonth.
        if (defaults != null && defaults.qliStringDefaults != null) {
            for (String fieldName : defaults.qliStringDefaults.keySet()) {
                if (qli.get(fieldName) == null) {
                    qli.put(fieldName, defaults.qliStringDefaults.get(fieldName));
                }
            }
        }

        // Apply Id defaults for null QLI fields
        if (defaults != null && defaults.qliIdDefaults != null) {
            for (String fieldName : defaults.qliIdDefaults.keySet()) {
                if (qli.get(fieldName) == null) {
                    qli.put(fieldName, defaults.qliIdDefaults.get(fieldName));
                }
            }
        }

        // PeriodBoundaryDay + PeriodBoundaryStartMonth are only valid when
        // PeriodBoundary = "DayOfPeriod". With "Anniversary", the platform uses
        // ServiceDate as the billing anchor — PeriodBoundaryDay is NOT allowed.
        // Setting PeriodBoundaryDay without PeriodBoundaryStartMonth causes
        // REQUIRED_FIELD_MISSING; setting PeriodBoundaryStartMonth with Anniversary
        // causes FIELD_INTEGRITY_EXCEPTION.
        String periodBoundary = (String) qli.get('PeriodBoundary');
        if (periodBoundary == 'DayOfPeriod'
            && qli.PeriodBoundaryDay == null && qli.StartDate != null) {
            qli.PeriodBoundaryDay = qli.StartDate.day();
            qli.PeriodBoundaryStartMonth = String.valueOf(qli.StartDate.month());
        }
    }

    /**
     * Applies default values to Quote-level fields.
     *
     * @param q The Quote to modify (mutated in-place)
     * @param defaults Resolved default values from CMT
     */
    public static void calculateQuoteFields(Quote q, ResolvedDefaults defaults) {
        if (defaults == null) {
            return;
        }

        // Apply Id defaults for null Quote fields
        if (defaults.quoteIdDefaults != null) {
            for (String fieldName : defaults.quoteIdDefaults.keySet()) {
                if (q.get(fieldName) == null) {
                    q.put(fieldName, defaults.quoteIdDefaults.get(fieldName));
                }
            }
        }

        // Apply string defaults for null Quote fields
        if (defaults.quoteStringDefaults != null) {
            for (String fieldName : defaults.quoteStringDefaults.keySet()) {
                if (q.get(fieldName) == null) {
                    q.put(fieldName, defaults.quoteStringDefaults.get(fieldName));
                }
            }
        }
    }

    /**
     * Captures the current writable price fields from a QuoteLineItem
     * so they can be restored after migration transformations.
     * Only UnitPrice and Discount are writable on QLI;
     * ListPrice, Subtotal, TotalPrice are formula/read-only.
     *
     * @param qli The QuoteLineItem to snapshot
     * @return Map of field name to current value
     */
    public static Map<String, Object> capturePriceFields(QuoteLineItem qli) {
        return new Map<String, Object>{
            'UnitPrice' => qli.UnitPrice,
            'Discount' => qli.Discount
        };
    }

    /**
     * Restores previously captured price fields onto a QuoteLineItem.
     *
     * @param qli The QuoteLineItem to restore values on
     * @param prices Map returned from capturePriceFields
     */
    public static void restorePriceFields(QuoteLineItem qli, Map<String, Object> prices) {
        if (prices == null) {
            return;
        }
        qli.UnitPrice = (Decimal) prices.get('UnitPrice');
        qli.Discount = (Decimal) prices.get('Discount');
    }

    /**
     * Invokes the "Run Salesforce Pricing" standard invocable action to
     * reprice a Quote. This is the programmatic equivalent of clicking
     * "Reprice All" in the Transaction Line Editor.
     *
     * Uses Invocable.Action (GA since Winter '23) to call the action
     * within the same Apex transaction — no HTTP callouts required.
     *
     * @param quoteId The Quote to reprice
     * @return RepricingResult with success status and execution details
     */
    public static RepricingResult repriceQuote(Id quoteId) {
        try {
            // Invoke the Fortra_Quote_Reprice autolaunched Flow which orchestrates:
            //   1. buildContext — creates a context instance from the Quote
            //   2. runSalesforcePricing — runs the pricing procedure
            //   3. persistContextData — writes results back to Quote/QLI records
            // buildContext is only available in Flows (not Apex Invocable.Action),
            // which is why we use Flow.Interview here.
            Map<String, Object> inputs = new Map<String, Object>();
            inputs.put('QuoteId', String.valueOf(quoteId));

            Flow.Interview flow = Flow.Interview.createInterview(REPRICE_FLOW_NAME, inputs);
            flow.start();

            Boolean isSuccess = (Boolean) flow.getVariableValue('IsSuccess');
            String errorMsg = (String) flow.getVariableValue('ErrorMessage');

            if (isSuccess == true) {
                PartnerNetPricePosthook.stampAttributeListPricesForQuote(quoteId);
                return new RepricingResult(true, null, null);
            } else {
                return new RepricingResult(false,
                    String.isNotBlank(errorMsg) ? errorMsg : 'Repricing flow completed without success',
                    null);
            }
        } catch (Exception e) {
            return new RepricingResult(false, e.getMessage(), null);
        }
    }

    /**
     * Creates pre-checked Operations Checklist items for migration Quotes.
     * Items are created with Is_Checked__c=true so Q2O validation passes.
     * Idempotent: skips Quotes that already have checklist items.
     *
     * @param quoteIds Set of Quote IDs to create checklist items for
     * @return ChecklistResult with counts and any errors
     */
    public static ChecklistResult createPreCheckedChecklistItems(Set<Id> quoteIds) {
        ChecklistResult result = new ChecklistResult();

        if (quoteIds == null || quoteIds.isEmpty()) {
            return result;
        }

        // 1. Query active checklist config items
        List<Operations_Checklist_Config__mdt> configItems = [
            SELECT Item_Label__c, Sort_Order__c
            FROM Operations_Checklist_Config__mdt
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c ASC
        ];

        if (configItems.isEmpty()) {
            result.errors.add('No active Operations_Checklist_Config__mdt records found');
            return result;
        }

        // 2. Check which Quotes already have checklist items (idempotency)
        Map<Id, Integer> existingCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Quote__c, COUNT(Id) cnt
            FROM Quote_Checklist_Item__c
            WHERE Quote__c IN :quoteIds
            GROUP BY Quote__c
        ]) {
            existingCounts.put((Id) ar.get('Quote__c'), (Integer) ar.get('cnt'));
        }

        // 3. Build checklist items for Quotes without existing items
        List<Quote_Checklist_Item__c> itemsToInsert = new List<Quote_Checklist_Item__c>();
        Id currentUserId = UserInfo.getUserId();
        Datetime now = System.now();

        for (Id quoteId : quoteIds) {
            if (existingCounts.containsKey(quoteId)) {
                result.quotesSkipped++;
                continue;
            }

            for (Operations_Checklist_Config__mdt cfg : configItems) {
                itemsToInsert.add(new Quote_Checklist_Item__c(
                    Quote__c = quoteId,
                    Item_Name__c = cfg.Item_Label__c,
                    Sort_Order__c = cfg.Sort_Order__c,
                    Is_Checked__c = true,
                    Checked_By__c = currentUserId,
                    Checked_Date__c = now
                ));
            }
        }

        // 4. Bulk insert with partial success
        if (!itemsToInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(itemsToInsert, false);
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    result.itemsCreated++;
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        result.errors.add('Checklist item: ' + err.getMessage());
                    }
                }
            }
        }

        return result;
    }

    // ── Private Helpers ───────────────────────────────────────────────

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
}