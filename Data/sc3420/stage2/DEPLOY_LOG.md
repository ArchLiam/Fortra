# SC-3420 — V14 in-place deploy log (2026-06-16)

## Deployed
- Rebased the TermDefined Proration insert onto **Marc's fresh live V14** (re-retrieved; Marc's +56-line
  edits were inside existing steps, no step add/remove; my insertion region unaffected; PTC writer still absent).
- Built modified V14 **in place** (versionNumber stays 14, status Active): added `TermDefinedProrationFilterLinelevel`
  (ListGroup, `SellingModelType='TermDefined'`) + `ListOperationTermDefinedPTC` condition + `ProrationTermDefined`
  writer (`ProrationMultiplier → PricingTermCount`); shifted 16 top-level steps seq ≥25 by +1.
- **Deploy: SUCCEEDED.** `sf project deploy start --metadata-dir --api-version 67.0` of the single
  `ExpressionSetDefinitionVersion` member. Deploy ID `0AfWC00000GMmb40AD`. (A single-version deploy modified the
  ACTIVE V14 in place WITHOUT the "deactivate active version" block — unlike a full-ExpressionSetDefinition deploy.
  No UI deactivate/reactivate needed, no offline window.)
- **Metadata verified live** (re-retrieve): V14 Active, 2 Proration steps, `ProrationTermDefined` +
  `ListOperationTermDefinedPTC` present, PricingTermCount refs 16→17.

## Functional verification — INCONCLUSIVE (PTC did NOT derive on API reprice)
- Force-repriced several Draft test quotes (configurationMethod=Skip AND full): all `isSuccess:true`,
  **PricingTermCount stayed null** on TermDefined lines. **No breakage** — reprice succeeds, NetUnitPrice
  preserved (246/266/766), OneTime lines still get PTC=0.
- **Root cause of non-derivation (from FINEST log of the reprice):** the proration's required INPUTS are not
  hydrated in the API reprice context:
  - `EffectiveTo` / `itemTransientEndDate` (the end-date transient) = **null** for the test lines — even though
    the QLI has EndDate. The surviving **Evergreen** proration depends on the SAME transient (its filter requires
    `itemTransientEndDate IsNotNull`), so this is a pre-existing engine/context behavior, not specific to the new step.
  - `ItemSubscriptionTerm` (standard term) = **null** (test lines have QLI.SubscriptionTerm null).
  - `SellingModelType` context tag IS correctly `TermDefined` for healthy lines (so the new filter matches);
    `PricingTermUnit=Annual` and `EffectiveFrom` ARE hydrated. Only the end-date transient + standard-term are missing.
  - `itemTransientEndDate`/`EffectiveTo` are **context-hydrated inputs, not computed by any procedure step** —
    they are not produced by `PricingEffectiveDates` (which only sets PricingDate) nor any other step in V14.

## Interpretation
The single-step restore is metadata-correct (mirrors V11 + the documented Proration design) and deploys cleanly,
but it cannot be functionally confirmed via the available API path:
1. **The API Force-reprice does not hydrate the end-date transient** the proration needs — the proper hydration
   likely happens only on the full PlaceQuote save / UI reprice / convert path (which can't be driven here;
   RLM blocks Quote DML for fresh-line creation).
2. **Open risk:** Marc's V11→V12 rework removed a whole cluster of steps (incl. the TermDefined filter container's
   other children + SubscriptionPricing73/77/83 + RegionalNetReconcile…). One of those may have computed the
   end-date/term transients the proration consumes. If so, restoring ONLY the Proration step is **insufficient** —
   the supporting transient computation must also be restored/re-seamed onto Marc's reworked procedure.

## State left on the org
- The change IS live on V14 (Active). It is **additive, TermDefined-gated, and currently inert** (no PTC output
  because inputs are null) — verified not to alter prices.
- Definitive validation requires a **UI reprice / fresh-line save / convert** by German/Marc, OR a coordinated
  trace with Marc of what transient-computation the rework removed.

## Revert (if chosen)
Marc's clean pre-change V14 is preserved at
`Data/sc3420/live_retrieve2/unpackaged/expressionSetVersion/...V140.expressionSetVersion`.
Redeploy it (same api-67 single-version package) to restore Marc's exact state.
