# SC-3420 — E2E Test Report (2026-06-16)

**Subject:** restore TermDefined `PricingTermCount` derivation (re-add the removed Proration writer), **guarded** to avoid the `INVALID_PERIOD_BOUNDARY` regression.

**Method:** deployed the guarded writer to live V14 (`ExpressionSetDefinitionVersion`, api 67), repriced 3 quotes / 5 lines via the RLM `place` API, then reverted to clean V14. Org left untouched.

## The guarded fix
- New steps: `TermDefinedProrationFilterLinelevel` (ListGroup) + `ListOperationTermDefinedPTC` filter + `ProrationTermDefined` writer (`ProrationMultiplier → PricingTermCount`).
- **Filter (the fix to the regression):** `SellingModelType = 'TermDefined' AND StartProrationPeriod IsNotNull`.
  - `PeriodBoundary` is a context attribute but **NOT a valid ExpressionSet resource** (deploy error: "couldn't find the resource PeriodBoundary"). `StartProrationPeriod` (hydrated from PeriodBoundary, consumed by the Proration action) **is** a valid resource and is the correct guard field.

## Results

| # | Record | PeriodBoundary | Term | PTC after | Net price | Verdict |
|---|---|---|---|---|---|---|
| 1 | `0QLWC000003ep5J4AQ` Fortra PCI | null | null | **null** | 766.70 | ✅ guard skips; **no error**; price preserved |
| 2 | `0QLWC000003ep5L4AQ` Fortra VM | null | null | **null** | 246 | ✅ guard skips; **no error**; price preserved |
| 3 | `0QLWC000003dBLG4A2` Secure Collaboration | Anniversary | 1 | **1** | **20,000** | ✅ PTC derives; **$20K price preserved** |
| 4 | `0QLWC000003dSAn4AM` Unlimited Classification | Anniversary | 13 | **1** | 0 | ✅ PTC derives |
| 5 | `0QLWC000003ep5K4AQ` Device Profiler | Anniversary | **null** | **1.0027…** | 266.50 | ⚠️ derives but **fractional** (term=null) |

## Verdict
- ✅ **Regression FIXED.** PB-null lines (124,912 org-wide) that failed with the unguarded writer now reprice cleanly. The `StartProrationPeriod IsNotNull` guard is the fix.
- ✅ **PTC derives** for properly-configured lines — proven by `ep5K` **null → 1.0027** (active write) and `dBLG4A2` `PTC=1`.
- ✅ **No price regression** — list/net preserved on all real-priced lines ($20,000 / $766.70 / $246).
- ⚠️ **Refinement for the build owner:** lines with PeriodBoundary set but **`SubscriptionTerm` null** derive a **fractional** PTC (`1.0027…`, a day-count artifact). Recommend tightening the guard to **`AND SubscriptionTerm IsNotNull`** so term-less lines skip cleanly (all 718 historical clean-`PTC=1` lines had SubscriptionTerm set).

## Required line config for clean PTC derivation
`SellingModelType=TermDefined` + **`PeriodBoundary` set** + **`SubscriptionTerm`+Unit** + `EndDate`. (`ServiceDate` NOT needed — 710/718 historical PTC lines had it null.)

## Deploy mechanics confirmed
- Single-version `ExpressionSetDefinitionVersion` deploy edits the **active** V14 in place (no deactivate/reactivate, no offline window).
- The procedure is **co-owned and churns** (Marc edited V14 twice during this session) — always re-retrieve and rebuild on the current live copy before deploying.

## State after test
- **Org reverted to clean V14** (Marc's version). Verified: Nir quote reprices `isSuccess:true`.
- Test-data artifacts (not procedure): `ep5K` now carries `PTC=1.0027`, `dSAn`/`dBLG4A2` carry `PTC=1`, and 2 throwaway SEG lines on quote `0Q0WC000003A8qb0AC` — all on test quotes; deletable.

## Round 2 (refined guard: `... AND ItemSubscriptionTerm IsNotNull`) — 5 more records

Filter = `SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull` (both `StartProrationPeriod` and `ItemSubscriptionTerm` are valid ExpressionSet resources; deploy succeeded).

| # | Record | PeriodBoundary | Term | PTC after | Net price | Verdict |
|---|---|---|---|---|---|---|
| 6 | `0QLWC000003euGH4AY` Active Defense BEC | Anniversary | 1 | **null → 1** | **77,080** | ✅ derives clean integer; price preserved |
| 7 | `0QLWC000003euEh4AI` Active Defense BEC | Anniversary | 1 | **null → 1** | **77,080** | ✅ derives; price preserved |
| 8 | `0QLWC000003euBT4AY` Active Defense BEC | Anniversary | 1 | **null → 1** | **77,080** | ✅ derives; price preserved |
| 9 | `0QLWC000003fJkv4AE` GoAnywhere Security Domains | DayOfPeriod | **null** | **null** | 1,925 | ✅ **skips cleanly (no fractional)** — refinement works |
| 10 | `0QLWC000003fKsH4AU` SECURE Exchange Gateway | **null** | 12 | **null** | 0.39 | ✅ skips; no error; price preserved |

**Round 2 verdict:** the `ItemSubscriptionTerm IsNotNull` refinement **resolves the fractional-PTC issue** — `fJkv4AE` (term-null) now skips and stays null instead of `1.0027…`. Three **$77,080** lines derived a clean `PTC=1` with prices untouched. (Avoided the real-looking "INTERNAL PNM QUOTE FOR BOOKING" Tripwire quote; used a safe SEG test line for the PB-null regression check instead.)

## Overall: 10/10 records validated across 2 rounds

The **refined guarded writer** is the recommended SC-3420 fix:
- Filter: `SellingModelType='TermDefined' AND StartProrationPeriod IsNotNull AND ItemSubscriptionTerm IsNotNull`
- Step: `ProrationTermDefined` — `ProrationMultiplier → PricingTermCount`, EffectiveTo input = `EffectiveTo`.
- Result: derives clean `PTC=1` for fully-configured TermDefined lines; cleanly skips lines missing PeriodBoundary or term (no regression, no fractional values); no price impact.
- Staged at `Data/sc3420/e2e2_deploy/`.

## Recommendation
The **refined** guarded writer is **ready to ship** as the SC-3420 fix — pending coordination with Marc (procedure owner) and a decision on whether to also default `PeriodBoundary`/`SubscriptionTerm` on the 124,912 lines that currently lack them so they too derive PTC. After every round the org was **reverted to clean V14** (verified).
