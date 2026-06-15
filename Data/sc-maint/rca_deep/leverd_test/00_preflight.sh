#!/bin/bash
# ============================================================================
# LEVER-D (H5) TEST — STEP 0: PREFLIGHT  (READ-ONLY, safe to run anytime)
# Confirms the active procedure is clean V14 + captures the before-baseline.
# Run from repo root:  bash Data/sc-maint/rca_deep/leverd_test/00_preflight.sh
# ============================================================================
set -uo pipefail
ORG="FortraUAT"
D="Data/sc-maint/rca_deep/leverd_test"
mkdir -p "$D/run"

echo "### 1. Active pricing-procedure version (expect V14, sole Active) ###"
sf data query --use-tooling-api -o "$ORG" \
  -q "SELECT Id, VersionNumber FROM ExpressionSetVersion WHERE ExpressionSetId='9QLWC0000015cDl4AI' AND IsActive=true" \
  2>/dev/null | grep -vE "Warning: @salesforce"

echo
echo "### 2. Fresh retrieve of the LIVE procedure definition (for drift-safe build) ###"
rm -rf "$D/run/live" && mkdir -p "$D/run/live"
sf project retrieve start -o "$ORG" --api-version 67 \
  -m "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" \
  -r "$D/run/live" 2>/dev/null | grep -vE "Warning: @salesforce" | tail -3
LIVE=$(find "$D/run/live" -name "Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition" | head -1)
echo "retrieved: $LIVE"

echo
echo "### 3. GATE CHECK — does the ACTIVE definition already contain RenMaintCOLA? ###"
if [ -n "$LIVE" ] && grep -q "RenMaintCOLA" "$LIVE"; then
  echo "  ⚠️  PRESENT — a prior deploy already landed the element. STOP and confirm whether the"
  echo "      ACTIVE runtime version contains it and whether it is inert before re-deploying."
else
  echo "  ✓ ABSENT — active definition is clean; the test is genuinely untried. Proceed."
fi

echo
echo "### 4. BEFORE-baseline: target lines (must FLIP to COLACalc) + control + regression ###"
sf data query -o "$ORG" --json \
  -q "SELECT Id, QuoteId, Quote.Status, Product2.ProductCode, NetUnitPrice, COLACalculatedPrice__c, QuoteActionId, NetTotalPrice FROM QuoteLineItem WHERE Id IN ('0QLWC000003e2Sn4AI','0QLWC000003ck6X4AQ','0QLWC000003cN584AE','0QLWC000003eMph4AE','0QLWC000003cy334AA','0QLWC000003dEW24AM','0QLWC000003d2Q14AI','0QLWC000003NO7x4AG','0QLWC000003dAaT4AU')" \
  2>/dev/null | grep -vE "Warning: @salesforce" > "$D/run/baseline_before.json"
python3 - "$D/run/baseline_before.json" <<'PY'
import sys,json
recs=json.load(open(sys.argv[1]))['result']['records']
tgt={'0QLWC000003e2Sn4AI':67.38,'0QLWC000003ck6X4AQ':67.38,'0QLWC000003cN584AE':67.38,
     '0QLWC000003eMph4AE':60.64,'0QLWC000003cy334AA':60.64}
ctl={'0QLWC000003dEW24AM':67.38}
reg={'0QLWC000003d2Q14AI':71.0,'0QLWC000003NO7x4AG':355.0}
acc={'0QLWC000003dAaT4AU':'ACCEPTED — DO NOT REPRICE'}
print(f"{'Id':20}{'Code':22}{'Status':10}{'Net':>8}{'COLAcalc':>10}  role")
for r in recs:
    i=r['Id'][:18]
    role = ('TARGET→%.2f'%tgt[i] if i in tgt else 'CONTROL(stay %.2f)'%ctl[i] if i in ctl
            else 'REGRESS(stay %.2f)'%reg[i] if i in reg else acc.get(i,'?'))
    code=(r.get('Product2') or {}).get('ProductCode','')
    print(f"{i:20}{code:22}{(r.get('Quote') or {}).get('Status',''):10}{str(r.get('NetUnitPrice')):>8}{str(r.get('COLACalculatedPrice__c')):>10}  {role}")
print("\nBaseline saved -> Data/sc-maint/rca_deep/leverd_test/run/baseline_before.json")
PY
echo
echo "PREFLIGHT COMPLETE. If gate-check = ABSENT, proceed to 01_build_and_deploy.sh inside the republish window."
