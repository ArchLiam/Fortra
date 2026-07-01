import xml.etree.ElementTree as ET, copy, sys
NSURI='http://soap.sforce.com/2006/04/metadata'
NS='{'+NSURI+'}'
ET.register_namespace('', NSURI)
def t(el,tag):
    c=el.find(NS+tag); return c if c is not None else None
def tx(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
def find_step(root,name):
    for st in root.findall(NS+'steps'):
        if tx(st,'name')==name: return st
    return None

R='retrieve/unpackaged/unpackaged/expressionSetVersion/'
V16f=R+'Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V160.expressionSetVersion'
V20f=R+'Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V200.expressionSetVersion'
v16=ET.parse(V16f).getroot()
tree=ET.parse(V20f); root=tree.getroot()   # base = V20

log=[]

# ---- PATCH 1: DerivedPricingFormula -> restore V16 7-tier formula value ----
src=find_step(v16,'DerivedPricingFormula'); dst=find_step(root,'DerivedPricingFormula')
def get_param(step,pname):
    for p in step.find(NS+'customElement').findall(NS+'parameters'):
        if tx(p,'name')==pname: return p
    return None
v16formula=get_param(src,'formula-section-0-input').find(NS+'value').text
dstp=get_param(dst,'formula-section-0-input')
old=dstp.find(NS+'value').text
dstp.find(NS+'value').text=v16formula
log.append(f"PATCH1 DerivedPricingFormula formula-section-0-input: replaced ({len(old)} chars -> {len(v16formula)} chars; 3-tier -> 7-tier)")

# ---- PATCH 2 & 3: aggregate guards -> copy V16 customElement wholesale ----
for nm in ('SoftwareAggregatePrice','SubscriptionAggregatePrice'):
    s16=find_step(v16,nm); s20=find_step(root,nm)
    ce16=copy.deepcopy(s16.find(NS+'customElement'))
    old_ce=s20.find(NS+'customElement')
    idx=list(s20).index(old_ce)
    s20.remove(old_ce); s20.insert(idx,ce16)
    log.append(f"PATCH {nm}: replaced customElement with V16's (adds where-condition-count=1 + ItemNetTotalPrice isNotNull guard)")

# ---- PATCH 4: add Term-Defined proration sub-tree (3 steps deep-copied from V16) ----
addnames=['TermDefinedProrationFilterLinelevel','ListOperationTermDefinedPTC','ProrationTermDefined']
# sanity: none must already exist in V20
for nm in addnames:
    assert find_step(root,nm) is None, f"{nm} already in V20!"
# find insertion point: after the last <steps> child
steps_children=[c for c in list(root) if c.tag==NS+'steps']
last_step=steps_children[-1]
insert_idx=list(root).index(last_step)+1
for off,nm in enumerate(addnames):
    st=copy.deepcopy(find_step(v16,nm))
    assert st is not None, f"{nm} not found in V16!"
    root.insert(insert_idx+off, st)
log.append(f"PATCH4: inserted Term-Defined proration sub-tree (3 steps: {', '.join(addnames)})")

# ---- HEADER: bump to V21 draft, status Inactive ----
def set_text(tag,val):
    e=root.find(NS+tag)
    if e is not None: e.text=val
set_text('label','Rev Mgmt Default Pricing V21')
set_text('description','Revenue Management Default Pricing Procedure V21 - V20 currency conversion + restored V16 logic (Term-Defined proration, 7-tier derived formula, aggregate null-guards). DRAFT for UAT.')
set_text('status','Inactive')
set_text('versionNumber','21')
log.append("HEADER: label=V21, status=Inactive, versionNumber=21, description updated")

# write
out='build/expressionSetDefinitionVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V210.expressionSetDefinitionVersion'
ET.indent(tree, space='    ')
tree.write(out, xml_declaration=True, encoding='UTF-8')
print('\n'.join(log))
print("\nWROTE:",out)
# verify counts
chk=ET.parse(out).getroot()
print("Result step count:", len(chk.findall(NS+'steps')), "(expected 119+3=122)")
