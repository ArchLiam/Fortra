# 03 — Recommended Fix, Alternatives, Data, Test Plan

> ⚠️ **Build gate:** Confirm the display-vs-storage reframe with the reporter first (see Open Questions),
> and obtain fresh explicit authorization before any UAT deploy/DML. This document is research only.

## Recommended direction — UI / read-layer fix (no DB remap, no backfill)

Keep persisting `iSeries_Model__c`. Fix the **read + label** so the already-saved value is visible.

### 1. Relabel both comboboxes
`hardwareGroupManager.html:211` **and** `:505` — change `label="Model Number"` → `label="iSeries Model"`
(matches the flow screen field label at `Fortra_Hardware_Hardware_Management_Orchestrator.flow:388`).
*Both* blocks must change or the fix is partial.

### 2. Fix the read surfaces to show iSeries model for iSeries platform
Resolve model as `iSeries_Model__c ?? Model_Number__c` and bind the display to the resolved value:
- Datatable columns `hardwareGroupManager.js:121` and `:130` → point `fieldName` at a computed
  `modelDisplay` property populated where rows are built (in `searchHardware` / `handleGroupSelection`).
- Detail cards `hardwareGroupManager.html:312` and `:611` → bind `{selectedHardware.modelDisplay}`.
- Hydration `hardwareGroupManager.js:822` → set `selectedHardware.modelDisplay`.
- Mirror the same fallback in `hardwareManagementModal.html:239-240`.

### 3. Add `iSeries_Model__c` to the controller SELECTs feeding the grid
So the LWC can compute the fallback: add `iSeries_Model__c` alongside the existing `Model_Number__c` at
`HardwareGroupController.cls:58`, `:116`, and `:395`.

### 4. Dead-code cleanup (prevents recurrence of this exact confusion)
- Remove unused `modelNumber: ''` state — `hardwareGroupManager.js:73` and reset at `:577`.
- Remove unreachable `case 'modelNumber'` — `hardwareGroupManager.js:652-654`.
- Remove the dead Apex `Model_Number__c` branch — `HardwareGroupController.cls:203-206`.

### Do NOT change
- The Apex write (`cls:170-171`) — `iSeries_Model__c` is correct.
- Pricing (`HardwareAttributePricingPrehook`) or eligibility (`HardwareProductEligibilityService`) — model is not an input.

## Alternatives considered

### A. Reporter's literal ask — rebind the modal to write `Model_Number__c`  → **REJECTED**
Disproven three ways:
1. The value **does** save (HW-0717956 `iSeries_Model__c=500` live) — there is no data loss to "remap."
2. Re-pointing the write would **orphan the `iSeries_Feature_Code__c` dependent picklist**, whose
   `controllingField` is metadata-locked to `iSeries_Model__c` (`field-meta.xml:12`).
3. `Model_Number__c` is **99.99% migration GUIDs** — the wrong semantic home for clean model codes.

*(Honors the reporter's correct instinct — keep `iSeries_Model__c` — while correcting the mechanism.)*

### B. Backfill `iSeries_Model__c` → `Model_Number__c` for the 46 rows  → **REJECTED**
Pollutes the 29,188-row GUID namespace, helps no live consumer (BSS has zero activated-order exposure),
and is not cleanly reversible.

## Data cleanup (manual data decisions, not code — optional)

The 46 diverted rows need **no migration** — they are correctly stored. Only 5 anomalous rows warrant a
data-steward decision:
- **2 platform-NULL legacy rows** `HW-0717915` / `HW-0717916` carry **off-picklist** `iSeries_Model__c`
  values `9080-M9S` / `9105-22A` (not in the 92-value set; loaded, not modal-entered). Decide: set
  `Hardware_Platform__c='iSeries'` + add codes to the picklist, or document as load artifacts.
- **3 dual-populated rows** — `HW-0717915` (`MN=IBM Power E1080` / `ISM=9080-M9S`), `HW-0717916`
  (`MN=IBM Power S1022` / `ISM=9105-22A`), `HW-0717935` (`MN=EP12` / `ISM=170`) — internally inconsistent;
  pick the canonical value per row since the `iSeries_Model__c`-first fallback will render the code.

The 29,192 historical `Model_Number__c` rows are GUID external keys on non-iSeries records — leave untouched.

## Test plan

1. **Happy path:** modal → Platform=iSeries → pick Model `500` → pick Feature Code → save. Confirm new
   `Hardware__c.iSeries_Model__c=500` and the card + datatable now **display "500"** (was blank).
2. **Dependent picklist regression:** after relabel, selecting a Model still filters the Feature Code
   dropdown correctly (`getFeatureCodeOptions` still controlled by `iSeries_Model__c`).
3. **Both blocks:** exercise the Hardware Selection path (`html:210/312`) **and** the inline Edit-mode
   Group Config path (`html:505/611`).
4. **Existing diverted record:** open `HW-0717956` (`iSeries_Model__c=500`, `Model_Number__c=null`) — grid/
   cards now show `500` via fallback.
5. **Dual-populated row:** open `HW-0717935` (`MN=EP12`/`ISM=170`) — resolved display shows the canonical
   value without throwing.
6. **Cross Platform regression:** create a Cross Platform record — no model field shown/required; nothing regressed.
7. **Apex:** validate-deploy `HardwareGroupController` with `iSeries_Model__c` added to SELECTs (`cls:58/116/395`);
   run `HardwareGroupControllerTest` — no SOQL/field break; `createHardwareRecord` + `getPicklistOptions` pass.
8. **Pricing/eligibility no-op:** run a hardware-attribute pricing and a product-eligibility scenario on an
   iSeries line — prices and eligible products unchanged.
9. **Dead-code removal:** confirm removing `modelNumber` state (`js:73/577`), `case 'modelNumber'`
   (`js:652-654`), and the Apex branch (`cls:203-206`) does not break the create flow.

## Open questions (confirm before build)

1. **Reporter (Dawn Krauss):** confirm the reframe — the value **does** save to `iSeries_Model__c`; the
   defect is that the UI reads `Model_Number__c`. Goal = "show the picked model in the card/grid"
   (display fix, recommended) or does business specifically need the code in `Model_Number__c` for an integration?
2. **BSS owner:** must the outbound BSS payload (`BSSOrderInfoRestService.model`) carry the iSeries model
   code for activated iSeries orders? If yes, scope a follow-up to give that reader (and the two search
   filters) an `iSeries_Model__c` branch — today exposure is 2 Draft OrderItems, zero activated.
3. **Search parity:** should model search (`cls:103`, `324-325`) also match `iSeries_Model__c`? In scope or follow-up?
4. **Data steward:** decision on the 3 dual-populated + 2 off-picklist legacy rows.
5. **Separate ticket:** `PowerOrderSplittingService` (`cls:410/424`) clones only `Model_Number__c` — add
   `iSeries_Model__c` + `iSeries_Feature_Code__c` to the clone path to prevent silent model loss on Power-split?
6. **Label:** confirm "iSeries Model" is the desired combobox label (vs keeping "Model Number" for familiarity).
