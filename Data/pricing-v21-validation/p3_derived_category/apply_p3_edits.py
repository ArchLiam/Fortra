#!/usr/bin/env python3
"""
Portion 3 (Derived + Category totals) edits to Rev_Mgmt_Default_Pricing_Procedure V21.
Operates ONLY on the V21 (Active, last) <versions> block; V1..V20 are left byte-identical.

Edits:
  A. 7-TIER RESTORE  (DerivedPricingFormula)   -- fixes the 3-tier regression land-mine
  B. J-10            (drop COLA filter crit 3 DerivedPricingAttribute=false + fix conditionLogic)
  C. K-02            (insert SurfaceMissingContributorK02 child of ListContainer9, seq3)
  D. K-09            (insert 3 top-level category zero-init resets; renumber top-level seq>=33 by +3)
"""
import re, sys

PATH = "deploy/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition"
src = open(PATH, encoding="utf-8").read()
lines = src.split("\n")

# ---- split full file: prefix (V1..V20, through V20's closing </versions>) | v21 block ----
# V21 <versions> opens at file line 110850 (1-based); index 110849. Line 110849 (idx 110848) is V20's </versions>.
# Locate robustly: the LAST '<versions>' occurrence.
open_idxs = [i for i, l in enumerate(lines) if l.strip() == "<versions>"]
assert len(open_idxs) == 21, f"expected 21 <versions>, found {len(open_idxs)}"
v21_start = open_idxs[-1]                      # index of the V21 '<versions>' line
prefix = "\n".join(lines[:v21_start])
v21 = "\n".join(lines[v21_start:])            # from '<versions>' (V21) .. EOF
assert v21.lstrip().startswith("<versions>")
assert "<versionNumber>21</versionNumber>" in v21
assert "Derived Pricing Formula reverted to 3-tier" in v21, "V21 description marker missing"
orig_v21 = v21

def replace_once(text, old, new, tag):
    n = text.count(old)
    assert n == 1, f"[{tag}] expected exactly 1 occurrence, found {n}"
    return text.replace(old, new)

# ============================================================ EDIT A : 7-TIER RESTORE
OLD_A = ("IF ( QuoteTypeText__c = &apos;Renewal&apos; , NetUnitPrice , "
         "IF ( AttributeValue = &apos;Premier&apos; , 0.30 , "
         "IF ( AttributeValue = &apos;Standard&apos; , 0.20 , "
         "IF ( AttributeValue = &apos;Professional&apos; , 0.20 , 0 ) ) ) "
         "* IF ( Base_Price__c &gt; 0 , Base_Price__c , "
         "IF ( Pre_Partner_Price__c &gt; 0 , Pre_Partner_Price__c , "
         "IF ( InputUnitPrice &gt; 0 , InputUnitPrice , 0 ) ) ) )")
# renewal branch = Option 2 (J-10): assign COLACalculatedPrice__c when COLA applies, else passthrough.
NEW_A = ("IF ( QuoteTypeText__c = &apos;Renewal&apos; , "
         "IF ( COLA_Uplift_Percent__c &gt; 0 , IF ( COLACalculatedPrice__c &gt; 0 , COLACalculatedPrice__c , NetUnitPrice ) , NetUnitPrice ) , "
         "IF ( AttributeValue = &apos;Basic&apos; , 0.15 , "
         "IF ( AttributeValue = &apos;Standard&apos; , 0.20 , "
         "IF ( AttributeValue = &apos;Professional&apos; , 0.20 , "
         "IF ( AttributeValue = &apos;Premium&apos; , 0.24 , "
         "IF ( AttributeValue = &apos;Express&apos; , 0.30 , "
         "IF ( AttributeValue = &apos;Premier&apos; , 0.30 , "
         "IF ( AttributeValue = &apos;Expert&apos; , 0.35 , 0 ) ) ) ) ) ) ) "
         "* IF ( Base_Price__c &gt; 0 , Base_Price__c , "
         "IF ( Pre_Partner_Price__c &gt; 0 , Pre_Partner_Price__c , "
         "IF ( InputUnitPrice &gt; 0 , InputUnitPrice , 0 ) ) ) )")
v21 = replace_once(v21, OLD_A, NEW_A, "A 7-tier")

