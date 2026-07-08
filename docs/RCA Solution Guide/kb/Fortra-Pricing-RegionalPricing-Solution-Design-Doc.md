# Fortra Pricing — Regional Pricing (Regional Services Pricing) — Solution Design KB

> **Purpose (one line):** Apply country-based pricing multipliers to *Services* products in the Revenue Cloud (RCA) pricing waterfall, keyed off the Quote's shipping country, using a dual Pre-Hook/Post-Hook architecture, CMDT-stored multipliers, and CEILING-to-nearest-$5 rounding.

**Source doc:** `Fortra-Pricing-RegionalPricing-Solution-Design-Doc.txt` (Pricing Regional Pricing Solution Design Document, prepared for Fortra).
**Scope note for the coding agent:** This KB captures the *design document* verbatim where values/formulas/types matter. Several internal inconsistencies in the source are flagged inline as `⚠ SOURCE INCONSISTENCY` — do not silently "fix" one side; treat them as open questions and verify against live metadata/Apex (`RegionalServicesPricingPrehook.cls`, `RegionalPricingCalculator.cls`) before refactoring.

---

## 1. Executive Summary

- Enables Fortra to apply **country-based pricing multipliers** for Services products sold globally.
- Services pricing varies by country; multipliers range from **0.30 (Argentina, 30% of US price)** to **1.015 (United Kingdom, 1.5% premium)**.
- Automatically adjusts list prices based on the **shipping country on the Quote**.
- Covers **177 countries** organized into **five geographic regions: APAC, EU, LATAM, MEA, and North America (NA)**.
- **Dual-hook architecture** within the Revenue Cloud pricing waterfall:
  - **Pre-Hook `RegionalServicesPricingPrehook`** — loads country multipliers from Custom Metadata Type records, looks up shipping country from the Quote context, calculates adjusted prices rounded to the nearest $5, writes results to the context.
  - **Post-Hook `RegionalServicesPricingPosthook`** — finalizes the regional price by writing it to `NetUnitPrice` after the pricing procedure completes; **chains to the Partner Pricing Post-Hook when present**.
- **CMDT `Services_Regional_Pricing__mdt`** stores all 177 country multipliers with effective dating and active/inactive status.
- **Decision Table `DT_Fortra_Regional_Pricing`** provides fast runtime lookups during pricing.
- Products **opt in** via **`Product2.Allow_Regional_Pricing__c`** checkbox (per-product granular control).

### 1.1 Key Features (verbatim points)
- Country-based multipliers for 177 countries across 5 regions (APAC, EU, LATAM, MEA, NA).
- Multiplier range **0.30 (Argentina)** to **1.015 (United Kingdom)**, with **1.0 as default** for unlisted countries.
- Product-level opt-in via `Allow_Regional_Pricing__c` checkbox on Product2.
- Rounding formula: **CEILING to nearest $5** (e.g., **$810.55 rounds UP to $815**).
- CMDT storage for **zero-SOQL-limit** multiplier lookups with effective dating support.
- Decision Table integration for fast runtime country→multiplier lookups.
- Pre-Hook/Post-Hook dual architecture to set and finalize regional pricing in the waterfall.
- Pricing waterfall visibility with **explainer text** showing the multiplier and country applied.

---

## 2. Solution Overview

### 2.1 Process Flow (exact sequence)
1. Revenue Cloud triggers the pricing procedure when a Quote is **saved or repriced**.
2. `RegionalServicesPricingPrehook.execute()` loads **all active** regional pricing multipliers from `Services_Regional_Pricing__mdt` CMDT records.
3. Pre-Hook reads the **SalesTransaction context tag** to extract the shipping country: **`ShipToPlace_Country__c`** or **`ShippingCountry` fallback**.
4. Multiplier for the shipping country is looked up from the loaded map; **countries not in the table default to 1.0** (no adjustment).
5. For each QuoteLineItem: the **current price is read (ListPrice or UnitPrice)**, the adjusted price is calculated as **Price × Multiplier**, then **rounded UP to the nearest $5 using CEILING**.
6. Pre-Hook writes to context:
   - **`UnitPrice`** (adjusted base price)
   - **`RegionalNetUnitPrice__c`** (audit field)
   - **`PrehookRSNetUnitPrice__c`** (Assignment element source)
   - **`RegionalPricingExplainer__c`** (waterfall text)
   - **`Pre_Regional_Price__c`** (original price)
