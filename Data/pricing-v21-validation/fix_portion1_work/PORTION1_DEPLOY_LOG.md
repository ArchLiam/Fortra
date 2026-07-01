# V21 Portion-1 — Deploy Log (FortraUAT, 2026-06-30)

Active proc `Rev_Mgmt_Default_Pricing_Procedure` V21 — ESDV `9QBWC0000000oWH4AY`, runtime ESV `9QMWC00000025LN4AY`.
Live ESD pre-edit md5 `5b19c304f07ac3eeed6dfa0ef31c9165` (= local source, no drift). Pre-edit backup: `fix_portion1_work/*.bak_preedit`.

## Decisions taken
- User: **Batch all 7 / Defer E-04**, then deactivated V21 and authorized deploy.
- **E-04 deferred** (user). Also: agent confirmed the prehook is wired on `ProcedurePlanOption 1FYWC0000002W3r4AE` (plan `Fortra_Pricing_PreHook`), **NOT** the ESD — the doc's "in-place ESD edit" was wrong. V2 (`01pWC000002TL37YAG`) returns 0% on null `Non_Orig_*` data, so PPM backfill must precede it.
- **I-03 excluded** — no confirmed proc edit; needs a fresh UI-built mid-term TermDefined repro + explainability trace (doc's own instruction). Static read shows proration legs gated by `Evergreen…` vs `TermDefined…ProrationFilter`; not resolvable blind.
- **F-09 + G-02 held from this cycle** — both currency, both with doc mechanics I could not confirm and that could make pricing WORSE:
  - The doc's **G-01** mechanic (`→NetUnitPrice`) was provably wrong (double-FX); the authoritative evidence (`rows_run3/G-01.json`) uses **`Base_Price__c`**. That the doc was wrong on G-01 is a strong prior the F-09/G-02 doc mechanics are also suspect.
  - **F-09**: evidence says fix = partner discount on **raw USD list**; the doc's "source ListPrice" would double-FX (EUR PBE × discount × hardcoded FX). Needs live trace.
  - **G-02**: evidence shows TWO defects — USD-gate fixes the leak, but L2 `$0` is a *currency-agnostic* no-PBE-fallback defect; gating ABA off without a fallback risks turning L1 from wrong-but-nonzero into **$0**. Needs live trace.
  - Plan: trace both with V21 ACTIVE (reprice + explainability), confirm exact mechanic, deploy as cycle 2.

## DEPLOYED THIS CYCLE (2 confident-correct fixes)
MDAPI deploy, api 67.0, `--metadata-dir`, target FortraUAT. Diff = 9 sites, all in ESD `Rev_Mgmt_Default_Pricing_Procedure`:

### K-01 / F-12 (SC-3441) — null-safe StampBaseFilter (3 unpatched copies)
- Lines 109595 / 116513 / 123420: `conditionLogic` `(1 OR 2) AND 3 AND 4 AND 5` → `(1 OR 2) AND 3 AND 4 AND (5 OR 6)`
- Added criterion 6 after criterion 5 in each: `<operator>IsNull</operator> <sequenceNumber>6</sequenceNumber> <sourceFieldName>NetUnitPrice</sourceFieldName>`
- Result: all **6** StampBaseFilter instances now null-safe (3 were already patched 05:56). Runtime recompiled by reactivation = the actual K-01 fix enabler.

### G-01 (SC-3384) — Currency 'Unit Price Display' single-FX (3 copies)
- Lines 106652 / 113321 / 120228 (`CurrencyConversionUnitPriceDisplay`): formula input `InputUnitPrice * IF(STICurrencyIsoCode…)` → `Base_Price__c * IF(STICurrencyIsoCode…)`
- Rationale: `Base_Price__c` is the preserved pre-FX USD base (=1575); `× FX` once = 1471.995. `InputUnitPrice` was a stale persisted value compounding `×0.9346` each reprice. (Evidence-confirmed; NOT the doc's `NetUnitPrice`.)

## NEXT STEPS (mandatory order)
1. **Reactivate V21 from Setup → Pricing Procedures → Versions list** (status flip, NOT canvas — hard rule #3). Recompiles runtime ESV.
2. Re-retrieve ESD; confirm md5 ≠ pre-edit and the 9 sites persisted (no canvas-clobber revert).
3. Verify: K-01 `0Q0WC000003FoMA0A0` (Net=15000,TP=-15000,isSuccess); F-12 `0Q0WC000003FapR0AS` (Net populated, NetTotal<0); G-01 `0QLWC000003kmG14AI` (UnitPrice=1471.995, stable on 2nd reprice).
4. Regression controls: USD partner E-02 `0Q0WC000003FO1u0AG` (301.75); a USD direct line; a BoKS derived demo quote.
5. Then trace + deploy F-09 + G-02 (cycle 2).
