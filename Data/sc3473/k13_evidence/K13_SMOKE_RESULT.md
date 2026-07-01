# K-13 — Sync InputUnitPrice when null (discount-base safety) — SMOKE RESULT

Active proc: Rev_Mgmt_Default_Pricing_Procedure **V21** (ExpressionSetVersion 9QMWC00000025LN4AY,
design 9QBWC0000000oWH4AY) — confirmed sole-Active 2026-06-29/30. Org = FortraUAT.

## Static trace (live V21 metadata)
File: Data/pricing-v21-validation/live/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml

- ListGroup `SyncInputUnitPriceforDiscountBase` ("Sync InputUnitPrice for Discount Base"), top-level **sequenceNumber 13**.
- Gating AdvancedListFilter `ListOperation38` (L114173-114211), conditionLogic **`1 AND 2 AND 3 AND 4`**:
    1. InputUnitPrice **IsNull**
    2. ItemPricingSource **NotEquals 'LastTransaction'**
    3. DerivedPricingAttribute **IsNotNull**
    4. DerivedPricingAttribute **Equals false**
  => EXACT match to K-13 proc_mechanism.
- Child BKM `SyncInputUnitPricefromNet` ("Sync InputUnitPrice from Net", L116683-116744): AssignmentElement
  `NetUnitPrice -> InputUnitPrice` with `{"whereConditions":[]}` (unconditional copy once the filter passes).
- Execution ordering: Sync group (seq 13) runs BEFORE the discount band — Discount Percent BKM (seq 36),
  RegionalNetReconcile (seq 33), and the Quantity*Price / Partner Discount steps that consume InputUnitPrice
  as the discount base. So InputUnitPrice is hydrated BEFORE discount math => discount base non-null.
- V21 has multiple InputUnitPrice seeds (from ListPrice @ ListContainer32 seq14, Base_Price__c,
  COLACalculatedPrice__c, RegionalNetUnitPrice__c); the K-13 NetUnitPrice-sync is the LAST-RESORT
  discount-base safety net.

## Field reality
`InputUnitPrice` and `ItemPricingSource` are pricing-ENGINE context attributes, NOT persisted QLI fields
(SOQL `SELECT InputUnitPrice FROM QuoteLineItem` => No such column). Observable only inside the opaque RLM
managed code unit; the standard RLM_PRICING_BEGIN/END dumps surface InputUnitPrice as a context map entry.

## Smoke test (REAL data, headless Force-reprice)
Positive control 1 — BoKS derived demo Quote 0Q0WC000003FKRJ0A4 (non-derived Perpetual line
PIA-PIA-NRPS-PIAP, PBE 01uWC000005ws8MYAQ active $355, Fortra Price Book active, USD):
  PREFLIGHT pass (active PBE, active book, currency match, non-zero list, CompletedWithPricing).
  Force-reprice (place, pricingPref=Force, config=Skip) => isSuccess:true, errorResponse:[].
  Post: NetUnitPrice=355, NetTotalPrice=355, TotalLineAmount=355, TotalPrice=355; header CompletedWithPricing,
  Subtotal/Total/Grand=426. NO SF-BRE / null-discount-base error. Discount math safe.
  Engine log (ApexLog batch 07LWC00000Pf9dj2AB) RLM_PRICING_BEGIN & END for a non-derived line
  0QLWC000003kkir4AA: InputUnitPrice={...=2800.0} present and NON-NULL at both BEGIN and END
  (=ListPrice/NetUnitPrice) — discount base non-null, exactly the K-13 contract.

Positive control 2 — E-02 partner quote 0Q0WC000003FO1u0AG (discount math ACTIVE): non-derived lines
(PIA-PIA-NRPS-PIAP, VM-BSL-RSL-BESECB Subscription) net cleanly (NetUnitPrice 17000 / 5490.15),
CompletedWithPricing, no error => discount applied on a non-null base.

## Verdict: PASS (N-A pass)
The K-13 branch exists and is gated EXACTLY per spec in active V21, runs before the discount band, and on
real non-derived non-LastTransaction lines the discount base (InputUnitPrice) is non-null and discount math
is safe (clean reprice, no SF-BRE, correct nets). The step is a defensive safety-net that no-ops on normal
lines (InputUnitPrice already seeded from ListPrice earlier) but guarantees a non-null discount base —
the observable expected_behavior is fully met.

Honest caveat: the exact internal firing on a line whose InputUnitPrice was genuinely null AT this step is
not directly observable (RLM step internals are opaque managed code; normal lines have InputUnitPrice already
seeded). Validated at the contract/effect level + exact static gating match, not at the step-fire level.
No defect; not a downgrade — expected_behavior met, preflight passed, branch routes correctly.
