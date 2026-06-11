# Custom Metadata Types (`__mdt`)

## Overview

Custom Metadata Types are the Fortra org's deploy-time configuration layer: admin-editable lookup tables
that drive pricing math, license-key generation, migration defaults, order validation, and integration
endpoints **without code changes**. Several are load-bearing for the Revenue Cloud (RCA) pricing pipeline —
the COLA/MyCAP uplift and Services Regional Pricing prehooks are `RevSignaling.SignalingApexProcessor`
implementations that read these tables at price time, so an empty or mis-keyed record silently changes
quote/order prices. Others (LKG_*) form a normalized brand→silo→solution→product hierarchy consumed by the
License Key Generator UI and email-template engine. This doc covers all 25 custom (`__mdt`) types; managed-package
metadata is out of scope.

Record counts are point-in-time (`_inventory/_cmdt_counts.json`). A **0** count means the type is defined but
unpopulated (defined-but-dormant — verify before assuming it does anything live).

---

### Pricing

These feed the RLM `Rev_Mgmt_Default_Pricing_Procedure` via Apex prehooks and pricing batches. Treat as
load-bearing: changes here move money on live quotes/orders.

| Type | Records | Purpose | Consumed by | Key fields |
| --- | --- | --- | --- | --- |
| `COLA_Uplift_Rules__mdt` | 22 | Default cost-of-living-adjustment uplift % per Solution Category, used for renewal/maintenance pricing (SC-3350). Keyed by `Solution_Category__c`; rule chosen via `qli.COLA_Solution_Category__c`. Date-bounded by Effective Start/End. | `COLAUpliftHandler` (builds `Map<String,COLA_Uplift_Rules__mdt>` by Solution Category for Y1 + out-year uplift), `COLAUpliftPrehook` (`implements RevSignaling.SignalingApexProcessor`), `Stamp_Maintenance_Pricing_Inputs` flow. Tested by `COLAUpliftTest`. | `Default_Uplift_Percent__c`, `Solution_Category__c`, `Effective_Start_Date__c`, `Effective_End_Date__c`, `Is_Active__c`, `Description__c` |
| `MyCAP_Rules__mdt` | 1 | Global floor/default for out-year (MyCAP) uplift % applied alongside COLA. Single `Global` instance fetched by `getInstance('Global')`. | `COLAUpliftHandler` / `COLAUpliftPrehook` (`MyCAPFlagApplier` Queueable). | `Default_Out_Year_Uplift_Percent__c`, `Minimum_Out_Year_Uplift_Percent__c`, `Is_Active__c` |
| `Maintenance_Rate__mdt` | 7 | Maintenance pricing rate per maintenance type. Lookup table for maintenance/renewal rate math. **No Apex/flow consumer found in repo** — verify it is wired (possibly read by a managed-package pricing element or stale). | _(none found in source — likely flow/formula or dormant)_ | `MaintenanceType__c`, `Rate__c` |
| `Services_Regional_Pricing__mdt` | 125 | Country/region price multiplier for the LIST channel on Services lines (e.g. Italy 0.64). Applied as `CEILING(price×m/5)×5`; net stays catalog, so `TotalLineAmount≠NetTotalPrice` by design (SC-3374). Keyed by both `Country__c` and `Country_Code__c`. | `RegionalServicesPricingPrehook` (`implements RevSignaling.SignalingApexProcessor`; SELECTs Country/Country_Code/Multiplier into a map). Tested by `RegionalServicesPricingPrehookTest`. | `Multiplier__c`, `Country__c`, `Country_Code__c`, `Region__c`, `Subregion__c`, `Effective_Start_Date__c`, `Effective_End_Date__c`, `Is_Active__c` |
| `Currency_Conversion_Formula__mdt` | 6 | FX rate + formula text per currency, driving multi-currency PriceBookEntry creation and bulk price updates. | `Fortra_CurrencyConversionService`, `Fortra_BulkPriceUpdateBatch` / `...Invocable`, flows `Fortra_Bulk_Price_Update_Flow`, `Fortra_Product_Create_Multi_Currency_PBE`, `Fortra_Product_Update_Currency_Prices_SubFlow`. Tested by `Fortra_BulkPriceUpdateBatchTest`. | `Conversion_Rate__c`, `Conversion_Formula__c`, `Formula_Text__c`, `Currency_ISO_Code__c` / `ISO_Code__c`, `Is_Active__c` |
| `Legal_Entity_Currency__mdt` | 27 | Maps a Legal Entity to its allowed/primary currency; drives Opportunity legal-entity auto-select and currency validation. | Flows `Fortra_Opportunity_Change_Legal_Entity`, `Fortra_Opportunity_LE_Currency_Validation`, `Fortra_Opportunity_Legal_Entity_AutoSelect`. | `Legal_Entity_Name__c`, `Currency_Code__c`, `Is_Primary__c` |

---

