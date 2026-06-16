# 🎯 SC-3415 — RCA done + visibility fix DEPLOYED (UAT) · two distinct issues, neither owned by SC-3411

@German Wren — investigation done and the silent-failure fix is **deployed to UAT**. The headline symptom is a **new** failure that SC-3411 does **not** fix.

| | |
|---|---|
| **Status** | ✅ Defect A visibility fix deployed (UAT) · collision mechanism + Defect B still open |
| **Scope** | UAT only |
| **Repro** | Order **00095470** (32 lines) + draft quote lines on Q-00095507 / Q-00095497 |

> **Deployed (UAT, 2026-06-15):** `Fortra_Assetize_Order` **V14** — **no new fields**. A failed async asset-generation run now writes **`Order Integration Error Messages = "Assetization failed: …"`** on the Order instead of a silently asset-less "Order Complete" (and clears it on a later success). Verified live (E2E, all scenarios pass). *The collision itself is native-platform behavior (see below); this makes it visible.*

---

## 🔑 Lead issue — orders complete with **no Assets** (the crux)

Order **00095470 activated cleanly** ("Order Complete", contract created) but generated **zero Assets**. We traced why:

- Asset creation runs in a **separate background (async) step** after activation, via the custom flow **`Fortra - Assetize Order`** (which overrides the native Salesforce asset flow).
- That step **failed and the error was silently swallowed** — the flow is built to "end gracefully" on a fault, so the order shows **Activated with no assets and no visible error.** That is exactly the symptom you saw.
- ✅ **This is NOT the SC-3411 problem.** SC-3411 was an *activation blocker* on un-termed lines. Here the order activated, and **all of its subscription lines were fully dated** (End Date + Term Count present). Different failure, different transaction, different fix.

**What we proved vs. what's still open:**
- ✅ The asset engine is healthy — the very next order (2 lines) assetized fine ~13 min later, and other orders assetized that day.
- ✅ We re-ran the asset step against 00095470 safely (rolled back, 3×): it fails **deterministically** with *"the asset was updated by another process"* — a **record-lock collision**, using **1 query** (so **not** a governor/SOQL-limit issue; that theory is ruled out).
- ✅ We rebuilt the symptom on throwaway orders: **duplicate same-product lines alone do NOT cause it** (2- and 12-line duplicate orders both assetized fine). The trigger is specific to 00095470's **maintenance lines** (PIAMBK) that get decomposed — the same area SC-3411 flagged as fragile.
- ❓ The exact maintenance-decomposition mechanism still needs a **full-logging re-test on 00095470 itself** (an owner-authorized re-run). The fix below makes the failure **visible** regardless.

---

## 🔑 Second issue — **Term Count not enterable** on quote lines

- On live draft quote lines, **End Date IS filling in** — the **only** missing field is **Pricing Term Count.**
- That field is **system-controlled (read-only)** — only the pricing engine can populate it, and **no flow can fill it in manually.**
- It **stopped deriving for newly-priced lines on June 11** during the pricing-procedure V12→V13 changeover — a pricing-engine regression, not a data entry gap. The null then carries to the order on convert.

---

## ▶️ What we recommend (UAT-first, prod-gated)

1. **Fix the async asset step** (`Fortra - Assetize Order`) — make it **surface the error** instead of swallowing it, then re-test a 30+ line order with full logging to confirm assets generate 1:1.
2. **Recover 00095470's assets** via an asset re-trigger once the step is fixed.
3. **Restore Term Count derivation at the Quote** by resyncing the pricing procedure/context that regressed in V13 (coordinate with the V13 owner).

---

## 🧭 How this sits next to SC-3411

- **SC-3411 (resolved):** order *couldn't activate* — patched at the **order** tier. Its own notes flagged the "quote-side true root" as out of scope.
- **SC-3415 (this ticket):** owns (a) the **no-Assets-after-activation** failure and (b) the **quote-side Term Count** regression. **Not a duplicate, not a subset.**

🚫 Nothing deployed; org left untouched. Full engineering RCA + evidence in the README.
