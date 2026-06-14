export const meta = {
  name: 'sc3346-reverify-batch1',
  description: 'Re-verify 8 non-test SC-3346 peer-review findings against live FortraUAT',
  phases: [{ title: 'Verify', detail: 'one agent per finding, live-org adversarial check' }],
}

const VERDICT = {
  type: 'object',
  additionalProperties: false,
  required: ['id', 'severity', 'status', 'headline', 'evidence', 'commands_run', 'residual_risk', 'recommendation'],
  properties: {
    id: { type: 'string' },
    severity: { type: 'string' },
    status: { type: 'string', enum: ['RESOLVED', 'NOT_RESOLVED', 'PARTIAL', 'CANNOT_VERIFY'] },
    headline: { type: 'string', description: 'one-line verdict' },
    evidence: { type: 'string', description: 'concrete live values / query rows / line refs that prove the status' },
    commands_run: { type: 'string' },
    residual_risk: { type: 'string' },
    recommendation: { type: 'string' },
  },
}

const PRE = [
  'You are adversarially re-verifying whether ONE peer-review finding for SC-3346 (Maintenance Derived Pricing) has actually been RESOLVED by Nir Kailash\'s recent changes. The claim "Nir fixed the issues" is what you must DISPROVE or confirm with live evidence.',
  '',
  'ORG: FortraUAT is the default org; always pass --target-org FortraUAT to every sf command. (Prod alias: FortraProd.)',
  '',
  'ESTABLISHED LIVE FACTS (2026-06-12):',
  '- The active pricing-procedure version is V12 (status Active). The review analyzed "V13" (its "V130:" line refs). V13 is now a near-empty draft. The procedure churns versions, so reason ONLY about the V12 active block.',
  '- Live procedure metadata retrieved at: Data/sc-maint/reverify/expset/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition (70448 lines). Version blocks: V1@4871, V2@9745, V3@14847, ... V11@58559, V12@64829 [status Active @64841], V13@70446 [empty draft]. The V12 ACTIVE block is lines 64829-70445. Use grep with line numbers and read around hits.',
  '- To read a class LIVE body without file conflicts use Tooling API: sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Name, LengthWithoutComments, Body FROM ApexClass WHERE Name=\'CLASSNAME\'" --json  (Body is large; pipe through python or write to a temp file then grep).',
  '- Do NOT trust local *.cls under Data/sc-maint/src or force-app unless you confirm it matches the live org body; these drift.',
  '',
  'Original review file: "*Jira/Task/sc3403 | Peer Review - SC-3346 Maintenance (Derived) Pricing/02_BLOCKERS_AND_DEFECTS.md".',
  '',
  'status meanings: RESOLVED = live state proves fixed; NOT_RESOLVED = defect still present live; PARTIAL = some sub-claims fixed; CANNOT_VERIFY = blocked, say exactly why. Cite concrete live values. Return exactly one VERDICT object.',
  '',
].join('\n')

