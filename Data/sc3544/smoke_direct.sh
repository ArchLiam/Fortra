#!/bin/bash
# SC-3544 smoke — invoke the post-persist stamp directly on every real scenario.
# stampAttributeListPricesForQuote does the SAME QLI query+update the async queueable does,
# so this faithfully tests the fix's EFFECT across all scenarios (the nudge test separately
# proves it RUNS on a real reprice). Asserts: UnitPrice fills on blank lines; every OTHER
# oracle column 0-delta (--ignore UnitPrice); idempotent on 2nd call; D-18 log clean.
cd /Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/harness
export ORG=FortraUAT
OUT=post_sc3544_direct
mkdir -p $OUT/before $OUT/after $OUT/after2

SCN=$(python3 -c "
import csv
seen=set()
for r in csv.DictReader(open('scenarios.tsv'),delimiter='\t'):
    q=r['quote_id'].strip()
    if q and q!='NEEDS-DATA' and q not in seen:
        seen.add(q); print(r['id'], q)
")

LOG0=$(sf data query -o FortraUAT -q "SELECT count() FROM Exception_Log__c" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
echo "### D-18 Exception_Log__c BEFORE: $LOG0"

echo "### snapshot BEFORE"
while read sid qid; do ./snapshot.sh Quote "$qid" "$OUT/before/$sid.tsv" 2>/dev/null; done <<< "$SCN"

echo "### invoke stampAttributeListPricesForQuote on each (one Apex run)"
{
  echo 'Map<String,Integer> res = new Map<String,Integer>();'
  while read sid qid; do echo "res.put('$sid', PartnerNetPricePosthook.stampAttributeListPricesForQuote('$qid'));"; done <<< "$SCN"
  echo "for(String k:res.keySet()) System.debug('STAMP '+k+' rows='+res.get(k));"
} > /tmp/sc3544_stamp_all.apex
sf apex run -o FortraUAT -f /tmp/sc3544_stamp_all.apex 2>&1 | grep "STAMP "

echo ""
echo "### snapshot AFTER + diff"
printf "%-5s %-16s %-16s %-9s %s\n" SID QUOTE IGNORE-UNITPRICE FILLED FULLDIFF
while read sid qid; do
  ./snapshot.sh Quote "$qid" "$OUT/after/$sid.tsv" 2>/dev/null
  IGN=$(python3 diff.py "$OUT/before/$sid.tsv" "$OUT/after/$sid.tsv" --ignore UnitPrice 2>/dev/null | tail -1)
  FULL=$(python3 diff.py "$OUT/before/$sid.tsv" "$OUT/after/$sid.tsv" 2>/dev/null | tail -1)
  FILLED=$(python3 -c "
import csv
def load(p):
    d={}
    try:
        for r in csv.DictReader(open(p),delimiter='\t'): d[r.get('LineNumber','')]=r
    except: pass
    return d
b=load('$OUT/before/$sid.tsv'); a=load('$OUT/after/$sid.tsv'); n=0
for k,av in a.items():
    bu=(b.get(k,{}).get('UnitPrice') or '').strip(); au=(av.get('UnitPrice') or '').strip()
    if bu in ('','0') and au not in ('','0'): n+=1
print(n)")
  printf "%-5s %-16s %-16s %-9s %s\n" "$sid" "$qid" "${IGN:0:15}" "$FILLED" "${FULL:0:28}"
done <<< "$SCN"

echo ""
echo "### idempotency: 2nd stamp call must return rows=0 on all"
{
  while read sid qid; do echo "System.debug('IDEM $sid rows='+PartnerNetPricePosthook.stampAttributeListPricesForQuote('$qid'));"; done <<< "$SCN"
} > /tmp/sc3544_stamp_idem.apex
sf apex run -o FortraUAT -f /tmp/sc3544_stamp_idem.apex 2>&1 | grep "IDEM "

LOG1=$(sf data query -o FortraUAT -q "SELECT count() FROM Exception_Log__c" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
echo ""
echo "### D-18 Exception_Log__c AFTER: $LOG1  (delta must be 0)"
echo "### SMOKE COMPLETE"
