// fix_d03_aba_rule.apex
// D-03 data fix (FortraUAT): add the missing Attribute-Based Adjustment for
//   Advanced Authentication Modes (01tWC00000DD11YYAT), One-Time PSM 0jPWC00000005yz2AA,
//   schedule 84Xa50000010nWQEAY, combo {Deployment=On Premise, Feature Options=SFTP Server,
//   Server Type=Non-Production} -> AdjustmentValue 1575 (Non-Prod 50% of SFTP/Production 3150).
// AttributeAdjConditionsHash / AttributeCount / ScheduleType are platform-computed (createable=false).
// Savepoint-wrapped; rolls back + re-throws on any error.

final Id PRODUCT   = '01tWC00000DD11YYAT';
final Id PSM       = '0jPWC00000005yz2AA';
final Id SCHEDULE  = '84Xa50000010nWQEAY';
final Id DEF_DEPLOY = '0tjWC000000096YYAQ'; // Deployment Option
final Id DEF_FEATURE= '0tjWC000000096ZYAQ'; // Feature Options
final Id DEF_SERVER = '0tjWC000000096jYAA'; // Server Type
final Decimal ADJ_VALUE = 1575;

Database.DMLOptions dml = new Database.DMLOptions();
dml.DuplicateRuleHeader.AllowSave = true;

System.Savepoint sp = Database.setSavepoint();
try {
    // 1) Rule
    AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name = 'ABARule_AA_SFTP_NonProd');
    Database.insert(rule, dml);

    // 2) Conditions (3) — equals on the three attribute definitions
    List<AttributeAdjustmentCondition> conds = new List<AttributeAdjustmentCondition>{
        new AttributeAdjustmentCondition(AttributeBasedAdjRuleId = rule.Id, ProductId = PRODUCT,
            AttributeDefinitionId = DEF_DEPLOY,  Operator = 'equals', StringValue = 'On Premise'),
        new AttributeAdjustmentCondition(AttributeBasedAdjRuleId = rule.Id, ProductId = PRODUCT,
            AttributeDefinitionId = DEF_FEATURE, Operator = 'equals', StringValue = 'SFTP Server'),
        new AttributeAdjustmentCondition(AttributeBasedAdjRuleId = rule.Id, ProductId = PRODUCT,
            AttributeDefinitionId = DEF_SERVER,  Operator = 'equals', StringValue = 'Non-Production')
    };
    Database.insert(conds, dml);

    // 3) Adjustment (platform fills AttributeAdjConditionsHash / AttributeCount / ScheduleType)
    AttributeBasedAdjustment adj = new AttributeBasedAdjustment(
        ProductId = PRODUCT, ProductSellingModelId = PSM, PriceAdjustmentScheduleId = SCHEDULE,
        AttributeBasedAdjRuleId = rule.Id, AdjustmentValue = ADJ_VALUE);
    Database.insert(adj, dml);

    // verify the platform computed the hash
    AttributeBasedAdjustment chk = [SELECT Id, AdjustmentValue, AttributeCount, ScheduleType, AttributeAdjConditionsHash
                                    FROM AttributeBasedAdjustment WHERE Id = :adj.Id];
    String base = 'https://fortra--uat.sandbox.lightning.force.com/lightning/r/';
    System.debug(LoggingLevel.ERROR, 'D03_FIX_OK rule=' + rule.Id + ' adj=' + adj.Id
        + ' value=' + chk.AdjustmentValue + ' attrCount=' + chk.AttributeCount
        + ' scheduleType=' + chk.ScheduleType + ' hash=' + chk.AttributeAdjConditionsHash
        + ' | ' + base + 'AttributeBasedAdjustment/' + adj.Id + '/view');
    if (chk.AttributeAdjConditionsHash == null) {
        System.debug(LoggingLevel.ERROR, 'D03_FIX_WARN hash not computed in-transaction; will need 2-step insert.');
    }
} catch (Exception e) {
    Database.rollback(sp);
    System.debug(LoggingLevel.ERROR, 'D03_FIX_FAIL ' + e.getTypeName() + ': ' + e.getMessage());
    throw e;
}
