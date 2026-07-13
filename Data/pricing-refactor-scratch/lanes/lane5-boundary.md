# LANE 5 — BOUNDARY INTERFACE CATALOG (read-only I/O contracts)

Scope: for each in-scope hook/service, the explicit I/O contract with every BOUNDARY artifact
(config MDT / custom-object storage / PBE tooling / flow / discovery procedure). Map only — never
propose boundary changes. Evidence surface = `Data/pricing-refactor-scratch/live-classes/<Name>.cls:<line>`
(force-app copies MATCH live as of 2026-07-06). All findings numbered BC-n.

Tag legend: CONFIRMED = verified in evidence this run · CORRECTED = prior claim proven wrong ·
UNVERIFIED = carried, not read-only-verifiable.

---

## PART A — CONFIG MDT INTERFACES (map as interface; never refactor the MDT)

### BC-1 · COLA_Uplift_Rules__mdt  (CONFIRMED)
The COLA per-Solution-Category default-uplift decision table. Two independent readers with an
IDENTICAL query (duplicated selector — refactor candidate but the MDT contract is one interface).

| Reader | READS (object.fields + filter) | WRITES | file:line |
|---|---|---|---|
| COLAUpliftHandler | `COLA_Uplift_Rules__mdt`: MasterLabel, Solution_Category__c, Default_Uplift_Percent__c, Is_Active__c, Effective_Start_Date__c, Effective_End_Date__c, Description__c · WHERE Is_Active__c=true | — (in-memory map keyed by Solution_Category__c) | COLAUpliftHandler.cls:378-384 |
| COLAUpliftPrehook | same 7 fields, same WHERE Is_Active__c=true | — | COLAUpliftPrehook.cls:867-870 |

Lookup key = `qli.COLA_Solution_Category__c` → rule (COLAUpliftHandler.cls:130, :189, :317;
COLAUpliftPrehook.cls:355). Handler WRITES the resolved % back onto the QLI:
`qli.COLA_Uplift_Percent__c` and `qli.Default_COLA_Uplift_Percent__c` (COLAUpliftHandler.cls:133-134).

### BC-2 · MyCAP_Rules__mdt  (CONFIRMED)
Singleton (`getInstance('Global')`) governing COLA out-year uplift eligibility. NOT in the lane-5
target list but co-resident in the COLA path — mapped because it is a config decision boundary.

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| COLAUpliftHandler | `MyCAP_Rules__mdt.getInstance('Global')`: Is_Active__c, Default_Out_Year_Uplift_Percent__c | `qli.COLA_Outyear_Uplift_Percent__c` (fallback literal `3` when field null) | COLAUpliftHandler.cls:151, :174, :153-154 |
| COLAUpliftPrehook | passed as `MyCAP_Rules__mdt mycapRule` (getInstance('Global') at :85) into processLineItems/processMyCAPEligibility | — | COLAUpliftPrehook.cls:85, :168, :1068, :1081 |

HARDCODE note (minor): out-year default fallback literal `3` (%) at COLAUpliftHandler.cls:154 when
`Default_Out_Year_Uplift_Percent__c` is null — should be an MDT default, not inline. See BC-13.

### BC-3 · Maintenance_Rate__mdt  (CONFIRMED — CORRECTS "inline 7-tier rates" suspicion)
Maintenance-tier → decimal rate decision table. Rates are MDT-sourced, NOT hardcoded in Apex.
Two readers, each with its own duplicated loader (same query text).

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| MaintenanceOrderDecompositionService | `Maintenance_Rate__mdt`: MaintenanceType__c, Rate__c (no WHERE — all rows) → `maintenanceRateByTier()` cache | — | MaintenanceOrderDecompositionService.cls:622-623 |
| PartnerNetPricePosthook | `Maintenance_Rate__mdt`: MaintenanceType__c, Rate__c (no WHERE) → `loadMaintenanceRates()` | derived NewMaint ListPrice/net stamped on QLI/OrderItem (resolveTierRate → resolveDerivedMaintenanceListPrice) | PartnerNetPricePosthook.cls:1988-1992, resolve @ :1980-1992, :2504, :2530-2541 |

