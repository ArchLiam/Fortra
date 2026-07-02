/**
 * @description Service class for managing Context Definition dependencies.
 *              Provides functionality to:
 *              - Query Context Definitions and their dependency trees
 *              - Deactivate all Expression Set Versions before Context Definition deactivation
 *              - Reactivate Expression Set Versions in the correct order
 *              - Display ProductConfigurationRules (Dynamic Rules) that reference the context
 *
 * Schema (Revenue Cloud):
 * ContextDefinition
 *   → ExpressionSetDefinitionContextDefinition (junction via ContextDefinitionId)
 *     → ExpressionSetDefinition (via ExpressionSetDefinitionId)
 *       → ExpressionSet (via ExpressionSetDefinitionId)
 *         → ExpressionSetVersion (via ExpressionSetId, IsActive boolean field)
 *   → ProductConfigurationRule (implicit via context tag usage in ConfigurationRuleDefinition)
 *       Note: Status is NOT updateable via DML - requires Metadata API or UI
 *
 * @usage Invoked from LWC component or via Anonymous Apex
 */
public with sharing class ContextDefinitionManager {

    // ============================================================
    // CONTEXT DEFINITION QUERIES
    // ============================================================

    /**
     * @description Gets all Context Definitions in the org with summary info
     * @return List of ContextDefinitionSummary objects
     */
    @AuraEnabled(cacheable=true)
    public static List<ContextDependencyWrapper.ContextDefinitionSummary> getContextDefinitions() {
        List<ContextDependencyWrapper.ContextDefinitionSummary> summaries =
            new List<ContextDependencyWrapper.ContextDefinitionSummary>();

        // Query all Context Definitions
        List<ContextDefinition> contextDefs = [
            SELECT Id, DeveloperName, MasterLabel, Description
            FROM ContextDefinition
            ORDER BY MasterLabel
        ];

        // For each Context Definition, count its dependencies
        for (ContextDefinition cd : contextDefs) {
            ContextDependencyWrapper.ContextDefinitionSummary summary =
                new ContextDependencyWrapper.ContextDefinitionSummary();

            summary.id = cd.Id;
            summary.developerName = cd.DeveloperName;
            summary.masterLabel = cd.MasterLabel;
            summary.isActive = true; // ContextDefinition doesn't have IsActive field

            // Get Expression Set counts via junction object
            Map<String, Integer> counts = getDependencyCounts(cd.Id);
            summary.expressionSetCount = counts.get('totalExpressionSets');
            summary.activeVersionCount = counts.get('activeVersions');
            summary.hasDependencies = summary.expressionSetCount > 0;
            summary.canDeactivate = summary.activeVersionCount == 0;

            summaries.add(summary);
        }

        return summaries;
    }

    /**
     * @description Gets the full dependency tree for a Context Definition
     * @param contextDefinitionId The ID of the Context Definition
     * @return ContextDefinitionNode with full dependency tree
     */
    @AuraEnabled(cacheable=true)
    public static ContextDependencyWrapper.ContextDefinitionNode getDependencyTree(
        String contextDefinitionId
    ) {
        // Get the Context Definition
        ContextDefinition cd = [
            SELECT Id, DeveloperName, MasterLabel, Description
            FROM ContextDefinition
            WHERE Id = :contextDefinitionId
            LIMIT 1
        ];

        ContextDependencyWrapper.ContextDefinitionNode node =
            new ContextDependencyWrapper.ContextDefinitionNode();
        node.id = cd.Id;
        node.developerName = cd.DeveloperName;
        node.masterLabel = cd.MasterLabel;
        node.isActive = true;
        node.description = cd.Description;

        // Get Expression Set Definitions linked via junction object
        List<ExpressionSetDefinitionContextDefinition> junctions = [
            SELECT Id, ExpressionSetDefinitionId, ContextDefinitionId
            FROM ExpressionSetDefinitionContextDefinition
            WHERE ContextDefinitionId = :contextDefinitionId
        ];

        Set<Id> expressionSetDefIds = new Set<Id>();
        for (ExpressionSetDefinitionContextDefinition j : junctions) {
            expressionSetDefIds.add(j.ExpressionSetDefinitionId);
        }

        if (expressionSetDefIds.isEmpty()) {
            return node;
        }

        // Get Expression Set Definitions
        Map<Id, ExpressionSetDefinition> expressionSetDefs = new Map<Id, ExpressionSetDefinition>([
            SELECT Id, DeveloperName, MasterLabel
            FROM ExpressionSetDefinition
            WHERE Id IN :expressionSetDefIds
        ]);

        // Get Expression Sets linked to these definitions
        List<ExpressionSet> expressionSets = [
            SELECT Id, Name, ApiName, Description, ExpressionSetDefinitionId
            FROM ExpressionSet
            WHERE ExpressionSetDefinitionId IN :expressionSetDefIds
            ORDER BY Name
        ];

        // Get all Expression Set IDs
        Set<Id> expressionSetIds = new Set<Id>();
        for (ExpressionSet es : expressionSets) {
            expressionSetIds.add(es.Id);
        }

        // Get all versions for these Expression Sets
        List<ExpressionSetVersion> versions = new List<ExpressionSetVersion>();
        if (!expressionSetIds.isEmpty()) {
            versions = [
                SELECT Id, Name, ExpressionSetId, IsActive, Rank, VersionNumber,
                       CreatedDate, LastModifiedDate
                FROM ExpressionSetVersion
                WHERE ExpressionSetId IN :expressionSetIds
                ORDER BY ExpressionSetId, Rank DESC
            ];
        }

        // Group versions by Expression Set
        Map<Id, List<ContextDependencyWrapper.ExpressionSetVersionNode>> versionsByEs =
            new Map<Id, List<ContextDependencyWrapper.ExpressionSetVersionNode>>();

        for (ExpressionSetVersion v : versions) {
            ContextDependencyWrapper.ExpressionSetVersionNode vNode =
                new ContextDependencyWrapper.ExpressionSetVersionNode();
            vNode.id = v.Id;
            vNode.name = v.Name;
            vNode.expressionSetId = v.ExpressionSetId;
            vNode.status = v.IsActive ? 'Active' : 'Inactive';
            vNode.rank = (Integer)v.Rank;
            vNode.isActive = v.IsActive;
            vNode.createdDate = v.CreatedDate;
            vNode.lastModifiedDate = v.LastModifiedDate;

            if (!versionsByEs.containsKey(v.ExpressionSetId)) {
                versionsByEs.put(v.ExpressionSetId,
                    new List<ContextDependencyWrapper.ExpressionSetVersionNode>());
            }
            versionsByEs.get(v.ExpressionSetId).add(vNode);

            // Count total dependencies
            node.totalDependencies++;
            if (vNode.isActive) {
                node.activeDependencies++;
            }
        }

        // Build Expression Set nodes
        for (ExpressionSet es : expressionSets) {
            ContextDependencyWrapper.ExpressionSetNode esNode =
                new ContextDependencyWrapper.ExpressionSetNode();
            esNode.id = es.Id;
            esNode.name = es.Name;
            esNode.apiName = es.ApiName;
            esNode.contextDefinitionId = contextDefinitionId;
            esNode.description = es.Description;

            // Get the Expression Set Definition info
            if (expressionSetDefs.containsKey(es.ExpressionSetDefinitionId)) {
                ExpressionSetDefinition esd = expressionSetDefs.get(es.ExpressionSetDefinitionId);
                esNode.expressionSetName = esd.MasterLabel;
            }

            esNode.versions = versionsByEs.get(es.Id) != null ?
                              versionsByEs.get(es.Id) :
                              new List<ContextDependencyWrapper.ExpressionSetVersionNode>();
            esNode.totalVersionCount = esNode.versions.size();

            // Count active versions
            for (ContextDependencyWrapper.ExpressionSetVersionNode v : esNode.versions) {
                if (v.isActive) {
                    esNode.activeVersionCount++;
                }
            }

            node.expressionSets.add(esNode);
        }

        // Query ProductConfigurationRules (Dynamic Rules) that use Transaction context
        // These rules use context tags from the Context Definition
        node.configurationRules = getConfigurationRulesForContext(cd.DeveloperName);
        for (ContextDependencyWrapper.ConfigurationRuleNode rule : node.configurationRules) {
            if (rule.isActive) {
                node.activeConfigRuleCount++;
            }
        }

        // Query RuleLibraryVersions (RLM 2026)
        // Deactivating the Rule Library Version unlocks the Context Definition
        node.ruleLibraryVersions = getRuleLibraryVersions();
        for (ContextDependencyWrapper.RuleLibraryVersionNode rlv : node.ruleLibraryVersions) {
            if (rlv.isActive) {
                node.activeRuleLibraryVersionCount++;
            }
        }

        // Query Decision Tables (RLM 2026)
        // Decision Tables must be deactivated before Context Definition
        node.decisionTables = getDecisionTables();
        for (ContextDependencyWrapper.DecisionTableNode dt : node.decisionTables) {
            if (dt.isActive) {
                node.activeDecisionTableCount++;
            }
        }

        return node;
    }

    /**
     * @description Gets ProductConfigurationRules that use context tags (Dynamic Rules)
     *              These rules reference the Context Definition through their ConfigurationRuleDefinition
     * @param contextDeveloperName The developer name of the Context Definition
     * @return List of ConfigurationRuleNode objects
     */
    private static List<ContextDependencyWrapper.ConfigurationRuleNode> getConfigurationRulesForContext(
        String contextDeveloperName
    ) {
        List<ContextDependencyWrapper.ConfigurationRuleNode> rules =
            new List<ContextDependencyWrapper.ConfigurationRuleNode>();

        // Query ProductConfigurationRules that use Transaction context
        // The ConfigurationRuleDefinition JSON contains usageSubType: "Transaction"
        List<ProductConfigurationRule> configRules = [
            SELECT Id, Name, ApiName, Status, RuleType, ProcessScope, Description,
                   EffectiveFromDate, EffectiveToDate, LastModifiedDate, ConfigurationRuleDefinition
            FROM ProductConfigurationRule
            ORDER BY Name
            LIMIT 200
        ];

        for (ProductConfigurationRule pcr : configRules) {
            // Parse the JSON to check if this rule uses Transaction context
            String usageSubType = extractUsageSubType(pcr.ConfigurationRuleDefinition);

            // Only include rules that use Transaction context (which use the Sales Transaction Context Definition)
            if (usageSubType == 'Transaction') {
                ContextDependencyWrapper.ConfigurationRuleNode ruleNode =
                    new ContextDependencyWrapper.ConfigurationRuleNode();
                ruleNode.id = pcr.Id;
                ruleNode.name = pcr.Name;
                ruleNode.apiName = pcr.ApiName;
                ruleNode.status = pcr.Status;
                ruleNode.ruleType = pcr.RuleType;
                ruleNode.processScope = pcr.ProcessScope;
                ruleNode.description = pcr.Description;
                ruleNode.isActive = (pcr.Status == 'Active');
                ruleNode.effectiveFromDate = pcr.EffectiveFromDate;
                ruleNode.effectiveToDate = pcr.EffectiveToDate;
                ruleNode.lastModifiedDate = pcr.LastModifiedDate;
                ruleNode.usageSubType = usageSubType;
                ruleNode.canDeactivateViaDml = false;  // Status is not DML-updateable

                rules.add(ruleNode);
            }
        }

        return rules;
    }

    /**
     * @description Extracts the usageSubType from ConfigurationRuleDefinition JSON
     * @param ruleDefinition The JSON string containing the rule definition
     * @return The usageSubType value or null if not found
     */
    private static String extractUsageSubType(String ruleDefinition) {
        if (String.isBlank(ruleDefinition)) {
            return null;
        }

        try {
            // Simple JSON parsing to extract usageSubType
            Map<String, Object> ruleMap = (Map<String, Object>)JSON.deserializeUntyped(ruleDefinition);
            return (String)ruleMap.get('usageSubType');
        } catch (Exception e) {
            return null;
        }
    }

    // ============================================================
    // DEACTIVATION OPERATIONS
    // ============================================================

    /**
     * @description Deactivates all active Expression Set Versions for a Context Definition
     * @param contextDefinitionId The ID of the Context Definition
     * @param config Operation configuration (optional)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateAllDependencies(
        String contextDefinitionId,
        ContextDependencyWrapper.OperationConfig config
    ) {
        if (config == null) {
            config = new ContextDependencyWrapper.OperationConfig();
        }

        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE';

        try {
            // Get Expression Set IDs linked to this Context Definition
            Set<Id> expressionSetIds = getExpressionSetIdsForContextDef(contextDefinitionId);

            if (expressionSetIds.isEmpty()) {
                result.success = true;
                result.message = 'No Expression Sets found for this Context Definition';
                return result;
            }

            // Get all active Expression Set Versions
            List<ExpressionSetVersion> activeVersions = [
                SELECT Id, Name, IsActive, ExpressionSetId
                FROM ExpressionSetVersion
                WHERE ExpressionSetId IN :expressionSetIds
                  AND IsActive = true
                  AND Id NOT IN :config.excludeVersionIds
                ORDER BY ExpressionSetId, Rank DESC
            ];

            if (activeVersions.isEmpty()) {
                result.success = true;
                result.message = 'No active Expression Set Versions found to deactivate';
                return result;
            }

            // Check if this is a dry run
            if (config.dryRun) {
                for (ExpressionSetVersion v : activeVersions) {
                    result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
                }
                result.message = 'DRY RUN: Would deactivate ' + activeVersions.size() +
                                ' Expression Set Versions';
                result.success = true;
                return result;
            }

            // Deactivate by setting IsActive = false
            for (ExpressionSetVersion v : activeVersions) {
                v.IsActive = false;
            }

            // Perform partial update to handle individual failures
            Database.SaveResult[] saveResults = Database.update(activeVersions, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                ExpressionSetVersion v = activeVersions[i];
                if (saveResults[i].isSuccess()) {
                    result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
                } else {
                    String errorMsg = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    result.addFailure(v.Id, v.Name, 'ExpressionSetVersion', errorMsg);

                    if (config.stopOnFirstError) {
                        break;
                    }
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error during deactivation: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Deactivates a single Expression Set Version
     * @param versionId The ID of the Expression Set Version
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateVersion(String versionId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE';

        try {
            ExpressionSetVersion v = [
                SELECT Id, Name, IsActive
                FROM ExpressionSetVersion
                WHERE Id = :versionId
                LIMIT 1
            ];

            if (!v.IsActive) {
                result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
                result.message = 'Version is already inactive';
                result.success = true;
                return result;
            }

            v.IsActive = false;
            update v;

            result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error deactivating version: ' + e.getMessage();
        }

        return result;
    }

    // ============================================================
    // REACTIVATION OPERATIONS
    // ============================================================

    /**
     * @description Reactivates Expression Set Versions that were previously active
     * @param contextDefinitionId The ID of the Context Definition
     * @param versionIds List of version IDs to reactivate (optional - if null, reactivates all)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateDependencies(
        String contextDefinitionId,
        List<String> versionIds
    ) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE';

        try {
            List<ExpressionSetVersion> versionsToActivate;

            if (versionIds != null && !versionIds.isEmpty()) {
                versionsToActivate = [
                    SELECT Id, Name, IsActive, ExpressionSetId
                    FROM ExpressionSetVersion
                    WHERE Id IN :versionIds
                      AND IsActive = false
                ];
            } else {
                // Get Expression Set IDs for this Context Definition
                Set<Id> expressionSetIds = getExpressionSetIdsForContextDef(contextDefinitionId);

                if (expressionSetIds.isEmpty()) {
                    result.success = true;
                    result.message = 'No Expression Sets found for this Context Definition';
                    return result;
                }

                // Reactivate all inactive versions
                versionsToActivate = [
                    SELECT Id, Name, IsActive, ExpressionSetId
                    FROM ExpressionSetVersion
                    WHERE ExpressionSetId IN :expressionSetIds
                      AND IsActive = false
                    ORDER BY ExpressionSetId, Rank DESC
                ];
            }

            if (versionsToActivate.isEmpty()) {
                result.success = true;
                result.message = 'No inactive Expression Set Versions found to reactivate';
                return result;
            }

            // Update IsActive to true
            for (ExpressionSetVersion v : versionsToActivate) {
                v.IsActive = true;
            }

            Database.SaveResult[] saveResults = Database.update(versionsToActivate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                ExpressionSetVersion v = versionsToActivate[i];
                if (saveResults[i].isSuccess()) {
                    result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
                } else {
                    String errorMsg = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    result.addFailure(v.Id, v.Name, 'ExpressionSetVersion', errorMsg);
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error during reactivation: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Reactivates a single Expression Set Version
     * @param versionId The ID of the Expression Set Version
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateVersion(String versionId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE';

        try {
            ExpressionSetVersion v = [
                SELECT Id, Name, IsActive
                FROM ExpressionSetVersion
                WHERE Id = :versionId
                LIMIT 1
            ];

            if (v.IsActive) {
                result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
                result.message = 'Version is already active';
                result.success = true;
                return result;
            }

            v.IsActive = true;
            update v;

            result.addSuccess(v.Id, v.Name, 'ExpressionSetVersion');
            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error reactivating version: ' + e.getMessage();
        }

        return result;
    }

    // ============================================================
    // RULE LIBRARY VERSION OPERATIONS (RLM 2026)
    // ============================================================

    /**
     * @description Gets all RuleLibraryVersions in the org
     *              In RLM, deactivating a RuleLibraryVersion automatically disables all rules
     *              and releases the lock on the associated Context Definition.
     * @return List of RuleLibraryVersionNode objects
     */
    private static List<ContextDependencyWrapper.RuleLibraryVersionNode> getRuleLibraryVersions() {
        List<ContextDependencyWrapper.RuleLibraryVersionNode> versions =
            new List<ContextDependencyWrapper.RuleLibraryVersionNode>();

        try {
            // Query RuleLibraryVersions
            List<RuleLibraryVersion> rlvList = [
                SELECT Id, Name, Status, VersionNumber, RuleLibraryId, RuleLibrary.Name, LastModifiedDate
                FROM RuleLibraryVersion
                ORDER BY RuleLibrary.Name, VersionNumber DESC
                LIMIT 100
            ];

            for (RuleLibraryVersion rlv : rlvList) {
                ContextDependencyWrapper.RuleLibraryVersionNode node =
                    new ContextDependencyWrapper.RuleLibraryVersionNode();
                node.id = rlv.Id;
                node.name = rlv.Name;
                node.versionNumber = String.valueOf(rlv.VersionNumber);
                node.status = rlv.Status;
                node.isActive = (rlv.Status == 'Active');
                node.ruleLibraryId = rlv.RuleLibraryId;
                node.ruleLibraryName = rlv.RuleLibrary?.Name;
                node.lastModifiedDate = rlv.LastModifiedDate;

                // Count rules in this version (if needed for display)
                node.ruleCount = 0;

                versions.add(node);
            }
        } catch (Exception e) {
            // RuleLibraryVersion might not exist in all orgs
            System.debug('RuleLibraryVersion query failed: ' + e.getMessage());
        }

        return versions;
    }

    /**
     * @description Deactivates all active RuleLibraryVersions
     *              This unlocks the Context Definition for deactivation
     * @param contextDefinitionId The ID of the Context Definition (for logging purposes)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateRuleLibraryVersions(
        String contextDefinitionId
    ) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE_RULE_LIBRARY_VERSIONS';

        try {
            // Get active RuleLibraryVersions
            List<RuleLibraryVersion> activeVersions = [
                SELECT Id, Name, Status, RuleLibrary.Name
                FROM RuleLibraryVersion
                WHERE Status = 'Active'
                ORDER BY Name
            ];

            if (activeVersions.isEmpty()) {
                result.success = true;
                result.message = 'No active Rule Library Versions found to deactivate';
                return result;
            }

            // Deactivate by setting Status = 'Inactive'
            for (RuleLibraryVersion rlv : activeVersions) {
                rlv.Status = 'Inactive';
            }

            // Perform partial update to handle individual failures
            Database.SaveResult[] saveResults = Database.update(activeVersions, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                RuleLibraryVersion rlv = activeVersions[i];
                String itemName = rlv.RuleLibrary?.Name + ' - ' + rlv.Name;
                if (saveResults[i].isSuccess()) {
                    result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
                } else {
                    String errorMsg = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    result.addFailure(rlv.Id, itemName, 'RuleLibraryVersion', errorMsg);
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error deactivating Rule Library Versions: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Reactivates all inactive RuleLibraryVersions
     * @param contextDefinitionId The ID of the Context Definition (for logging purposes)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateRuleLibraryVersions(
        String contextDefinitionId
    ) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE_RULE_LIBRARY_VERSIONS';

        try {
            // Get inactive RuleLibraryVersions
            List<RuleLibraryVersion> inactiveVersions = [
                SELECT Id, Name, Status, RuleLibrary.Name
                FROM RuleLibraryVersion
                WHERE Status = 'Inactive'
                ORDER BY Name
            ];

            if (inactiveVersions.isEmpty()) {
                result.success = true;
                result.message = 'No inactive Rule Library Versions found to reactivate';
                return result;
            }

            // Reactivate by setting Status = 'Active'
            for (RuleLibraryVersion rlv : inactiveVersions) {
                rlv.Status = 'Active';
            }

            // Perform partial update
            Database.SaveResult[] saveResults = Database.update(inactiveVersions, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                RuleLibraryVersion rlv = inactiveVersions[i];
                String itemName = rlv.RuleLibrary?.Name + ' - ' + rlv.Name;
                if (saveResults[i].isSuccess()) {
                    result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
                } else {
                    String errorMsg = '';
                    for (Database.Error err : saveResults[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    result.addFailure(rlv.Id, itemName, 'RuleLibraryVersion', errorMsg);
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error reactivating Rule Library Versions: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Deactivates a single RuleLibraryVersion
     * @param versionId The ID of the RuleLibraryVersion
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateRuleLibraryVersion(String versionId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE_RULE_LIBRARY_VERSION';

        try {
            RuleLibraryVersion rlv = [
                SELECT Id, Name, Status, RuleLibrary.Name
                FROM RuleLibraryVersion
                WHERE Id = :versionId
                LIMIT 1
            ];

            String itemName = rlv.RuleLibrary?.Name + ' - ' + rlv.Name;

            if (rlv.Status == 'Inactive') {
                result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
                result.message = 'Rule Library Version is already inactive';
                result.success = true;
                return result;
            }

            rlv.Status = 'Inactive';
            update rlv;

            result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error deactivating Rule Library Version: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Reactivates a single RuleLibraryVersion
     * @param versionId The ID of the RuleLibraryVersion
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateRuleLibraryVersion(String versionId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE_RULE_LIBRARY_VERSION';

        try {
            RuleLibraryVersion rlv = [
                SELECT Id, Name, Status, RuleLibrary.Name
                FROM RuleLibraryVersion
                WHERE Id = :versionId
                LIMIT 1
            ];

            String itemName = rlv.RuleLibrary?.Name + ' - ' + rlv.Name;

            if (rlv.Status == 'Active') {
                result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
                result.message = 'Rule Library Version is already active';
                result.success = true;
                return result;
            }

            rlv.Status = 'Active';
            update rlv;

            result.addSuccess(rlv.Id, itemName, 'RuleLibraryVersion');
            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error reactivating Rule Library Version: ' + e.getMessage();
        }

        return result;
    }

    // ============================================================
    // DECISION TABLE OPERATIONS (RLM 2026)
    // Note: DecisionTable requires Tooling API for status updates - DML is not allowed
    // ============================================================

    /**
     * @description Gets all Decision Tables in the org
     *              Decision Tables must be deactivated before the Context Definition.
     *              Note: Status updates require Tooling API, not standard DML.
     * @return List of DecisionTableNode objects
     */
    private static List<ContextDependencyWrapper.DecisionTableNode> getDecisionTables() {
        List<ContextDependencyWrapper.DecisionTableNode> tables =
            new List<ContextDependencyWrapper.DecisionTableNode>();

        try {
            // Query Decision Tables
            List<DecisionTable> dtList = [
                SELECT Id, DeveloperName, MasterLabel, Status, Description, LastModifiedDate
                FROM DecisionTable
                ORDER BY MasterLabel
                LIMIT 200
            ];

            for (DecisionTable dt : dtList) {
                ContextDependencyWrapper.DecisionTableNode node =
                    new ContextDependencyWrapper.DecisionTableNode();
                node.id = dt.Id;
                node.developerName = dt.DeveloperName;
                node.masterLabel = dt.MasterLabel;
                node.status = dt.Status;
                node.isActive = (dt.Status == 'Active');
                node.description = dt.Description;
                node.lastModifiedDate = dt.LastModifiedDate;

                tables.add(node);
            }
        } catch (Exception e) {
            // DecisionTable might not exist in all orgs
            System.debug('DecisionTable query failed: ' + e.getMessage());
        }

        return tables;
    }

    /**
     * @description Updates a Decision Table status using REST API
     *              DecisionTable does not allow standard DML updates, must use REST API callout
     *              Note: Uses standard REST API endpoint (not Tooling API)
     * @param tableId The ID of the Decision Table
     * @param newStatus The new status ('Active' or 'Inactive')
     * @return True if successful, false otherwise
     */
    private static Boolean updateDecisionTableViaRestApi(String tableId, String newStatus) {
        HttpRequest req = new HttpRequest();
        // Use standard REST API endpoint (NOT Tooling API)
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() +
            '/services/data/v60.0/sobjects/DecisionTable/' + tableId);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setBody('{"Status": "' + newStatus + '"}');

        Http http = new Http();
        HttpResponse res = http.send(req);

        // 200 or 204 indicates success
        return res.getStatusCode() == 200 || res.getStatusCode() == 204;
    }

    /**
     * @description Deactivates all active Decision Tables using Tooling API
     *              This is required to unlock the Context Definition for deactivation
     * @param contextDefinitionId The ID of the Context Definition (for logging purposes)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateDecisionTables(
        String contextDefinitionId
    ) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE_DECISION_TABLES';

        try {
            // Get active Decision Tables
            List<DecisionTable> activeTables = [
                SELECT Id, DeveloperName, MasterLabel, Status
                FROM DecisionTable
                WHERE Status = 'Active'
                ORDER BY MasterLabel
            ];

            if (activeTables.isEmpty()) {
                result.success = true;
                result.message = 'No active Decision Tables found to deactivate';
                return result;
            }

            // Deactivate each via Tooling API
            for (DecisionTable dt : activeTables) {
                String itemName = dt.MasterLabel != null ? dt.MasterLabel : dt.DeveloperName;
                try {
                    Boolean success = updateDecisionTableViaRestApi(dt.Id, 'Inactive');
                    if (success) {
                        result.addSuccess(dt.Id, itemName, 'DecisionTable');
                    } else {
                        result.addFailure(dt.Id, itemName, 'DecisionTable', 'REST API update failed');
                    }
                } catch (Exception e) {
                    result.addFailure(dt.Id, itemName, 'DecisionTable', e.getMessage());
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error deactivating Decision Tables: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Reactivates all inactive Decision Tables using Tooling API
     * @param contextDefinitionId The ID of the Context Definition (for logging purposes)
     * @return OperationResult with details of the operation
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateDecisionTables(
        String contextDefinitionId
    ) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE_DECISION_TABLES';

        try {
            // Get inactive Decision Tables
            List<DecisionTable> inactiveTables = [
                SELECT Id, DeveloperName, MasterLabel, Status
                FROM DecisionTable
                WHERE Status = 'Inactive'
                ORDER BY MasterLabel
            ];

            if (inactiveTables.isEmpty()) {
                result.success = true;
                result.message = 'No inactive Decision Tables found to reactivate';
                return result;
            }

            // Reactivate each via Tooling API
            for (DecisionTable dt : inactiveTables) {
                String itemName = dt.MasterLabel != null ? dt.MasterLabel : dt.DeveloperName;
                try {
                    Boolean success = updateDecisionTableViaRestApi(dt.Id, 'Active');
                    if (success) {
                        result.addSuccess(dt.Id, itemName, 'DecisionTable');
                    } else {
                        result.addFailure(dt.Id, itemName, 'DecisionTable', 'REST API update failed');
                    }
                } catch (Exception e) {
                    result.addFailure(dt.Id, itemName, 'DecisionTable', e.getMessage());
                }
            }

            result.finalize();

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error reactivating Decision Tables: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Deactivates a single Decision Table using Tooling API
     * @param tableId The ID of the Decision Table
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult deactivateDecisionTable(String tableId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'DEACTIVATE_DECISION_TABLE';

        try {
            DecisionTable dt = [
                SELECT Id, DeveloperName, MasterLabel, Status
                FROM DecisionTable
                WHERE Id = :tableId
                LIMIT 1
            ];

            String itemName = dt.MasterLabel != null ? dt.MasterLabel : dt.DeveloperName;

            if (dt.Status == 'Inactive') {
                result.addSuccess(dt.Id, itemName, 'DecisionTable');
                result.message = 'Decision Table is already inactive';
                result.success = true;
                return result;
            }

            Boolean success = updateDecisionTableViaRestApi(dt.Id, 'Inactive');
            if (success) {
                result.addSuccess(dt.Id, itemName, 'DecisionTable');
                result.finalize();
            } else {
                result.addFailure(dt.Id, itemName, 'DecisionTable', 'REST API update failed');
                result.finalize();
            }

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error deactivating Decision Table: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Reactivates a single Decision Table using Tooling API
     * @param tableId The ID of the Decision Table
     * @return OperationResult
     */
    @AuraEnabled
    public static ContextDependencyWrapper.OperationResult reactivateDecisionTable(String tableId) {
        ContextDependencyWrapper.OperationResult result =
            new ContextDependencyWrapper.OperationResult();
        result.operationType = 'REACTIVATE_DECISION_TABLE';

        try {
            DecisionTable dt = [
                SELECT Id, DeveloperName, MasterLabel, Status
                FROM DecisionTable
                WHERE Id = :tableId
                LIMIT 1
            ];

            String itemName = dt.MasterLabel != null ? dt.MasterLabel : dt.DeveloperName;

            if (dt.Status == 'Active') {
                result.addSuccess(dt.Id, itemName, 'DecisionTable');
                result.message = 'Decision Table is already active';
                result.success = true;
                return result;
            }

            Boolean success = updateDecisionTableViaRestApi(dt.Id, 'Active');
            if (success) {
                result.addSuccess(dt.Id, itemName, 'DecisionTable');
                result.finalize();
            } else {
                result.addFailure(dt.Id, itemName, 'DecisionTable', 'REST API update failed');
                result.finalize();
            }

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error reactivating Decision Table: ' + e.getMessage();
        }

        return result;
    }

    // ============================================================
    // UTILITY METHODS
    // ============================================================

    /**
     * @description Gets Expression Set IDs linked to a Context Definition
     * @param contextDefinitionId The ID of the Context Definition
     * @return Set of Expression Set IDs
     */
    private static Set<Id> getExpressionSetIdsForContextDef(String contextDefinitionId) {
        Set<Id> expressionSetIds = new Set<Id>();

        // Get Expression Set Definition IDs via junction
        List<ExpressionSetDefinitionContextDefinition> junctions = [
            SELECT ExpressionSetDefinitionId
            FROM ExpressionSetDefinitionContextDefinition
            WHERE ContextDefinitionId = :contextDefinitionId
        ];

        Set<Id> expressionSetDefIds = new Set<Id>();
        for (ExpressionSetDefinitionContextDefinition j : junctions) {
            expressionSetDefIds.add(j.ExpressionSetDefinitionId);
        }

        if (expressionSetDefIds.isEmpty()) {
            return expressionSetIds;
        }

        // Get Expression Sets linked to these definitions
        List<ExpressionSet> expressionSets = [
            SELECT Id
            FROM ExpressionSet
            WHERE ExpressionSetDefinitionId IN :expressionSetDefIds
        ];

        for (ExpressionSet es : expressionSets) {
            expressionSetIds.add(es.Id);
        }

        return expressionSetIds;
    }

    /**
     * @description Gets counts of active dependencies for a Context Definition
     * @param contextDefinitionId The ID of the Context Definition
     * @return Map with 'activeVersions', 'inactiveVersions', 'totalExpressionSets'
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getDependencyCounts(String contextDefinitionId) {
        Map<String, Integer> counts = new Map<String, Integer>{
            'activeVersions' => 0,
            'inactiveVersions' => 0,
            'totalExpressionSets' => 0
        };

        Set<Id> expressionSetIds = getExpressionSetIdsForContextDef(contextDefinitionId);
        counts.put('totalExpressionSets', expressionSetIds.size());

        if (expressionSetIds.isEmpty()) {
            return counts;
        }

        // Count versions by IsActive status
        List<AggregateResult> versionCounts = [
            SELECT IsActive, COUNT(Id) cnt
            FROM ExpressionSetVersion
            WHERE ExpressionSetId IN :expressionSetIds
            GROUP BY IsActive
        ];

        for (AggregateResult ar : versionCounts) {
            Boolean isActive = (Boolean)ar.get('IsActive');
            Integer count = (Integer)ar.get('cnt');
            if (isActive) {
                counts.put('activeVersions', count);
            } else {
                counts.put('inactiveVersions', count);
            }
        }

        return counts;
    }

    /**
     * @description Validates if the IsActive field on ExpressionSetVersion is DML-updateable
     * @return True if the field can be updated via DML
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isStatusFieldUpdateable() {
        try {
            Schema.DescribeFieldResult fieldDescribe =
                ExpressionSetVersion.IsActive.getDescribe();
            return fieldDescribe.isUpdateable();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Gets a preview of what would be deactivated (dry run)
     * @param contextDefinitionId The ID of the Context Definition
     * @return List of version summaries that would be affected
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getDeactivationPreview(String contextDefinitionId) {
        List<Map<String, Object>> preview = new List<Map<String, Object>>();

        Set<Id> expressionSetIds = getExpressionSetIdsForContextDef(contextDefinitionId);

        if (expressionSetIds.isEmpty()) {
            return preview;
        }

        List<ExpressionSetVersion> activeVersions = [
            SELECT Id, Name, IsActive, Rank, VersionNumber, ExpressionSetId
            FROM ExpressionSetVersion
            WHERE ExpressionSetId IN :expressionSetIds
              AND IsActive = true
            ORDER BY ExpressionSetId, Rank DESC
        ];

        // Get Expression Set names
        Map<Id, ExpressionSet> expressionSetMap = new Map<Id, ExpressionSet>([
            SELECT Id, Name, ApiName
            FROM ExpressionSet
            WHERE Id IN :expressionSetIds
        ]);

        for (ExpressionSetVersion v : activeVersions) {
            ExpressionSet es = expressionSetMap.get(v.ExpressionSetId);
            Map<String, Object> item = new Map<String, Object>{
                'id' => v.Id,
                'name' => v.Name,
                'expressionSetName' => es != null ? es.Name : 'Unknown',
                'expressionSetApiName' => es != null ? es.ApiName : 'Unknown',
                'rank' => v.Rank,
                'currentStatus' => 'Active',
                'newStatus' => 'Inactive'
            };
            preview.add(item);
        }

        return preview;
    }
}