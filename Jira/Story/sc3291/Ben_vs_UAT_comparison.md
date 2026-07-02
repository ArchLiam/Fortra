# Ben's source CSV vs. current FortraUAT — `Order_Submit_Validation__mdt`

Compares **Ben's** [Order Submission Custom Metadata - Source Custom Metadata Records.csv](Order%20Submission%20Custom%20Metadata%20-%20Source%20Custom%20Metadata%20Records.csv)
against the **live UAT** snapshot [UAT_Order_Submit_Validation_live.csv](UAT_Order_Submit_Validation_live.csv) (retrieved 2026-06-01),
keyed on `DeveloperName`. Normalized for format (Ben uses `1/0`; UAT uses `true/false`). Row-level results in
[Ben_vs_UAT_comparison.csv](Ben_vs_UAT_comparison.csv).

## Verdict
- **Same 48 records** — identical `DeveloperName` set (X00001–X00049, no X00009). None added or removed.
- **All structural fields match** — Object, Relationship Field, Field API Name, Field Label, Link Message are identical for every record (after trimming).
- Differences are limited to: **18 `Active__c` flips**, **1 lost error message**, and **5 cosmetic whitespace artifacts in Ben's file**.

**Interpretation:** Ben's CSV is the **baseline** (every primary row active `00001–00034`, the whole Ship-To set inactive `00035–00049`, X00028 carrying its error text). Live UAT is that baseline **after partial remediation** — 18 flags toggled and X00028's message dropped.

---

## 1) `Active__c` flips — 18 records changed since Ben's baseline

### Deactivated in UAT (`true → false`) — 13
These line up with German Wren's "remove / make conditional / auto-populate" directives:

| Dev | Object | Field | Note |
|---|---|---|---|
| X00005 | Places | Street Address Line 2 | conditional (country-specific) — turned off |
| X00006 | Places | Street Address Line 3 | conditional — turned off |
| X00007 | Places | Public | auto-populate — turned off |
| X00008 | Places | Primary | auto-populate — turned off |
| X00010 | Places | Location Type | not editable on layout — turned off |
| X00011 | Contact | Workday Customer Id | ⚠ field doesn't exist (F1) — turned off |
| X00012 | Contact | Business Entity Contact ID | Workday-generated — turned off |
| X00015 | Contact | Mobile Phone Country | conditional — turned off |
| X00016 | Contact | Mobile Phone Code | read-only formula — turned off |
| X00017 | Contact | Mobile | phone not required — turned off |
| X00026 | Order | Workday Contract Type | turned off |
| X00027 | Order | Billing Frequency | not required for Workday — turned off |
| X00034 | Order Product | **Product Code** | ⚠ turned off — but Product Code looks legitimately required; also `OrderItem.ProductCode` doesn't exist (F2). Confirm intent. |

### Activated in UAT (`false → true`) — 5
The Ship-To Contact rows were switched on to mirror the Bill-To set:

| Dev | Object | Field |
|---|---|---|
| X00036 | Contact (Ship-To) | First Name |
| X00037 | Contact (Ship-To) | Last Name |
| X00042 | Contact (Ship-To) | Workday MobilePhone Device Type |
| X00043 | Contact (Ship-To) | Workday MobilePhone Primary |
| X00044 | Contact (Ship-To) | Workday MobilePhone Usage Type |

> ⚠ The activation is **inconsistent**: Ship-To `MobilePhone` itself (X00038) stays inactive while its dependent attributes (Device Type / Primary / Usage Type) are now required — same backwards pattern as Bill-To. Per German, no phone-attribute field should be required unless a phone number exists.

---

## 2) Content difference — 1 record

| Dev | Field | Ben (baseline) | UAT (live) |
|---|---|---|---|
| **X00028** (Order Start Date) | `Error_Message__c` | *"Required Field: Order Order Start Date is required to be populated…"* | **(blank / nil)** |

The error message present in Ben's source is **missing in the org**. Because X00028 is still **active** and the enforcing flow has **no null-guard**, an empty Order Start Date renders a meaningless `"•   Link to Record"` with no text. **Restore the message** (Ben's CSV has the correct text).

---

## 3) Whitespace artifacts in Ben's CSV — 5 (cosmetic; org is clean)

These exist only in Ben's file (export/entry noise); the live org values are clean — **not real differences**:

| Dev | Field | Ben raw | Clean value (UAT) |
|---|---|---|---|
| X00014 | Field_API_Name | `"LastName "` (trailing space) | `LastName` |
| X00037 | Field_API_Name | `"LastName "` (trailing space) | `LastName` |
| X00021 | Field_API_Name | `"\tWorkday_Contract_ID__c"` (leading tab) | `Workday_Contract_ID__c` |
| X00025 | Field_API_Name | `"\tShip_To_Account__c"` (leading tab) | `Ship_To_Account__c` |
| X00028 | Field_API_Name | `"\tEffectiveDate"` (leading tab) | `EffectiveDate` |

> ⚠ **Caveat for any reload:** if Ben's CSV is ever loaded back into the org, these stray tabs/spaces would corrupt the field references (`FieldPopulatedCheck` would receive a `Field_API_Name__c` that matches no real field). **Clean them before any import.**

---

## Net takeaways
1. UAT has moved **18 toggles** past Ben's baseline — remediation is already partly done in the org, so Ben's CSV is **not** current. Treat live as truth.
2. **Restore X00028's `Error_Message__c`** (lost vs. Ben's source).
3. Re-confirm **X00034 (Product Code)** deactivation — likely a real requirement, and it points at a non-existent OrderItem field regardless.
4. Resolve the **phone-attribute vs. phone-source** activation inconsistency on both Bill-To and Ship-To Contact sets.
5. If Ben's CSV is used to redeploy, **strip the 5 whitespace artifacts** first.
