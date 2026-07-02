# SC-3374 — Final Fix Plan (holistic review + plan)

> FortraUAT · 2026-06-09 · read-only investigation complete · **no writes performed** · every write below is gated on fresh ack (D6).

## 1. Executive summary

SC-3374 (order **00095398** fails Workday: *"Contract Amount ≠ Contract Line Amount"*) is the visible symptom of a **same-day regression in the live v9 pricing procedure**: today's v9 rework (active 13:12:06Z) **broke regional services pricing** so the country multiplier no longer reaches the **net** price. The fix is to **restore regional pricing to set net == list == the regional price**, deployed as a new draft **v10** through the §3 gate, then reprice + resubmit 00095398.

**The correct price is not a judgment call:** the identical SKU `GS-GSE-NRST-EAQS` billed **net 1540** in April (order 00007889); today it bills **2400**. 1540 is *documented prior behavior*; 2400 is the regression overcharge.

## 2. Holistic data review

### 2.1 Root cause (proven)
- The active v9 (`Rev_Mgmt_Default_Pricing_Procedure`, version 9, LastModified 2026-06-09T13:12:06Z) introduced **brand-new** regional/derived machinery — `RegionalServicesPrice27`, `Source_List_Price` handling, `DerivedPricingNetUnitPriceValueReset` are all **absent from v7/v8, present only in v9**.
- Net is initialized by the native `PricingSettings` element from the pricebook/list (2400). The new `RegionalServicesPrice27` (under `ListContainer4`, seq 11, gated `AllowRegionalPricing__c=true`) assigns `RegionalNetUnitPrice__c → InputUnitPrice` — the **list** channel only. **Nothing propagates the regional value to `NetUnitPrice`.**
- Net result: regional pricing no longer reduces net. Prior to today it did (April proof).
- This is the **3rd regression from the same 13:12 rework** (with SC-3371 context-drop and SC-3372 derived-config gap). Shared anti-pattern: *a v9 change touched one side of a relationship and not the other.*

### 2.2 The regression is inconsistent — and that dictates the fix
Live evidence on two of today's orders, same EAQS SKU:

| Order | list / TLA | net | reg | Workday | Why |
|---|---|---|---|---|---|
| **00095398** | **1540** | 2400 | 1540 | **Failure** | regional hit **list only** → `list≠net` → rejected + overcharge |
| **00095415** | 2400 | 2400 | 1540 | **Success** | regional hit **neither** → `list==net` at catalog → passes **but still overcharged** |

**Consequence:** a net-only fix would set 00095415-shape lines to `net 1540 < list 2400` → a **new** Workday failure (inverse shape). **The fix must force BOTH channels to the regional price.**

### 2.3 Scope
- **Workday-blocked right now: only 00095398** (1 order). `Workday_ID__c` null → resubmittable.
- **Pricing-regressed lines today:** 5 lines / 3 orders — 00095398 (Failure), 00095406 (Draft/Pending, 11300), 00095415 (**already synced Success at 11300 — overcharged**, has `Workday_ID__c`).
- **Systemic exposure:** regional pricing is a **global** feature — `Services_Regional_Pricing__mdt` has **~120 active countries** (Europe 0.64–0.96, LATAM 0.5, APAC 0.4–0.8, MEA 0.8; Italy 0.64). Every future non-US/Canada **services** order will be mispriced (and the partial-apply ones will fail Workday) until v9 is fixed. This is not an Italy edge case.
- **Pre-regression lines (Feb–Apr):** 15/22 non-null-regional lines already show `net==reg` — regional pricing worked before today.

### 2.4 D4 resolved by evidence
Italy (and every regional country) should be billed the **regional** price (1540 for this SKU), per documented prior behavior. The MuleSoft `extendedAmount←NetTotalPrice` change is therefore **wrong for this ticket** — it would sync 00095398 at the regressed **2400** (lock in the overcharge). (It remains the correct, separate fix for the genuinely-discounted scXXXX backlog.)

### 2.5 Secondary issues found (separate follow-ups, not blockers)
- **Prehook overshoot:** `RegionalServicesPricingPrehook` `CEILING(List×mult/5)×5` can exceed list (e.g. `RPA-AUD-RSS-AUPS` reg 2435/2440 > list 2400). 4 lines. The fix's only-lower guard skips these; root-cause the prehook separately.
- **166/188 flagged OrderItems have NULL regional price** (flag set, prehook never stamped a value) — data-quality; the IsNotNull/`>0` guard makes them inert.
- **00095415 is overcharged and already synced** (11300 vs ~8000 correct) — correcting it needs a Workday contract amendment → business decision, out of scope here.

## 3. The fix — corrected v10

A **new gated `ListGroup` container placed LATE** (top-level `sequenceNumber 33`, after every price/net writer at seq 1–28 and the net-total writers 21–25, before the header roll-ups; renumber existing 33→34..42). Built as a **new draft version 10** (whole-file deploy, v9 untouched, atomic activate per the `Data/sc3345` mechanic). No new context fields — every variable already exists.

