# Fortra — Maintenance (Derived) Pricing — Solution Design (KB)

**Source doc:** `Fortra-Maintenance-Derived-Pricing-Solution-Design.txt` (Solution Design Document, Client: Fortra, Solution: "Maintenance (Derived) Pricing", Consultant: Coastal, Version 1.0, Date June 6, 2026, Author: `[Author Name]` placeholder).
**Domain:** Salesforce Revenue Cloud Advanced (RCA) — pricing procedure + declarative Flow for auto-added maintenance/support quote lines.

## Title + One-line Purpose
Price auto-added maintenance/support quote lines as **source license list price × user-selected maintenance tier rate**, using Revenue Cloud config + one declarative Flow (NO custom Apex pricing prehook), immune to selling-model mismatch and free of repricing price-shrinkage.

## Executive Summary
- Auto-added maintenance and support lines on Revenue Cloud quotes must price as the related **license's list price × a percentage that depends on the maintenance tier the salesperson selects on the line**.
- **Today these lines price at $0 across most of the catalog.** This is the defect being fixed.
- The solution prices them correctly using **Revenue Cloud configuration plus a single declarative Flow — with no custom Apex pricing prehook.**
- It is **immune to the selling-model mismatch** that breaks the platform's native derived-pricing for **roughly a third of the catalog**.
- It also corrects a **price-shrinkage defect** that caused maintenance prices to fall on each repricing.

### Key Features (verbatim rates)
- Prices each maintenance line as **source license list price × the user-selected tier rate (Premier 30%, Standard 20%, Professional 20%).**
- Follows the tier the salesperson selects on each line at quote time — **not a fixed per-product rate** — and updates when they change it.
- Immune to selling-model mismatch: the source list price is **captured as data on the line**, so pricing no longer depends on the native contributor-resolution step that fails when the license and maintenance products use different selling models.
- **No custom Apex pricing prehook** — delivered with **one new field, one Flow, and one pricing-procedure formula change.**
- Eliminates the multiplicative price-shrinkage seen on repeated repricing **by multiplying a stable stamped value instead of the field being written.**

## Business Requirements / Rules
> NOTE: The formal requirement tables in the source are **placeholder stubs only** — every row reads `[Requirement]` / `[Assumption]` / `[Dependency]` with no real content. IDs are defined but empty. The real, binding rules live in the Executive Summary, Solution Overview, and Technical Design prose (captured below). Do not treat the requirement/assumption/dependency IDs as carrying content.

- **BR-001..BR-005** — all `[Requirement]`, Priority **Medium** (no content in source).
- **TR-001..TR-005** — all `[Requirement]`, Priority **Medium** (no content in source).

### Effective business rules (from prose)
1. A salesperson adds a **license** product to a quote.
2. Revenue Cloud **automatically adds the matching maintenance / support line** next to it.
3. The salesperson **selects the maintenance tier** on that line (**Premier, Standard, or Professional**).
4. The maintenance line prices automatically as **license's list price × the selected tier's percentage**, and **re-prices correctly if the tier is changed.**

## Data Model
**No new objects are introduced.** One new field only.

### New custom field
| Field | Object | Type | Purpose / Notes |
|---|---|---|---|
| `Source_List_Price__c` | **QuoteLineItem** | **Currency** | Holds the source license's list price on the maintenance line so pricing does not depend on runtime contributor resolution. **MUST be hydration-mapped into the sales-transaction pricing context (`_v2`).** |

### Existing / reused model elements (not new)
- **Maintenance-to-source relationship**: existing `PriceBookEntryDerivedPrice.ContributingProductId` mapping — **one source product per maintenance product**.
- **Maintenance tier**: existing **`MTD` / `MaintenanceType`** line attribute (Product Attribute, user-selected). **Already configured on 184 maintenance products.**
- **Source price value**: read from **Source license `PricebookEntry.UnitPrice`** in the **quote's price book + currency**, where **`IsDerived = false`** (the non-derived PBE).

### Field mappings (verbatim from §6.2.1)
| Source Field | Target Field |
|---|---|
| Maintenance product → `PriceBookEntryDerivedPrice.ContributingProductId` | Source license `Product2` (the contributor) |
| Source license `PricebookEntry.UnitPrice` (quote price book + currency, `IsDerived = false`) | `QuoteLineItem.Source_List_Price__c` (stamped by Flow) |
| `QuoteLineItem.Source_List_Price__c` (context attribute) | Derived Pricing Formula input (stable base) |
| `MTD` / `MaintenanceType` attribute value (user-selected tier) | Derived Pricing Formula tier selector (IF on Premier / Standard / Professional) |
| Derived Pricing Formula output | `QuoteLineItem.NetUnitPrice` |

## Business Logic (exact formulas, defaults, edge cases)

