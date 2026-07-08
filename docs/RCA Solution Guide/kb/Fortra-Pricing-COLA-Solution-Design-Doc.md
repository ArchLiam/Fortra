# COLA Uplift Feature — Solution Design (Fortra Revenue Cloud)

> **Purpose (one line):** Automated Cost-of-Living-Adjustment (COLA) percentage uplift applied to **renewal** quote lines by product **Solution Category**, with Contract-level overrides, line-level overrides, and MyCAP out-year uplift enforcement (3% floor + Deal Desk approval) for multi-year annually-billed deals.

- **Source:** `Fortra-Pricing-COLA-Solution-Design-Doc.txt` — "COLA Uplift Feature, Solution Design Document, Fortra Revenue Cloud Implementation, Prepared by Coastal Cloud, April 16, 2026."
- **Author (revision history):** Marc DeBrey. Latest = **v2.0, January 2026** (added MyCAP enforcement).
- **Related MEMORY notes:** `project_cola_v16_v20_reconcile`, `project_sc3346_*` (COLA build/review), `project_sc3384_cola_line_override_fix`, `project_sc3350` (COLA renewal pricing review). This doc is the **design spec**; those notes carry the as-built pricing-procedure (V16→V21) reconciliation state.

---

## 1. Executive Summary

Applies **percentage-based pricing increases to renewal quote lines** based on product Solution Category. Uses the **current Asset price as the base amount** and applies a percentage increase per the product's Solution Category. For multi-year annually-billed deals, the **MyCAP enhancement enforces a standard 3% COLA floor**; pricing below this threshold flags the deal for **Deal Desk approval**. **Fully prepaid multi-year deals are exempt.**

Implementation surface:
- a **Custom Metadata Type** for configurable COLA rates,
- an **Apex trigger** for automatic application during quote-line creation,
- a **Revenue Cloud pricing prehook** for MyCAP enforcement during the pricing waterfall,
- a comprehensive **audit trail** for all COLA applications and modifications.

## 2. Business Goals / Rules

- Standardize annual renewal pricing increases across **all** product Solution Categories.
- Reduce manual pricing errors during renewal quote creation.
- Ensure pricing compliance through automated COLA rate enforcement.
- Support negotiated pricing through Contract-level and line-level overrides.
- Enforce **minimum COLA thresholds** for multi-year annual deals via **MyCAP Deal Desk approval**.
- Maintain complete audit trail for all COLA applications and user modifications.

---

## 3. Data Model

### 3.1 Relationship traversal paths (verbatim)

**Base (CMDT lookup) path:**
```
QuoteLineItem -> QuoteAction (Type=Renew) -> SourceAsset -> Product2 -> Solution_Category__c -> COLA_Uplift_Rules__mdt
```

**Extended (Contract override) path:**
```
QuoteLineItem -> QuoteAction -> SourceAsset -> AssetContractRelationship -> Contract -> COLA_Override_Percent__c
```

When a renewal quote is created, the system traverses this relationship to determine the COLA percentage. For MyCAP enforcement, the prehook reads pricing **context tags** (`SalesTransactionActionType`, `PricingTermCount`, `PricingTermUnit`, `ItemSubscriptionTerm`) during the RC pricing waterfall.

### 3.2 `COLA_Uplift_Rules__mdt` (Custom Metadata Type)

Stores COLA percentage configurations; admins update rates without code deployments.

| Field | Type | Description |
|---|---|---|
| `Solution_Category__c` | **Text(255)** | Solution Category name (**key field**) |
| `Default_Uplift_Percent__c` | **Number(5,2)** | COLA percentage to apply (e.g., `7.85`) |
| `Is_Active__c` | **Checkbox** | Enable/disable this rule without deleting |
| `Effective_Start_Date__c` | **Date** | Optional start date for time-bound rates |
| `Effective_End_Date__c` | **Date** | Optional end date for time-bound rates |
| `Description__c` | **Text(255)** | Description of the Solution Category |

### 3.3 COLA Rates by Solution Category (seed data — verbatim)

