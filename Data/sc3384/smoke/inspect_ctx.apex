// Does the context expose ABA_Raw_Net__c on the SalesTransactionItem node?
Context.IndustriesContext ctx = new Context.IndustriesContext();
Map<String, Object> build = ctx.buildContext(new Map<String, Object>{
    'contextDefinitionName' => 'SalesTransactionContextExt_v2', 'sourceRecordId' => '0Q0WC000003FcrF0AS' });
String cid = build.get('contextId') != null ? String.valueOf(build.get('contextId'))
                                             : String.valueOf(build.get('contextInstanceId'));
System.debug('CTXID=' + cid);
Map<String, Object> res = ctx.queryTags(new Map<String, Object>{
    'contextId' => cid, 'tags' => new List<String>{ 'SalesTransactionItem' } });
String s = JSON.serialize(res);
System.debug('HAS_ABA_TAG=' + s.contains('ABA_Raw_Net__c'));
System.debug('HAS_STICUR=' + s.contains('STICurrencyIsoCode'));
System.debug('HAS_NETUNIT=' + s.contains('NetUnitPrice'));
// print a slice around ABA if present
Integer i = s.indexOf('ABA_Raw_Net__c');
if (i >= 0) { System.debug('ABA_SLICE=' + s.substring(Math.max(0,i-20), Math.min(s.length(), i+80))); }
