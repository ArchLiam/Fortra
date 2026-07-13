# Pricing-Layer SDD Reconciliation Audit — Round 6

- **Date:** 2026-07-08 · **Tab:** 2 · **Org:** FortraUAT · **Branch:** uat
- **Mode:** READ-ONLY. No code/flow/ESD edits, no deploy/reprice/DML. This doc is the only deliverable. **Do NOT commit.**
- **Direction of truth:** the RCA Solution Design Docs (`docs/RCA Solution Guide/kb/`) are FROZEN and authoritative. Where live Apex diverges, the reconciliation is ALWAYS **code→SDD** (or, for a deliberate post-SDD decision, an SDD amendment under owner change-control). No fix is applied here.
- **Method:** 7 independent per-concern audits (Partner, COLA, Regional, Hardware, AttrVolume, Maintenance-derived, Cancel/credit), each cross-referencing the concern's SDD rules against the live class:line. Owner-intended divergences are tagged **OWNER-DECISION**, not counted as blind defects.
- **Severity:** CRITICAL = wrong price to customer / revenue leak / hard-fail in a common path · HIGH = wrong price or missing SDD-mandated behavior in a realistic path · MEDIUM = edge-case-only wrong value, or audit/traceability gap · LOW = cosmetic / logging / doc-accuracy.

> **Scope caveat (applies throughout):** these audits cover the pricing **Apex** (hooks + extracted calculators/services). Three governing surfaces live OUTSIDE this Apex and were not adjudicated in-file: (a) the **Procedure Plan Definition** (hook ordering / waterfall position), (b) the **Context Definition** on `SalesTransactionContextExt_v2` (which attributes are `inputoutput` and survive reprice), and (c) **triggers** (`QuoteLineItemTriggerHandler`, `COLAUpliftHandler`). Several verdicts depend on these and are marked "SDD-SILENT (in-code)" or flagged for a follow-up pass.

---

## Executive summary

**In-scope code→SDD DRIFTs: 23** — **7 HIGH · 12 MEDIUM · 4 LOW** — across the 7 audited classes/calculators.
Plus **1 cross-file HIGH architecture gap** (Regional post-hook absent, below), and **Cancel/Credit is entirely SDD-SILENT** (no cancel-line pricing rule exists in the KB; 3 governance flags raised).

Of the 7 HIGH drifts, **4 are OWNER-DECISION / architecture** — the code is a deliberate post-SDD choice and the SDD is stale, so the resolution is an SDD amendment, not a code fix: `D-COLA-1`, `D-ATTRVOL-1`, `D-MAINT-1`, `D-MAINT-5`. That leaves **3 genuinely actionable HIGH code defects**.

### Top 3 (most severe, genuinely actionable — code is wrong vs a still-valid SDD rule)

1. **D-HARDWARE-1 — No Power-only product-eligibility gate (HIGH).** Hardware SDD §8 Rule 12 mandates "only Power products get hardware pricing, gated by `HardwareProductEligibilityService` on family/solution-category." The prehook has **no** eligibility call — it prices any line with a `Hardware_Id__c` or a configured hardware attribute (`HardwareAttributePricingPrehook.cls:537`). A non-Power line that acquires a hardware link/attribute gets the pGroup/user/system multiplier and its `UnitPrice` overwritten. Compounding wrinkle: the referenced service actually filters on processor-count / feature-codes, **not** family/category (`HardwareProductEligibilityService.cls:80-141`), so the SDD-named gate is not implementable as written — needs an owner ruling on the intended predicate.

2. **D-ATTRVOL-2 — Volume tier keyed off the wrong dimension (HIGH).** AttrVolume SDD §2.1/§6.3/TR-007 says the tier is matched against **`LineItemQuantity`**. The code matches against a rep-entered configurator attribute `Attribute_Volume` (`AttributeVolumeCalculator.cls:31,364-375`; `AttributeVolumePricingPrehook.cls:270`) and never reads line quantity for banding. Where `Attribute_Volume ≠ LineItemQuantity` (or is blank), the customer is priced on the wrong number (blank → the reset-to-list branch, D-ATTRVOL-1).

