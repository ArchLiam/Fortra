# 01 — Root Cause Analysis

## Symptom (as reported)

On the **Create New Hardware Group** modal, selecting a value in the **"Model Number"** picklist does not
appear on the Hardware record's "Model Number" field. The Salesforce Inspector shows the value landing in
`iSeries_Model__c` instead. Reporter's hypothesis: *"the UI field is just mapped to the wrong DB field. We
believe `iSeries_Model__c` is the correct field to keep."*

## Actual root cause: a write-target ≠ read-target mismatch (not a wrong mapping)

The modal **saves the model correctly** to `iSeries_Model__c`. The defect is that **every place that
displays the model reads a *different* field (`Model_Number__c`)**, which is null for iSeries hardware. So
the saved value is invisible, creating the impression that it "didn't save."

```
USER picks "Model Number" in modal
        │  (combobox is LABELED "Model Number" but BOUND to iSeriesModel)
        ▼
newHardware.iSeriesModel                         hardwareGroupManager.js:622-631
        │
        ▼
hardwareData.iSeries_Model__c = ...              hardwareGroupManager.js:737   ← only model write
        │
        ▼
Hardware__c.iSeries_Model__c  ✅ SAVED           HardwareGroupController.cls:170-171
        ╎
        ╎   (Model_Number__c key is NEVER sent → cls:204-205 "Legacy" branch is dead code)
        ╎
        ▼
DISPLAY reads Hardware__c.Model_Number__c  ❌ NULL for iSeries
   • detail cards          hardwareGroupManager.html:312, :611   → blank
   • datatable "Model" cols hardwareGroupManager.js:121, :130    → blank
   • edit-mode hydration   hardwareGroupManager.js:822           → blank
```

The combobox **label** "Model Number" on an `iSeries_Model__c`-bound control is the cosmetic trigger that
led the reporter to conclude "wrong field." In reality the write is correct; the read is wrong.

## Evidence chain (file:line)

### WRITE path — value goes to `iSeries_Model__c`
- **Combobox binding (two identical blocks):**
  `hardwareGroupManager.html:210-218` and the duplicate at `:504-512` —
  `<lightning-combobox label="Model Number" options={iSeriesModelOptions} value={newHardware.iSeriesModel} data-field="iSeriesModel" required>`.
  Block 1 = Hardware Selection screen; Block 2 = inline Edit-mode Group Config. **Both** must be touched by any fix.
- **Change handler:** `hardwareGroupManager.js:622-631` `case 'iSeriesModel'` sets `newHardware.iSeriesModel`
  and resets/loads Feature Code options.
- **Only model write:** `hardwareGroupManager.js:737` `hardwareData.iSeries_Model__c = this.newHardware.iSeriesModel;`
  (no `Model_Number__c` key is built anywhere in `js:729-760`).
- **Apex persist:** `HardwareGroupController.cls:170-171` assigns `iSeries_Model__c` when the key is present.
- **Picklist options source:** `HardwareGroupController.cls:437-438` builds the combobox's `iSeriesModel`
  options from the **`iSeries_Model__c`** describe — so even the dropdown values come from the iSeries field.
- **Dead "Legacy" branch:** `HardwareGroupController.cls:203-206` (comment *"Legacy fields (kept for backward
  compatibility)"*) assigns `Model_Number__c` only `if (hardwareData.containsKey('Model_Number__c'))` — a key
  the LWC never sends. The JS `modelNumber` state (`js:73`, reset `:577`) and `case 'modelNumber'` (`js:652-654`)
  are likewise **dead** — no HTML element carries `data-field="modelNumber"`.

### READ path — display reads `Model_Number__c` (null for iSeries)
- Detail cards: `hardwareGroupManager.html:312` and `:611` → `{selectedHardware.Model_Number__c}`.
- Datatable columns: `hardwareGroupManager.js:121` (`Hardware__r.Model_Number__c`) and `:130` (`Model_Number__c`).
- Edit-mode hydration: `hardwareGroupManager.js:822` → `Model_Number__c: this.selectedGroup.Hardware__r?.Model_Number__c`.
- Sibling modal: `hardwareManagementModal.html:239-240` gates a "Model: …" line on `Model_Number__c` (suppressed for iSeries).

### The two facts that disprove the "wrong field" premise (independently re-verified by hand)

1. **`iSeries_Model__c` is the structurally-correct home and is metadata-locked as a controller.**
   `objects/Hardware__c/fields/iSeries_Feature_Code__c.field-meta.xml:12` →
   `<controllingField>iSeries_Model__c</controllingField>` (type Picklist). `HardwareGroupController.getFeatureCodeOptions`
   (`cls:486-487`) uses `iSeries_Model__c` as the controlling field and `iSeries_Feature_Code__c` as dependent.
   `iSeries_Model__c` is a 92-value IBM-Power picklist; `Model_Number__c` is `Text(100)` and controls nothing.
   → Re-pointing the write to `Model_Number__c` would **orphan the Feature Code dependent picklist**.

2. **`Model_Number__c` was never a model-code field.** Live FortraUAT (2026-06-28):
   `Model_Number__c` is populated on **29,192** rows, of which **29,188 are migration GUIDs**
   (e.g. `DEB80F77-BD25-E511-80C4-005056840EFE`); only **4** are real strings
   (`IBM Power S1022`, `IBM Power E1080`, `EP12`, `1223`). It is effectively a legacy external-key/GUID
   column. Routing clean iSeries codes into it would pollute a GUID namespace and help no consumer.

### Live confirmation the write already works
- Screenshot record **HW-0717956** (`a0nWC000001wRldYAE`): `Hardware_Platform__c=iSeries`,
  `iSeries_Model__c=500`, `Model_Number__c=null`. The model **did** save — it's just not displayed.
- Org-wide: only **46** Hardware rows have `iSeries_Model__c`; **44** are `iSeries` platform with
  `Model_Number__c=null`. The pattern is uniform with the bug.

## Why this isn't a fresh regression

The 46 diverted rows span **CreatedDate 2026-02-01 → 2026-06-26** (only 7 created on/after 2026-06-20).
The create-form path has been writing to `iSeries_Model__c` since February; SC-3468 surfaced the
display gap, but the storage behavior is long-standing. See [04_LIVE_EVIDENCE.md](04_LIVE_EVIDENCE.md).

## One-line root cause

> The modal's "Model Number" combobox is **mislabeled** but correctly persists to `iSeries_Model__c`; the
> Hardware grid and cards **read a different field (`Model_Number__c`)** that is null for iSeries, so the
> saved model is invisible. Fix the read/label, not the write.
