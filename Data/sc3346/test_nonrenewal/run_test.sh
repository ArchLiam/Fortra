#!/bin/zsh
set -e
cd /Users/liamjeong/Documents/Code/Fortra
ORG=FortraUAT
QUOTE=0Q0WC0000037AKH0A2
OUT=Data/sc3346/test_nonrenewal
echo "=== 1. VERIFY the edit is live in the active V23 runtime (re-retrieve) ==="
sf project retrieve start -m "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" -o $ORG -r $OUT/verify_after >/dev/null 2>&1
VF=$(find $OUT/verify_after -name "*.expressionSetDefinition*" | head -1)
NRLINE=$(grep -nE "Renewal__SC3346_DISABLED" "$VF" | head -1)
echo "sentinel in retrieved active-block? -> ${NRLINE:-NONE}"
echo ""
echo "=== 2. Set FINEST trace flag on running user ==="
sf apex run --file /dev/stdin -o $ORG >/dev/null 2>&1 <<'APEX'
Id uid = UserInfo.getUserId();
List<DebugLevel> dls = [SELECT Id FROM DebugLevel WHERE DeveloperName='SC3346Finest' LIMIT 1];
Id dlId;
if (dls.isEmpty()) {
  DebugLevel dl = new DebugLevel(DeveloperName='SC3346Finest', MasterLabel='SC3346Finest', ApexCode='FINEST', ApexProfiling='FINEST', System='FINEST', Database='FINEST', Validation='INFO', Visualforce='INFO', Workflow='INFO', Callout='INFO');
  insert dl; dlId = dl.Id;
} else { dlId = dls[0].Id; }
System.debug('DEBUGLEVEL='+dlId);
APEX
echo "(trace flag handled separately if needed)"
echo ""
echo "=== 3. Baseline maint net BEFORE reprice ==="
sf data query -o $ORG -q "SELECT Product2.ProductCode, NetUnitPrice, UnitPrice FROM QuoteLineItem WHERE QuoteId='$QUOTE'" 2>&1 | grep -v Warning
echo ""
echo "=== 4. PST Force reprice (full engine) ==="
cat > /tmp/pst_body.json <<JSON
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"$QUOTE"}}}]}}
JSON
sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" --method POST --body /tmp/pst_body.json -o $ORG 2>&1 | grep -v Warning | head -40
echo ""
echo "=== 5. Maint net AFTER reprice ==="
sleep 3
sf data query -o $ORG -q "SELECT Product2.ProductCode, NetUnitPrice, UnitPrice FROM QuoteLineItem WHERE QuoteId='$QUOTE'" 2>&1 | grep -v Warning