| Solution Category | COLA % | Solution Category | COLA % |
|---|---|---|---|
| Brand Protection | **5.00** | HRM / Security Awareness | **9.85** |
| Business Intelligence | **9.85** | Human Risk Management | **9.85** |
| Capacity Management | **5.00** | IBM i Security | **9.85** |
| Cloud Data Protection | **9.85** | Infrastructure Security | **9.85** |
| Core IGA | **9.85** | Managed Detection & Response | **9.85** |
| Data Classification | **5.00** | Managed File Transfer | **7.85** |
| Data Loss Prevention | **9.85** | Network Access Management | **9.85** |
| Digital Risk Protection | **9.85** | Robotic Process Automation | **9.85** |
| Email Security | **5.00** | Secure Collaboration | **9.85** |
| GoAnywhere | **7.85** | Vulnerability Management | **5.00** |
| Host Access | **7.85** | | |

- Distinct rate values in use: **5.00**, **7.85**, **9.85**. (5.00 categories: Brand Protection, Capacity Management, Data Classification, Email Security, Vulnerability Management. 7.85: GoAnywhere, Host Access, Managed File Transfer. All others: 9.85.)

### 3.4 `MyCAP_Rules__mdt` (Custom Metadata Type)

Single **"Global"** record controls MyCAP behavior org-wide. **Seed record:** `MyCAP_Rules.Global` (**DeveloperName = `Global`**).

| Field | Type | Default | Description |
|---|---|---|---|
| `Default_Out_Year_Uplift_Percent__c` | **Number(5,2)** | **3.00** | Standard COLA uplift defaulted to qualifying multi-year annual QLIs |
| `Minimum_Out_Year_Uplift_Percent__c` | **Number(5,2)** | **3.00** | Threshold below which `Quote.Mycap__c` is flagged true |
| `Is_Active__c` | **Checkbox** | **true** | Feature toggle — when false, MyCAP prehook branch takes **no action** |

### 3.5 QuoteLineItem custom fields

> Note: Section 5.1 header says "Nine custom fields" but the table lists **eleven** field API names (below). Treat the field list as authoritative.

| Field API Name | Type | Label | Description |
|---|---|---|---|
| `COLA_Uplift_Percent__c` | **Number(5,2)** | COLA Uplift % | Applied COLA percentage — **users can override** |
| `Default_COLA_Uplift_Percent__c` | **Number(5,2)** | Default COLA % | Original COLA % from rules — **preserved for comparison** |
| `Pre_COLA_Price__c` | **Currency** | Pre-COLA Price | Original Asset price **before** COLA applied |
| `COLA_Solution_Category__c` | **Text** | Solution Category | Solution Category used for COLA lookup |
| `COLA_Applied_Date__c` | **DateTime** | COLA Applied Date | When COLA was **first** applied |
| `COLA_Modified_By__c` | **Lookup(User)** | COLA Modified By | User who last modified COLA % |
| `COLA_Modified_Date__c` | **DateTime** | COLA Modified Date | When COLA % was last modified |
| `COLA_Override_Reason__c` | **Text Area** | Override Reason | Business justification for override |
| `Is_COLA_Overridden__c` | **Checkbox** | Is COLA Overridden | **TRUE if COLA % differs from Default** |
| `COLA_Source__c` | **Picklist** | COLA Source | Tracks override tier: `CMDT Lookup`, `Contract Override`, `Line Override`, `MyCAP Default` |
| `COLACalculatedPrice__c` | **Currency** | COLA Calculated Price | COLA-adjusted price for pricing waterfall |

### 3.6 Quote MyCAP fields

| Field API Name | Type | Label | Description |
|---|---|---|---|
| `Mycap__c` | **Checkbox** | MyCAP | **Apex-derived** flag: true when **any** qualifying renewal QLI has effective uplift **< minimum threshold** |
| `MYCAP_Approval__c` | **Checkbox** | MyCAP Approval | Set by record-triggered **flow** when `Mycap__c` flips to true; triggers Deal Desk approval routing |

### 3.7 Contract COLA override fields

| Field API Name | Type | Label | Description |
|---|---|---|---|
| `COLA_Override_Percent__c` | **Number(5,2)** | COLA Override % | Optional COLA override percentage for **all Assets under this Contract** |
| `COLA_Override_Persist_Until__c` | **Date** | COLA Override Persist Until | Date until which the Contract override remains active. **Null = one-time use.** |

---

## 4. Business Logic

### 4.1 Core price formula (verbatim)

```
UnitPrice = Pre_COLA_Price__c x (1 + COLA%/100)
```
On user override, recalculation is:
```
UnitPrice = Pre_COLA_Price__c x (1 + New COLA%/100)
```
`Pre_COLA_Price__c` preserves the **original `Asset.Price`**, ensuring accurate recalculation regardless of how many times the percentage is overridden.

