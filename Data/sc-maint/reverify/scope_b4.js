export const meta = {
  name: 'sc3346-b4-scope',
  description: 'Scope the exact B-4 renewal-formula null-guard fix + safe apply/deploy/validation plan',
  phases: [
    { title: 'Investigate', detail: 'formula / edit-mechanics+context / regression — parallel' },
    { title: 'Synthesize', detail: 'precise change spec + apply + rollback + validation' },
  ],
}

const FORMULA = {
  type: 'object', additionalProperties: false,
  required: ['renewal_element', 'current_formula', 'fixed_formula', 'all_netunitprice_writers', 'idiom_supported', 'notes'],
  properties: {
    renewal_element: { type: 'string', description: 'element name, parent container, sequence, file line of the renewal NetUnitPrice formula' },
    current_formula: { type: 'string', description: 'exact current <value> verbatim' },
    fixed_formula: { type: 'string', description: 'exact proposed BLANKVALUE-guarded replacement <value>' },
    all_netunitprice_writers: { type: 'string', description: 'every formula element in the active block that writes NetUnitPrice for renewal OR new business, with line + gate (for M-2 bundling decision)' },
    idiom_supported: { type: 'string', description: 'evidence BLANKVALUE/ISNULL is already used elsewhere in this active block (cite lines) so the syntax is valid' },
    notes: { type: 'string' },
  },
}
const MECH = {
  type: 'object', additionalProperties: false,
  required: ['edit_approach', 'deploy_mechanism', 'context_resync', 'apply_sequence', 'rollback', 'risks'],
  properties: {
    edit_approach: { type: 'string', description: 'in-place edit of active version vs clone-new-version-and-activate; what RLM requires' },
    deploy_mechanism: { type: 'string', description: 'ExpressionSetDefinition metadata deploy (does it round-trip? prior deploys exist in repo) vs Setup UI; concrete commands' },
    context_resync: { type: 'string', description: 'exact steps to re-sync SalesTransactionContextExt_v2 to the version, per the contextDefinitionName regression' },
    apply_sequence: { type: 'string', description: 'numbered safe sequence end-to-end' },
    rollback: { type: 'string' },
    risks: { type: 'string' },
  },
}
const REGR = {
  type: 'object', additionalProperties: false,
  required: ['shared_scope', 'isolation', 'regression_tests', 'b4_fallback_test', 'notes'],
  properties: {
    shared_scope: { type: 'string', description: 'what else lives in this active version that SC-3393/3372/3359/3384 rely on' },
    isolation: { type: 'string', description: 'is the renewal-formula edit isolated from those? evidence' },
    regression_tests: { type: 'string', description: 'concrete regression checks for the shared tickets' },
    b4_fallback_test: { type: 'string', description: 'a Year-2->Year-3 renewal test that forces COLACalculatedPrice=0 so the guarded fallback actually executes' },
    notes: { type: 'string' },
  },
}
const SPEC = {
  type: 'object', additionalProperties: false,
  required: ['exact_change', 'apply_sequence', 'deploy_and_rollback', 'validation_checklist', 'bundle_with_m2', 'residual_risk', 'recommendation'],
  properties: {
    exact_change: { type: 'string' },
    apply_sequence: { type: 'string' },
    deploy_and_rollback: { type: 'string' },
    validation_checklist: { type: 'string' },
    bundle_with_m2: { type: 'string', description: 'should B-4 and M-2 ship in one procedure edit? why/why not' },
    residual_risk: { type: 'string' },
    recommendation: { type: 'string' },
  },
}

const PRE = [
  'CONTEXT: SC-3346 Maintenance (Derived) Pricing, FortraUAT (default org; pass --target-org FortraUAT). You are scoping the FIX for peer-review blocker B-4. READ-ONLY: do NOT deploy/DML/refresh anything.',
  '',
  'B-4: the renewal pricing formula in the ACTIVE pricing-procedure version has NO null guards. Current formula (verified live):',
  "  IF ( QuoteTypeText__c = 'Renewal' , IF ( COLACalculatedPrice__c > 0 , COLACalculatedPrice__c , ( Base_Price__c - Prior_Partner_Discount__c - Prior_Discretionary_Discount__c ) * ( 1 + ( COLA_Uplift_Percent__c / 100 ) ) ) , NetUnitPrice )",
  'Defect: a Year-3 renewal where COLACalculatedPrice__c resolves to 0/null AND the prior-discount fields are null mis-prices via the unguarded (Base - null - null) * (1 + null/100) fallback. Proposed fix wraps each operand with BLANKVALUE(...,0).',
  '',
  'LIVE ARTIFACTS:',
  '- Active procedure metadata retrieved at: Data/sc-maint/reverify/expset/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition (70448 lines). The ACTIVE version block = lines 64829-70445 (the only <status>Active</status>; <versionNumber>12 but label "V13/V130"). The renewal formula is around line 66873 (element DerivedPricingRenewals ~66921); a related element DerivedPricingNewBusiness ~66856 also writes NetUnitPrice with an IF(QuoteTypeText__c=Renewal,...) wrapper.',
  '- ExpressionSet Id 9QLWC0000015cDl4AI, ApiName Rev_Mgmt_Default_Pricing_Procedure.',
  '- Prior procedure DEPLOYS exist in the repo (proof it is deployable, unlike the DecisionTable): *Jira Related Data/sc3345/v9_deploy*, *Jira Related Data/sc3374/v10_deploy* (expressionSetDefinition/ folders).',
  '',
  'CRITICAL KNOWN REGRESSION (do not repeat): an in-place edit to the LIVE active pricing procedure WITHOUT re-syncing the context SalesTransactionContextExt_v2 caused the "Specify the contextDefinitionName" Reprice-All gack. Any B-4 plan MUST include the context resync.',
  'SHARED-PROCEDURE RISK: this same active version is relied on by SC-3393 (Services add), SC-3372 (derived PBE), SC-3359 (partner net), SC-3384 (multi-currency). The edit must be isolated to the renewal formula and regression-checked against those.',
  '',
  'Return ONE structured object for your area. Cite exact line numbers / verbatim formula text / commands.',
].join('\n')

