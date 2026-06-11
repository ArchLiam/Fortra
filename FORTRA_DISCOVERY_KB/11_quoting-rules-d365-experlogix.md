# 11 — Quoting Rules for D365: Experlogix Configuration Rules, Bundles & Hardware

> **Scope.** Legacy **D365 / Experlogix CPQ** quoting & configuration rules that Fortra must re-implement in **Salesforce Revenue Cloud Advanced (RCA)** as Product Configuration Rules, bundles (ProductComponentGroup / ProductRelatedComponent), and hardware data. Source folder: [`Pricing and Products/Quoting Rules for D365`](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365). This is **raw discovery input** — the system being migrated *away from* (Microsoft Dynamics 365 CRM "OAZCRMEXPERDEV" org + Experlogix configurator). It complements the design KB (`FORTRA_KNOWLEDGE_BASE.md`); where the design KB describes the target RCA model, this doc inventories the legacy logic that must land in it.
>
> **Legacy stack identified in the data:** Dynamics 365 CRM (custom entity `hs_hardware`, option-set values in the `717710xxx` range = HelpSystems publisher prefix), Experlogix configurator (rule premise/conclusion grammar), publisher domains `OAZCRMEXPERDEV\…` and `OAZEXPERDEVINT\…`. "HelpSystems" (HS) is Fortra's former name — hence `hs_` schema prefixes and "HelpSystems Hosted" location type.

---

## 1. Experlogix Rule Model — Grammar & Semantics

Two extracts of the same rule set exist:

| File | Rows × Cols | Notes |
|---|---|---|
| [ExperlogixRules 2.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/ExperlogixRules%202.xlsx) | 124 × 6 | **Curated subset** — friendlier columns: `Experlogix Rule Name, Type, Rule Description, Premise, Conclusion, AutoFix`. Human-readable Type words (ERROR/ALLOW/LINK/EXCLUDE/REQUIRED/SUGGESTED LINK). |
| [Previous version/ExperlogixRules.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Previous%20version/ExperlogixRules.xlsx) | **334 × 20** | **Full raw export** from the configurator DB. Adds `RuleID, TypeSeq, IncompatOptionBehavior, ExtensionOf, ModifiedOn, ModifiedBy, Behavior, Priority, HasErrors, Errors, Message (DisplayMsg)`. Authoritative — use this for the complete rule inventory. |

The "2" file is a trimmed, re-typed view; the "Previous version" file is the larger, raw, current export (despite the folder name — it has rules modified into **2024**, e.g. row `MaintRenewResellerNameError_Exp` 2024-02-27, `DDI_ClearAll` 2024-12-10). **Treat the 334-row file as the master.**

### 1.1 Premise / Conclusion token grammar

Rules are boolean expressions over a token alphabet. **This grammar must be decoded to translate any rule.**

| Prefix | Meaning | Example |
|---|---|---|
| `S:` | **SKU/option is Selected** in the configuration | `S:AM00090` |
| `C:` | **Category** (option-set / product family group) | `C:AMSoftwareLegac`, `C:HALines` |
| `F:` | **Formula flag / named rule-flag** (a pre-computed boolean, often "…Owned" = customer already owns it, or a `Rule_…` helper) | `F:AMProfOwned`, `F:Rule_BWMaxQuantity` |
| `R:` | **Rule-flag formula reference** (used by `LNK` maintenance "RF" rules to drive auto-maintenance) | `R:AMMaint`, `R:LNSoftware_CP` |
| `NOT` `AND` `OR` `( )` | Boolean operators | `S:AM00090 NOT ( S:AM00093 AND ( … ) )` |
| `_SUFFIX` on a conclusion SKU | A **context-keyed bundle-child instance** (same child SKU pulled into a specific parent). e.g. `S:AM00090_UPL` = AM00090 as the child inside the UPL (User-Provisioning-Large) bundle | `S:AAS_IG00050`, `S:LN00188_1_Core_1` |

Note the implicit operator quirk: `ERROR` premises read as `PREMISE NOT (REQUIRED_SET)` → "if premise true and required set NOT satisfied, raise error". So `S:AM00090 NOT ( S:AM00093 AND (…) )` means *"AM00090 selected but its prerequisites are missing."*

### 1.2 Rule Type taxonomy (full export, 334 rules)

| Type code | "2" file word | Count | RCA / CPQ semantic |
|---|---|---:|---|
| `LNK` | LINK | **127** | **Auto-add** conclusion SKUs when premise true (included/linked components). Largest category — mostly bundle composition + "RF" maintenance auto-attach. |
| `ERR` | ERROR | **100** | **Validation rule** — block save / flag line when premise true & requirement unmet. |
| `ALW` | ALLOW | **48** | **Conditionally reveal** an option/category (gate visibility). |
| `EXC` | EXCLUDE | **35** | **Mutual exclusion / Clear-All** — when premise true, the conclusion options can't be selected (or whole categories cleared). |
| `SLK` | SUGGESTED LINK | **10** | **Default-on but removable** auto-add (suggested, not required). |
| `REQ` | REQUIRED | **6** | Hard "must also select" dependency. |
| `MSG` | (msg) | **4** | **Informational message** only (no block). e.g. `PL_CredentialTheftAddOn`. |
| `SUG` | (suggest) | **2** | Suggest adding a category (e.g. `HWCSystemSpecs_Add`). |
| `REM` | (remove) | **1** | Auto-remove (`HWCSystemSpecs_Remove`). |

