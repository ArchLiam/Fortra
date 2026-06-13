# 06 — B-5 fix plan: Asset_Action_Source decision-table refresh failing

**Status:** scoped 2026-06-12 (read-only, live FortraUAT). Fix identified + data-proven. Needs deploy authorization to apply.

## Root cause (reproduced live)
`Asset_Action_Source_Entries_Decision_Table_V2` (`0lDa50000007BJhEAM`, SourceObject=`AssetActionSource`, ~430,335 rows) fails to refresh: `RefreshStatus=Failed`, `RefreshFailureReason="Hash Key Group contains more than 200 rows"`.

The table's match/hash key is the **two Equals columns: `AssetAction.Asset.AccountId` + `AssetAction.Asset.Product2Id`**. The four date columns are *range* operators (`GreaterOrEqual`/`LessOrEqual`) and the engine excludes range columns from the hash key. So each hash bucket = "all asset-action rows for one Account + one Product" — and a customer who owns hundreds of the same product collides into one oversized bucket.

Live proof (reproduced, correct SOQL relationship path `AssetAction.Asset.*`):
- Baseline (current key): **51 buckets > 200 rows**, 19,797 rows total, **max 1,199**.
- PSM≠null filter alone: 47 buckets (max 686) — insufficient.
- EndDate≠null filter alone: 33 (max 571) — insufficient.
- +PricebookEntryId added to key: 42 (max 793) — insufficient.
- PSM≠null AND EndDate≠null + PBE key: 25 (max 396) — **still insufficient.**
- Data is mostly recent (2025=266K, 2026=96K rows), so it is **not** old migration residue → date-scoping won't help.

> Note: the investigation agent's "StartDate+PBE solves it" was validated only on the single worst bucket and does **not** hold globally. Don't use it.

## The fix (recommended): re-key to the specific Asset
Change the match/hash key from `(AccountId, Product2Id)` to the **Asset** (`AssetAction.Asset.Id` — already an OUTPUT column, "AssetId").

Live proof this works:
- GROUP BY `AssetAction.AssetId` HAVING COUNT>200 → **0 buckets**.
- GROUP BY `AssetAction.AssetId, Product2Id` → **0 buckets**.
- `COUNT_DISTINCT(AssetAction.AssetId)` = **430,327** of 430,335 rows ≈ **1 row per asset** → every hash group ≈ 1 row, trivially under the 200 cap.

Why it's also *more correct*: a renewal renews a **specific asset**, so the lookup should resolve that asset's source/renewal entry — not "every entry for the account+product." Asset-level keying is both the bucket fix and the semantically right key. The table already outputs `AssetId`, confirming asset-granularity is the design intent.

## Blast radius: LOW (the big de-risker)
The active pricing procedure does **NOT** reference this table — 0 grep hits for the table Id / `AssetActionSource` / `Asset_Action_Source` across all 70,448 lines of the live procedure. The table feeds **platform context hydration** (`SalesTransactionContextExt_v2` inherited `AssetActionSource*` nodes) upstream of the procedure, during native asset-initiated renewal. Therefore:
- **No pricing-procedure republish/re-version** is needed → zero blast radius on the shared SC-3393/3372/3359/3384 procedure.
- Disposition = **keep-and-fix the table** (NOT remove a consumer — there is none in the procedure; the "remove native element" guidance was for a different new-business element and was already rejected as unsafe).

## Apply steps (need explicit deploy authorization — UAT)
1. Confirm the DecisionTable is admin-editable (retrieved OK as mdapi `DecisionTable`; metadata at `Data/sc-maint/reverify/b5_dt/`).
2. Deactivate the table; set the match/group key to the Asset Equals column (`AssetAction.Asset.Id`); keep date columns as range filters; keep outputs (TotalPrice/ListPrice/AssetId/NetUnitPrice). No procedure version touched.
3. Reactivate + Refresh (mind the 20 refreshes/hour org cap).

## Validation (don't stop at RefreshStatus)
1. `SELECT RefreshStatus, LastSyncDate, RefreshFailureReason FROM DecisionTable WHERE Id='0lDa50000007BJhEAM'` → require `Completed` + non-null `LastSyncDate` + empty failure reason.
2. Reproduce blocker **B1**: renew the two assets at once → confirm it now reaches quote creation and prices from real source entries (non-zero, not silent $0).
3. Regression sanity: a new-business add (SC-3393) + a discounted reprice (SC-3359/3384) — expected no change (procedure doesn't reference the table).
4. Re-verify after any Gearset deploy / org refresh (refresh state can silently revert).

## UPDATE 2026-06-12 (apply attempt) — reclassify B-5 as OFF the build's critical path
Two findings during the apply changed the plan:

1. **The fix is NOT low-blast-radius after all.** The table cannot be deactivated/edited because it is referenced by **3 active expression-set versions**: `Salesforce_Default_Pricing_Discovery_Procedure_v2_V1`, `Salesforce_Default_Pricing_Discovery_Procedure_V1`, and `Stolle_Rev_Mgmt_Pricing_Procedure_V1`. (My earlier "0 references" was correct only for the *pricing* procedure `Rev_Mgmt_Default_Pricing_Procedure`; the table feeds the *discovery* procedures upstream — `UsageType=PricingDiscovery`.) Editing it requires deactivating the org-wide pricing-**discovery** procedure → high blast radius, change-managed only. The metadata-deploy path is also dead (DecisionTable round-trip validation bug: rejects even the pre-existing `AccountId` field).

2. **B-5 is not on the SC-3346 build's renewal critical path.** The table was created **2025-06-17 and has NEVER synced** (`RefreshStatus=Failed`, `LastSyncDate=null` for ~12 months). Yet renewal order **00095475** was created and priced correctly (Base 71 / Unit 60.64) on 2026-06-11 — via the Q2O carry-forward path (`MaintenanceOrderDecompositionService` persists `Base_Price__c`/`Prior_*`; the formula reads those, not `AssetActionSource`). So the build's renewal mechanism works **without** this table. B-5's "renewing both assets fails before a quote" (B1) is the **native asset-initiated renewal** entry point — a pre-existing platform gap, not a SC-3346 regression.

**Revised recommendation:** Do NOT do the high-risk discovery-procedure deactivation impulsively. Reclassify B-5 as a **separate, change-managed platform/native-renewal item** (entangled with M-3's "too many active discovery procedures" anomaly — 3 active `PricingDiscovery` procedures live: `Salesforce_Default_Pricing_Discovery_Procedure`, `_v2`, `Salesforce_Pricing_Discovery_Procedure`). It should not block SC-3346 sign-off of the build's intended (Q2O carry-forward) renewal flow. Before any fix, get a real B1 "renew both assets" repro to confirm the exact mechanism and whether native asset-renewal is even an in-scope path for Fortra. The fix itself (add Asset Equals column) stays valid — but only executes inside a maintenance window after deactivating the referencing expression-set versions.

## Open question to settle (priority, not the fix)
Does B1's "renewing both assets fails **before a quote is created**" go through the **native asset-initiated renewal** (needs this table via context hydration) or the SC-3346 build's **Q2O carry-forward** path (reads persisted `Base_Price__c`/`Prior_*` via `MaintenanceOrderDecompositionService` — does NOT need this table)? "Before a quote is created" strongly implies the native path → B-5 is on the critical path. Confirm with a real both-assets repro.
