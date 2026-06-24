# SC-3423 — Cannot Create New Hardware Group with New Hardware

**Status:** ✅ Root cause confirmed (adversarially verified) · fix **DEPLOYED to FortraUAT 2026-06-18** (NoTestRun; tests 24/24 green) · awaiting UAT functional verification · **prod promotion gated on coverage** (see [03_FIX_IMPLEMENTATION_LOG.md](03_FIX_IMPLEMENTATION_LOG.md))
**Reporter:** German Wren · **Assignee:** Liam Jeong · **Component:** Quote Line Flex Panel → Hardware Groups modal
**Researched:** 2026-06-18 against live FortraUAT (read-only).

---

## TL;DR

Clicking **Create & Select** *does* create the Hardware record — but the LWC then re-finds it via a capped query (`searchHardware … ORDER BY Hardware_ID__c LIMIT 200`). On accounts with **>200 Hardware records** (the reporter's has 236, **228 of them with a null `Hardware_ID__c`**), Salesforce's default **NULLS-FIRST** ordering fills the entire 200-row window with null-ID rows, so the brand-new record (always non-null ID) is **never returned**. `.find()` returns `undefined`, the selection block is skipped → **Create Group stays greyed** and the record **isn't in the list** — while a **"Success" toast fires anyway**, hiding the failure. Deterministic on 8+ UAT accounts; it has already left **~20 orphan `Quoting` Hardware records** (6 created by the reporter while filing this ticket).

**Fix:** stop the read-after-write — have `createHardwareRecord` return the full record (re-selected by Id) and use it directly instead of re-querying + `.find()`; gate the success toast; and fix the same `LIMIT 200` truncation on the initial list. Full plan in **[02_ROOT_CAUSE_AND_ROADMAP.md](02_ROOT_CAUSE_AND_ROADMAP.md)**.

---

## Component chain
```
Quote Record Page → quoteLineFlexPanel LWC → "Hardware Groups" button (handleNewHardwareGroup)
  → <c-hardware-group-manager> (hardwareGroupManager LWC, "Create New Hardware Group")
    → HardwareGroupController.cls (Apex)
```
Author: **Marc DeBrey**. The five `Fortra_Hardware_*` Flows are an *unrelated* generic hardware screen-flow set — **not** this UI.

## The bug in 6 lines (`hardwareGroupManager.js` `handleCreateHardware`)
```js
const newHardwareId = await createHardwareRecord({ hardwareData, accountId });   // ✅ saved
const newHardwareRecords = await searchHardware({ accountId, filters: {} });     // capped LIMIT 200
const createdHardware = newHardwareRecords.find(hw => hw.Id === newHardwareId);  // ⟶ undefined on >200 acct
if (createdHardware) { this.selectedHardware = createdHardware; /* …enables Create Group… */ }  // SKIPPED
this.showToast('Success', 'Hardware created successfully', 'success');           // ⚠️ fires anyway
```

## Key evidence (live UAT)
- `001WC00000XiZP4YAN` (reporter's test account): **236 Hardware**, **228 null-ID + 8 non-null**; the production `LIMIT 200` query returns **200 rows that are 100% null-ID** → new record at position 229–236, excluded.
- **8+ accounts** exceed 200 Hardware (top 1,172). **26 `Quoting` records** total (the only status this LWC produces), **~20 ungrouped orphans**; **German Wren created 6** on 2026-06-16/17.
- Alternative causes (VRs, `QuoteLineGroupTrigger`, FLS/sharing) **ruled out** — the insert succeeds.

---

## Files in this folder
| File | Contents |
|---|---|
| **[README.md](README.md)** | this overview |
| **[01_EVIDENCE_AND_DATA.md](01_EVIDENCE_AND_DATA.md)** | component chain, buggy code path, live-data proof (NULLS-FIRST), orphan analysis, ruled-out causes |
| **[02_ROOT_CAUSE_AND_ROADMAP.md](02_ROOT_CAUSE_AND_ROADMAP.md)** | root-cause statement, trigger table, fix options A–E + recommendation, test plan, data cleanup, residual risks |
| **[JIRA_COMMENT.md](JIRA_COMMENT.md)** | paste-ready Jira comment |
| `evidence/hardwareGroupManager.js` / `.html` | retrieved LWC (the bug) |
| `evidence/HardwareGroupController.cls` | retrieved Apex (`searchHardware` LIMIT 200; `createHardwareRecord` Status='Quoting') |
| `evidence/quoteLineFlexPanel.js` | retrieved host LWC |
| `evidence/adversarial_verification.json` | raw 5-skeptic verdicts + synthesis from the verification workflow |

Raw metadata retrieves are under `Data/sc3423/` (`lwc_retrieve/`, `apex_retrieve/`, `flexpanel_retrieve/`, `omnistudio_retrieve/`).

## Verification status
Adversarial workflow (5 independent skeptics + synthesis): `limit200` **CONFIRMED-high**, `silentfail` **CONFIRMED-high**, `altcause` **REFUTED-high** (no alternative cause), `cacheable` **PARTIAL** (secondary edge case), `orphans` **PARTIAL** (artifacts, with the grouped/ungrouped nuance captured).

## Next actions (none taken — awaiting go-ahead)
1. Implement **A+B2+D** (+companion **E**) per the roadmap; coordinate with Marc DeBrey.
2. Audit all callers of `createHardwareRecord`; capture Apex test baseline.
3. Run the 9-case test plan on the 236- and 1,172-row accounts + a small account.
4. After verification + owner sign-off: clean the ~20 ungrouped `Quoting` orphans (+ child Partitions).
5. Consider a separate data-hygiene ticket for the 228 null `Hardware_ID__c` rows.