**Rounding mode:** *not specified in the source.* Worked examples are exact (`$10,000 x 1.0785 = $10,785`; `x 1.05 = $10,500`; `x 1.035 = $10,350`; `x 1.03` implied for MyCAP). Do not invent a rounding rule — preserve whatever the current implementation does unless a spec says otherwise.

### 4.2 Override hierarchy (Section 6 — FOUR tiers, highest → lowest)

| Priority | Tier | Trigger condition | `COLA_Source__c` value |
|---|---|---|---|
| **1 (Highest)** | **Line Override** | User manually edits `COLA_Uplift_Percent__c` on QuoteLineItem | `Line Override` |
| **2** | **MyCAP Default** | Multi-year annual renewal line: **3% floor** applied by pricing prehook | `MyCAP Default` |
| **3** | **Contract Override** | `Contract.COLA_Override_Percent__c` has value AND persist date is valid | `Contract Override` |
| **4 (Default)** | **CMDT Lookup** | Default from `COLA_Uplift_Rules__mdt` by Solution Category | `CMDT Lookup` |

> **Discrepancy to preserve, not resolve:** Section 6 defines the authoritative **4-tier** hierarchy above. Section 7.1 (trigger flow) and Section 10.1 (contract-override flow) both describe a **"three-tier"** hierarchy of Line / Contract / CMDT (MyCAP tier is added by the prehook path, not the trigger path). Interpretation: the **trigger** resolves Line > Contract > CMDT at line creation; the **prehook** injects the MyCAP Default tier during the pricing waterfall for qualifying multi-year annual lines. Both sub-flows are documented below verbatim.

### 4.3 COLA application at line creation — trigger path (Section 7.1)

When a renewal quote line is created, the system automatically:
1. Identifies the quote line as a renewal by checking **`QuoteAction.Type = 'Renew'`**.
2. Retrieves the current Asset price (**`SourceAsset.Price`**) as the Pre-COLA base price.
3. Looks up the product's Solution Category via **`Product2.Solution_Category__c`**.
4. Checks for a valid Contract-level COLA override via **`AssetContractRelationship`**.
5. Applies the (three-tier) hierarchy to determine the COLA percentage.
6. Calculates: `UnitPrice = Pre_COLA_Price__c x (1 + COLA%/100)`.
7. Populates all COLA audit fields (Source, Solution Category, Applied Date, etc.).

### 4.4 Contract-override resolution (Section 10.1)

1. Identifies renewal (`QuoteAction.Type = 'Renew'`).
2. Retrieves `SourceAsset` and its `Price`.
3. Queries **`AssetContractRelationship`** to find the linked Contract.
4. Checks if Contract has `COLA_Override_Percent__c` set **AND** `COLA_Override_Persist_Until__c` is valid.
5. If valid Contract override: uses Contract COLA %, sets `source = 'Contract Override'`.
6. If no valid Contract override: falls back to CMDT lookup by Solution Category.
7. Calculates UnitPrice and populates all COLA fields.

**`COLA_Override_Persist_Until__c` validity logic (verbatim):**

| Value | Behavior |
|---|---|
| **NULL** | Override valid for **all future renewals** (no expiration) |
| **Future date (>= today)** | Override valid; used for this renewal |
| **Past date (< today)** | Override **expired**; system falls back to CMDT lookup |

### 4.5 Override handling (Section 7.3)

When `COLA_Uplift_Percent__c` is changed by a user:
1. Recalculate `UnitPrice = Pre_COLA_Price__c x (1 + New COLA%/100)`.
2. Update `COLA_Modified_By__c` and `COLA_Modified_Date__c`.
3. Set `Is_COLA_Overridden__c = TRUE` **if the new value differs from `Default_COLA_Uplift_Percent__c`**.
4. Set `COLA_Source__c = 'Line Override'`.

### 4.6 MyCAP out-year uplift enforcement — prehook path (Section 7.2)

Runs during the RC pricing waterfall via `COLAUpliftPrehook`.

