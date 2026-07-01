import xml.etree.ElementTree as ET, copy
NSURI='http://soap.sforce.com/2006/04/metadata'; NS='{'+NSURI+'}'
ET.register_namespace('', NSURI)
def tx(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
def find_step(root,name):
    for st in root.findall(NS+'steps'):
        if tx(st,'name')==name: return st
    return None
def get_param(step,pname):
    for p in step.find(NS+'customElement').findall(NS+'parameters'):
        if tx(p,'name')==pname: return p

R='retrieve/unpackaged/unpackaged/expressionSetVersion/'
V16f=R+'Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V160.expressionSetVersion'
# base = FRESH V20 from refresh/
import glob
V20f=glob.glob('refresh/**/*V200*.expressionSetVersion',recursive=True)[0]
v16=ET.parse(V16f).getroot()
tree=ET.parse(V20f); root=tree.getroot()
log=[]

# capture pre-change header for proof
pre_status=tx(root,'status'); pre_ver=tx(root,'versionNumber'); pre_label=tx(root,'label')

# PATCH 1: DerivedPricingFormula -> V16 7-tier
v16formula=get_param(find_step(v16,'DerivedPricingFormula'),'formula-section-0-input').find(NS+'value').text
get_param(find_step(root,'DerivedPricingFormula'),'formula-section-0-input').find(NS+'value').text=v16formula
log.append("PATCH1 DerivedPricingFormula -> 7-tier (V16)")

# PATCH 2&3: aggregate guards -> copy V16 customElement
for nm in ('SoftwareAggregatePrice','SubscriptionAggregatePrice'):
    s20=find_step(root,nm); ce16=copy.deepcopy(find_step(v16,nm).find(NS+'customElement'))
    i=list(s20).index(s20.find(NS+'customElement')); s20.remove(s20.find(NS+'customElement')); s20.insert(i,ce16)
    log.append(f"PATCH {nm} -> ItemNetTotalPrice isNotNull guard restored")

# PATCH 4: add Term-Defined proration sub-tree
addnames=['TermDefinedProrationFilterLinelevel','ListOperationTermDefinedPTC','ProrationTermDefined']
for nm in addnames: assert find_step(root,nm) is None
steps_children=[c for c in list(root) if c.tag==NS+'steps']
ins=list(root).index(steps_children[-1])+1
for off,nm in enumerate(addnames):
    root.insert(ins+off, copy.deepcopy(find_step(v16,nm)))
log.append(f"PATCH4 Term-Defined proration sub-tree (+3 steps)")

# HEADER: keep V20 identity; only set status=Inactive (matches deactivated deploy window)
root.find(NS+'status').text='Inactive'
log.append(f"HEADER kept versionNumber={pre_ver}, label='{pre_label}'; status {pre_status}->Inactive")

out='deploy/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V200.expressionSetVersion'
ET.indent(tree, space='    ')
tree.write(out, xml_declaration=True, encoding='UTF-8')
print('\n'.join(log)); print("WROTE",out)
chk=ET.parse(out).getroot()
print("steps:",len(chk.findall(NS+'steps')),"vars:",len(chk.findall(NS+'variables')),"ver:",tx(chk,'versionNumber'),"status:",tx(chk,'status'))
