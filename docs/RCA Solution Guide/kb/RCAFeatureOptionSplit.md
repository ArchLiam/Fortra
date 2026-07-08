# RCA "Feature Option" Attribute Split

**Purpose (one line):** Proposal to split the single RCA "Feature Option" product attribute into 24 category-specific "…Options" attributes, one per Fortra product line / suite.

> SOURCE-SCOPE WARNING: The source document (`RCAFeatureOptionSplit.txt`) is a **near-stub**. It contains ONLY a two-column table titled "Proposed New Attributes" listing `New Attribute Name` and `New Attribute Developer Name`. It does NOT specify field data types, picklist values, formulas, rounding, defaults, edge cases, Apex/flows/prehooks, or an integration sequence. Everything not present in the source is explicitly marked "NOT SPECIFIED IN SOURCE" below — do not infer or invent these.

---

## Executive summary

- The document is titled **"RCA 'Feature Option' Attribute Split – Proposed New Attributes"**.
- It proposes replacing a single (implied existing) "Feature Option" attribute with **24 new, category-scoped attributes**, each named `<Category> Options` with a corresponding Salesforce developer name `<Category>_Options`.
- Each row is a `(New Attribute Name, New Attribute Developer Name)` pair. No other metadata is provided.

---

## Business requirements / rules

The only requirement expressible from the source: create the 24 named attributes below, each with the exact label and exact developer name given. No selection logic, validation, or ordering rules are stated in the source.

- NOT SPECIFIED IN SOURCE: which object these attributes attach to (e.g., ProductAttributeDefinition / AttributeDefinition / AttributePicklist), field type, allowed values, required/optional, default values, dependency/controlling relationships, or migration/backfill from the old "Feature Option" attribute.

---

## Data model — the 24 proposed attributes (verbatim)

Every pair is quoted exactly as it appears in the source. **TYPE for each = NOT SPECIFIED IN SOURCE.**

| # | New Attribute Name (label) | New Attribute Developer Name |
|---|-----------------------------|------------------------------|
| 1 | Access Assurance Suite Options | `Access_Assurance_Suite_Options` |
| 2 | Application Security Options | `Application_Security_Options` |
| 3 | Beyond Security Legacy Options | `Beyond_Security_Legacy_Options` |
| 4 | Brand Protection Options | `Brand_Protection_Options` |
| 5 | Business Intelligence Options | `Business_Intelligence_Options` |
| 6 | Capacity Management Options | `Capacity_Management_Options` |
| 7 | Cloud Data Protection Options | `Cloud_Data_Protection_Options` |
| 8 | Core Access Insight Options | `Core_Access_Insight_Options` |
| 9 | Cybersecurity Options | `Cybersecurity_Options` |
| 10 | Data Protection Options | `Data_Protection_Options` |
| 11 | Digital Defense Legacy Options | `Digital_Defense_Legacy_Options` |
| 12 | Doc Management Options | `Doc_Management_Options` |
| 13 | Email Security Options | `Email_Security_Options` |
| 14 | File Integrity Monitoring Options | `File_Integrity_Monitoring_Options` |
| 15 | Globalscape Options | `Globalscape_Options` |
| 16 | GoAnywhere Options | `GoAnywhere_Options` |
| 17 | Human Risk Management Options | `Human_Risk_Management_Options` |
| 18 | Network Monitoring Options | `Network_Monitoring_Options` |
| 19 | Offensive Security Options | `Offensive_Security_Options` |
| 20 | Powertech Identity & Access Manager (BoKS) Options | `Powertech_Identity_Access_Manager_BoKS_Options` |
| 21 | Robotic Process Automation Options | `Robotic_Process_Automation_Options` |
| 22 | Systems Management Options | `Systems_Management_Options` |
| 23 | Visual Identity Suite Options | `Visual_Identity_Suite_Options` |
| 24 | Vulnerability Management Options | `Vulnerability_Management_Options` |

