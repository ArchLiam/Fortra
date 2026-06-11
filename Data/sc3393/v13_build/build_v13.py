#!/usr/bin/env python3
"""Build V13 = active V12 + an IsNotNull guard on RegionalNetReconcileGate.
Deterministic, asserts each edit is unique, writes V130 file + package.xml, prints diff."""
import sys, shutil, os, difflib

SRC = "Data/sc3393/evidence/proc_live/unpackaged/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V120.expressionSetVersion"
OUTDIR = "Data/sc3393/v13_build/src/expressionSetVersion"
OUTFILE = os.path.join(OUTDIR, "Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V130.expressionSetVersion")

text = open(SRC, encoding="utf-8").read()
orig = text

def replace_once(t, old, new, label):
    n = t.count(old)
    assert n == 1, f"[{label}] expected exactly 1 occurrence, found {n}"
    return t.replace(old, new)

# 1) label V12 -> V13
text = replace_once(text, "<label>Rev Mgmt Default Pricing V12</label>",
                          "<label>Rev Mgmt Default Pricing V13</label>", "label")
# 2) status Active -> Inactive  (must be unique = the version-level status)
text = replace_once(text, "<status>Active</status>", "<status>Inactive</status>", "status")
# 3) versionNumber 12 -> 13
text = replace_once(text, "<versionNumber>12</versionNumber>", "<versionNumber>13</versionNumber>", "versionNumber")

# 4) gate advancedCondition: add IsNotNull guard (seq2) before GreaterThan (renumber to seq3)
OLD_GATE = """        <advancedCondition>
            <conditionLogic>1 AND 2</conditionLogic>
            <criteria>
                <operator>Equals</operator>
                <sequenceNumber>1</sequenceNumber>
                <sourceFieldName>AllowRegionalPricing__c</sourceFieldName>
                <value>true</value>
                <valueType>Literal</valueType>
            </criteria>
            <criteria>
                <operator>GreaterThan</operator>
                <sequenceNumber>2</sequenceNumber>
                <sourceFieldName>RegionalNetUnitPrice__c</sourceFieldName>
                <value>0</value>
                <valueType>Literal</valueType>
            </criteria>
        </advancedCondition>"""
NEW_GATE = """        <advancedCondition>
            <conditionLogic>1 AND 2 AND 3</conditionLogic>
            <criteria>
                <operator>Equals</operator>
                <sequenceNumber>1</sequenceNumber>
                <sourceFieldName>AllowRegionalPricing__c</sourceFieldName>
                <value>true</value>
                <valueType>Literal</valueType>
            </criteria>
            <criteria>
                <operator>IsNotNull</operator>
                <sequenceNumber>2</sequenceNumber>
                <sourceFieldName>RegionalNetUnitPrice__c</sourceFieldName>
            </criteria>
            <criteria>
                <operator>GreaterThan</operator>
                <sequenceNumber>3</sequenceNumber>
                <sourceFieldName>RegionalNetUnitPrice__c</sourceFieldName>
                <value>0</value>
                <valueType>Literal</valueType>
            </criteria>
        </advancedCondition>"""
text = replace_once(text, OLD_GATE, NEW_GATE, "gate")

os.makedirs(OUTDIR, exist_ok=True)
open(OUTFILE, "w", encoding="utf-8").write(text)

# package.xml (deploy ONLY the new V13 version)
pkg = '''<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V130</members>
        <name>ExpressionSetDefinitionVersion</name>
    </types>
    <version>66.0</version>
</Package>
'''
open("Data/sc3393/v13_build/src/package.xml", "w", encoding="utf-8").write(pkg)

# show the focused diff (only changed regions)
print("=== UNIFIED DIFF (V12 -> V13) ===")
for line in difflib.unified_diff(orig.splitlines(), text.splitlines(),
                                 "V12", "V13", lineterm="", n=1):
    if line.startswith(('+','-','@')) and not line.startswith(('+++','---')):
        print(line)
print("\n=== byte delta:", len(text)-len(orig), "===")
print("OUTFILE:", OUTFILE)
