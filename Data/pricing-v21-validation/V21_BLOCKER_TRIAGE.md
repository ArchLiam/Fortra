# V21 Blocker Triage — Live Re-Classification

Date: 2026-06-29
Active pricing procedure: V21 (skeleton seq referenced below). Triage classifies all 13 P0 blockers as **DATA** (config/data gap), **CODE** (real logic defect in proc/apex/flow/mule), **FIXTURE** (test-data artifact, not a product bug), or **MIXED** (both).

> Note: the synthesis input enumerated 9 distinct blocker IDs (D-01, E-03, K-02, G-03, G-02, F-07, F-04, F-02, K-04). The "13 P0 blockers" headline reflects 13 raw FAILs that collapse onto these 9 root causes after de-duplication; the table below is keyed by root-cause ID.

---

## 1. Classification Table

| id | category | DATA/CODE/FIXTURE/MIXED | layer | fix type | root cause (1 line) | evidence | confidence |
|------|----------|--------------------------|--------------|----------|---------------------|----------|------------|
| D-01 | CODE | CODE | proc | edit context metadata: change `Attribute_Multiplier_Pct__c` context binding | V21 Calculated-mode formula `InputUnitPrice = Base_Price__c * Attribute_Multiplier_Pct__c` mis-binds the multiplier attribute (step `AttributeValuePricingCalculatedMode17`) | live active V21 step formula | high |
| E-03 | CODE | CODE | proc | edit V21 OneTime net path: add a `NetUnitPrice <- ListPrice` seed | OneTime/Perpetual NET rail is never seeded from list for a non-derived, percent-only partner line → partner discount applies to a null/zero net | live active V21 OneTime net rail trace | high |
| G-02 | MIXED | MIXED | mixed (proc + data) | CLSAAS leg (CODE): add `CurrencyIsoCode` to `AttributeVolumePricing…`; data leg: backfill currency on records | Multi-currency attribute-volume pricing leg is currency-blind (CODE) and underlying records lack `CurrencyIsoCode` (DATA) | dual leg trace | high |
| G-03 | CODE | CODE | proc | edit proc formula: make the 4 Currency Conversion steps conditional / non-self-referential | V21's four "Currency Conversion" steps (skeleton seq 33-36) are unconditional self-referential in-place multiplies: `NetUnitPrice = NetUnitPrice * rate` re-applied every pass | live active V21 seq 33-36 | high |
| F-04 | CODE | CODE | flow | edit flow: add a Place Sales Transaction (`pricingPref=Force`) step | Flow path doesn't force a Place/reprice, so downstream net is stale on the affected transition | flow trace | high |
| F-07 | CODE | CODE | proc | edit proc: make order-context partner discount idempotent | Order-level Reprice-All on a Channel-Originated order compounds the 15% partner discount every pass (non-idempotent) | active proc Reprice-All order-context trace | high |
| K-04 | CODE | CODE | mule | edit MuleSoft DataWeave mapping: contract-line `extendedAmount` source | Workday Submit_Customer_Contract payload `extendedAmount` mapped wrong in Mule (no SF Apex/Flow/DR/proc touches it — org-wide force-app search clean) | Mule DataWeave + force-app negative search | high |
| K-02 | FIXTURE | FIXTURE | test-fixture | rebuild test record: add contributing PIA-PIA-NRPS-PIAP row | FAIL driven by incomplete test fixture — quote `0Q0WC000003FZ5N0AW` derived maintenance line missing its contributing PIA row, not a product defect | quote 0Q0WC000003FZ5N0AW inspection | high |
| F-02 | FIXTURE | FIXTURE | test-fixture | rebuild test record: born as Renewal-Maintenance (RRM) SKU correctly | FAIL quote `0Q0WC000003FR6D0AW` "renewal-maintenance" line is a mis-constructed test record, not a product defect | quote 0Q0WC000003FR6D0AW inspection | high |

---

## 2. Buckets