7. After the pricing procedure completes, `RegionalServicesPricingPosthook` reads **`RegionalNetUnitPrice__c`** and writes it to **`NetUnitPrice`** to finalize the regional price as the **last-writer**.

### 2.2 Solution Components (component / type / description)
| Component | Type | Description |
|---|---|---|
| `RegionalServicesPricingPrehook.cls` | Apex Pre-Hook | Loads multipliers from CMDT, looks up shipping country, calculates adjusted prices with $5 rounding, writes to context |
| `RegionalServicesPricingPosthook.cls` | Apex Post-Hook | Finalizes regional price to `NetUnitPrice` after all pricing procedure steps complete; chains to Partner Pricing Post-Hook |
| `Services_Regional_Pricing__mdt` | Custom Metadata Type | Stores 177 country records with multipliers, country codes, regions, subregions, effective dates, active status flags |
| `DT_Fortra_Regional_Pricing` | Decision Table | Runtime lookup table sourced from `Regional_Pricing_Entry__c` mapping country → multiplier for pricing procedure use |
| `Regional_Pricing_Entry__c` | Custom Object | Source data for the Decision Table: country, country code, multiplier, active status, effective dates |
| `Product2.Allow_Regional_Pricing__c` | Custom Field | Checkbox enabling/disabling regional pricing per product (**default: false**) |
| QuoteLineItem Regional Fields | Custom Fields | Audit fields: `PrehookRSNetUnitPrice__c`, `RegionalPricingExplainerItem__c`, `RegionalNetUnitPrice__c`, `Pre_Regional_Price__c`, `Regional_Multiplier__c` |

---

## 3. Requirements

### 3.1 Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Apply country-based pricing multipliers to Services products based on the Quote's shipping country | High |
| BR-002 | Support 177 countries across 5 regions (APAC, EU, LATAM, MEA, NA) with multipliers **0.30 to 1.015** | High |
| BR-003 | **Round all adjusted prices UP to the nearest $5 using CEILING rounding** | High |
| BR-004 | Allow product managers to enable/disable regional pricing per product via a checkbox field | High |
| BR-005 | **Default to multiplier of 1.0** (no adjustment) for countries not in the pricing table | Medium |
| BR-006 | Display the applied multiplier and country in the pricing waterfall calculation details | Medium |
| BR-007 | Support **effective dating** on multiplier records for time-limited pricing adjustments | Low |

### 3.2 Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| TR-001 | Implement Pre-Hook and Post-Hook using **`RevSignaling.SignalingApexProcessor`** interface for dual-stage integration | High |
| TR-002 | Use CMDT (`Services_Regional_Pricing__mdt`) for **zero-SOQL-limit** multiplier storage | High |
| TR-003 | Position Regional Pricing as the **first custom step** in the pricing waterfall, **before Partner Pricing and COLA Uplift** | High |
| TR-004 | Post-Hook chaining to invoke `PartnerPricingPosthook` **if the class exists** (dynamic **`Type.forName`** invocation) | Medium |
| TR-005 | Write `UnitPrice` in Pre-Hook so downstream pricing steps receive the regional-adjusted base price | High |
| TR-006 | **Return SUCCESS even on errors** to avoid blocking the pricing procedure | High |

---