const TASKS = [
  {
    id: 'B-4', label: 'B-4 renewal carry-forward',
    task: [
      'FINDING B-4 (BLOCKER): Renewal carry-forward broken. Renewal maintenance priced E2E only once (order 00095475 / 801WC00000kaGBpYAM); Prior_Partner_Discount__c and Prior_Discretionary_Discount__c were NOT persisted (null), UnitPrice=0; and the renewal formula IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (Base_Price__c - Prior_Partner_Discount__c - Prior_Discretionary_Discount__c) * (1+COLA_Uplift_Percent__c/100)) had NO IsNull guard on operands, so a Year-3 renewal reading null priors mis-prices.',
      'VERIFY (RESOLVED requires all three):',
      '1. In the V12 ACTIVE block (lines 64829-70445) of the retrieved procedure, locate the renewal formula (grep that range for COLACalculatedPrice__c, Prior_Partner_Discount__c, DerivedPricingRenewals). Does it now have IsNull/BLANKVALUE/NULLVALUE guards on Base_Price__c / Prior_Partner_Discount__c / Prior_Discretionary_Discount__c? Quote the exact formula <value>.',
      '2. Query the original renewal order maintenance line: sf data query --target-org FortraUAT -q "SELECT Id, Product2.Name, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, UnitPrice, TotalPrice FROM OrderItem WHERE OrderId=\'801WC00000kaGBpYAM\'" --json . Are the two prior-discount fields now populated and UnitPrice non-zero?',
      '3. Look for NEWER renewal-maintenance lines created after the review: sf data query --target-org FortraUAT -q "SELECT Id, OrderId, Order.OrderNumber, Product2.Name, Base_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, UnitPrice, TotalPrice, CreatedDate FROM OrderItem WHERE Product2.Name LIKE \'%RRM%\' AND CreatedDate>2026-06-11T00:00:00Z ORDER BY CreatedDate DESC LIMIT 25" --json .',
      'RESOLVED only if the active formula has null-guards AND at least one real renewal order persists all three components with a committed non-zero unit net.',
    ].join('\n'),
  },
  {
    id: 'B-5', label: 'B-5 decision-table refresh',
    task: [
      'FINDING B-5 (BLOCKER): Asset_Action_Source_Entries_Decision_Table_V2 (0lDa50000007BJhEAM) Status=Active but RefreshStatus=Failed, LastSyncDate=null, reason "Hash Key Group contains more than 200 rows" (AssetActionSource ~430,329 rows). This IS the "renewing both assets fails before a quote" blocker.',
      'VERIFY: sf data query --target-org FortraUAT -q "SELECT Id, DeveloperName, Status, RefreshStatus, RefreshFailureReason, LastSyncDate FROM DecisionTable WHERE DeveloperName=\'Asset_Action_Source_Entries_Decision_Table_V2\'" --json',
      'Also current row count: sf data query --target-org FortraUAT -q "SELECT COUNT() FROM AssetActionSource".',
      'RESOLVED only if RefreshStatus=Completed with a recent LastSyncDate. Report live RefreshStatus, RefreshFailureReason, LastSyncDate verbatim.',
    ].join('\n'),
  },
  {
    id: 'B-6', label: 'B-6 decomposition persistence',
    task: [
      'FINDING B-6 (BLOCKER): Step-5 decomposition persisted inconsistently. Some orders carry the LICENSE base (e.g. 355) on the maintenance OrderItem.Base_Price__c instead of the maintenance base, because MaintenanceOrderDecompositionService.persistPatches/buildPatches did not run/overwrite on every Quote-to-Order. Renewal then reads OrderItem.Base_Price__c and carries the license base forward (~5x overprice).',
      'VERIFY:',
      '1. Live class body: query Body of MaintenanceOrderDecompositionService via Tooling API. Confirm whether buildPatches/persistPatches now run UNCONDITIONALLY on Q2O and overwrite Base_Price__c (find where Base_Price__c = decomp.maintenanceBase is set, and the guard/branch around it). Quote the control flow.',
      '2. Live data leakage hunt: sf data query --target-org FortraUAT -q "SELECT Id, OrderId, Product2.Name, Base_Price__c, Fortra_Product_Type__c, CreatedDate FROM OrderItem WHERE Base_Price__c=355 AND Fortra_Product_Type__c LIKE \'%Maintenance%\' ORDER BY CreatedDate DESC LIMIT 25" --json . Also check maintenance lines created after 2026-06-11 for any Base_Price__c equal to a plausible license base. Report leakage rows (or none).',
      'RESOLVED only if the service deterministically overwrites Base_Price__c AND no maintenance OrderItem created after the review carries a license base.',
    ].join('\n'),
  },
  {
    id: 'M-1', label: 'M-1 no-prehook principle',
    task: [
      'FINDING M-1 (MAJOR): The SDD "no Apex pricing prehook; one Flow only" principle is false as built. COLAUpliftPrehook and PartnerNetPricePosthook both implement RevSignaling.SignalingApexProcessor and write net; per SC-3350 the prehook seed is the only lever that commits net on non-derived renewal lines, so the prehook is NECESSARY. "Fixed" means either the prehooks were genuinely removed, OR the SDD/HANDOFF was reconciled to admit the prehook stack.',
      'VERIFY:',
      '1. Do both prehooks still exist and implement the interface? Query LengthWithoutComments + Body for COLAUpliftPrehook and PartnerNetPricePosthook; grep bodies for "implements RevSignaling.SignalingApexProcessor".',
      '2. Was the doc reconciled? Search the repo for FORTRA-Maintenance-Derived-Pricing-HANDOFF-NOTES.md and the SDD; check for language admitting the prehook stack. Read M-1 in 02_BLOCKERS_AND_DEFECTS.md.',
      'Decide: code change (prehooks removed) vs doc reconciliation vs neither. If prehooks still present + necessary AND SDD still claims "no prehook" => NOT_RESOLVED; if doc updated to admit them => PARTIAL/RESOLVED. State which.',
    ].join('\n'),
  },
  {
    id: 'M-2', label: 'M-2 competing formulas',
    task: [
      'FINDING M-2 (MAJOR): Two competing new-business formulas existed in the active version: a tier IF-expression times Source_List_Price__c writing NetUnitPrice, AND a DerivedPricingNewBusiness formula (Base_Price__c * tier) also writing NetUnitPrice, with one overwriting the other only when its filter passes -> divergent inputs/prices; SDD documents only one.',
      'VERIFY against the V12 ACTIVE block (lines 64829-70445) of the retrieved procedure file:',
      '- grep that line range for every formula element that WRITES NetUnitPrice for new business. Look for: Base_Price__c, Source_List_Price__c, Attribute_Multiplier_Pct__c, DerivedPricingNewBusiness, and tier IF-expressions. NOTE the live formula now appears to read "Base_Price__c * Attribute_Multiplier_Pct__c" (changed since the review).',
      '- Quote EACH new-business NetUnitPrice-writing formula element found, with its <value>, its gate/filter, and its sequence. Determine whether V12 now has exactly ONE unambiguous new-business formula path, or still multiple competing ones.',
      'RESOLVED only if there is a single, unambiguous new-business formula writing NetUnitPrice on derived lines in the active version.',
    ].join('\n'),
  },
  {
    id: 'M-4', label: 'M-4 Source_List_Price mapping',
    task: [
      'FINDING M-4 (MAJOR): QuoteToOrderFieldMapper has the Source_List_Price__c QLI->OrderItem propagation commented-out/DISABLED, while other carry-forward fields are mapped; tied to a "Unable to fetch tags: [Source_List_Price__c]" reprice error. NOTE there are TWO divergent copies in the repo: force-app (a Bill/Ship mapper, NO Source_List_Price__c) vs Data/sc-maint/src (maintenance build with the disabled block). The review mislabeled the location as "in force-app".',
      'VERIFY which class is actually DEPLOYED live and its state: query Name, LengthWithoutComments, Body for QuoteToOrderFieldMapper via Tooling API on FortraUAT.',
      '- Does the LIVE deployed body contain Source_List_Price__c at all? Is the mapping active code or still a commented-out/disabled block? Is the deployed class the Bill/Ship variant or the maintenance variant? Quote the relevant lines from the live body.',
      'RESOLVED only if the live class has a single coherent source-of-truth for Source_List_Price__c (correctly mapped, OR intentionally flow-owned with NO dangling disabled code and no reprice tag error).',
    ].join('\n'),
  },
  {
    id: 'M-5', label: 'M-5 derived PBE config',
    task: [
      'FINDING M-5 (MAJOR): Of 4 derived RRM/RNM PriceBookEntries, only 2 (01uWC000005wsbUYAQ RNM-Fortra, 01uWC000005wsbVYAQ RRM-Fortra/TermDefined) had PriceBookEntryDerivedPrice config; 01uWC000006XPNZYA4 (RRM Standard) and 01uWC000006XPPBYA4 (RRM Fortra/OneTime) had none, so native DerivedPricingDataRetrieval hard-errors "contributing products are missing" if reachable (SC-3372 risk).',
      'VERIFY:',
      '1. sf data query --target-org FortraUAT -q "SELECT Id, PricebookEntryId, Formula, ContributingProductId FROM PriceBookEntryDerivedPrice WHERE PricebookEntryId IN (\'01uWC000005wsbUYAQ\',\'01uWC000005wsbVYAQ\',\'01uWC000006XPNZYA4\',\'01uWC000006XPPBYA4\')" --json',
      '2. Describe the 4 PBEs: sf data query --target-org FortraUAT -q "SELECT Id, Product2.Name, Pricebook2.Name, IsActive FROM PricebookEntry WHERE Id IN (\'01uWC000005wsbUYAQ\',\'01uWC000005wsbVYAQ\',\'01uWC000006XPNZYA4\',\'01uWC000006XPPBYA4\')" --json',
      'RESOLVED only if all reachable PBEs now have PriceBookEntryDerivedPrice config, OR the 2 previously-uncovered ones are now inactive/unreachable. Report which of the 4 now have PBEDP rows and which are active.',
    ].join('\n'),
  },
  {
    id: 'M-6', label: 'M-6 prod prehook stale',
    task: [
      'FINDING M-6 (MAJOR): COLAUpliftPrehook prod copy is stale vs UAT: prod LengthWithoutComments=39,956 vs UAT 43,272 (~3,316 delta); prod runs an older prehook lacking the renewal-maintenance COLA logic. Neither in force-app.',
      'VERIFY (two orgs):',
      'sf data query --target-org FortraUAT --use-tooling-api -q "SELECT Name, LengthWithoutComments FROM ApexClass WHERE Name=\'COLAUpliftPrehook\'" --json',
      'sf data query --target-org FortraProd --use-tooling-api -q "SELECT Name, LengthWithoutComments FROM ApexClass WHERE Name=\'COLAUpliftPrehook\'" --json',
      'Report both lengths. RESOLVED only if prod now matches UAT (or the renewal-maintenance COLA logic is confirmed present in prod).',
      'IMPORTANT nuance: the SC-3346 work is UAT-only and prod deploys require explicit authorization per project policy. If prod is still behind, that may be CORRECT (deploy intentionally pending) rather than a defect — state that nuance in residual_risk, but status reflects the literal live comparison.',
    ].join('\n'),
  },
]

phase('Verify')
const results = await parallel(
  TASKS.map((t) => () => agent(PRE + '\n\n' + t.task, { label: t.label, phase: 'Verify', schema: VERDICT }))
)

return results.filter(Boolean)
