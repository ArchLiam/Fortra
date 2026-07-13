cd /Users/liamjeong/Documents/Code/Fortra
echo "=== reset S6 line to pre-smoke 593.28 (it's 824 now from the earlier refresh) + null Ifvp ==="
cat > /tmp/reset_fillonly.apex <<'APEX'
for (QuoteLineItem l : [SELECT Id,LineNumber FROM QuoteLineItem WHERE Id='0Q0WC000003IKeT' OR QuoteId='0Q0WC0000035dGj']) {}
// S6: set existing UnitPrice back to net so we can prove fill-only leaves it
List<QuoteLineItem> s6=[SELECT Id,LineNumber FROM QuoteLineItem WHERE QuoteId='0Q0WC0000035dGj' AND LineNumber='4266009'];
for(QuoteLineItem l:s6) l.UnitPrice=593.28;
update s6;
// Ifvp: null both to prove fill-only still fills blanks
List<QuoteLineItem> iv=[SELECT Id FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp'];
for(QuoteLineItem l:iv) l.UnitPrice=null;
update iv;
System.debug('SETUP done');
APEX
sf apex run -o FortraUAT -f /tmp/reset_fillonly.apex 2>&1 | grep -iE "SETUP|error" | head -3
echo "=== reprice S6 + Ifvp ==="
for q in 0Q0WC0000035dGj 0Q0WC000003Ifvp; do
  sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body "{\"inputs\":[{\"QuoteId\":\"$q\"}]}" -o FortraUAT 2>/dev/null | python3 -c "import sys,json;print('  reprice $q:',json.load(sys.stdin)[0].get('isSuccess'))"
done
sleep 45
echo "=== RESULT ==="
echo "S6 line 4266009 (existing 593.28 must be UNCHANGED - fill-only):"
sf data query -o FortraUAT -q "SELECT LineNumber,UnitPrice,NetUnitPrice,Pre_Partner_Price__c FROM QuoteLineItem WHERE QuoteId='0Q0WC0000035dGj' AND LineNumber='4266009'" 2>/dev/null | grep -vE "Warning|Querying"
echo "Ifvp (blank must be FILLED to Net - fill-only fills blanks):"
sf data query -o FortraUAT -q "SELECT LineNumber,UnitPrice,NetUnitPrice FROM QuoteLineItem WHERE QuoteId='0Q0WC000003Ifvp' ORDER BY LineNumber" 2>/dev/null | grep -vE "Warning|Querying"
