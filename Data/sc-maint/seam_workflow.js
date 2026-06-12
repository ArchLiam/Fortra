export const meta = {
  name: 'sc3346-seam-coverage-90',
  description: 'Add minimal behavior-preserving @TestVisible seams to PartnerNetPricePosthook + RenewalMaintenancePricingService so their Context.IndustriesContext I/O is unit-testable, then cover to >=90%. Verified live in UAT, sequential.',
  phases: [
    { title: 'RenewalMaintenancePricingService seam', detail: '50%->90%: seam the queryTags/buildContext/updateContextAttributes calls, remove dead getDecimal, test the parsing/build logic' },
    { title: 'PartnerNetPricePosthook seam', detail: '69%->90%: seam the context query/write path, test downstream logic' },
    { title: 'MaintenanceOrderDecompositionService coverage', detail: '~51-76%->90%: pure unit tests, NO seam (class has no Context I/O)' },
  ],
}

const ROOT = '/Users/liamjeong/Documents/Code/Fortra'
const STAGE = ROOT + '/Data/sc-maint/src/classes'

const COMMON = `
You are raising Apex unit-test coverage to >=90% (aim higher) for ONE class in the Fortra "Maintenance (Derived) Pricing" (SC-3346) build, VERIFIED LIVE against FortraUAT. The uncovered lines are the Salesforce RCA pricing-engine context I/O (Context.IndustriesContext.queryTags()/buildContext()/updateContextAttributes()/persistContext()/submitContextUpdates()), which THROW (NoDataFoundException/UnexpectedException/gack) outside a live pricing transaction and cannot be exercised by an Apex unit test as-is. Prod deployment is owned by another team; you ARE authorized to make MINIMAL, BEHAVIOR-PRESERVING test seams in the prod class.

MECHANICS (run from ${ROOT}):
- Re-retrieve the LATEST prod class + its test FRESH from UAT first (the build is churning) so you modify current live code, not a stale copy:
    sf project retrieve start -o FortraUAT -m "ApexClass:<Class>" "ApexClass:<Class>Test" --target-metadata-dir ${ROOT}/Data/sc-maint/fresh_<Class> --unzip
  then copy the .cls + .cls-meta.xml into ${STAGE}/ (overwriting). (If a test class does not exist, create it.)
- Edit files in ${STAGE}/. Deploy ONLY the files you changed:
    sf project deploy start -o FortraUAT --source-dir "${STAGE}/<File>.cls" --ignore-conflicts
- Run + coverage:
    sf apex run test -o FortraUAT --tests <Class>Test --code-coverage --result-format human --wait 30
- Full uncovered list: sf data query --use-tooling-api -o FortraUAT -q "SELECT NumLinesCovered, NumLinesUncovered, Coverage FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name='<Class>'" --json

THE SEAM PATTERN (use this; do NOT change production behavior):
1. For each Context.IndustriesContext READ (e.g. queryTags / buildContext): add a @TestVisible static override field, and branch so that WHEN the override is set AND Test.isRunningTest() the method uses the injected fake response instead of calling the platform. Example:
     @TestVisible private static Map<String, Object> testQueryTagsResponse;
     ...
     Map<String, Object> apiResponse = (Test.isRunningTest() && testQueryTagsResponse != null)
         ? testQueryTagsResponse
         : ctx.queryTags(new Map<String, Object>{ ... });
2. For each Context.IndustriesContext WRITE (updateContextAttributes / persistContext / submitContextUpdates): guard it so it is SKIPPED (or returns a stub) only when Test.isRunningTest() && the test-injection override is set:
     Map<String, Object> updateResult = (Test.isRunningTest() && testQueryTagsResponse != null)
         ? new Map<String, Object>{ 'isSuccess' => true }
         : ctx.updateContextAttributes(new Map<String, Object>{ ... });
   The production path (override null) is byte-for-byte the same behavior as today.
3. Remove genuinely DEAD private methods (grep the whole class to PROVE zero callers first) — e.g. RenewalMaintenancePricingService.getDecimal. Removing dead executable lines raises the coverable ratio. Do NOT remove anything with a caller.
4. KEEP the seams minimal. Do not restructure logic, rename, or change signatures of public/@InvocableMethod members. The diff should be a handful of guarded branches + one or two @TestVisible static fields + (optionally) dead-code removal.

TESTS: build fake apiResponse maps that mirror the real Context.queryTags shape so the parsing/update-building logic runs. The real shape (from the prod parser) is:
  { 'queryResult' => { 'SalesTransactionItem' => [ { 'tagValue' => { ...field=>value... }, 'dataPath' => [ quoteId, lineId ] } ] } }
Set the @TestVisible override, set up real renewal QLI/Quote data where the method also queries the DB (seed Quote_Checklist_Item__c if a Quote insert hits the 'No checklist items' VR), call the now-reachable method (applyToContext / applyColaNetFinalizeToContext / finalizeRenewalMaintenanceAfterPricing / execute / applyPartnerNetPrices / submitContextUpdates), and assert real outcomes (the built itemUpdates contents, the colaNet values, etc.). Cover guard/early-return branches too. All tests must PASS (green).

DELIVERABLE: iterate deploy->run until the class is >=90% and green. Report the EXACT prod-class diff (the seam) so it can be reviewed as behavior-preserving, plus final verified coverage from a real run.`

