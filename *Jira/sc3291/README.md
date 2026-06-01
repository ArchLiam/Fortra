# SC-3291 — Account / Contact / Places Validation Errors on Order Submission for Workday

**Source ticket:** [SC-3291](https://helpsystems.atlassian.net/browse/SC-3291) (parent [SC-3143](../sc3143/))
**Component:** SF RCA — **Resolution comments by:** German Wren (the "in Orange" annotations)
**Verified against FortraUAT** (`liam.jeong.c@fortra.com.uat`) on **2026-06-01** — live metadata retrieved + field-level describe validation.

## TL;DR
The "Required Field" errors at Order submission are **not validation rules**. They are driven by a single
**Custom Metadata Type, `Order_Submit_Validation__mdt`** (48 records), enforced by the active screen flow
**`Fortra_Order_Submission_Check`**. To remove/correct a check you flip the record's **`Active__c`** flag (or
edit the row) — you do **not** touch a validation rule. German Wren's directives translate to activating /
deactivating / making-conditional specific CMDT rows, plus fixing several **config bugs** found during
verification (rows pointing at non-existent or read-only fields).

---

## Enforcement mechanism (verified)
`force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml` (Active screen flow), triggered when a user sets Order **Status → 'Order Complete'**:

1. Loads the Order; if Status ≠ 'Order Complete' it just updates the stage and stops (no checks).
2. `Get_Order_Submit_Validation` queries **all `Order_Submit_Validation__mdt` rows `WHERE Active__c = true`**.
3. Splits rows into OrderItem vs non-OrderItem, loops each, and calls invocable Apex
   **`FieldPopulatedCheck.cls`** (`@InvocableMethod`) to test whether `Field_API_Name__c` is populated on the
   record reached via `Relationship_Field_API_Name__c`.
4. Any empty field → a bullet is added to the error collection using **`Error_Message__c`** + a hard-coded
   `HYPERLINK(..., "Link to Record")`. Errors → `Validation_Error_Screen`, toast **"Order NOT sent to Workday."**, status not advanced.
5. Zero errors → sets `Status='Order Complete'` **and `Workday_Sync_Status__c='Pending'`**, which fires the downstream Workday platform-event sync.

**Notes on the mechanism:**
- **`Active__c` is the on/off switch** — deactivating a row is exactly "REMOVE this validation".
- **`Link_Message__c` is dormant** — the flow never references it (the "Link to Account page." values are decorative; the link label is hard-coded "Link to Record").
- **`FieldPopulatedCheck.cls`** is a stateless helper; it does not read the CMDT and has no concept of "Order submission". The CMDT has no other Apex selector.
- The flow does a flat populated/empty check — it **cannot traverse relationships** (e.g. `Product2.ProductCode`) or evaluate conditional logic. "Required only when phone present" is **not expressible** in the current design without changing the flow/Apex.

---

## ⚠ Configuration-integrity findings (verification, not in the original ticket)
These are bugs in the CMDT config itself, independent of German's remove/keep directives:

| # | Records | Problem | Live `Active__c` | Impact |
|---|---|---|---|---|
| F1 | **X00011, X00041** | `Contact.Workday_Customer_Id__c` **does not exist** on Contact (closest real fields: `Workday_Contact_Id__c`, `Workday_ID__c`, `Workday_Sync_Correlation_Id__c`) | inactive | Latent — if reactivated, `FieldPopulatedCheck` gets a bad field name. Fix the API name or delete the rows. |
| F2 | **X00034** | `OrderItem.ProductCode` **does not exist** (ProductCode lives on Product2/PricebookEntry) | inactive | Latent. A flat check can't reach `PricebookEntry.Product2.ProductCode`. Delete or redesign. |
| F3 | **X00023** | `Order.WorkdayReferenceID__c` is a **read-only formula** ("Legal Entity's Workday Reference ID") but is **required & active** | **active** | If the formula evaluates blank, the user **can never satisfy it** → permanent submission block. |
| F4 | **X00031** | `OrderItem.Billing_Frequency__c` is a **read-only formula** but is **required & active** (note: on Order, X00027, the same-labelled field is an editable picklist) | **active** | Same trap as F3 — unsatisfiable if blank. |
| F5 | **X00033** | `OrderItem.TotalLineTaxAmount` ("Product Subtotal Tax") is a **system-maintained, read-only** currency, required & active | **active** | If tax isn't computed (tax module gap), blank → blocks submission, user can't fix. Confirm Workday actually needs line tax. |
| F6 | **X00028** | `Order.EffectiveDate` rule has **`Error_Message__c = nil`** (only active rule with no message) and the flow has **no null-guard** | **active** | Renders a degraded bullet `"•   Link to Record"` with no explanatory text. Populate the message. |
| F7 | X00010, X00045 | `Places__c.Location_Type__c` **is updateable at FLS/API** (restricted picklist: Billing/Shipping/Regulatory). German's "not editable on the Place form" is a **page-layout** constraint, not field-level | inactive | If it must be required, fix the page layout *or* auto-populate; FLS already allows edit. |

