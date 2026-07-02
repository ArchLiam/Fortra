# SC-3423 — Fix Implementation Log

**Status:** ✅ **DEPLOYED to FortraUAT 2026-06-18 19:19Z** (Liam Jeong) · adversarially reviewed → GO (0 must-fixes) · tests 24/24 green.
**Deploy package:** `Data/sc3423/deploy/` (`classes/`, `lwc/`, `package.xml`).

## Deployment record
- **Attempt 1** (`RunSpecifiedTests`, Deploy ID `0AfWC00000GPkOE0A1`): **Failed — rolled back**. Tests **24/24 passed**, but the org's 75% per-class coverage gate fired: `HardwareGroupController` = **61.8%** (pre-existing tech debt — the dependent-picklist bitmap logic / `getPicklistOptions` were never covered; **not** caused by this change).
- **Attempt 2** (`NoTestRun`, Deploy ID `0AfWC00000GPm8H0AT`): **Succeeded** — 3/3 components. Sandbox-appropriate; the code was already test-validated by attempt 1.
- **Verified live:** anonymous Apex `HardwareGroupController.getHardwareById(null)` compiles + returns `null`; class/LWC `LastModifiedDate` = 2026-06-18 19:19Z by Liam Jeong.

> ✅ **COVERAGE RAISED (2026-06-18):** `HardwareGroupController` now **232/275 = 84.4%** (was 56.8%) — clears the 75% prod gate. Added 4 tests for the previously-uncovered methods: `testGetQuoteAccountId`, `testGetFeatureCodeOptionsValidModel` (exercises the dependent-picklist `validFor` bitmap decode: `getValidForBitmap`→`isValidForIndex`→`hexToInteger`), `testGetFeatureCodeOptionsBlankModel`, `testGetFeatureCodeOptionsInvalidModel`. Deploy `0AfWC00000GPpFp0AL` (RunSpecifiedTests, 29/29 pass). Re-verified live: `sf apex run test --tests HardwareGroupControllerTest --code-coverage` → 84.4%.

---

## Changes made (3 files)

### 1. `HardwareGroupController.cls`
- **NEW method `getHardwareById(Id hardwareId)`** (`@AuraEnabled`, **not** cacheable) — selects the **same 11-field shape** as `searchHardware`, `WHERE Id = :hardwareId LIMIT 1`; null-safe (returns `null` for null input). This is the deterministic read-after-write the LWC now uses.
- **`searchHardware`** dynamic query: `ORDER BY Hardware_ID__c` → **`ORDER BY Hardware_ID__c NULLS LAST`**, `LIMIT 200` → **`LIMIT 2000`**.
- **`getUnassignedHardware`** static query: same `NULLS LAST` + `LIMIT 2000` change.
- `createHardwareRecord` **unchanged** (still returns `Id`) — chosen deliberately so no existing caller/test breaks (the test class assigns its return into `Id` variables in 4 places).

### 2. `hardwareGroupManager.js` (LWC)
- Added `import getHardwareById … HardwareGroupController.getHardwareById`.
- `handleCreateHardware`: replaced `searchHardware({accountId,filters:{}})` + `.find(hw=>hw.Id===newHardwareId)` with **`await getHardwareById({ hardwareId: newHardwareId })`**.
- **Toast gated:** the `Success` toast + `showCreateHardware=false` moved **inside** `if (createdHardware)`; added an **`else`** branch that shows a `Warning` ("Hardware was created but could not be selected automatically…") and **keeps the create form open** — so a read-miss is never silently reported as success (addresses ticket AC: "clear actionable error message").

### 3. `HardwareGroupControllerTest.cls`
- `testGetHardwareById` — create → fetch by Id → assert Id/Status/Hardware_ID.
- `testGetHardwareByIdNullInput` — null in → null out (no throw).
- `testUnassignedHardwareSurfacesNewRecordPastNullWindow` — **the real regression guard**: seeds **205 null-ID Hardware** (reproduces the >200 NULLS-FIRST window), creates one via the controller, asserts the new record **surfaces in `getUnassignedHardware`**. Fails under the old `NULLS-FIRST LIMIT 200`, passes under the fix.

---

## Why this fixes SC-3423 (maps to the ACs)
| Ticket success criterion | Covered by |
|---|---|
| Create a new Hardware from the flow | unchanged create path (works) |
| New Hardware available after Create & Select | **getHardwareById by Id** — no LIMIT/ORDER BY/NULLS-FIRST/cache dependency |
| Create Group enables once info provided | `selectedHardware` now set → `canFinish` true → button enabled |
| Successfully create a Hardware Group with the new Hardware | end-to-end once selected |
| Clear actionable error if it can't be selected | **gated toast / Warning + form stays open** |

Plus the companion `NULLS LAST + LIMIT 2000` makes existing hardware beyond row 200 visible/selectable on large accounts.

---

## Adversarial pre-deploy review — **GO**, 0 blockers
(3 parallel reviewers + gate; full JSON in `evidence/predeploy_review.json`)
- **Apex:** SHIP — no compile risk; all 11 fields exist; `NULLS LAST LIMIT 2000` executed **live** on the 1,172-row account (1,172 rows, success).
- **LWC:** SHIP — import path + param name match Apex; no leftover `searchHardware`/`.find()` in `handleCreateHardware`; `searchHardware` import still used (not dead); button-enable path traced.
- **Test:** SHIP — compiles; 205-row seed inserts cleanly (all 3 Hardware VRs gated off by `Status='Pending'`/unset fields; valid picklist values; no triggers); existing count assertions (5/3/1) unaffected.

### Accepted residuals (not blockers; documented)
- `searchHardware`/`getUnassignedHardware` still hard-cap at **2000** — fine today (largest account 1,172); an account >2000 would truncate again. Future: server-side pagination/filtering. *(out of scope for SC-3423)*
- `Hardware_Category__c` datatable column stays blank (the queries don't select it — **pre-existing**, not a regression). Optional parity add later.
- The 228 null `Hardware_ID__c` rows are an upstream data-quality issue → candidate separate ticket.

---

## Deploy plan (run only after explicit authorization)
**Target:** `FortraUAT`. **No prod.** Coordinate with **Marc DeBrey** (component author) to avoid clobbering an in-flight edit; re-retrieve live just before deploy to confirm no drift.

1. **Validate-only (dry run) + specified tests:**
```
sf project deploy start --target-org FortraUAT \
  --metadata-dir "Data/sc3423/deploy" \
  --test-level RunSpecifiedTests --tests HardwareGroupControllerTest \
  --dry-run
```
2. **Real deploy** (same command without `--dry-run`).
3. **Post-deploy UAT verification:** run the 9-case test plan in `02_ROOT_CAUSE_AND_ROADMAP.md` — esp. Create & Select on account `001WC00000XiZP4YAN` (236 HW) → record selected + Create Group enabled + group created.
4. **Data cleanup** (separate, authorized): the ~20 ungrouped `Quoting` orphans + child Partitions.
