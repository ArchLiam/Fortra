# SC-3522 Validation Runbook: How to Validate Asset State Period Behavior

**Org:** FortraUAT (00DWC000006eUFF2A2). **All queries below are read-only.** Alias assumed `FortraUAT` (`sf org list` to confirm). Replace 15-char short IDs with 18-char IDs as needed (short IDs used here are the 18-char middle segment, e.g. `08LXfZYAW` → `02iWC000008LXfZYAW`).

---

## Executive Summary

This runbook makes SC-3506's validation **executable**. It provides (A) inventory queries to census AssetAction by Type/CategoryEnum and dump AssetStatePeriod per asset; (B) a manual test procedure for amendment / renewal / cancellation with exact assertions; (C) a pass/fail checklist per scenario; (D) regression queries for the four confirmed anomalies (2039 end-date, mrr=0 renewals, null EndDate, renew-then-cancel). Run Section A first to reproduce the population baseline, then Sections B–C to generate and assert new lifecycle events, then Section D as a standing regression gate.

**Golden reference values (verified 2026-07-01):** AssetStatePeriod=430,642; AssetAction=430,646; Change/Renewals=5; Change/Upsells=10; Cancel/Cancellations=1; 16 live-lifecycle actions total.

---

## Section A — Read-Only Inventory Queries

**A1. Census AssetAction by Type/CategoryEnum (baseline population):**
```
sf data query --query "SELECT Type, CategoryEnum, COUNT(Id) c FROM AssetAction GROUP BY Type, CategoryEnum ORDER BY COUNT(Id) DESC" -o FortraUAT
```
Assert: Generate/Initial Sale ≈430,630; Change/Upsells=10; Change/Renewals=5; Cancel/Cancellations=1.

**A2. Amendment-subtype breadth (coverage gate):**
```
sf data query --query "SELECT Subtype, COUNT(Id) c FROM AssetAction GROUP BY Subtype" -o FortraUAT
sf data query --query "SELECT CategoryEnum, COUNT(Id) c FROM AssetAction GROUP BY CategoryEnum" -o FortraUAT
```
Today returns only Initial Sale/Upsells/Renewals/Cancellations and Subtype {null, FieldAmendment=1}. Any new test must add Downsells/Cross-Sells/Upgrades/Downgrades/Swaps/T&C rows here.

**A3. Enumerate all live-lifecycle actions (the 16 non-migration rows):**
```
sf data query --query "SELECT AssetActionNumber, Type, CategoryEnum, Subtype, AssetId, QuantityChange, MrrChange, TotalQuantity, CreatedDate FROM AssetAction WHERE Type != 'Generate' ORDER BY CreatedDate" -o FortraUAT
```

**A4. Inspect AssetStatePeriod rows for a given asset (ALWAYS order by StartDate, never CreatedDate):**
```
sf data query --query "SELECT AssetStatePeriodNumber, StartDate, EndDate, Quantity, Mrr, SegmentType, UnitPriceUplift, PriceRevisionPolicyId, CreatedDate FROM AssetStatePeriod WHERE AssetId='02iWC000008LXfZYAW' ORDER BY StartDate ASC" -o FortraUAT
```

**A5. Asset header vs periods (rollup sync check):**
```
sf data query --query "SELECT Id, Status, Quantity, CurrentQuantity, CurrentMrr, CurrentAmount, LifecycleStartDate, LifecycleEndDate, PricingSource FROM Asset WHERE Id='02iWC000008LXfZYAW'" -o FortraUAT
```

**A6. Source-line provenance (was the $0 / bad term already on the order line?):**
```
sf data query --query "SELECT AssetActionSourceNumber, PricingTermCount, StartDate, EndDate, Quantity, ReferenceEntityItemId FROM AssetActionSource WHERE AssetAction.AssetId='02iWC000006tCOTYA2' ORDER BY CreatedDate" -o FortraUAT
```

**A7. Native uplift usage (should be zero in this org):**
```
sf data query --query "SELECT COUNT(Id) FROM PriceRevisionPolicy" -o FortraUAT
sf data query --query "SELECT COUNT(Id) FROM AssetStatePeriod WHERE UnitPriceUplift != null" -o FortraUAT
sf data query --query "SELECT COUNT(Id) FROM AssetStatePeriod WHERE PriceRevisionPolicyId != null" -o FortraUAT
```

