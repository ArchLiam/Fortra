# 🟢 SC-3419 — RESOLVED (UAT)

### Subscription orders completed as **“Order Complete” but generated zero Assets.** The background asset step was failing **silently**. It’s now **visible, fixed, and verified end-to-end** — a clean rebuild generates all **32 Assets**.

> **TL;DR**
> • **Defect:** asset creation runs in a background step that *swallowed* its own error → order looked complete with **no Assets and no warning.**
> • **Fix (LIVE in UAT):** that failure now writes a visible **“Assetization failed: …”** message on the Order. `Fortra_Assetize_Order` **V14** — no new fields.
> • **Recovery (proven):** the same 32‑line order on a clean account → **32 Assets, no error.**
> • **Real trigger:** *not* the duplicate lines — it’s duplicate **maintenance** lines colliding on an Asset the account **already owns.**

---

## 🐛 What was happening

| | |
|---|---|
| **Symptom** | Order **00095470** activated cleanly (“Order Complete”, Contract created) but produced **0 Assets** — and showed **no error** to the rep. |
| **Why it was hidden** | Asset creation runs in a separate **background (async)** step (`Fortra_Assetize_Order`, which overrides the native Salesforce asset flow). Its error path was set to “end gracefully” → the failure was **silently swallowed.** |
| **Not SC‑3411** | That was an *activation blocker*. Here the order **activated** with all lines fully dated. Different step, different failure. |

## 🔍 Root cause (now pinned by live testing)

The underlying error is a Salesforce **record‑lock collision** —
`INVALID_API_INPUT: “the asset was updated by another process.”` — **deterministic** (re‑ran 3×, 1 query each, so **not** a governor/limit issue).

**The trigger is *not* the 32 duplicate lines.** We proved this directly:

- The **identical 32‑line order on a clean account → 32 Assets, no collision** (order **00095537**).
- It only fails when **duplicate same‑product *maintenance/renewal* lines** all try to update **an Asset the account already owns** — which is exactly 00095470 (its account already held the matching maintenance Asset).

This is **documented Salesforce behavior** for that data shape (matching is by Account + Product; there is **no platform bug/hotfix** to wait on). The genuine **Fortra‑owned defect was the silent swallow** — which V14 fixes.

## ✅ What we fixed — `Fortra_Assetize_Order` V14 (live in UAT, no new fields)

- A failed async asset run now writes **`Order Integration Error Messages = "Assetization failed: …"`** on the Order instead of a silent asset‑less “Order Complete.”
- It writes **only** that field (never Status) → it **can’t loop.**
- On a later success it **clears only** that message → it **won’t wipe** other integration errors (e.g. Workday).
- The native asset action is **unchanged.**

## 🧪 Proof — live UAT tests (owner‑authorized)

| Test | What it checks | Result |
|---|---|---|
| **Recovery — 32 lines, clean account** (00095537) | Can we get the 32 Assets? | ✅ **32 distinct Assets, no collision** |
| **Recovery — Quantity de‑dup** (00095536) | Collision‑free alternative | ✅ **4 quantity‑rolled Assets** (10/10/6/6) |
| **Collision re‑confirm** (00095470) | Is the failure real & deterministic? | ✅ Yes (1 query, instant) |
| **Visibility — clear on success** | Clears its own error | ✅ Cleared |
| **Visibility — don’t clobber Workday** | Leaves other errors intact | ✅ Retained |
| **Normal orders incl. future‑dated** | Healthy path still works | ✅ 8 orders, 48/48 lines assetized |

## ✔️ Acceptance criteria — all met

- ✅ **AC1** — failed async run is surfaced on the Order (not a silent “Order Complete”)
- ✅ **AC2** — a normal order assetizes every line, including future‑dated
- ✅ **AC3** — the surfacing flow never re‑fires itself
- ✅ **AC4** — success clears the assetization error without clobbering Workday
- ✅ **AC5** — **32 Assets recovered** (order **00095537**)

## 📋 For closure & going forward

1. **Use for renewal/COLA testing:** **00095537** (32 clean Assets) is the cleanest record. (00095470 stays as the assetless original — it can’t be fixed in place.)
2. **Rep guidance:** when re‑ordering products an account already owns, use **Quantity on one line**, not duplicate lines.
3. **Prod:** V14 ships on the normal cutover; it makes any future assetization failure **visible**.
4. **Spin‑off:** the *“Order Submission to Revenue Orchestrator”* error that blocks re‑activating an already‑submitted order is a **separate** issue — recommend its own ticket.

---
*Full engineering RCA, the live V14 flow, the collision proof log, all runtime test results, and the cited Salesforce/RLM documentation are attached in the dossier.*
