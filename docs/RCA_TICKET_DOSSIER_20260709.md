# RCA Ticket Dossier — FortraUAT · as of 2026-07-09

> Per-ticket reference for the 6 assigned Critical tickets, from live testing on the active V21 pricing
> procedure (`Rev_Mgmt_Default_Pricing_Procedure`). Companion to the full report (Artifact `c91bca96`) and
> the test prompt (`docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`, §T). Engine state: **idempotent 19/19,
> pricing stable day-over-day, 0 exception-log rows.**

| Ticket | Title | Status | One-line |
|---|---|---|---|
| SC-3501 | Amendment pricing does not recalculate | 🟠 **PARTIAL** | Lines now price; totals still stale on qty change |
| SC-3346 | Derived maintenance — **renewal branch** | 🔴 **OPEN** | Renewal maint prices $0 even with inputs stamped |
| SC-3384 | Non-USD quote lines priced from USD | 🔴 **OPEN** | EUR lines priced off USD base × FX |
| SC-3544 | Sales Price blank/$0 on renewal & amendment | 🟢 **RESOLVED** (fixed live 07-09) | `UnitPrice` now = Net on renewal |
| SC-3350 | Renewal COLA priced at list | 🟢 **NOT REPRODUCED** | COLA applied; descriptions present |
| SC-3502 | Renewal process fails to generate Opportunity | 🟢 **NOT REPRODUCED** | Renewal Opp exists on the bound contract |

---

# 🔴 OPEN — needs a fix

## SC-3501 — Amendment pricing does not recalculate — 🟠 PARTIALLY FIXED (2026-07-09)
- **Status:** 🟠 OPEN (partial) · the **$0 defect is resolved**; a **qty→total recalc residual remains**.
- **Binding:** `0Q0WC000003J4m9` (amendment, Draft) · `0Q0WC000003F55h` (now also prices — $2021.25)
- **Symptom (original):** on an amendment, updating a line **Quantity** left the line price at **$0**; totals didn't recompute.
- **Live evidence (07-09 run 3):**
  - **Fixed:** J4m9 lines now **price** — `NetUnitPrice` 10000 / 94000 / 15000 (were all **$0**).
  - **Residual:** bumped a line `Quantity 2 → 4`, repriced ×2 → `NetUnitPrice` stayed 10000 (correct) but **`NetTotalPrice` / `TotalPrice` stayed 20000** (should be **40000**) — the total is frozen at the pre-change quantity. Qty reverted to 2. D-18 clean.
- **Root cause:** the "left-behind" pricing logic (Marc) was restored → lines price again; but the **quantity → total recalculation** on an amendment line is still not firing.
- **Acceptance gap:** on a qty change, both `NetUnitPrice` **and** `NetTotalPrice`/`TotalPrice` must be quantity-correct, and quote + Opportunity totals must update.
- **Recommended next step:** fix the amendment total recalc so `NetTotalPrice = NetUnitPrice × Quantity` after a qty edit; re-test with the qty 2→4 repro (expect Total 40000).

## SC-3346 — Derived maintenance pricing · **RENEWAL branch** (new-business is validated)
- **Status:** 🔴 OPEN · renewal branch FAIL confirmed live 2026-07-09 · new-business PASS
- **Binding:** `0Q0WC0000035Xkn` ("Test Derived Pricing", Renewal)
- **Symptom:** Renewal maintenance lines price to **$0**.
- **Live evidence:**
  - New-business path **works**: BoKS-NewMaintenance = **$71.00** (`355 × 0.20`) ✓.
  - Renewal path **broken**: on `0035Xkn`, **Device Profiler & Tripwire maintenance = $0**; BoKS $71 / VnE $7,992.50 come from the native pull only.
  - Across 8+ renewal-maint quotes, renewal maintenance `NetUnitPrice` = **blank/$0 even when `Prior_Partner_Discount__c` / `Prior_Discretionary_Discount__c` / `COLA_Uplift_Percent__c` (7.85%) ARE stamped** (e.g. DOpB 600/246, DLBO 10.65/4.37). `Base_Price__c` is blank on all.
  - `MaintenanceType__c` — the tier field the build spec references — **does not exist on QuoteLineItem**.
  - reprice ×2 = 0 delta (stable, not flapping). D-18 clean.
- **Root cause:** the 3-component renewal formula `(PriorBase − PriorPartner − PriorDiscretionary) × (1+COLA)` in List Container 9 **never emits `NetUnitPrice`** — the **base component isn't landing** (null in → null out). The Flow stamps the discount + COLA inputs but the base isn't reaching the gated renewal formula.
- **Acceptance gap:** renewal maint must equal the worked example — **$144.20 (Yr2) / $148.53 (Yr3)** from prior Base $200 / Partner $20 / Discretionary $40 @ 3% COLA — and override the native pull; **no maintenance line with a valid base at $0**.
- **Recommended next step:** trace where `PriorBase` should reach the renewal formula (Flow renewal-stamp Step 6 → formula Step 7); confirm the tier field name (`MaintenanceType__c` missing). **Validate against a genuine platform renewal** descended from a real prior order (depends on SC-3502 generation). Ref: `FORTRA-Maintenance-Derived-Pricing` design.

