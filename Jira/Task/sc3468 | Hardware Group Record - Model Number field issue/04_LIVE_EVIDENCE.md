# 04 — Live Evidence (FortraUAT, 2026-06-28)

All queries **read-only** (SELECT / describe / metadata). Org alias `FortraUAT`
(`liam.jeong.c@fortra.com.uat`, `00DWC000006eUFF2A2`). No DML, no deploy.

## 1. The screenshot record — value DID save to `iSeries_Model__c`

```sql
SELECT Id, Name, Hardware_ID__c, Hardware_Platform__c, Model_Number__c,
       iSeries_Model__c, Serial_Number__c, CreatedDate
FROM Hardware__c WHERE Id='a0nWC000001wRldYAE'
```

| Name | Platform | Model_Number__c | iSeries_Model__c | Serial | Created |
|---|---|---|---|---|---|
| HW-0717956 | iSeries | **null** | **500** | 123456ABC | 2026-06-25 |

→ The model **saved correctly** to `iSeries_Model__c`; it is invisible because the card reads `Model_Number__c`.

## 2. Field-of-record by row count

```sql
SELECT COUNT(Id) total, COUNT(Model_Number__c) hasModel, COUNT(iSeries_Model__c) hasISeries FROM Hardware__c
```
| total | hasModel | hasISeries |
|---|---|---|
| 79042 | 29192 | **46** |

Grouped by platform:
| Platform | total | Model_Number__c | iSeries_Model__c |
|---|---|---|---|
| (null) | 78992 | 29191 | 2 |
| iSeries | 44 | 1 | 44 |
| Cross Platform | 6 | 0 | 0 |

## 3. ★ Linchpin finding — `Model_Number__c` is a migration-GUID column

```sql
-- populated
SELECT COUNT(Id) total, COUNT(Model_Number__c) populated FROM Hardware__c WHERE Model_Number__c != null
--> 29192 / 29192

-- GUID-shaped
SELECT COUNT(Id) guidShaped FROM Hardware__c
WHERE Model_Number__c LIKE '________-____-____-____-____________'
--> 29188

-- the ONLY non-GUID values
SELECT Model_Number__c, COUNT(Id) n FROM Hardware__c
WHERE Model_Number__c != null AND (NOT Model_Number__c LIKE '________-____-____-____-____________')
GROUP BY Model_Number__c
--> IBM Power S1022 (1), IBM Power E1080 (1), EP12 (1), 1223 (1)
```

**29,188 of 29,192** populated values are GUIDs (e.g. `DEB80F77-BD25-E511-80C4-005056840EFE`); only **4**
are real strings. `Model_Number__c` was never a model-code field → the reporter's "wrong field mapping"
premise does not hold.

## 4. Field types & the dependent-picklist lock

Live describe (`sf sobject describe -s Hardware__c`):
- `Model_Number__c` — type **STRING** (free text), `picklistValues=0`, `dependentPicklist=false`, `controllerName=null`.
- `iSeries_Model__c` — type **PICKLIST**, **92 active values**, `controllerName=null` (it is itself the controller).
- `iSeries_Feature_Code__c` — **dependent picklist**, controlled by `iSeries_Model__c`.
- `Hardware_Platform__c` — picklist, 2 values: `iSeries`, `Cross Platform`.

Metadata confirmation (authoritative):
```
objects/Hardware__c/fields/iSeries_Feature_Code__c.field-meta.xml:10  <type>Picklist</type>
objects/Hardware__c/fields/iSeries_Feature_Code__c.field-meta.xml:12  <controllingField>iSeries_Model__c</controllingField>
objects/Hardware__c/fields/Model_Number__c.field-meta.xml             <type>Text</type> <length>100</length>
objects/Hardware__c/fields/iSeries_Model__c.field-meta.xml            <type>Picklist</type> (92 IBM-Power values)
```
→ Re-pointing the model write to `Model_Number__c` would **orphan** the Feature Code dependent picklist.

## 5. The 46 diverted rows — not a fresh regression

```sql
SELECT COUNT(Id), MIN(CreatedDate), MAX(CreatedDate) FROM Hardware__c WHERE iSeries_Model__c != null
```
- 46 rows · **CreatedDate 2026-02-01 → 2026-06-26** · 12 distinct `CreatedById`.
- 44 `iSeries` platform + 2 platform-NULL legacy rows.
- `Model_Number__c=null` on 43; dual-populated on 3 (`HW-0717915`, `HW-0717916`, `HW-0717935`).
- 2 off-picklist values (`9080-M9S`, `9105-22A`) on the 2 platform-NULL rows.
- `iSeries_Feature_Code__c` populated on **35/46** → the model→feature-code chain works through `iSeries_Model__c`.

## 6. Downstream reference counts (the 46 HW)

| Relationship | Count | Of which `Model_Number__c=null` |
|---|---|---|
| `OrderItem.Hardware__c` | 24 | 24/24 |
| `OrderItem.Model__c` | 2 | — |
| `QuoteLineItem.Hardware__c` | 18 | 15/18 |
| `QuoteLineItem.Hardware_Reference__c` | 7 | — |
| `Asset.Hardware__c` | 25 | 24/25 |

**BSS-reachable** (via `OrderItem.Hardware_ID__c`, which `BSSOrderInfoRestService` actually reads) = **2
OrderItems, both on Draft orders** → no live integration data loss today.
