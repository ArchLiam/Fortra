// Step 1: rule + 3 conditions (commit) for D-03 AA SFTP/On-Prem/Non-Production
final Id PRODUCT='01tWC00000DD11YYAT';
Database.DMLOptions dml = new Database.DMLOptions(); dml.DuplicateRuleHeader.AllowSave=true;
System.Savepoint sp=Database.setSavepoint();
try {
  AttributeBasedAdjRule rule = new AttributeBasedAdjRule(Name='ABARule_AA_SFTP_NonProd');
  Database.insert(rule, dml);
  List<AttributeAdjustmentCondition> c = new List<AttributeAdjustmentCondition>{
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=rule.Id,ProductId=PRODUCT,AttributeDefinitionId='0tjWC000000096YYAQ',Operator='equals',StringValue='On Premise'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=rule.Id,ProductId=PRODUCT,AttributeDefinitionId='0tjWC000000096ZYAQ',Operator='equals',StringValue='SFTP Server'),
    new AttributeAdjustmentCondition(AttributeBasedAdjRuleId=rule.Id,ProductId=PRODUCT,AttributeDefinitionId='0tjWC000000096jYAA',Operator='equals',StringValue='Non-Production')};
  Database.insert(c, dml);
  Integer n=[SELECT COUNT() FROM AttributeAdjustmentCondition WHERE AttributeBasedAdjRuleId=:rule.Id];
  System.debug(LoggingLevel.ERROR,'D03_STEP1_OK rule='+rule.Id+' conditions='+n);
} catch(Exception e){ Database.rollback(sp); System.debug(LoggingLevel.ERROR,'D03_STEP1_FAIL '+e.getMessage()); throw e; }
