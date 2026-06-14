export const meta = {
  name: 'sc3346-scope-remaining',
  description: 'Make M-2, B-5, M-3+M-6, and SC-3372 execution-ready (scope/decide/plan; no live changes)',
  phases: [
    { title: 'Scope', detail: 'M-2 / B-5 / M-3+M-6 / SC-3372 in parallel' },
    { title: 'Synthesize', detail: 'consolidated execution plan + sequencing' },
  ],
}

const SPEC = {
  type: 'object', additionalProperties: false,
  required: ['item', 'status_today', 'decision_needed', 'exact_change', 'execution_sequence', 'risk', 'validation', 'blocked_by'],
  properties: {
    item: { type: 'string' },
    status_today: { type: 'string', description: 'precise current live state' },
    decision_needed: { type: 'string', description: 'any open design/business decision before execution (or "none")' },
    exact_change: { type: 'string', description: 'the concrete change: elements/fields/formulas/records, verbatim where possible' },
    execution_sequence: { type: 'string', description: 'numbered steps to execute, incl. who/where (UI vs deploy) and prerequisites' },
    risk: { type: 'string' },
    validation: { type: 'string' },
    blocked_by: { type: 'string', description: 'gating dependency: prod-auth / maintenance-window / design-decision / another item' },
  },
}

const PRE = [
  'CONTEXT: SC-3346 Maintenance (Derived) Pricing remediation, FortraUAT default org (pass --target-org FortraUAT; prod alias FortraProd). READ-ONLY: do NOT deploy/DML/refresh/activate anything. Produce an execution-ready spec.',
  '',
  'ESTABLISHED THIS SESSION (do not contradict without live evidence):',
  '- Active pricing procedure = Rev_Mgmt_Default_Pricing_Procedure, currently ACTIVE version = V14 (we just activated it; the ONLY active ExpressionSetVersion). It carries the B-4 ISNULL renewal-formula fix. Live procedure metadata: Data/sc-maint/sc3346_b4/apply/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition (V14 block) — but RE-RETRIEVE fresh for current state.',
  '- ExpressionSetDefinition deploys cleanly (round-trips); DecisionTable metadata does NOT (round-trip bug) → DecisionTable edits are UI-only.',
  '- ExpressionSetVersion.IsActive is DML-updateable and queryable via the STANDARD data API (not Tooling). Activate a single version via per-row UI Activate; NEVER the custom "Context Def Manager" LWC "Reactivate All Dependencies" (it set 8 versions active = corruption).',
  '- Procedure edits require a context resync of SalesTransactionContextExt_v2 after activation, or the "Specify the contextDefinitionName" gack appears.',
  '- The procedure is shared by SC-3393/3372/3359/3384 — regress those (non-renewal branches) after any procedure change.',
  '',
  'Existing dossier (READ to avoid redoing work): "*Jira/Task/sc3403 | Peer Review - SC-3346 Maintenance (Derived) Pricing/" — 02_BLOCKERS_AND_DEFECTS.md, 05_REVERIFICATION_2026-06-12.md, 06_B5_FIX_PLAN.md, 07_B4_FIX_PLAN.md, 08_M1_SDD_RECONCILIATION.md.',
  '',
  'Return ONE structured spec for your item. Be concrete and cite live values / line numbers / IDs.',
].join('\n')

