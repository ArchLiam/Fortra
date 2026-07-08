# Legal Entity Multi-Currency Validation — Revised Solution Design

**Source:** `Revised_Fortra_Legal_Entity_Solution_Designdocx.txt` (Prepared for Fortra, April 2, 2026, 9 pages)
**Purpose (one line):** Decouple transactional-currency selection from Legal Entity assignment on Salesforce Opportunities in Fortra's Revenue Cloud Advanced (RCA), so one Legal Entity record can support multiple transactional currencies, governed by a Custom Metadata Type mapping.

---

## 1. Executive Summary

- Revises the ORIGINAL design's incorrect assumption that **each Legal Entity has a single, fixed currency**.
- Confirmed with Salesforce: a Legal Entity's `CurrencyIsoCode` represents **only its primary currency**; transactional currencies **can differ from the primary currency without negative downstream effects in RCA**.
- Revised solution **decouples currency selection from Legal Entity assignment** by introducing a Custom Metadata Type (CMDT) mapping each Legal Entity to its set of allowed transactional currencies.
- Enables **a single Legal Entity record per business entity** while supporting multi-currency transactions.
- Preserves guardrails: validation that any Opportunity's transactional currency is valid for its assigned Legal Entity, plus guided workflows for scenarios involving existing Quotes.

### 1.1 Key Features (verbatim intent)
1. **Custom Metadata Type (`Legal_Entity_Currency__mdt`)** — Defines which currencies each Legal Entity can transact in, with primary currency designation.
2. **CMDT-Driven Currency Picker** — Screen Flow presents users a filtered list of valid currencies when changing Legal Entity.
3. **Hybrid Validation Approach** — Direct Legal Entity edits allowed when NO Quotes exist (validated by before-save flow); guided Change Legal Entity flow REQUIRED when Quotes exist.
4. **Backward-Compatible Auto-Selection** — New Opportunities inherit Legal Entity from Account and default to the CMDT-defined primary currency.
5. **Currency Sync Deactivation** — Removes the automatic currency-override behavior that forced Opportunity currency to match Legal Entity's `CurrencyIsoCode`.

---

## 2. Solution Overview

### 2.1 Process Flow Summary (exact 6-step sequence)
1. **New Opportunity Created:** Legal Entity auto-populated from Account's Default Legal Entity; currency defaulted to CMDT primary currency for that entity.
2. **User Changes Legal Entity (No Quotes):** User directly edits Legal Entity field; the **before-save flow** validates that the current Opportunity currency is in the CMDT allowed list for the new Legal Entity; if invalid, error directs user to the Change Legal Entity flow.
3. **User Changes Legal Entity (Quotes Exist):** **Validation rule blocks direct edits**; user must use the Change Legal Entity quick action, which presents valid currency options from CMDT and handles Quote conflicts.
4. **Change Legal Entity Flow — Currency Valid:** If the current Opportunity currency IS valid for the new Legal Entity, the Legal Entity is updated **without affecting Quotes or currency**.
5. **Change Legal Entity Flow — Currency Invalid:** If the current Opportunity currency is NOT valid for the new Legal Entity, the user is offered the option to **delete all Quotes and select a new currency, OR cancel**.
6. **Downstream Inheritance:** Quote, Order, and other RCA objects inherit the validated Legal Entity and currency from the Opportunity — **no additional per-object validation required**.

### 2.2 Solution Components (full table, exact API names + types)

