import subprocess, json
def q(soql):
    out=subprocess.run(['sf','data','query','--target-org','FortraUAT','--json','--query',soql],capture_output=True,text=True).stdout
    return json.loads(out).get('result',{}).get('records',[])
working=['0Q0WC000003Cvgj0AC','0Q0WC000003CvaH0AS','0Q0WC000003A80z0AC']
broken =['0Q0WC000003FNXF0A4','0Q0WC000003F55h0AC','0Q0WC000003F3yL0AS','0Q0WC000003F3n30AC','0Q0WC000003F3bl0AC','0Q0WC000003EzEn0AK','0Q0WC000003Ey2b0AC','0Q0WC000003Eb9F0AS','0Q0WC000003A3PV0A0','0Q0WC0000039fYT0AY']
allq=working+broken
inq=','.join("'%s'"%x for x in allq)
qlis=q("SELECT Id, QuoteId, Product2.Name, NetUnitPrice, ListPrice, Quote.CreatedDate FROM QuoteLineItem WHERE QuoteId IN (%s)"%inq)
qli_ids=[r['Id'] for r in qlis]
attrs={}
for s in range(0,len(qli_ids),60):
    ch=qli_ids[s:s+60]; inl=','.join("'%s'"%x for x in ch)
    for a in q("SELECT QuoteLineItemId, AttributeName, IsPriceImpacting FROM QuoteLineItemAttribute WHERE QuoteLineItemId IN (%s)"%inl):
        attrs.setdefault(a['QuoteLineItemId'],[]).append((a['AttributeName'],a['IsPriceImpacting']))
def label(qid): return 'WORK' if qid in working else 'BROK'
print("%-5s %-11s %-26s %9s %9s %3s %s"%('Q','Created','Product','List','NetUnit','PI','attrs'))
for r in sorted(qlis,key=lambda r:(label(r['QuoteId']),(r.get('Quote') or {}).get('CreatedDate',''))):
    p=r.get('Product2') or {}; a=attrs.get(r['Id'],[])
    pi=sum(1 for n,imp in a if imp)
    created=(r.get('Quote') or {}).get('CreatedDate','')[:10]
    anames=','.join(n for n,imp in a if imp)[:42]
    print("%-5s %-11s %-26s %9s %9s %3d %s"%(label(r['QuoteId']),created,(p.get('Name') or '')[:26],str(r.get('ListPrice')),str(r.get('NetUnitPrice')),pi,anames))
