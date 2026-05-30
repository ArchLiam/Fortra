# SC-3211 — Change Summary

**Date:** 2026-05-29
**Status:** **DEPLOYED — v3 Active in FortraUAT.**
**Source file:** `data/sc3211/retrieve/flows/Fortra_OrderItem_Set_Dates.flow-meta.xml`
**Deploy target:** `FortraUAT` (liam.jeong.c@fortra.com.uat)
**Deploy Id:** `0AfWC00000G580X0AR`
**Post-deploy version state:** v3 Active, v2 Obsolete, v1 Obsolete (confirmed via tooling SOQL on `Flow` entity).

---

## 1 · Scope

Three targeted edits inside the existing `Fortra_OrderItem_Set_Dates` Flow. No new flow, trigger, process, or Apex was added. Non-qualifying branch and decision conditions 1–4, 6, 7 are unchanged.

---

## 2 · Edits

### 2.1 Decision condition #5 — MyCap reference

**Before:**
```xml
<conditions>
    <leftValueReference>$Record.MYCAP__c</leftValueReference>
    <operator>EqualTo</operator>
    <rightValue>
        <booleanValue>true</booleanValue>
    </rightValue>
</conditions>
```

**After:**
```xml
<conditions>
    <leftValueReference>$Record.Order.MyCap__c</leftValueReference>
    <operator>EqualTo</operator>
    <rightValue>
        <booleanValue>true</booleanValue>
    </rightValue>
</conditions>
```

Implements Open Question #1 resolution. Aligns the decision element with the Quote → Order propagated field that the rest of the org (and the dead-but-correct `Tk` formula) already uses.

### 2.2 `Perpetual_Set_Dates` — `End_Date_Calculated__c`

**Before:**
```xml
<inputAssignments>
    <field>End_Date_Calculated__c</field>
    <value>
        <elementReference>$Record.EndDate</elementReference>
    </value>
</inputAssignments>
```

**After:**
```xml
<inputAssignments>
    <field>End_Date_Calculated__c</field>
    <value>
        <elementReference>NullDate</elementReference>
    </value>
</inputAssignments>
```

### 2.3 `Perpetual_Set_Dates` — `Start_Date_Calculated__c`

**Before:**
```xml
<inputAssignments>
    <field>Start_Date_Calculated__c</field>
    <value>
        <elementReference>$Record.ServiceDate</elementReference>
    </value>
</inputAssignments>
```

**After:**
```xml
<inputAssignments>
    <field>Start_Date_Calculated__c</field>
    <value>
        <elementReference>NullDate</elementReference>
    </value>
</inputAssignments>
```

### 2.4 New `<variables>` resource — `NullDate`

Added at the end of the Flow body, before `</Flow>`:

```xml
<variables>
    <name>NullDate</name>
    <dataType>Date</dataType>
    <isCollection>false</isCollection>
    <isInput>false</isInput>
    <isOutput>false</isOutput>
</variables>
```

---

## 3 · Date-null technique (why `NullDate` and not something else)

Salesforce Flow `recordUpdates` input assignments must resolve their `<value>` element to a typed reference. For Date fields:

- **`$GlobalConstant.EmptyString` does NOT work** — that global constant is type-restricted to String/Text/Picklist values. Using it against a Date field in a Flow input assignment surfaces a runtime DML write failure or is silently rejected at design time depending on builder version.
- **No `<dateValue></dateValue>` empty literal** — the Flow XSD requires a valid Date string inside `<dateValue>`; empty content fails XSD validation and the Salesforce deploy server enforces the same shape.
- **A Flow Variable of type Date with no default** is the canonical, supported pattern. The variable is initialized to null at interview start, and referencing it in an input assignment writes that null to the target field. This is the technique used here.

`NullDate` is intentionally `isInput=false / isOutput=false / isCollection=false` — it is a private internal resource, not part of the interview contract.

---

## 4 · What was deliberately NOT changed

- **`Non_Perpetual_Set_Dates` recordUpdates node** — left exactly as deployed (Req #6 forbids regression on the non-qualifying branch; the node already matches §1.2).
- **Decision conditions #1–4, #6, #7** — left as deployed (matched §1.1 already).
- **`conditionLogic`** — left as `1 OR 2 OR 3 OR 4 OR 5 OR (6 AND 7)`.
- **`Tk` formula** — unused; left in place (out-of-scope cleanup).
- **Trigger configuration** — Before-Save, CreateAndUpdate, on `OrderItem` — unchanged.
- **`<apiVersion>67.0</apiVersion>`** — unchanged.
- **`<status>Active</status>`** — kept Active so Salesforce activates v3 on deploy.

---

## 5 · Deploy plan (for whoever runs the deploy)

From the repo root:

```bash
cd /Users/liamjeong/Documents/Code/Fortra/data/sc3211/retrieve

# 1. Validate-only (safe; no commit)
sf project deploy validate \
    --source-dir flows/Fortra_OrderItem_Set_Dates.flow-meta.xml \
    --target-org FortraUAT

# 2. Actual deploy (creates v3 Active, demotes v2 → Obsolete)
sf project deploy start \
    --source-dir flows/Fortra_OrderItem_Set_Dates.flow-meta.xml \
    --target-org FortraUAT
```

Rollback if needed: re-activate v2 in the Flow Builder Versions list — Salesforce keeps prior versions even after a new activation. No data needs to be rolled back; the change is logic-only.

---

## 6 · Post-deploy validation

See `validation_results.md` — the plan is documented but **not yet executed** because nothing has been deployed to UAT. The validation plan is structured so a non-Claude operator can execute it directly: SOQL touch-update on hand-picked OrderItems per AC, then re-query the four fields.