### REAL CODE DEFECTS (need a code/proc/flow/mule fix)
- **D-01** (proc) — Calculated-mode formula mis-binds `Attribute_Multiplier_Pct__c` in step `AttributeValuePricingCalculatedMode17`.
- **E-03** (proc) — OneTime/Perpetual NET rail never seeded from list price for non-derived percent-only partner lines.
- **G-03** (proc) — 4 Currency Conversion steps (seq 33-36) are unconditional self-referential multiplies that re-apply every reprice pass.
- **F-04** (flow) — flow missing a forced Place Sales Transaction (`pricingPref=Force`); net stays stale.
- **F-07** (proc) — order-context partner discount is non-idempotent; Reprice-All compounds the 15% each pass on Channel-Originated orders.
- **K-04** (mule) — MuleSoft DataWeave maps contract-line `extendedAmount` from the wrong source for the Workday Submit_Customer_Contract payload.

### DATA / CONFIG GAPS (backfill / config, no logic change)
- *(none pure-DATA)* — the only data component is inside G-02 (see MIXED).

### TEST-FIXTURE ARTIFACTS (never a real product bug)
- **K-02** — incomplete test fixture: derived maintenance line on quote `0Q0WC000003FZ5N0AW` missing its contributing PIA-PIA-NRPS-PIAP row.
- **F-02** — mis-constructed test record: renewal-maintenance line on quote `0Q0WC000003FR6D0AW` not born as a proper RRM SKU.

### MIXED (both code and data)
- **G-02** — CODE: `AttributeVolumePricing…` CLSAAS leg is currency-blind (add `CurrencyIsoCode`); DATA: backfill `CurrencyIsoCode` on the underlying records.

---

## 3. Counts & Implication

| class | count | ids |
|-------|-------|-----|
| REAL CODE DEFECTS | 6 | D-01, E-03, G-03, F-04, F-07, K-04 |
| MIXED (code + data) | 1 | G-02 |
| DATA / CONFIG only | 0 | — |
| TEST-FIXTURE artifacts | 2 | K-02, F-02 |
| **Total root causes** | **9** | |

**Implication:**
- **7 of 9 require code/proc/flow/mule work** — the 6 pure CODE defects plus the code leg of the 1 MIXED (G-02). These are genuine product bugs in the active V21 stack and Mule layer.
- **1 of 9 also needs a data backfill** (G-02's `CurrencyIsoCode` records) alongside its code fix.
- **0 are pure data/config gaps** — there is nothing here that a backfill alone resolves.
- **2 of 9 were never product bugs** (K-02, F-02) — they are broken test fixtures and should be removed from the P0 blocker list and fixed in the test data, not the product.

Net: the P0 backlog that actually gates V21 is **7 fixes across 4 layers** (proc ×4, flow ×1, mule ×1, plus G-02's proc+data), not 13.

---

## 4. Recommended Fix Order (real code defects only)

Ordered by blast radius / dependency (idempotency and seeding bugs first, since they corrupt net on every pass and poison downstream Workday payloads):

1. **F-07** (proc) — make order-context partner discount idempotent. Highest blast radius: every Reprice-All on Channel-Originated orders compounds 15%, corrupting net for all downstream consumers (incl. Workday). Fix first so other traces aren't contaminated.
2. **G-03** (proc) — gate the 4 Currency Conversion steps (seq 33-36) so they stop self-multiplying each pass. Same class of repeat-apply corruption as F-07, multi-currency scope.
3. **E-03** (proc) — seed `NetUnitPrice <- ListPrice` on the OneTime/Perpetual non-derived percent-only partner net rail, so the partner discount has a real base.
4. **D-01** (proc) — correct the Calculated-mode multiplier binding (`Attribute_Multiplier_Pct__c`) in `AttributeValuePricingCalculatedMode17`.
5. **G-02** (proc + data) — add `CurrencyIsoCode` to the CLSAAS `AttributeVolumePricing…` leg and backfill the records. Depends on the currency rails (G-03) being correct first.
6. **F-04** (flow) — add the forced Place Sales Transaction (`pricingPref=Force`) step. Do after proc fixes so the forced reprice exercises the corrected formulas.
7. **K-04** (mule) — fix the DataWeave `extendedAmount` mapping. Last, because it consumes SF net output — it must be re-validated only after the proc net rails (F-07/G-03/E-03/G-02) are correct, else you'd map a corrected source to a wrong target or vice versa.
