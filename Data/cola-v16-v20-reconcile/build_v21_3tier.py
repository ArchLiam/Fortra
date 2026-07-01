import xml.etree.ElementTree as ET, glob
NSURI='http://soap.sforce.com/2006/04/metadata'; NS='{'+NSURI+'}'
ET.register_namespace('', NSURI)
def tx(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
def find_step(root,name):
    for st in root.findall(NS+'steps'):
        if tx(st,'name')==name: return st
def get_param(step,pname):
    for p in step.find(NS+'customElement').findall(NS+'parameters'):
        if tx(p,'name')==pname: return p

LIVE=glob.glob('verify/**/*V200*.expressionSetVersion',recursive=True)[0]   # current live V20 (7-tier + COLA + currency)
ORIG=glob.glob('retrieve/**/*V200*.expressionSetVersion',recursive=True)[0]  # original V20 (3-tier)
tree=ET.parse(LIVE); root=tree.getroot()
orig=ET.parse(ORIG).getroot()

# pull 3-tier formula from original V20
threetier=get_param(find_step(orig,'DerivedPricingFormula'),'formula-section-0-input').find(NS+'value').text
dst=get_param(find_step(root,'DerivedPricingFormula'),'formula-section-0-input')
before=dst.find(NS+'value').text
dst.find(NS+'value').text=threetier
ntier=lambda f: sum(f.count("'%s'"%t) for t in ['Expert','Premier','Express','Premium','Standard','Professional','Basic'])
print(f"DerivedPricingFormula: {ntier(before)}-tier -> {ntier(threetier)}-tier")

# header -> V21 draft
root.find(NS+'label').text='Rev Mgmt Default Pricing V21'
root.find(NS+'status').text='Inactive'
root.find(NS+'versionNumber').text='21'
root.find(NS+'description').text='Revenue Management Default Pricing Procedure V21 - V20 (COLA proration + guards + currency) with Derived Pricing Formula reverted to 3-tier. DRAFT.'

out='draft_v21_3tier/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V210.expressionSetVersion'
ET.indent(tree, space='    ')
tree.write(out, xml_declaration=True, encoding='UTF-8')
chk=ET.parse(out).getroot()
print("WROTE",out)
print("steps:",len(chk.findall(NS+'steps')),"vars:",len(chk.findall(NS+'variables')),"label:",tx(chk,'label'),"status:",tx(chk,'status'),"ver:",tx(chk,'versionNumber'))
