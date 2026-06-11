# SC-3390 Adversarial Verification — CANDIDATE: total-price-mode-net-channel-downstream-lag

Verdict: **REFUTED** (as the primary "click twice" lag mechanism).
Date: 2026-06-11. Read-only investigation against FortraUAT + retrieved metadata.

## Candidate claim (restated)
First reprice writes the new tier `Base_Price__c`/`Attribute_Multiplier_Pct__c` to context correctly,
but the downstream V12 consumer steps (AttributeValuePricingCalculatedMode33 / TotalPriceMode36 /
UnitPriceMode30 -> InputUnitPrice, then -> Net/Total) only propagate to NetUnitPrice/TotalPrice
"after another channel settles", converging on the second pass. Lag = procedure-step consumption
ordering, NOT volume-snapshot timing.

## REFUTING EVIDENCE

### R1 — Consumer steps are UNCHANGED V11 -> V12 (kills the "V12 regression" framing)
Retrieved live V12 (ACTIVE) and V11 (Inactive, prior). Byte-normalized block compare:
  AttributeValuePricingCalculatedMode33  UNCHANGED (1656 chars both)
  AttributeValuePricingTotalPriceMode36  UNCHANGED (1778)
  AttributeValuePricingUnitPriceMode30   UNCHANGED (1776)
  AttributeBasedPrice                    UNCHANGED (4129)  (InputUnitPrice -> NetUnitPrice/ItemNetTotalPrice)
  QuantityPrice57                        UNCHANGED (1756)
  SubscriptionPricing / 73               UNCHANGED
  ListContainer5/6/7 (mode containers)   UNCHANGED (seq 13/14/15)
  AttributeValuePricingCalculatedMode / TotalPriceMode / UnitPriceMode (filters)  UNCHANGED
V11->V12 actual diff is ENTIRELY in Derived/Renewal/Partner/COLA:
  CHANGED: AdjustmentType, DerivedPricing, PartnerDiscount, section-0-input1
  ADDED:   DerivedProductsNonRenewalFilter, ListContainerDerivedNative,
           ListContainerDerivedPartner, PartnerDiscountDerivedMaintFilter
  + DerivedPricingNewBusiness/Renewals formulas gained COLACalculatedPrice__c handling.
=> The consumer chain the candidate accuses is identical in V11. A V12-specific net-channel
   regression in these steps does not exist. The candidate's own REFUTE signature is met:
   "a V11-vs-V12 diff showing the consumer steps are unchanged and already propagate net in one pass."
   Files: Data/sc3390/evidence/retrieve-v11/...V110...  vs  Data/sc3390/retrieve/...V120...

### R2 — The chain is single-pass synchronous; there is no "channel to settle"
V12 lines 1073-1302: the three mode steps read context `Base_Price__c`/`Attribute_Multiplier_Pct__c`
and write `InputUnitPrice` in-pass (Calculated: `Base_Price__c * Attribute_Multiplier_Pct__c`;
Total/Unit: `Base_Price__c`). V12 lines 700-797: AttributeBasedPrice consumes `InputUnitPrice` and
emits `NetUnitPrice` (out) + `ItemNetTotalPrice` (Subtotal out) in the SAME procedure execution.
ExpressionSet/CalculationProcedure runs as ONE synchronous DAG pass per price-contexts call;
no async boundary, no persisted-register handoff between clicks. `NetUnitPrice` self-references are
all `QuoteTypeText__c='Renewal'`-gated (V12 1855/1920/1985/2071) and operate on the in-pass
register, not a prior-run persisted value. => identical context in -> identical Net out, every pass.

### R3 — Symptom shape contradicts the borrowed sc3384 surface
The candidate leans on sc3384's "Total-Price-mode Net=0" surface. But per
`02_ROOT_CAUSE_AND_FIX_SPEC.md` lines 87-88, 164, 202 that surface is a PERSISTENT, currency-
INDEPENDENT Net=0 that does NOT converge ("not traced to the exact element", treated as a separate
sub-fix). SC-3390's symptom is the OPPOSITE: click 1 shows a valid OLD tier price (not 0), click 2
shows the correct NEW tier price — it CONVERGES. A deterministic downstream step over an unchanged
context cannot produce "old then new" across two clicks; convergence requires the INPUT (Base_Price
/ the volume snapshot) to differ between click 1 and click 2 => points upstream (snapshot timing),
not downstream consumption.

### R4 — No first-click log evidence supports the CONFIRM signature
The CONFIRM signature requires a first-click log with prehook MATCH at the NEW tier + correct
Base_Price__c written, yet Net/Total stale. NONE of the 6 captured prehook ApexLogs contain a tier
MATCH: all hit the early return `earlyReturnMessage = 'No eligible line items
(Has_Attribute_Adjustment__c = true)'` (cls:200-203), processedCount=0 (e.g. log-place-04-34-13
lines 7365-8306 -> 901/923/926/930). The candidate's own Area-5 open question concedes this trace
was never performed. So the CONFIRM evidence does not exist; the claim is unproven by logs AND
structurally contradicted by R1/R2/R3.

## What this does NOT refute
This refutes the DOWNSTREAM-consumption-lag mechanism. It is consistent with — and actually
reinforces — the UPSTREAM snapshot-timing hypothesis (candidate #1): because the consumer chain is
deterministic and version-stable, the only way to get "old price then new price on identical
procedure code" is for the pricing CONTEXT (Attribute_Volume / the Base_Price the prehook derives
from it) to differ between click 1 and click 2 — i.e., the freshly-typed Unit Quantity attribute is
not yet flushed into the context snapshot the FIRST price-contexts call assembles.

## Residual uncertainty
- BKM step internals were compared by normalized-block byte length+content equality, not a
  field-by-field semantic diff; equal length+content is strong but a same-length compensating edit
  is theoretically possible (low risk; the diff -w of the whole file localizes all changes to the
  Derived/Renewal area).
- No live first-click-vs-second-click debug log with an ACTUAL tier MATCH was available (would
  require a controlled repro = DML/editing a quote = requires authorization). The refutation rests
  on metadata determinism + symptom-shape logic, not a captured converging trace.
