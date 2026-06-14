export const meta = {
  name: 'rca-e2e-test',
  description: 'Exhaustive end-to-end test of the RCA (Revenue Cloud) implementation in FortraUAT: every sObject cluster + standard/custom actions',
  phases: [
    { title: 'Test', detail: '8 lifecycle clusters in parallel — CRUD + actions + verify' },
    { title: 'Synthesize', detail: 'master coverage matrix + defects + verdict' },
  ],
}

const COV = {
  type: 'object', additionalProperties: false,
  required: ['cluster', 'sobject_coverage', 'action_coverage', 'records_created', 'defects', 'needs_ui', 'summary'],
  properties: {
    cluster: { type: 'string' },
    sobject_coverage: { type: 'string', description: 'one row per sObject: Name | count | createable/updateable | CREATE result | EDIT result | READ result | notes' },
    action_coverage: { type: 'string', description: 'one row per action: Action | mechanism tried | result (PASS/FAIL/BLOCKED) | evidence' },
    records_created: { type: 'string', description: 'tagged record Ids created this run (for traceability; nothing deleted)' },
    defects: { type: 'string', description: 'anything broken/unexpected/inconsistent found, with evidence (or NONE)' },
    needs_ui: { type: 'string', description: 'sObjects/actions not API-testable (UI/managed/integration-gated) + why' },
    summary: { type: 'string' },
  },
}

const SAFE = [
  'ORG: FortraUAT — every sf command MUST pass --target-org FortraUAT.',
  'HARD RULES (never violate):',
  '1. NEVER DELETE any record (no `sf data delete`, no DML delete, no purge). Create/edit only.',
  '2. TAG every record you create with the marker ZZ_E2E_RCA_20260613 in a Name/Description/Label-type field so it is traceable.',
  '3. Only EDIT records you created in THIS test (or obvious prior ZZ_E2E_ test records). Do NOT edit live business records or live config.',
  '4. Do NOT activate/deactivate or modify any ExpressionSet / ExpressionSetVersion / DecisionTable / ContextDefinition / pricing procedure — those are tested READ-ONLY + via the pricing action only (editing them is out of scope and dangerous).',
  '5. NO EXTERNAL SIDE-EFFECTS: do NOT activate Orders, do NOT publish Order_Completed_*/completion events, do NOT trigger Workday/MuleSoft/Tax-engine external calls. Keep test Orders in Draft. Test the RCA internal lifecycle up to (not through) external integration triggers; mark those BLOCKED/needs_ui.',
  '6. Prefer creating NEW tagged test records over touching existing ones. Reuse the BoKS IAM Test Account / test contracts where a parent is needed.',
  '',
  'METHOD per sObject: run `sf sobject describe --sobject NAME --target-org FortraUAT` -> note createable/updateable + required fields + record count (SELECT COUNT()). If createable AND safe (not platform-managed, no external trigger), create ONE minimal valid tagged record, EDIT one field, re-read to confirm (NO delete). If not createable (platform-managed/read-only), verify READ works and mark read-only. Capture concrete Ids/values as evidence.',
  'METHOD per action: attempt via the best API mechanism; if UI-only/managed, describe the exact procedure + verify via EXISTING records (do not fire external integrations). Report PASS/FAIL/BLOCKED with evidence.',
  'Be exhaustive within your cluster. Return the structured coverage object.',
].join('\n')

