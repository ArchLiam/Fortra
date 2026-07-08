# Product Attribute Updates by Fortra

**Purpose (one line):** Checklist mapping each Fortra product-attribute maintenance task (create picklists/attributes/values, wire attributes to classifications & SKUs, build attribute-based pricing, and "retire" old Feature Options) to the specific Salesforce RCA platform object it operates on.

> ⚠️ **SOURCE IS A NEAR-STUB.** The source document (`ProductAttributeUpdatesbyFortra.txt`) is ONLY a two-column task→object list. It contains **NO** field definitions, **NO** data types, **NO** formulas, **NO** rounding rules, **NO** tier-precedence logic, **NO** defaults, **NO** Apex/flow/prehook component names, and **NO** integration sequence. Everything below that is not in the "Task → Object mapping" table is explicitly labeled as absent. Do not invent details; re-derive field-level specifics from the live org or a fuller design doc before implementing.

## Executive Summary

The document is an operational runbook / checklist for a Fortra "Product Attribute Updates" effort. It enumerates the **standard Salesforce Revenue Cloud Advanced (RCA) platform objects** that must be touched to (1) stand up new product attributes and their picklists/values, (2) associate those attributes with product classifications and individual products/SKUs, (3) configure attribute-based pricing adjustments (including tiered pricing storage), and (4) decommission ("retire") the legacy "Feature Options" attribute stack by reversing the same object chain.

Notably, the "retire" tasks touch the SAME object set as the "create/connect" tasks — retirement is the inverse operation walking the object graph from the most specific association (product/SKU assignment) back up to the base attribute definition.

## Business Requirements / Rules

The source states requirements only as task headings. Verbatim task list, in source order:

1. Create new picklists
2. Create new attributes
3. Create new picklist values
4. Connect attributes to product classifications
5. Connect attributes to products/SKUs
6. Create new product-specific excluded values
7. Create/Update standard attribute pricing condition records
8. Create/update standard attribute pricing rule parents
9. Create/update standard attribute pricing adjustment records
10. Update tiered pricing storage records
11. "Retire" old Feature Options product/SKU assignments
12. "Retire" old Feature Options exclusions
13. "Retire" old Feature Options classification assignments
14. "Retire" old Feature Options picklist values
15. "Retire" old Feature Options picklist
16. "Retire" old Feature Options attribute

No acceptance criteria, ordering constraints, ownership, or validation rules are stated in the source.

## Data Model — Task → Object Mapping (VERBATIM)

The core (and only) content of the source. One custom RCA object per task. Only `Attribute_Tier_Pricing_Storage__c` is a custom (`__c`) object; the rest are standard RCA platform objects.

| # | Task | Object |
|---|------|--------|
| 1 | Create new picklists | `AttributePicklist` |
| 2 | Create new attributes | `AttributeDefinition` |
| 3 | Create new picklist values | `AttributePicklistValue` |
| 4 | Connect attributes to product classifications | `ProductClassificationAttr` |
| 5 | Connect attributes to products/SKUs | `ProductAttributeDefinition` |
| 6 | Create new product-specific excluded values | `AttrPicklistExcludedValue` |
| 7 | Create/Update standard attribute pricing condition records | `AttributeAdjustmentCondition` |
| 8 | Create/update standard attribute pricing rule parents | `AttributeBasedAdjRule` |
| 9 | Create/update standard attribute pricing adjustment records | `AttributeBasedAdjustment` |
| 10 | Update tiered pricing storage records | `Attribute_Tier_Pricing_Storage__c` |
| 11 | "Retire" old Feature Options product/SKU assignments | `ProductAttributeDefinition` |
| 12 | "Retire" old Feature Options exclusions | `AttrPicklistExcludedValue` |
| 13 | "Retire" old Feature Options classification assignments | `ProductClassificationAttr` |
| 14 | "Retire" old Feature Options picklist values | `AttributePicklistValue` |
| 15 | "Retire" old Feature Options picklist | `AttributePicklist` |
| 16 | "Retire" old Feature Options attribute | `AttributeDefinition` |

### Object reference (roles inferred from RCA platform semantics — NOT from the source)

The source names these objects without describing them. The following one-liners are standard RCA platform roles provided only for orientation; they are NOT authoritative field maps. Verify against the org.

- `AttributeDefinition` — the base attribute (its data type, code, picklist binding). Root of the attribute stack.
- `AttributePicklist` — the picklist container an attribute of type picklist points to.
- `AttributePicklistValue` — the individual selectable values within an `AttributePicklist`.
- `ProductClassificationAttr` — junction assigning an attribute to a Product Classification (applies the attribute to all products in that classification).
- `ProductAttributeDefinition` — junction assigning/overriding an attribute at the individual Product/SKU level.
- `AttrPicklistExcludedValue` — per-product (or per-context) exclusion removing specific picklist values from availability.
- `AttributeAdjustmentCondition` — the condition (which attribute value(s) trigger) for an attribute-based price adjustment.
- `AttributeBasedAdjRule` — the parent rule grouping attribute-based adjustments.
- `AttributeBasedAdjustment` — the actual price adjustment (amount/percent) applied when the condition matches.
- `Attribute_Tier_Pricing_Storage__c` — **custom** object holding tiered pricing rows for attribute-driven pricing.

## Business Logic

