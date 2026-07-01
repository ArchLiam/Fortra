import sys
import xml.etree.ElementTree as ET
NS='{http://soap.sforce.com/2006/04/metadata}'
def t(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
def steps(p):
    r=ET.parse(p).getroot()
    return [{'name':t(s,'name'),'label':t(s,'label'),'seq':t(s,'sequenceNumber'),
             'parent':t(s,'parentStep'),'at':t(s,'actionType'),'stype':t(s,'stepType')} for s in r.findall(NS+'steps')]
lbl=sys.argv[2]
ss=steps(sys.argv[1])
byname={s['name']:s for s in ss}
# find steps whose label or parent-chain mentions proration/term
print(f"--- {sys.argv[3]} : proration/term-related steps ---")
for s in ss:
    hay=(s['label'] or '')+' '+(s['at'] or '')+' '+(s['stype'] or '')
    if any(k in hay.lower() for k in ['proration','term','list operation','listgroup']):
        pl = byname.get(s['parent'],{}).get('label') if s['parent'] else None
        print(f"  seq={s['seq']:>3} label={s['label']!r:55} at={s['at']} stype={s['stype']} parent={pl!r}")