## 4. Assumptions
| ID | Assumption |
|---|---|
| A-001 | All Quotes have a valid shipping country via `ShipToPlace_Country__c` or `ShippingCountry` on the Quote |
| A-002 | `Services_Regional_Pricing__mdt` has been loaded with all 177 country entries |
| A-003 | Multipliers are **denominated in USD and apply BEFORE any currency conversion** |
| A-004 | CEILING rounding (round UP to nearest $5) is the approved business rounding rule for **all** regional price adjustments |
| A-005 | Products without `Allow_Regional_Pricing__c = true` receive **no** regional adjustment regardless of shipping country |
| A-006 | CSV data accuracy for the 177 country multipliers has been verified and approved by Fortra business stakeholders |

---

## 5. Dependencies

### 5.1 Internal (all Status = Complete)
| ID | Dependency |
|---|---|
| D-001 | `Services_Regional_Pricing__mdt` CMDT deployed with all 177 country records |
| D-002 | `Regional_Pricing_Entry__c` custom object deployed to support Decision Table data source |
| D-003 | `DT_Fortra_Regional_Pricing` Decision Table created and refreshed in target org |
| D-004 | `Product2.Allow_Regional_Pricing__c` checkbox field exists on Product2 |
| D-005 | Procedure Plan Definition registers Pre-Hook and Post-Hook in correct sequence positions |
| D-006 | Context Definition includes shipping country fields and regional pricing output fields |

### 5.2 External
| ID | Dependency | Owner |
|---|---|---|
| E-001 | Revenue Cloud license with Decision Table access provisioned | Salesforce Admin |
| E-002 | Regional pricing multiplier data approved | Fortra Finance/Operations |

---

## 6. Technical Design

### 6.1 Architecture Overview
- **Dual-Hook Architecture:** Pre-Hook (`RegionalServicesPricingPrehook`) runs **BEFORE** the pricing procedure to set the regional-adjusted `UnitPrice`; Post-Hook (`RegionalServicesPricingPosthook`) runs **AFTER** to finalize the regional price as `NetUnitPrice`, ensuring it survives any intermediate pricing steps.
- **CMDT Storage:** `Services_Regional_Pricing__mdt` gives zero-SOQL-limit access to 177 country multipliers, platform-cached, deployable across orgs via metadata packages.
- **Decision Table Complement:** `DT_Fortra_Regional_Pricing` is an alternative runtime lookup, sourced from `Regional_Pricing_Entry__c`, for declarative pricing procedure elements.
- **Pricing Waterfall Position (exact order):**
  `List Price → Regional Services Pricing (Pre-Hook) → Pricing Procedure → Regional Services Pricing (Post-Hook) → Partner Pricing → COLA Uplift → Final Price`
- **Post-Hook Chaining:** `RegionalServicesPricingPosthook` dynamically checks for and invokes `PartnerPricingPosthook` via `Type.forName()`, enabling modular hook composition without hard-coded dependencies.
- **Fail-Safe Operation:** Both hooks **always return SUCCESS**, logging errors but never blocking the pricing procedure.

### 6.2 Data Model (object / field / TYPE / description — types verbatim)

**`Services_Regional_Pricing__mdt`** (Custom Metadata Type)
| Field | Type | Description |
|---|---|---|
| `Country__c` | **Text** | Country name used for multiplier lookup (e.g., `'Germany'`) |
| `Country_Code__c` | **Text** | ISO country code for fallback lookup (e.g., `'DE'`) |
| `Region__c` | **Text** | Geographic region: `APAC`, `EU`, `LATAM`, `MEA`, or `NA` |
| `Subregion__c` | **Text** | Geographic subregion for grouping |
| `Multiplier__c` | **Number(4,2)** | Pricing multiplier from 0.30 to 1.015 |
| `Is_Active__c` | **Checkbox** | Whether this country's pricing is active |
| `Effective_Start_Date__c` | **Date** | When this pricing becomes effective |
| `Effective_End_Date__c` | **Date** | When this pricing expires |