# ============================================================ EDIT B : J-10 drop COLA crit 3
# Scope to the COLA filter <steps> block (uniquely id'd by its 6-criteria conditionLogic),
# since the seq-3 "DerivedPricingAttribute Equals false" criterion also appears in 2 other V21 filters.
cola_re = re.compile(r"        <steps>\n(?:(?!</steps>).)*?<conditionLogic>1 AND 2 AND 3 AND 4 AND 5 AND 6</conditionLogic>.*?\n        </steps>", re.S)
cm = cola_re.search(v21)
assert cm is not None, "COLA filter step block not found"
cola_block = cm.group(0)
assert "<name>COLAUpliftonRenewal</name>" in cola_block, "matched block is not the COLA filter"
CRIT3 = (
    "                <criteria>\n"
    "                    <operator>Equals</operator>\n"
    "                    <sequenceNumber>3</sequenceNumber>\n"
    "                    <sourceFieldName>DerivedPricingAttribute</sourceFieldName>\n"
    "                    <value>false</value>\n"
    "                    <valueType>Literal</valueType>\n"
    "                </criteria>\n")
assert cola_block.count(CRIT3) == 1, "crit3 not uniquely present in COLA block"
# 1) remove crit3
new_cola = cola_block.replace(CRIT3, "", 1)
# 2) set conditionLogic to CONTIGUOUS 1..5 (engine references criteria by position 1..N,
#    NOT by their original sequenceNumber — leaving '...AND 6' over a 5-item list errors at runtime)
new_cola = new_cola.replace(
    "<conditionLogic>1 AND 2 AND 3 AND 4 AND 5 AND 6</conditionLogic>",
    "<conditionLogic>1 AND 2 AND 3 AND 4 AND 5</conditionLogic>", 1)
# 3) renumber the surviving <criteria> sequenceNumbers contiguously 1..5 (only inside advancedCondition)
ac_m = re.search(r"<advancedCondition>.*?</advancedCondition>", new_cola, re.S)
assert ac_m is not None, "advancedCondition not found in COLA block"
_ctr = {"n": 0}
def _renum(_m):
    _ctr["n"] += 1
    return f"<sequenceNumber>{_ctr['n']}</sequenceNumber>"
ac_new = re.sub(r"<sequenceNumber>\d+</sequenceNumber>", _renum, ac_m.group(0))
assert _ctr["n"] == 5, f"expected 5 surviving criteria, renumbered {_ctr['n']}"
new_cola = new_cola[:ac_m.start()] + ac_new + new_cola[ac_m.end():]
v21 = v21[:cm.start()] + new_cola + v21[cm.end():]

# ============================================================ helpers for step XML
def fbp_step(formula, out_field, label, name, seq, parent=None):
    parent_line = f"            <parentStep>{parent}</parentStep>\n" if parent else ""
    return (
"        <steps>\n"
"            <actionType>FormulaBasedPricing</actionType>\n"
"            <customElement>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>formula-section-0-input</name>\n"
"                    <output>false</output>\n"
"                    <type>Formula</type>\n"
f"                    <value>{formula}</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>formulaSectionCount</name>\n"
"                    <output>false</output>\n"
"                    <type>Literal</type>\n"
"                    <value>1</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>HideWaterfall</name>\n"
"                    <output>false</output>\n"
"                    <type>Literal</type>\n"
"                    <value>false</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>sectionCount</name>\n"
"                    <output>false</output>\n"
"                    <type>Literal</type>\n"
"                    <value>0</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>selectedFunction</name>\n"
"                    <output>false</output>\n"
"                    <type>Literal</type>\n"
"                    <value>Get</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>true</input>\n"
"                    <name>IsRealTime</name>\n"
"                    <output>false</output>\n"
"                    <type>Literal</type>\n"
"                    <value>false</value>\n"
"                </parameters>\n"
"                <parameters>\n"
"                    <input>false</input>\n"
"                    <name>formula-section-0-output</name>\n"
"                    <output>true</output>\n"
"                    <type>Parameter</type>\n"
f"                    <value>{out_field}</value>\n"
"                </parameters>\n"
"            </customElement>\n"
"            <description>Formula Based Pricing</description>\n"
"            <hasNestedExplainability>false</hasNestedExplainability>\n"
f"            <label>{label}</label>\n"
f"            <name>{name}</name>\n"
f"{parent_line}"
"            <resultIncluded>false</resultIncluded>\n"
f"            <sequenceNumber>{seq}</sequenceNumber>\n"
"            <shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly>\n"
"            <shouldExposeConditionDetails>false</shouldExposeConditionDetails>\n"
"            <shouldShowExplExternally>false</shouldShowExplExternally>\n"
"            <stepType>BusinessKnowledgeModel</stepType>\n"
"        </steps>")

