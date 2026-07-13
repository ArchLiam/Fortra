// Does buildContext(sourceRecordId=quoteId) hydrate quote lines? (mirror applyNetPricesToOrder)
Id quoteId = '0Q0WC000003FcrF0AS';   // FcrF: 2 AAMP lines
Context.IndustriesContext ctx = new Context.IndustriesContext();
try {
    Map<String, Object> buildResult = ctx.buildContext(new Map<String, Object>{
        'contextDefinitionName' => 'SalesTransactionContextExt_v2',
        'sourceRecordId' => quoteId
    });
    System.debug('BUILD-OK keys=' + buildResult.keySet());
    Object cidO = buildResult.get('contextId') != null ? buildResult.get('contextId') : buildResult.get('contextInstanceId');
    String cid = String.valueOf(cidO);
    System.debug('CID=' + cid);
    Map<String, Object> res = ctx.queryTags(new Map<String, Object>{
        'contextId' => cid, 'tags' => new List<String>{ 'SalesTransactionItem' } });
    // count SalesTransactionItem line entries
    Object qr = res.containsKey('queryResult') ? res.get('queryResult') : res;
    Object items = (qr instanceof Map<String,Object>) ? ((Map<String,Object>)qr).get('SalesTransactionItem') : null;
    Integer n = (items instanceof List<Object>) ? ((List<Object>)items).size() : (items != null ? 1 : 0);
    System.debug('QT-SalesTransactionItem-count=' + n);
} catch (Exception e) {
    System.debug('BUILD-FAIL: ' + e.getTypeName() + ' | ' + e.getMessage());
}
