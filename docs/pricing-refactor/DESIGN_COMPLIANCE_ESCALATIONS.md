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
- **SDD conflict (internal):** §6 lists a **4-tier** hierarchy `Line > MyCAP Default > Contract > CMDT`;
  §7.1 / §10.1 describe a **3-tier** `Line > Contract > CMDT`.
- **Code + live data:** implements `Line > Contract > CMDT`, with MyCAP as an **out-year** concept
  (`COLA_Outyear_Uplift_Percent__c`, 3% floor for multi-year), NOT a year-1 tier. Confirmed by live data:
  **0 of 7** real `MyCAP Default` lines on FortraUAT carry the MyCAP value in year-1; all carry the CMDT default.
- **Recommendation:** the code is right; update SDD §6 to state MyCAP is an out-year floor, not a year-1 tier.
- **Impact if ruled the other way:** MyCAP would need to outrank Contract in year-1 tier selection
  (`COLAUpliftCalculator.resolveTier` + prehook) — a real behavioral change gated on S3.

### A-2. Partner V2 — E-04 Non_Orig fallback (⚠️ this lives in Nir's UNCOMMITTED working tree)
- **Behavior:** for a Fortra-Originated deal whose `Non_Orig_*_Pct__c` band is **blank**, the code
  (`PartnerPricingServiceV2.getMarginForProductType`, `effectivePct`) falls back to the standard /
  non-originating band instead of treating the blank as "no partner margin."
- **Provenance:** this change is in the **uncommitted** co-owned `PartnerPricingServiceV2.cls` (0 occurrences
  in committed HEAD, 11 in the working tree). It is **not** part of the committed refactor — it's Nir's WIP.
- **Ask:** Nir + Marc confirm whether the "borrow the standard band on blank Non_Orig" fallback is sanctioned
  (Partner V2 Open Issues RULE 2). If yes → document it in the Partner SDD. If no → Nir reverts in his file.
- **Not ours to change.**

### A-3. ARR — renewal Opportunity.Amount: MRR×12 or persisted Asset.ARR__c?
- **Behavior:** `RenewalForecastAmount` (SC-3500) computes `Opportunity.Amount = Σ (MRR × 12 × COLA)`,
  NOT from a persisted `Asset.ARR__c`.
- **Recommendation:** intentional per SC-3500; annotate the ARR SDD that renewal-opp amount is a forecast
  (MRR×12×COLA), not an Asset rollup. No code change.
- **Secondary:** verify `PowerOrderSplittingService` apportions `Order_Line_ARR__c` on splits (it currently
  divides only `Displaced_ARR__c`). If ARR must split too, that's a small, separate fix.

### A-4. AttrVolume — no-match / null-volume behavior (⚠️ SC-3390 regression risk)
- **Behavior:** on no-match AND null volume, the code **resets the line to list price**; SDD §6.3 / Rule 10
  may intend "leave the line untouched."
- **Risk:** this behavior is tied to **SC-3390** (tiered-price-twice fix). Changing it may regress a shipped
  ticket. Tab 3 is verifying the SC-3390 tie; if confirmed intentional → this becomes an SDD doc-update, not a code change.
- **Ask:** Marc confirms desired no-match behavior. Default assumption: keep current (SC-3390), update the SDD.

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
- **Tab 2 (Hardware):** `Hardware_Pricing_Source__c` 'User Override'→'Configurator'; open-ended top user-band (1M+→3.0×).
- **Tab 3 (Regional):** Active+null-`Multiplier__c` guard (skip, don't derive off null); effective-dating predicate (if KB Rule 14 is unambiguous).
