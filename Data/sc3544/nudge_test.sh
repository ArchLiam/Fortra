cd /Users/liamjeong/Documents/Code/Fortra
Q=0Q0WC000003Ifvp
echo "=== bump line 2 qty 1->2 (force non-idempotent reprice), null UnitPrice on both ==="
cat > /tmp/nudge.apex <<'APEX'
List<QuoteLineItem> ls=[SELECT Id,LineNumber,Quantity,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber];
for(QuoteLineItem l:ls){ l.UnitPrice=null; if(l.LineNumber=='04267452') l.Quantity=2; }
update ls;
for(QuoteLineItem l:[SELECT LineNumber,Quantity,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber]) System.debug('PRE '+l.LineNumber+' Qty='+l.Quantity+' UnitPrice='+l.UnitPrice);
APEX
sf apex run -o FortraUAT -f /tmp/nudge.apex 2>&1 | grep "PRE "
echo "=== reprice (now non-idempotent) ==="
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body '{"inputs":[{"QuoteId":"0Q0WC000003Ifvp"}]}' -o FortraUAT 2>/dev/null | python3 -c "import sys,json;print('reprice:',json.load(sys.stdin)[0].get('isSuccess'))"
sleep 40
echo "=== RESULT: did UnitPrice fill + queueable enqueue? ==="
sf data query -o FortraUAT -q "SELECT LineNumber,Quantity,UnitPrice,NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber" 2>/dev/null | grep -vE "Warning|Querying"
sf data query -o FortraUAT -q "SELECT Status,CreatedDate FROM AsyncApexJob WHERE ApexClass.Name='QuotePriceStampQueueable' ORDER BY CreatedDate DESC LIMIT 2" 2>/dev/null | grep -vE "Warning|Querying"
echo "=== revert qty 2->1 ==="
cat > /tmp/revert.apex <<'APEX'
List<QuoteLineItem> ls=[SELECT Id,LineNumber,Quantity FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp'];
for(QuoteLineItem l:ls) if(l.LineNumber=='04267452') l.Quantity=1;
update ls;
APEX
sf apex run -o FortraUAT -f /tmp/revert.apex 2>&1 | grep -iE "compiled|success" | head -1
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body '{"inputs":[{"QuoteId":"0Q0WC000003Ifvp"}]}' -o FortraUAT 2>/dev/null >/dev/null
echo "reverted + repriced"
