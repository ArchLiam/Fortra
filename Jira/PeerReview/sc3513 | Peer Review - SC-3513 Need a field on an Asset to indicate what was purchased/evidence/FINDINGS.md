# SC-3513 Peer Review — Evidence & Fact Table

**Org:** FortraUAT (fortra--uat / 00DWC000006eUFF2A2) · **Date:** 2026-07-06 · **All queries read-only.**

All record Ids, describe results, and query outputs used in `PEER_REVIEW_REPORT.md`.

---

## 1. Field writability (the field-choice premise) — CONFIRMED

`sf sobject describe -s Asset`:

| Field | Type | updateable | createable | length |
|---|---|---|---|---|
| **ProductDescription** (label "Product Description") | string | **false** | **false** | 4000 |
| **Description** (label "Description") | textarea | **true** | **true** | 32000 |
| Product2Id | reference | true | true | 18 |
| Name | string | true | true | 255 |

→ `Asset.ProductDescription` (the field the ticket names/screenshots) is a **system-locked mirror of Product2.Description** — no Apex/Flow/manual write can set it. `Asset.Description` is writable. The build's redirect to `Asset.Description` is **technically correct**.

`Asset.Description` **cannot be filtered** in SOQL (`field 'Description' can not be filtered in a query call`) — it is a long textarea. It CAN be SELECTed. (Affects how you verify coverage — you must SELECT+inspect, not COUNT WHERE.)

---

## 2. Build artifacts — where they actually live

| Artifact | In committed `force-app`? | In live FortraUAT? | Note |
|---|---|---|---|
| `Flow:Fortra_Asset_Stamp_Line_Description` | **NO** (absent) | **YES, Active** | Last modified **2026-07-06 21:13 by Marc DeBrey** |
| `ApexClass:QLDescriptionGeneratorPrehook` (flat-product fix) | **NO** (local copy is the *pre-fix* baseline) | **YES** (fix present) | Local `force-app` = stale; live has the attribute-less handling |
| `ApexClass:PopulateAssetLegacyFieldsAction` (reverted) | matches (no Description code) | matches | Consistent with "reverted to baseline" |
| `Layout:Asset-Asset Layout` (Description surfaced) | n/a | **YES** — has a "Description Information" section with `Description` | Last modified **2026-06-23 by Marc DeBrey** |

Diff of live vs committed `QLDescriptionGeneratorPrehook` (key hunks): live `buildContextUpdates` iterates `dataPathByLineId.keySet()` (ALL lines); live `buildDescription` emits product-name-only for attribute-less lines; live removed the `attrsByLineId.isEmpty()` short-circuit and reads `queryProductNames(dataPathByLineId.keySet())`. **Committed copy has none of this** — it still returns `null` on empty attrs (line ~505) and iterates `attrsByLineId`.

---

## 3. Flow trigger config (from retrieved `Fortra_Asset_Stamp_Line_Description.flow`) — CONFIRMED

- `<object>Asset</object>`, `<recordTriggerType>Create</recordTriggerType>`, `<triggerType>RecordAfterSave</triggerType>`
- Scheduled path `<pathType>AsyncAfterCommit</pathType>`
- Start entry filters: `Description IsNull = true` **AND** `HasLifecycleManagement = true`
- Resolution: `Get_Asset_Action` filters **AssetId only**, `getFirstRecordOnly=true`, **NO `Type = Generate` filter** (the design doc claims a Type filter — it is not in the build) → `Get_Asset_Action_Source` (by AssetActionId) → `Get_Source_Order_Item` (OrderItem by Id = `ReferenceEntityItemId`) → set `Asset.Description = OrderItem.Description`.

→ Fires **once, at Asset birth, only while Description is blank.** No update path exists.

---

## 4. Asset lifecycle in the org — the update events the ticket cares about

`SELECT Type, COUNT(Id) FROM AssetAction GROUP BY Type`:

| Type | Count |
|---|---|
| Generate | 430,671 |
| **Change** | **17** |
| Cancel | 3 |

`GROUP BY CategoryEnum`: Initial Sale 430,671 · **Renewals 6** · **Upsells 11** · Cancellations 3.

- 430,671 `Generate`/Initial-Sale = the **bulk legacy install-base load** (predates the flow).
- The **17 `Change`** actions (6 Renewals + 11 Upsells) are the real transactional amendments/renewals/upsells — **exactly the "attributes change" events SC-3513 lists.** They are `Type=Change` on **existing** Assets (no new Asset, no `Generate`) → **the create-only flow never fires for them.**

Total Assets: 430,688. Lifecycle-managed: 430,671. Only 1 Apex trigger on Asset: `AssetMigrationQueueClearTrigger` (unrelated — does not touch Description). No other automation writes `Asset.Description`.