3. **D-PARTNER-1 — Missing-model warning never emitted (HIGH).** Partner SDD §6.3/BR-007 requires a per-line `Partner_Pricing_Warning__c` when a configured partner lacks the required pricing-model type. The field is only ever written `null` (`PartnerPricingPayloadBuilder.cls:37`; clear path `PartnerPricingPrehookV2.cls:952`); a misconfigured partner silently prices at full list with no signal — the exact case the SDD requires a warning for.

**Highest raw blast radius (but OWNER-DECISION):** `D-ATTRVOL-1` — on no-match/null-volume the prehook stamps `Base_Price__c = ListPrice` (Section 3, i.e. *after* Regional/Partner), which can override an upstream regional/partner net with list price. It is the deliberately-retained SC-3390/D-17 behavior; the SDD mandates the opposite ("write nothing"). Resolution is owner change-control (amend SDD or narrow the reset to attribute-only fields), not a blind revert.

---

## 1. Prioritized DRIFT list (most severe first)

### HIGH

#### D-ATTRVOL-1 — No-match/null-volume writes a "reset-to-list" payload instead of writing nothing — HIGH (CRITICAL potential) · OWNER-DECISION (SC-3390 / D-17)
- **SDD:** AttrVolume §6.3 "No-Match Behavior — skip the line entirely; **no context attributes written**, allow standard pricing to fall through"; §7 Rule 10 "no-match = no writes; do not write defaults or zero out prices."
- **Code:** null volume → `AttributeVolumePricingPrehook.cls:273-281`; no tier match → `:285-294`; both append `AttributeVolumeCalculator.buildResetNodeUpdate` (`:244-275`) which writes `Base_Price__c = ListPrice` (`:255-258`) and `Attribute_Price_Mode__c = 'Unit Price'` (`:266-269`). Class header (`:33-35`) says this is "preserved EXACTLY… NOT fixed."
- **Delta:** SDD wants zero writes so the line keeps its upstream (Regional §1 / Partner §2) net; the code force-stamps list price. Whether it clobbers depends on how the downstream List Operations consume `Base_Price__c` for eligible lines (not verifiable in-file) → HIGH with CRITICAL potential (revenue impact on any line a rep left `Attribute_Volume` blank or that misses a tier).
- **Reconciliation (sketch, do NOT apply):** owner ruling — (a) amend SDD §6.3/Rule 10 to document the intentional reset-to-list (added to defeat SC-3390 stale-context on reprice), or (b) narrow the reset to clear only attribute-pricing context fields, leaving Regional/Partner outputs intact.

#### D-ATTRVOL-2 — Volume dimension read from `Attribute_Volume` attribute, not `LineItemQuantity` — HIGH
- **SDD:** §2.1 step 3/step 5, §6.3, TR-007: match the tier against the line's **`LineItemQuantity`**.
- **Code:** `AttributeVolumeCalculator.cls:31` (`ATTR_VOLUME_NAME='Attribute_Volume'`), `:364-375` reads that configurator attribute; `AttributeVolumePricingPrehook.cls:270`. `LineItemQuantity` is never read for banding.
- **Delta:** tier keyed off a rep-entered attribute rather than ordered quantity; blank/unparseable → null → reset-to-list (D-ATTRVOL-1). Wrong tier/price wherever the two differ.
- **Reconciliation (sketch, do NOT apply):** owner decision — if configurator-volume is the intended dimension, amend §2.1/§6.3/TR-007 to name `Attribute_Volume` + define the "unset" policy; if `LineItemQuantity` is authoritative, switch the volume source to the quantity context tag (still in-memory, no extra SOQL).

