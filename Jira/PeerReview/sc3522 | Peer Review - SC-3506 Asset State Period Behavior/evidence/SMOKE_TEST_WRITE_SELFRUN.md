# Write Smoke Test — Self-Run Lifecycle Events (UI-driven, CLI-verified)

**Org:** FortraUAT · **Account:** Fortra, LLC - Test · **Date:** 2026-07-02 · Each event driven in the UI (Managed Assets → action → Convert to Order → Activate), then verified read-only via `sf data query`.

## Method note
Pure-CLI (headless) generation was **not** cleanly achievable: the Fortra wrapper flows (`Fortra_Create_Renewal_Quote`, `Fortra_Create_Amendment_Quote`) require UI/opportunity **lineage context** (renewal auto-resolves the account's renewal contract; amendment's inner action needs `amendStartDate` the wrapper only derives from UI). Raw Quote/QLI DML is also platform-blocked (RLM). So events were generated in the **UI** and **verified via CLI** — the reliable split. (Setup performed via CLI where safe: linked a Renewal opportunity `RfDWPYA3` to Contract 00069404 via `ContractId`, and set `RZvFBYA1` → Order Processing/Renewal.)

## Results — 3 scenarios, all structure PASS

### 1. AMENDMENT — Cobalt Strike `02iWC000008deKLYAY` (Order 00095676)
- **Actions:** Generate/Initial Sale → **Change/Upsells** (Δqty +2, totQty 3).
- **State periods:** `2026-06-29→2026-06-30` qty1 → `2026-07-01→2027-06-30` qty **3**. Prior end-dated at effective date, new period contiguous. **STRUCTURE ✅**
- 🚩 **Defect:** new period MRR **491.67** for qty 3 (per-unit 492→164); action Δmrr **0** — the 2 added units contributed **$0**. Amendment analog of the renewal zero-price (Asset.PricingSource null carryover gap).

### 2. CANCELLATION — beSECURE `02iWC000008eU4RYAU` (Order 00095677)
- **Actions:** Generate/Initial Sale → **Cancel/Cancellations** (Δqty −1, **TotalCancellationsAmount −206**).
- **State periods:** **still 1** (`2026-06-29→2026-06-30`) — **NO new period ✅**.
- **Header:** CurrentQuantity **0**, CurrentMrr **0**, LifecycleEndDate pulled back to 2026-06-30. **STRUCTURE ✅**
- ✅ **Bonus:** non-zero credit (−206 = 17.17×12) — resolves the peer-review caveat that the org's only prior cancel (08ARwoYAG) was $0/atypical. Negative credit economics **do** flow.

### 3. RENEWAL — Cobalt Strike `02iWC000008dd1hYAA` (Order 00095678)
- **Actions:** Generate/Initial Sale → **Change/Renewals** (Δqty 0, Δmrr **−491.67**).
- **State periods:** original `2026-06-29→2027-06-28` mrr491.67 **preserved** → new `2027-06-29→2028-06-28` (StartDate = prior EndDate +1 day; term = **exactly 1 year**). LifecycleEndDate extended to 2028-06-28. **STRUCTURE ✅** (no 2039 bug — confirms that defect is data-specific to PTC=12, not universal.)
- 🚩 **Defect:** renewal period MRR **0** (Δmrr −491.67 drove it to zero) — the renewal zero-price defect (GAP-2, SC-3350/3346), self-reproduced live.

## Conclusion
The **AssetStatePeriod engine is correct in all three scenarios** — right period count, right effective-date splits, right forward-dating, right contiguity, right quantities, cancellation correctly creates no new period. **Every failure is upstream pricing** ($0 net on amend/renew via the PricingSource-null carryover gap + COLA zero-price). This independently confirms the peer-review verdict: SC-3506's core conclusion (native ASP mechanics are correct) holds; the real defects are upstream and the license-key risk is the $0/wrong price on an otherwise correctly-structured latest period.

## New records created by this smoke test (permanent, shared UAT)
- Orders: 00095676 (amend), 00095677 (cancel), 00095678 (renewal) — all Activated.
- Opportunity: `006WC00000RfDWPYA3` (Renewal, linked to Contract 00069404).
- Asset changes on `deKLYAY` (qty→3), `eU4RYAU` (cancelled), `dd1hYAA` (renewed).
