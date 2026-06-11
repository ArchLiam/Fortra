# Fortra Org — Core Metadata Reference

> **Purpose:** a developer-facing map of the Fortra Salesforce org's **custom (non-managed) metadata**, so
> work on this project starts from knowledge instead of rediscovery. Generated 2026-06-11 from a live retrieve
> of **FortraUAT** (no-namespace components only). Source files live under [`_src/`](_src/); raw inventory +
> counts under [`_inventory/`](_inventory/).

---

## What this org is
A **Salesforce Revenue Cloud / RLM ("RCA")** implementation for **Fortra** (enterprise software/cybersecurity).
The build centers on a **Quote → Order → Asset → Contract** lifecycle with heavy custom pricing, a large
**license-key generation** engine, **Workday** financial integration, and **legacy-CPQ migration** tooling.
On top sit major managed packages — **Certinia/FinancialForce** (`c2g` accounting, `ffrr` rev-rec, `pse` PSA,
`ffscpq` Services CPQ), **OmniStudio** (doc generation), plus LinkedIn/SalesIntel/Docebo. *Those are out of
scope here — this reference is the **custom** layer only.*

## Org at a glance (custom / no-namespace)
| Type | Count | Doc |
|---|---:|---|
| Apex classes | 404 | [01a](01a_Apex_LKG_Framework.md)–[01e](01e_Apex_Integration_Platform.md) |
| Apex triggers | 10 | [02](02_Triggers.md) |
| Flows | 245 | [03](03_Flows.md) |
| Custom objects (`__c`) | 39 | [04a](04a_Custom_Objects.md) |
| Customized standard / RCA objects | 20 | [04b](04b_Standard_Objects.md) |
| Custom Metadata Types (`__mdt`) | 25 | [05](05_Custom_Metadata_Types.md) |
| Platform Events (`__e`) | 15 | [06](06_Platform_Events.md) |
| LWC + Aura | 23 + 8 | [07](07_LWC_Aura.md) |
| Custom Settings / Labels / Apps / Record Types | 2 / labels / 12 / 62 | [08](08_Settings_Labels_Apps_RecordTypes.md) |

*(Raw totals incl. managed packages are far larger — e.g. 24,383 Apex classes, 1,589 objects — see [`_inventory/`](_inventory/).)*

---

## The major subsystems (start here)
1. **License Key Generation (LKG)** — the single biggest custom subsystem (**141 Apex classes** + the
   `LKG_*` CMDT hierarchy Brand→Silo→Solution→Product). A Strategy/Factory pipeline (Mapper → RequestBuilder →
   `callout:keygen_api` → RecordCreator) that mints software license keys per product "silo" into
   `License_Key__c`. → [01a](01a_Apex_LKG_Framework.md), [05](05_Custom_Metadata_Types.md).
2. **Revenue Cloud pricing** — the active procedure `Rev_Mgmt_Default_Pricing_Procedure` plus **six
   `RevSignaling.SignalingApexProcessor` prehooks** (COLA uplift, regional services, partner net, attribute/
   hardware volume, maintenance, description). **COLA renewal pricing is the SC-3350 hot spot.** → [01c](01c_Apex_Pricing.md), [05](05_Custom_Metadata_Types.md).
   - *Pricing-procedure (ExpressionSet) internals are documented separately in the SC-3350 dossier
     (`*Jira/Task/sc3350 …/`), since they're a different metadata type not in this retrieve.*
3. **Quote → Order → Asset lifecycle** — flow-invoked Q2O actions (reprice, Power-line split, field mapping,
   asset/contract linking), renewal/amend/cancel handlers. → [01b](01b_Apex_Quote_Order_Asset.md), [02](02_Triggers.md), [03](03_Flows.md).
4. **Hardware quoting & Partner channel** — hardware-first configurator + eligibility; partner pricing prehooks
   (V1/V2) + checklists + partner portal. → [01d](01d_Apex_Hardware_Partner_Ops.md).
5. **Integrations** — Workday (Billing_Event + `Order_Completed_WD__e` re-submit), MuleSoft (D&B), DocuSign,
   Globalscape, InterPayment/BSI, Microsoft JWT, HubSpot. → [01e](01e_Apex_Integration_Platform.md), [06](06_Platform_Events.md).
6. **Migration tooling** — Quote/Order migration batches, RCA product/technical-product creators,
   `ContextDefinition` dependency manager, and a 26-flow `GearsetCloneSupportFlow*` infra family. → [01e](01e_Apex_Integration_Platform.md), [03](03_Flows.md).

## Document index
| # | Doc | Covers |
|---|---|---|
| 01a | [Apex — LKG Framework](01a_Apex_LKG_Framework.md) | 141 license-key-generation classes |
| 01b | [Apex — Quote/Order/Asset](01b_Apex_Quote_Order_Asset.md) | 62 Q2O lifecycle + renewal + migration classes |
| 01c | [Apex — Pricing](01c_Apex_Pricing.md) | 31 pricing classes (COLA, currency, regional, partner, attribute) |
| 01d | [Apex — Hardware/Partner/Ops](01d_Apex_Hardware_Partner_Ops.md) | 66 hardware, license-email, partner, checklist classes |
| 01e | [Apex — Integration/Platform](01e_Apex_Integration_Platform.md) | 104 integration, migration-admin, bulk, site classes |
| 02 | [Triggers](02_Triggers.md) | 10 custom triggers |
| 03 | [Flows](03_Flows.md) | 245 flows grouped by object & type |
| 04a | [Custom Objects](04a_Custom_Objects.md) | 39 `__c` objects |
| 04b | [Standard / RCA Objects](04b_Standard_Objects.md) | 20 customized standard objects (Quote, Order, Asset, Product2, …) |
| 05 | [Custom Metadata Types](05_Custom_Metadata_Types.md) | 25 `__mdt` (pricing, LKG, ops, reference) |
| 06 | [Platform Events](06_Platform_Events.md) | 15 `__e` (Workday, geocoding, integration) |
| 07 | [LWC + Aura](07_LWC_Aura.md) | 31 UI components |
| 08 | [Settings / Labels / Apps / Record Types](08_Settings_Labels_Apps_RecordTypes.md) | custom settings, labels, 12 apps, record types |

## ⚠️ Known fragile / load-bearing spots (flagged during documentation)
- **Pricing prehook ordering is significant** — e.g. `PartnerNetPrice` is a seq-10 post-hook; `QLDescriptionGeneratorPrehook` **must run last**; COLA must run after Regional. Re-ordering breaks pricing.
- **One-trigger-per-object is NOT enforced** — `Quote` and `QuoteLineItem` each have **two** triggers with undefined sibling order. `QuoteLineItemTrigger` is the COLA/SC-3350 renewal hot zone.
- **Two `SourceListPrice` pricing classes are intentionally disabled**; `FieldPopulatedCheck` is deprecated (SC-3366 governor-limit).
- **`Stamp_Maintenance_Pricing_Inputs`** renewal branch flagged untested; superseded duplicate flow pairs exist.
- Several `__mdt` types have **no in-repo consumer** (candidates for cleanup — see [05](05_Custom_Metadata_Types.md)).

---

## Maintenance
- **Regenerate:** re-run the retrieve manifest [`_src_package.xml`](_src_package.xml) (`sf project retrieve start -x …`) and the inventory scripts, then refresh the per-type docs.
- **Source of truth** is always the org / `_src/`; these docs are a curated map, not a substitute for the metadata.
- `_src/` (~24 MB) and `_inventory/` are working artifacts — consider git-ignoring them if committing this folder.