#### D-HARDWARE-1 — No product-eligibility gate; hardware pricing applied to any line with hardware linkage or configured attrs — HIGH
- **SDD:** Hardware §8 Rule 12 (do-not-violate) + §4.7: "Only Power products get hardware pricing: eligibility gated by `HardwareProductEligibilityService` on product family / solution category."
- **Code:** the only guard is `HardwareAttributePricingPrehook.cls:537` — priced when `Hardware_Id__c` present **OR** any configured `Pgroup/Server_Type/Users`. `HardwareProductEligibilityService` is never referenced; `ProductId` (`:534`) feeds only a debug line (`:609`). Secondary mismatch: the service filters on `Processor_Min__c`/feature-codes (`HardwareProductEligibilityService.cls:80-141`), **not** family/category.
- **Delta:** SDD-mandated Power-only gate is entirely absent from the pricing path; a non-Power line with a hardware link/attribute gets the multiplier and `UnitPrice` overwrite (`:677`). HIGH not CRITICAL — the common non-Power line has no `Hardware_Id__c`, so wrong price only on realistic-but-not-default paths.
- **Reconciliation (sketch, do NOT apply):** add an eligibility gate in `processLineItem` before the multiplier math (skip ineligible via `Product2` family/category), OR add a per-line `isEligible(...)` seam to the service. **Owner ruling first** on the intended predicate (family/category vs the service's current processor/feature-code logic).

#### D-PARTNER-1 — Missing-model warning never emitted — HIGH
- **SDD:** Partner §6.3 "Missing Model Warning" / BR-007 / rule 14: write `Partner_Pricing_Warning__c` per line identifying the partner(s) needing configuration.
- **Code:** `PartnerPricingPayloadBuilder.cls:37` always sets `Partner_Pricing_Warning__c => null`; clear path `PartnerPricingPrehookV2.cls:952` only nulls it. No non-null write anywhere (grep-confirmed). A partner with no matching model → `getMarginForProductType` returns 0 → list price unchanged, silently.
- **Delta:** the SDD-required signal for a misconfigured partner is entirely absent (behavior missing, not merely different).
- **Reconciliation (sketch, do NOT apply):** when a participating partner resolves no model (or 0%), collect the partner name(s) and write an identifying `Partner_Pricing_Warning__c` instead of the hardcoded `null`.

#### D-COLA-1 — MyCAP 3% default never applied to the qualifying line's year-1 COLA % — HIGH · OWNER-DECISION (year-1/out-year redesign)
- **SDD:** COLA §4.6.4 / §11 r10 + §4.8 Ex4: a qualifying non-overridden multi-year annual renewal defaults `COLA_Uplift_Percent__c = 3.00`, price = base × 1.03.
- **Code:** value-persisting path keeps `colaPercent = cmdtDefault` and only relabels the source (`COLAUpliftPrehook.cls:393,409,416`); the MyCAP path's `targetUplift=defaultUplift` (`:1079`) is appended to `allContextUpdates` which is **never submitted** (`:1101-1113`). Rationale in-code (`:396-399`): year-1 stays at CMDT rate; out-year 3% applied by the `Final_Year_COLA_Calculated_Price__c` formula field.
- **Delta:** SDD wants the whole line at 3% (base × 1.03); live prices year-1 at full CMDT rate (e.g. base × 1.0985) → ~+6.85% year-1 divergence on a 9.85% category. Likely deliberate (MEMORY `project_cola_v16_v20_reconcile`).
- **Reconciliation (sketch, do NOT apply):** owner ruling — (a) amend Ex4/§4.6.4/§11 r10 to codify the year-1-CMDT + out-year-3% split, or (b) if the SDD binds, set `colaPercent = mycapDefault` when the MyCAP branch fires. Do NOT re-enable the dead `allContextUpdates` submit (can't write the percent anyway; would clobber Asset-priced audit writes).

#### D-MAINT-1 — Maintenance priced by a custom Apex posthook, not the SDD's config-only design — HIGH · OWNER-DECISION (architecture)
- **SDD:** Maintenance doc1 rule 1/3 + doc2 TR-001/rule 1: delivered via one field + one before-save Flow + one procedure Formula element; **custom Apex pricing is "explicitly NOT used… tried and abandoned."**
- **Code:** the maintenance net is Apex-computed and injected into the `_v2` context by `PartnerNetPricePosthook` + calculators — `RenewalMaintenancePricingService.cls:218-239`, `DerivedMaintenancePayloadBuilder.cls:15-68`.
- **Delta:** the "no prehook" letter is honored (it runs as a *post*hook after the native derived element), but "config-only / no custom Apex pricing" is not — the whole maintenance price is Apex-driven. Arithmetic matches the SDD formulas; the architecture does not.
- **Reconciliation (sketch, do NOT apply):** owner ruling — amend the SDD to record the posthook architecture as accepted, or confirm the Flow+formula path is still the target and the posthook is interim. No code change proposed.

#### D-MAINT-5 — Renewal-maintenance COLA branch fully shipped despite the SDD's explicit block — HIGH · OWNER-DECISION
- **SDD:** Maintenance doc2 rule 13 / BR-005 / E-001: "do not complete the renewal branch until BR-005/E-001 is resolved"; renewal branch "BUILT but NOT VALIDATED," carry-forward persistence "NOT built."
- **Code:** a complete Apex renewal implementation is live — `RenewalMaintenancePricingService` (whole file) + `RenewalMaintenanceColaCalculator.cls:14-82`, consuming persisted `Prior_Partner_Discount__c`/`Prior_Discretionary_Discount__c` (queried `:334-343`).
- **Delta:** live is well past the SDD's frozen "blocked/unvalidated" state (consistent with SC-3346/SC-3350). Frozen SDD and code now contradict each other on whether this branch should exist.
- **Reconciliation (sketch, do NOT apply):** owner — record the BR-005/E-001 resolution; mark rules 12/13 + D-005/TR-005 superseded. No code change.

#### D-REGIONAL(cross-file) — SDD-mandated `RegionalServicesPricingPosthook` (last writer of `NetUnitPrice`) does not exist — HIGH · cross-file / OWNER change-control
- **SDD:** Regional Rules 9 & 11 + §2.1 step 7: a post-hook is the last writer of `NetUnitPrice` (reads `RegionalNetUnitPrice__c`) and chains to Partner via `Type.forName()`.
- **Code:** grep finds **no** `RegionalServicesPricingPosthook` (or `PartnerPricingPosthook`) in `force-app`. Live V21 maps `RegionalNetUnitPrice__c → InputUnitPrice` (list-side) in the procedure (`Rev_Mgmt_Default_Pricing_Procedure…xml:3584-3612`) with no `NetUnitPrice` finalizer — i.e. the multiplier hits **LIST only; NET stays catalog** (matches MEMORY `project_regional_services_pricing_mechanism`).
- **Delta:** the two audited Regional Apex files are individually SDD-conformant, but the SDD's post-hook net-finalization design is absent from live. Highest-consequence Regional item; lives outside the audited files.
- **Reconciliation (sketch, do NOT apply):** owner — confirm whether the PP-only list-adjust approach intentionally superseded the post-hook design; if so, the SDD's post-hook section (Rules 9–11) is stale and needs change-control.

### MEDIUM

- **D-COLA-2 — MyCAP-Default vs Contract-Override tier order inverted — MEDIUM.** SDD §4.2/§11 r3 order is Line > **MyCAP > Contract** > CMDT; code resolves Contract first (`COLAUpliftCalculator.cls:74-76`) and only relabels MyCAP when source == 'CMDT Lookup' (`COLAUpliftPrehook.cls:401`), so a valid contract override never reaches MyCAP → effective Line > Contract > MyCAP > CMDT. (SDD is internally inconsistent on tier count — §6 lists 4, §7.1/§10.1 list 3.) Reconciliation: owner — if r3 is authoritative, widen the MyCAP relabel guard to also fire over 'Contract Override' for qualifying lines.
- **D-COLA-3 — `COLA_Applied_Date__c` rewritten to `now()` every reprice — MEDIUM.** SDD §3.5 = "when COLA was **first** applied." Both writers stamp `Datetime.now()` unconditionally (`COLAUpliftCalculator.cls:297-300,389`). Reconciliation: only stamp when the persisted value is null (requires reading prior value; interacts with the `inputoutput` context config).
- **D-COLA-4 — `MyCAPFlagApplier` no longer restores QLI audit fields — MEDIUM (compensated).** SDD §5/§7.3 says the Queueable flips `Quote.Mycap__c` **and** restores QLI audit fields; code does only the Quote flip (`COLAUpliftPrehook.cls:1185-1219`), relying on context write-back. Compensated iff the audit attrs are `inputoutput` on `SalesTransactionContextExt` (a context-definition dependency to verify). Reconciliation: keep the loop-avoiding design; amend SDD or verify the context config — no Apex change indicated.
- **D-PARTNER-2 — Posthook deferred path is deal-blind and non-deterministic on duplicates — MEDIUM.** For prehook-skipped lines (derived maint / $0-at-prehook), `PartnerNetPricePosthook` routes through V1 `PartnerPricingService` with `dealType=null` (`PartnerPricingService.cls:258`) → `useNonOriginating=false` always, and its `getPricingModels` SOQL has no `Non_Orig` fields and **no `ORDER BY`** (`:50-63`, last-put-wins). Prehook (V2, deal-aware, `CreatedDate DESC`) and posthook (V1, deal-blind) disagree. Reconciliation: point the deferred path at V2 with the quote's `Deal_Type__c` + newest-wins selection.
- **D-PARTNER-3 — Duplicate-model selection stays silent — MEDIUM.** V2 memo rule 5: when >1 model matches, keep newest-wins AND warn. Code resolves one via hierarchy + `CreatedDate DESC` (`PartnerPricingServiceV2.cls:58-104`) with no warning. Reconciliation: surface a duplicate warning through the same `Partner_Pricing_Warning__c` write as D-PARTNER-1.
- **D-PARTNER-4 — Price-source adds an un-doc'd `RegionalNetUnitPrice__c` tier — MEDIUM.** SDD §6.3 rule 10 = `UnitPrice` then `ListPrice` (two-source); code is `RegionalNetUnitPrice__c` > `UnitPrice` > `ListPrice` (`PartnerNetResolutionCalculator.cls:17-25`). Intent-consistent (regional writes that field, not UnitPrice) but literal-rule divergence. Reconciliation: amend rule 10 to name `RegionalNetUnitPrice__c` first (preferred, code→SDD-by-doc), or drop the extra tier.
- **D-PARTNER-5 — Custom `Partner_Discount_Percent__c` not written on success — MEDIUM.** SDD §6.2 names it "total partner % applied"; success payload writes only the **standard** `PartnerDiscountPercent` (`PartnerPricingPayloadBuilder.cls:27`), yet the custom field IS nulled on the stale path (`PartnerPricingPrehookV2.cls:948`) — asymmetric. No price impact (standard field carries value). Reconciliation: add `Partner_Discount_Percent__c => totalPercent` to the success payload.
- **D-REGIONAL-1 — Explainer multiplier truncated to 2 decimals — MEDIUM.** SDD range top is `1.015` (3-dec, UK); explainer uses `multiplier.setScale(2)` (`RegionalServicesPricingPrehook.cls:325`) while the price calc uses full precision (`RegionalPricingCalculator.cls:65`). Ties to the SDD §6.2 open field-scale question (`Number(4,2)` vs 3-dec need). Reconciliation: resolve the CMDT `Multiplier__c` scale first; render the explainer at actual scale (or correct the SDD).
- **D-ATTRVOL-3 — Waterfall-visibility OUTPUT fields never written to context — MEDIUM.** SDD §7 r18/TR-006 mandates `AttributePricingApplied__c`, `AttributePricingExplainer__c`, `Attribute_Feature__c`, `Attribute_Quantity__c` on apply. `AttributeVolumeCalculator.cls:192-223` writes none (explainer only `System.debug`; applied-flag deliberately removed to avoid batch-poisoning, `:215-217`). Reconciliation: create the four OUTPUT context attributes + hydration mappings (config) first, then re-add to the payload.
- **D-MAINT-2 — New-business multiplicand prefers runtime contributor over the stamped field — MEDIUM.** SDD doc1 rule 2/8: multiply the **stamped `Source_List_Price__c`**, do NOT rely on runtime contributor resolution. Code priority is inverted — runtime contributor base first, stamped field fallback (`PartnerNetPricePosthook.cls:1156-1161,1886-1889`). Usually coincides; diverges when contributor base ≠ stamped list. Reconciliation: flip priority to stamped-field-primary, or amend the SDD to accept the same-transaction Apex contributor lookup.
- **D-MAINT-3 — Order-path contributor base uses post-discount `NetUnitPrice` — MEDIUM.** SDD doc2 BR-002: base EXCLUDES partner/discretionary discounts (validated `$468 × 0.20 = $93.60`). `ContributorPricingCalculator.resolveContributorPricingBase(OrderItem)` returns `NetUnitPrice` first (`:69-86`), unlike the QLI overload (`:45-67`, pre-discount). On the order path a discounted license can pull the maintenance base down + partner% re-applied → compounded reduction. Reconciliation: align the OrderItem overload with the QLI overload (pre-discount base first), verify no double partner-discount.
- **D-MAINT-4 — Off-list/blank tier skips the line instead of writing $0 — MEDIUM.** SDD doc1 rule 11 / doc2 rule 4: blank/off-list tier → **$0**. `NewMaintenanceInputResolver.cls:12-14` returns null → posthook `continue`s (`:1153-1155,1206-1208`), retaining the native value. Equals SDD only when native is already $0. Reconciliation: stamp $0 explicitly on the off-list path, or document "skip = retain native $0" as equivalent.

### LOW

- **D-PARTNER-6 — Blank context id returns FAILED, not fail-safe SUCCESS — LOW.** `PartnerPricingPrehookV2.cls:111-115` returns FAILED on blank `ctxInstanceId`, contrary to the absolute SUCCESS rule (TR-004). Effectively unreachable. Reconciliation: return SUCCESS with a skip message.
- **D-COLA-5 — Stale class-header write-set — LOW.** Header (`COLAUpliftPrehook.cls:11-16`) claims it writes `COLAUpliftPercent__c`/`COLAExplainer__c`/`COLAApplied__c`, but `buildItemUpdate` deliberately omits all three (`COLAUpliftCalculator.cls:272-285`); the `explainer` param is computed then discarded. Cosmetic. Reconciliation: correct the header; optionally drop the unused explainer plumbing.
- **D-COLA-6 — Dead alt builder violates the base-price invariant if re-enabled — LOW (latent).** `buildCOLAContextUpdate` back-derives `preCOLA = unitPrice/(1+pct/100)` and compounds across terms (`COLAUpliftCalculator.cls:355-371`), not anchored to `SourceAsset.Price` (§11 r1). Only reachable via the never-submitted `allContextUpdates` → dead today. Reconciliation: if reactivated, source `preCOLA` from Asset price.
- **D-ATTRVOL-4 — Multiplier context attribute name mismatch — LOW (doc imprecision).** SDD §6.2/§6.2.1 name `AttributeMultiplierPct__c`; code writes `Attribute_Multiplier_Pct__c` (underscored, `AttributeVolumeCalculator.cls:210`). By batch-hygiene rule, the underscored name is almost certainly the real deployed attribute → SDD imprecise. Reconciliation: verify the org attribute API name, amend the SDD; do NOT rename the code.

---

## 2. Per-concern MATCH / DRIFT / SDD-SILENT summary

| Concern | Files (ln) | Rules checked | MATCH | DRIFT (H/M/L) | SDD-SILENT / N-A | OWNER-DECISION |
|---|---|---|---|---|---|---|
| **Partner** | PartnerPricingPrehookV2 (983), PartnerPricingServiceV2 (223), PartnerMarginDispatcher (119), PartnerNetPricePosthook (2056, net path) | ~19 | 13 | **6** (1H·4M·1L) | posthook net logic (lower-of, derived-maint commit), waterfall pos, Net/UnitPrice propagation, >100% cap | E-04 Non_Orig catalog fallback |
| **COLA** | COLAUpliftPrehook (1229), COLAUpliftCalculator (396) | 21 | 14 | **6** (1H·3M·2L) | rounding, order-scope guard, out-year flag input, Activated-contract filter, renewal-maint stamped path | D-COLA-1 year-1/out-year redesign; trigger→prehook move |
| **Regional** | RegionalServicesPricingPrehook (440), RegionalPricingCalculator (69) | 16 | 13 | **1M** in-file (+1H cross-file: post-hook absent) | waterfall pos, ≤0 skip, re-entrancy, logger, extra applied-flag | O-1 UnitPrice-for-all-lines; O-2 currency-blind $5 rounding; O-3 post-hook |
| **Hardware** | HardwareAttributePricingPrehook (914), HardwarePricingCalculator (148) | 12 (§8) | 9 | **1H** | waterfall pos (Rule 7), trigger inheritance (Rule 10), parse-error sub-source, zero-price skip, fractional users | (F1/F2/D-14 already fixed → MATCH) |
| **AttrVolume** | AttributeVolumePricingPrehook (525), AttributeVolumeCalculator (467) | 20 | 14 | **4** (2H·1M·1L) | section-3 ordering, price-mode arithmetic (downstream), key normalization, null-bound defaults, overlap A-002 | D-ATTRVOL-1/2 (SC-3390/D-17 reset retained) |
| **Maintenance-derived** | 8 calculators + posthook shell | 15 | 8 | **5** (2H·3M·0L) | field-write breadth, rounding, year-2 compounding, partner "New Maint" band (cross-domain J-06), tier-rate values (org-side) | D-MAINT-1 architecture; D-MAINT-5 BR-005 resolved |
| **Cancel/Credit** | CancelLineCreditPosthook (412), CancelLineCreditCalculator (454) | 12 behaviors | — | **0** | **ENTIRE concern SDD-SILENT** — no cancel-line pricing rule in the KB (SC-3441 absent) | 3 governance flags (N-1/N-2/N-3) |

---

## 3. OWNER-DECISION register (divergences that are deliberate — resolve via SDD amendment / owner ruling, NOT a blind code fix)

| Tag | Item | Why it's owner-intended | Owner action |
|---|---|---|---|
| **E-04** | `PartnerPricingServiceV2.effectivePct:164-170` returns catalog % (not hard 0%) on null `Non_Orig_*_Pct__c` | Documented Wave-3b "catalog" fallback (comment `:159-163`); prevents a Fortra-Originated deal silently dropping to 0% margin. Owner has taken full engine ownership. | Confirm/keep; ensure `Non_Orig_*` data-completeness audit (OQ-1). |
| **D-COLA-1** | Year-1 stays at CMDT rate; 3% MyCAP applied to out-years via `Final_Year_COLA_Calculated_Price__c` | Deliberate year-1/out-year redesign (MEMORY `project_cola_v16_v20_reconcile`). | Amend Ex4/§4.6.4/§11 r10 — OR set `colaPercent=mycapDefault` if SDD binds. |
| **D-ATTRVOL-1 / D-ATTRVOL-2** | Reset-to-list on no-match/null-volume; volume from `Attribute_Volume` attr | SC-3390/D-17 deliberately retained (class header "NOT fixed"). | Amend §6.3/Rule 10 + §2.1/TR-007, or narrow the reset / switch dimension. |
| **D-MAINT-1** | Maintenance priced by Apex posthook, not config+Flow+formula | Deliberate post-SDD architecture (posthook sidesteps the native derived element that discards prehook writes). | Amend SDD to record posthook architecture as accepted. |
| **D-MAINT-5** | Renewal-maintenance COLA branch fully shipped | BR-005/E-001 resolved by SC-3346/SC-3350; carry-forward fields now persisted. | Mark rules 12/13 + D-005/TR-005 superseded. |
| **D-REGIONAL O-3** | Regional post-hook absent; NET stays catalog (list-only adjust) | Live V21 PP-only list-adjust supersedes the SDD's post-hook net-finalizer. | Confirm supersession; mark Rules 9–11 stale. |
| **Trigger→prehook (COLA)** | Base COLA application moved from `COLAUpliftHandler` trigger to the prehook | RLM Quote-DML lock adaptation (MEMORY `project_rlm_quote_dml_lock`). | Note in SDD §4.3/§5/§7.1; follow-up audit of `COLAUpliftHandler` for §4.5 override-stamping. |
| **Partner "New Maint" band** | `NewMaintenanceBandCalculator` overrides a line's own partner % with the billing partner's "New Maintenance" band | Cross-domain (Partner SDD / J-06), not the Maintenance SDD. | Route to Partner Pricing owner. |

---

## 4. SDD-SILENT & governance gaps (no authoritative rule to reconcile against — surfaced for owner ruling)

- **Cancel/Credit — the whole feature is out-of-band.** SC-3441 / `CancelLineCredit` appear **nowhere** in the KB; no SDD governs how a cancellation/credit line is priced by the engine. The classes implement a negative-qty gate + `credit = net × qty` with a 3-tier unit-price source. Three flags for Fortra to rule on:
  - **N-2 (MEDIUM, most material) — lossy `ListPrice` fallback can over-credit.** When neither staged `CancelNetUnitPrice__c` nor an asset NET resolves (or currency mismatch), the credit uses `ListPrice` (`CancelLineCreditCalculator.cls:347-349`, code labels it "LOSSY"). Fortra deals are routinely discounted (list > net common), so a list-based credit can refund more than the customer paid. Owner should rule the intended credit basis (and whether the lossy path should credit $0 / skip).
  - **N-1 (MEDIUM) — automated full-net line credit vs the SDD's "manual / no-refund-for-unused-days" policy** (Amendments §7; Contracts-Config §Proration). Different field surface (engine QLI price fields vs manual `Credit_Amount__c`) and layer, so not a literal violation — but confirm intent.
  - **N-3 (MEDIUM, traceability) — undocumented addition to the pricing waterfall.** Registered in the POST section of `Fortra_Pricing_PreHook` but absent from every SDD; needs a new SDD/addendum to bring SC-3441 under design governance.
- **Tier-rate values not repo-tracked (Maintenance).** Premier/Standard/Professional → 0.30/0.20/0.20 live in `Maintenance_Rate__mdt` records read at `PartnerNetPricePosthook.cls:1613-1617`; no `customMetadata/Maintenance_Rate.*` in `force-app`. Config-driven design MATCHES the SDD, but the actual rates are org-side only — recommend sourcing the mdt records into the repo for auditability. (Hardware's equivalent `Hardware_Attribute_Pricing__mdt` IS repo-tracked as of D-14.)
- **Regional O-1/O-2 (owner-verification).** O-1: the prehook writes `UnitPrice`/`RegionalPricingApplied__c` for *every* priced line incl. `Allow_Regional_Pricing__c=false` products; the PP gates consumption but confirm the PP re-sources non-eligible lines' base from catalog. O-2: CEILING-to-$5 rounding is currency-blind (rounds to 5 units of the transaction currency, not $5 USD) — a multi-currency divergence the Regional SDD doesn't model.
- **Renewal-maintenance magic numbers (Maintenance, audit-note).** `RenewalMaintenanceColaCalculator.cls:45-50` uses `Base_Price__c >= 10000` and `preColaNet < 0.5 × Base` to detect a mis-stamped contributor base; brittle constants, undocumented guardrail.

---

## 5. What was NOT adjudicated (follow-up scope)

- **Procedure Plan Definition metadata** — hook ordering / waterfall position (Partner Rule 5, Regional Rule 10, Hardware Rule 7, AttrVolume Rule 19). Verdicts are "SDD-SILENT (in-code)"; audit the ESD/PP metadata to close.
- **Context Definition (`SalesTransactionContextExt_v2`)** — which audit attrs are `inputoutput` (governs D-COLA-3, D-COLA-4, D-ATTRVOL-3 whether the removed restores/writes are truly compensated).
- **Triggers** — `QuoteLineItemTriggerHandler` (Hardware Rule 10 inheritance), `COLAUpliftHandler` (COLA §4.5/§11 r8 override-stamping fields not written by the audited classes).
- **`RegionalServicesPricingPosthook` / `PartnerPricingPosthook`** — mandated by their SDDs, absent from the repo (see D-REGIONAL cross-file HIGH). Confirm whether the PP-only approach superseded them.