`TypeSeq` is mostly `2` (a few `0`); **`AutoFix` code** governs how the configurator auto-resolves a violation: `3` (214 rules — silent auto-fix/allow), `2` (109 — error requiring user action), `1` (9 — suggested), `7` (1 — message). `IncompatOptionBehavior`=`5` accompanies ERR rules.

`ExtensionOf` links a paired rule to its base (e.g. `MFTaas_Tier1|X1` EXCLUDE extends `MFTaas_Tier1` LINK — "when you pick Tier1, link its children **and** exclude the other tiers"). The `|X1`, `|Z1` suffix convention = "exclusion partner of base rule."

---

## 2. Reusable Rule Patterns → RCA mapping

These are the recurring archetypes. **Every brand prefix repeats the same handful of patterns**, so RCA implementation should be a *template applied per product family*, not 334 bespoke rules.

### 2.1 "Only one primary license" / "Max quantity = 1" (the dominant ERR pattern)

Nearly every brand has a trio:
- `xxDupPrimaryLicense` — "Only 1 primary license for a product is allowed" → `F:Rule_xxDupPrimaryLicense` over `C:xxLines`
- `xxMaxQuantity` — "primary product can't have quantity > 1" → `F:Rule_xxMaxQuantity`
- `xxPrimaryLicenseError` — "secondary licenses present but no primary in config or owned"
- `xxSoftwareDuplicationError` — "A partition can only have one instance of any software."

Brands using this trio (prefix → product line): **BW** (Bravura/?), **CCSS**, **HA** (Halcyon), **IM** (Intermapper), **LN** (Linoma/GoAnywhere), **PT** (Powertech), **RB** (Robot), **SB** (Skybot), **SQ** (Sequel), **SS** (Safestone), **SV**, **TG** (Tango), **TQ** (TeamQuest), **CSW** (Clearswift), **DDI**.

Some are SKU-list-driven (quantity-1 enforced on an explicit SKU list) rather than category-driven:
- `DDIServicesMaxQuantity` — hard-coded list of ~180 SKUs `DD00634…DD00835` limited to qty 1.
- `IMMaxQuantity` — list `IM05200…IM05519`.
- `TGMaxQuantity_CP` — list `TN00560…TN01252`.
- `TQMaxQuantity` — list `TQ04006…TQ04515`.

> **RCA translation:** these become **ProductConfigurationRule** validation rules (or attribute-based `ConfigurationRule` of type *Validation*) with a quantity constraint, plus a "primary license already owned" check that must read the customer's **Asset / install base** (the `F:…Owned` flags). The "owned" inputs have **no equivalent in a stateless CPQ config** unless RCA can query existing Assets — flag as integration dependency (see §6 Open Questions).

### 2.2 Prerequisite / Required dependency (ERR + REQ)

"If X selected, then Y (and one-of Z…) must also be selected or already owned."

Concrete examples:
- **`AM_AM00090Req`** (ERROR): `S:AM00090 NOT ( S:AM00093 AND ( S:AM00103 OR S:AM00105 OR S:AM00106 OR S:AM00111 OR S:AM00151 ) )`. Message: *"AM00090 – AutoMate Enterprise Server requires AM00093 – Developer Tools AND at least 1 Server Agent (AM00103 / AM00105 cap5 / AM00106 cap10 / AM00111 unlimited / AM00151 Process Agent)."*
- **`SB_SchedulerRequired`** (ERROR): a long OR-list of Skybot options requires `S:SB03030` (Scheduler Server/Host) or `F:SBSCHEDULEROWNED`. Message: *"The below options require a Skybot Scheduler license."*
- **`IM_Require`** (ERROR): remote-access/probe SKUs (`IM02501…IM02544`) require a core InterMapper license (`IM05500…IM05564`) or `F:IMCOREPRODOWNED`.
- **`WebDocsToolkit`** (REQUIRED): `RJ07451…RJ07457` → must add `RJ07465`.
- **`PT_PolicyMinder_CP`** (ERROR): `PT01552…PT01556` require `PT01551` (Policy Minder Console) or owned.
- **`BoKSNode_Services`** (REQUIRED): `S:FT00101` (BoKS Server Control 100-Node Bundle) → requires `S:FT01904` ("20 hours of BoKS Services Hourly").
- **`AM_ULTNonProdHA`** (REQUIRED): `AM03006 OR AM03007 OR AM03625` → require `AM03005` (Automate Ultimate base).

> **RCA translation:** **ProductConfigurationRule** of type *Validation* (block) or the dependency feature of a bundle (component min/max + qualifying-product rules). "or already owned" again needs Asset lookup.

