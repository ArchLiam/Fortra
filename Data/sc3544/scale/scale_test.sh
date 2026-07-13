cd /Users/liamjeong/Documents/Code/Fortra/Data/sc3544/scale
echo "=== reprice all 31 Draft blank-UnitPrice quotes via flow v28 ==="
QIDS=$(tail -n +2 before_blanks.csv | cut -d, -f1 | sort -u)
n=0
for q in $QIDS; do
  r=$(sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body "{\"inputs\":[{\"QuoteId\":\"$q\"}]}" -o FortraUAT 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)[0].get('isSuccess'))" 2>/dev/null)
  n=$((n+1)); echo "  [$n] $q -> $r"
done
echo "=== waiting 120s for async stamps ==="
sleep 120
echo "=== capture AFTER + verify each blank filled to expected COALESCE(Base>0,Pre>0,Net) ==="
IDS=$(tail -n +2 before_blanks.csv | cut -d, -f2 | paste -sd, - | sed "s/[^,A-Za-z0-9]//g")
# query after UnitPrice for the same line Ids
python3 - <<'PY'
import csv, subprocess, json
before={}
with open('before_blanks.csv') as f:
    for r in csv.DictReader(f):
        before[r['Id']]=r
ids="','".join(before.keys())
q=f"SELECT Id, UnitPrice, NetUnitPrice, Base_Price__c, Pre_Partner_Price__c FROM QuoteLineItem WHERE Id IN ('{ids}')"
out=subprocess.run(['sf','data','query','-o','FortraUAT','-q',q,'--result-format','csv'],capture_output=True,text=True).stdout
after={}
rdr=csv.DictReader([l for l in out.splitlines() if ',' in l and not l.startswith('Warning')])
for r in rdr: after[r['Id']]=r
def dec(x):
    try: return round(float(x),2)
    except: return None
def expected(b):
    base=dec(b['Base_Price__c']); pre=dec(b['Pre_Partner_Price__c']); net=dec(b['NetUnitPrice'])
    if base is not None and base>0: return base
    if pre is not None and pre>0: return pre
    return net
passes=fails=stillnull=0; fail_ex=[]
for lid,b in before.items():
    a=after.get(lid)
    if not a: continue
    au=dec(a['UnitPrice']); exp=expected(a)  # use after's Base/Pre/Net (post-reprice truth)
    if au is None: stillnull+=1; fail_ex.append((lid,'STILL NULL',exp)); continue
    if au==exp: passes+=1
    else: fails+=1; fail_ex.append((lid,au,exp))
print(f"lines checked: {len(before)}")
print(f"PASS (UnitPrice == expected COALESCE): {passes}")
print(f"FAIL (mismatch): {fails}")
print(f"STILL NULL (not filled): {stillnull}")
for ex in fail_ex[:12]: print("   mismatch:", ex)
PY
