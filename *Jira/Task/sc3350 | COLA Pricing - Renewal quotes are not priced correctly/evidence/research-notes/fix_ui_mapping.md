# SC-3350 — Fix Design/Designer-UI Mapping (NetUnitPrice=0 on non-derived COLA renewals)

**Date:** 2026-06-10 (read-only verification run). **Org:** FortraUAT.
**Procedure:** `Rev_Mgmt_Default_Pricing_Procedure`, **active version = V10** (ExpressionSetDefinition).
**Source XML:** `Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (52,499 lines).
**Active V10 block = lines 46677–52499** (`<fullName>...Rev_Mgmt_Default_Pricing_V100</fullName>` @46678, `<status>Active</status>` @46687, `<versionNumber>10</versionNumber>` @52497). All cites below are inside this block. (Earlier blocks V1–V9 are inactive; ignore.)

> **CRITICAL NAMING CORRECTION vs the brief/RCA.** The brief names the renewal container `ListContainer55` (filter `ListOperation56`) and the seed step `QuantityPrice49` in `ListContainer47`. **Those names do not exist in the active V10.** V10's step names were regenerated. The verified V10 equivalents are below. The brief's *mechanism* is correct; only the element *names* changed.

---

## 1. Verified V10 element inventory (the real wiring)

### 1a. COLA "Path A" — writes InputUnitPrice ONLY (the bug origin)
- **Filter** `COLAUpliftonRenewal` (line **48187**), `stepType=AdvancedListFilter`, `parentStep=ListContainer2`, seq 1.
  conditionLogic `1 AND 2 AND 3 AND 4 AND 5 AND 6` (lines 48143–48184):
  1. `ItemPricingSource` Equals `'LastTransaction'`
  2. `DerivedPricingAttribute` IsNotNull
  3. `DerivedPricingAttribute` Equals `false`
  4. `SalesTransactionActionType` IsNotNull
  5. `SalesTransactionActionType` Equals `'Renew'`
  6. `COLA_Uplift_Percent__c` IsNotNull
- **Assignment** `COLAUpliftonRenewal21` (line **48238**), `actionType=AssignmentElement`, `stepType=BusinessKnowledgeModel`, `parentStep=ListContainer2`, seq 2.
  - `section-0-input1` (source) = `COLACalculatedPrice__c`
  - `section-0-output` (target) = `InputUnitPrice` (line 48232)
  - `sectionJsonString2` whereCondition maps `COLACalculatedPrice__c (Currency) → InputUnitPrice (Currency)` (line 48225)
  - **Never touches NetUnitPrice.** (Prehook `COLAUpliftPrehook.cls` writes only `COLACalculatedPrice__c` + audit fields to context — confirmed lines 540–543; no NetUnitPrice write anywhere in the class.)
- `ListContainer2` top-level `sequenceNumber = 9` (line 49204).

### 1b. The renewal/LastTransaction container = **ListContainer62** (NOT ListContainer55)
- `ListContainer62` (name @ **49345**), `stepType=ListGroup`, top-level `sequenceNumber = 23` (line 49347).
- Its gate filter **ListOperation63** (name @ **49504**), `stepType=AdvancedListFilter`, `parentStep=ListContainer62`, seq 1, conditionLogic `1`:
  - `ItemPricingSource` Equals `'LastTransaction'` (line 49497–49499).  ← this is the renewal gate.
- Current child computation **FormulaBasedPricing** (name @ **49006**), `actionType=FormulaBasedPricing`, `stepType=BusinessKnowledgeModel`, `parentStep=ListContainer62`, **seq 2**, formula `NetUnitPrice * LineItemQuantity → ItemNetTotalPrice` (formula @ 48951, output @ 48993).
  - **This step READS NetUnitPrice but the container never SEEDED it.** On a LastTransaction line NetUnitPrice is still the default 0 → ItemNetTotalPrice = 0. This is where the $0 manifests.
- **ListContainer62 has exactly TWO children in V10: ListOperation63 (seq 1, filter) and FormulaBasedPricing (seq 2). No NetUnitPrice seed.** (Verified: only 2 `parentStep>ListContainer62` in V10.)

### 1c. The ONLY existing InputUnitPrice→NetUnitPrice-style seed (for the non-renewal path)
- Non-renewal container **ListContainer49** (name @ 49202… actually @ line for ListContainer49 = **49180-range**; top-level `sequenceNumber = 19`), gate **ListOperation50** (`ItemPricingSource NotEquals 'LastTransaction'`, line 49473–49477).
- Its NetUnitPrice producer is `BundleBasedAdjustmentEntries` (name @ **48136**, a BBM decision table that *outputs* NetUnitPrice @ 48120–48123) — not a plain assignment. So there is no verbatim "InputUnitPrice→NetUnitPrice" AssignmentElement to clone by name; instead clone the generic Assignment pattern (see 1d).

### 1d. Canonical AssignmentElement pattern to MIRROR (source→target copy)
Cleanest template = the `Assignment` step (line **47054**), `parentStep=ListContainer40`, which copies `ListPrice → InputUnitPrice`:
```
section-0-input1 (input=true,  Parameter) = <SOURCE>     e.g. ListPrice
section-0-output (input=false, output=true, Parameter) = <TARGET>  e.g. InputUnitPrice
sectionJsonString2 = {"whereConditions":[{"field":{...,"name":"section-0-input1","value":"<SOURCE>",...},"value":{...,"name":"section-0-output","value":"<TARGET>",...}}]}
actionType=AssignmentElement ; stepType=BusinessKnowledgeModel ; description/label = "Assignment"
```
For our fix invert direction: **SOURCE = InputUnitPrice, TARGET = NetUnitPrice.**
(Identical shape also at `COLAUpliftonRenewal21` @48238 and `DerivedPricingValuesAssignment` @48710 — the latter does `NetUnitPrice→InputUnitPrice`, i.e. our exact reverse, so it is the most faithful structural mirror.)

### 1e. SubscriptionPricing group (the downstream zero-reader the fix must precede)
- `SubscriptionPricing` (name @ **51421**), reads `NetUnitPrice` as input (51370–51373) and writes `SubscriptionNetUnitPrice → NetUnitPrice` back (51412–51415). `parentStep = TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel`.
- That parent ListGroup `TermDefinedSubscriptionFilter...` top-level `sequenceNumber = 24`, gate `ListOperation66` = `SellingModelType Equals 'TermDefined'` (49519–49521).
- Because SubscriptionPricing reads NetUnitPrice=0 then writes it back, it *propagates* the zero; it is the victim, not the cause.

### 1f. Top-level container execution order (by ListGroup sequenceNumber) — the proof the seed slots cleanly
| seq | ListGroup | Role |
|----:|-----------|------|
| 7  | `ListContainer` | Path B derived-renewal (DerivedPricingRenewals → NetUnitPrice; DerivedPricingValuesAssignment NetUnitPrice→InputUnitPrice) — `DerivedPricingAttribute=true`/MDT only |
| **9**  | **`ListContainer2`** | **COLA Path A — sets InputUnitPrice (COLACalculatedPrice__c→InputUnitPrice)** |
| 19 | `ListContainer49` | Non-renewal (`ItemPricingSource NotEquals 'LastTransaction'`) |
| **23** | **`ListContainer62`** | **Renewal/LastTransaction (`ItemPricingSource Equals 'LastTransaction'`) — INSERT THE SEED HERE** |
| **24** | `TermDefinedSubscriptionFilter...` | **SubscriptionPricing (reads NetUnitPrice) — fix must land BEFORE this** |

→ COLA (9) sets InputUnitPrice **before** LC62 (23). A seed inside LC62 sees the COLA price. LC62 (23) runs **before** SubscriptionPricing (24). **The placement is correct and unambiguous.**

> **Within the active V10 version each of these names occurs exactly once** (verified counts: ListContainer62 ×1, ListContainer2 ×1, COLAUpliftonRenewal21 ×1, FormulaBasedPricing ×1). The "10× duplication" noted elsewhere is *across* the 9 inactive prior versions in the same file, not within V10. The Designer shows one version at a time, so the admin sees exactly one of each.

---

## 2. THE FIX — element to add

**Add one `Assignment` element (Designer element type = "Assignment"; metadata `actionType=AssignmentElement`, `stepType=BusinessKnowledgeModel`) inside container `ListContainer62` (the renewal/LastTransaction List Group, top-level seq 23), copying `InputUnitPrice → NetUnitPrice`, sequenced BEFORE the existing `FormulaBasedPricing` (Quantity*Price) step, gated `ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute = false`.**

Rationale for the inner gate even though LC62 already gates on LastTransaction: the explicit `DerivedPricingAttribute = false` mirrors Path A's exclusion of MDT-derived lines (Path B in `ListContainer` @seq 7 already owns the `DerivedPricingAttribute=true` lines and writes their NetUnitPrice). It prevents this seed from overwriting a Path-B-derived NetUnitPrice if a derived line ever also carries `ItemPricingSource='LastTransaction'`. Without the gate the seed is still *probably* safe (Path B runs at seq 7, earlier, and its NetUnitPrice would be clobbered by InputUnitPrice here), so **the `DerivedPricingAttribute=false` condition is REQUIRED to avoid regressing Path B.**

---

## 3. (a) Click-by-click Designer instructions (Setup → Pricing Procedure)

1. **Setup → Pricing → Pricing Procedures** (or **Revenue Settings → Pricing Procedures**). Open **Revenue Management Default Pricing Procedure**.
2. Open **Version 10** (the Active version). The Designer canvas shows the ordered List Groups.
   - You **cannot edit an Active version in place.** Click **Clone / Save As New Version** → this creates **V11** as a Draft (see §6). Make all edits in V11.
3. In V11, locate the **renewal List Group**. It is the ListGroup whose **filter row reads `Item Pricing Source = LastTransaction`** (metadata `ListContainer62`, sequence 23 — it sits between the non-renewal group `ItemPricingSource ≠ LastTransaction` and the `Selling Model Type = TermDefined` Subscription Pricing group). Display label is the generic **"List Container"**; identify it by the `ItemPricingSource Equals LastTransaction` filter and by the single child **"Quantity \* Price" / "Formula Based Pricing"** step it contains.
4. Inside that group, click **Add Element → Assignment** (the "Assignment" element type).
5. Configure the new Assignment:
   - **Source / input** (`section-0-input1`): select field **`InputUnitPrice`**.
   - **Target / output** (`section-0-output`): select field **`NetUnitPrice`**.
   - (Designer builds the `sectionJsonString2` whereCondition automatically from these two picks.)
   - Label/Name it clearly, e.g. **"Seed Net Unit Price (Renewal)"**.
6. **Set its filter / advanced condition** (conditionLogic `1 AND 2`):
   - Row 1: `Item Pricing Source` **Equals** `'LastTransaction'`
   - Row 2: `Derived Pricing Attribute` **Equals** `false`
7. **Order it FIRST inside the group, before "Quantity \* Price"** (drag it above the existing Formula Based Pricing step, i.e. give it the lower sequence so it runs before the step that reads NetUnitPrice). After reorder the group should be: **Seed Net Unit Price (Renewal)** → **Quantity \* Price**.
8. **Save** V11 (Draft).
9. **Validate / Simulate** on a known-broken renewal quote (e.g. the Abstract line from the RCA waterfall): confirm the Net track now anchors on the COLA InputUnitPrice (≈4697.946) instead of "Net Unit Price USD 0.00".
10. **Activate V11** (see §6). Activation auto-deactivates V10.

---

## 3. (b) Equivalent metadata XML to insert (mirrors the Assignment pattern @47054 / DerivedPricingValuesAssignment @48710)

Insert this `<steps>...</steps>` block **inside the active version's `<steps>` collection** (it can go anywhere among the sibling `<steps>` — ordering within a container is governed by `sequenceNumber`, not document position). It declares a new child of `ListContainer62` at `sequenceNumber=2`; **you must also bump the existing `FormulaBasedPricing` step from `sequenceNumber>2<` to `sequenceNumber>3<` (line 49009)** so the seed runs first. (The ListOperation63 filter stays at seq 1.)

```xml
        <steps>
            <actionType>AssignmentElement</actionType>
            <advancedCondition>
                <conditionLogic>1 AND 2</conditionLogic>
                <criteria>
                    <operator>Equals</operator>
                    <sequenceNumber>1</sequenceNumber>
                    <sourceFieldName>ItemPricingSource</sourceFieldName>
                    <value>&apos;LastTransaction&apos;</value>
                    <valueType>Literal</valueType>
                </criteria>
                <criteria>
                    <operator>Equals</operator>
                    <sequenceNumber>2</sequenceNumber>
                    <sourceFieldName>DerivedPricingAttribute</sourceFieldName>
                    <value>false</value>
                    <valueType>Literal</valueType>
                </criteria>
            </advancedCondition>
            <customElement>
                <parameters>
                    <input>true</input>
                    <name>section-0-input1</name>
                    <output>false</output>
                    <type>Parameter</type>
                    <value>InputUnitPrice</value>
                </parameters>
                <parameters>
                    <input>true</input>
                    <name>sectionCount</name>
                    <output>false</output>
                    <type>Literal</type>
                    <value>1</value>
                </parameters>
                <parameters>
                    <input>true</input>
                    <name>sectionJsonString1</name>
                    <output>false</output>
                    <type>Literal</type>
                    <value>{&quot;whereConditions&quot;:[]}</value>
                </parameters>
                <parameters>
                    <input>true</input>
                    <name>sectionJsonString2</name>
                    <output>false</output>
                    <type>Literal</type>
                    <value>{&quot;whereConditions&quot;:[{&quot;field&quot;:{&quot;dataType&quot;:&quot;Currency&quot;,&quot;name&quot;:&quot;section-0-input1&quot;,&quot;value&quot;:&quot;InputUnitPrice&quot;,&quot;allowCompatibleDataTypes&quot;:true},&quot;value&quot;:{&quot;dataType&quot;:&quot;Currency&quot;,&quot;name&quot;:&quot;section-0-output&quot;,&quot;value&quot;:&quot;NetUnitPrice&quot;,&quot;allowCompatibleDataTypes&quot;:true}}]}</value>
                </parameters>
                <parameters>
                    <input>false</input>
                    <name>section-0-output</name>
                    <output>true</output>
                    <type>Parameter</type>
                    <value>NetUnitPrice</value>
                </parameters>
            </customElement>
            <description>Assignment</description>
            <hasNestedExplainability>false</hasNestedExplainability>
            <label>Seed Net Unit Price (Renewal)</label>
            <name>SeedNetUnitPriceRenewal</name>
            <parentStep>ListContainer62</parentStep>
            <resultIncluded>false</resultIncluded>
            <sequenceNumber>2</sequenceNumber>
            <shouldExposExecPathMsgOnly>true</shouldExposExecPathMsgOnly>
            <shouldExposeConditionDetails>false</shouldExposeConditionDetails>
            <shouldShowExplExternally>false</shouldShowExplExternally>
            <stepType>BusinessKnowledgeModel</stepType>
        </steps>
