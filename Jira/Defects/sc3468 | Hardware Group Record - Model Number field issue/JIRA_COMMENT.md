## RCA — SC-3468 (Hardware Group Record: "Model Number" field issue)

**Conclusion:** the instinct to **keep `iSeries_Model__c`** is correct, but the stated root cause ("the UI
is mapped to the wrong DB field / the value isn't saving") is not what's happening.

The modal **already saves the picked model correctly** to `Hardware__c.iSeries_Model__c` — verified in UAT
on the screenshot record **HW-0717956** (`iSeries_Model__c = 500`, `Model_Number__c = null`). The real
defect is a **display/read mismatch**: the create combobox is *labeled* "Model Number" but *bound* to
`iSeries_Model__c` (hardwareGroupManager.html:210-218 and the duplicate at :505-509; persisted at
HardwareGroupController.cls:171), while the detail cards and datatable **read `Model_Number__c`**
(html:312/611, js:121/130) — which is **null** for iSeries. So the model saves but "disappears" from the UI.

**We should NOT make `Model_Number__c` canonical** (the literal reading of the request). Two hard blockers:
1. `iSeries_Feature_Code__c` is a **dependent picklist whose controller is metadata-locked to
   `iSeries_Model__c`** (confirmed via describe + field metadata). Re-pointing the write would orphan the
   Feature Code dropdown.
2. `Model_Number__c` is free text whose live content is **29,188 of 29,192 migration GUIDs** — it was never
   a model-code field. `iSeries_Model__c` is the correct, typed home (92-value picklist + Feature Code controller).

**Recommended fix (UI/read-only — no DB remap, no backfill):** keep persisting `iSeries_Model__c`; relabel
both comboboxes to "iSeries Model" (html:211 **and** :505); make the read surfaces show `iSeries_Model__c`
(with `Model_Number__c` fallback) for iSeries platform (cards html:312/611, datatable js:121/130, hydration
js:822, hardwareManagementModal:239-240); add `iSeries_Model__c` to the controller SELECTs (cls:58/116/395);
and delete the dead `modelNumber` paths (js:73/577/652, cls:203-206). The 46 existing records need **no
migration** — the display fix surfaces them.

**Blast radius:** pricing and eligibility are **safe** (no model-based logic). BSS integration is **not
impacted today** — only 2 OrderItems reach the 46 records via the BSS lookup and both are on Draft orders.

**Out of scope / follow-ups to confirm with owners:** BSS must-carry-model on activation; search-by-code
parity (cls:103, 324-325); `PowerOrderSplittingService` clone copy (cls:410/424); and a small data cleanup
of 3 dual-populated + 2 off-picklist legacy rows.

➡️ **Please confirm the display-vs-storage reframe before we build.**
