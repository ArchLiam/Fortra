# K-16 Delete-group / sparse-context robustness — smoke test result (2026-06-29, FortraUAT, V21)

## Assertion
Procedure execution within a quote-group delete / sparse context must null-safe its filters and
NOT NPE on a missing context node. The native RLM "Delete Group" Map.get NPE is platform-side, not proc-side.

## Active proc confirmed
Rev_Mgmt_Default_Pricing_Procedure V21 = 9QBWC0000000oWH4AY (single Active). Null-safe steps present:
 - AllLinesNullSafeFilter  (AdvancedListFilter: LineItemQuantity >= 0)
 - NullCheckforLineAdjustment / NullSafeLineAdjustment (BKM + Formula: IF(ISNULL(ItemTotalAdjustmentAmount),0,...))
   30 occurrences of the null-coalesce formula across list containers.

## Test 1 — PROCEDURE reprice on the canonical sparse/grouped SC-3473 repro 0Q0WC000002U2020AC
Force place reprice -> isSuccess:true, errorResponse:[] -> CompletedWithPricing.
All 4 lines priced (survivors 20000 ea; grouped 29060/4356). Abstract TermDefined line PTC=1, EndDate=2027-06-25.
=> Procedure is null-safe; NO proc-side NPE. PASS for the proc-side assertion.

## Test 2 — native DeleteGroup on a faithful clone (0Q0WC000003FbQX0A0; group 1C9WC00000098rB0AQ)
DeleteGroup graph (method:DELETE action:DeleteGroup, pricingPref:Force):
 -> errorResponse INVALID_API_INPUT "Cannot invoke Object.toString() because the return value of
    java.util.Map.get(Object) is null", referenceId=refQuote. isSuccess:false.
 == EXACT SC-3473 signature reproduced.

## Test 3 — discriminator: clean control (0Q0WC000003FbS90AK), all-OneTime, NO TermDefined / NO null-term
 - Plain Force reprice -> isSuccess:true (proc null-safe).
 - DeleteGroup -> SAME Map.get NPE (isSuccess:false). After failure: CalculationStatus=SaveFailedOrIncomplete,
   group still present, both lines intact (matches live toast "your quote was not updated").
 - Ungroup (delete group, KEEP lines) on the SAME group -> isSuccess:true.
 => The NPE is NOT the malformed-term line (fires on a clean all-OneTime quote) and NOT the procedure
    (reprice + Ungroup both succeed). It is specific to the native DeleteGroup cascade-delete+reprice action.
    Platform-side robustness bug, not a V21 procedure step. Refutes the memory "malformed-term necessary" framing.

## Verdict
PASS for K-16's procedure-side assertion: the procedure does not NPE on the sparse/delete-group context;
the DeleteGroup Map.get NPE is platform-side (native RLM), unconditional, NOT fixable in the procedure.
Reportable defect is ORG/PLATFORM (SC-3473) -> Salesforce case for the unguarded native NPE; NOT a PROCEDURE-DEFECT.

Cleanup: both throwaway clones deleted; canonical 0Q0WC000002U2020AC untouched.
