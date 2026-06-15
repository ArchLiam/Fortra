# SC-3346 DATA-FIELD-POP — Resolution (2026-06-14, FortraUAT)

## Verdict: the carry-forward is functionally CORRECT for everything that drives pricing. The 3 "gaps" are each
## cosmetic, already-covered, or expected-historical → no in-scope defect. (One optional one-field completeness add.)

The build cohort is correct (retest-confirmed: renewal COLACalc exact; NB Base/SLP→71). The three retest "gaps":

## GAP2 (NB line SLP=null) = ZERO-LIST-PBE, already reclassified
The canonical NB line `0QLWC000003cFh44AE` SLP=null because it is on the **inactive Standard Price Book** with a
**non-derived PBE** → the Stamp_Source_List_Price flow's `Is_Derived_Line` gate skips it. This is the price-book /
wrong-book issue resolved under ZERO-LIST-PBE (restrict maintenance to the Fortra book). Not a DATA-FIELD-POP defect.

## GAP1 (legacy renewal lines with null Base/SLP/priors) = expected historical, not a defect
The retest's "44 of 50" is a tiny sample of a large historical set: **~498K** renewal-maintenance QLIs have null
Base/SLP — **overwhelmingly closed Won (362,790) / Approved (87,411)** quotes that predate the SC-3346 fields and the
stamp flow. These are historical lines that never had the new carry-forward fields — expected, not a defect. The
properly-created (post-V14) renewal lines DO carry the fields (canaries: Base 71, COLA% 7.85, COLACalc 67.38). Active
Drafts re-stamp on reprice when the source asset has data. No code fix; at most a one-time backfill if the business
wants historical lines populated (low value — they're closed).

## GAP3 (renewal OI missing SLP + COLA%) — cosmetic, not a mapper bug
- **SLP:** the OI `SLP=null` because the **source QLI's SLP is null** (`QuoteToOrderFieldMapper` copies SLP only when
  `sourceQLI.Source_List_Price__c != null`). Renewal pricing uses **Base**, not SLP — so a null SLP on a renewal line
  is correct, not a gap. Where the renewal QLI does carry SLP (Fortra-book derived), the OI gets it.
- **COLA%:** the renewal QLI carries `COLA_Uplift_Percent__c=7.85` but the mapper does **not** copy it to the OI
  (the only field it genuinely omits). **Cosmetic for in-scope pricing:** the renewal formula's
  `IF(COLACalculatedPrice__c>0, COLACalc, …)` branch uses **COLACalc** (the OI carries 67.38) on any order-side
  reprice — it never needs the OI's COLA%. Multi-year (which would re-derive COLA% from `COLA_Uplift_Rules__mdt`) is
  out of scope (RN-MULTIYEAR). So nothing in-scope consumes COLA% on the renewal OI today.

## Resolution
**Reclassify DATA-FIELD-POP from partial → effectively PASS for in-scope functionality.** The carry-forward correctly
populates the pricing-driving fields (Base, priors, COLACalc, COLA% on the QLI; SLP where applicable). The three gaps
are: GAP2 = ZERO-LIST-PBE (price-book, separately reclassified), GAP1 = expected historical, GAP3 = cosmetic.

### OPTIONAL one-field completeness add (defensive; not required for in-scope pricing)
If desired for Workday/reporting/future multi-year, copy `COLA_Uplift_Percent__c` (QLI→OI) on the renewal carry-forward
path in `QuoteToOrderFieldMapper` (a one-field addition next to the existing Base/priors/SLP copies). Clean Apex change,
no procedure/scale-cache risk, deploy with the existing SOLO test. Recommend only if a downstream consumer is identified;
otherwise leave as-is (the OI already carries the committed COLACalc/Net, which is what matters).