### 1. STAMP SOURCE LIST PRICE (record-triggered Flow on QuoteLineItem)
When a maintenance / derived line is **created or its source changes**, the Flow:
1. Finds the line's **source license product via the derived-price (`ContributingProduct`) mapping**.
2. Reads that product's list price from its **non-derived price-book entry** (`IsDerived = false`) in the **quote's price book and currency**.
3. Writes the value to **`Source_List_Price__c`**.

### 2. DERIVED PRICING FORMULA (pricing procedure element)
- **Location:** pricing procedure, **List Container 9**, positioned **after the MTD filter**.
- **Element type:** Formula Based Pricing.
- **Exact formula (verbatim):**
  ```
  IF(tier='Premier',0.30,
     IF(tier='Standard',0.20,
        IF(tier='Professional',0.20, <fallback>)
     )
  ) * Source_List_Price__c
  ```
- **Output:** writes result to **`NetUnitPrice`**.
- **CRITICAL correctness rule:** it **multiplies the stamped field (`Source_List_Price__c`), NOT `NetUnitPrice`** — this is what avoids multiplicative shrinkage. (Replaces the **current self-referencing `NetUnitPrice` multiplication**, which is the shrinkage bug.)

### 3. FIRST VALIDATION STEP (gates the rest of the build)
- On a **known selling-model-mismatched product `FIM-FIM-RRM-TECRM`**, confirm whether the native **"Derived Pricing Data Retrieval"** element **hard-errors (stops the reprice)** or **returns $0**.
- **If it hard-errors** → **remove that element** from the procedure (the formula does the full job from the stamped field).
- **If it returns $0** → **retain it** (the formula overwrites the $0).
- This decision is a build gate — the rest of the build depends on its outcome.

### 4. TIER FALLBACK / DATA HYGIENE (edge cases)
- Decide how **blank or off-list tiers** behave. The **current trailing `0`** in the IF chain (the `<fallback>`) **yields $0**.
- **Re-tag the four straggler products** to live tiers or confirm dead:
  - **Premium ×2**
  - **Expert ×1**
  - **platinum ×1** (lowercase as written)
