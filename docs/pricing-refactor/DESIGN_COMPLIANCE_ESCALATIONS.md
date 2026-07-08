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
- **Ask (Nir + Marc; do NOT touch the file):** (a) SANCTION ⇒ document in Partner SDD §6.3 as an explicit "blank Non_Orig ⇒ standard band" rule, track as an intended delta (plan exit-gate line 329), run a Non_Orig data-completeness audit; or (b) REJECT ⇒ Nir reverts `effectivePct` in his own tree, close E-04 by **data remediation** (populate Non_Orig — the V21-verified fix was 312.40 = Non_Orig 12%).

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

### A-4. AttrVolume — no-match / null-volume reset-to-list ✅ RESOLVED to a Tab-3 fix (NOT a ruling)
- **Verified finding (high confidence):** live code resets no-match lines (prehook `:283-291`) AND null-volume
  lines (`:271-279`) to list price via `AttributeVolumeCalculator.buildResetNodeUpdate` (`:244-275`:
  `Base_Price__c=ListPrice`, `Attribute_Price_Mode__c='Unit Price'`; or `Base_Price__c=0` when ListPrice is null).
  This **directly violates** SDD §6.3/Rule 10 ("write NOTHING, skip, do not zero out prices"). The null-ListPrice
  branch is a latent **$0** defect.
- **SC-3390 ruled OUT (proven):** the reset is **NOT** from SC-3390 — it predates it (present in the Jun-2 SC-3308
  org snapshot); SC-3390's commit only added evidence files; SC-3390's shipped fix was an `IsPriceImpacting`
  PAD-data flip with **zero Apex change**. The "SC-3390/D-17" code comment = discovery origin, not causation.
  ⇒ making no-match **SKIP would NOT regress SC-3390** (orthogonal).
- **Disposition: a real Tab-3-owned fix (refactor-plan D-17), NOT a Marc ruling.** Both the SDD (Rule 10) and the
  plan (D-17) agree: remove the silent reset-to-list. Tab 3's earlier STOP was about a `*_Warning__c` field-blocked
  variant — the skip/clear variant is unblocked and needs no new field.
- **One open technical precondition (for Tab 3):** a bare skip leaves any stale prior-tier `Base_Price__c` unless
  the V21 procedure re-derives list price on absent `Base_Price__c`. If V21 re-derives ⇒ **bare skip** (write
  nothing, per Rule 10). If V21 carries the stale value ⇒ replace the reset with an **explicit CLEAR** (write null
  `Base_Price__c`/`Attribute_Price_Mode__c`). Confirm V21 behavior first. Gate on S11/S2 (`0Q0WC000003GMu5`) + a
  constructed no-match-with-stale-prior-tier case.

---

## B. Context / ExpressionSet config items (NOT Apex — for the V21 procedure owner)

### B-1. COLA — audit fields must be `inputoutput` on `SalesTransactionContextExt` (reprice persistence)
- **KB §6.2 / line 253 (verbatim):** "To ensure audit fields persist through repricing, the Context
  Definition's `SalesTransactionContextExt` must have COLA audit fields set to **`inputoutput`**.
  **Output-only attributes get nullified on reprice** unless a pricing-procedure step explicitly outputs them."
- **Fields:** `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Solution_Category__c`, `COLA_Applied_Date__c`,
  `COLAApplied__c`, `COLAUpliftPercent__c`.
- **Action:** verify the V21 context definition has these as `inputoutput`. This is the real "COLA_Applied_Date
  overwritten/nullified on reprice" residual — it is **context config, not Apex** (the handler already writes
  Applied_Date once at first-application). Single-threaded, procedure-owner only.

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

## In-flight clean code fixes (Round 3, tabs — NOT escalations, listed for completeness)
- **Tab 2 (Hardware):** `Hardware_Pricing_Source__c` = `'User Override'` → map to the winning tier value per KB §8 Rule 5 (`Configurator | Hardware Default | System Default`, not hardcoded 'Configurator'); open-ended top user-band (1M+ → 3.0×, §8 Rule 3).
- **Tab 3 (Regional):** Active+null-`Multiplier__c` guard (skip, don't derive off null); effective-dating predicate (KB Rule 14; mind the CMDT vs `Regional_Pricing_Entry__c` field-name split).
- **Tab 3 (AttrVolume) — promoted from A-4:** remove the no-match/null-volume reset-to-list (SDD Rule 10 SKIP); SC-3390 proven unrelated. One V21 precondition (bare-skip vs explicit-clear) — see A-4.