| Component (API name) | Type | Description |
|---|---|---|
| `Legal_Entity_Currency__mdt` | Custom Metadata Type | Maps allowed currencies per Legal Entity with primary currency flag. **32 records covering 10 Legal Entities.** |
| `Fortra_Opportunity_Change_Legal_Entity` | Screen Flow (Revised) | Guided workflow for changing Legal Entity with CMDT-driven currency picker. Handles Quote conflicts. |
| `Fortra_Opportunity_LE_Currency_Validation` | Before-Save Flow (New) | Validates that Opportunity currency is in the CMDT allowed list when Legal Entity changes via direct edit. |
| `LE_Change_In_Progress__c` | Custom Field (New) | Checkbox on Opportunity used as a **bypass flag** for the validation rule during flow-driven updates. |
| `Legal_Entity_Requires_Action` | Validation Rule (Modified) | Blocks direct Legal Entity edits when Quotes exist. **Updated to use bypass flag instead of currency mismatch check.** |
| `Fortra_Opportunity_Legal_Entity_AutoSelect` | Record-Triggered Flow (Modified) | Auto-populates Legal Entity and currency on new Opportunities. Updated to use **CMDT primary currency**. |
| `Fortra_Opportunity_Currency_Sync` | Record-Triggered Flow (**Deactivated**) | Previously auto-synced currency to Legal Entity's `CurrencyIsoCode`. Deactivated — currency is now user-controlled. |
| `Quote_Count__c` | Custom Field (Unchanged) | Denormalized count of Quotes on Opportunity. Still used by validation rule and flow logic. |
| `Fortra_Quote_Count_Maintenance` | Record-Triggered Flow (Unchanged) | Increments `Quote_Count__c` when a Quote is created on the Opportunity. |
| `Fortra_Quote_Count_Maintenance_Delete` | Record-Triggered Flow (Unchanged) | Decrements `Quote_Count__c` when a Quote is deleted from the Opportunity. |
| `Opportunity.Change_Legal_Entity` | Quick Action (Unchanged) | Button on Opportunity record page that launches the Change Legal Entity screen flow. |

> NOTE: The design is **declarative/metadata-only** (CMDT, Flows, Validation Rule, custom fields, Quick Action). **No Apex classes or triggers are named or required by this solution.**

---

## 3. Requirements

### 3.1 Business Requirements
| ID | Requirement | Priority |
|---|---|---|
| BR-001 | Each Legal Entity must have exactly **one record** in Salesforce, representing one business entity regardless of how many currencies it supports. | High |
| BR-002 | Users must be able to select a transactional currency from a list of currencies **allowed for the selected Legal Entity**. | High |
| BR-003 | The system must **prevent** users from assigning a currency to an Opportunity that is not valid for the Opportunity's Legal Entity. | High |
| BR-004 | When a new Opportunity is created, the Legal Entity should default from the Account and the currency should default to the Legal Entity's **primary currency**. | High |
| BR-005 | When Quotes exist on an Opportunity, users must be guided through a **structured workflow** to change the Legal Entity, with clear warnings about potential impacts. | High |
| BR-006 | Users should be able to change the Legal Entity **directly (without the flow) when no Quotes exist**, as long as the current currency is valid for the new Legal Entity. | Medium |
| BR-007 | Changing the Legal Entity on an Opportunity must **NOT automatically change the transactional currency**. Currency changes should be explicit user actions. | High |
| BR-008 | The Legal Entity to Currency mapping must be **administrator-configurable without code changes**. | Medium |

### 3.2 Technical Requirements
| ID | Requirement | Priority |
|---|---|---|
| TR-001 | Create a CMDT (`Legal_Entity_Currency__mdt`) with fields for **Legal Entity Name, Currency Code, Is Primary, and Is Active**. | High |
| TR-002 | Implement a **before-save record-triggered flow** on Opportunity that validates the Legal Entity + Currency combination against the CMDT when Legal Entity changes. | High |
| TR-003 | Rewrite the Change Legal Entity screen flow to query CMDT for allowed currencies and present a **dynamic currency picker using `collectionChoiceSet` (API 56.0+)**. | High |
| TR-004 | Add a **bypass checkbox field (`LE_Change_In_Progress__c`)** to Opportunity to allow the screen flow's DML updates to bypass the validation rule. | High |
| TR-005 | Update the `Legal_Entity_Requires_Action` validation rule to **use the bypass flag instead of comparing Legal Entity and Opportunity currencies**. | High |
| TR-006 | **Deactivate** the `Fortra_Opportunity_Currency_Sync` flow to stop automatic currency overrides when Legal Entity changes. | High |
| TR-007 | Modify `Fortra_Opportunity_Legal_Entity_AutoSelect` flow to query CMDT for the Legal Entity's primary currency **instead of using `LegalEntity.CurrencyIsoCode`**. | Medium |
| TR-008 | Create **32 CMDT records covering all 10 active Legal Entities** and their allowed currencies as defined in the Fortra Legal Entities reference document. | High |

---

## 4. Data Model

### 4.1 Custom Metadata Type: `Legal_Entity_Currency__mdt`
Maps allowed transactional currencies per Legal Entity with a primary-currency designation. **32 records total, covering 10 Legal Entities.** Fields (per TR-001):