phase('Scope')
const specs = await parallel([
  () => agent(PRE + '\n\nITEM = M-2 (competing new-business formulas + MTD/MDT mismatch). In the ACTIVE procedure version, three FormulaBasedPricing elements write NetUnitPrice on derived lines: DerivedPricingNetUnitPriceValueReset (IF(Renewal,NetUnitPrice,0)), DerivedPricingFormula (tier-IF * Source_List_Price__c, gate AttributeDefinitionCode=MTD), DerivedPricingNewBusiness (IF(Renewal,NetUnitPrice,Base_Price__c*tier), gate ...=MDT). RESOLVE THE DESIGN DECISION: (1) Re-retrieve the live active version; quote each of the 3 elements verbatim with its filter/gate/sequence. (2) Determine which new-business formula the system ACTUALLY uses today (which gate passes on a real new-business derived maintenance line — is it MTD or MDT? check a real QLI attribute AttributeDefinitionCode and the SDD which says Base_Price__c is the field) and therefore which formula should WIN. (3) Confirm whether MTD vs MDT is a typo (one is dead) or two distinct attributes (query AttributeDefinition / the decision/attribute codes live). (4) Specify the exact edit to collapse to ONE unambiguous new-business formula (which element to keep, which to retire, make the survivor filter unconditional for new-business derived lines), as a V15 clone of V14. Give the cutover sequence (clone V14->V15 inactive, deploy, per-row activate, context resync, regress SC-3393/3372/3359/3384). Flag any Finance/owner decision.',
    { label: 'M-2', phase: 'Scope', schema: SPEC }),

  () => agent(PRE + '\n\nITEM = B-5 (Asset_Action_Source_Entries_Decision_Table_V2 refresh fails: Hash Key Group >200 rows). The fix (data-proven) = add the Asset Id as an Equals match column so the hash key becomes Asset-grained (~1 row/asset, 0 oversized buckets). Read 06_B5_FIX_PLAN.md. Finalize the EXECUTION sequence given the constraints we hit: (1) metadata deploy of the DecisionTable FAILS (round-trip bug) -> must edit in Setup UI Decision Table editor. (2) The table cannot be deactivated because 3 active expression-set versions reference it: Salesforce_Default_Pricing_Discovery_Procedure_v2_V1, Salesforce_Default_Pricing_Discovery_Procedure_V1, Stolle_Rev_Mgmt_Pricing_Procedure_V1 -> a maintenance window is required to deactivate those first. Re-confirm these 3 live. Give the exact ordered steps (deactivate the 3 referencing versions -> deactivate table -> add Asset Id Equals input column via UI -> reactivate table -> Refresh -> reactivate the 3 versions -> validate), the blast radius (org-wide discovery down during the window), and the validation (RefreshStatus=Completed + a both-assets renewal repro). Note B-5 is OFF the build critical path (renewals use Q2O carry-forward; the table never synced in 12mo yet renewals priced).',
    { label: 'B-5', phase: 'Scope', schema: SPEC }),

  () => agent(PRE + '\n\nITEM = M-3 + M-6 (PROD-cutover items, combined). M-3: prod LACKS ContextDefinition SalesTransactionContextExt_v2 (only base SalesTransactionContextExt) yet PartnerNetPricePosthook hardcodes _v2 -> prod reprice/convert would gack. M-6: prod COLAUpliftPrehook is stale (LengthWithoutComments ~39,956 vs UAT ~43,272; lacks renewal-maintenance COLA logic). Build the PROD-CUTOVER MANIFEST for SC-3346 maintenance pricing, derived from the LIVE org NOT the SDD. (1) Re-confirm prod gaps: query FortraProd for ContextDefinition list and COLAUpliftPrehook LengthWithoutComments vs FortraUAT. (2) Enumerate the FULL set of components that must deploy to prod for maintenance + renewal pricing to work: the V14 ExpressionSetDefinition + SalesTransactionContextExt_v2 context, the SignalingApexProcessor stack (COLAUpliftPrehook, PartnerNetPricePosthook) reconciled (note prod/UAT lineages diverge per M-6 — superset, do not blind-overwrite), the renewal/maintenance Apex classes, the QLI/OrderItem custom fields, the Stamp_Maintenance_Pricing_Inputs Flow, Maintenance_Rate__mdt, the decision tables, PBEDP rows (M-5). (3) Give the deploy ORDER + the post-deploy context resync + activation steps + regression. (4) Mark everything blocked_by = prod authorization (explicit, separate). Be clear this is a manifest/plan only — prod is gated.',
    { label: 'M-3+M-6', phase: 'Scope', schema: SPEC }),

  () => agent(PRE + '\n\nITEM = SC-3372 / MissingContributor (NEW ticket write-up). On a renewal quote with ONLY the maintenance line (no source license on the cart), pricing completes with ValidationResult=MissingContributor and committed NetUnitPrice=0 — even though the contributor product IS resolved (flow Get_First_Derived found ContributingProductId=01tWC00000DD1btYAD via PBEDP 182WC000000HNcwYAG, Nir M-5 fix) — because the contributor is not a LINE on the transaction, so native derived-pricing validation marks the txn incomplete. This blocked B-4 from displaying its (correctly computed in-flight, 67.38) renewal price. Write this up as a new ticket: (1) crisp problem statement + repro (quote 0Q0WC0000037XvB0AU, Powertech IAM RenewalMaintenance). (2) RCA: native DerivedProductsRenewals/contributor-resolution requires the contributing product present on the transaction for IsDerived renewal lines; the SC-3346 design intends the maintenance line to price standalone via stamped fields, but the native MissingContributor validation still fires. (3) Fix OPTIONS with tradeoffs: (a) ensure the contributing license is on the cart for renewals, (b) suppress/remove the native contributor element for the renewal branch (note SC-3372 RCA_v2 warned removal can convert to silent $0 — assess), (c) a validation-bypass/override for stamped-priced derived lines. (4) Relationship to SC-3346 (B-4) and SC-3372. Recommend an option.',
    { label: 'SC-3372', phase: 'Scope', schema: SPEC }),
])

phase('Synthesize')
const valid = specs.filter(Boolean)
const plan = await agent(
  PRE + '\n\nSYNTHESIZE the four specs into a single consolidated execution plan for the remaining SC-3346 remediation.\n\n' +
  valid.map((s) => '=== ' + (s.item || s.blocked_by) + ' ===\n' + JSON.stringify(s, null, 1)).join('\n\n') +
  '\n\nProduce: (1) a recommended EXECUTION ORDER across the four, separating UAT-executable-now (with ack) from prod/window-gated, and noting any inter-dependencies (e.g., M-2 and a future M-3/M-6 prod cutover both touch the procedure; SC-3372 gates renewal E2E display). (2) For each, the single most important decision or prerequisite. (3) A blunt risk ranking. (4) What can be done with zero live change vs what needs an authorized cutover/window/prod-auth. Keep it decision-useful for the owner.',
  { label: 'synthesize', phase: 'Synthesize', schema: { type: 'object', additionalProperties: false, required: ['execution_order', 'per_item_gate', 'risk_ranking', 'now_vs_gated'], properties: { execution_order: { type: 'string' }, per_item_gate: { type: 'string' }, risk_ranking: { type: 'string' }, now_vs_gated: { type: 'string' } } } }
)

return { specs: valid, plan }