phase('Investigate')
const [formula, mech, regr] = await parallel([
  () => agent(PRE + '\n\nAREA = FORMULA. (1) Extract the EXACT current <value> of the renewal NetUnitPrice formula element in the active block (grep the file 64829-70445 for COLACalculatedPrice__c / Prior_Partner_Discount__c / DerivedPricingRenewals; read around the hit). Give element name, parent container, sequence, file line. (2) Produce the exact BLANKVALUE-guarded replacement (wrap Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, COLA_Uplift_Percent__c each in BLANKVALUE(x,0)); keep the COLACalculatedPrice__c>0 branch and the outer QuoteTypeText__c gate intact. (3) Map ALL NetUnitPrice-writing formula elements in the active block (renewal AND new-business) with line + gate — this informs whether B-4 should bundle with M-2. (4) Prove BLANKVALUE/ISNULL is already used in this active block (cite a line, e.g. ~68196) so the syntax is engine-valid. Confirm the RLM formula function name (BLANKVALUE vs ISNULL vs NULLVALUE) actually supported here.',
    { label: 'B4:formula', phase: 'Investigate', schema: FORMULA }),

  () => agent(PRE + '\n\nAREA = EDIT MECHANICS + CONTEXT RESYNC. Determine the safe way to APPLY a one-formula change to the active pricing-procedure version. (1) In-place edit of the active version vs clone to a new ExpressionSetVersion then activate — what does RLM allow/require, and what did prior Fortra deploys do (inspect *Jira Related Data/sc3345/v9_deploy and sc3374/v10_deploy structure + any notes)? (2) Deploy mechanism: can ExpressionSetDefinition be metadata-deployed cleanly (prior deploys say yes) — give the exact sf project deploy command + source layout; note the DecisionTable round-trip bug does NOT necessarily apply here. (3) The MANDATORY context resync: exact steps to re-sync SalesTransactionContextExt_v2 to the deployed version (this is the step whose omission caused the contextDefinitionName gack). (4) Full numbered apply sequence + rollback (how to revert to the current active version; note version-delete is platform-blocked, so rollback = re-activate prior / redeploy original). List the real risks.',
    { label: 'B4:mechanics', phase: 'Investigate', schema: MECH }),

  () => agent(PRE + '\n\nAREA = REGRESSION / BLAST RADIUS. The active version is shared by SC-3393/3372/3359/3384. (1) Summarize what else this active version contains that those tickets rely on (ABA/partner/regional/derived steps) so we know the edit is near other live logic. (2) Assess whether changing ONLY the renewal NetUnitPrice formula is isolated from those paths (the renewal branch is gated by QuoteTypeText__c=Renewal; new-business/partner/currency paths are different gates) — give evidence. (3) Define a concrete regression test set to run AFTER the edit: a new-business Services add (SC-3393), a partner/discounted reprice (SC-3359/3384), a derived-PBE add (SC-3372), plus a plain reprice-all to confirm no contextDefinitionName gack. (4) Define the B-4-specific positive test: a Year-2 -> Year-3 renewal where COLACalculatedPrice__c=0 so the guarded discount fallback actually executes, asserting it does NOT mis-price on null priors. Use the existing test classes (RenewalMaintenancePricingServiceTest etc.) where possible.',
    { label: 'B4:regression', phase: 'Investigate', schema: REGR }),
])

phase('Synthesize')
const spec = await agent(
  PRE + '\n\nSYNTHESIZE the three findings into a precise, ready-to-execute B-4 change spec for the developer (who will get explicit deploy auth before applying).\n\n' +
  '=== FORMULA ===\n' + JSON.stringify(formula, null, 1) + '\n\n=== MECHANICS ===\n' + JSON.stringify(mech, null, 1) + '\n\n=== REGRESSION ===\n' + JSON.stringify(regr, null, 1) + '\n\n' +
  'Deliver: exact_change (verbatim before/after formula + element location), apply_sequence (numbered, incl. context resync), deploy_and_rollback (exact commands + revert), validation_checklist (B-4 positive test + the shared-ticket regressions + reprice-no-gack), bundle_with_m2 (recommend whether to fix M-2 in the SAME procedure edit since both touch this version, with rationale), residual_risk, recommendation.',
  { label: 'B4:synthesize', phase: 'Synthesize', schema: SPEC }
)

return { formula, mech, regr, spec }
