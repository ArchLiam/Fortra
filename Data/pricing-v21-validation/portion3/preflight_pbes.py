import csv, subprocess, json, sys

IDS = [l.strip() for l in open('Data/pricing-v21-validation/portion3/csv_pbe_ids.txt') if l.strip()]
def chunks(l,n):
    for i in range(0,len(l),n): yield l[i:i+n]

def soql(q):
    r = subprocess.run(['sf','data','query','-o','FortraUAT','-q',q,'--json'],
                       capture_output=True,text=True)
    if r.returncode!=0:
        sys.stderr.write(r.stdout+r.stderr); raise SystemExit('query failed')
    return json.loads(r.stdout)['result']['records']

# 1) PBE attributes
pbe={}
for ch in chunks(IDS,120):
    inlist="','".join(ch)
    recs=soql(f"SELECT Id,Pricebook2Id,Pricebook2.Name,Pricebook2.IsActive,Product2Id,Product2.Name,IsDerived,IsActive,CurrencyIsoCode,UnitPrice FROM PricebookEntry WHERE Id IN ('{inlist}')")
    for x in recs:
        pbe[x['Id']]={
          'pbookId':x['Pricebook2Id'],
          'pbook':(x['Pricebook2'] or {}).get('Name'),
          'pbookActive':(x['Pricebook2'] or {}).get('IsActive'),
          'prodId':x['Product2Id'],
          'prod':(x['Product2'] or {}).get('Name'),
          'isDerived':x['IsDerived'],'isActive':x['IsActive'],
          'cur':x['CurrencyIsoCode'],'unitPrice':x['UnitPrice']}

# 2) existing PBEDP coverage for these PBEs
covered={}
for ch in chunks(IDS,120):
    inlist="','".join(ch)
    recs=soql(f"SELECT PricebookEntryId, COUNT(Id) c FROM PriceBookEntryDerivedPrice WHERE PricebookEntryId IN ('{inlist}') GROUP BY PricebookEntryId")
    for x in recs: covered[x['PricebookEntryId']]=x['c']

missing=[i for i in IDS if i not in pbe]
print('CSV PBE ids:',len(IDS))
print('found live:',len(pbe),' | MISSING (deleted?):',len(missing))
if missing: print('  missing sample:',missing[:5])

from collections import Counter
print('\n--- live pricebook of CSV PBEs ---')
for k,v in Counter((pbe[i]['pbook'],pbe[i]['pbookActive']) for i in pbe).most_common():
    print(f'  {v:5d}  {k}')
print('\n--- live IsDerived ---')
for k,v in Counter(pbe[i]['isDerived'] for i in pbe).most_common(): print(f'  {v:5d}  isDerived={k}')
print('--- live IsActive (PBE) ---')
for k,v in Counter(pbe[i]['isActive'] for i in pbe).most_common(): print(f'  {v:5d}  isActive={k}')
print('--- live currency ---')
for k,v in Counter(pbe[i]['cur'] for i in pbe).most_common(): print(f'  {v:5d}  {k}')
print('\n--- coverage NOW (already has PBEDP rows) ---')
already=[i for i in pbe if i in covered]
print('  already-covered:',len(already),' | still 0-PBEDP:',len(pbe)-len(already))

# The TRUE insertable set: in ACTIVE Fortra Price Book, IsDerived, IsActive PBE, uncovered
FPB='01sWC0000022GHFYA2'
insertable=[i for i in pbe if pbe[i]['pbookId']==FPB and pbe[i]['isDerived'] and pbe[i]['isActive'] and i not in covered]
print('\n=== TRUE insertable (active Fortra Price Book 01sWC0000022GHFYA2 + IsDerived + IsActive + uncovered):',len(insertable),'===')
notFPB=[i for i in pbe if pbe[i]['pbookId']!=FPB]
print('  in a DIFFERENT pricebook (skip):',len(notFPB))
notDerived=[i for i in pbe if pbe[i]['pbookId']==FPB and not pbe[i]['isDerived']]
print('  in FPB but NOT IsDerived now (skip):',len(notDerived))
inactivePbe=[i for i in pbe if pbe[i]['pbookId']==FPB and pbe[i]['isDerived'] and not pbe[i]['isActive']]
print('  in FPB, derived, but PBE inactive (skip):',len(inactivePbe))
nowcov=[i for i in pbe if pbe[i]['pbookId']==FPB and pbe[i]['isDerived'] and pbe[i]['isActive'] and i in covered]
print('  in FPB, derived, active, but NOW already covered (skip):',len(nowcov))

json.dump({'pbe':pbe,'covered':covered,'insertable':insertable,'missing':missing},
          open('Data/pricing-v21-validation/portion3/preflight_pbes.json','w'),indent=0)
print('\nwrote preflight_pbes.json')
