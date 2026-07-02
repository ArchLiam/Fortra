# SC-3473 H2 (context-hydration-mapping-gap) — native-semantics lens REFUTATION

## Verdict: REFUTED (mechanism mislocated)

## Key read-only evidence
1. Active context = SalesTransactionContextExt_v2 (11OWC000002m21Z2AQ), active version v23 (11pWC000002TjF7YAK),
   versionNumber=23, isActive=true, startDate 2026-05-29; UNCHANGED since 2026-06-04 (per 3 prior dossiers).
   Retrieved live to EVID/verify/ctxdef/.
2. Quote-side node mappings COMPLETE: Quote->SalesTransaction, QuoteLineItem->SalesTransactionItem,
   QuoteLineItemAttribute->SalesTransactionItemAttribute, QuoteLineGroup->SalesTransactionGroup all present.
3. ZERO of 2165 contextAttributeMappings have an empty contextInputAttributeName.
   ZERO Quote-side objects lack hydration details. => No unmapped Quote-side attribute. (fails H2 confirm test)
4. Surviving lines (0QLWC000002ou4H4AQ / ...5t4AA, SEI TermDefined-Annual) are fully priced (net 20000),
   have valid PBE (01uWC000004dTDyYAM active non-derived), PSMO exists (0iOWC0000000RRM2A2). Null custom
   fields (Regional/Partner/COLA) are null-VALUE not unmapped-KEY; Map.get returns the key fine.
5. Signature mismatch: documented context-hydration NPE (Applikontech) = "Something went wrong while hydrating
   additional context fields: Cannot invoke ...DefaultContextRuntimeEntityAttribute.getTags() because ...Map.get
   is null". SC-3473 = bare Object.toString(), NO "hydrating context" preamble, NOT getTags(). Different locus.
6. Both in-org analogs (reprice_contextdef_error, v16_contextfetch) were ORDER-side, had DISTINCT messages
   ("Unable to fetch tags:[...]" / "couldn't fetch ... context definition"), and were caused by a Quote-mapped/
   Order-absent field. SC-3473 is QUOTE-side delete pricing through the FULLY-mapped Quote node => asymmetry n/a.
7. SC-3393's identical H2 was already REFUTED on this same v23 context for SalesTransactionItem node.
8. Specificity: failure is unique to MIXED OneTime+TermDefined-in-one-HW-group quote; survivor-node hydration
   is invariant to deleted-group composition, so a survivor hydration gap cannot explain the specificity.
