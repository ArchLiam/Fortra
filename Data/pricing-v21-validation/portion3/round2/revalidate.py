#!/usr/bin/env python3
"""J-09 round-2 LIVE re-validation (read-only).
Re-measures all 476 HICONF PBEs against current FortraUAT, recomputes the
actionable subset, validates contributor pricing, and diffs vs round-1's 253.
"""
import csv, subprocess, json, sys, os
from collections import Counter, defaultdict

BASE='Data/pricing-v21-validation/portion3'
R2=f'{BASE}/round2'
FPB='01sWC0000022GHFYA2'   # active Fortra Price Book

def chunks(l,n):
    for i in range(0,len(l),n): yield l[i:i+n]

def soql(q):
    r=subprocess.run(['sf','data','query','-o','FortraUAT','-q',q,'--json'],
                     capture_output=True,text=True)
    if r.returncode!=0:
        sys.stderr.write(r.stdout+r.stderr); raise SystemExit('query failed: '+q[:200])
    return json.loads(r.stdout)['result']['records']

# ---- inputs
hic=list(csv.DictReader(open('Data/sc-maint/sc3346_fix/m5_pbedp/backfill_HICONF.csv')))
csvmap={r['PricebookEntryId']:r for r in hic}          # PBE -> full HICONF row (maint/contrib names)
PBE_IDS=sorted(csvmap)
CONTRIB_IDS=sorted({r['ContributingProductId'] for r in hic})
IMP253=set(l.strip() for l in open(f'{R2}/import253_pbe.txt') if l.strip())
print(f'inputs: {len(PBE_IDS)} PBEs, {len(CONTRIB_IDS)} contributors, {len(IMP253)} staged-253')

# ---- 1) live PBE attributes
pbe={}
for ch in chunks(PBE_IDS,120):
    inl="','".join(ch)
    for x in soql(f"SELECT Id,Pricebook2Id,Pricebook2.Name,Pricebook2.IsActive,Product2Id,Product2.Name,IsDerived,IsActive,CurrencyIsoCode,UnitPrice FROM PricebookEntry WHERE Id IN ('{inl}')"):
        pbe[x['Id']]={'pbookId':x['Pricebook2Id'],'pbook':(x['Pricebook2']or{}).get('Name'),
          'pbookActive':(x['Pricebook2']or{}).get('IsActive'),'prodId':x['Product2Id'],
          'prod':(x['Product2']or{}).get('Name'),'isDerived':x['IsDerived'],'isActive':x['IsActive'],
          'cur':x['CurrencyIsoCode'],'unitPrice':x['UnitPrice']}
missing=[i for i in PBE_IDS if i not in pbe]

# ---- 2) live PBEDP coverage NOW for these PBEs
covered={}
for ch in chunks(PBE_IDS,120):
    inl="','".join(ch)
    for x in soql(f"SELECT PricebookEntryId, COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE PricebookEntryId IN ('{inl}') GROUP BY PricebookEntryId"):
        covered[x['PricebookEntryId']]=x['c']

# ---- 3) contributor pricing: does each contributor have an ACTIVE priced USD PBE in the active FPB?
contrib_priced={}   # prodId -> best UnitPrice in active FPB USD (or None)
contrib_any={}      # prodId -> has ANY active priced PBE anywhere
for ch in chunks(CONTRIB_IDS,120):
    inl="','".join(ch)
    for x in soql(f"SELECT Product2Id,Pricebook2Id,IsActive,CurrencyIsoCode,UnitPrice FROM PricebookEntry WHERE Product2Id IN ('{inl}') AND IsActive=true"):
        p=x['Product2Id']; up=x['UnitPrice'] or 0
        if x['CurrencyIsoCode']=='USD' and up>0:
            contrib_any[p]=True
        if x['Pricebook2Id']==FPB and x['CurrencyIsoCode']=='USD':
            prev=contrib_priced.get(p)
            if prev is None or up>prev: contrib_priced[p]=up