### LKG framework (License Key Generator)

A normalized **Brand → Silo → Solution Category → Solution → Product** hierarchy plus UI-field metadata,
powering the License Key Generator UI (`LkgUiController` + `lkgCustomKeyGenerator` LWC) and the license/email
template engine. Hierarchy links use `MetadataRelationship` fields (parent `__mdt` lookups), so these must be
loaded/deployed in dependency order. `Is_Hidden__c` toggles visibility in the generator UI.

| Type | Records | Purpose | Consumed by | Key fields |
| --- | --- | --- | --- | --- |
| `LKG_Brand__mdt` | 8 | Top of the LKG hierarchy (brand). | `LkgUiController`, `lkgCustomKeyGenerator` LWC. Parent of `LKG_Silo`. | `LKG_Solution_Group__c` (MetadataRelationship) |
| `LKG_Silo__mdt` | 25 | Product silo under a brand. | `LkgUiController`, `LkgMapperFactory`, `lkgCustomKeyGenerator`. | `LKG_Brand__c` (MetadataRelationship) |
| `LKG_Solution_Group__mdt` | 4 | Grouping above Solution Category. | `LkgUiController`. | `Is_Hidden__c` |
| `LKG_Solution_Category__mdt` | 10 | Solution category within a group. | `LkgUiController`. | `LKG_Solution_Group__c` (MetadataRelationship), `Is_Hidden__c` |
| `LKG_Solution__mdt` | 98 | Solution under a category. | `LkgUiController`. | `LKG_Solution_Category__c` (MetadataRelationship), `Is_Hidden__c` |
| `LKG_Product__mdt` | 140 | Leaf product node; carries license-key product naming + per-product email-template API names (permanent / subscription / specific-temp / generic) and flags (legacy, hidden, support). | `LkgUiController`, `LkgMapperFactory`, `EmailService`, `EmailTemplatePlaceholderProcessor`, `LicenseKeyTemplateResolver`. | `Product_Code__c`, `Internal_Product_Name__c`, `License_Key_Product_Name__c`, `*_Email_Template_API_Name__c` (several), `LKG_Silo__c` / `LKG_Solution__c` (MetadataRelationship), `Is_Legacy__c`, `Is_Support_Product__c`, `Is_Hidden__c` |
| `LKG_Key_Type__mdt` | 25 | License-key type definition (scope + type) used by the key-mapper to pick generation behavior. | `LkgMapperBase` (`LKG_Key_Type__mdt.getInstance(keyType)`), `LkgUiController`. | `Type__c` (Picklist), `Scope__c` (Picklist), `LKG_Silo__c` (MetadataRelationship) |
| `LKG_UI_Field__mdt` | 366 | **Largest CMDT.** Defines the dynamic input fields rendered in the LKG generator UI (type, default, picklist source, display order, scope) per product/silo. | `LkgUiController`. | `Type__c`, `Scope__c`, `Default_Value__c`, `Display_Order__c`, `Picklist_JSON__c`, `Picklist_Values__c`, `LKG_Product__c` / `LKG_Silo__c` (MetadataRelationship), `Is_Hidden__c` |
| `LKG_UI_Field_Option__mdt` | 140 | Per-field option/default override, keyed by UI Field + Key Type. | `LkgUiController`. | `Default_Value__c`, `LKG_UI_Field__c` / `LKG_Key_Type__c` (MetadataRelationship), `Is_Hidden__c` |
| `LKG_Email_Template_Place_Holder__mdt` | 6 | Text-injection placeholders merged into license/notification email templates, keyed by brand + key type + template API name. | `EmailTemplatePlaceholderProcessor` (tested by `...Test`). | `Placeholder__c`, `Text_Injection__c`, `Email_Template_Api_Name__c`, `Brand__c`, `Key_Type__c` |

---

### Operations / Validation

Drive order-submission gating, migration defaults, and checklist UIs.

