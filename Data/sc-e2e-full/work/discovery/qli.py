import json,sys,subprocess

def q(soql):
    r=subprocess.run(["sf","data","query","--query",soql,"-o","FortraUAT","--json"],capture_output=True,text=True)
    d=json.loads(r.stdout)
    if 'result' not in d:
        print("ERR", d.get('message'), file=sys.stderr); return []
    return d['result']['records']

def lines(qid):
    soql=("SELECT Product2.ProductCode, Product2.Name, Product2.Family, Fortra_Product_Type__c, "
          "CurrencyIsoCode, Quantity, ListPrice, NetUnitPrice, TotalLineAmount, NetTotalPrice, "
          "PartnerDiscountPercent, Discount, SellingModelType FROM QuoteLineItem "
          "WHERE QuoteId='%s' ORDER BY LineNumber" % qid)
    recs=q(soql)
    for r in recs:
        p=r.get('Product2') or {}
        print("   %-22s %-30s fam=%-14s type=%-20s %s qty=%s list=%s net=%s tla=%s ntp=%s pd%%=%s disc=%s sm=%s" % (
            p.get('ProductCode'), (p.get('Name') or '')[:30], p.get('Family'),
            r.get('Fortra_Product_Type__c'), r.get('CurrencyIsoCode'), r.get('Quantity'),
            r.get('ListPrice'), r.get('NetUnitPrice'), r.get('TotalLineAmount'), r.get('NetTotalPrice'),
            r.get('PartnerDiscountPercent'), r.get('Discount'), r.get('SellingModelType')))

if __name__=='__main__':
    for qid in sys.argv[1:]:
        print("QUOTE", qid)
        lines(qid)