Confirmed-as-stated (German was right): **`Contact.Workday_MobilePhone_International_Phone__c` ("Mobile Phone Code") is a read-only Coastal `CASE()` formula** (ISO country → dialing code). Cannot be user-populated.

---

## Live state & drift (this retrieval)
Full type + all **48 records** retrieved from FortraUAT into
[force-app/.../objects/Order_Submit_Validation__mdt/](../../force-app/main/default/objects/Order_Submit_Validation__mdt/) and
[force-app/.../customMetadata/](../../force-app/main/default/customMetadata/). Object schema (8 fields) unchanged.

Drift vs the prior committed local copy (which had only 20 Contact records):
- **28 records were missing locally** (Account, Order, Order Product, Bill-To Places, the whole Ship-To set).
- **8 records flipped `Active__c` true→false** since 2026-05-29: `X00012/15/16/17` (Bill-To Contact) + `X00035/38/39/40` (Ship-To Contact) — Business Entity Contact ID, Mobile, Mobile Phone Country, Mobile Phone Code.
- Live `Active__c` also differs from the "Source CSV" the reconciliation was built on → the org is **mid-remediation**; treat live (and [UAT_Order_Submit_Validation_live.csv](UAT_Order_Submit_Validation_live.csv)) as truth.

**Currently active rows (25):** X00001-04, X00013-14, X00018-20, X00021-25, X00028, X00029-33, X00036-37, X00042-44.
**Currently inactive rows (23):** X00005-08, X00010, X00011-12, X00015-17, X00026-27, X00034, X00035, X00038-41, X00045-49.

---

## Per-object reconciliation (live-verified)
**Disposition key:** KEEP (active, legit) · DEACTIVATE (turn `Active__c` off) · CONDITIONAL (only-if-phone; **not expressible today** — needs flow change) · AUTOMATE (auto-populate) · FIX-CONFIG (bug F1–F7) · CONFIRM. "Live" = current `Active__c`.

### ACCOUNT — rel. `AccountId` (all fields exist, editable)
| Rec | Field API | Label | Live | German's directive → Disposition |
|---|---|---|---|---|
| X00001 | `Phone` | Account Phone | active | "Not required for Workday." → **DEACTIVATE** |
| X00002 | `DB_DUNS__c` | D&B DUNS | active | Workday account match key → **KEEP** |
| X00003 | `Name` | Account Name | active | **KEEP** |
| X00004 | `Type` | Account Type | active | **KEEP** — serves the "no blank Account Type" guard German asked for. ⚠ but this only gates at Order-Complete; German wanted it blocked **at account creation, before Workday send** — a separate creation-time rule may still be needed. |