**Qualifying line detection:**
1. Prehook reads `SalesTransactionActionType` context tag **per line** — only **`'Renew'`** lines are evaluated.
2. **Multi-year annual detection:** `PricingTermCount > 1 AND PricingTermUnit = 'Annual'`, **OR** `ItemSubscriptionTerm > 1` with Annual pricing unit.
3. **Prepaid bypass:** bulk SOQL on **`QuoteLineItemAttribute`** where `AttributeDefinition.DeveloperName = 'PS_Service_Type'` and `AttributePicklistValueId` matches **`'Prepaid'`**.
4. For qualifying **non-overridden** lines: defaults `COLAUpliftPercent__c` to **CMDT-configured value (3%)** via **`updateContextAttributes`**.
5. For **ALL** renewal QLIs: writes audit fields (`Pre_COLA_Price`, `COLA_Source`, `COLA_Solution_Category`, `COLA_Applied_Date`) via context for pricing write-back.

**`Quote.Mycap__c` flag evaluation:**
1. If **ANY** qualifying line's effective uplift **< `MyCAP_Rules.Minimum_Out_Year_Uplift_Percent__c`** → enqueue `flag=true`.
2. If **ALL** qualifying lines meet threshold → enqueue `flag=false`.
3. **`MyCAPFlagApplier` Queueable runs AFTER pricing commits** (the pricing context **forbids DML**).
4. Queueable flips `Quote.Mycap__c` **only when the desired state differs from current value**.
5. Existing flow `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` fires on `Mycap__c` change and sets `MYCAP_Approval__c`.

### 4.7 Edge cases / defaults (from examples + test scenarios)

- **No matching Solution Category → default 0% COLA** (Test Scenario 3). Products without a matching category receive 0% (no uplift).
- **Non-renewal lines** receive **no COLA application** (Scenario 2).
- **Inactive COLA rule** (`COLA_Uplift_Rules__mdt.Is_Active__c = false`) → excluded from processing (Scenario 7).
- **Single-year annual** line → bypassed by MyCAP; COLA stays at CMDT default (Scenario 11).
- **MyCAP rule inactive** (`MyCAP_Rules__mdt.Is_Active__c = false`) → **no MyCAP processing** (Scenario 12; prehook branch takes no action).
- **Prepaid multi-year** → MyCAP skips the line entirely; COLA stays at CMDT default (e.g., 9.85%); **no MyCAP flag evaluation for that line** (Scenario 10 / Example 6).
- **Mixed lines** → only the qualifying line gets 3%; flag set based on **ANY** qualifying line below threshold (Scenario 13).
- **Bulk** → must handle 200-QLI creation within governor limits (Scenario 4).

### 4.8 Worked examples (verbatim)

- **Ex1 Standard:** GoAnywhere MFT, `Asset.Price=$10,000`, COLA 7.85% → `$10,000 x 1.0785 = $10,785`; `Pre_COLA_Price=$10,000`; `COLA_Source='CMDT Lookup'`.
- **Ex2 Line override:** user changes 7.85%→5.00% → `$10,000 x 1.05 = $10,500`; `Is_COLA_Overridden=TRUE`; `COLA_Source='Line Override'`.
- **Ex3 Contract override (multi-renewal):** `Contract.COLA_Override_Percent__c=3.50%`, `Persist_Until=2027-12-31`, `Asset.Price=$10,000` → `x 1.035 = $10,350`; `COLA_Source='Contract Override'`; re-applies automatically on next renewal before 2027-12-31.
- **Ex4 MyCAP default:** Automate Professional (RPA), 3-year annual renewal, CMDT default 9.85% but MyCAP default **3.00%** overrides for qualifying multi-year annual lines → `COLA_Uplift_Percent__c=3.00`, `COLA_Source='MyCAP Default'`, `Quote.Mycap__c=false` (3% meets threshold).
- **Ex5 MyCAP approval trigger:** rep overrides 3.00%→1.00% → `Is_COLA_Overridden__c=true`, effective 1% < 3% min → `Quote.Mycap__c` flips true → flow sets `MYCAP_Approval__c=true` → Deal Desk approval.
- **Ex6 MyCAP prepaid bypass:** Automate Professional with `PS_Service_Type='Prepaid'`, 3-year annual but fully prepaid → MyCAP skips line; COLA stays at CMDT default (9.85%); no flag evaluation.

---

## 5. Components