Tier key origin = the `Maintenance Type Defn` attribute value (MaintenanceOrderDecompositionService.cls:13
`MAINTENANCE_TIER_ATTRIBUTE`), joined via QuoteLineItemAttribute/OrderItemAttribute
(PartnerNetPricePosthook.cls:1356-1368 QLI path, :1410-1422 OrderItem path). The "7-tier vs 3-tier"
derived-pricing distinction is an ESD-formula concern (KEY FACT 9, ACTIVE V21 description "Derived
Pricing Formula reverted to 3-tier"), NOT Apex — see BC-12.

### BC-4 · Services_Regional_Pricing__mdt  (CONFIRMED)
Country/country-code → multiplier table for regional services pricing.

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| RegionalServicesPricingPrehook | `Services_Regional_Pricing__mdt`: Country__c, Country_Code__c, Multiplier__c · WHERE Is_Active__c=true → map keyed by BOTH Country__c and Country_Code__c | multiplier applied to LIST price only; net stays catalog (per MEMORY regional mechanism) — stamped to OrderItem.RegionalNetUnitPrice__c / Quote PrehookRSNetUnitPrice__c·Pre_Regional_Price__c | RegionalServicesPricingPrehook.cls:89-100 |

Default when country blank/unmatched = `DEFAULT_MULTIPLIER` (1.0) — RegionalServicesPricingPrehook.cls:111-115.
This 1.0 default is a defined constant, acceptable (not a hardcode defect).

### BC-5 · Currency_Conversion_Formula__mdt  (CONFIRMED — CORRECTS "0.9346 FX literal in Apex")
The currency-conversion decision table. Formula is stored as a STRING expression (e.g. `* 0.92`) OR a
`Conversion_Rate__c` decimal — both live in the MDT, NOT hardcoded in Apex. `0.9346` does NOT appear
in any live class (grep negative). The only inline FX-ish literal in the class family is the string
example `"* 0.92"` inside doc-comments (Fortra_CurrencyConversionService.cls:10, :97, :99) — documentation, not runtime.

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| Fortra_CurrencyConversionService | `Currency_Conversion_Formula__mdt`: MasterLabel, DeveloperName, ISO_Code__c, Conversion_Formula__c, Conversion_Rate__c, Is_Active__c, Description__c · WHERE Is_Active__c=true → cache keyed by ISO_Code__c.toUpperCase() | — (pure calc service) | Fortra_CurrencyConversionService.cls:31-40 |

Resolution precedence (Fortra_CurrencyConversionService.cls:81-91): `Conversion_Rate__c` (decimal
multiply) wins; else parse `Conversion_Formula__c` string via `applyFormula` (a mini expression
interpreter supporting `* / + -`, first-char operator, HALF_UP scale 2 — :102-149). Consumers per
class header: Fortra_BulkPriceUpdateBatch + Flow single-product update (Fortra_CurrencyConversionService.cls:6-8).
**Latent hazard:** `applyFormula` is a homegrown string-formula evaluator — the "config" is executable
text, so the MDT is a code surface, not just data. Map as interface but flag for the refactor plan.

### BC-6 · QL_Description_Attribute__mdt  (CONFIRMED)
Config table driving QuoteLineItem.Description assembly (segment order / roles). Config-with-fallback
pattern: when zero active rows exist, code falls back to the in-code `defaultConfig()` (BC-11).

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| QLDescriptionGeneratorPrehook | `QL_Description_Attribute__mdt`: Attribute_API_Name__c, Role__c, Sort_Order__c, Match_Value__c (queryActiveConfig, active rows) | writes assembled text to context attr `SalesTrxnItemDescription` → hydrates QuoteLineItem.Description | QLDescriptionGeneratorPrehook.cls:225-228, buildResolvedConfig :240-262, write-back :169/:771 |

Test seam: `configOverride` static (QLDescriptionGeneratorPrehook.cls:177) substitutes the SOQL.

### BC-7 · Attribute_Tier_Pricing_Storage__c  (custom OBJECT, not MDT)  (CONFIRMED)
Attribute-volume tiered-pricing storage. This is a data object queried at runtime (bulk SOQL), read as
a boundary interface by the attribute-volume prehook.

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| AttributeVolumePricingPrehook | `Attribute_Tier_Pricing_Storage__c`: Id, Product__c, Product_Selling_Model__c, Attribute_Name__c, Attribute_Value__c, Lower_Bound__c, Upper_Bound__c, Tier_Value__c, Multiplier__c, Price_Mode__c · WHERE Product__c IN :productIds AND Product_Selling_Model__c IN :psmIds | — (builds tier lookup map keyed Product__c+PSM+Attribute_Name__c) | AttributeVolumePricingPrehook.cls:211-219, buildTierLookupMap :331-341, apply :379-417 |

Eligibility gate before query = `Has_Attribute_Adjustment__c` (AttributeVolumePricingPrehook.cls:156).
Early-return when no rows (AttributeVolumePricingPrehook.cls:225).

### BC-8 · QuoteMigration config MDTs (out-of-primary-scope, co-resident)  (CONFIRMED)
QuoteMigrationService reads two additional config MDTs. Mapped as interfaces; not a pricing hook.

| Reader | READS | WRITES | file:line |
|---|---|---|---|
| QuoteMigrationService | `Migration_Field_Default__mdt`: Target_Object__c, Target_Field__c, Default_Value__c (+ active filter) | applies defaults to migrated records | QuoteMigrationService.cls:265-272 |
| QuoteMigrationService | `Operations_Checklist_Config__mdt`: Item_Label__c, Sort_Order__c (active) | seeds checklist items; errors if none active | QuoteMigrationService.cls:497-505, :531 |

---

## PART B — PRICEBOOKENTRY TOOLING INTERFACES (bulk/config, not runtime pricing)

### BC-9 · PBE bulk-update + attribute-loading tooling  (CONFIRMED)
These are admin/batch/invocable surfaces (in force-app, NOT in the 32 live-classes set) that WRITE
PricebookEntry / QuoteLineItemAttribute. They are the write-side counterpart to the read-only runtime
hooks. Map as interface — a pricing refactor must not silently change their PBE-write contract.

| Tool | READS | WRITES / DML | file:line (force-app/main/default/classes) |
|---|---|---|---|
| Fortra_BulkPriceUpdateBatch | Product2 (Id,Name,ProductCode,Solution_Category__c,IsActive + child PBEs) WHERE Solution_Category__c IN :categories; standard Pricebook2 (IsStandard=true); `Currency_Conversion_Formula__mdt` (via BC-5 service) | upsert Standard + custom `PricebookEntry` per pricebook×currency | Fortra_BulkPriceUpdateBatch.cls:53,133-177,193-198 |
| Fortra_BulkPriceUpdateInvocable | Flow entry wrapper (categories, pricebooks) | starts batch; returns AsyncApexJob Id + estimates | Fortra_BulkPriceUpdateInvocable.cls:@InvocableMethod (17+) |
| UpdatePricebookEntriesInvocable | inputs: Product2 Id, Pricebook2 Id, currency ISO list, parallel Unit Prices | update/create `PricebookEntry` (multi-currency), create Standard PBE | UpdatePricebookEntriesInvocable.cls:19-61 |
| PricebookEntryCascadeDeleter | `PricebookEntry` (Id,Product2.Name,IsActive); OpportunityLineItem, AssetActionSource, AssetAction, Asset by PricebookEntryId | `Database.delete` cascade (OLI→AAS→AA→Asset) under savepoint | PricebookEntryCascadeDeleter.cls:31-53 |
| AttributeLoadingService | CSV → Legacy_Id__c map; AttributeDefinition (Id,Name IsActive=true), AttributePicklistValue; QuoteLineItem WHERE Legacy_Id__c IN :ids | preview/validation only (batch does insert) | AttributeLoadingService.cls:166,191,208,311,329 |
| AttributeLoadingBatch | QuoteLineItem WHERE Legacy_Id__c IN :ids; existing QuoteLineItemAttribute | insert `QuoteLineItemAttribute` (QLIA) via Database.insertImmediate | AttributeLoadingBatch.cls:73-82, :107-197 |

---

## PART C — FLOW / DISCOVERY-PROCEDURE INTERFACES

### BC-10 · Reprice flows & discovery-procedure wiring  (CONFIRMED)
The flows are the orchestration boundary that invokes the ESD pricing procedure. Read-only mapping:

| Flow | pricingProcedureName | discovery procedure | skipDiscovery | file:line (force-app/main/default/flows) |
|---|---|---|---|---|
| Fortra_Quote_Reprice | `Rev_Mgmt_Default_Pricing_Procedure` | `Salesforce_Pricing_Discovery_Procedure` | true | Fortra_Quote_Reprice.flow-meta.xml:169-195 |
| Fortra_Order_Reprice | `Rev_Mgmt_Default_Pricing_Procedure` | (none referenced) | present @:108 | Fortra_Order_Reprice.flow-meta.xml:90-92, :108, :169 |
| Fortra_Quote_to_Order_Conversion | calls Fortra_Order_Reprice before Activate_Order | — | — | Fortra_Order_Reprice.flow-meta.xml:169 (description) |
| Stamp_Source_List_Price | (stamps Source_List_Price__c — SourceListPricePrehook is UNWIRED per KEY FACT 6) | — | — | Stamp_Source_List_Price.flow-meta.xml (exists) |
| Quote_Handle_Quote_Currency_Change | invokes QuoteCurrencyChangeService(_Fixed) | — | — | Quote_Handle_Quote_Currency_Change.flow-meta.xml (exists) |

4 discovery ExpressionSetDefinitions exist (KEY FACT 12): Product_Discovery_Pricing_Procedure,
Salesforce_Pricing_Discovery_Procedure, Salesforce_Default_Pricing_Discovery_Procedure,
..._v2. Only `Salesforce_Pricing_Discovery_Procedure` is referenced by a flow (Quote path), and it is
short-circuited via skipDiscovery=true. Discovery procedures are map-only, out of scope.

---

## PART D — HARDCODE FINDINGS (Priority-A anti-pattern: Apex inlines what belongs in MDT/config)

### BC-11 · QLDescriptionGeneratorPrehook — hardcoded ordered attribute list  (CONFIRMED)
`ATTRIBUTE_ORDER` is a 9-element inline `List<String>` (not the "10" prior docs claimed — CORRECTED;
one entry `License_Type` is a forward-compat PLACEHOLDER for an attribute that does not yet exist in
fortrauat). Members: License_Type, PS_Service_Type, Feature_Options, Maintenance_Type_Defn,
Deployment_Option, Server_Location_Type, Power_License_Type, Server_Type, Group_Number.
- file:line: QLDescriptionGeneratorPrehook.cls:111-128; also inline constants UNIT_TYPE_ATTR
  `Unit_Type` (:131), UNIT_QUANTITY_ATTR `Attribute_Volume` (:145), NUMBER_OF_UNITS_ATTR
  `Number_of_Units` (:152), UNIT_TYPE_PER_USERS trigger `Per User` (:161).
- SHOULD be config vs IS inline: **already has the MDT interface** (`QL_Description_Attribute__mdt`,
  BC-6). The inline list is only the `defaultConfig()` fallback used when zero active MDT rows exist
  (QLDescriptionGeneratorPrehook.cls:198-208, :220). So this is a config-with-fallback pattern —
  lower priority than a pure hardcode. Refactor lever = seed the MDT and delete the fallback (or keep
  fallback but drive it from a static resource). Not a defect today.

### BC-12 · Maintenance tier rates — MDT-sourced (NOT an Apex hardcode)  (CORRECTED)
Prior suspicion "inline maintenance tier rates (7-tier vs 3-tier) in Apex" is FALSE. Rates come from
`Maintenance_Rate__mdt` (BC-3; MaintenanceOrderDecompositionService.cls:622-623,
PartnerNetPricePosthook.cls:1988-1992). The 7-tier→3-tier reversion is an **ESD pricing-procedure
formula** change (ACTIVE V21 `<description>` "Derived Pricing Formula reverted to 3-tier",
KEY FACT 9), i.e. lives in `ACTIVE_V21_block.xml` as a BusinessKnowledgeModel formula step, NOT in
Apex. **Config location = ESD formula step (canvas), not a class.** No Apex hardcode to remediate here.

### BC-13 · COLA out-year default literal `3`  (CONFIRMED)
COLAUpliftHandler.cls:154 uses literal `3` as the out-year uplift % when
`MyCAP_Rules__mdt.Default_Out_Year_Uplift_Percent__c` is null. SHOULD be an MDT-side default (the MDT
already exists — BC-2); IS an inline fallback. Low blast radius (only fires on null MDT field).

### BC-14 · CurrencySelectionService — hardcoded country→currency map  (CONFIRMED)
A 14-entry inline `Map<String,String>` country→ISO (US→USD, CA→CAD, AU→AUD, 11 EU countries→EUR) plus
a locked-order-status `Set<String>` {Activated, In Fulfillment, Fulfilled, Completed}.
- file:line: CurrencySelectionService.cls:13-30 (country map), :47-52 (locked statuses).
- SHOULD be config vs IS inline: the country→currency mapping is pure reference data that belongs in a
  `Country_Currency__mdt` (or reuse `Services_Regional_Pricing__mdt.Country_Code__c`); it is fully
  inline. Adding a Euro-zone member or a new-currency country today requires an Apex deploy. **Priority-A
  hardcode.** Note this map is Priority-2 (fallback): User.DefaultCurrencyIsoCode wins first (:8-10),
  final fallback `USD` (:37) — but that does not excuse the inline table.

### BC-15 · HardwareAttributePricingPrehook — hardcoded system defaults + multiplier tables  (CONFIRMED)
Multiple inline pricing tables — the single largest concentration of pricing constants in the Apex
tier. All `private static final`:
- System defaults: DEFAULT_PGROUP `P20`, DEFAULT_SYSTEM_TYPE `Production`, DEFAULT_USERS `1`
  (HardwareAttributePricingPrehook.cls:37-39); DEFAULT_MULTIPLIER 1.0, DEFAULT_DISCOUNT 0.0 (:33-34).
- Attribute DeveloperNames: ATTR_PGROUP `Pgroup`, ATTR_SERVER_TYPE `Server_Type`, ATTR_USERS `Users` (:43-45).
- `PGROUP_MULTIPLIERS` map (7 rows P05..P60 → 0.5/0.75/1.0/1.5/2.0/3.0/4.0) — :48-56.
- `USER_TIER_RANGES` list (6 bands 1-10..501-999999 → 1.0/1.25/1.5/2.0/2.5/3.0) — :59-66.
- `SYSTEM_TYPE_DISCOUNTS` map (Production 0.0 / Staging 25.0 / Test 50.0) — :69-73.
- SHOULD be config vs IS inline: **all three pricing tables (pGroup multipliers, user-tier bands,
  system-type discounts) plus the P20/Production/1 fallbacks are actual pricing levers hardcoded in
  Apex.** No MDT interface exists for them. This is the top Priority-A remediation target — a pricing
  change (e.g. re-band users, add P70) requires an Apex deploy. Candidate: a
  `Hardware_Attribute_Pricing__mdt` (multiplier/tier/discount rows).

### BC-16 · Fortra_CurrencyConversionService — no numeric FX literal, but string-formula interpreter  (CORRECTED)
No `0.9346` and no `* 0.92` runtime literal — those are doc-comment examples only
(Fortra_CurrencyConversionService.cls:10, :97, :99). Runtime FX comes entirely from
`Currency_Conversion_Formula__mdt` (BC-5). The residual anti-pattern is architectural, not a hardcode:
the MDT stores an executable **formula string** parsed by `applyFormula` (:102-149), so config = code.
Note also an unrelated inline pricing threshold `Base_Price__c >= 10000 && preColaNet < Base_Price__c *
0.5` at PartnerNetPricePosthook.cls:1232 (a sanity/guard heuristic, magic numbers 10000 and 0.5) — flag
for review but it is a guard, not a rate table.

---

## PART E — LKG (MAP-ONLY, per hard stop rule)

### BC-17 · LKG family  (CONFIRMED; map-only, NOT enumerated)
LKG is an out-of-scope automation subsystem, mapped by family + factory + one representative triad only:
- Family size: 174 `Lkg*` classes (force-app/main/default/classes; `ls Lkg*.cls | wc -l` = 174). Do not enumerate.
- Factory entry point: `LkgAutomatePointsBuilderFactory` → returns `new AutomateDefaultPointsBuilder()`
  (LkgAutomatePointsBuilderFactory.cls:1, :19).
- Representative triad (one example only): LkgCcssFileBuilder (+ its factory + builder peers).
STOP — LKG has no in-scope pricing boundary; it is not a root cause of any pricing symptom examined.

---

## OPEN QUESTIONS / OWNER-ROLE HANDOFFS (boundary root-cause, STOP rule)

- **OQ-BC-1 (ESD formula owner):** the 7-tier↔3-tier derived-maintenance formula lives in the ACTIVE
  V21 ESD, not Apex (BC-12). Any change to derived-maint math is a pricing-procedure/canvas edit —
  owner = pricing-procedure admin (Liam/Nir per MEMORY), NOT a class refactor. STOP.
- **OQ-BC-2 (Currency config-as-code):** `Currency_Conversion_Formula__mdt.Conversion_Formula__c`
  stores executable text evaluated by `applyFormula` (BC-5/BC-16). Whether to keep string formulas or
  move to pure `Conversion_Rate__c` decimals is a data-model decision — owner = pricing/finance config
  owner. Map-only; do not refactor the interpreter.
- **OQ-BC-3 (Hardware pricing tables):** no MDT exists for pGroup/user-tier/system-type tables
  (BC-15). Introducing one is a NET-NEW boundary — owner = pricing config owner + Rev Cloud admin.
  Flagged as the #1 hardcode; decision required before refactor.

---

### Cross-lane notes for orchestrator
- Duplicated MDT loaders (same query in 2 classes): COLA_Uplift_Rules__mdt (BC-1), Maintenance_Rate__mdt
  (BC-3). DRY candidate but each is a correct read of one interface.
- Write-side staging fields the hooks stamp (dual-object QLI+OrderItem) are Lane-3/4 territory; here
  only noted where a boundary read feeds them (BC-1 COLA %, BC-3 maint net, BC-4 regional net).
- Priority-A hardcode ranking (most→least severe): BC-15 (Hardware tables, no MDT) > BC-14
  (CurrencySelectionService country map, no MDT) > BC-13 (COLA `3` literal, MDT exists) > BC-11
  (QLDescription list, MDT exists w/ fallback). BC-12/BC-16 are NON-findings (CORRECTED).
