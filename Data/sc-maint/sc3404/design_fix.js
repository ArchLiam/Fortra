export const meta = {
  name: 'sc3404-surgical-design',
  description: 'Design + adversarially verify the exact surgical SC-3404 edit (native non-authoritative only for stamped maintenance lines)',
  phases: [
    { title: 'Anatomy', detail: 'read the V14 native-pull container precisely' },
    { title: 'Design+Verify', detail: 'exact edit + adversarial 513K-safety check' },
  ],
}

const FILE = 'Data/sc-maint/sc3404/x/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition'

const ANATOMY = {
  type: 'object', additionalProperties: false,
  required: ['native_element', 'formula_element', 'nonrenewal_filter', 'interaction', 'exact_xml'],
  properties: {
    native_element: { type: 'string', description: 'DerivedProductsRenewals: line, resultIncluded, output params, parentStep, sequenceNumber, any advancedCondition/filter' },
    formula_element: { type: 'string', description: 'DerivedPricingRenewals: line, resultIncluded, output, sequenceNumber, the formula value' },
    nonrenewal_filter: { type: 'string', description: 'DerivedProductsNonRenewal: line, its exact condition, role (how it scopes the native pull)' },
    interaction: { type: 'string', description: 'precise execution order + which element commits NetUnitPrice for a renewal derived line, and why native wins' },
    exact_xml: { type: 'string', description: 'verbatim XML of the native element + the formula element + the nonrenewal filter, with line numbers' },
  },
}
const DESIGN = {
  type: 'object', additionalProperties: false,
  required: ['discriminator', 'exact_edits', 'preserves_513k', 'commits_stamped', 'fim462_test', 'rollback', 'risks', 'recommendation'],
  properties: {
    discriminator: { type: 'string', description: 'the exact field/condition that distinguishes stamped SC-3346 maintenance lines from the 513K native-priced lines (e.g. Base_Price__c IsNotNull)' },
    exact_edits: { type: 'string', description: 'the precise metadata changes: element, tag, before -> after, verbatim. Both coordinated changes if needed.' },
    preserves_513k: { type: 'string', description: 'proof/argument the 513K native-priced renewal lines still price via native after the edit' },
    commits_stamped: { type: 'string', description: 'proof the stamped maintenance line now commits the formula value (67.38), not 0' },
    fim462_test: { type: 'string', description: 'the exact regression: which MTD-less product, expected price, how to verify' },
    rollback: { type: 'string' },
    risks: { type: 'string' },
    recommendation: { type: 'string', description: 'GO / NO-GO / NEEDS-OWNER, with why' },
  },
}

const PRE = [
  'CONTEXT: SC-3404 fix design, FortraUAT, READ-ONLY (no deploy/DML). The active pricing procedure version is V14, block lines 69795-75411 in file ' + FILE + ' . Confirmed live findings: on a renewal derived maintenance line, the formula DerivedPricingRenewals (B-4 ISNULL formula) computes the correct value (67.38) in-flight with resultIncluded=false, but the native DerivedProductsRenewals (actionType=DerivedPricing, resultIncluded=true, runs last under container DerivedProductsNativePull) is the authoritative committer and overwrites it to 0 (or the native-derived value).',
  'GOAL: make the native element NON-authoritative ONLY for the small cohort of stamped SC-3346 maintenance lines (those carrying Base_Price__c / COLACalculatedPrice__c), so the formula commits for THEM, while the native element stays authoritative for the ~513,622 of 513,627 renewal-maintenance lines that have NO stamped inputs and price ONLY via native (a global flip of resultIncluded would zero those ~513K — proven unsafe).',
  'IMPORTANT mechanics for the implementer (do not contradict): the edit will be IN-PLACE on V14 (no new version, per owner constraint); the existing sibling DerivedProductsNonRenewal (AdvancedListFilter under DerivedProductsNativePull) is the model for how to scope/exclude lines from the native pull.',
  'Only reason about the ACTIVE V14 block (lines 69795-75411). Cite exact line numbers from ' + FILE + ' .',
].join('\n')

phase('Anatomy')
const anatomy = await agent(
  PRE + '\n\nAREA = ANATOMY. Read the DerivedProductsNativePull container in the V14 block (69795-75411) precisely. For EACH of: DerivedProductsRenewals (native), DerivedPricingRenewals (formula), DerivedProductsNonRenewal (filter) — extract verbatim: the full <steps> block, parentStep, sequenceNumber, resultIncluded, actionType, output <parameters> (what it writes), and any <advancedCondition>/<filterConditions>/<conditionLogic>. Explain the EXACT execution order within the container and precisely WHY the native element commits NetUnitPrice over the formula for a renewal derived line. Quote the DerivedProductsNonRenewal filter condition verbatim (it is the template for excluding lines from the native pull). grep within lines 69795-75411 only.',
  { label: 'anatomy', phase: 'Anatomy', schema: ANATOMY }
)

phase('Design+Verify')
const design = await agent(
  PRE + '\n\nAREA = FIX DESIGN + ADVERSARIAL SAFETY. Here is the anatomy:\n' + JSON.stringify(anatomy, null, 1) + '\n\n' +
  'Design the EXACT surgical edit. (1) Pick the discriminator that cleanly separates the stamped SC-3346 maintenance cohort from the 513K native-priced lines — verify it live read-only if useful (e.g. how many renewal-maintenance QLIs have Base_Price__c populated vs null; we know ~5 vs ~513,622). (2) Specify the precise metadata change(s): likely BOTH (a) add an exclusion to the native DerivedProductsRenewals so it does NOT run/commit for lines where the discriminator is set (model it on DerivedProductsNonRenewal), AND (b) set DerivedPricingRenewals resultIncluded false->true so the formula commits for those lines — confirm whether both are needed or one suffices, given execution order. Give before->after verbatim XML for each edit. (3) ADVERSARIALLY verify: prove the 513K native-priced lines are UNAFFECTED (native still authoritative for them), prove the stamped maintenance line now commits 67.38, and identify failure modes (partial stamping, lines with Base_Price but meant for native, ordering). (4) Define the FIM-462 regression (MTD-less config product renewal must still price its native value, e.g. ~462) + the positive test (stamped maintenance commits 67.38) + no-gack + SC-3393/3372/3359/3384 no-ops. (5) Rollback for an IN-PLACE V14 edit (no clone). (6) Recommend GO / NO-GO / NEEDS-OWNER with rationale — be blunt about whether this is safe to execute in-place tonight or needs Nir/Marc.',
  { label: 'design', phase: 'Design+Verify', schema: DESIGN }
)

return { anatomy, design }
