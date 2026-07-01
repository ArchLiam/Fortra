/**
 * @description Wrapper classes for Context Definition dependency management.
 *              These classes represent the dependency tree structure and operation results.
 */
public class ContextDependencyWrapper {

    /**
     * @description Represents a Context Definition with its full dependency tree
     */
    public class ContextDefinitionNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public List<ExpressionSetNode> expressionSets { get; set; }
        @AuraEnabled public List<ConfigurationRuleNode> configurationRules { get; set; }
        @AuraEnabled public List<RuleLibraryVersionNode> ruleLibraryVersions { get; set; }
        @AuraEnabled public List<DecisionTableNode> decisionTables { get; set; }
        @AuraEnabled public Integer totalDependencies { get; set; }
        @AuraEnabled public Integer activeDependencies { get; set; }
        @AuraEnabled public Integer activeConfigRuleCount { get; set; }
        @AuraEnabled public Integer activeRuleLibraryVersionCount { get; set; }
        @AuraEnabled public Integer activeDecisionTableCount { get; set; }

        public ContextDefinitionNode() {
            this.expressionSets = new List<ExpressionSetNode>();
            this.configurationRules = new List<ConfigurationRuleNode>();
            this.ruleLibraryVersions = new List<RuleLibraryVersionNode>();
            this.decisionTables = new List<DecisionTableNode>();
            this.totalDependencies = 0;
            this.activeDependencies = 0;
            this.activeConfigRuleCount = 0;
            this.activeRuleLibraryVersionCount = 0;
            this.activeDecisionTableCount = 0;
        }
    }

    /**
     * @description Represents an Expression Set
     */
    public class ExpressionSetNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String expressionSetName { get; set; }  // From ExpressionSetDefinition.MasterLabel
        @AuraEnabled public String contextDefinitionId { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public List<ExpressionSetVersionNode> versions { get; set; }
        @AuraEnabled public Integer activeVersionCount { get; set; }
        @AuraEnabled public Integer totalVersionCount { get; set; }

        public ExpressionSetNode() {
            this.versions = new List<ExpressionSetVersionNode>();
            this.activeVersionCount = 0;
            this.totalVersionCount = 0;
        }
    }

    /**
     * @description Represents an Expression Set Version
     */
    public class ExpressionSetVersionNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String expressionSetId { get; set; }
        @AuraEnabled public String expressionSetName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer rank { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }

        public ExpressionSetVersionNode() {
            this.isActive = false;
        }
    }

    /**
     * @description Represents a Decision Table in RLM (2026)
     *              Decision Tables must be deactivated to unlock the Context Definition.
     *              Status IS DML-updateable (Active/Inactive).
     */
    public class DecisionTableNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String contextDefinitionId { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }

        public DecisionTableNode() {
            this.isActive = false;
        }
    }

    /**
     * @description Represents a RuleLibraryVersion in RLM (2026)
     *              Deactivating a RuleLibraryVersion automatically disables all rules within it
     *              and releases the lock on the associated Context Definition.
     */
    public class RuleLibraryVersionNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String versionNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String ruleLibraryId { get; set; }
        @AuraEnabled public String ruleLibraryName { get; set; }
        @AuraEnabled public Integer ruleCount { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }

        public RuleLibraryVersionNode() {
            this.isActive = false;
            this.ruleCount = 0;
        }
    }

    /**
     * @description Represents a ProductConfigurationRule (Configuration Rule / "Dynamic Rule")
     *              These rules use context tags from Context Definitions and must be
     *              deactivated via the UI or Metadata API before deactivating the Context Definition.
     */
    public class ConfigurationRuleNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String ruleType { get; set; }
        @AuraEnabled public String processScope { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Datetime effectiveFromDate { get; set; }
        @AuraEnabled public Datetime effectiveToDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public String usageSubType { get; set; }
        @AuraEnabled public Boolean canDeactivateViaDml { get; set; }

        public ConfigurationRuleNode() {
            this.isActive = false;
            this.canDeactivateViaDml = false;  // Status is not updateable via DML
        }
    }

    /**
     * @description Result of a dependency management operation
     */
    public class OperationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<ItemResult> itemResults { get; set; }
        @AuraEnabled public Integer totalProcessed { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public String operationType { get; set; }  // 'DEACTIVATE' or 'REACTIVATE'
        @AuraEnabled public Datetime operationTimestamp { get; set; }

        public OperationResult() {
            this.itemResults = new List<ItemResult>();
            this.totalProcessed = 0;
            this.successCount = 0;
            this.failureCount = 0;
            this.operationTimestamp = Datetime.now();
        }

        public void addSuccess(String itemId, String itemName, String itemType) {
            ItemResult ir = new ItemResult();
            ir.itemId = itemId;
            ir.itemName = itemName;
            ir.itemType = itemType;
            ir.success = true;
            ir.message = 'Successfully processed';
            this.itemResults.add(ir);
            this.totalProcessed++;
            this.successCount++;
        }

        public void addFailure(String itemId, String itemName, String itemType, String errorMessage) {
            ItemResult ir = new ItemResult();
            ir.itemId = itemId;
            ir.itemName = itemName;
            ir.itemType = itemType;
            ir.success = false;
            ir.message = errorMessage;
            this.itemResults.add(ir);
            this.totalProcessed++;
            this.failureCount++;
        }

        public void finalize() {
            if (this.failureCount == 0) {
                this.success = true;
                this.message = 'All ' + this.totalProcessed + ' items processed successfully';
            } else if (this.successCount == 0) {
                this.success = false;
                this.message = 'All ' + this.totalProcessed + ' items failed to process';
            } else {
                this.success = false;
                this.message = this.successCount + ' of ' + this.totalProcessed + ' items processed. ' +
                              this.failureCount + ' failures.';
            }
        }
    }

    /**
     * @description Result for an individual item in an operation
     */
    public class ItemResult {
        @AuraEnabled public String itemId { get; set; }
        @AuraEnabled public String itemName { get; set; }
        @AuraEnabled public String itemType { get; set; }  // 'ExpressionSetVersion', 'ContextDefinition', etc.
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String previousStatus { get; set; }
        @AuraEnabled public String newStatus { get; set; }
    }

    /**
     * @description Summary of a Context Definition for list views
     */
    public class ContextDefinitionSummary {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Integer expressionSetCount { get; set; }
        @AuraEnabled public Integer activeVersionCount { get; set; }
        @AuraEnabled public Boolean hasDependencies { get; set; }
        @AuraEnabled public Boolean canDeactivate { get; set; }

        public ContextDefinitionSummary() {
            this.expressionSetCount = 0;
            this.activeVersionCount = 0;
            this.hasDependencies = false;
            this.canDeactivate = true;
        }
    }

    /**
     * @description Configuration for deactivation/reactivation operations
     */
    public class OperationConfig {
        @AuraEnabled public Boolean includeInactiveVersions { get; set; }
        @AuraEnabled public Boolean stopOnFirstError { get; set; }
        @AuraEnabled public Boolean dryRun { get; set; }  // Preview without making changes
        @AuraEnabled public List<String> excludeVersionIds { get; set; }  // Versions to skip

        public OperationConfig() {
            this.includeInactiveVersions = false;
            this.stopOnFirstError = false;
            this.dryRun = false;
            this.excludeVersionIds = new List<String>();
        }
    }

}