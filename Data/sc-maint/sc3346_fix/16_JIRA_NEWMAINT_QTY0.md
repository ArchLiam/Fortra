# Jira ticket drafts — New-Maintenance $0 (paste-ready)

Two tickets: **TICKET 1 (Mode A — Joe's line)** and **TICKET 2 (Mode B — separate defect)**.
The Jira editor auto-converts pasted Markdown.

---

## TICKET 1 — Mode A (Joe's reported line)

**Work type:** Bug   **Priority:** High   **Components:** Pricing / RLM
**Links:** relates to SC-3346 (parent), SC-3403 (peer review)

### Summary
```
New-Maintenance line prices to $0 — auto-add creates the line with Quantity 0 and it cannot be corrected on an Accepted quote
```

### Description

> 🔴 **A New-Maintenance line nets $0** and stays $0 after **Reprice All**. Setting Quantity ≥ 1 + reprice *appears* not to help — because the quantity edit does **not save** on an Accepted quote. Raised by **Joe (Fortra)**.

#### 🎯 Root cause
The auto-added New-Maintenance companion line is **born with `Quantity = 0`**. Its **per-unit price is correct** ($355 × 20% = **$71**), but `$71 × 0 = $0`.
- The line is auto-added by **`ProductConfigurationRule 14OWC0000022ULp2AM`** ("Year 1 Maintenance Sku added to Powertech IAM Perpetual"; Active; fires on license `PIA-PIA-NRPS-PIAP` + Quote Type = New). Its AutoAdd action has **no quantity parameter**, so the line is born qty 0 even though the source license/asset is qty 1 (`StartQuantity=1, EndQuantity=1, Quantity=0`).
- The only quantity-normalizer in the build, `RenewalAssetQuantityHandler`, is **renewal-gated** and never fires on a New-quote maintenance line. **No New-business equivalent exists.**

#### 🟠 Why "set Quantity = 1 + Reprice" doesn't work
The maintenance line's field history shows **no Quantity change ever** — the qty=1 edit **never committed**. The quote is **`Accepted` + `IsSyncing`**, so the RLM line editor doesn't commit the change (it's *not* a field-level lock). **Quantity is the correct lever — it just must be set on a Draft quote.**

#### 🧾 Example (live in UAT)
| Field | Value |
|---|---|
| Quote | `Q-Wren - Test Pricebook 2-2026-06-15` (`0Q0WC0000039Vm10AE`, **Accepted/IsSyncing**) |
| Line | Powertech IAM (BoKS)-NewMaintenance — `PIA-PIA-RNM-PIAMBK` |
| Quantity | **0** (born qty 0 via auto-add) |
| Source List Price | $355 ✅ · Maintenance Type | Standard → 20% ✅ |
| Expected net/unit | **$71.00** (355 × 20%) |
| Actual net / list | **$0.00** / $0.00 ❌ |

> ℹ️ `List Price = 0` is **normal** for derived maintenance lines — the price lands in the **Net** fields. The bug is purely **Net = $0** caused by **Quantity = 0**.

#### 🔁 Steps to reproduce
1. New quote → add perpetual license `PIA-PIA-NRPS-PIAP`.
2. The `-NewMaintenance` line auto-adds alongside it (same instant) with **Quantity 0**.
3. **Reprice All** → maintenance line **Net = $0**.
4. Try to set Quantity = 1 on the (Accepted) quote + Reprice → **price does not change** and the quantity does not persist.

#### ✅ Expected vs ❌ Actual
- **Expected:** auto-added maintenance line inherits the license quantity → Net/unit = $355 × 20% = **$71** (× qty, less partner discount).
- **Actual:** born Quantity 0 → **$0**, and qty cannot be corrected on an Accepted quote.

#### 🛠️ Proposed fix
- **Option 1 (preferred, config):** add a **quantity parameter** to `ProductConfigurationRule 14OWC0000022ULp2AM` so the AutoAdd sets `Quantity = triggering license quantity` *(verify the Configurator AutoAdd action supports a qty/expression param)*.
- **Option 2 (code):** add a New-Maintenance analog of `RenewalAssetQuantityHandler` (normalize qty from `StartQuantity`/`SourceAsset.Quantity` on insert), wired into the existing `QuoteLineItemTrigger` after-insert hook.
- **Spec gate:** the intended New-Maintenance quantity rule is **not in the SDD** — confirm "maint qty = license qty" with Nir/Marc before building.

#### 💥 Impact
- New perpetual sales' first-year maintenance lands at **$0** → understated quote/order totals + downstream Workday revenue.
- Live: **6** such `qty=0` lines currently in UAT (query, not a fixed count).

#### 👤 Owner / area
SC-3346 Maintenance Derived Pricing build — **Nir Kailash**. Fix is rule/Apex (not a procedure edit).

#### Workaround (until fixed)
Set the maintenance line Quantity to the license quantity **on a Draft quote** (before accept/sync) and reprice → $71/unit.

---

## TICKET 2 — Mode B (separate defect; NOT Joe's line)

**Work type:** Bug   **Priority:** Medium   **Components:** Pricing / RLM
**Links:** relates to SC-3346

### Summary
```
Some New-Maintenance lines net $0 at Quantity >= 1 — native derived-pricing fails to bind the contributor for duplicate/anomalous companion lines
```

### Description

> 🟡 A small set of New-Maintenance lines net **$0 even with Quantity ≥ 1 and a populated Source List Price** — a different mechanism from the Quantity=0 issue (TICKET 1).

#### 🎯 Root cause (per current evidence)
Priced by the **native `DerivedProductsRenewals` engine (container seq 5)**, which **fails to bind the contributor** for duplicate/anomalous-provenance companion lines. **Byte-identical-twin proof:** `broQ4` (Net 0) vs `broR4` (Net **462** = 0.23 × 2008) on the **same quote, same product (`FIM-FIM-RNM-CCMLSE`), same Source List Price, identical attributes** — the only difference is update/binding provenance.
- The V14 7-tier `DerivedPricingFormula` is **correct — do not change it.**

#### 🔁 Affected
~2 lines live (`broQ4`, `DAuh4`) — re-baseline by query, not a fixed count.

#### 🔬 Next step
Capture a **FINEST pricing / expression-set debug log** on an authorized reprice to confirm whether the native step executes-but-drops-the-write vs never-binds, then fix binding and/or clean duplicate companion data.

#### 👤 Owner
SC-3346 — **Nir Kailash / Marc DeBrey**.
