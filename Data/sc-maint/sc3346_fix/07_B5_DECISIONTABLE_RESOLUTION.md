# SC-3346 B5-DECISIONTABLE — Resolution (2026-06-14, FortraUAT)

## Verdict: NOT a SC-3346 build defect → reclassify out of scope. It is a genuine (low-urgency) platform-infra
## item with a data-proven, UI-only fix runbook.

## Root cause — confirmed live
`DecisionTable Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`):
- `Status=Active`, **`RefreshStatus=Failed`**, **`LastSyncDate=None`** (never successfully synced in its lifetime),
  `SourceObject=AssetActionSource`.
- **`RefreshFailureReason = "common.exception.ApiException: Hash Key Group contains more than 200 rows"`.**
- `AssetActionSource` = **430,335 rows**. The hash key is too coarse: grouped at Product (PricebookEntry) grain, the
  top buckets hold **7,837 / 6,548 / 6,103 / 5,776 / 5,697** rows — far over the platform's **200-row** group limit.
  So the refresh fails on the very first sync and the table has no data.

## OFF the SC-3346 build path (decisive)
- The **active V14 SC-3346 pricing procedure (`Rev_Mgmt_Default_Pricing`) has ZERO references** to the decision table
  or `AssetActionSource` — anywhere in the procedure (grep = 0).
- SC-3346 renewals price via **Quote→Order carry-forward** (the stamp flow + `MaintenanceOrderDecompositionService`),
  not this native-discovery index — proven by renewal `00095475` pricing correctly while this table is `Failed`.
- → **B-5 does not gate SC-3346 build readiness.** It is the org-wide native discovery path's index
  (`Salesforce_Default_Pricing_Discovery_Procedure_v2`, 3 versions, `IsRealTime=false`), not the SC-3346 procedure.

## Fix (data-proven) — re-key the hash to a high-cardinality, non-null column
The 200-row overflow is purely a **hash-key cardinality** problem:
- Current coarse key → buckets up to 7,837 rows (fails).
- A finer, **asset-action / asset-grain** key collapses buckets to ~1–2 rows (data-proven: grouping at the asset-line
  reference grain yields a top non-null bucket of **2** rows; 170,371 distinct values).
- **Caveat for the platform team:** do **not** key on `ReferenceEntityItemId` alone — 254,122 rows have it null, which
  would form a single 254K-row bucket that still overflows. Use a **populated** high-cardinality key (e.g. the
  Asset / AssetAction grain), or a composite that is non-null + ≤200 per bucket.

### Runbook (UI-only, maintenance window — the owner/platform team executes)
1. Setup → **Decision Tables** → `Asset_Action_Source_Entries_Decision_Table_V2` → add a high-cardinality, **non-null**
   Equals key column (Asset / AssetAction grain) so no hash bucket exceeds 200 rows.
2. **Maintenance window:** the table is referenced by the org-wide `Salesforce_Default_Pricing_Discovery_Procedure_v2`
   (3 inactive-realtime versions) — coordinate so the discovery path isn't disrupted during the edit/refresh.
3. **Refresh/Sync** the table → confirm `RefreshStatus=Complete`, `LastSyncDate` populated.
4. **Do NOT use a metadata deploy** for the re-key — `DecisionTable` has a documented round-trip bug; the change must
   be made in the UI.

## Net
B-5 is a real but **off-critical-path** platform-infra issue (a >12-month-broken native-discovery index). It is **not**
a SC-3346 build defect and does not block SC-3346 build-readiness → **reclassified out of SC-3346 scope.** The fix is a
**UI-only decision-table re-key in a maintenance window**, executed by the platform/RCA team (not deployable by code).
The diagnosis is confirmed live and the re-key direction is data-proven above.
