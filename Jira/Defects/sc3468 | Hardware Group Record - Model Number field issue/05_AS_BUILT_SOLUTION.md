# 05 — As-Built Solution (deployed)

**Status:** ✅ Deployed to FortraUAT 2026-06-28 · backfill complete · symptom verified resolved
**Direction chosen:** **Dual-write** (decided with assignee, overriding the dossier's original display-only recommendation).

## Why dual-write (not display-only)

The business intent is that the picked model **must land in `Model_Number__c`** (the field the reporter
sees as broken, and the field BSS / model-search / Power-split all read). The dossier originally recommended
keeping `iSeries_Model__c` canonical and only fixing the display, on the grounds that `Model_Number__c` is
~99.99% legacy migration GUIDs. That is a data-cleanliness observation, **not** a functional blocker — so
the assignee elected to populate `Model_Number__c` going forward.

We keep writing `iSeries_Model__c` (rather than remap-only to `Model_Number__c`) for three reasons:
1. The reporter explicitly asked to keep `iSeries_Model__c`.
2. **UI consistency:** `iSeries_Feature_Code__c` is a dependent picklist controlled by `iSeries_Model__c`,
   and the create/edit modal's Feature Code dropdown is driven by it at runtime. If `iSeries_Model__c`
   weren't stored, re-opening a record in the edit modal would show its saved Feature Code as
   invalid/unavailable (no controlling value).
3. `iSeries_Model__c` is the typed, validated 92-value picklist; `Model_Number__c` is free text.

> ⚠️ **Correction (smoke-test finding 2026-06-28):** an earlier draft claimed Salesforce *hard-fails at the
> DML tier* when a Feature Code is saved without its controlling `iSeries_Model__c`. The smoke test's
> negative path **disproved** this — a direct `insert` of a Feature Code with a null controlling field
> **succeeded**. The dependency is **UI-enforced, not DML-enforced**. Dual-write is still the correct choice
> (reasons 1–3 above), but remap-only would have caused UI inconsistency, not an Apex/DML save error.

So the solution writes the picked value to **both** fields.

## What was changed (deployed)

Deployed from `Data/sc3468/retrieve/` — Deploy ID **`0AfWC00000Ga28X0AR`** (validate **`0AfWC00000Ga25J0AR`**),
`RunSpecifiedTests: HardwareGroupControllerTest` → **28/28 pass**.

### `hardwareGroupManager` (LWC)
- **Dual-write** — `handleCreateHardware` now sets `hardwareData.Model_Number__c = this.newHardware.iSeriesModel`
  alongside the existing `hardwareData.iSeries_Model__c = ...` write.
- **Display fallback (robustness)** — new `decorateModel()` helper computes
  `modelDisplay = iSeries_Model__c ?? Model_Number__c`; datatable "Model" columns + both detail cards +
  all data-entry points (search ×2, create, groups map, edit-mode) bind to `modelDisplay`. Lets legacy rows
  display correctly even before/without backfill.
- **Relabel** — both "Model Number" comboboxes → "iSeries Model" (kept per assignee; trivially revertible if
  the reporter prefers "Model Number").
- **Cleanup** — removed the genuinely-dead `modelNumber` state + handler case.

### `HardwareGroupController` (Apex)
- Added `iSeries_Model__c` to the 4 display SELECTs: `getExistingGroups` (cls:59), `searchHardware` (cls:117),
  `getHardwareById` (cls:272 — the SC-3423 read-after-write path), `getUnassignedHardware` (cls:431).
- **Kept** the `Model_Number__c` write branch (createHardwareRecord) — now load-bearing for the dual-write.

> Source-drift note: live had the **SC-3423** fix (`getHardwareById` + `NULLS LAST`/`LIMIT 2000`) that the
> repo `Org Data/_src` copy lacked. All edits were made against the live-retrieved copy in
> `Data/sc3468/retrieve/`. `Org Data/_src` remains pre-SC-3423 and should be resynced separately.

## Data backfill (deployed)

Anonymous Apex (`Data/sc3468/backfill.apex`) set `Model_Number__c = iSeries_Model__c` for the
**44** rows that had `iSeries_Model__c` populated but `Model_Number__c` null. Backup of the prior state:
`Data/sc3468/backfill_preflight_backup.csv`. Post-checks: 0 diverted rows remain; HW-0717956 now
`Model_Number__c = 500`. No triggers / record-triggered flows fire on `Hardware__c` update (verified).

## Headless smoke test (2026-06-28)

Self-cleaning anonymous Apex (`Data/sc3468/smoke_test.apex`), run via a verify workflow (run + source audit +
cleanup/coverage critique). Results:

- **Persist/read path — PASS.** `createHardwareRecord` with an iSeries payload →
  `Model_Number__c=500`, `iSeries_Model__c=500`, `iSeries_Feature_Code__c=2140`; `getHardwareById` returns
  `iSeries_Model__c=500` and `Model_Number__c=500` (proves the modified SELECT). `getFeatureCodeOptions('500')`
  resolved 4 options.
- **Deployed source — PASS.** Live FortraUAT retrieve confirms the dual-write (`hardwareGroupManager.js:752`)
  and `iSeries_Model__c` in all 4 display SELECTs (cls:59/117/272/431).
- **Cleanup — PASS.** 0 stray `SC3468*` Hardware/Partition records left behind.
- **Negative path:** DML-insert of a Feature Code without its controlling field **succeeded** → dependency is
  UI-enforced only (see correction above).

⚠️ **Coverage gap (smoke only):** the smoke test handed the controller a Map that *already* contained both
fields, so it validated the controller persist/read path but **did not execute the JS line that builds the
dual-write payload**. → **CLOSED by live UI test below.**

### ✅ Live UI confirmation (2026-06-29)

Assignee created an iSeries hardware through the real **Quote Line Flex Panel → Hardware Groups** modal on
Quote 00781364 (AB Test Account). Result record **HW-0717961** (`a0nWC000001wlvdYAA`):
`Hardware_Platform__c=iSeries`, **`Model_Number__c=300`**, `iSeries_Model__c=300`, `iSeries_Feature_Code__c=2040`,
attached to the "Test Hardware" QuoteLineGroup. This proves the dual-write line (`hardwareGroupManager.js:752`)
fires at runtime in the browser — **SC-3468 verified end-to-end.** (Note: the group's "(0) / No items to
display" is the Quote Line *Item* count — unrelated to the hardware association, which is set correctly.)

## Remaining / recommended

- **UI smoke test (closes the only open gap):** create a new iSeries hardware via the modal → confirm the
  model shows in the card/grid and the new `Hardware__c` has both `Model_Number__c` and `iSeries_Model__c`
  set, and the Feature Code dropdown still filters.
- **Data steward:** 3 pre-existing dual-populated rows (`Model_Number__c` = full name, `iSeries_Model__c` = code)
  were intentionally left untouched — decide canonical value per row.
- **Production:** this fix is UAT-only so far; promote with the same component set when ready.
- **Follow-ups unchanged:** BSS-on-activation parity, model-search parity (`cls:103`, `HardwareManagementController:324-325`),
  `PowerOrderSplittingService` clone copy (cls:410/424) — now partly mitigated since `Model_Number__c` is populated.
