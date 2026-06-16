# SC-3419 — Runtime test results (FortraUAT, 2026-06-16, owner-authorized)

Owner authorized live testing ("debug log turned on. go ahead and test it."). All tests below were run read/write against FortraUAT. Diagnostic Apex: `Data/sc3419/diag/`.

## Summary

| Test | What it proves | Result |
|---|---|---|
| **A** — sync collision re-confirm (rolls back) | The native optimistic-lock collision is still live today | ✅ `INVALID_API_INPUT "the asset was updated by another process"`, `ok=0 bad=1`, **2 SOQL / CPU 937 / 0 DML rows** → deterministic, not a governor limit |
| **B1** — re-fire 00095470 in place | Whether AC5 can recover by re-activating the real order | ❌ **BLOCKED** — `CANNOT_EXECUTE_FLOW_TRIGGER: "Order Submission to Revenue Orchestrator" process failed … Sales Transaction cannot be processed`. Save rolls back; the async assetize flow never schedules. **New since the 06-15 E2E.** |
| **C** — V14 success **clears** an assetization error | AC4 (clear) at runtime | ✅ seeded `"Assetization failed: SC3419-SEED"` → order assetized (Asset `02iWC000008MyfFYAS`, AssetAction `Generate`) → field **cleared to null** |
| **N** — V14 success **does not clobber** a Workday error | AC4 (no-clobber) at runtime | ✅ seeded `"Workday: SC3419-WD-ERR"` → order assetized (AAS=1) → field **retained** unchanged |
| (incidental) | Asset granularity in this org | ✅ a single Quantity=1 line produced a **new** asset via `Generate` (not a merge) → **per-unit granularity**, supporting the AC5 "32 Assets" expectation |
| (incidental) | Fresh orders still activate today | ✅ both throwaway orders activated first-time without the orchestration block → the B1 block is specific to **re-submitting** an already-submitted order |

## Detail

### Test A — collision still deterministic (safe, rolled back)
`Data/sc3419/diag/test_a_collision.apex` — re-invoked `createOrUpdateAssetFromOrder('801WC00000kYmw8YAC')` inside a savepoint, rolled back. Same 5 pre-existing account assets as the SC-3415 capture (2 CLSAAS, 1 PIAMBK, 2 PIAP; SEAW=0). Outcome identical to 06-15: deterministic lock collision at 2 SOQL.

### Test B1 — in-place re-fire is now blocked (material for AC5)
`Data/sc3419/diag/test_b1_refire.apex` (Apex `update`, the SC-3415 E2E method) and `sf data update record` both throw the same `CANNOT_EXECUTE_FLOW_TRIGGER`. A **synchronous** record-triggered flow ("Order Submission to Revenue Orchestrator") now faults on the `Status → Activated` change for this already-submitted order and **blocks the save entirely** — so the order's Status was never changed (clean rollback, still "Order Complete") and the AsyncAfterCommit `Fortra_Assetize_Order` never ran.
**Implication:** AC5 recovery **cannot** re-fire 00095470 in place. It must **rebuild from the quote** (the runbook's preferred path) or go via a platform case. (Interesting aside: this submission flow *blocks* on its fault — the opposite of the assetize flow's silent swallow that SC-3419 fixes.)

### Tests C & N — V14 success path proven on the real field
Two throwaway 1-line PIAP orders on test account `001WC00000kpGHxYAM`:
- **C** `801WC00000kt4GfYAI` (`Data/sc3419/diag/test_c_clear.apex`): pre-seeded `Order_Integration_Error_Messages__c = "Assetization failed: SC3419-SEED"`, then activated → assetized successfully (AssetActionSource `4nMWC0000046n5N2AQ` → AssetAction `4nLWC00000338qX2AQ` Type `Generate` → Asset `02iWC000008MyfFYAS` PIAP, 18:52:49Z) → field **cleared to null**. Because V14's *only* clear path is the post-success `Clear_Assetization_Error`, a null result proves the success branch ran and cleared correctly.
- **N** `801WC00000kt4GgYAI` (`Data/sc3419/diag/test_n_noclobber.apex`): pre-seeded `"Workday: SC3419-WD-ERR"`, then activated → assetized (AAS=1) → field **retained** unchanged. Proves the `StartsWith "Assetization failed"` gate prevents clobbering non-assetization integration errors.

## Updated AC verification status

| AC | Before testing | After this session |
|---|---|---|
| AC1 surface fault | static-verified | static-verified + the same `recordUpdate` mechanism now **runtime-proven** via C/N success writes; fault stamp was runtime-proven on the equivalent V13 element (06-15). **Residual gap:** a live fault-stamp on the *real* field needs the collision, which needs the 00095470 rebuild (AC5). |
| AC2 assetize incl future-dated | live-verified | re-confirmed — both fresh orders assetized today |
| AC3 never writes Status | static-verified | corroborated — flow's success writes touched only the error field |
| AC4 clear without clobber | static-verified | ✅ **RUNTIME-PROVEN** (Tests C + N) |
| AC5 recover 00095470 → 32 | open | **in-place re-fire BLOCKED** (Test B1) → must rebuild from quote; per-unit granularity (Test C) supports the 32 target; needs owner go/no-go on the rebuild |

## AC5 recovery — EXECUTED (rebuild from quote, owner-authorized)

Because in-place re-fire is blocked (Test B1), AC5 was executed by **rebuilding** 00095470 as a Quantity-based order on the **same account** (`001WC00000XiZP4YAN`), mirroring its line fields. Build/activate Apex: `Data/sc3419/diag/build_recovery.apex` + `activate_recovery.apex`.