const CLUSTERS = [
  { label: 'catalog-product', task:
    'CLUSTER = CATALOG & PRODUCT. sObjects: Product2, ProductCatalog, ProductCategory, ProductCategoryProduct, ProductCategoryQualification, ProductCategoryDisqual, ProductClassification, ProductClassificationAttr, ProductSellingModel, ProductSellingModelOption, ProductComponentGroup, ProductComponentGrpOverride, ProductRelatedComponent, ProductRelComponentOverride, ProductConfigurationRule, ProductConfigurationFlow, ProductConfigFlowAssignment, ProductQualification, ProductDisqualification, ProductRampSegment, ProductEntitlementTemplate, ProductSpecificationType, ProductSpecificationRecType, ProductRelationshipType, ProductRelatedMaterial, ProductDecompEnrichmentRule, ProductFulfillmentScenario, ProductFulfillmentDecompRule. ACTIONS: product create + add to catalog/category; bundle structure (component group + related component); configuration-rule existence/validity. Test CRUD per the method; verify a real configurable bundle exists and its component graph is coherent.' },
  { label: 'attributes-adjustments', task:
    'CLUSTER = ATTRIBUTES & ADJUSTMENTS. sObjects: AttributeDefinition, AttributeCategory, AttributeCategoryAttribute, AttributePicklist, AttributePicklistValue, ProductAttributeDefinition, AttributeBasedAdjustment, AttributeBasedAdjRule, AttributeAdjustmentCondition, BundleBasedAdjustment, Attribute_Tier_Pricing_Storage__c. ACTIONS: define an attribute + picklist + assign to a product (ProductAttributeDefinition); verify an AttributeBasedAdjustment row + its rule resolve. Test CRUD per the method. Verify ABA data integrity (e.g., currency coverage, a sample adjustment maps to a real product).' },
  { label: 'pricing-config-engine', task:
    'CLUSTER = PRICING CONFIG & ENGINE (mostly READ + action-verify; do NOT edit/activate any of these). sObjects: Pricebook2, PricebookEntry, PriceBookEntryDerivedPrice, PriceAdjustmentSchedule, PriceAdjustmentTier, ExpressionSet, ExpressionSetDefinition, ExpressionSetVersion, DecisionTable, DecisionTableParameter, DecisionTableDataset, DecisionTableDatasetLink, ContextDefinition, ContextDefinitionVersion, ExpressionSetObjectAlias. CRUD-test ONLY the safe ones (Pricebook2, PricebookEntry, PriceBookEntryDerivedPrice, PriceAdjustmentSchedule/Tier — create a tagged test PBE on a test product). For ExpressionSet/DecisionTable/ContextDefinition: READ-ONLY (counts, active versions, RefreshStatus per DecisionTable, sync state). ACTION: report the active pricing procedure version + each DecisionTable RefreshStatus (flag any Failed) + each ContextDefinition active version. Note: known Failed table = Asset_Action_Source_Entries_Decision_Table_V2.' },
  { label: 'quote-configurator-pricing', task:
    'CLUSTER = QUOTE + CONFIGURATOR + PRICING ACTION (the core engine test). sObjects: Quote, QuoteLineItem, QuoteLineItemAttribute, QuoteLineGroup, QuoteLineDetail, QuoteLinePriceAdjustment, QuoteLineRelationship, QuoteAction, QuoteDocument, QuoteRecipientGroup, QuoteRecipientGroupMember, QuoteLineItemRecipient. ACTIONS (the most important): create a NEW tagged Draft Quote on the BoKS IAM Test Account; add a QuoteLineItem for a real priceable Product2 (use a Pricebook2 + PricebookEntry that exists); run the PRICING action (Reprice / the managed PlaceQuote or quote-save reprice) and verify NetUnitPrice/Subtotal compute; add/verify a QuoteLineItemAttribute (configurator). If the managed Reprice cannot be invoked headlessly, document the exact API/UI mechanism and verify pricing on an EXISTING tagged/test quote. Report whether pricing produces correct non-zero values. Do NOT convert/activate.' },
  { label: 'order-convert', task:
    'CLUSTER = ORDER + CONVERT. sObjects: Order, OrderItem, OrderItemAttribute, OrderItemGroup, OrderItemDetail, OrderAction, OrderItemAdjustmentLineItem, OrderItemRelationship, OrderDeliveryGroup, OrderDeliveryMethod, OrderItemRecipient, OrderAdjustmentGroup. ACTIONS: create a NEW tagged Draft Order (do NOT activate, do NOT fire completion/Workday); add an OrderItem + OrderItemAttribute; verify the Convert-Quote-to-Order mechanism (describe the QuoteAction/managed convert; verify on an EXISTING converted quote->order chain that OrderItems mirror QuoteLineItems). CRUD-test the order sObjects per the method. Mark activation + Workday completion BLOCKED (external side-effects).' },
  { label: 'asset-contract', task:
    'CLUSTER = ASSET + CONTRACT + LIFECYCLE ACTIONS. sObjects: Asset, AssetAction, AssetActionSource, AssetContractRelationship, AssetStatePeriod, AssetStatePeriodAttribute, AssetRelationship, AssetFulfillmentDecomp, Contract, ContractLineItem, ContractItemPrice, ContractItemPriceAdjTier, ContractContactRole, ContractType, ContractTypeConfig, ContractStatus. Most Asset/AssetAction/AssetActionSource are platform-managed (READ-ONLY — verify reads + relationships). CRUD-test the safe ones (Contract, ContractContactRole, a tagged Asset if createable). ACTIONS: verify the asset lifecycle (renew/amend/cancel) mechanism — describe how renewal is triggered (Managed Assets -> Renew) and VERIFY on the existing test contract 800WC00000S5ub1YAB (#00069255) that renewing produced a coherent quote->asset chain; confirm AssetContractRelationship links assets to contracts. Do NOT initiate new renewals that fire external sync.' },
  { label: 'billing-tax-usage', task:
    'CLUSTER = BILLING + TAX + USAGE. sObjects: BillingSchedule, BillingScheduleGroup, TaxEngine, TaxEngineProvider, TaxPolicy, TaxRate, TaxTreatment, TaxTreatmentItem, UsageResource, UsageResourcePolicy, UsageResourceBillingPolicy, UsageCommitmentPolicy, UsageOveragePolicy, UsageGrantRenewalPolicy, UsageGrantRolloverPolicy, ProductUsageResource, ProductUsageResourcePolicy, ProductUsageGrant, SalesTransactionType, SalesTransactionFulfillReq, RevenueAsyncOperation, RevenueTransactionErrorLog. Mostly READ + safe CRUD (TaxRate/TaxTreatment/TaxPolicy/Usage policies if createable). ACTIONS: verify BillingSchedule generation exists (read existing 2347 schedules + relationships); verify Tax config (engine/provider/policy/rate) is present; DO NOT call the external Tax engine. Report RevenueTransactionErrorLog recent entries (a health signal).' },
  { label: 'custom-fortra-layer', task:
    'CLUSTER = CUSTOM FORTRA LAYER (custom objects + custom actions). Custom sObjects: Attribute_Tier_Pricing_Storage__c, ProductDescription__c, Product_Assignment__c, Product_of_Interest__c, Sales_Territory__c (+ any other __c in the pricing/quote/order domain you find via `sf sobject list`). CUSTOM ACTIONS: enumerate the Fortra Apex pricing classes that participate (SignalingApexProcessor prehooks/posthooks: COLAUpliftPrehook, PartnerNetPricePosthook, PartnerPricingPrehook, RegionalServicesPricingPrehook, AttributeVolumePricingPrehook, HardwareAttributePricingPrehook; + OrderRepriceInvocable, MaintenanceOrderDecompositionService, RenewalMaintenancePricingService, QuoteToOrderFieldMapper) and the record-triggered Flows on Quote/QuoteLineItem/Order/OrderItem (e.g. Stamp_Maintenance_Pricing_Inputs, Fortra_OrderItem_Set_*). For each: confirm it exists/active (ApexClass + FlowDefinitionView via tooling), its trigger context, and recent test-coverage/health. CRUD-test the safe custom objects per the method. Report which custom actions are wired into the live pricing path.' },
]

