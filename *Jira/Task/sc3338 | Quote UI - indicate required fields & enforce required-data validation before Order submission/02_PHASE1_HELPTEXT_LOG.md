# SC-3338 — Phase 1 Build Log: Quote field help text (AC2)

**Status:** ✅ Deployed to FortraUAT 2026-06-12 · Deploy ID `0AfWC00000GJQvG0AX` (6/6 Changed, Succeeded) · verified live via describe.
**Prod:** not yet (Phase 5, after Wren sign-off). Pure `inlineHelpText` — prod-safe.

## What changed
Pre-change source matched live exactly (no drift). Only `inlineHelpText` touched; no functional metadata altered. Quote help-text coverage 36 → 39 fields (3 ADD, 3 KEEP/REPLACE).

| Quote field | Action | New `inlineHelpText` |
|---|---|---|
| `BillToContactId` | ADD | Select the Bill To contact. Required to complete the Order — this contact's First/Last Name and Workday mobile-phone details must be filled in before the Order can be submitted to Workday. Pick a contact related to this Quote's Account. |
| `ContactId` | REPLACE | This is the Fortra Quote Contact and becomes the Order's Ship To contact. Required for Order submission — its First/Last Name and Workday mobile-phone details must be populated. |
| `StartDate` | ADD | Quote start date. Carries to the Order's Start Date (Effective Date), which is required to submit the Order. |
| `Status` | ADD | Quote status. The Order is created automatically once the Quote is converted; check the Required Fields guidance before converting. |
| `Bill_To_Place__c` | KEEP+append | Select the place where invoices should be sent for this quote. Becomes the Order's Bill To Address and is required to submit the Order. |
| `Ship_To_Place__c` | KEEP+append | Select the place where products should be delivered. Becomes the Order's Ship To Address, and its Account becomes the Ship To Account — both required to submit the Order. |

## Notes / follow-ups
- Deploy via full-project `--metadata` hit a **pre-existing** broken file `force-app/main/default/classes/rca_diagnostic.cls-meta.xml` (meta with no `.cls`, untracked, dated May 21 — NOT from this work). Worked around by deploying the 6 field files by `--source-dir` path. Worth cleaning up separately.
- Copy is the proposed wording from `14_SOLUTION_DESIGN.md §1.2`; **pending Wren's final approval** (Phase 0). If Wren revises wording, re-edit the same 6 files and redeploy.
- Em dash (—) used in 2 strings; swap to ASCII hyphen if house style requires.
- Account/Contact-resident required fields (DUNS/Phone/Type, contact names, Workday mobile attrs) **cannot** get Quote help text — they are surfaced by the Phase 2 guidance modal.

## Verification
`sf sobject describe --sobject Quote --target-org FortraUAT` → all 6 fields return the new text; total fields with help text = 39.
