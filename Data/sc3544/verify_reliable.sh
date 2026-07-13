cd /Users/liamjeong/Documents/Code/Fortra
Q=0Q0WC000003Ifvp
echo "=== null UnitPrice (flow gone -> stays null) ==="
cat > /tmp/null2.apex <<'APEX'
List<QuoteLineItem> ls=[SELECT Id,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp'];
for(QuoteLineItem l:ls) l.UnitPrice=null; update ls;
for(QuoteLineItem l:[SELECT LineNumber,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber]) System.debug('NULLED '+l.LineNumber+' UnitPrice='+l.UnitPrice);
APEX
sf apex run -o FortraUAT -f /tmp/null2.apex 2>&1 | grep NULLED
echo "=== latest queueable BEFORE reprice ==="
sf data query -o FortraUAT -q "SELECT CreatedDate FROM AsyncApexJob WHERE ApexClass.Name='QuotePriceStampQueueable' ORDER BY CreatedDate DESC LIMIT 1" 2>/dev/null | grep -oE "2026[^ ]+" | head -1
echo "=== reprice via flow v28 ==="
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body '{"inputs":[{"QuoteId":"0Q0WC000003Ifvp"}]}' -o FortraUAT 2>/dev/null | python3 -c "import sys,json;print('reprice:',json.load(sys.stdin)[0].get('isSuccess'))"
sleep 40
echo "=== RESULT: UnitPrice filled? new queueable? ==="
sf data query -o FortraUAT -q "SELECT LineNumber,UnitPrice,NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber" 2>/dev/null | grep -vE "Warning|Querying"
echo "latest queueables:"
sf data query -o FortraUAT -q "SELECT Status,CreatedDate FROM AsyncApexJob WHERE ApexClass.Name='QuotePriceStampQueueable' ORDER BY CreatedDate DESC LIMIT 2" 2>/dev/null | grep -oE "(Completed|Queued|Processing).*2026[^ ]+|2026-[0-9T:.-]+"
