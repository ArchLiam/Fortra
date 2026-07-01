import xml.etree.ElementTree as ET, sys, json
NS='{http://soap.sforce.com/2006/04/metadata}'
def t(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
def parse(p):
    r=ET.parse(p).getroot(); out=[]
    for st in r.findall(NS+'steps'):
        params={}
        ce=st.find(NS+'customElement')
        if ce is not None:
            for pr in ce.findall(NS+'parameters'):
                params[t(pr,'name')]={'v':t(pr,'value'),'in':t(pr,'input'),'out':t(pr,'output'),'ty':t(pr,'type')}
        crit=[(t(c,'sourceFieldName'),t(c,'operator'),t(c,'value')) for c in st.findall(NS+'criteria')]
        out.append({'name':t(st,'name'),'label':t(st,'label'),'seq':t(st,'sequenceNumber'),
                    'stepType':t(st,'stepType'),'actionType':t(st,'actionType'),
                    'parent':t(st,'parentStep'),'cond':t(st,'conditionLogic'),
                    'params':params,'crit':crit})
    return out

a=parse(sys.argv[1]); b=parse(sys.argv[2])
# align by (label, occurrence)
from collections import defaultdict
def keyed(lst):
    seen=defaultdict(int); d={}
    for s in lst:
        k=(s['label'],seen[s['label']]); seen[s['label']]+=1; d[k]=s
    return d
ka=keyed(a); kb=keyed(b)
allk=sorted(set(ka)|set(kb), key=lambda x:(x[0] or '',x[1]))
only_a=[]; only_b=[]; changed=[]
for k in allk:
    sa=ka.get(k); sb=kb.get(k)
    if sa and not sb: only_a.append(sa); continue
    if sb and not sa: only_b.append(sb); continue
    # compare params
    pa=sa['params']; pb=sb['params']
    addp=sorted(set(pb)-set(pa)); remp=sorted(set(pa)-set(pb))
    chg=[]
    for pn in sorted(set(pa)&set(pb)):
        if pa[pn]['v']!=pb[pn]['v']:
            chg.append((pn,pa[pn]['v'],pb[pn]['v']))
    meta=[]
    for f in ('actionType','stepType','cond'):
        if sa[f]!=sb[f]: meta.append((f,sa[f],sb[f]))
    if sa['crit']!=sb['crit']: meta.append(('criteria',sa['crit'],sb['crit']))
    if addp or remp or chg or meta:
        changed.append((k,sa,sb,addp,remp,chg,meta))

print("="*70)
print("STEPS ONLY IN V16 (must consider porting to V20):")
for s in only_a: print(f"  [{s['seq']}] {s['label']}  type={s['actionType']}/{s['stepType']}")
print("\nSTEPS ONLY IN V20 (Nir currency additions):")
for s in only_b: print(f"  [{s['seq']}] {s['label']}  type={s['actionType']}/{s['stepType']}")
print("\n"+"="*70)
print(f"MATCHED-BUT-CHANGED STEPS: {len(changed)}")
for k,sa,sb,addp,remp,chg,meta in changed:
    print(f"\n--- '{k[0]}' (occ {k[1]})  V16 seq={sa['seq']} / V20 seq={sb['seq']}  name16={sa['name']} name20={sb['name']}")
    for m in meta: print(f"     META {m[0]}: V16={m[1]!r} -> V20={m[2]!r}")
    for pn in addp: print(f"     +param(V20 only) {pn} = {sb['params'][pn]['v']!r}")
    for pn in remp: print(f"     -param(V16 only) {pn} = {sa['params'][pn]['v']!r}")
    for pn,va,vb in chg: print(f"     ~param {pn}: V16={va!r} -> V20={vb!r}")
