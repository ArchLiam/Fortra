#!/bin/bash
# ============================================================================
# LEVER-D (H5) TEST — STEP 3: VERIFY   (reprices Draft test quotes — MUTATING,
# but only Draft canary/test quotes; NEVER the Accepted line dAaT4AU)
# Run AFTER the new procedure version is ACTIVE. Reprices each target Draft
# quote (Force/Skip), then asserts the 3 cruxes + regression guards.
# ============================================================================
set -uo pipefail
ORG="FortraUAT"
D="Data/sc-maint/rca_deep/leverd_test"
API="/services/data/v64.0/connect/rev/sales-transaction/actions/place"
mkdir -p "$D/run"

# quote -> {line: expected_net}.  Accepted quote 0037yTx is DELIBERATELY EXCLUDED.
reprice () { # $1=quoteId
  local body="/tmp/leverd_rp_$1.json"
  cat > "$body" <<JSON
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"1","records":[{"referenceId":"r","record":{"attributes":{"type":"Quote","method":"PATCH","id":"$1"}}}]}}
JSON
  sf api request rest "$API" --method POST --body @"$body" -o "$ORG" 2>/dev/null \
    | grep -vE "Warning|beta|scripts" \
    | python3 -c "import sys,json;
try:
 d=json.load(sys.stdin); print('   reprice %s -> isSuccess=%s err=%s'%('$1',d.get('isSuccess'),str(d.get('errorResponse'))[:80]))
except Exception as e: print('   reprice $1 PARSE:',sys.stdin.read()[:120])"
}

echo "### 1. Reprice the 5 broken Draft target quotes + the control quote (Force/Skip) ###"
for q in 0Q0WC0000038aXd0AI 0Q0WC0000037XvB0AU 0Q0WC0000037AKH0A2 0Q0WC0000039AMb0AM 0Q0WC0000037muD0AQ 0Q0WC00000382MH0AY; do reprice "$q"; done
echo "### 2. Reprice the regression-guard quotes (NB-derive 71, perpetual 355) ###"
for q in 0Q0WC0000037rFZ0AY 0Q0WC000002sjLZ0AY; do reprice "$q"; done
sleep 4

echo
echo "### 3. ASSERT — committed NetUnitPrice + rollups vs expectation ###"
sf data query -o "$ORG" --json \
  -q "SELECT Id, Quote.Status, Product2.ProductCode, NetUnitPrice, COLACalculatedPrice__c, NetTotalPrice FROM QuoteLineItem WHERE Id IN ('0QLWC000003e2Sn4AI','0QLWC000003ck6X4AQ','0QLWC000003cN584AE','0QLWC000003eMph4AE','0QLWC000003cy334AA','0QLWC000003dEW24AM','0QLWC000003d2Q14AI','0QLWC000003NO7x4AG','0QLWC000003dAaT4AU')" \
  2>/dev/null | grep -vE "Warning: @salesforce" > "$D/run/baseline_after.json"
python3 - "$D/run/baseline_after.json" <<'PY'
import sys,json
recs={r['Id'][:18]:r for r in json.load(open(sys.argv[1]))['result']['records']}
# expected committed NetUnitPrice after fix
exp={'0QLWC000003e2Sn4AI':67.38,'0QLWC000003ck6X4AQ':67.38,'0QLWC000003cN584AE':67.38,
     '0QLWC000003eMph4AE':60.64,'0QLWC000003cy334AA':60.64,         # TARGETS (flip + $0 overwrite crux)
     '0QLWC000003dEW24AM':67.38,                                     # CONTROL stays
     '0QLWC000003d2Q14AI':71.0,'0QLWC000003NO7x4AG':355.0,           # REGRESSION stays
     '0QLWC000003dAaT4AU':60.64}                                     # ACCEPTED untouched (expect unchanged)
role={'0QLWC000003e2Sn4AI':'TARGET','0QLWC000003ck6X4AQ':'TARGET($0)','0QLWC000003cN584AE':'TARGET($0)',
      '0QLWC000003eMph4AE':'TARGET','0QLWC000003cy334AA':'TARGET','0QLWC000003dEW24AM':'CONTROL',
      '0QLWC000003d2Q14AI':'REGRESS','0QLWC000003NO7x4AG':'REGRESS','0QLWC000003dAaT4AU':'ACCEPTED'}
ok=True; print(f"{'role':12}{'Id':20}{'Net':>9}{'exp':>9}{'NetTotal':>10}  verdict")
for i,e in exp.items():
    r=recs.get(i)
    if not r: print(f"{role[i]:12}{i:20}{'--MISSING--':>9}"); ok=False; continue
    net=r.get('NetUnitPrice'); nt=r.get('NetTotalPrice')
    good = (net is not None and abs(float(net)-e)<0.005)
    # rollup crux: for targets, NetTotalPrice should also reflect the new net (qty 1 -> == net)
    roll = (nt is not None and abs(float(nt)-e)<0.005) if role[i].startswith('TARGET') else True
    v = 'PASS' if good and roll else ('NET✗' if not good else 'ROLLUP-STALE✗')
    if not (good and roll): ok=False
    print(f"{role[i]:12}{i:20}{str(net):>9}{e:>9.2f}{str(nt):>10}  {v}")
print()
print("CRUX 1 overwrite-settled-node:", "PASS — fossils flipped" if ok else "CHECK — a target/$0 line did not flip")
print("CRUX 2 rollup-staleness:", "see NetTotal column (targets must == net)")
print("REGRESSION:", "control 67.38 + NB-derive 71 + perpetual 355 must be unchanged")
print("\nVERDICT:", "✅ LEVER-D CONFIRMED — ship as primary fix" if ok else "❌ NOT clean — capture FINEST, fall back to H3 born-net, then ROLLBACK (04)")
PY
echo
echo "### 4. (recommended) Pull the FINEST reprice log of the canary to confirm the WRITE LANDED ###"
echo "   sf data query --use-tooling-api -o $ORG -q \"SELECT Id,Operation,StartTime FROM ApexLog ORDER BY StartTime DESC LIMIT 5\""
echo "   Then: sf apex get log -i <id> -o $ORG | grep -E 'RenMaintCOLA|NetUnitPrice=\\{0QLWC000003e2Sn4AI'"
echo
echo "Regardless of outcome, run 04_rollback (reactivate prior V14) to close the window unless shipping lever-d."
