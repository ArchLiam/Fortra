# SC-3473 H6-platform-robustness-gap — DIFFERENTIAL lens verification

## Hypothesis under test
H6: "Latent platform robustness gap: the managed engine leaks a raw unhandled JEP-358 NPE
instead of an actionable message whenever ANY pricing/context prerequisite key is absent —
the specific missing key is secondary."

## Lens: differential / counter-example
Attack: does the SAME engine emit guarded, actionable messages for OTHER missing-prerequisite
conditions? If yes, the "ANY missing key → raw NPE" universal framing is false.

## DECISIVE EVIDENCE — platform DOES have a designed, guarded error contract on the Delete-Group path

Source: RLM/Revenue Management Developer Guide v67.0 (Summer '26), downloaded copy at
EVID/research-web/rlm_dev_guide.txt (240,061 lines). The QLE "Delete Group" action calls the
Place Quote / Place Sales Transaction ConnectApi (Mission A verified).

1. PlaceQuoteResponse class (line ~135542, ~145082) has a designed error channel:
   - `success` (Boolean): "Indicates whether the synchronous part of the processing is successful"
   - `responseError` : List<ConnectApi.PlaceQuoteErrorResponse>  "List of errors encountered
      during the SYNCHRONOUS processing."  (line 135582-135593, 145123)
   => The very save path that Delete-Group runs has a structured, designed slot for actionable
      errors returned with success=false.

2. PlaceQuoteErrorResponse / "Place Quote Error Response" (line 135468-135536). JSON example:
       { "errorCode": "INVALID_API_INPUT",
         "message": "Include record type and method in the request and try again.",
         "referenceId": "refQuoteItem2" }
   - errorCode: "Error code representing the type of error encountered..."
   - message:  "Message stating the reason for the error, if any."
   - referenceId: ties the error to the specific offending line.
   => This is a GUARDED, user-actionable validation message with a pointer to the bad record.

3. Broader engine guards exist too:
   - errorCodeToErrorMap with named codes e.g. UOM_INFO_API_003,
       messageTitle "Invalid uomId is passed.",
       messageDetail "Invalid uomId is passed. Please specify a valid uomId." (line 15588-15596)
   - INSUFFICIENT_ACCESS errorCode (line 17683, 17941)
   => The engine clearly null-guards and surfaces designed messages for MANY conditions.

## CONCLUSION on the universal claim
The engine is NOT uniformly unguarded. It emits designed PlaceQuoteErrorResponse{errorCode,
message, referenceId} for many prerequisite/input failures on the exact Delete-Group save path.
Therefore H6's literal claim — "whenever ANY pricing/context prerequisite key is absent" the
engine leaks a raw NPE — is FALSE AS STATED. The raw JEP-358 NPE occurs on a SPECIFIC
unguarded code path (the context-hydration / pricing Map.get(key).toString()), not as a
universal property of the engine.

## Refute test for H6 — partially met, with nuance
H6 refute test = "the engine DOES emit a guarded, actionable message for the SAME condition
under a patched version."
- For the IDENTICAL missing-key condition (context-hydration Map.get==null), there is NO
  evidence of a platform patch that converts it to a guarded message. The documented sibling
  getTags() NPE (applikontech RLM troubleshooting guide) still leaks the raw Java NPE and is
  only worked around via CONFIG (Context Definition Mappings, Generate All Mappings, default
  mapping, link new ctx version to both procedures, sync decision tables, attribute-based
  pricing output marking, permissions). So for THIS condition the gap is real and unpatched.
- BUT for OTHER missing-prerequisite conditions the engine emits guarded PlaceQuoteErrorResponse.
=> The gap is condition-SPECIFIC, not universal. This refutes the "ANY key" framing while
   leaving intact the narrow, true observation that THIS particular context-hydration path is
   unguarded.

## Org-side counter-example (differential) — INFERENCE ONLY, cannot be DML-verified
Mission E (EVID/missionE/differentiator_summary.json) found a near-twin non-failing group
1C9WC00000096J70AI "06/22 HW-1.2 Group" (quote 0Q0WC000003CTVx0AO): Accepted, HW-type,
Power-configured, net>>list (NetUnitPrice 17463.9 vs ListPrice 2324.15), Hardware__c stamped —
shares almost every alleged surface condition with the failing group but is single-selling-model
(all TermDefined) and NOT a mixed quote. CAVEAT: "deletes fine" is INFERRED; actually deleting
it is DML and forbidden, so no group in this org has been delete-tested. This counter-example
shows the surface conditions (HW-type, markup, Accepted, configured) are NOT individually
sufficient — consistent with a specific missing-key trigger rather than a blanket robustness gap.

## Verdict: REFINED
H6 is TRUE in its narrow form (this specific context-hydration/pricing path is unguarded and
leaks a raw JEP-358 NPE; no patch known) but FALSE in its universal "ANY missing key" form,
because the same Place Quote save path demonstrably returns guarded PlaceQuoteErrorResponse
errors for many other prerequisite failures. It is a meta-finding about message QUALITY, not an
identification of the actionable missing key — so it cannot be the primary answer to remediation.