# ============================================================ EDIT C : K-02 surfacing step
# DISABLED 2026-06-29: deploy rejected ValidationResult as "unsupported field type" in a
# FormulaBasedPricing formula. K-02 needs a different surfacing mechanism (see handoff). The
# other 3 fixes are independent of this step, so we ship them and rework K-02 separately.
INCLUDE_K02 = False
if INCLUDE_K02:
    K02_FORMULA = ("IF ( QuoteTypeText__c = &apos;Renewal&apos; , ValidationResult , "
                   "IF ( Base_Price__c &gt; 0 , ValidationResult , "
                   "IF ( Pre_Partner_Price__c &gt; 0 , ValidationResult , "
                   "IF ( InputUnitPrice &gt; 0 , ValidationResult , &apos;MissingContributor&apos; ) ) ) )")
    k02_step = fbp_step(K02_FORMULA, "ValidationResult",
                        "Surface Missing Contributor (K-02)", "SurfaceMissingContributorK02",
                        3, parent="ListContainer9")
    anchor = "            <label>Derived Pricing Formula</label>\n            <name>DerivedPricingFormula</name>"
    idx = v21.find(anchor)
    assert idx != -1, "DerivedPricingFormula anchor not found"
    close = v21.find("\n        </steps>", idx)
    assert close != -1, "DerivedPricingFormula close </steps> not found"
    insert_at = close + len("\n        </steps>")
    v21 = v21[:insert_at] + "\n" + k02_step + v21[insert_at:]

# ============================================================ EDIT D : K-09 zero-inits + renumber
# (D1) renumber TOP-LEVEL steps (no <parentStep>) with sequenceNumber>=33  ->  +3
step_re = re.compile(r"        <steps>\n.*?\n        </steps>", re.S)
def is_top_level(block):
    return "<parentStep>" not in block
def get_seq(block):
    m = re.search(r"<sequenceNumber>(\d+)</sequenceNumber>", block)
    return int(m.group(1)) if m else None

# Build new v21 by walking blocks (span-safe).
out = []
last = 0
renumbered = []
for m in step_re.finditer(v21):
    out.append(v21[last:m.start()])
    block = m.group(0)
    if is_top_level(block):
        seq = get_seq(block)
        if seq is not None and seq >= 33:
            newseq = seq + 3
            block = re.sub(r"(<sequenceNumber>)\d+(</sequenceNumber>)",
                           rf"\g<1>{newseq}\g<2>", block, count=1)
            renumbered.append((seq, newseq))
    out.append(block)
    last = m.end()
out.append(v21[last:])
v21 = "".join(out)
assert len(renumbered) >= 12, f"expected >=12 top-level renumbers, got {len(renumbered)}"

# (D2) build 3 reset steps and insert before the first <variables>
resets = "\n".join([
    fbp_step("0", "Total_Services__c",     "Reset Total Services (K-09 zero-init)",     "ResetTotalServicesK09",     33),
    fbp_step("0", "Total_Software__c",     "Reset Total Software (K-09 zero-init)",     "ResetTotalSoftwareK09",     34),
    fbp_step("0", "Total_Subscription__c", "Reset Total Subscription (K-09 zero-init)", "ResetTotalSubscriptionK09", 35),
])
var_anchor = "\n        <variables>"
vi = v21.find(var_anchor)
assert vi != -1, "<variables> anchor not found in V21"
v21 = v21[:vi] + "\n" + resets + v21[vi:]

# ============================================================ reassemble + write
assert orig_v21 != v21, "no change made to V21!"
result = prefix + "\n" + v21
open(PATH, "w", encoding="utf-8").write(result)

print("EDITS APPLIED OK")
print(f"  A 7-tier restore:        1 formula replaced")
print(f"  B J-10:                  conditionLogic + crit3 removed")
print(f"  C K-02:                  SurfaceMissingContributorK02 inserted (ListContainer9 seq3)")
print(f"  D K-09:                  3 resets inserted (seq 33/34/35); renumbered top-level: {renumbered}")