> ⚠ **SOURCE INCONSISTENCY (Multiplier precision):** `Multiplier__c` is declared **`Number(4,2)`** (2 decimal places) but the stated range includes **`1.015`** (3 decimals) — a `Number(4,2)` field cannot store `1.015` without truncation/rounding to `1.02` or `1.01`. Verify the live field's scale before relying on 3-decimal multipliers. The same `Number(4,2)` type is declared on `Regional_Pricing_Entry__c.Multiplier__c`.

**`Regional_Pricing_Entry__c`** (Custom Object — Decision Table source)
| Field | Type | Description |
|---|---|---|
| `Country__c` | **Text** | Country name for Decision Table lookup |
| `Country_Code__c` | **Text** | ISO country code |
| `Multiplier__c` | **Number(4,2)** | Regional pricing multiplier |
| `Is_Active__c` | **Checkbox** | Active status flag |
| `Start_Date__c` | **Date** | Effective start date |
| `End_Date__c` | **Date** | Effective end date |

> Note: `Regional_Pricing_Entry__c` uses **`Start_Date__c` / `End_Date__c`**, whereas the CMDT uses **`Effective_Start_Date__c` / `Effective_End_Date__c`**. Do not assume field-name parity across the two.

**`Product2`**
| Field | Type | Description |
|---|---|---|
| `Allow_Regional_Pricing__c` | **Checkbox** | Enables regional pricing for this product (**default: false**) |

**`QuoteLineItem`** (regional fields)
| Field | Type | Description |
|---|---|---|
| `PrehookRSNetUnitPrice__c` | **Currency** | Calculated regional price for the Assignment element in the pricing procedure |
| `RegionalPricingExplainerItem__c` | **Text** | Human-readable explainer text for waterfall display (e.g., `'Regional Services Multiplier: 0.96 (Germany)'`) |
| `RegionalNetUnitPrice__c` | (audit) | Written by Pre-Hook; read by Post-Hook to finalize `NetUnitPrice` |
| `Pre_Regional_Price__c` | (original price) | Original price captured before adjustment |
| `Regional_Multiplier__c` | (audit) | Listed in §2.2 as a QLI regional field; not detailed with a type in §6.2 |

> Note: `RegionalNetUnitPrice__c`, `Pre_Regional_Price__c`, and `Regional_Multiplier__c` are named as QLI audit fields in §2.2 but the source does not give explicit types for them in the §6.2 table — confirm types in live metadata.

### 6.2.1 Field Mappings (Source → Target)
| Source Field | Target Field |
|---|---|
| `Quote.ShipToPlace_Country__c` | Context: `SalesTransaction.ShipToPlace_Country__c` |
| `Quote.ShippingCountry` (fallback) | Context: `SalesTransaction.ShippingCountry` |
| `QuoteLineItem.ListPrice` | Context: `SalesTransactionItem.ListPrice` |
| `QuoteLineItem.UnitPrice` | Context: `SalesTransactionItem.UnitPrice` |
| Context: `UnitPrice` (pre-hook write) | `QuoteLineItem.UnitPrice` (regional-adjusted base) |
| Context: `RegionalNetUnitPrice__c` | `QuoteLineItem.RegionalNetUnitPrice__c` (audit) |
| Context: `PrehookRSNetUnitPrice__c` | `QuoteLineItem.PrehookRSNetUnitPrice__c` |
| Context: `RegionalPricingExplainer__c` | `QuoteLineItem.RegionalPricingExplainerItem__c` |
| Context: `NetUnitPrice` (post-hook write) | `QuoteLineItem.NetUnitPrice` (finalized) |

> Note the **context attribute name differs from the QLI field name** for the explainer: context `RegionalPricingExplainer__c` → QLI `RegionalPricingExplainerItem__c`.

### 6.3 Business Logic (exact formulas / precedence / defaults / edge cases)

