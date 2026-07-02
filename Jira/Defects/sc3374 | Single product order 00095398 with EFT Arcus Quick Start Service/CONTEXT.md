# SC-3374 — Full Context & Work Log

> **Single product order 00095398 (EFT Arcus Quick Start Service, "no discount") failed to generate Workday contract.**
> Critical · Reporter Joe Romo · Assignee Liam Jeong · FortraUAT (UAT-only) · CRM Sprint 14
> **Status: core defect RESOLVED — v10 pricing fix deployed + ACTIVE + validated end-to-end (Workday Success).** One follow-up (v10.1 category aggregates) open.
> Companion docs in this folder: `README.md` (original RCA) · `FINAL_PLAN.md` (the fix plan).

---

## 1. TL;DR

00095398 failed Workday with *"Contract Amount and the Contract Line Amount must be equal"*. Root cause = a **same-day regression** in the live v9 pricing procedure: the 2026-06-09 13:12Z rework re-implemented **regional services pricing** so the country multiplier reached only the **list** channel, not **net** — so the line had `list 1540 ≠ net 2400`, which Workday rejects. The correct price (regional **1540**) was *documented prior behavior* (same SKU billed 1540 in April). Fixed Salesforce-side with pricing-procedure **v10** (`RegionalNetReconcile` step) that forces `net == list == regional`. **00095398 now syncs to Workday Success at 1540.**

---

## 2. The order / key records

| Thing | Id / value |
|---|---|
| Order | **00095398** = `801WC00000kQn0zYAC` |
| OrderItem | `802WC00000OZKPRYA5` — EFT Arcus Quick Start Service (`GS-GSE-NRST-EAQS`, One Time) |
| Source Quote | `0Q0WC0000036wUD0AY` ("Q-Automation Test-2026-06-09", Joe Romo) |
| Account | **PAGANI SPA** `001WC00000gVLfxYAG` — BillingCountry **Italy** |
| Pricebook | Fortra Price Book `01sWC0000022GHFYA2` |
| Pricing procedure | `Rev_Mgmt_Default_Pricing_Procedure` (ESD `9QAWC0000003mg14AA`) |
| Context | `SalesTransactionContextExt_v2` (`11OWC000002m21Z2AQ`), mapping `OrderEntitiesMapping` |
| Regional prehook | `RegionalServicesPricingPrehook` v12.2 |
| Regional config | `Services_Regional_Pricing__mdt` (~120 countries; **Italy = 0.64**) |

**Original failing state (OrderItem):** `ListPrice 2400 · UnitPrice/TotalLineAmount 1540 · NetUnitPrice/NetTotalPrice 2400 · TotalAdjustmentAmount +860 · RegionalNetUnitPrice__c 1540 · AllowRegionalPricing__c true`. Header `TotalAmount 2400`, `Workday_Sync_Status__c Failure`, `Workday_ID__c` null.

---

## 3. Root cause (proven)

**It's a same-day regression, not the originally-suspected MuleSoft mapping.**

- The active **v9** of the pricing procedure was reworked/re-activated **2026-06-09T13:12:06Z**. That rework introduced **new** elements — `RegionalServicesPrice27`, `Source_List_Price` handling, `DerivedPricingNetUnitPriceValueReset` — all **absent from v7/v8, present only in v9** (grep across version blocks confirmed).
- `RegionalServicesPrice27` (under `ListContainer4`, seq 11, gated `AllowRegionalPricing__c=true`) assigns `RegionalNetUnitPrice__c → InputUnitPrice` — the **list** channel only. Nothing propagates the regional value to `NetUnitPrice`, which stays at catalog (from the native `PricingSettings` element).
- The regional value `1540 = CEILING(2400 × 0.64 / 5) × 5` (Italy multiplier 0.64), computed by the prehook.
- **Proof of regression:** the identical SKU `GS-GSE-NRST-EAQS` billed **net 1540** on 2026-04-24 (order 00007889); today it billed **2400**. So 1540 is documented prior behavior; 2400 is the regression overcharge → **D4 resolved by evidence: Italy should pay 1540.**
- The regression is **inconsistent**: 00095398 got regional on the **list** channel only (list 1540 / net 2400 → list≠net → Workday FAIL); 00095415 got it on **neither** (list=net=2400 → passes but overcharged). ⇒ the fix must force **both** channels to the regional value.