| Field (label from TR-001) | Type (inferred from role; source names label only) | Purpose |
|---|---|---|
| Legal Entity Name | Text (metadata) | Legal Entity the row applies to. Must **exactly match** the Legal Entity record name in the org (see A-002 / D-004). |
| Currency Code | Text (ISO currency code) | An allowed transactional currency ISO code for the Legal Entity. |
| Is Primary | Checkbox | Marks the primary/default currency for that Legal Entity (used for new-Opportunity default). |
| Is Active | Checkbox | Whether the mapping row is active. |

> The source specifies **field roles/labels only** (TR-001); exact API field names and precise metadata field data types beyond the above are NOT given in the source. Do not invent API names.

### 4.2 Custom Fields on Opportunity
| Field API Name | Type | Status | Purpose |
|---|---|---|---|
| `LE_Change_In_Progress__c` | Checkbox | New | Bypass flag set by the screen flow so its DML updates bypass the `Legal_Entity_Requires_Action` validation rule. |
| `Quote_Count__c` | (Number — denormalized count) | Unchanged | Denormalized count of Quotes on the Opportunity; consumed by the validation rule and flow logic. Maintained by the Quote Count Maintenance flows. |
| `Legal_Entity__c` | Lookup to `LegalEntity` | Pre-existing (D-003) | The Opportunity's assigned Legal Entity. |

### 4.3 Related fields on other objects
| Field | Object | Type | Notes |
|---|---|---|---|
| `Default_Legal_Entity__c` | Account | Lookup | Source for auto-populating Legal Entity on new Opportunities (A-007, D-002). |
| `CurrencyIsoCode` | LegalEntity / Opportunity | Standard multi-currency field | LegalEntity's `CurrencyIsoCode` = **primary currency ONLY** (no longer the enforced transactional currency). |

---

## 5. Business Logic / Rules (exact behavior)

- **New Opportunity default:** Legal Entity ← `Account.Default_Legal_Entity__c`; currency ← CMDT primary currency for that Legal Entity (the row where `Is Primary` = true). Sourced by `Fortra_Opportunity_Legal_Entity_AutoSelect`. Must NOT use `LegalEntity.CurrencyIsoCode` for the default currency (TR-007).
- **Direct edit path (No Quotes, `Quote_Count__c` == 0):** Allowed. `Fortra_Opportunity_LE_Currency_Validation` (before-save) checks that the current Opportunity currency is in the CMDT allowed list for the NEW Legal Entity. If NOT valid → block/error, directing the user to the Change Legal Entity flow.
- **Blocked edit path (Quotes Exist, `Quote_Count__c` > 0):** `Legal_Entity_Requires_Action` validation rule blocks direct Legal Entity edits; user must use the `Opportunity.Change_Legal_Entity` quick action.
- **Validation-rule bypass:** The screen flow sets `LE_Change_In_Progress__c` = true before its DML so the validation rule allows the flow-driven update. The validation rule keys off this bypass flag — **NOT** a currency-vs-Legal-Entity comparison (TR-005).
- **Change Legal Entity flow — currency valid:** Update Legal Entity only; do NOT touch Quotes or currency.
- **Change Legal Entity flow — currency invalid:** Offer user two choices only — (a) **delete ALL Quotes and select a new currency**, or (b) **cancel**. (Reflects platform limit A-004: currency cannot change on an Opportunity that has existing Quote Line Items.)
- **Currency independence:** Changing Legal Entity must NOT auto-change transactional currency (BR-007). The old auto-sync behavior is removed by deactivating `Fortra_Opportunity_Currency_Sync` (TR-006, D-005).
- **Downstream:** No per-object currency/Legal-Entity validation on Quote/Order/Contract/Asset; they inherit from Opportunity (A-003).

> The source contains **no numeric formulas, rounding modes, or tier-precedence logic** — this is a validation/guardrail design, not a pricing/calculation design.

---

## 6. Components / Sequencing (deploy order)