**NONE PRESENT IN SOURCE.** The source contains no formulas, no rounding mode, no tier-precedence order, no default values, and no edge-case handling. The only logic implied is the object-graph ordering below (creation top-down, retirement bottom-up), which is an inference from the list order and standard dependency direction — confirm before relying on it.

**Inferred dependency ordering (NOT stated as a rule in source):**
- Create path (build dependencies before dependents): `AttributePicklist` → `AttributeDefinition` → `AttributePicklistValue` → `ProductClassificationAttr` / `ProductAttributeDefinition` → `AttrPicklistExcludedValue` → pricing objects (`AttributeAdjustmentCondition`, `AttributeBasedAdjRule`, `AttributeBasedAdjustment`) → `Attribute_Tier_Pricing_Storage__c`.
- Retire path (reverse — remove associations before base definitions): `ProductAttributeDefinition` → `AttrPicklistExcludedValue` → `ProductClassificationAttr` → `AttributePicklistValue` → `AttributePicklist` → `AttributeDefinition`.

Note the source uses the word **"Retire" (in quotes)** — it does NOT specify whether retirement is a hard delete, a deactivation/flag, or an end-dating. Treat retirement semantics as UNRESOLVED.

## Components (Apex / Triggers / Flows / Prehooks)

**NONE NAMED IN SOURCE.** No Apex classes, triggers, flows, pricing prehooks, or automation are referenced. The document reads as a manual/data-load runbook against platform objects, not a code artifact. If a pricing prehook or Apex path participates in attribute-based adjustment at runtime, it is out of scope of this document and must be sourced elsewhere.

## Integration Points & Sequence

**NONE PRESENT IN SOURCE.** No external systems, no Workday, no APIs, no ordered runbook steps, and no data-load tool are named. The only sequencing signal is the inferred create-vs-retire object ordering above.

## Assumptions / Dependencies / Open Issues

- **Assumption:** Tasks operate on standard RCA platform attribute/pricing objects plus one custom object (`Attribute_Tier_Pricing_Storage__c`).
- **Open issue — retirement semantics:** "Retire" is quoted and undefined (delete vs. deactivate vs. end-date). MUST be clarified before implementing tasks 11–16.
- **Open issue — field-level spec missing:** No field names, types, formulas, or required values are given for ANY object. A real implementation needs the actual object field maps from the org or a detailed design doc.
- **Open issue — no ordering guarantee:** Create/retire dependency order is inferred, not stated.
- **Dependency:** `Attribute_Tier_Pricing_Storage__c` custom object must exist in the target org.
- **Cross-reference:** This ties to Fortra Feature Code / Feature Options work (cf. SC-3468 Model Number / Feature Code dependent-picklist notes) and RCA attribute-based pricing; the legacy "Feature Options" attribute stack is what tasks 11–16 decommission.

## CODE-GOVERNING RULES

Rules an engineer implementing or refactoring this MUST NOT violate. Each cites the exact spec from the source.

1. **Use the exact object per task — do not substitute.** The task→object binding is authoritative and verbatim:
   - Create picklists → `AttributePicklist`
   - Create attributes → `AttributeDefinition`
   - Create picklist values → `AttributePicklistValue`
   - Connect attributes to product classifications → `ProductClassificationAttr`
   - Connect attributes to products/SKUs → `ProductAttributeDefinition`
   - Create product-specific excluded values → `AttrPicklistExcludedValue`
   - Create/Update attribute pricing **condition** records → `AttributeAdjustmentCondition`
   - Create/update attribute pricing **rule parents** → `AttributeBasedAdjRule`
   - Create/update attribute pricing **adjustment** records → `AttributeBasedAdjustment`
   - Update **tiered pricing storage** records → `Attribute_Tier_Pricing_Storage__c`
2. **Retirement reuses the SAME objects as creation — the inverse chain.** Retire tasks target exactly: `ProductAttributeDefinition` (SKU assignments), `AttrPicklistExcludedValue` (exclusions), `ProductClassificationAttr` (classification assignments), `AttributePicklistValue` (picklist values), `AttributePicklist` (picklist), `AttributeDefinition` (attribute). Do not introduce a separate "archive" object not in this list.
3. **`Attribute_Tier_Pricing_Storage__c` is the ONLY custom object.** All other nine objects are standard RCA platform objects (`AttributePicklist`, `AttributeDefinition`, `AttributePicklistValue`, `ProductClassificationAttr`, `ProductAttributeDefinition`, `AttrPicklistExcludedValue`, `AttributeAdjustmentCondition`, `AttributeBasedAdjRule`, `AttributeBasedAdjustment`). Do not append `__c` to platform objects or drop it from the tier-pricing object.
4. **The three attribute-based pricing objects are distinct and layered — condition, rule parent, adjustment.** `AttributeAdjustmentCondition` (condition) ≠ `AttributeBasedAdjRule` (parent) ≠ `AttributeBasedAdjustment` (adjustment). Preserve the parent/condition/adjustment separation; do not collapse them.
5. **"Retire" semantics are UNRESOLVED — do not assume hard delete.** The source quotes "Retire" and never defines it. Any implementation must confirm delete vs. deactivate vs. end-date before writing DML against `ProductAttributeDefinition`, `AttrPicklistExcludedValue`, `ProductClassificationAttr`, `AttributePicklistValue`, `AttributePicklist`, or `AttributeDefinition`.
6. **Do not fabricate fields, types, formulas, defaults, or tier precedence.** The source specifies NONE. Any such detail must be sourced from the live org or a fuller design doc, never from this document.
