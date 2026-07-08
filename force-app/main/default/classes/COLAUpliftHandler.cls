/**
 * @description Handler class for COLA (Cost of Living Adjustment) uplift calculations
 *              on QuoteLineItem records. Applies COLA percentage based on a three-tier hierarchy:
 *              1. Line Override - Manual edit on QuoteLineItem (highest priority)
 *              2. Contract Override - Active Contract COLA override (if valid)
 *              3. CMDT Lookup - Default from COLA_Uplift_Rules__mdt by Solution Category
 * @author Claude/Fortra
 * @date December 2024
 */
public with sharing class COLAUpliftHandler {

    /**
     * @description Handles Before Insert trigger context. Applies COLA uplift to renewal quote lines.
     * @param newItems List of new QuoteLineItem records being inserted
     */
    public static void handleBeforeInsert(List<QuoteLineItem> newItems) {
        if (newItems == null || newItems.isEmpty()) {
            return;
        }

        // Collect QuoteActionIds from the new items
        Set<Id> quoteActionIds = new Set<Id>();
        for (QuoteLineItem qli : newItems) {
            if (qli.QuoteActionId != null) {
                quoteActionIds.add(qli.QuoteActionId);
            }
        }

        if (quoteActionIds.isEmpty()) {
            return;
        }

        // Query QuoteActions with Asset and Product data for renewals only
        Map<Id, QuoteAction> quoteActionMap = new Map<Id, QuoteAction>([
            SELECT Id, Type, SourceAssetId, SourceAsset.Price, SourceAsset.Product2Id,
                   SourceAsset.Product2.Solution_Category__c
            FROM QuoteAction
            WHERE Id IN :quoteActionIds
            AND Type = 'Renew'
        ]);

        if (quoteActionMap.isEmpty()) {
            return;
        }

        // Populate COLA fields for renewal quote lines
        populateCOLAFields(newItems, quoteActionMap);
    }

    /**
     * @description Handles Before Update trigger context. Recalculates price when COLA % is overridden.
     * @param newItems List of updated QuoteLineItem records
     * @param oldMap Map of old QuoteLineItem records by Id
     */
    public static void handleBeforeUpdate(List<QuoteLineItem> newItems, Map<Id, QuoteLineItem> oldMap) {
        if (newItems == null || newItems.isEmpty() || oldMap == null) {
            return;
        }

        // Load CMDT rules once (lazy) for COLA_Source sync
        Map<String, COLA_Uplift_Rules__mdt> colaRulesMap = null;

        List<QuoteLineItem> changedItems = new List<QuoteLineItem>();

        for (QuoteLineItem qli : newItems) {
            QuoteLineItem oldQli = oldMap.get(qli.Id);
            if (oldQli == null) continue;

            // Year-1 Line Override: a direct user edit to COLA_Uplift_Percent__c
            // (new non-null and changed from the prior value — INCLUDING a
            // null->value edit on a legacy/partially-hydrated line) that diverges
            // from EVERY active system value must be promoted to 'Line Override'
            // BEFORE the system-source sync below, or that sync resets it back to
            // the CMDT rate. The old value is intentionally NOT required to be
            // non-null: isManualLineOverride already rejects system values
            // (CMDT/MyCAP), so a programmatic null->CMDT population is not
            // promoted, while a genuine null->override edit is. This is the
            // single-year analogue of the outyear override detection further down
            // — a 1-year renewal has no outyear field to trip that path, so
            // without this a year-1 override can never stick.
            if (qli.COLA_Source__c != 'Line Override'
                && qli.COLA_Source__c != 'Contract Override'
                && qli.COLA_Uplift_Percent__c != null
                && qli.COLA_Uplift_Percent__c != oldQli.COLA_Uplift_Percent__c
                && qli.COLA_Solution_Category__c != null) {
                if (colaRulesMap == null) {
                    colaRulesMap = getCOLARulesMap();
                }
                COLA_Uplift_Rules__mdt y1Rule = colaRulesMap.get(qli.COLA_Solution_Category__c);
                if (y1Rule != null && y1Rule.Default_Uplift_Percent__c != null) {
                    // Use the SINGLE shared override predicate (isManualLineOverride),
                    // matching the prehook's year-1 detection. The year-1 system value
                    // is the CMDT default ONLY — MyCAP is an OUTYEAR concept
                    // (COLA_Outyear_Uplift_Percent__c), never a year-1 value (confirmed
                    // by live data: 0 of 7 real 'MyCAP Default' lines carry the MyCAP
                    // value in year-1). MyCAP is therefore passed as null here: a year-1
                    // edit equal to the MyCAP rate (e.g. 3%) is a GENUINE manual override
                    // and must stick. Contract Override is covered by the COLA_Source__c
                    // != 'Contract Override' guard above, so it is null here too.
                    if (isManualLineOverride(qli.COLA_Uplift_Percent__c, y1Rule.Default_Uplift_Percent__c, null, null)) {
                        // Is_COLA_Overridden__c is now a derived formula (pct <> Default) — no longer written.
                        qli.COLA_Source__c = 'Line Override';
                        qli.COLA_Modified_By__c = UserInfo.getUserId();
                        qli.COLA_Modified_Date__c = DateTime.now();
                    }
                }
            }

            // Sync COLA% to CMDT default when COLA_Source is a system source
            // (MyCAP Default or CMDT Lookup) and COLA% doesn't already match.
            // The prehook uses the CMDT rate for year-1 pricing but can't
            // write COLA_Uplift_Percent__c (context-only attribute), so the
            // trigger syncs it on every pricing write-back.
            // Contract Override and Line Override are excluded: their percent
            // comes from the Contract record / user edit, not CMDT.
            // NOTE: a MyCAP-source year-1 value normalizing to CMDT here is BY
            // DESIGN, not a bug — MyCAP is an OUTYEAR concept
            // (COLA_Outyear_Uplift_Percent__c). Confirmed by live data: 0 of 7
            // real 'MyCAP Default' lines on fortrauat carry the MyCAP value in
            // year-1; all carry the CMDT default. The year-1 override predicate
            // above only prevents a coincidental year-1==MyCAP value from being
            // mislabeled a manual override; this block then normalizes it to CMDT.
            if (qli.COLA_Source__c != null
                && qli.COLA_Source__c != 'Line Override'
                && qli.COLA_Source__c != 'Contract Override'
                && qli.COLA_Solution_Category__c != null) {
                if (colaRulesMap == null) {
                    colaRulesMap = getCOLARulesMap();
                }
                COLA_Uplift_Rules__mdt rule = colaRulesMap.get(qli.COLA_Solution_Category__c);
                if (rule != null && rule.Default_Uplift_Percent__c != null
                    && qli.COLA_Uplift_Percent__c != rule.Default_Uplift_Percent__c) {
                    qli.COLA_Uplift_Percent__c = rule.Default_Uplift_Percent__c;
                    qli.Default_COLA_Uplift_Percent__c = rule.Default_Uplift_Percent__c;
                    // Is_COLA_Overridden__c derived (pct now == Default -> false).
                }
            }

            // Outyear uplift defaulting — only fires for sources where the
            // prehook's multi-year detection already gated (Contract Override
            // and MyCAP Default are both multi-year-relevant). Cannot rely on
            // PricingTermUnit because it is read-only and gets stripped from
            // Trigger.new; PricingTermCount is readable and > 1 is a
            // reliable multi-term signal. Line Override skipped to respect
            // user edits; CMDT Lookup skipped because single-year has no
            // outyear.
            if ((qli.COLA_Source__c == 'Contract Override'
                    || qli.COLA_Source__c == 'MyCAP Default')
                && qli.PricingTermCount != null && qli.PricingTermCount > 1
                && qli.COLA_Outyear_Uplift_Percent__c == null) {
                MyCAP_Rules__mdt mycapRule = MyCAP_Rules__mdt.getInstance('Global');
                if (mycapRule != null && mycapRule.Is_Active__c == true) {
                    qli.COLA_Outyear_Uplift_Percent__c = mycapRule.Default_Out_Year_Uplift_Percent__c != null
                        ? mycapRule.Default_Out_Year_Uplift_Percent__c : 3;
                }
            }

            // Check if COLA percentage was changed (by user or by sync above)
            if (qli.COLA_Uplift_Percent__c != null &&
                qli.COLA_Uplift_Percent__c != oldQli.COLA_Uplift_Percent__c &&
                qli.Pre_COLA_Price__c != null) {

                changedItems.add(qli);
            }

            // Flag override when outyear percent is changed by user.
            // Requires BOTH old and new to be non-null so the programmatic
            // null-to-MyCAP-default population above is not mistaken for a
            // user edit. Actual user edits are either non-null→non-null or
            // user explicitly nulling the field (not covered here).
            if (qli.COLA_Outyear_Uplift_Percent__c != null
                && oldQli.COLA_Outyear_Uplift_Percent__c != null
                && qli.COLA_Outyear_Uplift_Percent__c != oldQli.COLA_Outyear_Uplift_Percent__c) {
                MyCAP_Rules__mdt mr = MyCAP_Rules__mdt.getInstance('Global');
                // Active-gate MyCAP exactly like the year-1 block and the prehook:
                // an inactive/missing MyCAP rule is NOT a system value (null), so a
                // user's outyear edit must read as a real override rather than be
                // mistaken for the disabled default. Reuses the one shared predicate
                // (no CMDT or Contract source applies to the outyear value, so those
                // arguments are null).
                Decimal mycapDflt = (mr != null && mr.Is_Active__c == true)
                    ? (mr.Default_Out_Year_Uplift_Percent__c != null ? mr.Default_Out_Year_Uplift_Percent__c : 3)
                    : null;
                Boolean outyearOverridden = isManualLineOverride(qli.COLA_Outyear_Uplift_Percent__c, null, mycapDflt, null);
                // Compare year-1 against CMDT lookup (not stale Default field)
                if (colaRulesMap == null) { colaRulesMap = getCOLARulesMap(); }
                Boolean year1Overridden = false;
                if (qli.COLA_Solution_Category__c != null) {
                    COLA_Uplift_Rules__mdt catRule = colaRulesMap.get(qli.COLA_Solution_Category__c);
                    if (catRule != null && catRule.Default_Uplift_Percent__c != null) {
                        year1Overridden = (qli.COLA_Uplift_Percent__c != catRule.Default_Uplift_Percent__c);
                    }
                }
                // Is_COLA_Overridden__c is derived (formula); use a local for the source/audit decision.
                Boolean overridden = outyearOverridden || year1Overridden;
                if (overridden) {
                    qli.COLA_Source__c = 'Line Override';
                    qli.COLA_Modified_By__c = UserInfo.getUserId();
                    qli.COLA_Modified_Date__c = DateTime.now();
                } else {
                    qli.COLA_Source__c = 'MyCAP Default';
                }
            }
        }

        if (!changedItems.isEmpty()) {
            recalculateCOLAPrice(changedItems);
        }
    }

    /**
     * @description The single authoritative "is this a manual Line Override?" predicate,
     *              shared by this trigger handler AND COLAUpliftPrehook so the two can
     *              never drift. A percent is a manual override only when it is non-null
     *              and differs from EVERY known system source: the CMDT default, the
     *              MyCAP default, and the Contract Override. A null system value means
     *              "no such system source" and is skipped (matches the prehook, where an
     *              inactive/missing MyCAP rule yields a null mycapDefaultPct).
     * @param pct            The line's COLA_Uplift_Percent__c (the value under test).
     * @param cmdtDefaultPct The CMDT (COLA_Uplift_Rules__mdt) default for the category.
     * @param mycapDefaultPct The active MyCAP default, or null if MyCAP is inactive/missing.
     * @param contractPct    The applicable Contract Override percent, or null if none.
     * @return true when pct represents a genuine manual edit, false when it matches a system source.
     */
    public static Boolean isManualLineOverride(Decimal pct, Decimal cmdtDefaultPct, Decimal mycapDefaultPct, Decimal contractPct) {
        // Delegates to the shared engine (D-13 — one COLA override predicate for handler + prehook).
        // Temporary wrapper so the intra-class callers (:100/:184) keep compiling; removed in cleanup.
        return COLAUpliftCalculator.isManualLineOverride(pct, cmdtDefaultPct, mycapDefaultPct, contractPct);
    }

    /**
     * @description Populates COLA fields on quote line items for renewal transactions.
     *              Uses three-tier override hierarchy: Line Override > Contract Override > CMDT Lookup.
     *              Thin wrapper that resolves the Contract-override map (which performs the
     *              AssetContractRelationship query) and delegates the per-line tier logic to the
     *              testable core below.
     * @param items List of QuoteLineItem records to process
     * @param quoteActions Map of QuoteAction records with Asset data
     */
    private static void populateCOLAFields(List<QuoteLineItem> items, Map<Id, QuoteAction> quoteActions) {
        // Collect Asset IDs to query Contract overrides
        Set<Id> assetIds = new Set<Id>();
        for (QuoteAction qa : quoteActions.values()) {
            if (qa.SourceAssetId != null) {
                assetIds.add(qa.SourceAssetId);
            }
        }

        // Get Contract overrides for Assets via AssetContractRelationship.
        // NOTE: getContractOverrides delegates to AssetContractQueryHelper.queryAssetContracts,
        // which runs the live AssetContractRelationship SOQL inside its own try/catch.
        Map<Id, ContractOverride> contractOverridesByAssetId = getContractOverrides(assetIds);

        populateCOLAFields(items, quoteActions, contractOverridesByAssetId);
    }

    /**
     * @description Testable core of populateCOLAFields: applies the three-tier override hierarchy to
     *              each renewal line given a PRE-RESOLVED Contract-override map. Extracting the map as a
     *              parameter lets tests exercise the Tier-2 (Contract Override) branch with an in-memory
     *              override map, because the underlying AssetContractRelationship cannot be inserted in a
     *              test on this org (the linked Asset needs platform-owned HasLifecycleManagement=true).
     *              No SOQL on the line loop apart from the CMDT rules lookup. Behavior is identical to the
     *              prior inline implementation.
     * @param items List of QuoteLineItem records to process
     * @param quoteActions Map of QuoteAction records with Asset data
     * @param contractOverridesByAssetId Resolved Tier-2 overrides keyed by SourceAssetId
     */
    @TestVisible
    private static void populateCOLAFields(
        List<QuoteLineItem> items,
        Map<Id, QuoteAction> quoteActions,
        Map<Id, ContractOverride> contractOverridesByAssetId
    ) {
        // Get COLA rules from Custom Metadata
        Map<String, COLA_Uplift_Rules__mdt> colaRulesMap = getCOLARulesMap();

        // Process each quote line item
        for (QuoteLineItem qli : items) {
            if (qli.QuoteActionId == null) {
                continue;
            }

            QuoteAction qa = quoteActions.get(qli.QuoteActionId);
            if (qa == null || qa.SourceAsset == null) {
                continue;
            }

            // Get the Asset price as base
            Decimal assetPrice = qa.SourceAsset.Price;
            if (assetPrice == null) {
                continue;
            }

            // Get Solution Category directly from Product2
            String solutionCategory = null;
            if (qa.SourceAsset.Product2 != null) {
                solutionCategory = qa.SourceAsset.Product2.Solution_Category__c;
            }

            // Resolve the two system inputs (Contract override + CMDT default) exactly as before, then
            // delegate the tier selection to the one engine (D-13). INSERT has no Line Override, so
            // resolveTier(null, null, cmdtDefault, contractPct) provably collapses to Contract-else-CMDT.
            Decimal contractPct = null;
            if (qa.SourceAssetId != null && contractOverridesByAssetId.containsKey(qa.SourceAssetId)) {
                ContractOverride contractOverride = contractOverridesByAssetId.get(qa.SourceAssetId);
                if (contractOverride.isValid) {
                    contractPct = contractOverride.overridePercent;
                }
            }
            Decimal cmdtDefault = 0;
            if (String.isNotBlank(solutionCategory) && colaRulesMap.containsKey(solutionCategory)) {
                COLA_Uplift_Rules__mdt rule = colaRulesMap.get(solutionCategory);
                if (rule.Is_Active__c) {
                    cmdtDefault = rule.Default_Uplift_Percent__c != null ? rule.Default_Uplift_Percent__c : 0;
                }
            }
            COLAUpliftCalculator.TierResult tier = COLAUpliftCalculator.resolveTier(null, null, cmdtDefault, contractPct);
            Decimal colaPercent = tier.percent;
            String colaSource = tier.source;

            // Calculate new price with COLA
            Decimal newPrice = assetPrice * (1 + (colaPercent / 100));

            // Populate COLA fields
            qli.UnitPrice = newPrice;
            qli.Pre_COLA_Price__c = assetPrice;
            qli.COLA_Uplift_Percent__c = colaPercent;
            qli.Default_COLA_Uplift_Percent__c = colaPercent;
            qli.COLA_Solution_Category__c = solutionCategory;
            qli.COLA_Applied_Date__c = DateTime.now();
            // Is_COLA_Overridden__c derived (pct == Default at insert -> false).
            qli.COLA_Source__c = colaSource;
        }
    }

    /**
     * @description Recalculates UnitPrice when COLA percentage is overridden by user
     * @param changedItems List of QuoteLineItem records with changed COLA percentage
     */
    private static void recalculateCOLAPrice(List<QuoteLineItem> changedItems) {
        for (QuoteLineItem qli : changedItems) {
            if (qli.Pre_COLA_Price__c != null && qli.COLA_Uplift_Percent__c != null) {
                // Recalculate price using Pre-COLA price as base
                Decimal newPrice = qli.Pre_COLA_Price__c * (1 + (qli.COLA_Uplift_Percent__c / 100));
                qli.UnitPrice = newPrice;

                // Update audit fields
                qli.COLA_Modified_By__c = UserInfo.getUserId();
                qli.COLA_Modified_Date__c = DateTime.now();

                // Set override flag and source (Tier 1 - Line Override takes priority).
                // Do NOT re-derive the classification for a line already promoted to
                // Line Override by the predicate-based blocks above (year-1 / outyear):
                // recomputing from the possibly-stale Default_COLA_Uplift_Percent__c can
                // wrongly clear a genuine override — e.g. a null-old / legacy line whose
                // stale Default happens to equal the user's value while the active CMDT
                // rate differs. Those blocks own Is_COLA_Overridden__c / COLA_Source__c.
                if (qli.COLA_Source__c != 'Line Override') {
                    // Is_COLA_Overridden__c is derived (formula); use a local for the source promotion.
                    Boolean overridden = (qli.COLA_Uplift_Percent__c != qli.Default_COLA_Uplift_Percent__c);
                    if (overridden) {
                        qli.COLA_Source__c = 'Line Override';
                    }
                }
            }
        }
    }

    /**
     * @description Gets COLA rules from Custom Metadata Type, indexed by Solution Category
     * @return Map of COLA rules keyed by Solution Category name
     */
    private static Map<String, COLA_Uplift_Rules__mdt> getCOLARulesMap() {
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
    private static Map<Id, ContractOverride> getContractOverrides(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new Map<Id, ContractOverride>();
        }

        // Query AssetContractRelationship using elevated access helper.
        // This is necessary because Revenue Cloud objects may not be accessible
        // via dynamic SOQL in trigger context with sharing enforcement.
        // NOTE: queryAssetContracts runs the live AssetContractRelationship + Contract
        // SOQL inside its own try/catch; this method only transforms its rows.
        List<AssetContractQueryHelper.AssetContractData> contractDataList =
            AssetContractQueryHelper.queryAssetContracts(assetIds);

        return buildContractOverrideMap(contractDataList);
    }

    /**
     * @description Builds the keyed-by-Asset Contract-override map from already-queried
     *              AssetContractData rows, applying the persist-date validity logic. Pure in-memory
     *              transform (no SOQL/DML) so tests can drive the Tier-2 validity branches with
     *              in-memory AssetContractData rows -- the underlying AssetContractRelationship cannot
     *              be inserted in a test on this org (the linked Asset needs platform-owned
     *              HasLifecycleManagement=true). The live path delegates here unchanged.
     * @param contractDataList AssetContractData rows from AssetContractQueryHelper.queryAssetContracts
     * @return Map of valid ContractOverride wrappers keyed by Asset Id
     */
    @TestVisible
    private static Map<Id, ContractOverride> buildContractOverrideMap(
        List<AssetContractQueryHelper.AssetContractData> contractDataList
    ) {
        Map<Id, ContractOverride> overrideMap = new Map<Id, ContractOverride>();
        if (contractDataList == null) {
            return overrideMap;
        }

        Date today = Date.today();

        for (AssetContractQueryHelper.AssetContractData contractData : contractDataList) {
            // Skip if no COLA override set
            if (contractData.colaOverridePercent == null) {
                continue;
            }

            // Check if override is valid based on persist date logic
            Boolean isValid = false;
            Date persistUntil = contractData.colaPersistUntil;

            if (persistUntil == null) {
                // Null persist date = one-time use, valid for next renewal
                isValid = true;
            } else if (persistUntil >= today) {
                // Future persist date = valid for renewals until that date
                isValid = true;
            }
            // Past persist date = expired, not valid (isValid remains false)

            if (isValid) {
                ContractOverride colaOverride = new ContractOverride();
                colaOverride.contractId = contractData.contractId;
                colaOverride.overridePercent = contractData.colaOverridePercent;
                colaOverride.persistUntil = persistUntil;
                colaOverride.isValid = true;

                // Only use the first valid activated Contract per Asset
                // (In practice, there should only be one active Contract per Asset)
                if (!overrideMap.containsKey(contractData.assetId)) {
                    overrideMap.put(contractData.assetId, colaOverride);
                }
            }
        }

        return overrideMap;
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

}