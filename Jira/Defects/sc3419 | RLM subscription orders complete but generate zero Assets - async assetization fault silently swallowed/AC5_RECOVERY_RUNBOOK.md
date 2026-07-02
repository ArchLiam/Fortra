# SC-3419 — AC5 recovery runbook (recover 00095470's assets + runtime-prove AC1)

**Goal:** recover Order **00095470**'s missing assets and, in the same pass, observe the V14 fault stamp populate at runtime (the only outstanding AC1 evidence gap). **Owner-authorized** — these steps mutate a shared real order. Read-only pre-work is done; execution is gated.

**Order:** 00095470 = `801WC00000kYmw8YAC` · account `001WC00000XiZP4YAN` · Contract 00069266 (`800WC00000S9jqbYAB`).
**Workday-safe:** `Workday_Sync_Status__c = 'Pending'` (re-firing won't push a bad payload).

---

## What we already know (read-only, done)

- The fault is **deterministic** — `createOrUpdateAssetFromOrder` on 00095470 → `INVALID_API_INPUT "the asset was updated by another process"` at **2 SOQL / 0 CPU** (`evidence/k2_capture_collision_proof.log`). Not a governor limit.
- **5 pre-existing account assets** for the 4 products are the collision surface: PIAMBK `02iWC000008DFvvYAG` (×1, the cleanest 10-lines-→-1-row funnel), PIAP `02iWC000008DFvxYAG` + `02iWC000008LagcYAC` (×2), CLSAAS `02iWC000007kLByYAM` + `02iWC000007mWZfYAM` (×2); SEAW = 0 (new-row, no collision).
- The order is **32 duplicate lines** (PIAMBK×10 / PIAP×10 / SEAW×6 / CLSAAS×6), one PIAMBK line qty 0 + 2 `OrderItemDetail` (maintenance decomposition).
- Plain duplication alone does **not** collide (synthetic 2-/12-line OneTime orders assetized) — it's the **duplicate + maintenance-decomposed + pre-existing-asset** combination.

---

## Step 1 — FINEST re-fire AS-IS (captures AC1 runtime proof + pins the contended Asset)

Purpose: (a) prove the **V14 fault stamp** writes at runtime, (b) name the exact contended Asset in the async interview.

1. Create a `TraceFlag` (DebugLevel FINEST, all categories) for the activating user **and** the Automated Process user, ~30 min window (Tooling API).
2. Snapshot: `Order_Integration_Error_Messages__c` (= null now) and the 5 assets' `SystemModstamp`.
3. Re-fire: `Order.Status → 'Activated'` on 00095470 (it is currently the custom label "Order Complete" / StatusCode Activated — set Status so the start re-arm `Status EqualTo 'Activated'` + `doesRequireRecordChangedToMeetCriteria` fires).
4. Wait ~15s for the `AsyncAfterCommit` `Fortra_Assetize_Order` interview.
5. **AC1 proof:** confirm `Order_Integration_Error_Messages__c = "Assetization failed: We couldn't process your request because the asset was updated by another process."`
6. Restore `Order.Status → 'Order Complete'` (the stamp persists — it's accurate).
7. Pull the async `ApexLog`; find the **Asset Id** in the error context and the **DML/SOQL on Asset** immediately before the failure → that names the contended asset (expected: the PIAMBK `02iWC000008DFvvYAG` funnel).

> Synchronous alternative (no flow, full log, auto-rollback) — re-run the `evidence/k2_capture_collision_proof.log` Apex with FINEST to re-pin the asset without mutating the order. Use this first if a mutation window isn't yet authorized.

---

## Step 2 — Restructure to clear the collision (de-dup via Quantity)

Collapse the 32 duplicate lines to **4 lines carrying Quantity** (the doc-endorsed shape, `OFFICIAL_RCA_REFERENCES.md` §B.3):

| ProductCode | Quantity | Model | Notes |
|---|---|---|---|
| PIA-PIA-NRPS-PIAP | 10 | OneTime | |
| PIA-PIA-RNM-PIAMBK | 10 | OneTime | absorbs the qty-0 line + its 2 `OrderItemDetail` decomposition rows |
| HRM-HRM-RSL-SEAW | 6 | TermDefined | future-dated; new-row (no collision) |
| HRM-HRM-RSL-CLSAAS | 6 | TermDefined | future-dated |

Because activated orders are largely immutable (RLM `AssetActionSource` immutability), the practical paths are, in order of preference:
1. **Rebuild from the quote** — clone quote `0Q0WC0000037rAj0AI` with Quantity-based lines, convert → new order → activate. Cleanest; leaves an audit trail; doesn't fight order immutability.
2. **Amendment / change order** against Contract 00069266 to consolidate, if the org's amendment flow supports it.
3. **Salesforce platform case** with the FINEST repro if the native `createOrUpdateAssetFromOrder` is judged a platform concurrency bug for decomposed lines (W2: no Known Issue exists today, so this is the escalation-of-last-resort).

---

## Step 3 — Re-trigger assetization & verify

1. Re-fire the restructured order's activation (or run `createOrUpdateAssetFromOrder` for it).
2. Confirm **`Order_Integration_Error_Messages__c` is cleared** (AC4 success-clear path) — proves the StartsWith-gate clears the prior "Assetization failed: …" stamp without touching Workday errors.
3. **Count the resulting Assets and settle the count:**
   - **Per-unit org (expected):** 10 + 10 + 6 + 6 = **32 Assets** ✅ matches the ticket.
   - **Per-(Account+Product) rollup:** 4 Assets with Quantity 10/10/6/6.
   The org's existing assets are Quantity = 1 per row (→ per-unit → 32), but **this run is the authoritative test.** Record the actual count in the close-out; do not pre-commit to 32 in writing without it.

---

## Analysis targets (from the FINEST log)
- **Which Asset Id** raises the optimistic lock — existing (update) or a sibling line's freshly-created one? (Expected: existing PIAMBK `02iWC000008DFvvYAG`.)
- **How many operations** touch that asset in one action invocation (the contending "other process").
- Whether the contention maps to the **maintenance parent ↔ decomposed-child** pair (`OrderItemDetail`).

## Remediation decision tree (after the log)
- **Multiple order lines updating ONE shared asset concurrently** → de-dup via Quantity (Step 2) — the primary path.
- **Native platform concurrency bug in `createOrUpdateAssetFromOrder` for decomposed lines** → Salesforce platform case with the FINEST repro.
- **Fortra maintenance-decomposition writes the asset out-of-band** → fix in the decomposition/asset path (Fortra-owned).

## Status
Runbook ready; read-only pre-work complete. Steps 1–3 are **owner-authorized** (Step 1's sync variant rolls back; the async re-fire and Step 2 rebuild mutate data). Not yet run — this is the single remaining SC-3419 action (AC5 + the AC1 runtime confirmation).
