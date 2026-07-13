List<QuoteLineItem> s6=[SELECT Id,LineNumber,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC0000035dGj' AND LineNumber='04266009'];
for(QuoteLineItem l:s6) l.UnitPrice=593.28;
update s6;
for(QuoteLineItem l:[SELECT LineNumber,UnitPrice,NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC0000035dGj' AND LineNumber='04266009'])
  System.debug('RESTORED '+l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice);
