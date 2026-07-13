// Probe: does a standard QLI save fire Fortra_Stamp_Sales_Price and stamp UnitPrice?
List<QuoteLineItem> lines = [SELECT Id, LineNumber, UnitPrice, NetUnitPrice, Base_Price__c, Pre_Partner_Price__c
                             FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber];
System.debug('BEFORE:');
for (QuoteLineItem l : lines) System.debug(l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice);
try {
    update lines;               // standard DML -> fires before-save record-triggered flows
    System.debug('UPDATE OK');
} catch (Exception e) {
    System.debug('UPDATE BLOCKED: '+e.getMessage());
}
List<QuoteLineItem> after = [SELECT LineNumber, UnitPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber];
System.debug('AFTER:');
for (QuoteLineItem l : after) System.debug(l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice);
