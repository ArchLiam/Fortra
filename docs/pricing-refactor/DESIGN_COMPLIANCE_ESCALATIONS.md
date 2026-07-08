# Design-Compliance Escalations — RCA Pricing (Round 3)

**Date:** 2026-07-08 · **Owner:** Tab 1 (coordinator) · **Audience:** Marc DeBrey (design authority) + Nir (co-owned Partner V2) + the ExpressionSet/procedure owner.

**Context.** The behavior-preserving refactor (Waves 1–2) is complete and SDD-validated (0-delta;
reflection found nothing to revert). Round 3 fixes the ~24 **pre-existing** code-vs-SDD gaps the SDD
reflection surfaced. On close reading against the KB (`docs/RCA Solution Guide/kb/`), most gaps resolve
to **"the SDD blesses the current behavior"** or **"needs a ruling / config change outside Apex."**
Only a small set are clean code fixes (in flight on Tabs 2/3: Hardware label + user-band, Regional
null-guard). This doc is everything that needs a **human decision** before code changes — nothing here
was blind-fixed.

---

## A. Rulings needed (bucket-C — Marc decides which is authoritative: SDD or code)

### A-1. COLA — MyCAP precedence: is it a year-1 TIER or an OUT-YEAR concept?
- **SDD conflict (internal):** §6 lists a **4-tier** `Line > MyCAP Default > Contract > CMDT`; §7.1/§10.1 describe **3-tier** `Line > Contract > CMDT`.
- **Verified code reality (high confidence, adversarially confirmed):** live code implements **3-tier** year-1 selection (`COLAUpliftCalculator.resolveTier`, MyCAP hardcoded `null` at `:71`); "MyCAP Default" is only a **source LABEL** applied to multi-year lines that already resolved to CMDT Lookup (relabel gated on `colaSource=='CMDT Lookup'`, prehook `:399`) — so **Contract outranks MyCAP in year-1**, the opposite of §6. The year-1 3% payload §6 calls for is **built but never submitted** — `COLAUpliftPrehook :1074-1084` writes to `allContextUpdates`, which is dead code (submit only at `:277/:289/:587`). The 3% floor is realized only in out-years (`COLA_Outyear_Uplift_Percent__c` + `Final_Year_COLA_Calculated_Price__c` + the `Quote.Mycap__c` Deal-Desk flag).
- **Recommendation — AFFIRM the code, but present as a GENUINE conflict (not pre-settled):** MyCAP is a 3% **minimum/floor** (`Minimum_Out_Year_Uplift_Percent__c`, "flag if below") — a floor should RAISE sub-3% out-year uplifts, never REPLACE a year-1 rate; SDD Ex4 (9.85%→3% in year-1) is a *reduction* that contradicts the floor semantic in the same doc; the CMDT fields are literally named `Out_Year`; RN-MULTIYEAR (closed 2026-06-14, owner-accepted) already ruled year-1 MyCAP out of scope. **But** the dead year-1 payload shows *someone* once intended year-1 MyCAP — so this warrants a real ruling, not a doc-only edit.
- **Impact if ruled the other way:** MyCAP must outrank Contract in year-1 (`resolveTier` + prehook), forcing a negotiated 3.5% contract rate (or 9.85% CMDT) DOWN to 3% in year-1 — materially wrong pricing; gated on S3.
- **Tab-1 SOQL to confirm the "0 of 7" claim (I have read auth):** `SELECT COLA_Source__c, COLA_Uplift_Percent__c, Default_COLA_Uplift_Percent__c FROM QuoteLineItem WHERE COLA_Source__c='MyCAP Default'` — re-verify none carry the MyCAP rate in year-1.
- **Hygiene:** the dead `allContextUpdates` year-1 MyCAP payload (`:1074-1084`) is removable dead code (low priority; COLA prehook = handle carefully).

