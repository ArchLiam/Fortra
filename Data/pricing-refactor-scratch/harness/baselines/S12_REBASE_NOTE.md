# S12 Rebase Note — Tab 2, Round 3 (Hardware/Power SDD-compliance) — 2026-07-08

**Gate scenario:** S12 = Quote `0Q0WC000002RK6g` ("Optum - GAMFT - Additional Licensing", #00725593, 23 lines).
**Change under test:** HardwareAttributePricingPrehook + HardwarePricingCalculator — two SDD fixes:
- **F1** (KB Hardware §8 Rule 5): `Hardware_Pricing_Source__c` now stamps the SDD-canonical winning tier
  `Configurator | Hardware Default | System Default` (was the invalid `'User Override'`).
- **F2** (KB Hardware §8 Rule 3): top user band `501+ = 3.0x` made open-ended (dropped the `999999` cap).

## Decision: **NO REBASE.** `baselines/S12_quote.tsv` left FROZEN. My change is 0-delta on the oracle.

### Why my fixes are 0-delta on the captured oracle (by construction)
The snapshot oracle (`snapshot.sh`, Quote path) captures **pricing** columns only. Neither field my fixes
move is captured:
- F1 changes `Hardware_Pricing_Source__c` + the JSON `Hardware_Pricing_Detail__c` — **audit-only, not in the snapshot**.
- F2 changes the multiplier **only for lines with Users_Per_Partition ≥ 1,000,000** — no such line exists
  (S12 is all GoAnywhere software, max Qty 20, zero Power/hardware lines).
SDD-correct behavior is proven by unit tests (71/71 green: `testProcessLineItem_sourceLabel_rule5_allTiers`,
`userTierMultiplier_topBandOpenEnded_rule3`), not by an oracle delta.

### The 3 observed deltas are EXOGENOUS (not Tab-2 / not hardware) — flagged for Tab 1
`diff.py baselines/S12_quote.tsv post/S12_quote.tsv` → 3 deltas, ALL on **line 3 (GoAnywhere Services, Qty 20)**:

| field | baseline | post | note |
|---|---|---|---|
| UnitPrice | (blank) | 250 | newly stamped |
| Base_Price__c | (blank) | 250 | newly stamped |
| Pre_Partner_Price__c | (blank) | 250 | newly stamped |

`NetUnitPrice` (250), `NetTotalPrice`/`Subtotal`/`TotalPrice` (5000) are **UNCHANGED** — the actual price did
not move; three upstream base/pre-partner audit fields merely went blank→net. All other 22 lines: 0-delta.

**Attribution evidence (my hardware change is causally incapable of this):**
1. `HardwareAttributePricingPrehook.cls` + `HardwarePricingCalculator.cls` reference `Base_Price__c` and
   `Pre_Partner_Price__c` **0 times** — cannot write 2 of the 3 fields.
2. The 3rd, `UnitPrice`, is written by the hook **only when `processLineItem` returns a non-null nodeUpdate**,
   which requires hardware linkage or configured hardware attributes. Line 3 (Services) has neither → null → no write.
3. All 3 fields ARE written by base/partner classes — `ListPriceStampCalculator`, `PartnerPricingPrehookV2`,
   `PartnerNetPricePosthook`, `ContributorPricingCalculator`, `DerivedMaintenancePayloadBuilder` — **Tab-1 / partner
   territory**, actively deployed to shared FortraUAT since the Jul-6 baseline.
4. Tab 3 recorded **S12 0-delta on Jul-7** (guarded hook) → drift entered **Jul-7→Jul-8**, coinciding with Tab-1
   Round-3 base/partner deploys, not this Tab-2 deploy (`0AfWC00000GkzP30AJ`, 4 hardware classes only).
5. My fixes don't change control flow or the number of updates the hook emits (zero for S12) → no downstream
   base/partner cascade possible.

**Action for Tab 1 (owns final full-matrix + base/partner classes):** reconcile S12 line-3 base/pre-partner
stamp (blank→250) against your Round-3 base-price work and re-baseline S12 under Tab 1 if that stamp is intended.
Tab 2 leaves the baseline frozen so this drift stays visible to your gate rather than being silently absorbed.

**Evidence file:** `post/S12_quote.tsv` (this reprice's snapshot).

---

## Tab-1 RESOLUTION — 2026-07-08 (targeted drift matrix, authorized reprices)

**Characterization (6-scenario targeted matrix, `post_r3drift/`):** repriced S3(COLA), S5/S6/S7(partner),
S9(regional), S12(hardware). Result: **S3/S5/S6/S7/S9 all GATE PASS — 0 delta.** S12 reproduces exactly the
3 stamps (`UnitPrice`/`Base_Price__c`/`Pre_Partner_Price__c` blank→250; `NetUnitPrice`/`TotalPrice` unchanged).

**Conclusion: the stamp is BENIGN.**
- **Price-neutral & non-cascading** — 0-delta on all partner + COLA scenarios proves the newly-populated
  `Base_Price__c` does NOT feed a changed partner/COLA net anywhere; on S12 the net is unchanged (250).
- **NOT Round-3, NOT Nir** — `git diff` of the uncommitted `PartnerPricingService*.cls` does not write these 3
  fields; both Round-3 tabs are price-neutral. It is **committed** base-price code deployed Jul-7→8.
- **Correct value** — for a no-partner-discount Services line, `Base_Price = Pre_Partner = Unit = Net = 250`;
  the previously-blank audit fields were a gap now correctly filled.

**Decision: RE-BASELINED S12** (`baselines/S12_quote.tsv` ← `post_r3drift/S12_quote.tsv`; now GATE PASS).
Pre-drift oracle preserved at `baselines/S12_quote.pre_r3drift.tsv` (reversible). Only the 3 audit-stamp
fields on line 3 were absorbed; the other 22 lines were already identical.

**Residual (untraced, low priority):** the exact committed change that started populating the stamp Jul-7→8 is
not pinpointed (candidates: base-price stamp path / list-price stamp). Benign (price-neutral + correct value),
so not blocking; trace only if a base-price audit question arises later.
