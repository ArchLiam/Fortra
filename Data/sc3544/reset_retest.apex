// Reset the probe-stamped lines to null, then save -> flow should stamp EXACT (scale 2)
List<QuoteLineItem> lines = [SELECT Id, LineNumber, UnitPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber];
for (QuoteLineItem l : lines) l.UnitPrice = null;
update lines;  // ISBLANK(UnitPrice) -> flow fills exact
List<QuoteLineItem> after = [SELECT LineNumber, UnitPrice, NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber];
for (QuoteLineItem l : after) System.debug('RESULT '+l.LineNumber+' UnitPrice='+l.UnitPrice+' Net='+l.NetUnitPrice+' MATCH='+(l.UnitPrice==l.NetUnitPrice));