| Component | Type | Responsibility |
|---|---|---|
| `COLA_Uplift_Rules__mdt` | Custom Metadata | COLA percentages by Solution Category with effective dates |
| `MyCAP_Rules__mdt` | Custom Metadata | Configurable threshold + default uplift % for MyCAP out-year deals (Global record) |
| QuoteLineItem Fields | Custom Fields | Track COLA application, overrides, audit info (11 fields, §3.5) |
| Quote Fields (`Mycap__c`, `MYCAP_Approval__c`) | Custom Fields | MyCAP approval flag fields on Quote |
| `QuoteLineItemTrigger` | **Apex Trigger** | Automatically applies COLA on quote-line creation and handles overrides |
| `COLAUpliftHandler` | **Apex Class** | Business logic for COLA calculation and field population |
| `COLAUpliftPrehook` | **Apex Class (global)** | RC pricing prehook — runs MyCAP detection + defaulting during pricing waterfall |
| `MyCAPFlagApplier` | **Apex Queueable** | Deferred DML for `Quote.Mycap__c` flag flip + QLI audit-field restore (runs after pricing commits) |
| `COLA_Admin` | **Permission Set** | FLS for COLA and MyCAP fields + CMDT access |
| `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` | **Flow** | Sets `MYCAP_Approval__c` when `Mycap__c` flips to true |

---

## 6. Context Attribute Architecture (Section 9) — CRITICAL

RC pricing context attributes have **directional field types** controlling value flow between the QLI and the pricing context. **These field-type directions are load-bearing** — misconfiguring them silently corrupts pricing or nullifies audit fields.