**Cluster:** this is the **3rd regression from the same 13:12 v9 rework**, alongside **SC-3371** (convert gack: Order context lost `Prior_*` mappings) and **SC-3372** (contributing-products: derived-pricing config gap). Shared anti-pattern: *a v9 change touched one side of a relationship and not the other.*

**MuleSoft note:** the separate `extendedAmount ← TotalLineAmount` mapping defect (scXXXX / SC-3347) is real but is **not** the cause here — and would have *locked in* the 2400 overcharge if used to "fix" this order. It remains the right fix for the genuinely-discounted backlog, tracked separately.

---

## 4. The fix — pricing procedure v10

Built as a new **draft version 10** of `Rev_Mgmt_Default_Pricing_Procedure` (whole-file deploy; v9 preserved byte-identical for rollback; §3-gated). Adds one top-level `ListGroup` container **`RegionalNetReconcile` at sequenceNumber 33** (after all per-line writers seq 1–29 and net-total writers 21–25; existing seq 33–41 renumbered → 34–42; the `MAX(net,list)` step at new seq 35 becomes a no-op).

Per-line gate: `AllowRegionalPricing__c = true AND RegionalNetUnitPrice__c > 0`. Five child steps (FormulaBasedPricing):
1. clamp `NetUnitPrice = IF(RegionalNetUnitPrice__c < NetUnitPrice, RegionalNetUnitPrice__c, NetUnitPrice)` — **only-lower** (never raises).
2. `InputUnitPrice = NetUnitPrice` (clamped).
3. `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity`.
4. `TotalLineAmount = NetUnitPrice × LineItemQuantity`.

Net effect: for flagged lines, **`net == list == clamped-regional`** and totals consistent ⇒ Workday `Contract Amount == Contract Line Amount`. Non-regional lines (flag false) and lines with null/zero regional are untouched. Blast radius: 188 / 229,823 OrderItems carry the flag (0.08%).

**Build artifacts (in repo):** `Data/sc3374/v10_deploy/` (deployable metadata) · `Data/sc3374/build_v10.py` (deterministic constructor) · `Data/sc3374/v10_container.xml` (the inserted steps) · `Data/sc3374/v10_build_workflow.js` + `v10_design_workflow.js` (design workflows) · `Data/sc3371/v9_live/...` (the v9 snapshot analyzed).

---

## 5. Deployment & activation

- **2026-06-10 ~02:18Z** — v10 deployed as **Inactive** draft (metadata deploy succeeded; the "MetadataTransferError: …Finalizing" was the known cosmetic CLI bug on success; verified via deploy report + re-retrieve). v9 stayed Active.
- **~04:00Z** — user **activated v10** in the UI (v9 → Inactive). v10 is now the **active** pricing procedure.
- **Rollback** (instant, no data change): activate v9 in the Pricing Procedures UI (v9 bytes unchanged → exact prior behavior).
- ⚠️ **Context re-sync** (`SalesTransactionContextExt_v2`) should be re-verified after any activation (SC-3371 protection) — v10 adds no new field, and the user's reprices worked, so the context is functional.

---

## 6. Validation (smoke test)

All via the user's **UI "Reprice All"** (the only working reprice path — see §7).

| Record | Before | After v10 | Verdict |
|---|---|---|---|
| **00095398** EAQS | list 1540 / net 2400 | net==list==**1540**, total 1540, **Workday Sync = Success** | ✅ end-to-end fixed |
| 00095406 EAQS | list=net 2400 | **1540** / **1540** | ✅ fixed (00095415-shape) |
| 00095406 HRSCTM ×10 | net 275 / 2750 | **180 / 1800** | ✅ fixed |
| 00095406 ARCUS (non-reg) | 3000 | 3000 | ✅ control unchanged |
| 00095406 AAMP (non-reg) | 3150 | 3150 | ✅ control unchanged |
| 00095406 header `TotalAmount` | 11300 | **9490** | ✅ correct (Workday header right) |

**Core SC-3374 defect is resolved** — 00095398 now produces a balanced contract and syncs to Workday Success at the correct regional price.

---

## 7. Issues found during testing (open)

