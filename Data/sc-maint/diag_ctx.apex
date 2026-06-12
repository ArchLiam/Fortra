// Probe Context API behavior with a bogus context id (simulates what tests will hit)
try {
    Context.IndustriesContext ctx = new Context.IndustriesContext();
    Map<String,Object> r = ctx.queryTags(new Map<String,Object>{ 'contextId' => 'bogus123', 'tags' => new List<String>{'SalesTransactionItem'} });
    System.debug('DIAGCTX queryTags returned: ' + r);
} catch (Exception e) {
    System.debug('DIAGCTX queryTags THREW: ' + e.getTypeName() + ' :: ' + e.getMessage());
}
try {
    Context.IndustriesContext ctx2 = new Context.IndustriesContext();
    Map<String,Object> b = ctx2.buildContext(new Map<String,Object>{ 'contextDefinitionName' => 'SalesTransactionContextExt_v2', 'sourceRecordId' => UserInfo.getUserId() });
    System.debug('DIAGCTX buildContext returned: ' + b);
} catch (Exception e) {
    System.debug('DIAGCTX buildContext THREW: ' + e.getTypeName() + ' :: ' + e.getMessage());
}
