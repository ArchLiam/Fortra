# SC-3423 — Root Cause & Fix Roadmap

> Verified against live FortraUAT 2026-06-18. Root cause adversarially verified (5 independent skeptics: `limit200` **CONFIRMED-high**, `silentfail` **CONFIRMED-high**, `altcause` **REFUTED-high** = no alternative cause, `cacheable` **PARTIAL** = secondary, `evidence/orphans` **PARTIAL** = artifacts with nuance).

---

## 1. Root cause (one paragraph)

SC-3423 is a **client/server read‑after‑write design flaw** in the `hardwareGroupManager` LWC + `HardwareGroupController` Apex (author Marc DeBrey). After **Create & Select** inserts a new `Hardware__c` (which always gets a **non‑null** `Hardware_ID__c`), `handleCreateHardware()` re‑derives the just‑created record by calling `searchHardware({accountId, filters:{}})` and doing `newHardwareRecords.find(hw => hw.Id === newHardwareId)`. `searchHardware` runs `WHERE Account__c = :accountId ORDER BY Hardware_ID__c LIMIT 200`. On the reporter's account (236 Hardware rows, **228 with a null `Hardware_ID__c`**), the default **NULLS‑FIRST** ordering fills positions 1–228 with null‑ID rows, so the `LIMIT 200` window is **100 % null‑ID records** and the new record (position 229–236) is **never returned**. `.find()` therefore returns `undefined`, the `if (createdHardware) { … }` block — the **only** place `selectedHardware` is set on this path — is skipped, and because `canFinish` (create + "assign hardware now") requires `selectedHardware !== null`, the **Create Group** button stays greyed. Meanwhile `showToast('Success')` fires **unconditionally** outside that block, so the failure is silent. Net: the three exact reported symptoms — success toast, new record absent from the list, Create Group greyed.

**Deterministic** on any account with >200 Hardware rows (8+ such accounts in UAT; top = 1,172). Not a validation‑rule/trigger/FLS/sharing issue (alternative‑cause sweep **REFUTED** all of those — the record *is* saved, proven by 26 `Quoting` rows in the org).

### Failure-chain diagram
```
Create & Select → createHardwareRecord()  ✅ inserts Hardware__c (Status='Quoting', non-null Hardware_ID__c)
                → searchHardware(account,{}) → "ORDER BY Hardware_ID__c LIMIT 200"
                                              → 228 null-ID rows take slots 1-200 (NULLS FIRST)
                                              → new record (slot 229-236) NOT in result
                → find(id) === undefined  ➜  if(createdHardware){…} SKIPPED
                                              ├─ selectedHardware stays null → canFinish=false → "Create Group" GREYED
                                              └─ hardwareRecords unchanged → new record not in list
                → showToast('Success')  ⚠️ fires anyway → silent failure, leaves orphan Hardware
```

---

## 2. Confirmed triggers (priority order)

| # | Trigger | Deterministic | Scope |
|---|---|---|---|
| **P0** | `searchHardware` `ORDER BY Hardware_ID__c LIMIT 200` excludes the new record; post‑create `.find()` → `undefined` | ✅ | All accounts >200 Hardware (8+ in UAT) |
| **P0** | `if(createdHardware)` is the only place `selectedHardware` is set; skipped on miss → Create Group greyed | ✅ | Every find() miss |
| **P0** | `showToast('Success')` fires unconditionally outside the `if` → silent failure, masks the bug, leaves orphans | ✅ | Every failed create |
| P1 | NULLS‑FIRST on `ORDER BY Hardware_ID__c ASC` lets 228 null‑ID rows consume the whole window | ✅ | Reporter account + any ≥200 null/low‑sorting IDs |
| P1 | `getUnassignedHardware` is also `LIMIT 200` → initial "Available Hardware" list truncated | ✅ | All >200 accounts (parallel UX defect) |
| P2 | `searchHardware` is `@AuraEnabled(cacheable=true)` → stale client cache on **2nd+** create in one modal session | ❌ (edge) | Repeat create only; not the first‑create repro |

---

## 3. Fix roadmap

### Recommended fix = **A + B2 + D** (and **E** as a required companion)