### A-2. Partner V2 — E-04 Non_Orig fallback (⚠️ this lives in Nir's UNCOMMITTED working tree)
- **Verified behavior (high confidence):** the uncommitted `effectivePct` helper (`PartnerPricingServiceV2.cls:164-170`) makes a **blank** `Non_Orig_*_Pct__c` on a Fortra-Originated deal return the **standard/non-originating band** (e.g. `Software_Percent__c`); returns 0 only if BOTH are null — replacing HEAD's blank⇒0. Only the Fortra-Originated branch changes; the else branch (`effectivePct(x, null)`) is byte-equivalent to HEAD.
- **Provenance:** uncommitted (0 in HEAD, 11 in working tree; `git status ' M'`, blame "Not Committed Yet" 2026-07-08), co-owned `PartnerPricingServiceV2.cls`, **not** the committed refactor (sole file commit `a1fc2b3`). Authorship=Nir per ESCALATIONS A-2 + co-ownership; not independently git-provable for an uncommitted edit.
- **SDD status:** the Partner SDD is **silent** on the blank-Non_Orig case; Open-Issues RULE 2 only fixes *which branch* reads Non_Orig, not the blank fallback. So this resolves the still-open owner-gated **OQ-1** (null⇒0% vs null⇒catalog).
- **Key fact for the ruling (semantic RISK):** `Non_Orig_*` is the Fortra-Originated discount schedule (partner sourced less ⇒ typically a **smaller** margin); the standard band is the **larger** partner-originated discount. So "borrow the standard band on blank" can **over-discount** a Fortra-Originated deal.
- **✅ RULED (owner, 2026-07-08): REJECT the fallback — follow the SDD / best practice.** Committed HEAD already
  does the correct thing (`Non_Orig_X != null ? Non_Orig_X : 0` — blank ⇒ 0, no borrowed margin, no over-discount),
  so **no committed-code change is needed**. Nir's uncommitted `effectivePct` standard-band fallback is **not
  adopted** (it over-discounts Fortra-Originated deals). E-04 closes by **data remediation** — populate the
  `Non_Orig_*_Pct__c` bands (the V21-verified fix was 312.40 = Non_Orig 12%). Action: Nir should drop the uncommitted
  edit from his tree; if his fallback is currently deployed to FortraUAT, redeploy HEAD's `PartnerPricingServiceV2`
  to restore blank⇒0 (verify org state first).

### A-3. ARR — `Order_Line_ARR__c` N-fold overcount on Power order-line splits
- **Verified finding (high confidence):** `PowerOrderSplittingService` apportions only `Displaced_ARR__c` +
  `Manual_Discount__c` (÷qty across original+clones); `Order_Line_ARR__c` is copied **whole** to every clone
  (`createFullClone` `:404-421`) and left whole on the original (`:259-266`) → a qty=N Power split yields
  `Σ Order_Line_ARR__c = N×X` and propagates N copies to `Asset.ARR__c` (the SDD's ARR reporting field). By the
  SDD's own logic (Displaced_ARR is divided to "preserve the total"), `Order_Line_ARR__c` — also a whole-line
  writable snapshot — should be too.
- **NOT a code-vs-SDD violation:** the OrderLineSplitting SDD explicitly lists ONLY `Manual_Discount__c` +
  `Displaced_ARR__c` as distributed (BR-002, rules 7/9) and is **silent** on `Order_Line_ARR__c`. The code follows
  the SDD's list; the asymmetry is a latent defect the SDD didn't anticipate.
- **Recommendation (Marc/Nir ruling — recommended YES):** apportion `Order_Line_ARR__c` on splits by parity with
  `Displaced_ARR__c`, to protect `Asset.ARR__c`/finance from an N-fold overstatement. Requires (a) an SDD amendment
  adding the field to the distributed list in BOTH the OrderLineSplitting SDD and the ARR SDD (Rule 10), and (b)
  accepting Apex-stamping this ARR field despite ARR SDD Rule 5 ("ARR declarative-only") — **precedent exists**
  (`Displaced_ARR__c` is already Apex-stamped here). **Scoped fix if greenlit: ~3 lines in
  `PowerOrderSplittingService`, mirroring the `Displaced_ARR` pattern.** NOT autonomously safe (declarative-only rule) → escalate.
- **(Separate, intentional — no change):** renewal `Opportunity.Amount = Σ MRR×12×COLA` (`RenewalForecastAmount`,
  SC-3500) is a forecast by design, not an `Asset.ARR__c` rollup — annotate the ARR SDD.

### A-4. AttrVolume — no-match / null-volume reset-to-list (⚠️ SC-3390 ruled out, but a LOAD-BEARING stale-guard → Marc ruling)
- **Verified finding (high confidence):** live code resets no-match lines (prehook `:283-291`) AND null-volume
  lines (`:271-279`) to list price via `AttributeVolumeCalculator.buildResetNodeUpdate` (`:244-275`:
  `Base_Price__c=ListPrice`, `Attribute_Price_Mode__c='Unit Price'`; or `Base_Price__c=0` when ListPrice is null).
  This **violates** SDD §6.3/Rule 10 ("write NOTHING, skip, do not zero out prices"). The null-ListPrice branch is a latent **$0** defect.
- **SC-3390 ruled OUT (proven twice — Tab-1 workflow + Tab-3):** the reset is NOT from SC-3390 — it predates it
  (SC-3308 org snapshot; the reset arrived in a bulk org-mirror commit); SC-3390's shipped fix was an
  `IsPriceImpacting` PAD flip with **zero Apex change**. The "SC-3390/D-17" comment = discovery origin, not causation.
- **Why it's a RULING, not an autonomous fix (Tab-3's V21 investigation):** the reset is a **deliberate, documented
  stale-guard**, and RCA **re-hydrates persisted `Base_Price__c`** between reprices. So removing it (per Rule 10) or
  clearing it risks **stale tiered prices on a match→no-match transition** (a line that matched a tier, then stops
  matching, keeps its old tier `Base_Price__c`). That regression is **structurally unobservable in headless reprice
  testing** — the exact reason SC-3390's two-click bug couldn't be reproduced headlessly. Shipping a fix gated only
  by the headless harness would be unsafe.