**Recovery order 00095536 (`801WC00000kswTSYAY`) — 4 Quantity lines:** PIAP ×10, PIAMBK ×10, SEAW ×6, CLSAAS ×6. No maintenance decomposition (clean OneTime lines → 0 `OrderItemDetail`). Repriced ready=true; activated first-time (no orchestration block).

**Result — collision ELIMINATED, assets generated:**
- `Order_Integration_Error_Messages__c = null` → V14 success path; **no fault** → the Quantity de-dup removed the multiple-writers-per-Asset condition. ✅
- **4 Assets created**, all `Status=Installed`, `AssetAction.Type=Generate`, `Category=Initial Sale`:

| Asset | Product | Quantity |
|---|---|---|
| 02iWC000008N0QxYAK | PIA-PIA-NRPS-PIAP | 10 |
| 02iWC000008N0QvYAK | PIA-PIA-RNM-PIAMBK | 10 |
| 02iWC000008N0QyYAK | HRM-HRM-RSL-SEAW | 6 |
| 02iWC000008N0QwYAK | HRM-HRM-RSL-CLSAAS | 6 |

**⚠️ This settles the 32-vs-4 question empirically: the answer is 4, not 32.** RLM in this org creates **one Asset per order line, carrying Quantity** (corroborated by Test C: a single Qty=1 line → 1 Asset). De-duping 32 duplicate lines to 4 Quantity lines therefore yields **4 quantity-rolled Assets** (10/10/6/6 = 32 units), **not 32 individual Asset records.** The ticket's "expect 32 Assets" assumed a per-unit granularity this org does not use. **The collision-free path and "32 individual assets" are mutually exclusive**: 32 separate assets require 32 separate lines, which is exactly the shape that collides. To get 32 *individual* assets you would need platform-level serialization of asset creation (or a Salesforce platform fix) — neither exists today.

**Pricing caveat:** 00095536 was priced at catalog unit price × Quantity (TotalAmount $17,340), which differs from 00095470's original $4,189 (the original carried decomposition/discounts). 00095536 faithfully recovers the **assets/quantities**, not the original deal economics — if the financials must match, apply the original discounts to the rebuilt lines.

**Reconciliation for the owner:** 00095470 still exists, assetless, and **cannot be recovered in place** (Test B1). 00095536 is its working replacement (assets present). German/Nir should decide whether 00095536 is canonical and whether to cancel/close 00095470, and whether 4 quantity-rolled assets (vs 32 individual) is acceptable for renewal/COLA testing.
- **Contract gap:** 00095536 activated with `ContractId = null` — building the order directly (bypassing the standard submission orchestration that now faults on re-submit) created the **Assets** but not a **Contract** (the original had Contract 00069266). Assets are sufficient for renewal/COLA off the asset lifecycle, but if a Contract is required, the order must be (re)submitted through the orchestration — which is the same "Order Submission to Revenue Orchestrator" path that is currently faulting and may itself need attention.

## Fresh-record reproduction test (owner-requested) — 32 lines on a CLEAN account → 32 Assets, no collision

Owner created a fresh account `001WC00000ktNCrYAM` + draft quote **0Q0WC000003A7D00AK** ("Test LJ", same Fortra pricebook) — **no pre-existing assets**. Asked to replicate 00095470's exact setup and test. (RLM blocks Quote-line DML, so the order was built directly on that account; Apex `Data/sc3419/diag/build_quote_test.apex` + `activate_quote_test.apex`.)

**Order 00095537 (`801WC00000ktRukYAE`) — exact 00095470 replica: 32 separate Qty-1 lines** (PIAP ×10, PIAMBK ×10, SEAW ×6, CLSAAS ×6), 0 `OrderItemDetail`. Activated.

**Result — clean success, the "32 Assets" target MET:**
- `Order_Integration_Error_Messages__c = null` → **no collision, no fault.**
- **32 distinct Assets** (`count_distinct(AssetId) = 32`): PIAP 10, PIAMBK 10, SEAW 6, CLSAAS 6 — **one Asset per line**, all created via `Generate`. Account total = 32 assets.

**This is the decisive RCA confirmation and resolves the 32-vs-4 question from both ends:**
- The **identical 32-duplicate-line shape** that produced **0 assets + collision** on 00095470 produces **32 assets cleanly** on a clean account. ∴ the trigger is **not** the line count/duplication — it is **duplicate same-product lines contending on a PRE-EXISTING matching Asset already on the account** (00095470's account held the matching PIAMBK maintenance asset + others; the clean account holds none, so every line `Generate`s its own new asset).
- "**32 individual Assets**" *is* achievable — on a clean account with 32 separate lines (00095537). "**4 quantity-rolled Assets**" is the alternative (00095536). The collision only appears when **duplicate lines meet pre-existing matching assets** (the real-world re-order/renewal case = 00095470). De-dup via Quantity avoids it on *any* account.
- (The PIAP control corroborates the "pre-existing asset" axis: in the SC-3415 E2E, 12 duplicate *OneTime* PIAP lines on an account that already had PIAP assets did **not** collide — so the contention is specific to the **maintenance/renewal (RNM) line type updating an existing maintenance asset**, which is exactly 00095470's PIAMBK ×10 against German's existing PIAMBK asset. The precise contended line wasn't isolated live because the diagnostic rolls back, but every cross-test is consistent with this.)

## Residual test data (inert, clearly marked `SC3419TEST_*`)
Throwaway orders `801WC00000kt4GfYAI` / `801WC00000kt4GgYAI` (+ their lifecycle assets) on test account `001WC00000kpGHxYAM` can't be API-deleted (RLM immutable `AssetActionSource`). Remove via Setup UI if desired. **Order 00095470 was never modified** — both re-fire attempts rolled back cleanly (still "Order Complete", `Order_Integration_Error_Messages__c = null`).
