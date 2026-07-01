# Portion 2 (Partner net + Currency idempotency) — SIGN-OFF

Date: 2026-06-30. Org: **FortraUAT** only (`liam.jeong.c@fortra.com.uat`; NOT the `uat`/5sInfusion alias).
Active proc: `Rev_Mgmt_Default_Pricing_Procedure` **V21**, version `9QBWC0000000oWH4AY`,
LastModified **2026-06-30T04:52:08Z**, **130 steps**, context `SalesTransactionContextExt_v2` v23.
Baseline (canonical, post-04:52): `Data/pricing-v21-validation/v21_fix_baseline/v21_active_tooling_FRESH.json`.

## Outcome: NO new Portion-2 metadata change required.
All three assigned defects are addressed in the live V21 as of the 04:52 integrator merge.
No deploy from Portion 2. (Deploy/DML stayed human-ack-gated throughout; user declined the verification reprice.)

## The 04:52 update = the integrator merged the FIX_DESIGN edits into live V21
7 new elements vs the prior 123-step snapshot, none of MY existing steps (106 / 87-88 / 33-36) edited:
- `OneTimeNetSeedPrePartner` + `OneTimeNetSeedFilter` + `OneTimeNetSeed` → **E-03 seed** (FIX_DESIGN).
- `ResetNetToPrePartnerBase` → **F-07 reset** (FIX_DESIGN). Child seq2 of `StampContributorBasePreDiscount`
  (P3's container 107), between `StampBaseFilter` (105) and `StampBase_PriceandPre_PartnerfromNet` (106).
- `ResetTotalServicesK09` / `ResetTotalSoftwareK09` / `ResetTotalSubscriptionK09` → **Portion 3's K-09**.

## Per-defect verdict (verified against the FRESH live V21 + persisted records)

### E-03 — One-Time/Perpetual partner net — **NOT A DEFECT (PASS) → no change**
- §2 validation matrix line 53 = **PASS** (named-script, real quote 00781439, Net=1706.8). The handoff
  premise came from the **stale §3a P0 list** ("verbatim findings retained" from the prior wave).
- Structural: `SubscriptionPricing89` (One-Time) and `SubscriptionPricing95` (TermDefined) are byte-identical,
  so "mirror the TermDefined branch" is a literal no-op. The net=0 FAIL is an upstream `PricingSetting`(seq1)
  hydration artifact on Apex-inserted fixture lines, not a procedure defect.
- A harmless guarded `OneTimeNetSeed` (`IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice)`) is now present; no harm.

### F-07 — Order Reprice-All partner non-idempotency — **REAL; already FIXED → signed off**
- Root (confirmed): step 106 seeded `Base_Price__c`/`Pre_Partner_Price__c` from the live (discounted)
  `NetUnitPrice`; step 88 re-discounted in place → geometric ×0.85/pass (301.75→256.49→218.01→…).
- Fix (live): `ResetNetToPrePartnerBase` resets `NetUnitPrice = IF(PDP>0, IF(Has_Attribute_Adjustment, NetUnitPrice, ListPrice), NetUnitPrice)`
  BEFORE the base stamp and BEFORE PartnerDiscount. For a plain partner line each pass resets to the immutable
  `ListPrice` (355) → ×0.85 = **301.75** = true fixed point.
- Confirmed on the persisted OrderItem `802WC00000OpoppYAB`: `NetUnitPrice=301.75`, `Base_Price__c=355`,
  `Pre_Partner_Price__c=355`, `ListPrice=355` (was `Base_Price__c=185.31` when broken). **Signed off on static
  proof + persisted state per user (no DML reprice run).**

### G-03 — EUR FX idempotency — **NOT A DEFECT (PASS) → no change**
- §2 validation matrix line 64 = **PASS** (real quote 00781568, single FX, ordering correct). The compounding
  capture in `rows_run1/G-03.json` was a **synthetic fixture** (NetUnitPrice=0, no UI partner seed) — same
  artifact class as E-02/E-03. The 4 `CurrencyConversion*` steps are unchanged; correct for plain-PBE lines.

## Bonus finding (logged, deferred per user)
- **G-01** (real-line FAIL, matrix line 62): step 36 `CurrencyConversionUnitPriceDisplay` double-applies FX
  *within one pass* (`UnitPrice = 1375.73 = 1471.995 × 0.9346`) because `InputUnitPrice` already holds the
  EUR-converted net by that step. This is the genuine in-lane currency defect (vs the non-defect G-03). Fix =
  source the display from a pre-conversion unit value or apply FX exactly once. **Left deferred per user.**

## Residual (OUT OF SCOPE per user — follow-up ticket)
- `ResetNetToPrePartnerBase` stabilizes only **plain partner** lines. **Attribute-partner** lines keep
  `NetUnitPrice` (no reset to a stable base → may still compound unless attribute pricing re-seeds each pass);
  **GSA-partner** lines reset to *full* `ListPrice` (may drop the GSA ×0.5). Confirm with an ack'd reprice on
  those line types before any hardening; tracked as a separate follow-up, not a Portion-2 deliverable.

## Process note
Handoff briefs (00_OVERVIEW + PORTION_1/2/3, written ~22:09–22:10) were built from the stale §3a P0 FAIL list,
not the authoritative §2 matrix where E-03 and G-03 had already flipped to PASS. Future portions: trust the §2
matrix (and a FRESH live retrieve) over the §3a "verbatim findings retained" block.
