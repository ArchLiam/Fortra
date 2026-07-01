Database.DMLOptions dml = new Database.DMLOptions(); dml.DuplicateRuleHeader.AllowSave=true;
System.Savepoint sp=Database.setSavepoint();
try {
  AttributeBasedAdjustment adj = new AttributeBasedAdjustment(
    ProductId='01tWC00000DD11YYAT', ProductSellingModelId='0jPWC00000005yz2AA',
    PriceAdjustmentScheduleId='84Xa50000010nWQEAY', AttributeBasedAdjRuleId='12HWC000001YthR2AS',
    AdjustmentType='Override', AdjustmentValue=1575,
    EffectiveFrom=DateTime.newInstanceGmt(2025,11,14,15,31,0));
  Database.SaveResult sr = Database.insert(adj, dml);
  System.debug(LoggingLevel.ERROR,'D03_STEP2 success='+sr.isSuccess()+' id='+sr.getId()+' errors='+sr.getErrors());
} catch(Exception e){ Database.rollback(sp); System.debug(LoggingLevel.ERROR,'D03_STEP2_FAIL '+e.getMessage()); throw e; }