1. **Stale category aggregates (→ v10.1, recommended).** The per-category header fields `Total_Services__c` / `Total_Software__c` / `Total_Subscription__c` compute at seq 30–32, **before** the seq-33 fix, so they're stale for fixed orders (00095406 `Total_Services__c` = **5150**, should be 3340). The overall `TotalAmount` is recomputed at seq 34 (after the fix) and is **correct**, so **Workday is unaffected**. Fix = move the 3 category-aggregate steps to after seq 33 (a small v10.1, same draft→activate process).
2. **Programmatic reprice is broken in this org** (not a v10 issue). The `runSalesforceHeadlessPricing` invocable errors `INTERNAL_ERROR: No value present` (same as SC-3372); the `Fortra_Order_Reprice` / `Fortra_Migration_Price_Quote` flows run "OK" but are **silent no-ops** (LastModifiedDate unmoved). **Only UI "Reprice All" actually applies pricing.** ⇒ validation must be UI-reprice + read-only SOQL; no mass-automated reprice.
3. **Edge cases not yet empirically confirmed** (couldn't programmatically reprice): the discounted-line list-collapse (net<reg → list collapses to net, e.g. 00000236 list 165→160) and qty interactions on more SKUs. Predicted-correct by design; confirm on a UI reprice if desired.

---

## 8. Remaining work / recommendations

- [ ] **Decide:** ship the core fix as-is (it works, Workday Success) vs. also ship **v10.1** for the category aggregates. (Recommend v10.1 — small, removes the only known correctness gap.)
- [ ] **v10.1:** relocate `ServicesAggregatePrice` / `SoftwareAggregatePrice` / `SubscriptionAggregatePrice` (seq 30–32) to after seq 33; redeploy draft → activate → re-verify.
- [ ] **Backfill sweep (systemic):** regional pricing is global (~120 countries) — every non-US **services** order priced under the regressed v9 is mispriced. v10 corrects on reprice. Decide which existing orders to UI-reprice. **Do NOT** reprice already-Workday-synced orders without a plan (changes price below the synced contract → desync).
- [ ] **00095415:** already synced to Workday Success at the **catalog** (overcharged) price → correcting it needs a **Workday contract amendment** (separate decision).
- [ ] **Coordinate with Marc DeBrey** — v10 sits on top of his in-flight v9 rework; ensure no v11 clobbers it.
- [ ] Optional: confirm `OrderItem.UnitPrice` (standard field) follows `InputUnitPrice` for fixed lines (v10 writes `InputUnitPrice`, not the std `UnitPrice`; RLM normally derives it).

---

## 9. Draft Jira comment

> See the ready-to-paste version in §10 below (also pasted into the ticket).

---

## 10. Jira comment (paste-ready)

**Root cause — resolved (Salesforce-side).** SC-3374 was a *same-day regression* in the active v9 pricing procedure (reworked 2026-06-09 13:12Z). That rework re-implemented **regional services pricing** so the country multiplier reached only the **list** channel (`RegionalServicesPrice27`: `RegionalNetUnitPrice__c → InputUnitPrice`), not **net** — so the line had `list 1540 ≠ net 2400`, which Workday rejects ("Contract Amount ≠ Contract Line Amount"). The correct price (Italy regional **1540**) is documented prior behavior — the same SKU billed 1540 in April, 2400 today. This is the 3rd regression from that v9 rework (with SC-3371 and SC-3372). *(The MuleSoft `extendedAmount` mapping is a separate, pre-existing issue and is NOT the cause here — using it would have locked in the 2400 overcharge.)*

**Fix — deployed & active.** New pricing-procedure **v10** adds a late, gated `RegionalNetReconcile` step (seq 33; gate `AllowRegionalPricing=true AND RegionalNetUnitPrice>0`) that clamps `NetUnitPrice = MIN(regional, net)` and forces both channels + line totals to that value → `net == list == regional`, never raising a price. Built as a draft version and activated (v9 retained for one-click rollback).

**Validated end-to-end.** 00095398 reprices to net==list==**1540** and **syncs to Workday Success** (TotalAmount 1540). 00095406: both regional lines fixed (EAQS 2400→1540, HRSCTM 275→180), non-regional lines unchanged, header total correct (9490).

**Follow-ups (not blockers):**
- **v10.1 (recommended):** per-category header totals (`Total_Services__c` etc.) compute before the seq-33 fix → stale for regional orders. Workday header `TotalAmount` is correct, so sync is unaffected. Fix = move the 3 category-aggregate steps after seq 33.
- Regional pricing is global (~120 countries) — every non-US services order was mispriced under the regressed v9; v10 corrects on reprice.
- 00095415 already synced at the catalog (overcharged) price → needs a Workday amendment to correct.
- Note: programmatic reprice is broken in this org (headless API errors; `Fortra_Order_Reprice` no-ops) — only UI "Reprice All" applies pricing.
