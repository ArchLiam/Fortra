# SC-3441 Live Runtime Waterfall Investigation - DECISIVE FINDING

## Root cause: V19 is INACTIVE; the live runtime is V16 (no cancel group, no field)

Active runtime ExpressionSetVersion = V16 (9QMWC00000024PJ4AY, IsActive=true)
Active design ExpressionSetDefinitionVersion = V16 (9QBWC0000000niH4AQ, Status=Active)
V19 runtime (9QMWC00000024tx4AA) = IsActive=FALSE (compiled 17:28:32 but never activated)
V19/V18 design = Status=Inactive

## simulationInputVariablesWithData (GET) - the live runtime context input
- Runtime V19 (inactive): CancelNetUnitPrice__c = 15000.0  PRESENT (41 keys)
- Runtime V18 (inactive): CancelNetUnitPrice__c PRESENT
- Runtime V17 (inactive): CancelNetUnitPrice__c ABSENT
- Runtime V16 (ACTIVE):   CancelNetUnitPrice__c ABSENT (40 keys)

The field is only wired into the context input of V18/V19 - the versions that contain the
ListContainer13/ListOperation1/FormulaBasedPricing1 cancel group. V16 (live) never pulls it.

## Why the Simulator works but live reprice = $0
Simulator ran against V19 DESIGN (has the cancel group) -> -15000.
Live Reprice All runs the ACTIVE RUNTIME = V16 (no cancel group, field not even in context) -> $0.
"Fresh compile" didn't fix it because the new V19 runtime was compiled but NOT ACTIVATED.

## Read-only endpoints available (RLM dev guide v67.0 / Salesforce Pricing connect API)
- GET  /connect/core-pricing/simulationInputVariablesWithData  (USED - decisive)
- GET  /connect/core-pricing/waterfall/{lineItemId}/{executionId}  (needs persisted executionId; QLI.PriceWaterfallIdentifier=null)
- GET  /connect/core-pricing/pricing-process-execution/{executionId}
- GET  /connect/core-pricing/apiexecutionlogs/{executionId}
- POST /connect/core-pricing/pricing  (returns SF-Pricing-00008 output-tags-invalid for THIS procedure even with minimal input - procedure-intrinsic to headless invocation, not the bug)

## Fix
Activate ExpressionSetVersion V19 (or whichever version carries the cancel group) as the runtime,
and ensure the corresponding design version is Active. No context re-sync needed - the field
resolves correctly the moment the version that references it is the active one.
