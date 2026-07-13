List<QuoteLineItem> lines = [SELECT Id, UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp'];
for (QuoteLineItem l : lines) l.UnitPrice = null;
update lines;
for (QuoteLineItem l : [SELECT LineNumber,UnitPrice,LastModifiedDate FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber])
  System.debug('NULLED '+l.LineNumber+' UnitPrice='+l.UnitPrice+' LMD='+l.LastModifiedDate);
