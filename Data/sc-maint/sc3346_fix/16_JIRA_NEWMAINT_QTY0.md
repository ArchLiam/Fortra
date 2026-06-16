# Jira ticket drafts — New-Maintenance $0 (paste-ready)

Two tickets: **TICKET 1 (Mode A — Joe's line)** and **TICKET 2 (Mode B — separate defect)**.
The Jira editor auto-converts pasted Markdown.

---

## TICKET 1 — Mode A (Joe's reported line)

**Work type:** Bug   **Priority:** High   **Components:** Pricing / RLM
**Links:** relates to SC-3346 (parent), SC-3403 (peer review)

### Summary
```
New-Maintenance line prices to $0 — asset-amendment/renewal births the line with Quantity 0 (no New-business quantity normalizer)
```

### Description

> 🔴 **A New-Maintenance line nets $0** and stays $0 after **Reprice All**. Setting Quantity ≥ 1 + reprice *appears* not to help — because the quantity edit does **not save** on an Accepted quote. Raised by **Joe (Fortra)**.

#### 🎯 Root cause (empirically confirmed 2026-06-15, live FortraUAT)
The New-Maintenance line is **born with `Quantity = 0` only when it is created by an asset-copy QuoteAction** (`Type IN Amend / No Change / Renew`, off an existing maintenance Asset). Its **per-unit price is correct** ($355 × 20% = **$71**), but `$71 × 0 = $0`. The qty=0 is the *only* thing wrong.

**Proven by controlled live tests — the discriminator is the asset-copy QuoteAction, NOT the AutoAdd rule:**

| Creation path | QuoteAction? | Born qty | Net |
|---|---|---|---|
| Greenfield **Configurator AutoAdd** (rule `14OWC0000022ULp2AM`) | no | **1** | **$62.48** ✅ |
| Manual add | no | **1** | $71 ✅ |
| **Asset-copy (Amend / No-Change / Renew)** | **yes** | **0** | **$0** ❌ |

- A fresh Draft quote with `PIA-PIA-NRPS-PIAP` auto-added the maintenance SKU at **qty 1 / $62.48** — so **the AutoAdd rule is fine and must NOT be edited.**
- Joe's line (and the repro line) carry an **Amend / No-Change QuoteAction** off source Asset `02iWC000008DFvvYAG` (qty 1); the platform asset-copy clones it into a new line with `Quantity 0` (`StartQuantity=1`).
- The only quantity-normalizer in the build, `RenewalAssetQuantityHandler`, is **renewal-gated** and never fires on an Amend/No-Change asset-copy. **No New-business / amend equivalent exists.**

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
1. Take a quote whose maintenance line was created by an **asset amendment / renewal / no-change** (i.e. the line carries a QuoteAction off an existing maintenance Asset) — e.g. Joe's `Q-Wren - Test Pricebook 2`.
2. Observe the `-NewMaintenance` line is born **Quantity 0** (`StartQuantity=1, EndQuantity=1`).
3. **Reprice All** → maintenance line **Net = $0** (per-unit $71 × 0 qty).
4. Try to set Quantity = 1 on the **Accepted** quote + Reprice → **does not change / does not persist** (RLM editor won't commit on Accepted+IsSyncing).

> ⚠️ A **greenfield** add (new Draft quote → add `PIA-PIA-NRPS-PIAP`) does **NOT** reproduce this — it births qty 1 / $62.48. The bug is specific to the asset-copy path.

#### ✅ Expected vs ❌ Actual
- **Expected:** auto-added maintenance line inherits the license quantity → Net/unit = $355 × 20% = **$71** (× qty, less partner discount).
- **Actual:** born Quantity 0 → **$0**, and qty cannot be corrected on an Accepted quote.

#### 🛠️ Proposed fix — Apex normalizer (rule edit ruled out)
- Generalize **`RenewalAssetQuantityHandler`** (or add a sibling) to normalize **any asset-copy line**: `QuoteAction.Type IN (Amend, No Change, Renew)` AND `Quantity <= 0` AND `StartQuantity > 0` → set `Quantity = StartQuantity` (the source-asset quantity). Wire into the existing `QuoteLineItemTrigger` after-insert hook. One place, covers all maintenance products.
- ⛔ **Do NOT edit the AutoAdd rule** `14OWC0000022ULp2AM` (or the other 198) — greenfield auto-add already births qty 1 (proven). Config edits are unnecessary and don't address the asset-copy path.
- **Spec gate:** the intended quantity rule is **not in the SDD** — confirm "maint qty = source asset/license qty" with Nir/Marc before building.

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