### 2.3 Conditional reveal (ALW)

"If X selected/owned, option Y becomes available."
- **`AM_PROMaintenancePlus`**: `S:AM00050 OR F:Rule_AM_OwnPRO_single` → reveal `S:AM02000` (Maintenance Plus). There is a full matrix of Maintenance-Plus reveal rules per edition & per pack size (single/3pk/5pk/10pk/25pk/50pk) and per perpetual vs subscription (`AMSUB_…`).
- **`IG_ShowAASSections`**: `S:IG00064` → reveal categories `C:IGAAASBundle_S C:IGAAASBundle_C` (AAS Software + Connector sections).

> **RCA translation:** dynamic option visibility — RCA Product Configurator **constraint rules** / qualifying conditions on optional components, or attribute-driven feature visibility.

### 2.4 Mutual exclusion (EXC) and Clear-All

- **`SBHAInterface` / `SBHAInterface1`** (paired EXC): selecting the Scheduler (`SB03030/SB03350`) excludes the HA interface (`SB03063/SB03363`) and vice-versa.
- **`MFTaas_Tier1|X1` … `Tier3_LATAM|X1`**: picking any GoAnywhere MFTaaS hosting tier excludes all other tiers (one-tier-only).
- **`RJS_SMBWebDocs` / `RJS_SMBWebForms`**: "customer cannot own WebForms standard and WebDocs SMB" (cross-product incompatibility).
- **`xx_ClearAll`** rules (one per brand, ~35 total): when a "clear" flag fires, wipe entire category lists. e.g. `AM_ClearAll` clears 14 AutoMate categories (`C:AMSoftware C:AMMaint C:AMMaintPlus … C:AMMPSubsLegacy`). These are reset/scoping rules, **likely not needed in RCA** (RCA manages config state differently) — confirm before porting.

### 2.5 Auto-link bundles & suggested defaults (LNK / SLK)