**Regional Pricing Formula (verbatim):**
```
Adjusted Price = CEILING((ListPrice × Multiplier) / 5) × 5
```
- Rounds **UP to the nearest $5 increment**.
- **Worked example (verbatim):** `$1,247 × 0.65 = $810.55`; `CEILING(810.55 / 5) × 5 = CEILING(162.11) × 5 = 163 × 5 = $815`.

> ⚠ **SOURCE INCONSISTENCY (base price):** The §6.3 formula uses **`ListPrice`**; §2.1 step 5 says "the current price is read (**ListPrice or UnitPrice**)"; TR-005 / §2.1 step 6 has the Pre-Hook **write `UnitPrice`** as the adjusted base. When refactoring, confirm which input field the calculation actually reads (ListPrice vs UnitPrice) — the two are conflated in the source.

**Country Lookup Priority:**
- Pre-Hook first tries **`ShipToPlace_Country__c`** from the Quote context.
- If blank, falls back to **`ShippingCountry`**.
- **Both country name AND country code are indexed** in the multiplier map for flexible matching.

**Default Multiplier Behavior:**
- Countries **not found** in `Services_Regional_Pricing__mdt` receive a **default multiplier of 1.0** (no price adjustment).
- The Pre-Hook **logs this case and skips the update** (no write for defaulted countries).

**Product Eligibility:**
- Only products with **`Allow_Regional_Pricing__c = true`** receive adjustments.
- Evaluated at the **Decision Table / Pricing Procedure level**.

**Post-Hook Finalization:**
- Post-Hook reads **`RegionalNetUnitPrice__c`** (written by Pre-Hook) and writes it to **`NetUnitPrice`**.
- Ensures the regional price is the **final value even if the pricing procedure's `PriceRevision` step overwrites `UnitPrice`**.

**Post-Hook Chaining:**
- Post-Hook dynamically invokes **`PartnerPricingPosthook` via `Type.forName()`** if the class exists.
- If the class is **not deployed, chaining is silently skipped**.

### 6.4 Integration Points
- **Revenue Cloud Context API:** uses **`Context.IndustriesContext.queryTags()`** to read `SalesTransaction` (shipping country) and `SalesTransactionItem` (line item prices), and **`updateContextAttributes()`** to write regional pricing results.
- **Procedure Plan Definition:** both Pre-Hook and Post-Hook are registered in the Fortra pricing Procedure Plan Definition — Pre-Hook **before** the pricing procedure, Post-Hook **after**.
- **Custom Metadata Type:** `Services_Regional_Pricing__mdt` records queried with **zero governor limit impact**; cached multiplier data for all 177 countries.
- **Decision Table:** `DT_Fortra_Regional_Pricing` provides a declarative lookup from `Regional_Pricing_Entry__c` for pricing procedure formula elements.

---

## 7. Cross-references (repo/domain context — not from source doc)
- Live Apex under active edit: `force-app/main/default/classes/RegionalServicesPricingPrehook.cls` (modified) and new `RegionalPricingCalculator.cls` / `RegionalPricingCalculatorTest.cls` — part of the pricing-refactor workstream (`docs/pricing-refactor/`). The refactor extracts calculator logic from the prehook; verify behavior parity against this design before/after.
- Related pricing hooks in the same waterfall: Partner Pricing (`PartnerPricingService` / `PartnerPricingServiceV2`, `PartnerNetPricePosthook`), COLA Uplift, Hardware Attribute Pricing.
- Prior memory: "Regional services pricing" — `RegionalServicesPricingPrehook` + pricing procedure V9/V21 apply country multiplier **to LIST only**; **NET stays catalog**. Also `RegionalNetReconcileGate` null-guard history (SC-3393 V13). These live-behavior notes may diverge from this design doc; treat live Apex + active pricing procedure (currently V21) as ground truth.

---

## 8. CODE-GOVERNING RULES (an engineer refactoring this MUST NOT violate)