**Per-line gate (only-lower):** `AllowRegionalPricing__c = true` AND `RegionalNetUnitPrice__c > 0` AND `RegionalNetUnitPrice__c < NetUnitPrice`.

**Actions (force BOTH channels to regional):**
1. `NetUnitPrice = RegionalNetUnitPrice__c`
2. list channel `= RegionalNetUnitPrice__c` (so `UnitPrice`/`TotalLineAmount` match — exact mechanism, set `InputUnitPrice` + recompute vs. set `TotalLineAmount` directly, **confirmed at trace time**)
3. recompute `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity` (mirror `QuantityPrice57`)
4. ensure the list total recomputes to `regional × qty`

**Why this is correct and safe:**
- Restores pre-regression behavior (net = regional); fixes the overcharge **and** the Workday failure in one change.
- `only-lower` gate ⇒ never raises a price, never discards a deeper discount (the 2 discounted lines: `net 115.5 < reg 165` → untouched), auto-skips the 4 `reg>list` overshoot lines.
- Both-channels ⇒ `net == list == regional` for every flagged line ⇒ no inverse Workday failure on 00095415-shape orders.
- Late placement ⇒ order-independent; survives whatever earlier (buggy) steps did.
- Blast radius bounded: 188/229,823 lines (0.08%) carry the flag; non-regional lines never enter the container.

**Rejected alternatives:** net-only (creates inverse `net<list` failures); broad unconditional (discards discounts on 2 lines); MuleSoft remap (locks in the overcharge); reprice-only (current v9 is the broken one — won't self-heal).

## 4. Deploy runbook (§3-gated; each write needs fresh ack — D6)

0. **Heads-up to Marc** — v9 is his in-flight area; confirm no v11 is queued that would clobber v10 (and ideally fold this into his rework).
1. **Build draft v10** locally under `Data/sc3374/v10_deploy/` (copy v9 block → versionNumber 10, status Inactive, insert the container, renumber tail). No org write.
2. **Validate-only deploy** (check-only) — confirm parse/compile, v9 still Active, v10 Inactive.
3. **Deploy v10 as Inactive draft** — adds the version, no live pricing change.
4. **🚦 FINEST reprice trace on 00095398 (GATE — activation NOT trusted until this passes):** confirm the seq-33 container fires, `NetUnitPrice→1540` and is not re-overwritten, `ItemNetTotalPrice→1540`, list channel `→1540`, and discount/subscription steps no-op for this line. Also trace one subscription-regional and one discounted-regional line.
5. **Atomic activate:** single deploy flipping v10→Active **and** v9→Inactive.
6. **Re-verify + re-sync `OrderEntitiesMapping`** on context `SalesTransactionContextExt_v2` (SC-3371 protection — the active-procedure swap must not re-drop the Order-side tags).
7. **Reprice + validate:** reprice 00095398 → assert `net == list == 1540`, total 2400→1540; assert a non-regional control order is byte-identical.
8. **Resubmit:** publish `Order_Completed_WD__e` `Order_Id__c=801WC00000kQn0zYAC` → confirm Workday **Success**.
9. **Sweep:** reprice 00095406 (Draft) before it completes. **Leave 00095415** (already synced; needs a Workday amendment decision).
- **Rollback:** single atomic deploy v9→Active / v10→Inactive + context re-sync. v9 is byte-unchanged → exact rollback. No DML to undo.

## 5. Acceptance criteria
- [ ] 00095398 reprices to `net == list == 1540`, resubmits Workday **Success**.
- [ ] A fresh regional services order (any flagged country) prices `net == list == regional`, syncs clean.
- [ ] Non-regional, discounted-below-regional, and `reg>list` lines are **unchanged**.
- [ ] §3: `OrderEntitiesMapping` re-verified post-activate (SC-3371 not re-broken).
- [ ] Rollback rehearsed/understood.

## 6. Open items / risks
- **Runtime gate:** RLM execution order + the list-channel recompute mechanism are static-inferred — the step-4 FINEST trace must confirm before activation.
- **List-channel write:** exact mechanism to force `TotalLineAmount=regional` (set `InputUnitPrice` late vs. direct `TotalLineAmount` assignment) to be finalized against the trace.
- **Coordination:** v9 is Marc's live in-flight area (collision risk).
- **Follow-ups (separate tickets):** prehook overshoot; null-regional data quality; 00095415 overcharge/Workday amendment; MuleSoft `extendedAmount` for the discount backlog.

## 7. Authorization checkpoints
1. Build + validate + deploy **inactive draft** + run the **reprice trace** (write: the reprice). 
2. **Atomic activate** + context re-sync (the live cutover).
3. Reprice/resubmit 00095398 (+ 00095406).

Each is a separate explicit go.
