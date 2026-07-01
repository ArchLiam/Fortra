import xml.etree.ElementTree as ET, sys, json, re

NS = '{http://soap.sforce.com/2006/04/metadata}'
def strip(t): return t.replace(NS,'')

def text(el, tag):
    c = el.find(NS+tag)
    return c.text if c is not None and c.text is not None else None

def parse(path):
    tree = ET.parse(path)
    root = tree.getroot()
    steps = []
    for st in root.findall(NS+'steps'):
        d = {
            'name': text(st,'name'),
            'label': text(st,'label'),
            'seq': text(st,'sequenceNumber'),
            'stepType': text(st,'stepType'),
            'actionType': text(st,'actionType'),
            'parentStep': text(st,'parentStep'),
            'conditionLogic': text(st,'conditionLogic'),
        }
        # capture parameters (name->value) inside customElement
        params = {}
        ce = st.find(NS+'customElement')
        if ce is not None:
            for p in ce.findall(NS+'parameters'):
                pn = text(p,'name'); pv = text(p,'value'); pin = text(p,'input'); pout=text(p,'output')
                params[pn] = {'value':pv,'input':pin,'output':pout,'type':text(p,'type')}
        d['params'] = params
        # advanced conditions / criteria
        crits = []
        for c in st.findall(NS+'criteria'):
            crits.append({'field':text(c,'sourceFieldName'),'op':text(c,'operator'),'val':text(c,'value')})
        d['criteria'] = crits
        steps.append(d)
    return steps

def main():
    v16 = parse(sys.argv[1])
    v20 = parse(sys.argv[2])
    print(f"V16 steps: {len(v16)}   V20 steps: {len(v20)}")
    by_label16 = {}
    for s in v16: by_label16.setdefault(s['label'], []).append(s)
    by_label20 = {}
    for s in v20: by_label20.setdefault(s['label'], []).append(s)
    labels16 = set(by_label16); labels20 = set(by_label20)
    print("\n=== Steps ONLY in V16 (missing from V20) ===")
    for l in sorted(labels16 - labels20):
        for s in by_label16[l]:
            print(f"  [seq {s['seq']}] {l}  ({s['actionType']})")
    print("\n=== Steps ONLY in V20 (Nir's additions) ===")
    for l in sorted(labels20 - labels16):
        for s in by_label20[l]:
            print(f"  [seq {s['seq']}] {l}  ({s['actionType']})")
    print("\n=== Labels in BOTH (count differs?) ===")
    for l in sorted(labels16 & labels20):
        if len(by_label16[l]) != len(by_label20[l]):
            print(f"  {l}: V16x{len(by_label16[l])} V20x{len(by_label20[l])}")

main()