phase('Test')
const results = await parallel(CLUSTERS.map((c) => () => agent(SAFE + '\n\n' + c.task, { label: c.label, phase: 'Test', schema: COV })))

phase('Synthesize')
const valid = results.filter(Boolean)
const report = await agent(
  'You are consolidating an exhaustive RCA end-to-end test of FortraUAT into a final QA report. Here are the 8 cluster results:\n\n' +
  valid.map((r) => '=== ' + r.cluster + ' ===\nSOBJECTS:\n' + r.sobject_coverage + '\nACTIONS:\n' + r.action_coverage + '\nDEFECTS: ' + r.defects + '\nNEEDS_UI: ' + r.needs_ui + '\nCREATED: ' + r.records_created + '\nSUMMARY: ' + r.summary).join('\n\n') +
  '\n\nProduce: (1) COVERAGE_MATRIX — a consolidated count of RCA sObjects tested with C/E/R (created/edited/read) outcomes + how many were read-only/managed; (2) ACTIONS — every RCA action (standard + custom) with PASS/FAIL/BLOCKED and the reason; (3) DEFECTS — every real defect/inconsistency found, ranked by severity, with evidence; (4) BLOCKED/UI-ONLY — what could not be API-tested and why (managed/UI/external-integration); (5) VERDICT — overall health of the RCA implementation + the top risks. Be concrete and cite the cluster evidence.',
  { label: 'synthesize', phase: 'Synthesize',
    schema: { type: 'object', additionalProperties: false, required: ['coverage_matrix', 'actions', 'defects', 'blocked_ui', 'verdict'],
      properties: { coverage_matrix: { type: 'string' }, actions: { type: 'string' }, defects: { type: 'string' }, blocked_ui: { type: 'string' }, verdict: { type: 'string' } } } }
)

return { clusters: valid, report }
