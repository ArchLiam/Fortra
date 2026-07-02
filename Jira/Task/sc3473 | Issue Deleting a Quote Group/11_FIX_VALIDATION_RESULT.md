# SC-3473 — Fix Deployed & Validated (2026-06-29)

**Fix:** Re-added the guarded TermDefined Proration writer (dropped in Nir's V12) to pricing procedure **V16**.
Build: `Data/sc3473/build/` · Rollback: `Data/sc3473/backup/V160_PRISTINE.expressionSetVersion` · FINEST logs: `Data/sc3473/debug_logs/`
Deploy: deactivate V16 (UI) → deploy fix to inactive V16 → reactivate V16 (UI). 3 steps live: `TermDefinedProrationFilterLinelevel` → `ListOperationTermDefinedPTC` (guard: TermDefined + StartProrationPeriod IsNotNull + ItemSubscriptionTerm IsNotNull) → `ProrationTermDefined` (ProrationMultiplier→PricingTermCount).

## ✅ SC-3473 RESOLVED (the repro quote 0Q0WC000002U2020AC)
Reprice under new V16 derived the missing term fields; quote went **SaveFailedOrIncomplete → CompletedWithPricing**:

| Line | Type | PTC before→after | EndDate before→after |
|---|---|---|---|
| Advanced Job Scheduler | OneTime | 0 → 0 | null *(correct)* |
| Suspicious Email Intelligence | TermDefined | 1 → 1 | set |
| Suspicious Email Intelligence | TermDefined | 1 → 1 | set |
| **Abstract** (the malformed line) | TermDefined | **null → 1** | **null → 2027-06-25** |

Log proof: `PricingTermCount={…0QLWC000003jN8P4AU=1.0}`, `EffectiveTo={…=2027-06-25}`. The null term key that produced the Delete-Group NPE is now populated → trigger eliminated. **Remaining: retry Delete Group on the quote to confirm the NPE is gone end-to-end.**

## ✅ No regression
- Guard skips PeriodBoundary-null lines (StartProrationPeriod null) → no `INVALID_PERIOD_BOUNDARY`.
- Org-wide since activation (04:13Z): 0 `PriceCalculationFailed` / `SaveFailedOrIncomplete`; OneTime line stayed PTC=0 clean.

## ⚠️ Follow-up (out of scope for this fix): renewal TermDefined lines
Positive control #2 (beSECURE, quote 0Q0WC000003DLBP0A4 "Renewal Quote") did **not** derive PTC — its `PricingTermCount` map was empty for the whole reprice despite passing the guard (`StartProrationPeriod=DayOfPeriod`, `ItemSubscriptionTerm=1`). It routes through the **V12 maintenance/renewal-derived branch** (713 derived/renewal markers), not the new-business subscription proration where this writer sits. **Renewal TermDefined lines have a separate PTC gap** (SC-3346/COLA-renewal domain) — not a regression (PTC was null before), not addressed here.
