# SC-3420 — staged fix (candidate V16) — what changed

**Status:** CANDIDATE, **not deployed**. Built read-only off live-active **V14** (retrieved 2026-06-16).

> ⚠️ **DEPLOY DECISION (2026-06-16, Liam):** the fix will be applied **into V14 in place — NOT as V15/V16 —**
> **after Marc DeBrey finishes his active V14 work.** This V16 file is therefore a **reference candidate only**;
> it is built off the *current* V14 and will be **stale once Marc edits V14**. When Marc signals done:
> (1) re-retrieve his final live V14, (2) re-apply the TermDefined Proration insert onto it (rebase +
> recompute top-level sequence numbers), (3) apply into V14 (builder UI preferred), (4) validate.
> **Do not deploy this V16.** Holding until Marc is done.

Owner review + a separate deploy ack required before anything touches the org. The active procedure
is co-owned and churns daily — **re-retrieve live and rebase before deploying**, and coordinate with
Marc DeBrey / Nir Kailash / Ben Kozlowski so an in-flight republish doesn't clobber it.

## The change in one sentence
Re-add the one pricing-procedure step that was dropped in the V11→V12 rebuild: a **Proration**
element gated to **TermDefined** lines whose *Proration Multiplier* output is written to
**`PricingTermCount`** — restoring engine derivation of PTC for subscription quote lines.

## Exactly what was added to the procedure (3 new steps)
1. **`TermDefinedProrationFilterLinelevel`** — a `ListGroup` filter container (top-level
   `sequenceNumber = 25`), mirroring the existing `EvergreenanytimeprorationfilterLinelevel`.
2. **`ListOperationTermDefinedPTC`** — its `AdvancedListFilter` child: condition
   `SellingModelType Equals 'TermDefined'`.
3. **`ProrationTermDefined`** — `actionType=Proration`, `resultIncluded=true`, child seq 2.
   - inputs: `EffectiveFrom`, **`EffectiveTo`** (actual line EffectiveTo — *not* the Evergreen
     `itemTransientEndDate*), `ProrationPeriod=PricingTermUnit`, `SubscriptionTermUnit=PricingTermUnit`,
     `SubscriptionTerm=ItemSubscriptionTerm`, `SellingModelType`, `StartProrationPeriod*`,
     `AllowPartialProrationPeriods`.
   - **output: `ProrationMultiplier → PricingTermCount`** ← the field write that was missing.

## Ordering / mechanical notes
- The new filter sits at **seq 25**, the same tier as the Evergreen proration writer, so it runs
  **before** the subscription-pricing read of `PricingTermCount` (`ListContainer83`). To make room,
  every pre-existing **top-level** step with `sequenceNumber ≥ 25` was shifted **+1** (16 steps;
  Evergreen container 25→26, … ListContainer83 28→29). Relative order is preserved — only the new
  step slots in. Child steps reference parents by name, so they're unaffected.
- Header bumped: `versionNumber` 14 → **16**, `status` Active → **Draft** (V15 already exists as a
  draft, hence 16).
- Result `PricingTermCount` flows back to the QLI via the (already-correct) context mapping in
  `SalesTransactionContextExt_v2`.

## Why this is safe in scope
- TermDefined-only filter ⇒ **does not touch** Evergreen (constant/own proration) or OneTime
  (constant) PTC writers, nor any Derived-Maintenance / COLA steps added in V12.
- Returns the procedure to **Salesforce's documented design** (Trailhead: *map Proration Multiplier
  → PricingTermCount*). It is a restoration, not a new invention.

## Two ways to apply (owner's choice)
- **Preferred — Pricing Procedure builder UI** (lowest risk; auto-handles sequencing/IDs): on a new
  version off V14/V15, add a List Group filtered `SellingModelType = TermDefined`, drop a
  **Proration** element inside it, map inputs as above, and map **Proration Multiplier → PricingTermCount**.
  Activate, then Reprice a test line.
- **Alternative — metadata deploy** of this candidate: `deploy/` (package.xml +
  `expressionSetVersion/...V160`). Deploy as **Draft**, then **activate via the UI** (activation is
  UI-only). Validate before activating org-wide.

## Validation (UAT, owner-authorized) before sign-off
- Reprice a fresh TermDefined line (ACTIDB / BESTSU / SEG) → `PricingTermCount` auto-populates to
  **1.0** (1-yr annual), `CalculationStatus = CompletedWithPricing`, **no manual edit**.
- Survives a 2nd reprice; carries to the Order on convert (OrderItem PTC=1) **without** the SC-3411
  V6 backstop.
- Regression check: Evergreen + OneTime lines still get PTC; Derived-Maintenance/COLA outputs
  unchanged; ARR (= TotalLineAmount/PricingTermCount) correct on TermDefined lines.

## Files
- `Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V160.expressionSetVersion` — candidate (XML-validated, well-formed).
- `deploy/` — MDAPI package (package.xml + version + definition for reference).
- Built by `Data/sc3420/` evidence; root cause + spec in `*Jira/Task/sc3420 | …/README.md`.