- **Ask (Marc):** confirm the desired no-match behavior AND provide/authorize a **non-headless (UI two-click)**
  validation path. If approved, the fix is Tab-3-owned (remove reset per Rule 10, or explicit-clear), gated on a UI
  match→no-match repro, NOT the headless S11/S2 gate alone. Refactor-plan D-17 is the tracking item.

### A-5. Hardware — per-line product-eligibility gate (Tab-2 escalated, KB §8 Rule 12)
- **Finding (Tab 2):** the SDD (§8 Rule 12) implies a product-eligibility gate, but `HardwareProductEligibilityService`
  exposes **no per-line API**, and adding a gate risks (a) changing pricing on already-hardware-linked lines and
  (b) the SC-3447 governor budget (per-unit OrderItem explosion on high-qty Power).
- **Ask (Marc):** confirm whether a per-line hardware-eligibility gate is required and, if so, its exact predicate;
  Tab 2 did NOT fix (rationale in STATUS_TAB2.md). Tab 2's other two fixes (source-label Rule 5, open-ended user-band
  Rule 3) shipped (`173431a`, 71/71 tests, S12 price-neutral).

### A-6. Regional — Active row with null `Multiplier__c` (Tab-3 escalated, SDD-silent extension of Rule 2)
- **Finding (Tab 3):** KB Rule 2 covers only country-**not-found** → 1.0 default → skip. An **Active** row with a
  **null** `Multiplier__c` is a distinct, SDD-silent edge. Live CMDT read: `Services_Regional_Pricing__mdt` has
  **125 active rows, 0 with a null multiplier** — so the edge is currently **unobservable** on any gate.
- **Ask (Marc):** confirm desired behavior for an active null-multiplier row (recommended: treat as skip, like the
  1.0 default). Per Rule 6.1 this is escalate-not-blind-fix (SDD-silent). Low priority (zero live rows). Tab 3's
  effective-dating fix (Rule 14) shipped instead (`8d1ec19`, 18/18 tests, S9/S10 0-delta).

---

## B. Context / ExpressionSet config items (NOT Apex — for the V21 procedure owner)

### B-1. COLA — audit fields must be `inputoutput` on `SalesTransactionContextExt` (reprice persistence)
- **KB §6.2 / line 253 (verbatim):** "To ensure audit fields persist through repricing, the Context
  Definition's `SalesTransactionContextExt` must have COLA audit fields set to **`inputoutput`**.
  **Output-only attributes get nullified on reprice** unless a pricing-procedure step explicitly outputs them."