| FieldType | Direction | Behavior | COLA attributes (verbatim) |
|---|---|---|---|
| **input** | QLI → Context | Pricing reads from QLI at start; **cannot write back**. Including input-only attrs in an `updateContextAttributes` batch **poisons the entire batch silently**. | `COLA_Uplift_Percent__c`, `Is_COLA_Overridden__c` |
| **output** | Context → QLI | Pricing writes to QLI at end; prehook writes via `updateContextAttributes` **land only if a pricing procedure step produces the value**. | `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `COLA_Applied_Date__c`, `COLAApplied__c`, `COLAUpliftPercent__c` |
| **inputoutput** | Both | Pricing reads from QLI **AND** writes back. Prehook writes via `updateContextAttributes` are **preserved through the pricing cycle**. | `COLACalculatedPrice__c`, `COLAExplainer__c`, `COLAUpliftPercent2__c` |

> **Important (verbatim):** To ensure audit fields persist through **repricing**, the Context Definition's `SalesTransactionContextExt` must have COLA audit fields set to **`inputoutput`** FieldType. **Output-only attrs get nullified on reprice** unless a pricing procedure step explicitly outputs them.

> **Naming caution:** the **context attribute API names** differ from the QLI custom field API names. E.g., context attr `COLAUpliftPercent__c` / `COLAApplied__c` / `COLACalculatedPrice__c` / `COLAExplainer__c` / `COLAUpliftPercent2__c` are distinct identifiers from custom fields `COLA_Uplift_Percent__c` / `COLACalculatedPrice__c`. Do not conflate underscore vs non-underscore variants.

---

## 7. Integration Points & Sequence

1. **Renewal quote-line creation** → `QuoteLineItemTrigger` (via `COLAUpliftHandler`) resolves Line/Contract/CMDT tier, sets `Pre_COLA_Price__c` from `SourceAsset.Price`, computes `UnitPrice`, stamps audit fields. Requires `QuoteAction` populated with `SourceAssetId` and `Type='Renew'`.
2. **RC pricing waterfall** → `COLAUpliftPrehook` (registered signaling processor) reads context tags, applies MyCAP 3% default to qualifying non-overridden multi-year annual lines via `updateContextAttributes`, evaluates the `Mycap__c` desired state, and enqueues `MyCAPFlagApplier`.
3. **After pricing commits** → `MyCAPFlagApplier` Queueable performs the deferred DML: flips `Quote.Mycap__c` (only if state changed) and restores QLI audit fields. (Pricing context forbids DML, hence the Queueable.)
4. **On `Mycap__c` change** → record-triggered flow `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` sets `MYCAP_Approval__c = true` → routes to **Deal Desk approval**.

**Context tags read by the prehook:** `SalesTransactionActionType`, `PricingTermCount`, `PricingTermUnit`, `ItemSubscriptionTerm`.

---

## 8. Page Layout (Section 8)

A **'COLA Information'** section on the QuoteLineItem page layout:
- COLA Uplift % — **editable** (modifiable by sales)
- Default COLA Uplift % — read-only (original CMDT/Contract default)
- Pre-COLA Price — read-only (original Asset price)
- COLA Source — read-only (which tier provided the value)
- COLA Solution Category — read-only
- COLA Applied Date — read-only
- COLA Modified By/Date — read-only
- Is COLA Overridden — read-only
- COLA Calculated Price — read-only
- COLA Override Reason — **editable**

---

## 9. Dependencies & Assumptions (Section 13)

**Dependencies:**
- Product Catalog hierarchy includes Solution Category level (**Unit > Solution Group > Solution Category > Product**).
- `QuoteAction` object populated during renewal quote creation with `SourceAssetId`.
- `AssetContractRelationship` records link Assets to parent Contracts.
- RC pricing procedure includes `COLAUpliftPrehook` as a **registered signaling processor**.
- Context Definition `SalesTransactionContextExt` has COLA audit fields configured with appropriate FieldType (**inputoutput recommended**).
- `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` flow is **active**.

**Assumptions:**
- **Each product has exactly one Solution Category assignment.**
- `Asset.Price` reflects the **current annual subscription price**.
- COLA rates maintained by admins via Custom Metadata.
- `MyCAP_Rules__mdt.Global` deployed with `Default=3.00`, `Minimum=3.00`.
- `COLA_Source__c` **restricted picklist** includes the `'MyCAP Default'` value.
- `PS_Service_Type` AttributeDefinition exists with a `'Prepaid'` picklist value for prepaid detection.
- `Quote.Mycap__c` and `Quote.MYCAP_Approval__c` **checkbox** fields exist on Quote.

**Open issues / spec gaps (not in source; flagged, not invented):**
- **Rounding mode unspecified** for the `UnitPrice` formula.
- **Tier-count discrepancy** between Section 6 (four tiers incl. MyCAP) and Sections 7.1/10.1 ("three-tier"). See §4.2.
- Section 5.1 says "Nine custom fields" but lists **eleven** (§3.5).

---

## 10. Test Scenarios (Section 12 — expected results verbatim)

| # | Scenario | Expected Result |
|---|---|---|
| 1 | Renewal — standard COLA | Renewal line receives correct COLA % based on Solution Category |
| 2 | Non-renewal quote line | Non-renewal lines do **not** receive COLA application |
| 3 | No matching Solution Category | Products without matching category **default to 0% COLA** |
| 4 | Bulk operation (200 QLIs) | Handles bulk creation within governor limits |
| 5 | COLA override by user | Price recalculates correctly when COLA % is overridden |
| 6 | Pre-COLA Price preservation | `Pre_COLA_Price__c` unchanged after multiple overrides |
| 7 | Inactive COLA rule | Inactive rules excluded from processing |
| 8 | MyCAP: multi-year annual, no override | COLA% defaults to **3.00**, `Mycap__c = false` |
| 9 | MyCAP: multi-year annual, override to 1% | COLA% = 1.00, `Mycap__c = true`, `MYCAP_Approval__c = true` |
| 10 | MyCAP: prepaid line bypass | COLA% stays at CMDT default, line bypassed |
| 11 | MyCAP: single-year annual | COLA% stays at CMDT default, line bypassed |
| 12 | MyCAP: rule inactive | No MyCAP processing when `Is_Active__c = false` |
| 13 | MyCAP: mixed lines | Only qualifying line gets 3%; flag based on ANY qualifying line below threshold |

---

## 11. CODE-GOVERNING RULES (an engineer refactoring MUST NOT violate)

1. **Base-price invariant:** `UnitPrice = Pre_COLA_Price__c x (1 + COLA%/100)`. `Pre_COLA_Price__c` MUST equal the original `SourceAsset.Price` and MUST remain **unchanged across any number of overrides** (Scenario 6). Never recompute UnitPrice off a previously-uplifted price.
2. **Renewal gate:** COLA applies **only** to renewal lines — `QuoteAction.Type = 'Renew'` (trigger) / `SalesTransactionActionType = 'Renew'` (prehook). Non-renewal lines get **no** COLA (Scenario 2).
3. **Four-tier precedence (highest→lowest):** Line Override > MyCAP Default > Contract Override > CMDT Lookup. `COLA_Source__c` MUST reflect the winning tier using exactly the strings `Line Override` / `MyCAP Default` / `Contract Override` / `CMDT Lookup`.
4. **Unmatched category default = 0% COLA** (Scenario 3). Do not throw, and do not substitute any nonzero fallback.
5. **Inactive-rule exclusion:** rows with `COLA_Uplift_Rules__mdt.Is_Active__c = false` MUST be excluded from CMDT lookup (Scenario 7).
6. **Effective-date honoring:** respect `Effective_Start_Date__c` / `Effective_End_Date__c` when both are present on a CMDT rule (time-bound rates).
7. **Contract-override validity:** use `Contract.COLA_Override_Percent__c` only when set **AND** `COLA_Override_Persist_Until__c` is valid — **NULL = valid forever (one-time use per field description, but persists for all future renewals when null-vs-dated semantics apply)**, **future/today = valid**, **past = expired → fall back to CMDT**. Preserve the exact null/future/past branching in §4.4.
8. **`Is_COLA_Overridden__c` semantics:** TRUE **iff** `COLA_Uplift_Percent__c != Default_COLA_Uplift_Percent__c`. On a user edit also stamp `COLA_Modified_By__c`, `COLA_Modified_Date__c`, and set `COLA_Source__c='Line Override'`.
9. **MyCAP qualification:** a line qualifies only if **multi-year annual** — `PricingTermCount > 1 AND PricingTermUnit = 'Annual'` **OR** `ItemSubscriptionTerm > 1` with Annual pricing unit. Single-year annual lines MUST be bypassed (Scenario 11).
10. **MyCAP default only for non-overridden qualifying lines:** default `COLAUpliftPercent__c` to `MyCAP_Rules.Default_Out_Year_Uplift_Percent__c` (3.00). Never overwrite an explicit line override (tier 1 wins over tier 2).
11. **Prepaid bypass:** a qualifying line whose `QuoteLineItemAttribute` has `AttributeDefinition.DeveloperName = 'PS_Service_Type'` and `AttributePicklistValueId` = `'Prepaid'` is **entirely skipped** by MyCAP (no default, no flag evaluation). MUST use **bulk SOQL** (governor-safe).
12. **`Mycap__c` flag rule:** set true if **ANY** qualifying line's effective uplift `< MyCAP_Rules.Minimum_Out_Year_Uplift_Percent__c` (3.00); false only when **ALL** qualifying lines meet threshold.
13. **Feature toggle:** when `MyCAP_Rules__mdt.Global.Is_Active__c = false`, the MyCAP prehook branch MUST take **no action** (no defaulting, no flag evaluation) (Scenario 12).
14. **No DML inside pricing context:** the prehook MUST NOT perform DML. All `Quote.Mycap__c` / QLI audit-field writes MUST be deferred to the `MyCAPFlagApplier` Queueable, which runs **after pricing commits**.
15. **Idempotent flag flip:** `MyCAPFlagApplier` MUST flip `Quote.Mycap__c` **only when the desired state differs from the current value** (avoid redundant DML / flow re-triggers).
16. **Context FieldType direction is load-bearing:**
    - NEVER include an **input**-type attribute (`COLA_Uplift_Percent__c`, `Is_COLA_Overridden__c`) in an `updateContextAttributes` batch — it **silently poisons the whole batch**.
    - Audit fields that must survive **reprice** MUST be **`inputoutput`** on `SalesTransactionContextExt`; **output**-only attributes get nullified on reprice unless a pricing-procedure step explicitly outputs them.
    - Do not conflate context-attribute API names (`COLAUpliftPercent__c`, `COLAApplied__c`, `COLACalculatedPrice__c`, `COLAExplainer__c`, `COLAUpliftPercent2__c`) with QLI custom-field API names (`COLA_Uplift_Percent__c`, `COLACalculatedPrice__c`).
17. **Bulk-safe:** all logic (trigger + prehook) MUST handle 200-QLI creation within governor limits (Scenario 4) — no per-line SOQL/DML.
18. **Field types are fixed:** all percentage fields are `Number(5,2)`; `Pre_COLA_Price__c` / `COLACalculatedPrice__c` are `Currency`; `COLA_Source__c` is a **restricted** picklist that MUST include `'MyCAP Default'`; date/datetime types per §3.5–§3.7. Do not change types in refactors.
19. **One Solution Category per product** is assumed (`Product2.Solution_Category__c` single-valued); resolution logic MUST NOT assume multi-category.
20. **Preserve the MyCAP approval chain:** flag flip → flow `Fortra_Quote_MYCAP_Sale_Approval_Criteria_Record_Triggered` → `MYCAP_Approval__c = true` → Deal Desk. Do not bypass the flow by writing `MYCAP_Approval__c` from Apex.