---

## Section B — Manual Test Procedure per Scenario

> Setup for renewables: `scripts/apex/setupSC3502Lineage.apex` builds a renewable Contract+Asset; `scripts/apex/f04_initiateRenewal.apex` drives headless renewal via the `Fortra_Create_Renewal_Quote` flow. Amendments are driven from the Contract's **Managed Assets** action. (Executing these Apex scripts is a WRITE and requires fresh explicit UAT authorization — this runbook only prescribes it; do not run without ack.)

### B1. Amendment (Upsell / Downsell / etc.)
1. Open the asset's Contract → **Managed Assets** → amend the target line (e.g. quantity delta +N, or a Downsell −N, or a FieldAmendment). Set an **effective date strictly AFTER the asset's LifecycleStartDate** (to force a split; effective == start collapses to one period — an expected exception).
2. Activate the resulting amendment order.
3. Re-query A4 for the asset.

**Assert:** prior period EndDate = amendment effective date boundary; **new period** StartDate = next boundary, Quantity = new total, Mrr updated; periods tile contiguously (prior EndDate `...23:59:59` → next `...00:00:00`), **no overlap**. A new AssetAction Change/<Category> exists with the delta quantity.

### B2. Renewal
1. Run the renewal path (`f04_initiateRenewal.apex` / `Fortra_Create_Renewal_Quote`) against a termed asset; verify the renewal quote/order line's `NetUnitPrice` and `PricingTermCount` **before** activation.
2. Activate the renewal order.
3. Re-query A4 + A6.

**Assert:** a **new forward-dated** period exists; StartDate = prior EndDate + 1 day; EndDate = StartDate + exactly the term (1 year for a 1-yr renewal — **NOT 12 years**); Quantity carried forward; **Mrr non-zero** and uplifted; prior period unchanged; AssetActionSource `PricingTermCount` reflects the intended term in the correct unit.

### B3. Cancellation
1. From **Managed Assets**, cancel the asset (full or partial qty decrement). Prefer a **clean, never-renewed** asset for the baseline and a **non-zero-priced** asset to exercise credit economics.
2. Activate the cancellation order.
3. Re-query A4 + A5 (+ `--all-rows`).

**Assert:** a new AssetAction Cancel/Cancellations with Δqty = −(current qty); **NO new AssetStatePeriod** created; Asset CurrentQuantity/CurrentMrr → 0; for a non-zero cancel, `MrrChange<0` and `TotalCancellationsAmount<0` (watch for the SC-3441 USD-0.00 defect).

---

## Section C — Pass/Fail Assertion Checklist

**Amendment**
- [ ] Prior period end-dated at effective date
- [ ] New period created with correct new Quantity/Mrr
- [ ] Periods contiguous, no overlap (verify by ordering on StartDate)
- [ ] Change AssetAction with correct delta + CategoryEnum/Subtype
- [ ] (Expected exception) effective==start → single period, no split → PASS not FAIL

**Renewal**
- [ ] New forward-dated period; StartDate = prior EndDate + 1 day
- [ ] EndDate = StartDate + intended term (reject any span > requested term, esp. multi-year)
- [ ] Mrr non-zero and matches upstream renewal price
- [ ] Prior period unchanged
- [ ] Asset.LifecycleEndDate = MAX(period EndDate) and equals the intended term end
- [ ] `UnitPriceUplift`/`PriceRevisionPolicyId` null is EXPECTED (uplift is upstream)

**Cancellation**
- [ ] Cancel/Cancellations AssetAction, Δqty negative
- [ ] NO new AssetStatePeriod (confirm with `--all-rows`)
- [ ] Asset CurrentQuantity=0, CurrentMrr=0
- [ ] Non-zero cancel: MrrChange<0, TotalCancellationsAmount<0
- [ ] Status stays Installed = EXPECTED native behavior (gate downstream on LifecycleEndDate/current-period, not Status)

---

