# 🎯 SC-3372 — Root Cause Identified & Verified (UAT)

> **TL;DR:** Not a software bug. The license **EFT 8 Continuum** is missing a **Term-Based (annual) price entry**, so its maintenance line has no term price to derive from → *"contributing products are missing."* **Fix is data/config only.** Verified live in UAT, then reverted.

| | |
|---|---|
| **Status** | ✅ Root cause **confirmed** (live-tested) |
| **Type** | 🗂️ Data / product-setup gap — **no code/flow/procedure change** |
| **Blocker** | ❓ Needs a product decision + the real list price |

---

## 🔍 Root Cause

Maintenance products (e.g. *EFT 8 Continuum-NewMaintenance*) are **priced by derivation** from the contributing license's **Term-Based / annual** price — **not** its One-Time price.

The license **`GS-GSE-NRPS-E8CP`** is currently set up with:
- ✅ a One-Time price entry — but priced at **$0**
- ❌ **no Term-Based-Annual price entry at all**

➡️ With no term price to derive from, the engine flags the contributing product as **"missing."**

---

## 🧪 How It Was Confirmed

In UAT, temporarily added a Term-Based-Annual price entry to the license (test value **$10,000**) → repriced:

- ✅ Maintenance line derived correctly → **$3,000** (30% of term price)
- ✅ Banner **cleared**
- 🔄 Test data **fully reverted** — no permanent changes left in the org

---

## ⚠️ This Is Not Isolated to One SKU

The recent **Maintenance Derived Pricing** rollout made maintenance pricing depend on contributor reference data (a derived-pricing config row **and** a Term-Based price entry) that **hasn't been fully backfilled** — **~91% of derived-maintenance products are missing the config row today.**

➡️ **Any** perpetual product sold One-Time-only (no Term-Based price entry) will hit this **same error** on its maintenance line.

---

## 🔧 Fix (data/configuration only)

1. Add a **"Term Based - Annual"** selling-model option to `GS-GSE-NRPS-E8CP`
2. Add **Term-Based-Annual price entries** (Standard + Fortra books, all currencies) at the correct price
3. Set the **One-Time** price to the correct value (currently $0)
4. Add the **contributing-product config row** *(already staged in UAT)*

---

## ❓ Decision Needed to Proceed

**Is *EFT 8 Continuum* a real, sellable product missing its price — or not-yet-released / test data?**

- 🟢 **Real product** → provide the correct list price; fix applies immediately.
- 🔵 **Not ready to sell** → close as *"product not yet priced/configured"* (and the maintenance line ideally shouldn't auto-generate for an unpriced product).