| Type | Records | Purpose | Consumed by | Key fields |
| --- | --- | --- | --- | --- |
| `Order_Submit_Validation__mdt` | 48 | Declarative "required field" rules for Order submission — each row names a field on the Order / its lines / a related record (resolved via `Relationship_Field_API_Name__c`) that must be populated, with the error + link message shown when blank. Constant-SOQL validator. | `OrderSubmissionValidator` (`@InvocableMethod`, validates all active rules), flow `Fortra_Order_Submission_Check`. **UAT-only / `FieldPopulatedCheck` adjacent — do NOT assume present in prod (SC-3291).** | `Field_API_Name__c`, `Object_API_Name__c`, `Relationship_Field_API_Name__c`, `Error_Message__c`, `Link_Message__c`, `Field_Label__c`, `Object_Label__c`, `Active__c` |
| `Operations_Checklist_Config__mdt` | 16 | Defines the Operations checklist items (label, category, icon, order) initialized on records during quote migration / order ops. | `ChecklistInitializationService`, `QuoteMigrationService` (tested by `QuoteMigrationBatchTest`). | `Item_Label__c`, `Category__c`, `Icon_Name__c`, `Sort_Order__c`, `Is_Active__c` |
| `Partner_Checklist_Definition__mdt` | 7 | Partner-portal checklist items, gated by partner tier (basic / mid / top) with a label, description, sort order, and optional URL. | `PartnerChecklistController`. | `Display_Label__c`, `Description__c`, `URL__c`, `Sort_Order__c`, `Basic_Partner_Users__c`, `Mid_Tier_Partner_Users__c`, `Top_Tier_Partner_Users__c`, `Active__c` |
| `Migration_Field_Default__mdt` | 9 | Default values stamped onto migrated Order/Quote records when a source field is blank; specifies target object/field, default value, and an optional lookup resolution (`Lookup_Object__c` + `Lookup_Name_Filter__c`). | `OrderMigrationService` / `OrderMigrationBatch` / `OrderMigrationController`, `QuoteMigrationService` / `QuoteMigrationBatch` / `QuoteMigrationController` (+ their tests). | `Target_Object__c`, `Target_Field__c`, `Default_Value__c`, `Lookup_Object__c`, `Lookup_Name_Filter__c`, `Is_Active__c` |

---

### Reference / Integration

Lookup tables and integration endpoint config.

| Type | Records | Purpose | Consumed by | Key fields |
| --- | --- | --- | --- | --- |
| `Country_Crosswalk__mdt` | 230 | Crosswalk of country code/name to region & subregion (region picklists). Reference data for regional pricing/reporting geography. **No direct Apex/flow consumer found in repo** — likely referenced by formula fields or read indirectly; verify before relying on it. | _(none found in source)_ | `Country_Code__c`, `Country_Name__c`, `Country__c`, `Region__c` / `Region_Code__c` / `Region_Name__c` (Picklist), `Subregion__c` / `Subregion_Code__c` / `Subregion_Name__c` |
| `UOM_Categories__mdt` | 0 | Unit-of-measure category reference. **Empty and no custom fields / no consumer** — defined-but-dormant; safe to treat as unused until populated. | _(none)_ | _(label/value only — no custom fields)_ |
| `Workday_Base_URL__mdt` | 1 | Single base URL for the Workday environment, used to build the `Workday_Invoice_URL__c` deep-link formula field. | `Workday_Invoice_URL__c` formula field (references `Base_Url__c`). | `Base_Url__c` |
| `InterPayment_Settings__mdt` | 1 | OAuth + gateway config for the InterPayment payment-link integration (host, client id/secret, audience, token URL, gateway/location ids, redirect). Secrets live here. | `BSIInvoicePaymentLinkController`. | `ApiHost__c`, `ClientId__c`, `ClientSecret__c`, `Audience__c`, `AuthTokenUrl__c`, `GatewayId__c`, `Location_Id__c`, `RedirectUrl__c`, `IsActive__c` |
| `Export_License_Expiration_Settings__mdt` | 0 | Config for the export-license expiration notification email (lead days, recipients/CC, template). **0 records** — the notification flow exists but is unconfigured, so it will not fire until a record is created. | Flow `Send_Export_License_Notification_Email`. | `Days_Before_Expiration__c`, `Recipient_Emails__c`, `CC_Emails__c`, `Email_Template_Developer_Name__c`, `Active__c` |

---

## Notes & gotchas

- **Pricing prehooks are platform-wired**, not trigger-wired: `COLAUpliftPrehook` and
  `RegionalServicesPricingPrehook` implement `RevSignaling.SignalingApexProcessor` and run inside the RLM
  pricing procedure. An empty or mis-keyed `COLA_Uplift_Rules__mdt` / `Services_Regional_Pricing__mdt` row
  changes live prices silently.
- **0-record types** (`UOM_Categories`, `Export_License_Expiration_Settings`): defined but dormant — their
  consumers no-op or never fire. Do not assume behavior until populated.
- **No-consumer-in-repo types** (`Maintenance_Rate`, `Country_Crosswalk`, and the empty `UOM_Categories`):
  not referenced by any custom Apex/flow in this source. They may be read by managed-package pricing, by
  formula fields, or be stale. Confirm against the live org before deleting or trusting.
- **LKG hierarchy** uses `MetadataRelationship` parent lookups (Brand→Silo→Solution Category→Solution→Product,
  plus Key Type / UI Field). Deploy/load child types after their parents.
- **`Order_Submit_Validation__mdt` is UAT-scoped** alongside `FieldPopulatedCheck` (SC-3291) — present in UAT,
  absent/under-tested in prod. Validate environment before deploying changes.
- Keys: COLA rules key on `Solution_Category__c`; Services Regional Pricing keys on both `Country__c` and
  `Country_Code__c` (map populated under both); LKG Key Type / MyCAP use `getInstance(<DeveloperName>)`.
