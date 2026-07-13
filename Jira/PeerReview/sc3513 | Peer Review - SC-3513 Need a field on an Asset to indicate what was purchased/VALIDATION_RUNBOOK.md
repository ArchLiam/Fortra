# SC-3513 Validation Runbook

**Org:** FortraUAT · All Part-A commands are **read-only**. Part-B requires **explicit UAT write authorization** before running.

---

## Part A — Reproduce the review (read-only)

### A1. Confirm the requested field is system-locked and the delivered field is writable
```bash
sf sobject describe -o FortraUAT -s Asset | \
  python3 -c "import json,sys;d=json.load(sys.stdin);[print(f['name'],f['type'],'upd='+str(f['updateable']),'cre='+str(f['createable'])) for f in d['fields'] if f['name'] in ('Description','ProductDescription')]"
```
Expect: `ProductDescription … upd=False cre=False` · `Description … upd=True cre=True`.

### A2. Confirm the flow exists, is Active, and its trigger type
```bash
sf project retrieve start -o FortraUAT -m "Flow:Fortra_Asset_Stamp_Line_Description" --target-metadata-dir /tmp/sc3513fl
# then inspect /tmp/sc3513fl/unpackaged/flows/…: expect
#   <recordTriggerType>Create</recordTriggerType>
#   start filters: Description IsNull=true AND HasLifecycleManagement=true
#   Get_Asset_Action filters AssetId only (NO Type=Generate)
sf data query --use-tooling-api -o FortraUAT -q "SELECT MasterLabel, Status, LastModifiedDate FROM Flow WHERE Definition.DeveloperName='Fortra_Asset_Stamp_Line_Description' AND Status='Active'"
```

### A3. Show the lifecycle: Change actions exist on EXISTING assets
```bash
sf data query -o FortraUAT -q "SELECT Type, COUNT(Id) FROM AssetAction GROUP BY Type"
sf data query -o FortraUAT -q "SELECT CategoryEnum, COUNT(Id) FROM AssetAction GROUP BY CategoryEnum"
sf data query -o FortraUAT -q "SELECT Id, AssetId, CategoryEnum, CreatedDate FROM AssetAction WHERE Type='Change' ORDER BY CreatedDate DESC"
```
Expect: `Change` = 17 (Renewals 6 + Upsells 11), each with an `AssetId` (existing asset, not a new one).

### A4. Prove AC-2 fails by outcome: changed assets have blank Description
```bash
sf data query -o FortraUAT -q "SELECT Id, Name, Description, ProductDescription FROM Asset WHERE Id IN ('02iWC000008dd1hYAA','02iWC000008deKLYAY','02iWC000008deyfYAA','02iWC000008MuWoYAK','02iWC000008MuWnYAK')"
```
Expect: `Description = null` on all; `ProductDescription` shows only static product text.

### A5. Prove AC-1 works: fresh (post-deploy) assets carry the dynamic value
```bash
# find recent Generate assets, then read their Description
sf data query -o FortraUAT -q "SELECT AssetId, CreatedDate FROM AssetAction WHERE Type='Generate' AND CreatedDate=LAST_N_DAYS:2 ORDER BY CreatedDate DESC LIMIT 10"
sf data query -o FortraUAT -q "SELECT Id, Name, Description, ProductDescription FROM Asset WHERE Id IN ('02iWC000008kuVhYAI','02iWC000008kvl3YAA','02iWC000008kvl5YAA','02iWC000008kvl6YAA')"
```
Expect: `Description` = pipe-delimited line string (incl. `BoKS Administration License Fee` for the flat product).

### A6. Confirm the Change-action source is NOT an OrderItem (G-2)
```bash
sf data query -o FortraUAT -q "SELECT AssetActionId, ReferenceEntityItemId FROM AssetActionSource WHERE AssetActionId='4nLWC0000038vdi2AA'"
sf data query -o FortraUAT -q "SELECT Id FROM OrderItem WHERE Id='14CWC000001S9UP2A0'"   # expect 0 rows
```

### A7. Confirm no other automation writes Description
```bash
sf data query --use-tooling-api -o FortraUAT -q "SELECT Name, Status FROM ApexTrigger WHERE TableEnumOrId='Asset'"   # only AssetMigrationQueueClearTrigger
```

---

## Part B — Live AC-2 confirmation (REQUIRES UAT WRITE AUTHORIZATION — do not run until explicitly approved)

Goal: demonstrate that after a config change the delivered field does NOT update (and, once the fix is built, that it does).

1. Pick a lifecycle-managed Asset that already has a stamped `Description` (e.g. one of the A5 assets). Record its `Description`.
2. Put its Account through an **amendment or renewal** that changes an in-scope attribute (e.g. device range / node bundle / user band) on that product line. Activate/convert per the standard flow.
3. Re-query the Asset: `SELECT Id, Description, ProductDescription FROM Asset WHERE Id='<assetId>'` and its new `AssetAction` (`Type=Change`).
   - **Current build (expected):** `Description` unchanged/stale (or blank), a new `Type=Change` AssetAction present, flow did not fire. → AC-2 fails.
   - **After the update-path fix:** `Description` re-derived to the new config.
4. Repeat for **manual asset update** and any other event enumerated in the G-3 trigger-event matrix, to answer the reporter's "confirm no other trigger events" ask empirically.

> Note: `Asset.Description` is a long textarea and **cannot be filtered** in SOQL — always `SELECT` and inspect, never `WHERE Description …`.