const RESULT_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    className: { type: 'string' },
    finalPercent: { type: 'number' },
    uncoveredRemaining: { type: 'number' },
    allTestsPass: { type: 'boolean' },
    prodSeamDiff: { type: 'string', description: 'the exact prod-class changes (seam fields + guarded branches + any dead-code removal), so a reviewer can confirm production behavior is unchanged' },
    deadCodeRemoved: { type: 'string' },
    testRunId: { type: 'string' },
    residualUncoveredExplanation: { type: 'string', description: 'what lines (if any) remain uncovered and why' },
    summary: { type: 'string' },
  },
  required: ['className', 'finalPercent', 'allTestsPass', 'prodSeamDiff', 'summary'],
}

phase('RenewalMaintenancePricingService seam')
const r1 = await agent(`${COMMON}

YOUR CLASS: RenewalMaintenancePricingService (currently 50.4%, target >=90%). Existing test: RenewalMaintenancePricingServiceTest (37 passing methods — EXTEND it, keep them green).
Specifics for this class:
- queryLineItems(ctx, contextInstanceId) at ~line 379 calls ctx.queryTags() -> add testQueryTagsResponse override so the parser (lines ~385-436) runs on a fabricated apiResponse.
- applyToContext (~158) and applyColaNetFinalizeToContext (~224): guard the ctx.updateContextAttributes() write; with the override set + seeded renewal QLIs, drive both end-to-end so the colaNetByLineId build loop, mapLineItemsById, getLineItemRecordId, resolveUpdatePath, and the itemUpdates loops all execute.
- finalizeRenewalMaintenanceAfterPricing (~129): guard ctx.buildContext() (add a testContextIdOverride) and ctx.persistContext() so the method runs end-to-end and delegates to applyToContext.
- getDecimal (~462-481) is DEAD CODE — grep the class to confirm zero callers, then remove it.
- The InvocableMethod applyRenewalMaintenanceNetPrices dispatch branches (contextInstanceId + finalizeAfterPricing true/false; blank contextInstanceId -> finalize) should now be reachable with the seams.
Existing real-data setup mirrors RenewalQuoteLineHandlerTest; non-writeable fields seeded via JSON.deserialize. Report final verified coverage and the seam diff.`, { label: 'rmp-seam', phase: 'RenewalMaintenancePricingService seam', schema: RESULT_SCHEMA })

phase('PartnerNetPricePosthook seam')
const r2 = await agent(`${COMMON}

YOUR CLASS: PartnerNetPricePosthook (currently 69.2%, target >=90%). Existing test: PartnerNetPricePosthookTest (73 passing methods — EXTEND it, keep them green).
Specifics for this class (958 lines): the uncovered ~155 lines are downstream of Context.IndustriesContext.queryTags()/buildContext() in execute(), queryLineItems / queryQuoteHeaderFromContext (JSON parsing), the per-line loop in applyPartnerNetPrices, submitContextUpdates, and applyNetPricesToOrder's buildContext path.
- Add a @TestVisible override for the queryTags response(s) so queryLineItems and queryQuoteHeaderFromContext parse fabricated data, and guard the context WRITE calls (updateContextAttributes/submitContextUpdates) and any buildContext call so they are skipped/stubbed under Test.isRunningTest() when the override is set.
- Then drive execute() (RevSignaling.TransactionRequest via JSON.deserialize, as the existing tests do) and applyPartnerNetPrices / submitContextUpdates / applyNetPricesToOrder with the injected response so the per-line partner-net application loop and the order path execute and assert real outcomes.
- Identify any genuinely dead defensive lines the agent earlier flagged (253-254/256-257, 376, 427, 835); only remove if provably unreachable AND dead (no behavior change). Otherwise cover via tests.
Report final verified coverage and the exact seam diff (behavior-preserving).`, { label: 'pnpp-seam', phase: 'PartnerNetPricePosthook seam', schema: RESULT_SCHEMA })

phase('MaintenanceOrderDecompositionService coverage')
const r3 = await agent(`${COMMON}

YOUR CLASS: MaintenanceOrderDecompositionService (currently ~51-76% depending on test mix; target >=90%). Existing test: MaintenanceOrderDecompositionServiceTest (33 passing methods — EXTEND it, keep them green).
IMPORTANT: this class has NO Context.IndustriesContext I/O (grep confirms 0) — so DO NOT add a seam. The uncovered lines are reachable by ordinary unit tests; you just need more of them.
Step 1: get the exact uncovered lines: sf data query --use-tooling-api -o FortraUAT -q "SELECT Coverage FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name='MaintenanceOrderDecompositionService'" --json  (and re-run MaintenanceOrderDecompositionServiceTest solo first so the aggregate reflects its own coverage). Open each uncovered line in ${STAGE}/MaintenanceOrderDecompositionService.cls and add targeted behavioral tests (the class does base x tier decomposition, loadDerivedPricebookEntryIds, loadMaintenanceTierByQliId, buildPatches/persistPatches/buildCommercialPatchesFromWork/loadWork/seedFromWork/prepareForReprice, the QLI->OI quoteMapper, resolveNetPrice/resolveTierRate/compute). Cover the guard/early-return branches and the DML paths (seed Quote_Checklist_Item__c if a Quote insert hits the checklist VR; mirror existing setup). Remove any provably-dead private method (grep zero callers) only if it cleanly raises coverage.
NOTE: this class's coverage can read low when run alongside other heavy tests (multi-test-context artifact) — VERIFY your final number by running ONLY MaintenanceOrderDecompositionServiceTest, and report that solo number. Target >=90% solo + green.`, { label: 'mods-coverage', phase: 'MaintenanceOrderDecompositionService coverage', schema: RESULT_SCHEMA })

return { results: [r1, r2, r3].filter(Boolean) }
