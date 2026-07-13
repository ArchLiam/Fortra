Context.IndustriesContext ctx = new Context.IndustriesContext();
try {
    Map<String, Object> b = ctx.buildContext(new Map<String, Object>{
        'contextDefinitionName' => 'SalesTransactionContextExt_v2', 'sourceRecordId' => '801WC00000aYcxXYAS' });
    Object cidO = b.get('contextId') != null ? b.get('contextId') : b.get('contextInstanceId');
    Map<String, Object> res = ctx.queryTags(new Map<String, Object>{ 'contextId' => String.valueOf(cidO), 'tags' => new List<String>{ 'SalesTransactionItem' } });
    Object qr = res.containsKey('queryResult') ? res.get('queryResult') : res;
    Object items = (qr instanceof Map<String,Object>) ? ((Map<String,Object>)qr).get('SalesTransactionItem') : null;
    Integer n = (items instanceof List<Object>) ? ((List<Object>)items).size() : (items != null ? 1 : 0);
    System.debug('ORDER-BUILD-OK count=' + n);
} catch (Exception e) { System.debug('ORDER-BUILD-FAIL: ' + e.getMessage()); }