### 4a. Change actions (recent, real) — the ones that go stale
`SELECT Id, AssetId, CategoryEnum, CreatedDate FROM AssetAction WHERE Type='Change' ORDER BY CreatedDate DESC` (17 rows), sample:

| AssetAction | Asset | Category | Date |
|---|---|---|---|
| 4nLWC0000038xPN2AY | 02iWC000008dd1hYAA | Renewals | 2026-07-02 |
| 4nLWC0000038vdi2AA | 02iWC000008deKLYAY | Upsells | 2026-07-02 |
| 4nLWC00000383wf2AA | 02iWC000008deyfYAA | Upsells | 2026-06-29 |
| 4nLWC00000337Mc2AI | 02iWC000008MuWoYAK | Upsells | 2026-06-16 |
| 4nLWC00000337Mb2AI | 02iWC000008MuWnYAK | Upsells | 2026-06-16 |

### 4b. Those changed Assets — `Description` is BLANK (delivered field empty)
`SELECT Id, Name, Description, ProductDescription FROM Asset WHERE Id IN (...)`:

| Asset | Name | Description (delivered field) | ProductDescription (locked mirror) |
|---|---|---|---|
| 02iWC000008MuWnYAK | Data Redaction For SECURE Exchange Gateway | **null** | `Users 25-99 \| Subscription` |
| 02iWC000008MuWoYAK | Structural Sanitization For SECURE Exchange Gateway | **null** | `Users 25-99 \| Subscription \| 1 Instance` |
| 02iWC000008dd1hYAA | Cobalt Strike (Renewal) | **null** | `Subscription \| Named User` |
| 02iWC000008deKLYAY | Cobalt Strike (Upsell) | **null** | `Subscription \| Named User` |
| 02iWC000008deyfYAA | Cobalt Strike (Upsell) | **null** | `Subscription \| Named User` |

→ On assets that have been renewed/upsold, the **delivered field (`Description`) is blank** and the **requested field (`ProductDescription`) shows only the static product-level text** — not the config that was actually purchased.

### 4c. Change-path source is NOT an OrderItem
`AssetActionSource` for Change action `4nLWC0000038vdi2AA` (Upsell): 2 sources, `ReferenceEntityItemId` = `14CWC000001S9UP2A0`, `14CWC000001S9UQ2A0` — **key prefix `14C`, not `802` (OrderItem)**. `SELECT Id FROM OrderItem WHERE Id='14CWC000001S9UP2A0'` → 0 rows. So even if the flow were made to trigger on update, its `OrderItem`-by-Id resolution would not resolve a Change action's source. The change-path source shape differs from the Generate-path.

---

## 5. Create path (initial population) — WORKS. Verified live.

Flow (re)deployed 2026-07-06 21:13. `Generate` assets created minutes later:
`SELECT Id, Name, Description, ProductDescription, CreatedDate FROM Asset WHERE Id IN (...)`:

| Asset | Created | Description (STAMPED, dynamic) | ProductDescription (static mirror) |
|---|---|---|---|
| 02iWC000008kuVhYAI | 07-06 21:18 | `beSECURE - Cloud-Based \| Devices: 1001-2000 \| One Time \| Cloud Based` | `Devices 1-10 \| Subscription \| Monthly` |
| 02iWC000008kvl3YAA | 07-06 21:34 | `BoKS Administration License Fee` | `Other` |
| 02iWC000008kvl4YAA | 07-06 21:34 | `Powertech Identity & Access Manager (BoKS)-NewMaintenance \| Standard` | `New Maintenance \| Standard` |
| 02iWC000008kvl5YAA | 07-06 21:34 | `Powertech Identity & Access Manager (BoKS) \| 100 Node Bundle \| Standard` | `Perpetual \| Standard` |
| 02iWC000008kvl6YAA | 07-06 21:34 | `beSECURE - Cloud-Based \| Devices: 1001-2000 \| One Time \| Cloud Based` | `Devices 1-10 \| Subscription \| Monthly` |

Proves: (a) async create stamp works end-to-end; (b) the **flat/attribute-less** fix works — `BoKS Administration License Fee` (0 ProductAttributeDefinition rows) gets its Product Name instead of blank; (c) the **delivered `Description` is the correct dynamic value**, while the **requested `ProductDescription` shows a stale/generic mirror** (`Devices 1-10 | Subscription | Monthly` on a 1001-2000-device one-time line) — which is *why* the writable field was chosen, and simultaneously why leaving `ProductDescription` in play would mislead.

---

## 6. Layout visibility — Description IS surfaced

`Layout:Asset-Asset Layout` (the only Asset layout; last modified 2026-06-23 by Marc DeBrey) contains a **"Description Information"** section with `<field>Description</field>`. It does **not** contain `ProductDescription`. So the delivered value is visible to users under a section labeled "Description Information" / field label "Description" — not under the "Product Description" label the ticket screenshot circled.
