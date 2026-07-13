#!/bin/bash
cd /Users/liamjeong/Documents/Code/Fortra
Q=0Q0WC000003Ifvp
# 1) null UnitPrice (flow is obsolete -> should stay null)
cat > /tmp/null_ifvp.apex <<'APEX'
List<QuoteLineItem> ls=[SELECT Id,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp'];
for(QuoteLineItem l:ls) l.UnitPrice=null;
update ls;
for(QuoteLineItem l:[SELECT LineNumber,UnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber]) System.debug('POST-NULL '+l.LineNumber+' UnitPrice='+l.UnitPrice);
APEX
echo "=== null UnitPrice (confirm flow gone -> stays null) ==="
sf apex run -o FortraUAT -f /tmp/null_ifvp.apex 2>&1 | grep POST-NULL
echo ""
echo "=== reprice via production flow ==="
sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body '{"inputs":[{"QuoteId":"0Q0WC000003Ifvp"}]}' -o FortraUAT 2>/dev/null | python3 -c "import sys,json;print('reprice isSuccess:',json.load(sys.stdin)[0].get('isSuccess'))"
echo "=== wait for async post-persist queueable ==="
sleep 45
echo "=== RESULT: did the Apex post-persist stamp fill UnitPrice? ==="
sf data query -o FortraUAT -q "SELECT LineNumber,UnitPrice,NetUnitPrice,LastModifiedDate FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber" 2>/dev/null | grep -vE "Warning|Querying"