| Opt | Change | Effect | Risk |
|---|---|---|---|
| **A** *(core)* | In `handleCreateHardware`, **delete the post‑create `searchHardware` re‑query + `.find()`**. Set `selectedHardware` / `hardwareRecords` directly from the created record. | Eliminates the read‑after‑write the whole bug depends on. | low |
| **B2** *(core)* | Change `createHardwareRecord` to **re‑select the inserted row by Id** and `return newHardware` (full `Hardware__c` SObject with the fields the UI reads) instead of `return newHardware.Id`. The LWC consumes that object directly. | O(1), immune to LIMIT/ORDER BY/NULLS‑FIRST/cache; carries any trigger‑computed fields. | low |
| **D** *(guard)* | Gate the success toast on `createdHardware` actually being present; on miss show a Warning/Error and keep the form open. | Defense‑in‑depth: no future read‑miss is ever silently reported as success. | low |
| **E** *(companion)* | Apply the same treatment to `getUnassignedHardware` (and `searchHardware`'s manual‑search path): bounded/paginated **server‑side search** + `NULLS LAST` (or `ORDER BY CreatedDate DESC`), raise cap to e.g. 2000 — **not** unbounded. | Existing hardware beyond row 200 becomes visible/selectable on large accounts (incl. the 1,172‑row account). | med |

**Why this combination:** minimal blast radius (no VR/trigger/sharing/FLS in play — sweep REFUTED them), kills the deterministic primary cause **and** the silent‑failure masking, and works on accounts of **any size** rather than just raising a cap a 1,000‑row account would blow past again. Option **C** (drop `cacheable`) becomes unnecessary on the create path once **A/B2** remove the post‑create `searchHardware` call.

### Smallest possible patch (if a one‑liner hotfix is wanted first)
Even without the Apex change, replacing the create‑path `.find()` so it **falls back to the returned `newHardwareId`** (build the selected record from `hardwareData` + `newHardwareId`) and **gating the toast (D)** removes the silent failure and re‑enables Create Group. But **A+B2** is the durable fix and is strongly preferred.

### Implementation steps
1. **Caller audit** — repo‑wide grep for `createHardwareRecord` to size the `Id → Hardware__c` return‑type change (blast radius). *(completeness gap: not yet enumerated)*
2. **Apex** — `HardwareGroupController.createHardwareRecord`: after `insert`, re‑select the row by Id selecting exactly the fields `searchHardware`/`fetchHardwareAttributes` read; `return newHardware;`. Verify the returned SObject carries every field the UI needs (incl. attribute‑display fields).
3. **LWC** — `hardwareGroupManager.handleCreateHardware`: consume the returned record directly; delete the `searchHardware`+`.find()`; implement guard **D**.
4. **Companion E** — bound/paginate `getUnassignedHardware` + `searchHardware`; `NULLS LAST`.
5. **Tests** — extend `HardwareGroupController` test for the new return + a >200‑row account; run coverage (no drop). *(completeness gap: baseline coverage not yet captured)*
6. **Deploy** — coordinate with **Marc DeBrey** (co‑owner; same‑day in‑place edits risk clobber). UAT first; **prod deploy needs explicit owner ack** and confirmation the LWC/Apex even exist in prod (currently unverified).

---

## 4. Test plan (key cases)
1. **Repro pre‑fix** on `001WC00000XiZP4YAN` (236 HW): Flex Panel → Hardware Groups → Create New Hardware Group → check "Assign or change hardware" → Create New Hardware → fill → Create & Select ⇒ confirm success toast + record absent + Create Group greyed.
2. **Post‑fix** same flow ⇒ new record shows as Selected, `selectedHardware` non‑null, **Create Group enabled**; click it ⇒ `QuoteLineGroup` created with `Hardware__c` = new record, `Hardware_Group_Type__c=true`.
3. Cross‑Platform **user‑override ID** on the >200 account ⇒ selected & groupable.
4. **iSeries** path on the >200 account ⇒ auto `HW######` record selected; child `Partition` `HW######-P1` created, not rolled back.
5. **Small‑account regression** (<200 HW) ⇒ unchanged, no regression.
6. **Two creates in one session** (cache edge) ⇒ both selected/groupable.
7. **getUnassignedHardware on 1,172‑row account** ⇒ hardware beyond row 200 visible/searchable/selectable; assigned hardware still excluded.
8. **Silent‑failure guard** ⇒ forced read‑miss shows Warning/Error, modal stays open.
9. **Governor/perf** on the 1,172‑row account ⇒ no SOQL/heap errors, acceptable render.

---

## 5. Data cleanup (the 26 `Quoting` orphans)
**Do NOT mass‑delete by `Status='Quoting'`.** Verified split: **6 of 26 are legitimately grouped** (in use, on small accounts where `find()` succeeded) — must be kept. **~20 are ungrouped orphans**; of those, German Wren's 6 on `001WC00000XiZP4YAN` (HW000030‑33, `123`, `123456`, 6/16–6/17) + Liam's repro HW000034 (6/18) are confirmed SC‑3423 victims (positions 229‑236, none grouped). Other small‑account orphans (e.g. Marc's HW000001‑005 on an 8‑row account) are **below 200** and thus a **different** cause — don't attribute to SC‑3423.
**Recommended:** after fix verification + owner sign‑off, delete only ungrouped `Quoting` Hardware (no `QuoteLineGroup.Hardware__c` ref, no Order/Asset ref) **together with their child `Partition` (`HW######-P1`)** to avoid orphan partitions. At minimum clean the confirmed German/Liam repro records on the reporter account (they occupy non‑null‑ID slots). Consider a scheduled cleanup of never‑grouped `Quoting` hardware older than N days. **No UAT DML without explicit authorization.**

---

## 6. Residual risks & open items
- **Coordinate with Marc DeBrey** — `createHardwareRecord` signature change (`Id → Hardware__c`) + LWC contract; audit all callers; run the Apex test class for a passing/coverage baseline (not yet done).
- **Companion E unbounded‑query risk** on the 1,172‑row account — must be paginated/bounded, not just "remove LIMIT".
- **Data‑quality root** — *why are 228/236 `Hardware_ID__c` null?* Upstream ID‑generation/migration gap; not fixed by this code change — candidate **separate data‑hygiene ticket**.
- **`generateHardwareId()`** uses a global `'HW'+count('HW%')` — collision‑prone under concurrency, not account‑scoped. Out of scope but latent; flag.
- **Prod scope unconfirmed** — does the LWC/Apex exist in prod? Prod deploy + prod data cleanup need owner ack ("focus on UAT" ≠ deploy authorization).
- **Unverified completeness gaps** (from critic): full caller enumeration of `createHardwareRecord`; whether any Hardware insert trigger mutates fields post‑insert (argues for re‑select by Id, which B2 already does); end‑to‑end datatable UX on the 1,172‑row account; empirical 2nd‑create cache test.