### CONTACT — rel. `BillToContactId` (X00011-20) / `ShipToContactId` (X00035-44, mirror)
| Rec (Bill/Ship) | Field API | Label | Live | German's directive → Disposition |
|---|---|---|---|---|
| X00011 / X00041 | `Workday_Customer_Id__c` | Workday Customer Id | inactive | **FIX-CONFIG (F1)** — field doesn't exist; likely Workday-generated → keep off / correct name |
| X00012 / X00035 | `Business_Entity_Contact_ID__c` | Business Entity Contact ID | inactive | "Workday-generated, can't be required." → **DEACTIVATE** ✓ (already off) |
| X00013 / X00036 | `FirstName` | First Name | active | **KEEP** |
| X00014 / X00037 | `LastName` | Last Name | active | **KEEP** |
| X00015 / X00040 | `Workday_MobilePhone_Country_ISO_Code__c` | Mobile Phone Country | inactive | "Only if phone present." → **CONDITIONAL** (off today) |
| X00016 / X00039 | `Workday_MobilePhone_International_Phone__c` | Mobile Phone Code | inactive | Read-only Coastal formula ✓ confirmed → **DEACTIVATE / CONDITIONAL** |
| X00017 / X00038 | `MobilePhone` | Mobile | inactive | "Phone number itself not required." → **DEACTIVATE** ✓ |
| X00018 / X00042 | `Workday_MobilePhone_Device_Type__c` | MobilePhone Device Type | active | "Auto-set when phone provided." → **AUTOMATE** (currently required) |
| X00019 / X00043 | `Workday_MobilePhone_Primary__c` | MobilePhone Primary | active | "Only if phone present." → **CONDITIONAL / AUTOMATE** |
| X00020 / X00044 | `Workday_MobilePhone_Usage_Type__c` | MobilePhone Usage Type | active | "Auto-set when phone provided." → **AUTOMATE** |

> ⚠ Inconsistency: the **source** phone field (`MobilePhone`, X00017/38) is **inactive**, yet its dependent attributes **Device Type / Primary / Usage Type (X00018-20 / X00042-44) are still active and required**. That's backwards from German's rule ("no phone-related field required unless a phone number exists"). Either activate the source check or deactivate/condition the attributes.

### ORDER — rel. `Id` (the Order itself)
| Rec | Field API | Label | Live | Disposition |
|---|---|---|---|---|
| X00021 | `Workday_Contract_ID__c` | Workday Contract Id | active | **CONFIRM** — likely Workday-generated post-sync; if so DEACTIVATE |
| X00022 | `Status` | Status | active | **KEEP** |
| X00023 | `WorkdayReferenceID__c` | Legal Entity's Workday Reference ID | active | **FIX-CONFIG (F3)** — read-only formula required; unsatisfiable if blank |
| X00024 | `Bill_To_Account__c` | Bill To Account | active | **KEEP** (lookup→Account) |
| X00025 | `Ship_To_Account__c` | Ship To Account | active | **KEEP / CONFIRM** — required, yet the Ship-To Contact/Place rule set is mostly inactive (scope mismatch) |
| X00026 | `Workday_Contract_Type__c` | Workday Contract Type | inactive | CONFIRM intent |
| X00027 | `Billing_Frequency__c` | Billing Frequency | inactive | "Not required for Workday. Meant to be Usage Type?" → **DEACTIVATE** ✓ (already off); clarify Usage-Type intent |
| X00028 | `EffectiveDate` | Order Start Date | active | **KEEP** but **FIX-CONFIG (F6)** — populate the nil `Error_Message__c` |

### ORDER PRODUCT (`OrderItem`) — rel. `OrderId`
| Rec | Field API | Label | Live | Disposition |
|---|---|---|---|---|
| X00029 | `LineNumber` | Line Number | active | KEEP (system autonumber) |
| X00030 | `Workday_Contract_Line_Type__c` | Workday Contract Line Type | active | KEEP (only user-editable target) |
| X00031 | `Billing_Frequency__c` | Billing Frequency | active | **FIX-CONFIG (F4)** — read-only formula required |
| X00032 | `Id` | Id | active | KEEP (trivially always present) |
| X00033 | `TotalLineTaxAmount` | Product Subtotal Tax | active | **FIX-CONFIG (F5)** — system tax field; confirm Workday needs it |
| X00034 | `ProductCode` | Product Code | inactive | **FIX-CONFIG (F2)** — not a field on OrderItem |

