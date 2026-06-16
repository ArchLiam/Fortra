# SC-3412 — New-Maintenance $0 — Closure Notes (2026-06-15, FortraUAT)

## Outcome
**Code fix: DONE & deployed to UAT (go-forward).** Backfill corrected the real affected line (Joe's).
A few items remain to fully close (live FINEST capture, a No-Change handling decision, Joe's locked records).

## Root cause (final, empirically proven)
A New-Maintenance line is born `Quantity = 0` **only when created by an asset-copy QuoteAction**
(`Amend` / `No Change` / `Renew`) — the platform clones the source asset (qty 1) into a new line with
`Quantity 0`, `StartQuantity 1`. The per-unit price is correct ($355 × 20% = $71); `$71 × 0 = $0`.
- **NOT** the Configurator AutoAdd rule — greenfield add births qty 1 (proven: quote `0Q0WC0000039bwH0AQ`
  auto-added at qty 1 → **$62.48**).
- The only quantity-normalizer (`RenewalAssetQuantityHandler`) was renewal-gated and never fired on new business.

## The fix
`RenewalAssetQuantityHandler` gate-widened to cover New Maintenance asset-copy lines:
- Scope at line level (QuoteAction present + maintenance type + qty ≤ 0), not quote type.
- New-Maintenance branch normalizes `Quantity = source-asset qty`, **without** the renewal `No Change → Renew` flip.
- Constant `QUOTE_ACTION_AMEND = 'Amend'` (matches the stored picklist value).
- Deployed via MDAPI (api 62). Diff + source in this folder.

## Test status
- `RenewalAssetQuantityHandlerTest`: **28/28 pass**, handler coverage **96%** (24 original renewal tests + 4 new
  New-Maintenance/Amend cases). No regressions.
- End-to-end pricing proven separately: greenfield quote priced a qty-1 New-Maintenance line to **$62.48**.

## Backfill result (the existing broken lines)
Ran `applyAssetQuantitiesForQuotes` over the 9 affected quotes:
- ✅ **2 `Amend` lines normalized qty 0→1** — including **Joe's L2 (`0QLWC000003ehR84AI`)**.
- ❌ **7 `No Change` lines blocked** by platform rule: *"Specify 0 in Quantity … action of type No Change."*

### ⚠️ Decision needed (for Nir): No-Change handling
The platform **forbids a positive Quantity on a `No Change` line** — you must flip the action type first
(which is exactly why the renewal path flips `No Change → Renew`). The current New-Maintenance branch does **not**
flip, so it can't normalize a No-Change New-Maintenance line (it errors).
- **All 7 blocked lines are malformed test data** (New-Maintenance product on *renewal* quotes); real new-maintenance
  comes through as `Amend` (like Joe's), which works.
- **Options:** (a) leave as-is — defensively **skip** No-Change for New Maintenance so the handler doesn't throw on
  malformed data (recommended; small handler tweak); (b) flip `No Change → Renew`/`Amend` for New Maintenance too
  (lets them normalize, but changes action semantics on a new-business line — needs care re: downstream order/Workday).

## Verification status
| Item | Status |
|---|---|
| Handler logic | ✅ 28/28 tests, 96% cov |
| Qty normalization (Amend) | ✅ backfill fixed Joe's line (qty 0→1) |
| End-to-end net at qty 1 | ✅ greenfield quote → $62.48 |
| FINEST log of a live reprice | ⏳ pending (see below) |
| Joe's line shows non-zero net | ⏳ pending reprice — his quote is **Accepted**, order 00095503 **Activated** (locked) |

## To fully close
1. **FINEST log:** a *quote* reprice can't be scripted (no API — needs UI). Trace is active on the user; reprice a
   **Draft** quote (e.g. `0Q0WC0000039bwH0AQ`) in the UI → pull the FINEST `ApexLog`.
2. **Joe's records:** his quote/order are locked; net stays $0 until they're repriced through a normal flow or reopened.
3. **No-Change decision** (above) — owner call.
4. (Optional) permission rule `Bash(sf apex run:*)` to allow scripted reprice/backfill without per-call prompts.

## Key IDs
Handler `RenewalAssetQuantityHandler` (api 62) · test `RenewalAssetQuantityHandlerTest` · Joe L2 `0QLWC000003ehR84AI`
· greenfield Draft quote `0Q0WC0000039bwH0AQ` · order engine `commerceorders.PlaceOrderExecutor` (Force).
