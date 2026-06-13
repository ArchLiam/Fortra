# 10 — B-5 maintenance-window runbook (in SC-3346 scope, per owner decision 2026-06-13)

**Goal:** make `Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`) refresh succeed by re-keying the hash to Asset-grained.
**Fix (data-proven):** add **one** Equals INPUT column — Object=Asset, Field=`Id`, fieldPath=`AssetActionId.AssetId.Id`, Operator=Equals, Required=true, seq 7 → `conditionCriteria` becomes `1 AND 2 AND 3 AND 4 AND 5 AND 6 AND 7`. (`GROUP BY AssetId HAVING COUNT>200` = 0 buckets; ~1 row/asset.)
**Why a window:** the table can't be deactivated/edited while 3 active expression-set versions reference it → those must be deactivated first → **org-wide Pricing Discovery is OFFLINE for the window** (every quote/order reprice across all tickets can fail/misprice while down). DecisionTable metadata does NOT round-trip → **Setup UI only**, no CI rollback.

## Pre-window (read-only, no impact)
1. **Confirm the table is on the failing path** (the open question): run a real B1 "renew both assets at once" repro and confirm it fails *before quote creation* via the native asset-renewal path. If renewals only ever go through Q2O carry-forward, B-5 may not be exercised — settle this first.
2. Re-confirm the 3 referencing **ExpressionSetVersion** IDs are still active (they churn): `Salesforce_Default_Pricing_Discovery_Procedure_v2_V1` (9QMWC000000227N4AQ), `Salesforce_Default_Pricing_Discovery_Procedure_V1` (9QMWC0000001qNx4AI), `Stolle_Rev_Mgmt_Pricing_Procedure_V1` (9QMWC0000001DzJ4AU). `SELECT Id,ApiName,VersionNumber,IsActive FROM ExpressionSetVersion WHERE IsActive=true`.
3. Snapshot rollback baseline: retrieve the table metadata; note the exact active-version set.
4. Confirm 20-refreshes/hour cap headroom (leave room for ≥2 retries). Pick a **low-traffic window** with discovery-offline approved.

## In-window (Setup UI; discovery DOWN from step 1→6)
1. **Deactivate the 3 referencing versions** — per-row in Setup → each procedure → Versions → **Deactivate**. **NEVER** the Context Def Manager "Reactivate All Dependencies" (it set 8 versions active = the corruption we hit). Verify 0 of those 3 active.
2. **Deactivate the table** (now unblocked).
3. **Add the Asset.Id Equals INPUT column** (seq 7) in the Decision Table editor — mirror the existing `AccountId` column's Asset-domain navigation, landing on the Asset's `Id`.
4. **Reactivate the table** → **Refresh**. Wait for `RefreshStatus=Completed` (retry if Refreshing/Failed; mind the 20/hr cap).
5. **Reactivate exactly the 3 versions** (per-row Activate). Verify only the intended set is active (no extras — this is where the "8 active" corruption happened last time; check via `ExpressionSetVersion WHERE IsActive=true`).
6. **Context resync** `SalesTransactionContextExt_v2` if discovery binding needs it (verify with a reprice — no `contextDefinitionName` gack).

## Validate (don't stop at RefreshStatus)
- `SELECT Status, RefreshStatus, LastSyncDate, RefreshFailureReason FROM DecisionTable WHERE Id='0lDa50000007BJhEAM'` → **Completed** + non-null `LastSyncDate` + empty failure reason.
- Re-retrieve table metadata → 7 input columns; seq-7 Asset.Id Equals present.
- `ExpressionSetVersion WHERE IsActive=true` → exactly the expected set (the 3 + Product_Discovery + Rev_Mgmt V140), no extras.
- **B1 repro:** renew both assets at once → reaches quote creation, prices non-zero (not silent $0).
- Discovery back up: a normal new-business add + reprice completes clean.

## Rollback (UI only — no metadata fallback)
Deactivate the 3 versions → deactivate table → remove the seq-7 column → reactivate table → Refresh → reactivate the 3 versions → resync. (The pre-edit table had no Asset.Id column / `conditionCriteria 1..6`.)

## Open prerequisites before scheduling
- The **B1 native-renewal repro** (pre-window step 1) — confirms B-5 is actually on a failing path.
- A **fresh explicit UAT deploy/DML ack** + an approved **low-traffic window** (org-wide discovery offline).
