export const meta = {
  name: 'sc3346-b5-investigate',
  description: 'Scope the real fix for B-5 (Asset_Action_Source decision-table refresh failing on >200-row hash group)',
  phases: [
    { title: 'Investigate', detail: 'anatomy / consumers / platform — parallel' },
    { title: 'Synthesize', detail: 'ranked fix options with tradeoffs' },
  ],
}

const FIND = {
  type: 'object', additionalProperties: false,
  required: ['area', 'summary', 'facts', 'open_questions'],
  properties: {
    area: { type: 'string' },
    summary: { type: 'string' },
    facts: { type: 'string', description: 'concrete live values / metadata / query rows' },
    open_questions: { type: 'string' },
  },
}

const OPTIONS = {
  type: 'object', additionalProperties: false,
  required: ['recommended_option', 'options', 'sequence', 'risks', 'validation'],
  properties: {
    recommended_option: { type: 'string' },
    options: { type: 'string', description: 'each fix option: what it changes, effort, risk, reversibility' },
    sequence: { type: 'string', description: 'step-by-step to apply the recommended option' },
    risks: { type: 'string' },
    validation: { type: 'string', description: 'how to prove RefreshStatus=Completed + renewal repro works' },
  },
}

const PRE = [
  'CONTEXT: SC-3346 Maintenance (Derived) Pricing, FortraUAT (default org; pass --target-org FortraUAT). You are scoping the FIX for peer-review blocker B-5.',
  'B-5: DecisionTable Asset_Action_Source_Entries_Decision_Table_V2 (Id 0lDa50000007BJhEAM, SourceObject=AssetActionSource) is Status=Active but RefreshStatus=Failed, LastSyncDate=null, RefreshFailureReason="common.exception.ApiException: Hash Key Group contains more than 200 rows". AssetActionSource has ~430,335 rows. This is the lookup that maps a renewing asset to its source/renewal entries; with a never-completed sync it returns no usable data -> "renewing both assets at once fails in the pricing procedure before a quote is created". The companion Derived_Pricing_Entries_Decision_Table IS Completed (so new business works, renewal fails).',
  'Live retrieved active pricing procedure: Data/sc-maint/reverify/expset/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition (active block lines 64829-70445, labelled V13/V130).',
  'This is READ-ONLY investigation: do NOT deploy, refresh, or DML anything. Only query/retrieve/read. Return structured findings.',
].join('\n')

