import subprocess, json, sys
FPB='01sWC0000022GHFYA2'
def soql(q):
    r=subprocess.run(['sf','data','query','-o','FortraUAT','-q',q,'--json'],capture_output=True,text=True)
    if r.returncode!=0: sys.stderr.write(r.stdout+r.stderr); raise SystemExit('fail')
    return json.loads(r.stdout)['result']['records']
def chunks(l,n):
    for i in range(0,len(l),n): yield l[i:i+n]

print('=== J-10 evidence ===')
for rid,lbl in [('01uWC000005wzX8YAI','EUR PBE (BoKS NewMaint)'),('01uWC000005wsbUYAQ','USD twin')]:
    r=soql(f"SELECT Id,Pricebook2.Name,Product2Id,Product2.Name,IsDerived,IsActive,CurrencyIsoCode,UnitPrice FROM PricebookEntry WHERE Id='{rid}'")
    x=r[0]; print(f"  {lbl}: {rid} | {x['Product2']['Name']} | derived={x['IsDerived']} active={x['IsActive']} cur={x['CurrencyIsoCode']} book={x['Pricebook2']['Name']} price={x['UnitPrice']}")
q=soql("SELECT Id,Product2.Name,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalPrice,PricebookEntryId,COLACalculatedPrice__c,Source_List_Price__c,CurrencyIsoCode FROM QuoteLineItem WHERE Id='0QLWC000003kinW4AQ'")
x=q[0]; print(f"  EUR QLI 0QLWC000003kinW4AQ: {x['Product2']['Name']} qty={x['Quantity']} UnitPrice={x['UnitPrice']} Net={x['NetUnitPrice']} List={x['ListPrice']} Total={x['TotalPrice']} COLA={x['COLACalculatedPrice__c']} SLP={x['Source_List_Price__c']} cur={x['CurrencyIsoCode']} pbe={x['PricebookEntryId']}")

print('\n=== J-10 scope (active Fortra Price Book) ===')
# Pass 1: distinct Product2Ids with USD IsDerived active PBE in FPB
p1=soql(f"SELECT Product2Id FROM PricebookEntry WHERE IsDerived=true AND CurrencyIsoCode='USD' AND IsActive=true AND Pricebook2Id='{FPB}'")
usd_prods=sorted(set(r['Product2Id'] for r in p1))
print('  USD IsDerived active PBEs in FPB:',len(p1),'| distinct products:',len(usd_prods))
# also org-wide (any book) for context
p1all=soql("SELECT COUNT(Id) c FROM PricebookEntry WHERE IsDerived=true AND CurrencyIsoCode='USD'")
print('  (org-wide USD IsDerived PBEs any book:',p1all[0]['c'],')')
pNonUsdDerived=soql("SELECT COUNT(Id) c FROM PricebookEntry WHERE IsDerived=true AND CurrencyIsoCode!='USD'")
print('  (org-wide non-USD IsDerived PBEs any book:',pNonUsdDerived[0]['c'],')')

# Pass 2: non-USD active PBEs in FPB for those products, IsDerived=false -> flip set
flip=[]
for ch in chunks(usd_prods,200):
    inlist="','".join(ch)
    recs=soql(f"SELECT Id,Product2Id,Product2.Name,CurrencyIsoCode,IsDerived,IsActive FROM PricebookEntry WHERE Product2Id IN ('{inlist}') AND CurrencyIsoCode!='USD' AND IsActive=true AND Pricebook2Id='{FPB}'")
    flip.extend(recs)
flip_to_set=[r for r in flip if not r['IsDerived']]
already=[r for r in flip if r['IsDerived']]
from collections import Counter
print(f"\n  non-USD active FPB PBEs for USD-derived products: {len(flip)}")
print(f"    -> need flip (IsDerived=false): {len(flip_to_set)}")
print(f"    -> already IsDerived=true: {len(already)}")
print('  currency breakdown of flip set:')
for k,v in Counter(r['CurrencyIsoCode'] for r in flip_to_set).most_common(): print(f'      {v:5d}  {k}')
ev_in = '01uWC000005wzX8YAI' in [r['Id'] for r in flip_to_set]
print('  evidence EUR PBE 01uWC000005wzX8YAI in flip set:', ev_in)
json.dump({'flip_ids':[r['Id'] for r in flip_to_set],'flip_detail':flip_to_set,'usd_prod_count':len(usd_prods)},
          open('Data/pricing-v21-validation/portion3/j10_flip.json','w'))
print('\n  wrote j10_flip.json (',len(flip_to_set),'ids )')
