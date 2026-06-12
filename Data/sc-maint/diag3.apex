String qliPrefix = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix();
String quotePrefix = Quote.SObjectType.getDescribe().getKeyPrefix();
System.debug('DIAG QLI prefix=' + qliPrefix + ' Quote prefix=' + quotePrefix);

// Old approach
try {
    Id bad = (Id) (qliPrefix + '000000000001AAA');
    System.debug('DIAG old 18-char parsed OK = ' + bad);
} catch (Exception e) {
    System.debug('DIAG old 18-char FAILED: ' + e.getMessage());
}

// New approach
String body = String.valueOf(1).leftPad(12, '0');
Id good = Id.valueOf(qliPrefix + body);
System.debug('DIAG new 15-char Id = ' + good + ' -> String.valueOf = ' + String.valueOf(good));
Id roundtrip = Id.valueOf(String.valueOf(good));
System.debug('DIAG roundtrip OK = ' + roundtrip);
