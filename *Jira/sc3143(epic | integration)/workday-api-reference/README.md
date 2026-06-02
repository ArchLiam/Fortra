# Workday Revenue Management API references (v46.1)

Field-level references for the three Workday Revenue Management web-service operations called
out in the [SC-3143](../README.md) epic ("Contract Data / Billing Schedule Data / Revenue Data").
These define the values expected to pass through the Workday integration on trigger-activity
creation, and are the source-of-truth field maps for **SC-3134** and its child tickets.

## Files
| File | Operation | SC-3143 label | Data types |
|---|---|---|---|
| [Submit_Customer_Contract.md](Submit_Customer_Contract.md) | `Submit_Customer_Contract` | Contract Data | 152 (19 primary, 88 reference, 45 enum) |
| [Submit_Billing_Schedule.md](Submit_Billing_Schedule.md) | `Submit_Billing_Schedule` | Billing Schedule Data | 148 (22 primary, 84 reference, 42 enum) |
| [Put_Multiple-Element_Revenue_Allocation.md](Put_Multiple-Element_Revenue_Allocation.md) | `Put_Multiple-Element_Revenue_Allocation` | Revenue Data (MEA) | 22 (7 primary, 10 reference, 5 enum) |

Each file has a **Data type index** (jump links) followed by one section per data type, with the
source's `Parameter name / Type/Value / Cardinality / Description / Validations` table. Per-field
validation rules (nested tables in the source's *Validations* column) are rendered inline in that
column. Category: **primary** = data-bearing type; **reference** = `*Object`/`*ObjectID` wrapper;
**enumeration** = `*ReferenceEnumeration` (`@type` allowed values).

## Provenance
- **Source:** public Workday Community docs, Revenue Management **v46.1**
  (`https://community.workday.com/.../Revenue_Management/v46.1/<Operation>.html`). Each file's
  header links the live page plus its WSDL/XSD.
- **Method:** deterministic HTML parse of the raw source pages (no LLM extraction in the final
  output) — lossless, with no truncation. The generator and the downloaded source HTML live in
  `Data/sc3143/` (`generate_docs.py`). Re-run it to regenerate if Workday bumps the API version.
- **Extracted:** 2026-06-01.

> Note: an initial LLM-based extraction under-captured the large Billing page's tail (the
> response/exception and prepaid/installment substructure) because the fetch tool truncates pages
> >~460 KB. The deterministic parse above supersedes it and covers every documented type.