- **Tier rates remain in administrator-editable `Maintenance_Rate` custom metadata.** (Rates are config, not hardcoded in the doc's intent — though the formula snippet inlines 0.30/0.20/0.20.)

## Components (with responsibility)
| Component | Type | Responsibility |
|---|---|---|
| `Source_List_Price__c` | Custom Field (**QuoteLineItem**, **Currency**) | Holds source license list price on the maintenance line so pricing does not depend on runtime contributor resolution. **Must be hydration-mapped into the `_v2` sales-transaction pricing context.** |
| **Stamp Source List Price** | **Record-Triggered Flow (QuoteLineItem)** | On maintenance-line create/update, finds the source license product via the derived-price (`ContributingProduct`) mapping, reads its list price from the PBE in the quote's price book and currency, and writes `Source_List_Price__c`. |
| **Derived Pricing Formula** | Pricing Procedure element (**Formula Based Pricing, List Container 9**) | Rewritten to compute **tier rate × `Source_List_Price__c`** and output to **`NetUnitPrice`**, replacing the current self-referencing `NetUnitPrice` multiplication. |
| **Derived Pricing Data Retrieval** | Pricing Procedure element (**Derived Price**) | Native contributor-resolution element. **Removed** if it hard-errors on selling-model mismatch, or **retained** (its $0 output is overwritten by the formula) if it fails softly — determined by the First Validation Step. |
| **Maintenance tier attribute (`MTD` / `MaintenanceType`)** | Product Attribute (user-selected) | Selected per line at quote time; drives the tier percentage. **Already configured on 184 maintenance products.** |
| `Maintenance_Rate` | Custom Metadata | Administrator-editable store of tier rates. |

**Explicitly NOT used:** custom Apex pricing prehook (approach was tried and **abandoned** — see architecture constraints).

## Integration Points & Sequence
- **Integration points: NONE.** The solution is entirely within Salesforce Revenue Cloud; there are **no external system integrations.**
- **Operational dependency:** a **manual Decision Table refresh** is required after pricing-data or formula changes.

### Runtime sequence
1. Salesperson adds license → RCA auto-adds matching maintenance/support line.
2. **On maintenance-line create / source change**, record-triggered Flow (`Stamp Source List Price`) looks up source license's list price and stamps `Source_List_Price__c`.
3. Salesperson selects tier (`MTD`/`MaintenanceType`: Premier / Standard / Professional).
4. **During pricing**, the procedure reads the user-selected tier attribute and the stamped `Source_List_Price__c` from the line.
5. **Formula Based Pricing element (List Container 9, after MTD filter)** multiplies stamped `Source_List_Price__c` by the tier rate and writes result to `NetUnitPrice`.
6. Re-price on tier change recomputes correctly (multiplies stable stamped base, no shrinkage).

## Architecture Constraints (why this design — from §6.1)
Two platform constraints drive the approach:
1. **For `IsDerived` lines the native derived-pricing element OWNS the line's Net Unit Price and DISCARDS any prehook write** — so a prehook cannot set the price. **Verified empirically; the prehook approach was abandoned.**
2. That same native element **only resolves the source ('contributor') list price when the source license and the maintenance product share a selling model**. **Roughly a third of the catalog mismatches** and the line falls to **$0 or errors**.

**Sidestep:** capture source license list price as **data on the maintenance line** (Flow at line creation) and compute the maintenance price from that stamped field, not from runtime contributor resolution. Because the source price is plain data on the line, selling-model mismatches can no longer zero it; and because the formula multiplies a **stable stamped field** instead of the field it writes to, the price no longer shrinks on repeated repricing.

## Assumptions / Dependencies / Open Issues
- **Assumptions A-001..A-006**: all `[Assumption]` placeholders — **no content in source.**
- **Internal Dependencies D-001..D-005**: all `[Dependency]`, Status **Pending** — **no content in source.**
- **External Dependencies E-001, E-002**: `[Dependency]` / `[Owner]` placeholders — **no content in source.**

### Real open issues / decisions extracted from prose
1. **First Validation Step outcome is unresolved** — whether to remove or retain the native "Derived Pricing Data Retrieval" element depends on testing `FIM-FIM-RRM-TECRM`.
2. **Tier fallback behavior undecided** — current trailing `0` yields $0 for blank/off-list tiers; must decide desired behavior.
3. **Four straggler products (Premium ×2, Expert ×1, platinum ×1)** must be re-tagged to live tiers or confirmed dead.
4. **`Source_List_Price__c` hydration mapping into `_v2` context is mandatory** — pricing fails silently if not mapped.
5. **Manual Decision Table refresh** required after pricing-data or formula changes (operational, easy to forget).

---

## CODE-GOVERNING RULES (an engineer refactoring this MUST NOT violate)
1. **NO custom Apex pricing prehook may set the maintenance line price.** For `IsDerived` lines the native derived-pricing element owns `NetUnitPrice` and discards prehook writes — this was verified empirically. Pricing must be done via the pricing procedure Formula Based Pricing element, not a prehook.
2. **The pricing formula MUST multiply the stamped `Source_List_Price__c`, NEVER `NetUnitPrice` (the field it writes).** Multiplying the output field causes multiplicative price-shrinkage on every reprice. The whole point of the stamped field is to have a stable base.
3. **Formula is exactly:** `IF(tier='Premier',0.30, IF(tier='Standard',0.20, IF(tier='Professional',0.20, <fallback>))) * Source_List_Price__c` → output `NetUnitPrice`. Tier rates: **Premier 30% (0.30), Standard 20% (0.20), Professional 20% (0.20).** Do not swap Standard/Professional off 0.20 or change Premier off 0.30 without spec change.
4. **The Formula Based Pricing element lives in List Container 9, AFTER the MTD filter.** Placement/order matters — it must run after the tier attribute is available.
5. **`Source_List_Price__c` is a Currency field on QuoteLineItem and MUST be hydration-mapped into the `_v2` sales-transaction pricing context.** Without the `_v2` context mapping the formula cannot read the stamped value and the line zeros.
6. **The Stamp Flow resolves the source product via `PriceBookEntryDerivedPrice.ContributingProductId` (one source per maintenance product), and reads `PricebookEntry.UnitPrice` from the NON-derived PBE (`IsDerived = false`) in the QUOTE'S price book AND currency.** Do not read from a derived PBE, a different price book, or ignore currency.
7. **The Stamp Flow must fire on maintenance-line CREATE and when its SOURCE CHANGES** (record-triggered on QuoteLineItem). Missing the update/source-change trigger leaves stale stamped prices.
8. **Do NOT rely on native contributor resolution for pricing** — it fails (S0 or hard-error) for ~1/3 of the catalog on selling-model mismatch. Pricing must come from the stamped line data.
9. **The native "Derived Pricing Data Retrieval" (Derived Price) element is remove-or-retain based on the First Validation Step against `FIM-FIM-RRM-TECRM`:** remove if it hard-errors (stops reprice); retain if it soft-fails to $0 (formula overwrites). Do not blindly delete or keep it without honoring that gate.
10. **Tier rates are stored in administrator-editable `Maintenance_Rate` custom metadata** — treat rates as configuration; do not hardcode business rates in a way that removes admin editability beyond the formula's tier-selection logic.
11. **Blank / off-list tier → fallback yields $0 by design of the current trailing `0`.** Any change to fallback behavior is a deliberate spec decision, not a bug fix.
12. **No external integrations exist** — do not introduce external calls. **A manual Decision Table refresh is required after any pricing-data or formula change** and must remain part of the deploy runbook.
13. **No new objects.** The only new schema element is `Source_List_Price__c` on QuoteLineItem. Reuse existing `MTD`/`MaintenanceType` attribute (already on 184 products) and existing `PriceBookEntryDerivedPrice` mapping.