phase('Investigate')
const findings = await parallel([
  () => agent(PRE + '\n\nAREA = ANATOMY. Determine WHY the hash key group exceeds 200 rows and what the table is keyed on.\n' +
    '1. Query the table: sf data query --target-org FortraUAT -q "SELECT Id, DeveloperName, Status, RefreshStatus, RefreshFailureReason, SourceObject, LastSyncDate FROM DecisionTable WHERE Id=\'0lDa50000007BJhEAM\'" --json\n' +
    '2. Retrieve its metadata to see input/output columns and which columns form the match/hash key: sf project retrieve start --target-org FortraUAT -m "DecisionTable:Asset_Action_Source_Entries_Decision_Table_V2" --target-metadata-dir Data/sc-maint/reverify/b5_dt . If that metadata type is unsupported, inspect via Tooling API objects (DecisionTable, DecisionTableParameter, DecisionTableColumn or similar) — discover the right sobjects with: sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Id FROM DecisionTableParameter LIMIT 1" and adapt.\n' +
    '3. Describe AssetActionSource (sf sobject describe --sobject AssetActionSource --target-org FortraUAT) and identify the field(s) used as the decision-table match/hash key.\n' +
    '4. Prove the >200 problem with data: GROUP BY the suspected key field(s) and find groups with COUNT>200, e.g. sf data query --target-org FortraUAT -q "SELECT <keyField>, COUNT(Id) c FROM AssetActionSource GROUP BY <keyField> HAVING COUNT(Id)>200 ORDER BY COUNT(Id) DESC LIMIT 20" --json . Report the worst offenders and how many distinct key values exist.\n' +
    'Report the exact match-key columns, the offending high-cardinality group(s), and what extra discriminator column(s) would split groups under 200.',
    { label: 'B5:anatomy', phase: 'Investigate', schema: FIND }),

  () => agent(PRE + '\n\nAREA = CONSUMERS + DESIGN INTENT. Determine what actually USES this table and whether the design even needs it.\n' +
    '1. grep the retrieved active procedure block (lines 64829-70445) for references to this decision table by API name and by Id 0lDa50000007BJhEAM, and for "AssetActionSource", "DerivedPricingDataRetrieval", "Asset_Action_Source": grep -n "Asset_Action_Source\\|0lDa50000007BJhEAM\\|AssetActionSource\\|DerivedPricingDataRetrieval" on the file. Identify which procedure element(s) (Lookup/native derived element) consume it and on which branch (renewal vs new business).\n' +
    '2. Read the SC-3346 design + the peer-review docs to see whether the design intends to KEEP this native asset-action-source lookup or REMOVE the native derived element (the build spec says "the design removes the native element"; SC-3372 memory says native DerivedPricingDataRetrieval should be removed). Files: the build spec / SDD under docs/, and "*Jira/Task/sc3403 | Peer Review - SC-3346 Maintenance (Derived) Pricing/" (README, 02_BLOCKERS_AND_DEFECTS.md). Also check "*Jira/Task/sc3372*" for the native-element-removal design.\n' +
    '3. Determine: is B-5 fixed by REPAIRING the table (re-key/refresh) or by REMOVING its consumer from the renewal path (so the table is no longer reached)? Report the consumer element(s), the branch, and the design-intended disposition (keep-and-fix vs remove-consumer), with citations.',
    { label: 'B5:consumers', phase: 'Investigate', schema: FIND }),

  () => agent(PRE + '\n\nAREA = PLATFORM + FIX PATTERNS. Research the Salesforce RLM/decision-table "Hash Key Group contains more than 200 rows" constraint and the supported remedies.\n' +
    '1. Use WebSearch/WebFetch on Salesforce docs/help/known-issues for "DecisionTable Hash Key Group contains more than 200 rows", Revenue Cloud / Industries decision table limits, and how the hash/group key works (which columns count, range vs exact match).\n' +
    '2. Enumerate the supported remedies and their tradeoffs: (a) add discriminator column(s) to the match key so each group < 200; (b) filter/scope the SourceObject (a filtered dataset / where-clause / a curated subset object) so AssetActionSource feeding the table is renewal-relevant only; (c) change column match type (exact vs range) to reduce group size; (d) remove the native consumer entirely (if the design no longer needs the table); (e) split into multiple narrower tables.\n' +
    '3. For each remedy note: effort, risk, reversibility, whether it needs a metadata deploy vs setup-UI action, and whether it requires re-publishing the pricing procedure.\n' +
    'Report a ranked shortlist of remedies with the platform rationale for the recommended one.',
    { label: 'B5:platform', phase: 'Investigate', schema: FIND }),
])

phase('Synthesize')
const valid = findings.filter(Boolean)
const synth = await agent(
  PRE + '\n\nYou are the synthesizer. Here are the three investigation findings (anatomy, consumers/design, platform):\n\n' +
  valid.map((f, i) => '=== FINDING ' + (i + 1) + ' (' + f.area + ') ===\nSUMMARY: ' + f.summary + '\nFACTS: ' + f.facts + '\nOPEN: ' + f.open_questions).join('\n\n') +
  '\n\nProduce ranked fix options for B-5 for a developer who is about to implement the fix. Be concrete: name the exact columns/elements/objects to change. Give a recommended option, the step-by-step sequence to apply it (read-only investigation already done; the implementer will need explicit deploy authorization for any change), the risks (esp. impact on the live pricing procedure shared by SC-3393/3372/3359/3384 and the renewal path), and how to validate (RefreshStatus=Completed + a both-assets renewal repro).',
  { label: 'B5:synthesize', phase: 'Synthesize', schema: OPTIONS }
)

return { findings: valid, fix: synth }
