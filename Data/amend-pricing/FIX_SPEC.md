# Amendment net=$0 — FIX SPEC (V22)

## Root cause (active V21)
Amend lines (ItemPricingSource='LastTransaction') pass ONLY ListContainer79; its FormulaBasedPricing does
ItemNetTotalPrice = NetUnitPrice * Qty but NEVER seeds NetUnitPrice. PricingSetting (native Get) returns
NetUnitPrice=0 for new amend QLIs, and every other net writer is gated NotEquals 'LastTransaction' => skipped.
Gross carries (UnitPrice/TotalLineAmount via InputUnitPrice lane) but NET stays 0. (Renewals work; amendments don't.)

## Fix (one step) — V22 = V21 + AmendNetSeedFromCarry
Inside ListContainer79 (gate ItemPricingSource Equals 'LastTransaction'), BEFORE the existing FormulaBasedPricing:
  name: AmendNetSeedFromCarry  (FormulaBasedPricing / BusinessKnowledgeModel, parent ListContainer79, seq 2)
  formula: IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )
  output:  NetUnitPrice
(existing FormulaBasedPricing bumped seq 2 -> 3)
Runs seq26 (after derived reset seq22, before CurrencyConversion seq35) so it also re-seeds derived/maintenance
amend lines. NetUnitPrice then tracks InputUnitPrice through the same CAD/USD conversion as UnitPrice => net=gross.

## Builder-equivalent (RLM Pricing Procedure builder)
Clone V21 -> V22. In the "List Container 79" group (filter ItemPricingSource = 'LastTransaction'), add a
Calculation step BEFORE "Formula Based Pricing": formula IF(NetUnitPrice > 0, NetUnitPrice, InputUnitPrice),
output NetUnitPrice. Save -> Activate (Setup > Pricing Procedures; NEVER "Reactivate All Dependencies").

## Verify
Force-reprice 0Q0WC000003FNXF0A4 -> expect AA Modes Qty2 (CAD): NetUnitPrice ~5906.30, NetTotalPrice ~11812.59,
TotalPrice ~11812.59 (UnitPrice/TotalLineAmount unchanged 5906.30/11812.59). Cross-check a USD amend.
Rollback: reactivate V21.
