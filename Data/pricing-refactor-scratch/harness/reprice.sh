#!/usr/bin/env bash
# Force-reprice a Quote via the managed place action, then wait for the post-persist
# stamp queueable to drain. READ+WRITE (the reprice is the only write). Usage: ./reprice.sh <quoteId>
set -euo pipefail
QID="${1:?quote id}"; ORG="${ORG:-FortraUAT}"
BODY=$(cat <<JSON
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"$QID"}}}]}}
JSON
)
echo "$BODY" > /tmp/reprice_body.json
sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" \
  --method POST -o "$ORG" --body "@/tmp/reprice_body.json" > /tmp/reprice_resp.json 2>/tmp/reprice_err.txt || {
    echo "REPRICE-HTTP-ERR $QID"; cat /tmp/reprice_err.txt; tail -c 500 /tmp/reprice_resp.json; exit 1; }
# surface any error in the response
python3 - "$QID" <<'PY'
import json,sys
qid=sys.argv[1]
try:
    d=json.load(open('/tmp/reprice_resp.json'))
except Exception as e:
    print("REPRICE-PARSE-ERR", qid, e); sys.exit(0)
s=json.dumps(d)
low=s.lower()
if '"errors"' in low and '"errors":[]' not in low and '"errors":null' not in low:
    print("REPRICE-RESP-ERRORS", qid, s[:400])
else:
    print("REPRICE-OK", qid)
PY
# Drain the QuotePriceStampQueueable (post-persist Source_List_Price / UnitPrice stamp).
python3 - "$ORG" <<'PY'
import subprocess, json, time, sys
org=sys.argv[1]
for i in range(20):
    r=subprocess.run(["sf","data","query","-o",org,"--query",
        "SELECT COUNT() FROM AsyncApexJob WHERE JobType='Queueable' AND ApexClass.Name='QuotePriceStampQueueable' AND Status IN ('Queued','Processing','Preparing','Holding')",
        "--json"],capture_output=True,text=True)
    try:
        n=json.loads(r.stdout)['result']['totalSize']
    except Exception:
        n=json.loads(r.stdout)['result']['records'][0]['expr0']
    if n==0:
        print(f"QUEUEABLE-DRAINED after {i}s"); break
    time.sleep(2)
else:
    print("QUEUEABLE-STILL-PENDING (proceeding)")
PY
