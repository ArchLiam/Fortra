#!/usr/bin/env python3
import sys

F = "apply/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition"
raw = open(F).read()
lines = raw.split("\n")

# 1) locate the <versions> block that contains <status>Active</status>
blocks = []
start = None
for i, l in enumerate(lines):
    if l.strip() == "<versions>":
        start = i
    elif l.strip() == "</versions>" and start is not None:
        blocks.append((start, i)); start = None

active = [(s, e) for (s, e) in blocks if any("<status>Active</status>" == lines[k].strip() for k in range(s, e + 1))]
assert len(active) == 1, f"expected exactly 1 active block, got {len(active)}"
s, e = active[0]
block = lines[s:e + 1]
print(f"active block lines (1-based): {s+1}-{e+1}, {len(block)} lines")

# 2) integrity checks within the block
def count_in(block, needle):
    return sum(needle in x for x in block)

BEFORE = "<value>IF ( QuoteTypeText__c = &apos;Renewal&apos; , IF ( COLACalculatedPrice__c &gt; 0 , COLACalculatedPrice__c , ( Base_Price__c - Prior_Partner_Discount__c - Prior_Discretionary_Discount__c ) * ( 1 + ( COLA_Uplift_Percent__c / 100 ) ) ) , NetUnitPrice )</value>"
AFTER  = "<value>IF ( QuoteTypeText__c = &apos;Renewal&apos; , IF ( COLACalculatedPrice__c &gt; 0 , COLACalculatedPrice__c , ( IF ( ISNULL ( Base_Price__c ) , 0 , Base_Price__c ) - IF ( ISNULL ( Prior_Partner_Discount__c ) , 0 , Prior_Partner_Discount__c ) - IF ( ISNULL ( Prior_Discretionary_Discount__c ) , 0 , Prior_Discretionary_Discount__c ) ) * ( 1 + ( IF ( ISNULL ( COLA_Uplift_Percent__c ) , 0 , COLA_Uplift_Percent__c ) / 100 ) ) ) , NetUnitPrice )</value>"

checks = {
    "<fullName>Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V130</fullName>": 1,
    "<label>Rev Mgmt Default Pricing V13</label>": 1,
    "<status>Active</status>": 1,
    "<versionNumber>13</versionNumber>": 1,
    BEFORE.strip(): 1,
}
for needle, want in checks.items():
    got = count_in(block, needle.strip()) if needle != BEFORE.strip() else sum(BEFORE.strip() in x for x in block)
    # use substring for header tags too (they appear as full-line content)
    got = sum(needle in x for x in block)
    assert got == want, f"INTEGRITY FAIL: '{needle[:50]}...' found {got}x in block, want {want}"
    print(f"  ok: {needle[:55]:57} = {got}")

# 3) build the cloned V14 block (transform a COPY of the block text only)
clone = []
for x in block:
    y = x
    y = y.replace("Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V130",
                  "Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V140")
    y = y.replace("<label>Rev Mgmt Default Pricing V13</label>",
                  "<label>Rev Mgmt Default Pricing V14</label>")
    y = y.replace("<status>Active</status>", "<status>Inactive</status>")
    y = y.replace("<versionNumber>13</versionNumber>", "<versionNumber>14</versionNumber>")
    if BEFORE in y:
        y = y.replace(BEFORE, AFTER)
    clone.append(y)

# 4) verify the clone transformed correctly
assert sum("<status>Inactive</status>" in x for x in clone) == 1, "clone status not Inactive"
assert sum("<status>Active</status>" in x for x in clone) == 0, "clone still has Active"
assert sum("_V140</fullName>" in x for x in clone) == 1, "clone fullName not V140"
assert sum("<versionNumber>14</versionNumber>" in x for x in clone) == 1, "clone versionNumber not 14"
assert sum(AFTER in x for x in clone) == 1, "clone formula not ISNULL-guarded"
assert sum(BEFORE in x for x in clone) == 0, "clone still has unguarded formula"

# 5) insert clone immediately AFTER the active block's </versions> (index e)
new_lines = lines[:e + 1] + clone + lines[e + 1:]
out = "\n".join(new_lines)
open(F, "w").write(out)

# 6) post-write whole-file verification
after_raw = open(F).read()
al = after_raw.split("\n")
print("\n=== post-write verification ===")
print("  total lines:", len(al), "(was", len(lines), ", +", len(al) - len(lines), ")")
print("  <status>Active</status> count:", after_raw.count("<status>Active</status>"), "(must be 1)")
print("  V140 fullName count:", after_raw.count("_V140</fullName>"), "(must be 1)")
print("  ISNULL-guarded formula count:", after_raw.count(AFTER), "(must be 1)")
print("  original unguarded formula count:", after_raw.count(BEFORE), "(must be 4: untouched older versions + the still-active V13)")
assert after_raw.count("<status>Active</status>") == 1
assert after_raw.count("_V140</fullName>") == 1
assert after_raw.count(AFTER) == 1
print("OK: clone+edit applied; active V13 untouched, V14 inactive added with ISNULL guard.")
