Integer n = PartnerNetPricePosthook.stampAttributeListPricesForQuote('0Q0WC000003Ifvp');
System.debug('STAMPED rows=' + n);
for (QuoteLineItem l : [SELECT LineNumber,UnitPrice,NetUnitPrice,Base_Price__c,Pre_Partner_Price__c FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber])
    System.debug('AFTER '+l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice+' Base='+l.Base_Price__c+' Pre='+l.Pre_Partner_Price__c);
