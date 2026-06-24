# SC-3423 — Evidence & Live-Data Facts

**Ticket:** SC-3423 "Cannot Create New Hardware Group with New Hardware"
**Reporter:** German Wren · **Assignee:** Liam Jeong · **Labels:** CRM-RevenueCloud, LOB-Salesforce-1-UAT
**Org:** FortraUAT (`liam.jeong.c@fortra.com.uat`, 00DWC000006eUFF2A2)
**Research date:** 2026-06-18 · all facts retrieved live from FortraUAT.

---

## 1. Component chain (what actually renders the screen)

The screenshot UI is **not** an OmniScript or the `Fortra_Hardware_*` flows (those are an unrelated, generic "Hardware Management" screen-flow set). The real chain is pure LWC + Apex:

```
Quote Record Page
└─ quoteLineFlexPanel (LWC)              ← user's clarification: "it's Quote Line Flex Panel"
   └─ "Hardware Groups" button  → handleNewHardwareGroup() → showHardwareGroupModal = true
      └─ <c-hardware-group-manager>  (hardwareGroupManager LWC, modalTitle "Create New Hardware Group")
         └─ HardwareGroupController.cls  (Apex, with sharing)
```

- Host button: `quoteLineFlexPanel.html:197-203` → `quoteLineFlexPanel.js:330 handleNewHardwareGroup`.
- Modal embed: `quoteLineFlexPanel.html:210-215` (`<c-hardware-group-manager record-id={recordId} onsuccess=… oncancel=…>`).
- `hardwareGroupManager.js-meta.xml`: `isExposed=true`, target `lightning__RecordAction` (also usable as a Quick Action). masterLabel "Hardware Groups".
- Author of both LWC + Apex: **Marc DeBrey** (per file headers, v1.1, since 2025-01).

The screenshot's buttons map exactly:
| Screenshot button | LWC binding |
|---|---|
| **Create New Hardware** | `hardwareGroupManager.html:160 / :454` → `handleToggleCreateHardware` (reveals the create form) |
| **Create & Select** (shown "Create and Select") | `hardwareGroupManager.html:291` → `handleCreateHardware` |
| **Create Group** (greyed) | `hardwareGroupManager.html:356 / :356` `disabled={canFinishDisabled}` → `handleFinish`→`handleCreateGroup` |
| radio list of Pending hardware | `getUnassignedHardware` (create-mode hardware-selection screen) |

---

## 2. The buggy code path

**`hardwareGroupManager.js` `handleCreateHardware()` (lines 687-794):**

```js
const newHardwareId = await createHardwareRecord({ hardwareData, accountId: this.quoteAccountId }); // returns the new Id

// Re-query ALL hardware for the account, then try to re-find the record we just made:
const newHardwareRecords = await searchHardware({ accountId: this.quoteAccountId, filters: {} });
const createdHardware = newHardwareRecords.find(hw => hw.Id === newHardwareId);

if (createdHardware) {                       // ← if find() misses, this whole block is skipped
    this.selectedHardware = createdHardware;  //   selection that ENABLES "Create Group"
    this.hardwareRecords = [createdHardware];
    this.hardwareCreatedAndSelected = true;
    await this.fetchHardwareAttributes(createdHardware.Id);
}
this.showToast('Success', 'Hardware created successfully', 'success'); // ← fires UNCONDITIONALLY
this.showCreateHardware = false;
```

**Why "Create Group" stays greyed:** `disabled={canFinishDisabled}` → `!canFinish`. In create mode with "Assign or change hardware" checked, `canFinish` (js:148-149) requires `this.selectedHardware !== null`. If the `if (createdHardware)` block is skipped, `selectedHardware` is never set → button stays disabled. The available list also keeps the old `hardwareRecords` (so the new record "is not in this list").

**Why it fails silently:** the success toast on line 786 is **outside** the `if`, so the user sees "Hardware created successfully" even though selection never happened.

---

## 3. Why `find()` misses — `HardwareGroupController.searchHardware` (lines 88-130)

```apex
@AuraEnabled(cacheable=true)                              // ← line 88
public static List<Hardware__c> searchHardware(Id accountId, Map<String,String> filters){
    String whereClause = 'Account__c = :accountId';       // filters empty ⇒ only this
    ...
    String query = 'SELECT … FROM Hardware__c WHERE ' + whereClause +
                   ' ORDER BY Hardware_ID__c LIMIT 200';   // ← line 122-123: CAP + sort
    return Database.query(query);
}
```

`createHardwareRecord` (lines 138-248) always sets:
- `Status__c = 'Quoting'` (line 156, hard-coded, override-protected line 207)
- `Hardware_ID__c = generateHardwareId()` → `'HW' + count('HW%').leftPad(6)` (e.g. `HW000034`), unless the user supplied a Cross-Platform Hardware ID (then that value).