```
And bump the existing FormulaBasedPricing child of ListContainer62 (line 49009) from `<sequenceNumber>2</sequenceNumber>` to `<sequenceNumber>3</sequenceNumber>`.

**Notes on the XML approach:**
- The brief used `AssignmentElement` schema convention: `section-0-input1` is the SOURCE, `section-0-output` is the TARGET. Confirmed against the `Assignment` step @47054 (ListPrice→InputUnitPrice) and `DerivedPricingValuesAssignment` @48710 (NetUnitPrice→InputUnitPrice).
- `resultIncluded=false` matches the assignment template (assignments don't aggregate into the result set; only the pricing computation step `FormulaBasedPricing` has `resultIncluded=true`).
- `<name>` must be unique within the version; `SeedNetUnitPriceRenewal` is unused.
- The hand-edit is the LAST resort (52k-line file, V11 must be reconstructed). **Strongly prefer the Designer path in §3(a).** If editing XML, you must (1) duplicate the entire V10 `<versions>` block into a new `<versions>` block with `<fullName>...V11...</fullName>` / a fresh label / `<status>` handled by activation, then (2) add the step there, because the Designer's Clone creates that block for you.

---

## 4. Why this is the correct, minimal fix (verification summary)

- **Cause is in the procedure, not Apex.** `COLAUpliftPrehook.cls` writes `COLACalculatedPrice__c` (and audit fields) only — never NetUnitPrice (verified all `attributeName` writes). The procedure's only NetUnitPrice writers on the LastTransaction path are: (Path B) `DerivedPricingRenewals` for MDT-derived lines, and (non-renewal) `BundleBasedAdjustmentEntries` in `ListContainer49`. **Nothing seeds NetUnitPrice for a non-derived LastTransaction line.** Confirmed: ListContainer62's only steps are the LastTransaction filter + a NetUnitPrice-reader.
- **The seed value is correct.** COLA Path A (`ListContainer2`, seq 9) writes the COLA-adjusted price into `InputUnitPrice` *before* LC62 (seq 23). Copying `InputUnitPrice → NetUnitPrice` inside LC62 captures exactly the COLA price the RCA waterfall shows missing from the Net track (≈4697.946).
- **Ordering is safe.** seed (new, seq 2 in LC62) → `FormulaBasedPricing` (seq 3, computes ItemNetTotalPrice from the now-seeded NetUnitPrice) → SubscriptionPricing group (top-level seq 24) reads a non-zero NetUnitPrice.
- **No Path B regression.** `DerivedPricingAttribute=false` excludes MDT-derived lines, whose NetUnitPrice is owned by Path B (`ListContainer` seq 7).

---

## 5. Uncertainties / things to confirm before deploy

1. **Designer step-type label.** Salesforce labels the AssignmentElement as **"Assignment"** in the RLM Pricing Procedure Designer. Confirm the exact Add-Element menu wording in this org's API version (metadata is v66; org SOAP v67) — the underlying `actionType=AssignmentElement` is certain from the XML; the menu label may differ slightly by release.
2. **Whether the inner `ItemPricingSource Equals LastTransaction` row is redundant.** LC62's container gate (ListOperation63) already enforces it, so row 1 may be optional. Keeping it is harmless and makes the step self-documenting; **row 2 (`DerivedPricingAttribute = false`) is the load-bearing one and must stay.**
3. **Aggregation side-effects.** `FormulaBasedPricing` (now seq 3) is `resultIncluded=true`; the seed is `resultIncluded=false`. Re-verify in Simulate that Subtotal/TotalLineAmount (list side, already correct) are untouched and only the Net track changes. The RCA flagged that the field named "Net" is sometimes wired to list elsewhere — confirm this seed does not collide with any RegionalNet/Subtotal reconcile step (e.g. `RegionalInputUnitPrice` @50755 writes InputUnitPrice in a different container `RegionalNetReconcile`; it runs in its own group and is not on the renewal seq-23 path — low risk, but validate on an Italy-regional renewal line too).
4. **Exact line numbers** above are for the current retrieve; they will shift after any edit. Anchor on **element names** (ListContainer62 / FormulaBasedPricing / SubscriptionPricing) not line numbers.

---

## 6. Versioning & activation

- **A new version IS required.** V10 is `Active`; ExpressionSetDefinitionVersions are immutable once activated. The Designer's **Clone / Save As New Version** produces **V11** in **Draft** status. All edits go into V11.
- **Activation:** publishing/activating V11 atomically **deactivates V10** (only one Active version per ExpressionSetDefinition at a time). Activation also re-syncs/compiles the version against the context definition `SalesTransactionContextExt_v2`; if any referenced field/attribute (InputUnitPrice, NetUnitPrice, ItemPricingSource, DerivedPricingAttribute — all already used in V10) is unmapped it will error at activate, but all four are pre-existing context attributes, so no context change is needed.
- **Provenance note (from live_procedure_v10.md §1):** V10 was created+activated by **Liam Jeong** (02:18Z create / 03:22Z activate today), not Marc DeBrey. V11 should be created the same way (Designer clone), and after activation re-verify `OrderEntitiesMapping`/context sync per the team's republish hardening checklist.
- **Deploy gate:** per project rules, any UAT deploy/activation (even validate-only) needs a fresh explicit ack. This document is design-only; do not activate V11 without that ack.
