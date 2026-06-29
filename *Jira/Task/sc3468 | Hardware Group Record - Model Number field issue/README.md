# SC-3468 — Hardware Group Record: "Model Number" field issue

**Status:** 🔬 Research complete · awaiting reporter confirmation of reframe before build
**Priority:** High · **Reporter:** Dawn Krauss · **Assignee:** Liam Jeong
**Label:** LOB-Salesforce-2-GoLive · **Created:** 2026-06-25 · **Researched:** 2026-06-28
**Component:** `hardwareGroupManager` LWC + `HardwareGroupController` (same stack as SC-3423)

---

## TL;DR

The reporter's **instinct is right** (keep `iSeries_Model__c`), but the stated **root cause is wrong**
("the UI is mapped to the wrong DB field and the value isn't saving").

- The "Create New Hardware Group" modal **already saves the picked model correctly** to
  `Hardware__c.iSeries_Model__c`. Verified live: screenshot record **HW-0717956**
  (`a0nWC000001wRldYAE`) holds `iSeries_Model__c = 500`, `Model_Number__c = null`.
- The real defect is a **display / read mismatch**: the combobox is *labeled* "Model Number" but
  *bound* to `iSeries_Model__c`, while the detail cards and datatable **read `Model_Number__c`**
  (which is null for iSeries) — so the value the user just picked "disappears" from the UI.
- Making `Model_Number__c` canonical (the literal reading of the request) is the **wrong fix** for two
  hard, independently-verified reasons:
  1. `iSeries_Feature_Code__c` is a **dependent picklist whose controller is `iSeries_Model__c`**
     (`<controllingField>iSeries_Model__c</controllingField>`). Re-pointing the write would orphan the
     Feature Code dropdown (35/46 existing rows populate it through that chain).
  2. `Model_Number__c` is a free-text column whose live content is **29,188 of 29,192 migration GUIDs**
     — it was never a model-code field.

**Recommended fix:** UI / read-layer only. Keep persisting `iSeries_Model__c`; relabel both comboboxes
to "iSeries Model"; make the read surfaces show `iSeries_Model__c` (with `Model_Number__c` fallback) for
iSeries platform; add `iSeries_Model__c` to the controller SELECTs; delete the dead `modelNumber` paths.
**No DB remap, no backfill** — the 46 existing records are already stored correctly.

---

## File index

| File | Contents |
|---|---|
| [01_RCA.md](01_RCA.md) | Root cause, full write-vs-read evidence chain, why the reporter's premise fails |
| [02_IMPACT_AND_BLAST_RADIUS.md](02_IMPACT_AND_BLAST_RADIUS.md) | Per-consumer downstream audit (what breaks / what's safe) |
| [03_RECOMMENDED_FIX.md](03_RECOMMENDED_FIX.md) | Concrete fix (file:line), rejected alternatives, data cleanup, test plan, open questions |
| [04_LIVE_EVIDENCE.md](04_LIVE_EVIDENCE.md) | SOQL + describe outputs from FortraUAT (2026-06-28), all read-only |
| [JIRA_COMMENT.md](JIRA_COMMENT.md) | Jira-ready RCA comment |
| [evidence/consumer_audit.md](evidence/consumer_audit.md) | Full consumer-by-consumer table for both fields |
| [evidence/workflow_raw_output.json](evidence/workflow_raw_output.json) | Raw multi-agent research output (traceability) |

---

## Methodology

Researched with a multi-agent workflow (5 parallel code/data researchers → adversarial verification →
synthesis), then the two load-bearing, reporter-contradicting claims were **independently re-verified by
hand** against FortraUAT and the field metadata. All org access was **read-only** (SELECT / describe);
no DML or deploy was performed (UAT change would require a separate explicit authorization).