This is where **bundle composition** lives (see §3). Two sub-flavors:
- **`LNK` (auto-add, required):** `IGA_AASBundle` → on `S:IG00064` auto-select `AAS_IG00050, AAS_IG00065, AAS_IG00067, AAS_IG00055`.
- **`SLK` (suggested, removable):** `AM_ULTBundle` → on `S:AM03005` suggest-add `AM03006, AM03007, AM03625` (don't require). `AMSUB_ULTBundle`, `IGA_AASBundle` (SLK in "2" file).

There are also **"…RF"** maintenance rules (`AMMaintenanceRF`, `IMMaintenanceRF`, `LNCPMaintenanceRF`, etc.) — `LNK` rules whose premise is a `R:<Category>` flag and conclusion is `NULL`. These drive **automatic maintenance-line attachment** off a RuleFlag formula (the configurator auto-creates the matching maintenance line for each software line). Note row 271 `SHCMaintenanceRF` has `HasErrors=1`, `Errors="RuleFlag formula is not assigned for category 'SHCMaintenance'"` — a known broken legacy rule.

### 2.6 Header / quote-level validations (port to RCA quote validation, not product rules)

These are **quote-level** ERR rules, important to re-home in RCA as **flow/validation on the Quote**, not product config:
- **`CurrencyError` / `CurrencyError_SUB`**: *"You cannot have multiple currencies on one quote."* (Directly relevant to the SC-3384 multi-currency work.)
- **`DateError`** (over `C:HEADER`): date validation.
- **`MaintRenewLegalEntityError` (+ `_Exp`/`_Wtg`)**: *"Only products from one legal entity may be renewed on the same quote."*
- **`MaintRenewResellerNameError` (+ variants)**: *"Only products from one Reseller may be renewed on the same quote."*
- **`SubRenewLegalEntityError` / `SubRenew…` family**: same constraints for subscription renewals; plus `SubRenewal_ZeroDuration*`/`MaintRenewal_ZeroDuration*`: *"All maintenance terms must be at least 1 month."*
- **`Rule_TermLengthCheck`** (`F:F_RULE_termlenghtcheck` over renewal categories): *"1 or more of the products does not meet the Term length requirements."*
- **`BS_3YearTermError` / `BS_3YearTermWarning`** (Beyond Security): *"You have selected a product that requires a 3 year term."* (`F:Rule_BS3YearTerm` over `C:BSSubscription`).
- **`UpliftCheck`** (over `S:Header`): *"Uplift percent entered is greater than allowed."* — i.e. legacy renewal-uplift cap; ties to approval logic in §5.
- **`TS_Over3000Users`** (Tripwire?): *"You have selected a product that limits the quantity to no more than 10000."* (msg says 10000 though rule name says 3000 — legacy inconsistency.)

---

## 3. Bundle Composition — `Bundle Items D365.xlsx`

[Bundle Items D365.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Bundle%20Items%20D365.xlsx) — sheet `BundleItems`, **3,148 rows × 11 cols** (extract truncated at 400 non-empty rows; the tail is dominated by the single huge Core-AAS connector enumeration). This is the **bill-of-materials for every D365 bundle** → maps directly to RCA **ProductComponentGroup + ProductRelatedComponent** (parent bundle → child components).

**Columns:** `Name (composite key bundleSKU_childSKU), Bundle Product (name), Bundle Product SKU, Line Product (name), Line Product SKU, Sequence, Quantity, Bundle Price Multiplier, Bundle Price Discount Percent, Product Relationship (= "Bundle Item"), Unit Quantity`.

### 3.1 Distinct bundle parents in the extract

| Bundle parent SKU | Bundle name |
|---|---|
| AM00078 | AutoMate Bundles - AutoMate Professional Package |
| AM00079 | AutoMate Bundles - AutoMate Premium Package |
| AM00080 | AutoMate Bundles - AutoMate BPA Server Standard Package |
| AM00081 | AutoMate Bundles - EPAS Professional |
| AM00082 | AutoMate Bundles - EPAS Premium |
| AM00083 | AutoMate Bundles - EPAS Plus |
| AM00084 | AutoMate Bundles - EPAS Enterprise |
| AM00140/141/142 | AutoMate User Provisioning Application - Small / Medium / Large |
| AM00790/791/792 | …Small/Medium/Large - **Subscription** |
| AM03005 | Automate Ultimate |
| AM03414 | Automate Plus - Multi-Deployment Pack (Promotional Bundle) - Subscription |
| TN04119 | Click & Launch – ALL STAR - Managed - Bundle |
| TN04120 | Click & Launch – CHAMPION - Managed - Bundle |
| CT00800 | Cobalt Strike and Core Impact **Enterprise** Bundle - Subscription |
| CT00801 | Cobalt Strike and Core Impact **Basic** Bundle - Subscription |
| CT00802 | Cobalt Strike and Core Impact **Pro** Bundle - Subscription |
| IG00064 | **Core AAS Bundle (Includes Internal & External) - Perpetual** (1,000s of optional connector children IG03000…IG05xxx) |

(The full 3,148-row sheet also contains the GoAnywhere/Linoma `LN_*` bundles whose composition is visible in the Experlogix `LNK` rules in §3.3 — e.g. `LN_EnterpriseBundle` LN08022, `LN_Premium` LN00416, `LN_StarterBundle` LN08025, etc.)

### 3.2 Concrete component examples (with quantities)

```
AM00080  AutoMate BPA Server Standard Package:
  AM00090  AutoMate Enterprise Server (Single Workstation)        qty 1
  AM00093  …Developer Tools                                       qty 1
  AM00106  Enterprise Server Agent, Capacity 10                   qty 1
  AM01906  AutoMate Online Services Full Day                      qty 1
  AM02002  Maintenance Plus, Enterprise Server Standard           qty 1

AM00084  EPAS Enterprise (note multi-qty children):
  AM00093, AM00098, AM00111, AM01906, AM02003, AM02008  qty 1 each
  SB03025  Schedule Agent Licenses - Bundle Agent      qty 10   <-- non-1 quantity
  SB03030  Automate Scheduler - Server/Host License     qty 1
  SB03065  Schedule Interface License - Bundle Interface qty 2
```

The `Sequence`, `Quantity`, and `Unit Quantity` columns map to RCA `ProductRelatedComponent.Sequence` / `Quantity` / `MinQuantity`/`MaxQuantity`. Most children are `Bundle Price Multiplier = 1, Discount % = 0` (price rolls from child list).

### 3.3 Bundle pricing — multiplier / discount (the load-bearing pricing rows)

Most bundles price children at list (`mult=1, disc=0`). The **exceptions that carry real bundle-level discounting** — these are the ones that matter for pricing translation:

| Bundle (SKU) | Child (SKU) | Price Multiplier | Discount % |
|---|---|---:|---:|
| Cobalt Strike + Core Impact **Basic** (CT00801) | Cobalt Strike Standard (CB00200) | 0.5932 | 40.68 |
| Cobalt Strike + Core Impact **Basic** (CT00801) | Impact Basic User (CT00772) | 0.9630 | 3.70 |
| Cobalt Strike + Core Impact **Enterprise** (CT00800) | Cobalt Strike Standard (CB00200) | 0.5932 | 40.68 |
| Cobalt Strike + Core Impact **Enterprise** (CT00800) | Impact Enterprise User (CT00770) | 0.9778 | 2.22 |
| Cobalt Strike + Core Impact **Pro** (CT00802) | Cobalt Strike Standard (CB00200) | 0.5932 | 40.68 |
| Cobalt Strike + Core Impact **Pro** (CT00802) | Impact Pro User (CT00771) | 0.9722 | 2.78 |

Relationship: **`Bundle Price Multiplier = 1 − (Discount % / 100)`**. The child's list price is multiplied by the multiplier to get the in-bundle price (income split across brands — see Pricing Notes §5). The AutoMate-Plus Promotional bundle (AM03414) and Click & Launch bundles (TN04119/04120) use Sequence numbering but mult=1/disc=0 (priced at bundle level instead — see §5).

> **RCA translation:** these per-child discount-off-list rows map to **ProductRelatedComponent** child pricing or **bundle-based adjustments** in the pricing procedure. The Pricing Notes (§5) explicitly say bundles can be priced *either* by discounting children off list *or* by setting price at the bundle level "if splitting the income across brands is not necessary." This is a **direct design decision** for RCA bundle modeling.

---

## 4. Required Items — `RequiredItemsSetUpInD365.xlsx`

[RequiredItemsSetUpInD365.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/RequiredItemsSetUpInD365.xlsx) — `Sheet1`, **62 rows × 8 cols**. Distinct from bundle BOM: these are **mandatory companion items** (mostly *services / onboarding / QuickStart*) that must accompany a base product.

**Columns:** `Name (base_line composite), Base Product, Bundle Product SKU, Line Product, Line Product SKU, Bundle Price Multiplier, Product Relationship (= "Required Item"), Allow Removal (= "With Approval")`.

Every row: **`Bundle Price Multiplier = 1`, `Product Relationship = Required Item`, `Allow Removal = With Approval`** — i.e. the required service is added at full price and **can only be removed with an approval**.

Representative rows:

| Base product (SKU) | Required line item (SKU) |
|---|---|
| GoAnywhere Starter Bundle w/ Gateway – Perpetual (LN08026) | GoAnywhere MFT Starter QuickStart Services (LN02004) |
| GoAnywhere Premium Bundle w/ Threat Protection (LN08044) | GoAnywhere MFT Premium QuickStart (LN02005) **+** Clearswift ICAP QuickStart (LN09073) **+** MFT Expert Certification ILT (LN02030) |
| GoAnywhere Enterprise Bundle (LN08022 / sub LN09037) | GoAnywhere MFT Enterprise QuickStart (LN02006) + MFT Expert Cert (LN02030) |
| Endpoint DGMC Subscription - SaaS On Prem (DG03007) | Fortra Cares - Digital Guardian (DG06101) |
| DG Data Protection Platform for DLP - SaaS (DG09008) | Fortra Cares - Digital Guardian (DG06101) |
| DP Select – Essentials/Plus/Advanced (DG08001-08005) | DG Setup - MM Only (DG06019) |
| DMARC Protection (AG04001) / Agari DMARC up to 10M…10B (AG05008-05016) | Onboarding - DMARC Protection (AG04023) |
| Cloud Email Protection (AG04000) | Onboarding - CEP (AG04024) |

> **RCA translation:** **ProductRelatedComponent** with `IsComponentRequired = true` / min-quantity 1, but **removable subject to approval** — i.e. a *required* component that an **approval rule** can waive. The "With Approval" semantics tie into the approval matrix (§5 / FORTRA_KNOWLEDGE_BASE design approvals). Notably maps "Fortra Cares" support and "QuickStart/Onboarding" services as enforced attach items.

---

## 5. Pricing Notes — `Pricing Notes.docx`

[Pricing Notes.docx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Pricing%20Notes.docx) — short but high-signal narrative on the **legacy pricing model**. Verbatim-derived rules:

**Prices**
- **Maintenance** is priced **as a fraction of the perpetual item; in the price book it is stored as zero** and computed. (Direct relevance to RCA derived/maintenance pricing — cf. project memory on Maintenance Derived Pricing & `Source_List_Price__c`.)
- Other **$0-priced items** may be **priced case-by-case** (manual).
- **Tiered items** use a unit label; **tiers are set at the price level** and a tier can be a **total price for the tier, a unit price, or a formula**. **Formulas can include a financial parameter (assets or revenue)** → confirms attribute/financial-driven tiered pricing (cf. SC-3384 `Attribute_Tier_Pricing_Storage`, AttributeVolumePricing).

**Discounts** (stacking order matters — see Approvals)
- **Hardware discounts (for non-production servers):** moved from Experlogix into a D365 table. "**None**" = that hardware type has no discount; any other text (≠0) = some set of server types do get a discount. → links to `hs_servertype` non-production values (DR / HA / Test / Staging / Development / Online Non-Production) in §6.
- **Partner discounts:** available across the board; **stored in Contracts or input on the opportunity/quote**.
- **Term-length discounts:** on some tiered-pricing items; some SKUs are **sold only at certain subscription lengths** (e.g. **Beyond Security** — cf. `BS_3YearTermError`).
- **Regional discounts:** available for some **one-time and recurring services** (cf. RCA `RegionalServicesPricingPrehook` in project memory).
- **Bundle pricing:** either (a) **children discounted off list** (the §3.3 multiplier rows), **or** (b) **price set at the bundle level** when splitting income across brands isn't required.

**Approvals**
- **Typically based on a percentage of list price** — and the basis is the **price AFTER partner, hardware, and term-length discounts**. → defines the discount-stacking sequence and the approval threshold basis for the RCA approval matrix. (`UpliftCheck` enforces a max uplift; approval matrix lives in the design KB.)

---

## 6. Hardware Model — `hs_hardware` (D365 custom entity)

Fortra licenses much legacy software **per machine/server**, so quoting needs a structured **hardware/server object**. The D365 custom entity is **`hs_hardware`**. Three files describe it.

### 6.1 Field metadata — `Fortra Hardware Object Metadata.xlsx`

[Fortra Hardware Object Metadata.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Fortra%20Hardware%20Object%20Metadata.xlsx) — sheet `hs_hardware attributes`, **106 rows × 12 cols** (`LogicalName, SchemaName, DisplayName, AttributeType, Description, EntityLogicalName, IsAuditEnabled, IsCustomAttribute, IsLogical, IsPrimaryId, IsPrimaryName, RequiredLevel`). Excluding D365 platform/system fields (createdby, owner, statecode, *Yomi*, version, etc.), the **business-meaningful custom fields** (`hs_*`) to re-create on the RCA hardware object are:

| Field (LogicalName) | Display Name | Type | Required | Notes |
|---|---|---|---|---|
| `hs_hardwarename` | System/Server Name/Computer Descript. | String | — | **Primary name** of the record |
| `hs_hardwareidnumber` | Hardware ID | String | Recommended | external/legacy id |
| `hs_computerid` | Computer ID (Legacy) | String | — | |
| `hs_computernumber` | Computer Number | Integer | — | |
| `hs_computerdescription` | Computer Description | String | — | |
| `hs_account` | Account | Lookup | **ApplicationRequired** | owning customer |
| `hs_brandaccount` | Brand Account | Lookup | — | |
| `hs_productbrand` | Product Brand | Lookup | — | |
| `hs_product` | Product | Lookup | — | the licensed product |
| `hs_model` | Model | Lookup | — | |
| `hs_featurecode` / `hs_featurecodenumber` | Master Feature Code / Feature Code | Lookup / String | — | IBM feature code |
| `hs_servertype` | **Server Type** | **Picklist** | **ApplicationRequired** | prod vs non-prod (drives hardware discount) — values §6.3 |
| `hs_serverlocationtype` | Server Location Type | Picklist | — | On-Prem / Cloud / Hosted — values §6.3 |
| `hs_hostoperatingsystem` | Host Operating System | Picklist | — | OS — values §6.3 |
| `hs_hostname` | Hostname | String | — | |
| `hs_serialnumber` | Serial Number | String | — | |
| `hs_numberofprocessors` | # of Processors | Integer | — | |
| `hs_cpw` | CPW | Double | — | IBM i processing capacity (Commercial Processing Workload) — capacity-based licensing |
| `hs_groupnumberlist` / `hs_groupnumbers` | Group Number List / Group Number | Picklist / String | — | IBM i software group (P05–P60 mapping) §6.3 |
| `hs_pgrouplist` / `hs_pgroup` | P Group List / P Group | Picklist / String | — | IBM i processor group §6.3 |
| `hs_mcpsystemtype` | MCP System Type | Picklist | — | Unisys MCP ClearPath models §6.3 |
| `hs_os2200systemtype` | OS2200 System Type | Picklist | — | Unisys 2200 ClearPath models §6.3 |
| `hs_clustered` | Clustered | Boolean | — | |
| `hs_hardwaretype` | Hardware Type | Boolean | — | |
| `hs_lpardescription` | LPAR Description | String | — | logical partition (IBM) |
| `hs_parenthardware` | Parent Hardware | Lookup | — | self-referential hierarchy (LPAR→host) |
| `hs_quoteid` | Quote | Lookup | — | links hardware to a Quote |
| `hs_order` | Order | Lookup | — | |
| `hs_invoice` | Invoice | Lookup | — | |
| `hs_entitlement` | Entitlement | Lookup | — | |
| `hs_shipto_countryid` / `hs_shipto_stateprovinceid` | Ship To Country / State | Lookup | — | new lookups (replace OBSOLETE picklists below) |
| `hs_shiptoaddress1/2/3`, `hs_shiptoaddresscity`, `hs_shiptoaddresszipcode` | Ship To Address lines | String | — | |
| `hs_shiptoaddresscountry`, `hs_shiptoaddressstateprovince` | (OBSOLETE) Ship To Country / State | Picklist | — | superseded by the `…_countryid`/`…_stateprovinceid` lookups |
| `hs_migrationchange` | Migration Change | Boolean | — | "disables custom plugins for the message; data-migration steps set it true" — **migration control flag** worth replicating |
| `hs_importmappingacctnumber` | ImportMappingAcctNumber | String | — | migration helper |

Note `hs_serverlocationtype.Description` explicitly says: *"Add a new field below 'Server Location Type' on the Hardware Form View with dropdown options"* — i.e. this metadata sheet was used as a build spec.

> **RCA translation:** create an equivalent custom object (e.g. `Hardware__c` / asset-extension) or extend the **Asset** model, since hardware is the install-base context for per-machine licensing, maintenance renewals, and **non-production hardware discounts**. The `hs_parenthardware` self-lookup and LPAR fields model IBM i / mainframe partition hierarchies.

### 6.2 Option-set value catalogs — `HardwareOptionSets.xlsx` / `.csv`

[HardwareOptionSets.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/HardwareOptionSets.xlsx) has 2 sheets: `Sheet1` (202r — pivot/row-label list of values) and **`HardwareOptionSets` (192r × 5c)** — the authoritative value map: `Entity, Attribute, Global Name, Value (integer), Label-English`. All on entity `hs_hardware`. The [HardwareOptionSets.csv](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/HardwareOptionSets.csv) is a 10-line stub listing only the attribute row-labels (no values) — effectively empty/superseded by the xlsx.

The integer **option values all carry the `717710xxx` HelpSystems publisher prefix** (D365 managed-solution option-set base). When recreating in Salesforce, the **labels** carry forward; the integer codes do not (Salesforce picklists use API names, not integer option values) — but the integer map is needed for **migrating existing `hs_hardware` records** (legacy data → SF picklist label).

### 6.3 Picklist values (the catalogs to recreate)

**`hs_servertype`** (drives non-production hardware discount — see Pricing Notes §5):
`Production` (717710000) · `Online Production` (717710007) · `Test` (717710001) · `Staging` (717710002) · `Development` (717710003) · `Online Non-Production` (717710008) · `DR` (717710004) · `HA` (717710005) · `???` (717710006, junk value to drop).
→ Non-production set eligible for hardware discount = **Test, Staging, Development, Online Non-Production, DR, HA**.

**`hs_serverlocationtype`** (no Global Name — local option set):
`On-Prem` (0) · `Cloud` (1) · `HelpSystems Hosted` (2) · `3rd Party On-Prem Hosted` (3) · `HS One` (4). → "HelpSystems Hosted" / "HS One" should likely be **renamed to Fortra-branded** equivalents in RCA.

**`hs_hostoperatingsystem`** (Global `hs_operatingsystem`), 18 values:
`AIX, HP-UX Itanium, HP-UX PA-RISC, IBM Power, Linux, Linux Itanium, Linux POWER, Linux zSeries, Mac, Solaris SPARC, SunSolaris, Unix, VMWare, Windows, zSeries, MCP ClearPath, 2200 ClearPath, Other`. (Sheet1 pivot also lists `2200 ClearPath` first.)

**`hs_groupnumberlist`** (Global `hs_groupnumbers`) — IBM i software tier groups, 12 values:
`GROUP 100, GROUP 200, GROUP 250, GROUP 300, GROUP 400, GROUP 500, GROUP 600, GROUP 700, GROUP 800, GROUP 900, GROUP 950, GROUP 1000` (values 717710000–717710011, with 250 inserted at …011).

**`hs_pgrouplist`** (Global `hs_ibmipgroup`) — IBM i processor groups, 7 values:
`P05, P10, P20, P30, P40, P50, P60` (717710000–717710006).

**`hs_mcpsystemtype`** (Unisys **MCP ClearPath** models) — **118 values** (`717710000`–`717710117` + `Any System` at 717710118). Range: `A1…A19, A2100/A2400/A2800, CC3100, CS180…CS890 + CS4080…CS8490 series, DE1000, EA1100/EA1400, FS550…FS6290 series, GE0500/1000/1500, LX5/6/7/100, MICROA, MP4101, NX4200…NX6830, SJ1200, SP1760, VMDEMT, VM-VSE, VSE400…VSE550, XE1000`.

**`hs_os2200systemtype`** (Unisys **OS 2200 ClearPath** models) — 20 values + `Any System` (717710020):
`1100/90, 2200/100, 2200/200, 2200/400, 2200/500, 2200/600, 2200/900, 2200/1010, 2200/3400, 2200/3800, 2200/8010…2200/8080, 2200/9010, 2200/9020`.

> These large mainframe model catalogs (Unisys MCP / OS2200, IBM i P-groups & CPW) confirm Fortra's legacy install base spans **IBM Power/i, Unisys ClearPath, AIX/HP-UX/Solaris/zSeries** — capacity- and model-tier-based licensing that the RCA pricing model and attribute-based pricing must accommodate.

---

## 7. How this maps to the SF RCA / Workday / MuleSoft target

| Legacy D365/Experlogix artifact | Target in Salesforce RCA |
|---|---|
| Experlogix `ERR`/`REQ` rules (prereqs, qty=1, primary-license) | **ProductConfigurationRule** (Validation) / Constraint rules |
| Experlogix `ALW` (conditional reveal) | Configurator option visibility / qualifying conditions |
| Experlogix `EXC` (mutual exclusion) | Constraint (exclusion) rules; `ClearAll` likely retired |
| Experlogix `LNK`/`SLK` (auto/suggested add) | **ProductRelatedComponent** (required vs default-on-removable) |
| `Bundle Items D365` BOM | **ProductComponentGroup** + **ProductRelatedComponent** (Sequence/Quantity) |
| Bundle multiplier/discount % rows | child-level price adjustments **or** bundle-level pricing (per Pricing Notes choice) |
| `RequiredItemsSetUpInD365` ("With Approval") | required components waivable by **Approval** rules |
| `hs_hardware` entity + option sets | custom Hardware object / Asset extension + picklists |
| `…Owned` (`F:…Owned`) flags | **Asset / install-base lookup** at config time — *new integration requirement* |
| Header rules (currency, legal entity, reseller, term length, uplift) | **Quote-level validation** (flow / validation rules), not product rules |
| Maintenance "RF" auto-attach + $0-in-pricebook maintenance | **Derived / maintenance pricing** procedure (cf. project memory) |
| Tiered formula pricing (assets/revenue) | **Attribute-based / volume tiered pricing** (cf. SC-3384) |
| Non-production hardware discount table | pricing adjustment keyed on `Server Type` ∈ non-prod set |
| Partner discount (Contracts/quote) | RCA contract pricing / partner discount schedules |

**Workday / MuleSoft:** none of these files reference Workday or MuleSoft directly — they are upstream (configuration/quoting) of the order→financial handoff. The connection is indirect: bundle composition and required-item rules determine the **line structure** that later flows Quote→Order→Workday (relevant to the line-type / split-line work in project memory, e.g. SC-3347/SC-3210), and the multi-currency header rule (`CurrencyError`) anticipates the SC-3384 multi-currency pricing issue.

---

## 8. Open Questions / Ambiguities

1. **"…Owned" flags (`F:AMProfOwned`, `F:IMCOREPRODOWNED`, etc.)** — the legacy configurator consulted the customer's existing install base. RCA must source this from **Assets / entitlements** at configuration time. Confirm the data source and whether it's available in the configurator context.
2. **Which `ClearAll` / `…RF` maintenance rules port to RCA vs. are obsolete** under RCA's native state management and derived-maintenance pricing? Likely retire the 35 `ClearAll` and replace `RF` with derived pricing — needs confirmation.
3. **Full bundle BOM** — the extract is truncated at 400 of 3,148 rows (Core-AAS connector list dominates). The complete `LN_*` GoAnywhere bundle compositions live partly in the Experlogix `LNK` rules but the **authoritative quantities** for all 3,148 rows need re-extraction from the original xlsx before migration.
4. **Non-production hardware discount table** — Pricing Notes says the values were moved into "a d365 table" but **that table is not in this folder.** The actual discount %s per server type are missing — sourced elsewhere.
5. **`hs_servertype` value `???` (717710006)** — junk legacy value; drop on migration.
6. **"2" file vs "Previous version" naming** — the folder labels the 334-row export "Previous version," but it contains newer modification dates than the 124-row "ExperlogixRules 2." Treat 334-row as master; confirm which the migration team considers current.
7. **`TS_Over3000Users`** message/name mismatch (3000 vs 10000) — clarify the real quantity cap for the Tripwire(?) subscription SKU.
8. **Tiered formula pricing on "assets or revenue"** — confirm which financial parameter each tiered SKU uses and how it surfaces in RCA attribute-based pricing (ties to SC-3384 `Attribute_Tier_Pricing_Storage`).

---

## Sources

All under [`Fortra Discovery Documentation/Pricing and Products/Quoting Rules for D365`](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365):

- [ExperlogixRules 2.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/ExperlogixRules%202.xlsx) — curated 124-rule subset (6 cols).
- [Previous version/ExperlogixRules.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Previous%20version/ExperlogixRules.xlsx) — **master** raw 334-rule export (20 cols, incl. DisplayMsg & modification audit).
- [Bundle Items D365.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Bundle%20Items%20D365.xlsx) — bundle BOM (3,148 rows; **extract truncated at 400 non-empty rows** — tail is Core-AAS connector enumeration).
- [RequiredItemsSetUpInD365.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/RequiredItemsSetUpInD365.xlsx) — 62 required-item ("With Approval") rows.
- [Fortra Hardware Object Metadata.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Fortra%20Hardware%20Object%20Metadata.xlsx) — `hs_hardware` attribute metadata (106 fields).
- [HardwareOptionSets.xlsx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/HardwareOptionSets.xlsx) — option-set value catalogs (192-row value map).
- [HardwareOptionSets.csv](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/HardwareOptionSets.csv) — **stub** (10 lines, attribute names only; superseded by the xlsx).
- [Pricing Notes.docx](Fortra%20Discovery%20Documentation/Pricing%20and%20Products/Quoting%20Rules%20for%20D365/Pricing%20Notes.docx) — narrative on legacy price/discount/approval model.

**Read in full; none encrypted/binary/empty.** Two extracts were length-truncated by the extraction step (noted inline): `Bundle Items D365.xlsx.txt` (400 of 3,148 rows) and large single-file pages handled via paging. `HardwareOptionSets.csv` is intentionally a near-empty stub.

**Related KBs:** target RCA model in `FORTRA_KNOWLEDGE_BASE.md` (design docs); pricing/approval and tiered-pricing detail connect to project memory on Derived/Maintenance Pricing, SC-3384 multi-currency & attribute-tier pricing, and line-type/split work (SC-3347/SC-3210).