### Naming-normalization facts (exact, from the source rows)

These transformations from label → developer name are load-bearing and must be preserved verbatim:

- Row 20 label contains an ampersand and parentheses: **"Powertech Identity & Access Manager (BoKS) Options"**. Its developer name **drops the `&` and the parentheses entirely** and joins tokens with underscores: `Powertech_Identity_Access_Manager_BoKS_Options`. (The `&` is NOT rendered as `And`; the parenthesized `BoKS` becomes the bare token `BoKS`.)
- `GoAnywhere_Options` (row 16) preserves the internal **camelCase "GoAnywhere"** — it is NOT split into `Go_Anywhere`.
- `Globalscape_Options` (row 15) keeps the lowercase-`s` spelling **"Globalscape"** (not "GlobalSCAPE").
- Developer names use spaces → single underscore, and otherwise match the label token casing (e.g., `Cybersecurity_Options`, `Doc_Management_Options`).

---

## Business logic (formulas, rounding, tiers, defaults, edge cases)

- NOT SPECIFIED IN SOURCE. There are no formulas, no rounding mode, no tier precedence, no defaults, and no edge-case handling in the document. Do not fabricate any.

---

## Components (Apex classes / triggers / flows / prehooks)

- NOT SPECIFIED IN SOURCE. The document names no Apex class, trigger, flow, prehook/posthook, or pricing procedure. It is a proposed-attribute list only.

---

## Integration points & sequence

- NOT SPECIFIED IN SOURCE. No integration, no ordering, no system-of-record, no sequence diagram is present.

---

## Assumptions / dependencies / open issues

- ASSUMPTION (not stated, flagged): the split implies a pre-existing single "Feature Option" attribute being decomposed by product line; the document title says "Attribute Split" but the body does not describe the source attribute, its values, or a migration.
- OPEN: object/field type for the 24 attributes is undefined.
- OPEN: whether the 24 categories are mutually exclusive per product, controlling/dependent picklist behavior, and how the old "Feature Option" values map into these 24 buckets.
- OPEN: whether "Legacy" attributes (rows 3 `Beyond Security Legacy Options`, 11 `Digital Defense Legacy Options`) are for deprecated products retained for existing assets only.

---

## CODE-GOVERNING RULES (must not be violated)

Each rule carries the exact spec it enforces. An engineer implementing or refactoring MUST NOT deviate.

1. **Exactly 24 attributes, exact labels + developer names.** Create all and only the 24 rows in the Data-model table. Both the label and the developer name must match character-for-character (including underscores, casing, and the `Options` suffix). Do not rename, merge, or drop any row.

2. **Every developer name ends in `_Options`** and every label ends in ` Options`. Preserve this suffix.

3. **Row 20 mapping is fixed and non-obvious — do not "correct" it.** Label `Powertech Identity & Access Manager (BoKS) Options` MUST map to developer name `Powertech_Identity_Access_Manager_BoKS_Options`. Specifically: the `&` is removed (NOT converted to `And`/`_And_`), the parentheses around `BoKS` are removed, and `BoKS` retains its exact mixed casing. Do not regenerate this developer name from the label with a generic slugifier that would produce a different result.

4. **Preserve exact brand casing in tokens:** `GoAnywhere` (single token, camelCase — never `Go_Anywhere`), `Globalscape` (lowercase `s` — never `GlobalSCAPE`), `Cybersecurity` (single word), `BoKS` (as in rule 3). These are brand spellings, not free to normalize.

5. **Do not invent field type, picklist values, formulas, defaults, or dependencies.** The source specifies none; any such choice is a new decision requiring its own spec/approval, not a refactor of this document.

6. **Preserve the `Legacy` qualifier** on `Beyond_Security_Legacy_Options` and `Digital_Defense_Legacy_Options`; these are distinct from any non-legacy counterpart and must not be collapsed.
