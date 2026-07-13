#!/bin/bash
# SC-3544 full smoke matrix — Apex post-persist UnitPrice stamp.
# Proves: (a) UnitPrice fills on previously-blank renewal/derived/COLA lines via reprice;
#         (b) display-only — every OTHER oracle column is 0-delta on every scenario (--ignore UnitPrice);
#         (c) idempotency — 2nd reprice identical;
#         (d) D-18 Exception_Log__c stays clean.
cd /Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/harness
export ORG=FortraUAT
OUT=post_sc3544_apex
mkdir -p $OUT/before $OUT/after $OUT/after2

reprice(){ sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" \
  --method POST --body "{\"inputs\":[{\"QuoteId\":\"$1\"}]}" -o FortraUAT 2>/dev/null \
  | python3 -c "import sys,json;print(json.load(sys.stdin)[0].get('isSuccess'))" 2>/dev/null; }

# distinct real quotes from scenarios.tsv (col2), skip NEEDS-DATA
SCN=$(python3 -c "
import csv
seen=set()
with open('scenarios.tsv') as f:
    for r in csv.DictReader(f,delimiter='\t'):
        q=r['quote_id'].strip()
        if q and q!='NEEDS-DATA' and q not in seen:
            seen.add(q); print(r['id'], q)
")

LOG0=$(sf data query -o FortraUAT -q "SELECT count() FROM Exception_Log__c" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
echo "### D-18 Exception_Log__c rows BEFORE: $LOG0"
echo ""
echo "### PHASE 1: snapshot BEFORE + reprice"
while read sid qid; do
  ./snapshot.sh Quote "$qid" "$OUT/before/$sid.tsv" 2>/dev/null
  R=$(reprice "$qid")
  echo "  $sid ($qid) reprice=$R"
done <<< "$SCN"

echo ""
echo "### waiting 90s for async post-persist queueables..."
sleep 90

echo ""
echo "### PHASE 2: snapshot AFTER + diff (display-only proof + UnitPrice fills)"
printf "%-5s %-16s %-14s %-9s %s\n" SID QUOTE IGNORE-UNITPRICE UPRICE-FILLED FULL-DIFF
while read sid qid; do
  ./snapshot.sh Quote "$qid" "$OUT/after/$sid.tsv" 2>/dev/null
  IGN=$(python3 diff.py "$OUT/before/$sid.tsv" "$OUT/after/$sid.tsv" --ignore UnitPrice 2>/dev/null | tail -1)
  FULL=$(python3 diff.py "$OUT/before/$sid.tsv" "$OUT/after/$sid.tsv" 2>/dev/null | tail -1)
  # count lines where UnitPrice went blank->value
  FILLED=$(python3 -c "
import csv
def load(p):
    d={}
    try:
        for r in csv.DictReader(open(p),delimiter='\t'):
            k=r.get('LineNumber') or r.get('line'); d[k]=r
    except: pass
    return d
b=load('$OUT/before/$sid.tsv'); a=load('$OUT/after/$sid.tsv')
n=0
for k,av in a.items():
    bv=b.get(k,{})
    bu=(bv.get('UnitPrice') or '').strip(); au=(av.get('UnitPrice') or '').strip()
    if (bu=='' or bu=='0') and au not in ('','0'): n+=1
print(n)
")
  printf "%-5s %-16s %-14s %-9s %s\n" "$sid" "$qid" "${IGN:0:13}" "$FILLED" "${FULL:0:30}"
done <<< "$SCN"

LOG1=$(sf data query -o FortraUAT -q "SELECT count() FROM Exception_Log__c" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
echo ""
echo "### D-18 Exception_Log__c rows AFTER: $LOG1  (delta must be 0)"
echo ""
echo "### IDEMPOTENCY: reprice S3(renewal) S4(derived) again, diff after vs after2"
for pair in "S3 0Q0WC000003IKkv" "S4 0Q0WC0000028bsk"; do
  set -- $pair; sid=$1; qid=$2
  reprice "$qid" >/dev/null
done
sleep 45
for pair in "S3 0Q0WC000003IKkv" "S4 0Q0WC0000028bsk"; do
  set -- $pair; sid=$1; qid=$2
  ./snapshot.sh Quote "$qid" "$OUT/after2/$sid.tsv" 2>/dev/null
  echo "  $sid idempotency: $(python3 diff.py $OUT/after/$sid.tsv $OUT/after2/$sid.tsv 2>/dev/null | tail -1)"
done
echo ""
echo "### SMOKE COMPLETE"