### PLACES (`Places__c`) — rel. `Bill_To_Address__c` (X00005-10) / `Ship_To_Address__c` (X00045-49, mirror)
| Rec (Bill/Ship) | Field API | Label | Live | German's directive → Disposition |
|---|---|---|---|---|
| X00005 / X00048 | `Street_Address_Line_2__c` | Street Address Line 2 | inactive | "Can't be required for all; some countries only." → **CONDITIONAL** (off today) |
| X00006 / X00049 | `Street_Address_Line_3__c` | Street Address Line 3 | inactive | Same → **CONDITIONAL** |
| X00007 / X00047 | `Public__c` | Public | inactive | "Auto-populate." → **AUTOMATE** ✓ (off) |
| X00008 / X00046 | `Primary__c` | Primary | inactive | "Auto-populate." → **AUTOMATE** ✓ (off) |
| X00010 / X00045 | `Location_Type__c` | Location Type | inactive | **FIX-CONFIG (F7)** — editable at FLS; "not editable" is a page-layout issue. Auto-set or expose on layout. |

*(No `X00009` exists — the DeveloperName sequence skips it.)*

---

## Phone vs Mobile — German's open question (resolved on the SF side)
- The Contact object has a **full mirrored Phone family and Mobile family**: every `Workday_MobilePhone_*` has a `Workday_Phone_*` twin (Country ISO, International code [both read-only formulas], Device Type, Primary, Usage Type, Public). Standard `Phone` (label "Business Phone") and `MobilePhone` both exist.
- **The CMDT references only the Mobile family.** There is **no rule for `Contact.Phone`** at all. So SF-side validation is built around **MobilePhone → `Workday_MobilePhone_*`**.
- German observed the **Phone** field being sent to Workday in testing → that contradicts the SF config. **The integration mapping (MuleSoft) is not in this SF repo** and must be confirmed: if MuleSoft sends `Phone`/`Workday_Phone_*`, the CMDT rules are guarding the wrong family. ⚠ Decide one family and align both the mapping and the rules.
- API-name asymmetry to watch: Phone side is `Workday_Phone_International_Phone_Code__c`; Mobile side is `Workday_MobilePhone_International_Phone__c`.

---

## Success criteria — deliverable status
Target (from ticket): a **Green tab** on the [Integration Workbook sheet](https://docs.google.com/spreadsheets/d/1yM1SWOL6aJojpPSzsl80m5NNji-5Ot5_ytsUT9azIUY/edit?usp=sharing)
with columns Object Label · Object API Name · Relationship Field API Name · Field API Name · Field Label · Dynamic Conditions · Notes.

- ✅ **All required-field sources identified** — single source: `Order_Submit_Validation__mdt` (48 rows), enforced by `Fortra_Order_Submission_Check`. No other validation rule/Apex gates Order submission (only the unrelated `Lock_Currency_At_Order_Activation`).
- ✅ Live values captured + field existence/type verified (this README + the two data files).
- ⬜ **TODO:** transcribe the per-object reconciliation above into the Green tab (the local [SC-3291_Required_Fields_Reconciliation.xlsx](SC-3291_Required_Fields_Reconciliation.xlsx) needs syncing to live `Active__c` and findings F1–F7 — its "Keep" for ProductCode/X00034 is now wrong).
- ⬜ **TODO:** post the findings as a ticket comment.

## Files in this folder
| File | What it is |
|---|---|
| `README.md` | This file — authoritative, live-verified working notes |
| `UAT_Order_Submit_Validation_live.csv` | Live SOQL snapshot of all 48 records (incl. live `Active__c`) — source of truth |
| `UAT_field_validation_results.json` | Structured field-existence/type validation output (per object + consumer-logic analysis) |
| `SC-3291_Required_Fields_Reconciliation.xlsx` | Pre-existing disposition workbook — **needs updating** to live state + findings F1–F7 |
| `Order Submission Custom Metadata - Source Custom Metadata Records.csv` | Earlier "source" export — now stale vs live `Active__c`; kept for history |
