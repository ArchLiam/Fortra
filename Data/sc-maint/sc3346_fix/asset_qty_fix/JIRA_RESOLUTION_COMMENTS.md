# SC-3410 + SC-3412 — Jira resolution comments (paste-ready, 2026-06-15)

Both tickets cover the same defect (auto-added New-Maintenance derived line priced $0) and are resolved together.

---

## SC-3410 — resolution comment

> ✅ **RESOLVED in UAT.** The New-Maintenance line now prices **$0 → $62.48**, verified live on this ticket's test quote (Q-Wren - Test Pricebook 2). Root cause was **two** defects — *not* the auto-add rule.

### 🎯 Root cause (corrects the ticket premise)
The description's hypothesis — *"the auto-add **rule** sets quantity to 0"* — is **not** the cause. Proven: a greenfield add births the maintenance line at **qty 1** and prices fine. The $0 came from the **asset-copy / amend** path, via two distinct defects:

| # | Defect | Why it produced $0 |
|---|---|---|
| 1 | Born **Quantity 0** | An asset-copy QuoteAction (Amend / No-Change) clones the source asset (qty 1) into a new line at **qty 0**; the only quantity-normalizer was renewal-gated -> never fired for New Maintenance |
| 2 | **Derived net dropped** | The pricing procedure leaves NetUnitPrice null on the asset-copy ("settled") node; the partner posthook then has no net to finalize -> line stuck at "Deferred List" |

Per-unit math is correct: `Source_List_Price 355 x Standard rate 20% x (1 - 12% partner) = $62.48`. (List Price 0 is normal for derived maintenance - price lands in the Net fields.)

### 🔧 Fixes (deployed to UAT)
- **RenewalAssetQuantityHandler** - normalizes New-Maintenance asset-copy lines: Quantity = source-asset qty.
- **PartnerNetPricePosthook** - new fallback: when the procedure leaves a New-Maintenance line at $0, computes Source_List_Price x maintenance_rate (MTD tier) x (1 - partner%).
- **MaintenanceOrderDecompositionService** - computes the order maintenance net at conversion time.

### ✅ Verification (live)
- Repriced this ticket's quote -> maintenance line **$62.48**.
- Greenfield New quote + auto-add -> **$62.48**.
- Tests: handler **28/28**, posthook **52/52** (47 existing + 5 new), zero regressions.

### 📋 Success Criteria
| Criterion | Status |
|---|---|
| Auto-added products created with correct quantity | ✅ |
| Derived Pricing calculated correctly | ✅ |
| No lingering $0 lines | ✅ |
| Clear actionable error if it can't be priced | ⚠️ Not built - separate enhancement (lines now price, so this path isn't hit here) |

### 📦 Order side
Orders use a different pricing path (no posthook). New orders price correctly **at conversion**. An order that was **activated while $0** is damaged data - its OrderItemDetail records lock the price fields - so re-convert from the corrected quote for a clean order.

*Resolved jointly with SC-3412.*

---

## SC-3412 — resolution comment

> ✅ **RESOLVED in UAT** - fixed **jointly with SC-3410** (same defect: auto-added New-Maintenance derived line priced $0). Technical summary below.

### 🎯 Root cause
Two defects on the **asset-copy (Amend / No-Change) maintenance line** - **not** the Configurator auto-add rule 14OWC0000022ULp2AM, which correctly births qty 1:
1. **Quantity 0** at line creation (no New-business quantity normalizer; the existing one is renewal-gated).
2. **Derived net not finalized** - the procedure drops NetUnitPrice on the asset-copy node; the posthook can't discount a net that was never written.

### 🔧 Fix - 3 classes, deployed to UAT
| Class | Change | Tests |
|---|---|---|
| RenewalAssetQuantityHandler | gate-widened -> normalize New-Maint qty = source-asset qty | **28/28** |
| PartnerNetPricePosthook | New-Maint net fallback srcLP x rate x (1-partner%) when procedure leaves $0; handles QuoteLineItem **+ OrderItem** | **52/52** |
| MaintenanceOrderDecompositionService | order conversion-time maintenance net | - |

### ✅ Verified
Original quote 0Q0WC0000039Vm10AE repriced -> **$62.48**; greenfield and deep-clone quotes also **$62.48**.

### ⚠️ Notes / follow-ups
- **Tightly gated** - fires only on New-Maintenance lines the procedure left at $0; cannot affect the ~12k correctly-priced lines.
- **Orders:** the posthook does **not** run on the RLM order pricing path (verified via debug log) - orders are fixed **at conversion** via the decomp service. Activated-with-$0 orders are damaged data (OrderItemDetail price-field lock).
- **Open enhancement:** actionable-error UX for genuinely unpriceable lines (SC-3410 criterion 4) - not built.
- Source, diffs, and tests staged under `Data/sc-maint/sc3346_fix/asset_qty_fix/`.

*Resolved jointly with SC-3410.*