Declarative components (from §2.2). Critical ordering constraint from D-005 / TR-006:
1. Ensure prerequisites exist: `Quote_Count__c` + Quote Count Maintenance flows (D-001), `Account.Default_Legal_Entity__c` (D-002), `Opportunity.Legal_Entity__c` (D-003), matching Legal Entity records (D-004).
2. **Deactivate `Fortra_Opportunity_Currency_Sync` BEFORE deploying the revised screen flow** (D-005 — prevents conflicting currency behavior).
3. Deploy CMDT `Legal_Entity_Currency__mdt` + its 32 records (TR-001, TR-008).
4. Deploy `LE_Change_In_Progress__c` field (TR-004).
5. Deploy/modify `Legal_Entity_Requires_Action` validation rule to use bypass flag (TR-005).
6. Deploy `Fortra_Opportunity_LE_Currency_Validation` before-save flow (TR-002).
7. Deploy revised `Fortra_Opportunity_Change_Legal_Entity` screen flow with `collectionChoiceSet` picker (TR-003).
8. Modify `Fortra_Opportunity_Legal_Entity_AutoSelect` to read CMDT primary currency (TR-007).

---

## 7. Integration Points & Downstream Sequence

- **No external system integration** in this solution. All logic is native Salesforce (RCA / Revenue Cloud Advanced).
- Downstream RCA objects (**Quote, Order, Contract, Asset**) **inherit** validated Legal Entity + currency from the Opportunity; there is deliberately **no additional per-object validation** (A-003, step 6 of §2.1).
- External confirmation dependency (E-001): Salesforce confirmed transactional-currency independence does not impact RCA billing, asset creation, or order processing.

---

## 8. Currencies & Legal Entities (exact values from source)

- **Required active currency ISO codes (A-001):** `USD, EUR, GBP, CAD, AUD, JPY, CHF, NZD, ARS`.
- **10 active Legal Entities** covered by 32 CMDT records (exact per-entity currency lists are in the external **Fortra Legal Entities Confluence reference document** (E-002), NOT enumerated in this design doc).
- **Renewal-only Legal Entities (A-008):** `Terranova Worldwide Corporation`, `Tripwire Inc.` — still included in CMDT for existing Opportunity management even though NOT used for new sales.

---

## 9. Assumptions (verbatim)

| ID | Assumption |
|---|---|
| A-001 | Org has multi-currency enabled and all required ISO codes (USD, EUR, GBP, CAD, AUD, JPY, CHF, NZD, ARS) are configured as active currencies. |
| A-002 | Legal Entity names in the org **exactly match** names in the CMDT records. A pre-deployment data audit will verify this. |
| A-003 | Validation of Legal Entity + Currency is required **only at the Opportunity level**; downstream objects (Quote, Order, Contract, Asset) inherit from the Opportunity. |
| A-004 | The Salesforce platform limitation **preventing currency changes on Opportunities with existing Quote Line Items** remains in effect. |
| A-005 | `collectionChoiceSet` flow element (available since **API 56.0**) is supported in target org. **Project uses API version 64.0.** |
| A-006 | Transactional currency can differ from the Legal Entity's primary `CurrencyIsoCode` without causing issues in Revenue Cloud billing, asset management, or order processing. |
| A-007 | Existing `Account.Default_Legal_Entity__c` lookup field continues to be used for auto-populating Legal Entity on new Opportunities. |
| A-008 | Renewal-only Legal Entities (Terranova Worldwide Corporation, Tripwire Inc.) should still be included in the CMDT for existing Opportunity management, even though not used for new sales. |

---

## 10. Dependencies

### 10.1 Internal
| ID | Dependency | Status |
|---|---|---|
| D-001 | `Quote_Count__c` field and Quote Count Maintenance flows must be deployed and operational before the validation rule and screen flow can function. | Complete |
| D-002 | `Account.Default_Legal_Entity__c` lookup field must exist on Account for the auto-select flow to function. | Complete |
| D-003 | `Opportunity.Legal_Entity__c` lookup field to LegalEntity must exist. | Complete |
| D-004 | Legal Entity records must exist in the org with names matching the CMDT records exactly. | **Verification Required** |
| D-005 | `Fortra_Opportunity_Currency_Sync` flow must be deactivated **BEFORE** deploying the revised screen flow to prevent conflicting currency behavior. | **Pending** |

### 10.2 External
| ID | Dependency | Owner | Status |
|---|---|---|---|
| E-001 | Salesforce confirmation that transactional-currency independence from Legal Entity primary currency does not impact RCA billing, asset creation, or order processing. | Salesforce / Fortra | Complete |
| E-002 | Fortra Legal Entities Confluence reference document provides the authoritative list of Legal Entities, primary currencies, and allowed currencies. | Fortra Business Operations | Complete |