## Section D — Regression Queries for Confirmed Anomalies

**D1. 2039 / multi-year renewal end-date (GAP-1).** Flags any renewal ASP whose span exceeds ~1.5 years, and cross-checks the source term:
```
sf data query --query "SELECT AssetStatePeriodNumber, AssetId, StartDate, EndDate, Quantity, Mrr FROM AssetStatePeriod WHERE AssetId='02iWC000006tCOTYA2' ORDER BY StartDate" -o FortraUAT
sf data query --query "SELECT AssetActionSourceNumber, PricingTermCount, StartDate, EndDate FROM AssetActionSource WHERE AssetAction.AssetId='02iWC000006tCOTYA2' AND AssetAction.CategoryEnum='Renewals'" -o FortraUAT
```
FAIL if any renewal source line has `PricingTermCount` > 1 for a 1-year term, or ASP EndDate year ≥ (StartDate year + 2). (Verified: PTC=12 → 2039.)

**D2. mrr=0 renewals (G4/GAP-2).** Any Renewals AssetAction that drives TotalMrr to 0 or an ASP renewal period with Mrr=0:
```
sf data query --query "SELECT AssetActionNumber, AssetId, MrrChange, TotalMrr FROM AssetAction WHERE CategoryEnum='Renewals' AND TotalMrr = 0" -o FortraUAT
```
FAIL if any row returns (excluding intentional $0 renewals). Verified hits: AA-000543549 (08FcLaYAK), AA-000543567 (08LXfZYAW).

**D3. null EndDate on non-OneTime assets (refined G1).** Do NOT flag OneTime lines. Flag null-EndDate periods on **term-capable** products only:
```
sf data query --query "SELECT AssetStatePeriodNumber, AssetId, StartDate, EndDate FROM AssetStatePeriod WHERE AssetId='02iWC000008DFvvYAG' ORDER BY StartDate" -o FortraUAT
sf data query --query "SELECT ProductSellingModel.SellingModelType FROM ProductSellingModelOption WHERE Product2Id='01tWC00000DD1bsYAD'" -o FortraUAT
```
PASS if the product is OneTime (null EndDate is correct — verified BoKS = OneTime). Only FAIL when SellingModelType is TermDefined/Evergreen-inconsistent.

**D4. Renew-then-cancel (G1-ROLLBACK).** Confirm only the original closed period survives and inspect recycle bin:
```
sf data query --query "SELECT AssetStatePeriodNumber, StartDate, EndDate, Quantity, Mrr, IsDeleted FROM AssetStatePeriod WHERE AssetId='02iWC000008ARwoYAG' ORDER BY StartDate" -o FortraUAT --all-rows
sf data query --query "SELECT AssetActionNumber, Type, CategoryEnum, QuantityChange, MrrChange, CreatedDate FROM AssetAction WHERE AssetId='02iWC000008ARwoYAG' ORDER BY CreatedDate" -o FortraUAT
```
Expect 1 period (ASP-000543404), no soft-deleted rows. To disambiguate hard-delete vs never-created, re-run this after a **controlled non-zero renewal→cancel** test.

**D5. Stale Asset rollups (G6/GAP-4).** Compare header to active-today period:
```
sf data query --query "SELECT Id, CurrentQuantity, CurrentMrr, Quantity FROM Asset WHERE Id='02iWC000008LXfZYAW'" -o FortraUAT
sf data query --query "SELECT AssetStatePeriodNumber, Quantity, Mrr FROM AssetStatePeriod WHERE AssetId='02iWC000008LXfZYAW' AND StartDate<=TODAY AND EndDate>=TODAY" -o FortraUAT
```
FAIL if Asset.CurrentQuantity/CurrentMrr ≠ the active-today period's Quantity/Mrr. Verified: header 0/0 vs active period q100/mrr162.5.

**D6. SegmentType consistency (G3/GAP-6).** Track the null/Yearly split (forward-looking):
```
sf data query --query "SELECT SegmentType, COUNT(Id) c FROM AssetStatePeriod GROUP BY SegmentType" -o FortraUAT
```
Not a hard FAIL (no consumer keys off SegmentType today); log the count to detect drift.