So the new record matches `Account__c = :accountId` — **but only if it survives `ORDER BY Hardware_ID__c LIMIT 200`.**

### Live proof on the reporter's account — the precise mechanism is **NULLS FIRST**
| Metric (FortraUAT, 2026-06-18) | Value |
|---|---|
| Total `Hardware__c` | 79,028 |
| Accounts with **>200** hardware | **8+** (top 1,172 / 831 / 776 / 514 / 510 / 507 / 445 / 402 …) |
| German Wren's test account `001WC00000XiZP4YAN` | **236** hardware |
| …of which `Hardware_ID__c` **IS NULL** | **228** |
| …of which `Hardware_ID__c` is **non-null** | **8** (incl. every record created via this LWC) |

`ORDER BY Hardware_ID__c ASC` uses Salesforce's default **NULLS FIRST**, so the **228 null‑ID records occupy positions 1–228**. The exact production query —
`SELECT … FROM Hardware__c WHERE Account__c='001WC00000XiZP4YAN' ORDER BY Hardware_ID__c LIMIT 200` —
returns **200 rows that are *all* null‑ID** (verified live; rows 1–200 and the 195–205 window are 100% null). The only 8 non‑null IDs sit at positions **229–236**, entirely past the cap.

A newly-created record **always** has a non-null `Hardware_ID__c` (`generateHardwareId()` or the Cross‑Platform override), so it lands in the 229–236 band and is **never** in `searchHardware`'s result — `.find()` returns `undefined` **deterministically, regardless of the new ID's value**. This is why even German's low-sorting custom ids `'123'`/`'123456'` failed. Any account with ≥200 lower-sorting (esp. null) IDs reproduces it on every create.

> Reconciliation of the raw counts: `WHERE Hardware_ID__c < 'HW000033'` = 235 and `< '123'` = 229 because SOQL counts the 228 nulls as "less than" a non-null value, plus the few non-null IDs below each — consistent with 228 nulls + 8 non-nulls.

`getUnassignedHardware` is **also** `LIMIT 200 ORDER BY Hardware_ID__c` (line 403), so on big accounts the initial "Available Hardware" list is itself 100% null-ID rows — existing hardware beyond row 200 is invisible/unselectable too (parallel defect → fix together).

**Secondary trigger:** `searchHardware` is `@AuraEnabled(cacheable=true)`. Imperative calls to cacheable Apex are client-cached by signature+args, so a repeat `searchHardware(accountId, {})` in the same session can return a stale set missing the just-created record — breaking `.find()` even on small accounts after the first create.

---

## 4. Smoking-gun artifacts: orphan `Quoting` hardware

`createHardwareRecord` always stamps `Status='Quoting'`. Status distribution:

| Status | Count |
|---|---|
| Pending | 78,979 (migrated/seed data — what the screenshot list shows) |
| **Quoting** | **26** (only ever produced by this LWC) |
| Active | 23 |

Of the 26 `Quoting` records, **20 are ungrouped orphans** (created but never attached to any `QuoteLineGroup`) — the exact signature of "create succeeded, find/selection failed, group never created." Reporter **German Wren created 6** of them on **2026-06-16 / 2026-06-17** on the 236-record account `001WC00000XiZP4YAN` (`HW000030-33`, plus custom ids `123`, `123456`) — i.e. the artifacts of reproducing this ticket. (The 6 grouped `Quoting` records are successful small-account creates still awaiting Opportunity → Order Processing, where `Status` flips to `Active`.)

---

## 5. Alternative causes ruled out
- Active `Hardware__c` VRs (`VR_Hardware_Serial_Required_When_Active`, `VR_Hardware_Warranty_Date_Logic`, `VR_Hardware_Account_Match_Parent`) do **not** fire on a `Quoting` create. The insert clearly succeeds — the 26 `Quoting` rows are proof.
- `QuoteLineGroup` VR `Hardware_Groups_Must_Have_Hardware` only constrains group creation (worked around in `createHardwareGroup` lines 273-278); it is not in the create-hardware path and is not what greys the button.
- `QuoteLineGroupTrigger` runs only on group DML, not on the failing step.
- No FLS/sharing block: the record is created and committed; the failure is purely the client-side re-query/`find` miss.

---

## Retrieved evidence files (in `evidence/`)
- `hardwareGroupManager.js` / `.html` — the LWC (buggy `handleCreateHardware`).
- `HardwareGroupController.cls` — Apex (`searchHardware` LIMIT 200 + cacheable; `createHardwareRecord` Status='Quoting').
- `quoteLineFlexPanel.js` — host that launches the modal.
- Raw retrieves under `Data/sc3423/` (`lwc_retrieve/`, `apex_retrieve/`, `flexpanel_retrieve/`, `omnistudio_retrieve/`).