- **Fields:** `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `COLA_Applied_Date__c`,
  `COLAApplied__c`, `COLAUpliftPercent__c`.
- **✅ RESOLVED — NO ACTION (empirically confirmed 2026-07-08).** Retrieved `SalesTransactionContextExt_v2`: the
  substantive COLA audit attributes (`Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`,
  `COLA_Applied_Date__c`, `COLAUpliftPercent__c`) **already have `<contextAttrHydrationDetails>` from QuoteLineItem**
  → they persist. **Proof:** after 2 reprices today, S3 (`0Q0WC000003IKkv`) line 2 has ALL audit fields populated,
  with `COLA_Applied_Date__c=2026-07-06` — the ORIGINAL first-applied date, which survived the reprices AND was not
  overwritten. The only output-only COLA attribute, `COLAApplied__c`, has **no backing QuoteLineItem field** (pure
  transient context flag, derivable from `COLA_Source != null`) — so its nulling is by-design, not a gap. The KB's
  generic "nullify on reprice" warning does not manifest here. No UI/context edit needed.

---

## C. Confirmations — SDD blesses the current Apex behavior (NO action; documented for the record)

- **COLA Apex is SDD-compliant.** `COLA_Applied_Date__c` written once at first-application (handler before-insert;
  `handleBeforeUpdate` never re-invokes it; override path uses `COLA_Modified_Date__c`) = KB "when first applied."
  Rounding: KB §4.1/§10 says preserve current. Zero/neg: Rule 4 = 0% is a valid unchanged price. → no change.
- **Maintenance Apex is SDD-compliant.** `NewMaintenanceInputResolver.resolveTierRate` is **CMDT-sourced**
  (Rule 10, admin-editable — not hardcoded) and returns **null** for off-list tiers (consistent with Rule 11's
  by-design $0 fallback). The core derived-pricing mechanism is **declarative** (Flow + procedure Formula element,
  List Container 9 — "no custom Apex prehook") = V21 territory. The Apex overlay prices off the contributor base
  **intentionally** (SC-3346/J-06). → no change; KB Rule 11 says off-list changes are spec decisions, not bug fixes.

---

## D. SDD doc-update notes (KB annotations — low priority, no code)

- **COLA §3.5 field inventory** missing `COLA_Outyear_Uplift_Percent__c` + `Final_Year_COLA_Calculated_Price__c`
  (these carry the actual MyCAP out-year values).
- **Partner §6.2.1 / §2.2** context contract exceeds the documented "18 attributes" — add `Deal_Type__c` (Quote input)
  and the five `Non_Orig_*_Pct__c` inputs.
- **AttrVolume §2.1 / §6.3** volume source is a rep-entered `Attribute_Volume` configurator attribute, not `LineItemQuantity`.

---

## E. Final-matrix reconciliation (Tab-1) — S12 exogenous base-price drift
- **Observed (Tab 2's frozen S12 gate, `S12_REBASE_NOTE.md`):** S12 line 3 (GoAnywhere Services, Qty 20) shows
  `Base_Price__c` / `Pre_Partner_Price__c` / `UnitPrice` **blank→250**; `NetUnitPrice` (250) + `TotalPrice` (5000)
  **UNCHANGED**. So **no price moved** — three base/pre-partner *audit* stamps populated to match the net.
- **Attribution:** exogenous to Round-3 design work (Tab 2's hardware classes reference those fields 0×; Tab 3's
  changes are 0-delta). Written by base/partner classes (`ListPriceStampCalculator`, `PartnerPricingPrehookV2`,
  `PartnerNetPricePosthook`, `ContributorPricingCalculator`) — the committed refactor base-price stamps and/or Nir's
  uncommitted `PartnerPricingServiceV2`, deployed to shared FortraUAT Jul-7→Jul-8.
- **✅ RESOLVED (Tab-1 targeted drift matrix, 2026-07-08):** repriced S3/S5/S6/S7/S9/S12 → the 5 partner/COLA/regional
  scenarios are **0-delta**; S12 reproduces only the 3 audit stamps (net unchanged). So the stamp is **price-neutral
  and non-cascading** (does not move any partner/COLA net), is **committed** (not Nir's uncommitted diff, which
  doesn't touch these fields; not Round-3), and the value is **correct** (`Base=Pre_Partner=Unit=Net=250` for a
  no-discount Services line). **Re-baselined S12** (pre-drift copy preserved at `baselines/S12_quote.pre_r3drift.tsv`).
  Residual: the exact introducing commit is untraced but benign — see `baselines/S12_REBASE_NOTE.md` Tab-1 resolution.

---

## Round-3 SHIPPED fixes (outcomes, for the record)
- **Tab 2 (Hardware) `173431a`:** F1 source-label → SDD-canonical winning tier per §8 Rule 5 (was invalid `'User
  Override'`); F2 top user-band open-ended per §8 Rule 3 (dropped 999999 cap, 1M+ → 3.0×). 71/71 tests; S12 price-neutral.
- **Tab 3 (Regional) `8d1ec19`:** effective-dating per Rule 14/BR-007 via null-safe in-memory `isEffectiveOn` (CMDT
  SOQL rejects the null-safe OR window). Provably 0-delta today (125 active rows, 0 dated); 18/18 tests; S9/S10 0-delta.
- **Escalated (no code):** Hardware product-gate (A-5), Regional null-multiplier (A-6), AttrVolume no-match (A-4).