---

## 11. CODE-GOVERNING RULES (do NOT violate when refactoring/implementing)

1. **One Legal Entity record per business entity** (BR-001). Do NOT create multiple LegalEntity records to represent per-currency variants.
2. **CMDT is the single source of allowed currencies** — `Legal_Entity_Currency__mdt` with 4 field roles: Legal Entity Name, Currency Code, Is Primary, Is Active (TR-001). Currency allow-lists MUST be read from this CMDT, never hard-coded in Apex/Flow. Admin-configurable, no code change (BR-008).
3. **New-Opportunity currency default = CMDT primary currency** (the `Is Primary` row), NOT `LegalEntity.CurrencyIsoCode` (TR-007, BR-004). `Fortra_Opportunity_Legal_Entity_AutoSelect` must query CMDT.
4. **Legal Entity default = `Account.Default_Legal_Entity__c`** (A-007, BR-004). Do not remove/repurpose this lookup.
5. **Changing Legal Entity must never auto-change transactional currency** (BR-007). The old `Fortra_Opportunity_Currency_Sync` behavior MUST stay deactivated (TR-006). Do NOT reactivate or re-implement currency auto-sync.
6. **Deactivate `Fortra_Opportunity_Currency_Sync` BEFORE deploying the revised screen flow** (D-005) — ordering is load-bearing to avoid conflicting currency writes.
7. **Hybrid path branching keys on `Quote_Count__c`:** No Quotes → direct edit allowed, validated by the before-save flow `Fortra_Opportunity_LE_Currency_Validation` (TR-002, BR-006). Quotes exist → direct edit BLOCKED by `Legal_Entity_Requires_Action`, must use the `Opportunity.Change_Legal_Entity` quick action (BR-005). Preserve `Quote_Count__c` maintenance flows (`Fortra_Quote_Count_Maintenance` increment, `Fortra_Quote_Count_Maintenance_Delete` decrement) — the validation depends on an accurate count (D-001).
8. **Validation rule `Legal_Entity_Requires_Action` bypass mechanism:** rule must gate on the `LE_Change_In_Progress__c` checkbox bypass flag, NOT on a Legal-Entity-vs-Opportunity currency comparison (TR-005). Any flow doing legitimate flow-driven Legal Entity DML MUST set `LE_Change_In_Progress__c = true` to pass the rule (TR-004).
9. **System must reject any Opportunity currency not in the CMDT allowed list for its Legal Entity** (BR-003). The before-save flow validates the LE+Currency combination on Legal Entity change; invalid → error directing user to the Change Legal Entity flow.
10. **Change Legal Entity flow, currency-invalid branch offers exactly two options:** delete ALL Quotes + pick a new currency, OR cancel (§2.1 step 5). This is forced by platform limit A-004 (cannot change currency while Quote Line Items exist). Do not attempt to silently change currency while Quotes/QLIs exist.
11. **Change Legal Entity flow, currency-valid branch:** update Legal Entity ONLY; do not delete Quotes or alter currency (§2.1 step 4).
12. **Currency picker uses `collectionChoiceSet`** (dynamic, from CMDT) and requires **API >= 56.0**; project uses **API 64.0** (TR-003, A-005). Keep flow API version compatible.
13. **Validation is Opportunity-level ONLY** (A-003). Do NOT add per-object Legal-Entity/currency validation on Quote, Order, Contract, or Asset — they inherit from Opportunity.
14. **CMDT must contain 32 records for all 10 active Legal Entities** (TR-008), INCLUDING renewal-only entities `Terranova Worldwide Corporation` and `Tripwire Inc.` (A-008), even though these are not used for new sales.
15. **Legal Entity names must match exactly between org records and CMDT** (A-002, D-004). String-match is the join key; a rename on either side breaks the mapping.
16. **Required active currencies:** USD, EUR, GBP, CAD, AUD, JPY, CHF, NZD, ARS (A-001). CMDT currency codes must be among configured active org currencies.
17. **Authoritative currency/entity data lives in the external Fortra Legal Entities Confluence doc** (E-002), not in this design doc. Source per-entity allowed-currency lists from there.
18. **This is a declarative/metadata solution** — no Apex is named or required. Prefer Flow + Validation Rule + CMDT; do not introduce Apex triggers unless a new requirement demands it.