# ---- categorize each of the 476
cat=defaultdict(list)
for i in PBE_IDS:
    row=csvmap[i]; contrib=row['ContributingProductId']
    if i not in pbe: cat['missing_pbe'].append(i); continue
    p=pbe[i]
    if p['pbookId']!=FPB: cat['wrong_pricebook'].append(i); continue
    if not p['isDerived']: cat['not_derived'].append(i); continue
    if not p['isActive']: cat['pbe_inactive'].append(i); continue
    if i in covered: cat['now_covered'].append(i); continue
    cp=contrib_priced.get(contrib)
    if cp is None or cp<=0: cat['contrib_unpriced'].append(i); continue
    cat['actionable'].append(i)

actionable=set(cat['actionable'])
print('\n=== LIVE categorization of 476 HICONF PBEs ===')
for k in ['actionable','wrong_pricebook','not_derived','pbe_inactive','now_covered','contrib_unpriced','missing_pbe']:
    print(f'  {len(cat[k]):5d}  {k}')

# ---- drift vs round-1 staged 253
newly_blocked=sorted(IMP253-actionable)     # were staged, now NOT actionable
newly_action=sorted(actionable-IMP253)      # now actionable, were NOT in 253
stable=sorted(IMP253 & actionable)
print(f'\n=== DRIFT vs round-1 staged 253 ===')
print(f'  stable (still actionable): {len(stable)}')
print(f'  newly BLOCKED (in 253, now not actionable): {len(newly_blocked)}')
print(f'  newly actionable (not in 253): {len(newly_action)}')
def why(i):
    if i not in pbe: return 'missing_pbe'
    p=pbe[i]
    if p['pbookId']!=FPB: return f"wrong_pricebook={p['pbook']}"
    if not p['isDerived']: return 'not_derived'
    if not p['isActive']: return 'pbe_inactive'
    if i in covered: return f'now_covered({covered[i]})'
    cp=contrib_priced.get(csvmap[i]['ContributingProductId'])
    if cp is None or cp<=0: return 'contrib_unpriced'
    return 'actionable'
for i in newly_blocked[:40]:
    print(f'    {i}  {csvmap[i]["maint_name"][:40]:40s} -> {why(i)}')

# ---- write outputs
def wrows(path, ids):
    with open(path,'w',newline='') as f:
        w=csv.writer(f); w.writerow(['PricebookEntryId','ContributingProductId','maint_name','contrib_name','contrib_code','csv_pb','csv_cur','live_pbook','live_isDerived','live_isActive','live_cur','live_unitPrice','pbedp_now','contrib_fpb_usd_price','category'])
        for i in ids:
            row=csvmap[i]; p=pbe.get(i,{})
            w.writerow([i,row['ContributingProductId'],row['maint_name'],row['contrib_name'],row['contrib_code'],row['pb'],row['cur'],
                        p.get('pbook'),p.get('isDerived'),p.get('isActive'),p.get('cur'),p.get('unitPrice'),
                        covered.get(i,0),contrib_priced.get(row['ContributingProductId']),why(i)])

wrows(f'{R2}/live_actionable.csv', sorted(actionable))
blocked=[i for i in PBE_IDS if i not in actionable]
wrows(f'{R2}/live_blocked_for_marc.csv', blocked)
json.dump({'pbe':pbe,'covered':covered,'contrib_priced':contrib_priced,
           'actionable':sorted(actionable),'blocked':blocked,
           'newly_blocked':newly_blocked,'newly_action':newly_action,'missing':missing,
           'cat_counts':{k:len(v) for k,v in cat.items()}},
          open(f'{R2}/revalidate.json','w'),indent=0)
print(f'\nwrote {R2}/live_actionable.csv ({len(actionable)}), live_blocked_for_marc.csv ({len(blocked)}), revalidate.json')
