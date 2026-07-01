# Amendment line totals = $0 — Interim RCA (2026-06-29, for Marc DeBrey demo)

## Symptom
Subject quote 0Q0WC000003FNXF0A4 "Amendment Quote" (CAD): single line Advanced Authentication Modes Qty2,
ListPrice=4252.5 CAD correct, but UnitPrice/NetUnitPrice/NetTotalPrice/TotalLineAmount/TotalPrice = 0.

## Established facts (read-only verified)
- CLEAN TIME-BASED REGRESSION, not attribute/currency-specific.
  - Same products priced correctly thru Jun 23, net $0 from Jun 27 onward.
  - 5250 Integrator (no attrs): Jun23 amend Net 2021.25 -> Jun28 amend Net 0.
  - Additional Threat Assessment (Unit Type attr): Jun23 amend Net 10000 -> Jun27 amend Net 0.
  - Amend lines WITH and WITHOUT price-impacting attributes both affected.
- NEW SALE unaffected (Jun24-28 new sales price correctly, incl same products+attrs).
- Even UnitPrice=0 => failure is EARLY (base price never established for amend lines).

## Root cause (high confidence)
Active pricing procedure = "Revenue Management Default Pricing Procedure" **V20** (id 9QLWC0000015cDl4AI),
IsActive=true, last modified TODAY 16:32 (5 min before the demo quote at 16:37).
- V16 (active this morning per derived_pricing_demo README) is now INACTIVE.
- Version trail: V17(Jun23) -> V18/V19 "Cancelled Line item prehook wired" (Jun27) -> V20 "USD pricing with
  end-of-line currency conversion" (active).
- Jun 27 (V18 cancel-prehook wiring) == exact day amendments started returning $0.

### What V20 added over V16 (step diff)
ADDED: 4 Currency Conversion steps (NetUnitPrice/UnitPriceDisplay/NetTotalSubtotal/TotalLineAmount, seq35-38,
  hardcoded FX: CAD x1.3889, USD x1.0 ...), + 6 Attribute Value Pricing bridge steps.
REMOVED: ListOperationTermDefinedPTC, ProrationTermDefined, TermDefinedProrationFilterLinelevel.

### Mechanism
- Currency conversion steps only MULTIPLY (USD x1.0) -> they pass 0 through, they don't create it.
  => zeroing is UPSTREAM, in V20's new USD base/net derivation for amend lines.
- Pricing steps are gated on ItemPricingSource NotEquals 'LastTransaction' and ItemSalesTransactionAction='Amend'.
  Amend lines exit the waterfall with no base established => UnitPrice/NetUnitPrice = 0; conversion keeps 0.
- Under the SAME active proc, New Sale path produces correct net; Amend path produces 0. Confirmed by data.

### Important operational warning
The "working" Jun16/23 amends keep correct values only because they were priced under the OLD version and have
NOT been repriced. Re-pricing ANY amend under V20 will likely zero it. DO NOT reprice the good demo quotes.

## Fix options (NONE executed — UAT writes need explicit authorization)
1. Activate last-known-good version (V16 or V17) -> restores amend pricing fast (UI activation).
   Risk: loses V20 multi-currency (SC-3384) + cancel-line (SC-3441) features; verify other demos.
2. Surgically fix V20's amend base-derivation/LastTransaction path -> correct but riskier in <2h.
3. Demo workaround: demo amendments using a pre-Jun27 amend quote, or demo a New Sale (unaffected).

## Verification (after a fix, needs auth)
Reprice subject quote 0Q0WC000003FNXF0A4; expect AA Qty2 net ~ list-based non-zero (CAD).

## PROOF IT IS NOT A DATA ISSUE (read-only, empirical) — added after pushback
The amend line inherits its net from the source Asset's AssetActionSource snapshot. That seed is HEALTHY:
  Asset                         AssetActionSource.NetUnitPrice   Resulting QLI net
  5250 Integrator (Jun23, V16)  2021.25                          2021.25  (= seed, CORRECT)
  Adv Auth Modes (subject, V20) 5906.30 CAD                      0        (seed thrown away, WRONG)
=> The asset data / seed is pristine (5906.30 present). The PRICING RUN received a valid seed and output 0.
=> Under V16 the amend line inherited the seed exactly; under active V20 it does not. This is a pricing-procedure
   regression, NOT a data/records problem.
Mechanism nuance: PricingSetting (the Apex 'Get' that hydrates NetUnitPrice from the pricing context/store) is
BYTE-IDENTICAL in V16 and V20, and no V20-added step can turn nonzero into 0 (currency conv only multiplies).
=> The seed-carry broke at V20 republish/activation (context/waterfall-store desync for amend lines), not via a
   changed formula step. Consistent with this org's known "republish live proc w/o context resync -> silent zero".
Confidence: HIGH that it is the active proc (not data); MEDIUM on V16-reactivation being a clean fix vs a context
resync of V20. Decisive confirmation = reprice subject 0Q0WC000003FNXF0A4 under V16 -> expect net ~5906.30 (reversible).