1. **Rounding is CEILING-to-nearest-$5, always UP.** Formula is exactly `Adjusted Price = CEILING((Price × Multiplier) / 5) × 5`. Never use round-half or FLOOR. Golden case: `$1,247 × 0.65 = $810.55 → $815`. (BR-003, A-004, §6.3)
2. **Default multiplier is `1.0` for any country not in the table, and defaulted rows are SKIPPED (no write).** Do not write adjusted prices or audit fields when the country resolves to the 1.0 default. (BR-005, §6.3)
3. **Country lookup order is fixed:** try `ShipToPlace_Country__c` first, fall back to `ShippingCountry` only if blank. The multiplier map must be indexed by **both country name and country code**. (§6.3, A-001)
4. **Product opt-in gate:** only products with `Product2.Allow_Regional_Pricing__c = true` may receive adjustments; default is `false`. Enforced at Decision Table / Pricing Procedure level. (BR-004, A-005, §6.3)
5. **Multipliers are USD-denominated and apply BEFORE currency conversion.** Do not move the adjustment after FX. (A-003)
6. **Both hooks MUST return SUCCESS even on error** — log, never block/fault the pricing procedure. (TR-006, §6.1)
7. **Hooks implement `RevSignaling.SignalingApexProcessor`.** Do not change the interface contract. (TR-001)
8. **Pre-Hook must write `UnitPrice`** (regional-adjusted base) so downstream steps see the adjusted price, AND write the audit set: `RegionalNetUnitPrice__c`, `PrehookRSNetUnitPrice__c` (Assignment-element source), `RegionalPricingExplainer__c` (context) → `RegionalPricingExplainerItem__c` (QLI), and `Pre_Regional_Price__c` (original). (TR-005, §2.1, §6.2.1)
9. **Post-Hook is the last writer of `NetUnitPrice`:** it reads `RegionalNetUnitPrice__c` (Pre-Hook value) and writes `NetUnitPrice`, specifically to survive the pricing procedure's `PriceRevision` step overwriting `UnitPrice`. Do not let any later custom step clobber this without re-establishing the invariant. (§6.3)
10. **Waterfall position is fixed and ordered:** `List Price → Regional (Pre-Hook) → Pricing Procedure → Regional (Post-Hook) → Partner Pricing → COLA Uplift → Final`. Regional Pricing is the FIRST custom adjustment, BEFORE Partner Pricing and COLA. (TR-003, §6.1)
11. **Post-Hook chaining to `PartnerPricingPosthook` is dynamic via `Type.forName()` and silently no-ops if the class is absent.** Do not hard-code a compile-time dependency on Partner Pricing. (TR-004, §6.1, §6.3)
12. **CMDT access must remain zero-SOQL / governor-free.** Use `Services_Regional_Pricing__mdt` CMDT reads (platform-cached), not SOQL against a custom object, for the multiplier map in the Pre-Hook. (TR-002, §6.1, §6.4)
13. **Context I/O uses `Context.IndustriesContext.queryTags()` for reads and `updateContextAttributes()` for writes.** Reads span `SalesTransaction` (shipping country) and `SalesTransactionItem` (line prices). (§6.4)
14. **Support effective dating** on multiplier records (CMDT `Effective_Start_Date__c`/`Effective_End_Date__c`; `Regional_Pricing_Entry__c` `Start_Date__c`/`End_Date__c`) and honor `Is_Active__c`. Only load ACTIVE multipliers. (BR-007, §2.1 step 2)
15. **Scope is 177 countries / 5 regions (APAC, EU, LATAM, MEA, NA); multiplier range 0.30–1.015.** Verify `Multiplier__c` field scale can actually hold 3-decimal values like `1.015` before relying on them (declared `Number(4,2)` — see §6.2 inconsistency). (BR-002, §6.2)
16. **Explainer text format:** `'Regional Services Multiplier: <multiplier> (<Country>)'`, e.g. `'Regional Services Multiplier: 0.96 (Germany)'`, written for waterfall visibility. (§6.2, BR-006)