## SC-3384 — Non-USD quote lines priced from USD values
- **Status:** 🔴 OPEN · FAIL confirmed live 2026-07-09
- **Binding:** `0Q0WC0000036xy9` ("Q-Wren Test Currencies", EUR, 6 lines)
- **Symptom:** EUR quotes display the **EUR** symbol but compute Net/Total/Subtotal from **USD** values.
- **Live evidence:** `ListPrice` is EUR, but `Base_Price__c` holds **USD** (824 / 500 / 8165 / 857.75 / 492.07), and net = USD × 0.9346 (not the EUR price-book entry): beSECURE-Cloud **8165 → 7631.009**, Click&Launch **492 → 459.89**, AAM **857 → 801.66**. Attribute Tier Pricing Storage records are **USD-only**. Auto-add maintenance fails with *"The price book entry currency code is different than the one assigned to the Quote."* **New (07-09):** after the SC-3544 fix, `UnitPrice` now also **displays the USD Base** on this EUR quote — the USD leak is now visible in the Sales Price column too. reprice ×2 = 0 delta. D-18 clean.
- **Root cause:** **currency-blind lookups over USD data** — `AttributeVolumePricingPrehook` omits currency from the tier lookup and the attribute/tier pricing storage is USD-only. The org *has* per-currency PBEs, but the configured-pricing path ignores them and prices USD then applies a hardcoded FX.
- **Acceptance gap:** non-USD lines use pricing records **matching the quote currency**; EUR Net/Total/Subtotal from **EUR** pricing; tier / attribute / server-type / attribute-tier all respect currency; auto-add maintenance uses a **same-currency** PBE; quote saves with **no currency-mismatch error**.
- **Recommended next step:** add `CurrencyIsoCode` to the attribute/tier pricing lookups (currency-aware selection); backfill EUR attribute-tier storage; resolve the auto-add-maintenance PBE currency mismatch. (Larger SC-3384 multi-currency cluster — architectural.)

---

# 🟢 RESOLVED / NOT REPRODUCED (for the record)

## SC-3544 — Sales Price (`UnitPrice`) blank/$0 on renewal & amendment — ✅ FIXED LIVE (2026-07-09)
- **Status:** 🟢 RESOLVED — the fix landed **between** the §T run and the re-run on 07-09.
- **Binding:** renewal `0Q0WC000003Ifvp` · new-biz control `0Q0WC000003Ih3B`
- **Before → After:** renewal `Ifvp` `UnitPrice` was **BLANK** (Net 4573.80 / 918.75); now `UnitPrice` = **4573.80 / 918.75 = Net** ✓. The same fix populated `UnitPrice` on S4/S9/S12/S14 $0 lines, Ibx3, xy9 — a systemic `Stamp_Sales_Price` change, with net/pricing unchanged (0 delta ignoring `UnitPrice`).
- **Caveat:** symptom verified in the data; the flow metadata / exact shipped change was **not** inspected. **Watch:** on the EUR quote (SC-3384) it now surfaces the USD Base in the Sales Price column.

## SC-3350 — Renewal (COLA) quotes priced at list — 🟢 NOT REPRODUCED (caveat)
- **Status:** 🟢 PASS — both reported symptoms are gone.
- **Binding:** renewal `0Q0WC000003Ibx3`
- **Evidence:** COLA **is applied** — Active Defense `94000 × 1.05 = 98700`, beSTORM `60000 × 1.062 = 63720`, `COLA_Source = CMDT Lookup`; **Line Item Descriptions present**. (Not bare list; not blank description.)
- **Caveat:** one line (Additional Threat Assessments) prices **$0**, and the COLA **base = list / CMDT default** — confirming a *prior-discounted-net* base needs a genuine platform renewal descended from a real prior order (ties to SC-3502).

## SC-3502 — Renewal process fails to generate Opportunity — 🟢 NOT REPRODUCED (observational)
- **Status:** 🟢 PASS — the "no opp / hangs" symptom does not reproduce.
- **Binding:** activated contract `800WC00000TNpyn` (00069451)
- **Evidence:** the contract **has** a renewal Opportunity `006WC00000RtJ0r` (Amount 316.93, `Renewed_Contract__c` set) plus a Draft renewal quote `0Q0WC000003JAjV`. AssetAction lifecycle spans Initial Sale / Renewals / Upsells / Cancellations.
- **Caveat:** validated against **existing** generation, not by firing a fresh async trigger — so an intermittent hang can't be fully ruled out. A clean SC-3502 generation is the **precondition** for faithfully validating SC-3346-renewal and SC-3350.

---

## Cross-cutting (as of 2026-07-09, run 3)
- **Engine:** NET idempotent **19/19** (reprice ×2 = 0 delta on net/COLA/subtotal); day-over-day stable.
- **D-18 exception log:** **0 rows** — no pricing hook silently swallowed an error across the whole run.
- **⚠️ New watch item — S6 Guaranteed-Margin Sales Price (side-effect of the SC-3544 fix):** `UnitPrice` became non-idempotent on the GM quote `0Q0WC0000035dGj` — reprice1 kept the stale 593.28, reprice2 moved it to **824** (=list). It **converged** (stable 824/593.28 across 3 further reprices) and the **net (593.28) is always correct**, so display-only + self-healing. Watch that Sales Price settles on the **first** click for GM lines (SC-3390 family).
- **Dependency chain:** SC-3502 (renewal generation) → real prior order → is the precondition for faithful SC-3346-renewal and SC-3350 "prior-net base" validation.

*Sources: report Artifact `c91bca96`; snapshots `Data/pricing-refactor-scratch/rca_fulltest_20260708/run0709/`; test prompt §T. Live-verified on FortraUAT — re-verify record statuses (they drift) before acting.*
