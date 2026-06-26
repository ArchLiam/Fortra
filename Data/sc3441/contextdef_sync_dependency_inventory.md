# SC-3441 — Context Definition Sync Dependency Inventory (LIVE, read-only)

Org: FortraUAT (00DWC000006eUFF2A2). Captured 2026-06-25 (evening), all read-only.
Context to Sync: **SalesTransactionContextExt_v2**

## 1. ContextDefinition + version
| Item | Id | Notes |
|---|---|---|
| ContextDefinition (record) | `11OWC000002m21Z2AQ` | DeveloperName=SalesTransactionContextExt_v2. NOTE: prompt called this a "version" — it is the CD record itself. |
| ACTIVE runtime version | `11pWC000002TjF7YAK` | VersionNumber **23**, IsActive=true, StartDate 2026-05-29. ONLY active version (clean, single-active). |

Field `CancelNetUnitPrice__c` IS mapped into this active version on both line nodes:
- QuoteEntitiesMapping `11jWC0000064MRWYA2` → ContextNodeMapping `11bWC00000346zPYAQ` (Object=QuoteLineItem) → ContextAttributeMapping `11RWC000003q47R2AQ` → ContextAttribute `11nWC0000D9vxSXYQY`
- OrderEntitiesMapping `11jWC0000064MRYYA2` → ContextNodeMapping `11bWC00000346y9YAA` (Object=OrderItem) → ContextAttributeMapping `11RWC000003q47S2AQ` → same ContextAttribute `11nWC0000D9vxSXYQY`

Design-time mapping is present on both nodes; the Sync regenerates the compiled runtime hydration.

## 2. ExpressionSetDefinitions binding to this context (deactivate before Sync / reactivate after)
Binding key = `Metadata.contextDefinitions` on each ExpressionSetDefinition. EXACTLY TWO bind to v2:

| Procedure | ESDef Id | ExpressionSet Id | active design ver (ESDV) | active runtime ver (ESV) | flag |
|---|---|---|---|---|---|
| Rev_Mgmt_Default_Pricing_Procedure (PricingProcedure) | `9QAWC0000003mg14AA` | `9QLWC0000015cDl4AI` | **MULTI-ACTIVE: V16 `9QBWC0000000niH4AQ` AND V18 `9QBWC0000000o3F4AQ`** | **V16 `9QMWC00000024PJ4AY` AND V18 `9QMWC00000024p74AA`** | deactivate both; reactivate ONLY what was active pre-sync |
| Salesforce_Default_Pricing_Discovery_Procedure_v2 (DiscoveryProcedure) | `9QAWC000000C8mb4AC` | `9QLWC000003ae0P4AQ` | V1 `9QBWC0000000mW54AI` | V1 `9QMWC000000227N4AQ` (rank 1) | deactivate before sync; reactivate V1 after |

The other 3 ExpressionSetDefinitions bind to DIFFERENT contexts (NOT affected by a v2 Sync):
- Product_Discovery_Pricing_Procedure → ProductDiscoveryContextExt
- Salesforce_Default_Pricing_Discovery_Procedure → SalesTransactionContextExt
- Salesforce_Pricing_Discovery_Procedure → SalesTransactionContextExt

## 3. Rule Libraries — NONE currently active on v2 (do NOT need deactivation)
| RuleLibrary | Id | active version | binds to | blocks v2 sync? |
|---|---|---|---|---|
| Rule Library for Configurator | `9QsWC0000001Re50AE` | V4 `9Q1WC0000000Em90AE` (Active) | **SalesTransactionContextExt** (not v2) | NO |
| (same) inactive V3 | — | V3 `9Q1WC0000000EkX0AU` (Inactive) | SalesTransactionContextExt_v2 | inactive, no |
| DRORuleLibrary | `9QsWC0000001Rsb0AE` | DRORuleLibrary_v1 `9Q1WC0000000CHJ0A2` (Active) | **SalesTransactionContext__stdctx** (not v2) | NO |

CORRECTION to prompt: neither active rule-library version currently binds to v2. The active config rule lib is V4 bound to `SalesTransactionContextExt` (non-v2). V4's predecessor V3 was the v2 binder but is inactive.

## 4. DecisionTable / CalculationMatrix — NOT context dependencies
Neither object has a ContextDefinition binding field. They are referenced by procedure steps (UsageType=DefaultPricing etc.), not bound to the context. They do NOT block a context Sync. (23 DecisionTables / 21 CalculationMatrices exist; downstream of the procedure, not of the context.)

## CRITICAL LIVE-STATE FINDINGS (vs prompt premise)
1. **The active pricing procedure is NOT V18.** At session start only V16 was active; by re-query V18 had ALSO been activated (LastModified 2026-06-26T04:03Z). The procedure is now in a **MULTI-ACTIVE state (V16 + V18 both Active, same StartDateTime 2026-06-18, null Rank)** — ambiguous version selection. This must be resolved (deactivate one) before/independent of the Sync.
2. The CancelNetSeed logic exists ONLY in V18 (5 CancelNetUnitPrice refs); V16 has ZERO CancelNet refs but does contain StampBaseFilter (the SF-BRE-00004 site). If RLM resolves to V16, the seed never runs regardless of context hydration.

## SYNC DEACTIVATE/REACTIVATE LIST (the two binders only)
Deactivate before Sync, then reactivate EXACTLY these (whatever is active at sync time):
- Rev_Mgmt_Default_Pricing_Procedure: V16 `9QBWC0000000niH4AQ` and/or V18 `9QBWC0000000o3F4AQ` (record the live active set immediately before sync; reactivate the SAME set — but FIRST resolve the multi-active to a single intended version)
- Salesforce_Default_Pricing_Discovery_Procedure_v2: V1 `9QBWC0000000mW54AI`

Do NOT use "Reactivate All" / reactivateDependencies(null).
