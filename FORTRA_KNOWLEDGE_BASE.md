# Fortra Salesforce Revenue Cloud — Knowledge Base

> Consolidated reference distilled from the `Confluence/` export (31 documents, as of the
> Oct 2025 – Apr 2026 review cycle). Use this as the orientation map for any Fortra work;
> the full-fidelity source is the raw Confluence export `.doc` files in `Confluence/` (MIME/HTML —
> open in a browser or text editor for the complete content this KB summarizes). When a detail
> here conflicts with the live org, **the org wins** — verify field/object state by retrieving
> from FortraUAT before scoping a deploy.

---

## 1. System Landscape & Systems of Record

Fortra is consolidating multiple legacy CRMs onto **Salesforce Revenue Cloud Advanced (RCA)**,
implemented with partner **Coastal**, with **Workday** as the financial back end and **MuleSoft**
as the integration layer. **BSI** (Business Systems & Innovation) owns integration build.

**End-to-end flow:**
```
Quote (Salesforce) → Order (Salesforce) → Contract (Salesforce)
      → Contract (Workday) → Invoice (Workday)
```

| Data domain | Source of Truth | Secondary / consumer |
|---|---|---|
| SKU / Product master (commercial definition) | **Salesforce RCA** | Workday (mirror subset) |
| Official price lists | **Salesforce RCA** | Workday (reference only — must NOT re-price) |
| Quotes, Orders, Amendments | **Salesforce RCA** | Workday (consumes) |
| Contracts & Invoices | **Workday** | Salesforce (status visibility) |
| Product hierarchy / internal naming | **PowerBI "Product Mapping"** (SharePoint/Fortra Hub) | Salesforce, Workday, Adaptive |

**Guiding principles**
- One-way master-data sync: Salesforce → MuleSoft → Workday. **No manual SKU creation in Workday.**
- Event-driven sync for transactions (orders/amendments); daily scheduled reconciliation for drift.
- **Immutable SKU Code** — once created the identifier never changes.
- **Effective dating** on pricing — versioned, never overwritten; no overlapping effective dates for the same SKU + price list + charge type + billing frequency.
- Workday invoices from **order-line amounts**, never recomputed list prices.

**Legacy source systems** being migrated/retired: **D365** (Dynamics 365), **Tripwire Salesforce**, **Globalscape Salesforce**. During Jan–Feb cutover, D365/Zuora/OrdersX still calculated tax via Avalara; Avalara in Workday was off until March.

**Key go-live context:** target go-live referenced as **July 20, 2026** for renewals automation; auto-renewal brands and order processing being stood up through UAT in mid-2026.

---

## 2. Product Hierarchy (the backbone of everything)

The hierarchy drives SKU codes, pricing, territory routing, COLA, partner pricing, marketing,
reporting, and Workday business-unit mapping. **Source of truth = PowerBI "Product Mapping."**

### 2.1 Six levels (and their many aliases)

| Salesforce level | AKA in other systems |
|---|---|
| **Unit 0.00** | Segment, Family Unit, FAM/0; Workday "Superior Organization Segment" (Cyber/Tech) |
| **Solution Group 1.00** | Sub-Segment, F1 |
| **Solution Category 2.00** | Business Unit, Brand Level, F2 (used on Support Portal KB/Downloads); **= Workday "Fortra Business Unit"** |
| **Solution 3.00** | Product Family, F3 |
| **Feature 4.00** | Software Product Family, F4 (Support Portal case selection) |
| **Product / SKU 5.00** | Actual SKUs on quotes/orders |

> Strategy: move away from 18,000+ D365 SKUs to "pick the solution, then pick attributes
> (users, server type, etc.)" — SKUs collapse to Level 3/4 plus configurator attributes that
> drive price, key generation, and provisioning. Levels **0.00 (Unit)** and **2.00 (Solution
> Category)** are considered set/locked; 3.00/4.00/5.00 were the review targets.

### 2.2 Unit → Solution Group → Solution Category values

- **Units:** Cyber, Tech, Corporate.
- **Solution Groups:** Cyber → Defensive Security, Offensive Security, (XDR); Tech → RPA+, Power, Managed File Transfer; Corporate → Fortra Corporate.
- **Solution Categories** (Group → Categories):
  - **Defensive Security:** Vulnerability Management, File Integrity Monitoring, Email Security, Brand Protection, Human Risk Management, Data Protection, Cloud Data Protection, Fortra Platform. *(Offensive Security is also tracked here in COLA/screening contexts.)*
  - **Offensive Security:** Offensive Security.
  - **Managed File Transfer:** GoAnywhere, Globalscape.
  - **Power:** Business Intelligence, Doc Management, Systems Management, Cybersecurity (+ "Power" generic).
  - **RPA+:** Robotic Process Automation, Core IGA, Network Monitoring, Powertech Identity & Access Manager (BoKS), Capacity Management, Business Intelligence, Doc Management, Systems Management, Cybersecurity, IPP.
  - **IPP / Fortra Platform:** IPP (0% COLA, "no current SKUs" for Fortra Platform).

> **D365 migration mapping caveats:** "Beyond Security" & "Digital Defense" → Vulnerability
> Management; "Clearswift" → Brand Protection; "Terranova" → Human Risk Management; "Automate"
> → Robotic Process Automation; BoKS/Capacity Mgmt/Core IGA/InterMapper → RPA+ (historically
> labeled "Hybrid"). Many legacy brands (Robot, Sequel, Halcyon, CCSS, Bytware, Showcase,
> Tango, Safestone, Doc Management) collapse into **Power**. (Ref `Product Hierarchy Updates D365`, ticket BSS-23284.)

### 2.3 Marketing Products (`Marketing_Product__c`)

Custom **reference table** (not Product2) representing products at any of three levels (Unit /
Solution Group / Solution Category) for **territory assignment, product-interest tracking,
campaign attribution**. Fields: `Marketing Product Name`, `Unit__c`, `Solution_Group__c`,
`Solution_Category__c`, `Active`.

- **One-to-one sync** required with the **Products of Interest** global picklist — names must match exactly or territory-assignment logic fails.
- Deprecate by setting `Active = false` (never delete — preserves historical relationships).
- Managed **only by admins**. Quarterly review recommended.
- Territories reference Marketing Products indirectly via hierarchy fields; one Marketing Product can back many `Sales_Territory__c` rows with different geo/industry/named-account criteria.

---

## 3. Hierarchy-Field Change Runbook (admin-critical)

The hierarchy is **not** one model: some fields are shared picklists, some dependent picklists,
some plain text. **Primary risk: `Product2` stores Unit/Solution Group/Solution Category/Solution
as TEXT, so metadata changes do not cascade — text data must be remediated by hand.**

### 3.1 Field types by level

| Level | Model |
|---|---|
| `Unit__c` | Shared value set **`Unit`**; controlling field for `Solution_Group__c` on 3 objects |
| `Solution_Group__c` | Dependent picklist on 3 objects, **TEXT** on `Product2` and `Partner_Discount_Matrix__c` |
| `Solution_Category__c` | Dependent picklist on 3 objects, shared picklist on `Campaign`, **TEXT** on `Product2` & `COLA_Uplift_Rules__mdt` |
| `Solution__c` | **TEXT** on `Product2` only |

### 3.2 Where each field lives

- **`Unit__c`** picklist on: `Product2`, `Marketing_Product__c`, `Sales_Territory__c`, `AccountTeamMember`, `Lead`. Formula `Product_of_Interest__c.Product_Unit__c` derives `TEXT(Marketing_Product__r.Unit__c)`.
- **Dependent mappings** (`Unit__c`→`Solution_Group__c`) configured on `Marketing_Product__c`, `Sales_Territory__c`, `AccountTeamMember`.
- **`Solution_Category__c`** also on `Campaign` (picklist) and `COLA_Uplift_Rules__mdt` (text, External ID); `QuoteLineItem.COLA_Solution_Category__c` (historical/reporting text).

> **Known data quirk:** `AccountTeamMember` has the **Power and RPA+ category sets reversed**
> vs `Marketing_Product__c`/`Sales_Territory__c`. Preserve unless explicitly correcting.

### 3.3 Hard-coded references (must be hand-edited on rename/remove)

| Field | Component(s) with hard-coded dependency |
|---|---|
| `Unit__c` | `Inquiry_Conversion_Screen_Flow` (Cyber/Tech visibility), `Screen_Flow_Partner_Portal_Deal_Registration_Form` (Cyber/Tech lookups & decision) |
| `Solution_Group__c` | `displayAndFilterKnowledge.js`, `Partner_Product_Compliance_Alert` (CASE values), `PowerOrderSplittingService` (`= Power`), `RCATechnicalProductService` (copies to technical products) |
| `Solution_Category__c` | `Fortra_Bulk_Price_Update_Flow` (manual category list), `COLAUpliftPrehook`, `COLAUpliftHandler`, `RCATechnicalProductService` |
| `Solution__c` | `RCATechnicalProductService` (copy at creation), `Product_Record_Page_UAT`, mirrored to `ssot__Product__dlm`, `Revenue_Model__dlm` |

Dynamic (no hard-code, but test): `TerritoryFlowHelper`, `Sales_Territories_Before_Insert_Update`,
`Sales_Inquiry_Territory_Assignment`, `Fortra_BulkPriceUpdateInvocable`/`Batch`, `Marketing_Product_Record_Page`.

### 3.4 Execution order for any hierarchy change
1. Update metadata (value sets / dependent mappings) first.
2. Update text-field records second (`Product2`, `Partner_Discount_Matrix__c`, technical products, CMDT).
3. Update hard-coded references third.
4. Run the exact validation path (Automation Test Matrix) for the changed field.

> Technical products created by `RCATechnicalProductService` copy hierarchy values **at creation
> time and do not self-correct** — existing ones need data fixes on a rename.

---

## 4. SKU & Product Database

### 4.1 SKU / Product Code format

```
[Solution Category]-[Solution]-[Rev Category]-[Product]   e.g. BP-DW-RCNM-xxx
```
Built by a spreadsheet VLOOKUP against the `Product Codes` tab (abbreviations per level).
`_LIC` / `_MAINT` suffixes are appended for Subscription-split and maintenance variants.
The full abbreviation list (≈150 Solution abbreviations, Solution-Category codes, Rev-Category
codes) is in the `Sku/Product Code - Fortra Salesforce` doc (`Confluence/Sku_Product+Code+-+Fortra+Salesforce.doc`).

- **Salesforce Product Code** is the official immutable cross-system key linking SF ↔ Workday ↔ legacy.
- **Final SKU Name + License_Type** is the invoice/quote display name (formula; adds `_MAINT` for RC_43120, `_LIC` for RC_41202 non-bundle-parent).
- **Duplicate guardrails:** a new SKU is needed only if **Final SKU name+License type**, **Rev Category** (Finance), or **Tax Code** (Tax team) differs. No duplicate SF Product Code; no duplicate Final SKU + License_Type.

### 4.2 Revenue Categories (Finance — drives Workday rev treatment)

| Rev Cat | Identifier / Name | Rev Schedule Template | Treatment | Selling Model | Term |
|---|---|---|---|---|---|
| RC_41000 | SOFTWARE / Non-Recurring Perpetual – Software | (blank) | Invoice | One-Time | — |
| RC_41200 | SUBSCRIPT / Software Rentals | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_41202 | SUBS SPLIT / Software Subscriptions | Subscription Split | Deferred | Term Based – Renew | 12 mo |
| RC_41204 | SUBS SAAS / SaaS License | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_41205 | SUBS SAAS HOST / SaaS Hosting | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_42000 | NEW MAINT / Recurring New Maintenance | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_43000 | RENEW MAIN / Recurring Renew Maintenance | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_43120 | Renew Maintenance Subs ASC 606 | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_44000 | CHANGE FEE | — | Invoice | One-Time | — |
| RC_45000 | SERVICES / Training | As Delivered | Deferred | One-Time | — |
| RC_45001 | SERV SUP / Set Up | As Delivered | Deferred | One-Time | — |
| RC_45002 | SERV EXP / Expense Reimbursements | Expense Reimbursement | Invoice | One-Time | — |
| RC_45004 | SERV RECUR / Recurring Professional Services | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_45005 | SUBS MSS / Managed Services | Spread_Even | Deferred | Term Based – Renew | 12 mo |
| RC_46000 | OTHER | — | Invoice | One-Time | — |
| RC_47000 | UNISYS SW | — | Invoice | Term Based – Renew | 12 mo |
| RC_48000 | UNISYS SUBS MAINT | Spread_Even | Deferred | Term Based – Renew | 12 mo |

### 4.3 Multi-SKU creation rules

- **Subscription split (RC_41202):** one item needs **3 SKUs** — the bundle parent (`Is Workday Bundle = TRUE`, recognized upfront), a `_LIC` copy (RC_41202, Tax DC010500 software, Spread Even, **non-quotable in SF**), and a `_MAINT` copy (RC_43120, Tax SC100222 maintenance, Spread Even, **non-quotable**). The `_LIC`/`_MAINT` SKUs are **Workday-only**; auto-generated.
- **Perpetual (RC_41000):** requires 2 additional manually-maintained SKUs identical except:
  - **New Maintenance** — RC_42000, Tax SC100222, Add-On, One-Time, $0, related to a Renewal Maintenance SKU (RC_43000).
  - **Renewal Maintenance** — RC_43000, Tax SC100122, Add-On, Term Based–Renew, $0.
  - `Related To` formula links Perpetual → New Maintenance → Renewal Maintenance.

### 4.4 New-SKU database columns (highlights)

The master DB ("All Fortra Products", single source of truth for historical→new mapping) has
~70 columns. Required-on-new-add highlights: hierarchy (Unit/Group/Category/Solution), Final SKU
Name, License_Type, Product Family, Rev Category, Tax Code, USD Price, Product Type (Standalone/
Add-On/Bundle/Bundle Component), Product Selling Model, Term Length, Unit of Measure, Branching.
Legacy-mapping fields (`Legacy System` = D365/Tripwire SF/Globalscape SF, `Legacy productid`,
`Legacy Name`, `Legacy Product Number`, `Legacy Product Brand`) are optional. `Migrate Y/N`,
`Legacy Item? (Legacy Renewal Only / New Sales)` drive filtering and whether the SKU needs RCA build.

**Attribute fields** (drive invoice detail / license-key generation, joined by ` | ` into
`LineItem Description`): PS Services Type, Feature, Pricing Tier, Maintenance Type
(Express/Limited/Premium/Standard/Basic), Unit Type, Number of Units, Deployment Type
(Hosted/Managed/Managed Services/On Premise/SaaS), Server Type (Prod/Dev/DR/HA/Staging…),
Operating System (IBM i, Linux, Windows, OSX, AIX/UNIX…), PGroup (P05–P60), Group Number,
Agent Type, Number of Agents, Clustered. (**Power License Type** attribute removed 2026-05-21 —
replaced with separate Primary/Secondary SKUs.)

Workday-driven derived columns: `Is Workday Bundle`, `Workday Bundle Parent Code`, `Contract
Line Type`, `Is Services Estimate Product (Certinia)`, `Fortra Business Unit` (VLOOKUP → BU code,
e.g. Email Security = BU49), `Fixed or Usage Based`, `Product Classification`.

### 4.5 SKU governance & lifecycle

- Create/update SKUs & prices **only in Salesforce** (RevOps/Product Ops own; Finance owns rev-category/tax/GL mappings; BSI owns pipelines).
- Retire in SF → sync to Workday → blocks new quoting, existing contracts unaffected.
- Salesforce must be able to export: "Official Published Price List," "Current Active SKU Catalog," "SKU Change Log."
- **D365 deactivation review:** mark SKUs inactive when no quotes/invoices in last year, no active system products, not on a price book, or name contains "Do Not Use." `Legacy Product?` / `Experlogix Series` fields distinguish renewal-only from truly dead SKUs.

---

## 5. Pricing

### 5.1 Multi-currency / currency conversion

- Approach: **Single Currency Per Transaction with native Salesforce Multi-Currency**, **USD = corporate currency**.
- USD master price → per-currency **Price Book Entries** generated via Fortra conversion formulas (static stored values). **No conversion at quote time** — the quote inherits currency from the Opportunity and reads the matching PBE directly. Currency is **locked after quote creation** (to change currency, create a new Opp + Quote).
- Native currency fields flow Quote → Order → Asset → Invoice unchanged; profitability uses `CURRENCYRATE()` to normalize to USD.
- **Fixed annual ARR rates** (Dec 2024 set, not live FX; round up to nearest $5): USD 1, ARS 666.6667, AUD 1.5385, CAD 1.3889, CHF 0.8850, EUR 0.9346, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667. Rate table is a **Custom Metadata Type**. Finance reviews annually (optionally quarterly).
- ⚠️ Multi-currency, once enabled, **cannot be disabled**; users see ISO codes before amounts.

### 5.2 Services Regional Pricing

Adjusts **Services** pricing by customer **ShippingCountry** to reflect market rates FX doesn't capture.
- `Services_Regional_Pricing__mdt` (Country, Country_Code ISO, Region, Subregion, **Multiplier 0.4–1.015**, Is_Active, effective dates) → **Decision Table** → pricing-procedure element **inserted right after List Price**.
- Eligibility gate: `Product2.Allow_Regional_Pricing__c = true`. Scope: **New Quote + Amendment** only (renewals use asset price; cancellations excluded).
- Formula: `AdjustedPrice = CEILING(ListPrice × Multiplier / 5) × 5` (round up to nearest 5, all currencies).
- Sample multipliers: South Asia 0.4, LATAM 0.5, SE Asia 0.6, E. Europe 0.64, ANZ 0.65, E. Asia 0.8, W. Europe 0.96, North America 1.0, UK 1.015.

### 5.3 COLA Uplift (renewal price increases)

Automatically applies an annual % increase to **renewal** quote lines by Solution Category, with override.

- **`COLA_Uplift_Rules__mdt`**: `Solution_Category__c` (matches `ProductCategory.Name`), `Default_Uplift_Percent__c`, `Is_Active__c`, `Effective_Start/End_Date__c`, `Description__c`.
- **9 `QuoteLineItem` fields**: `COLA_Uplift_Percent__c` (editable), `Default_COLA_Uplift_Percent__c` (RO), `Pre_COLA_Price__c` (RO, stores Asset.Price for re-calc), `COLA_Solution_Category__c`, `COLA_Applied_Date__c`, `COLA_Modified_By__c`, `COLA_Modified_Date__c`, `COLA_Override_Reason__c`, `Is_COLA_Overridden__c` (formula).
- Components: `QuoteLineItemTrigger`, `COLAUpliftHandler`, `COLAUpliftPrehook`, `COLA_Admin` permission set.
- Trigger path: renewal (`QuoteAction.Type = 'Renew'`) → `Asset.Price` → catalog hierarchy → CMDT lookup → `UnitPrice = Asset.Price × (1 + COLA%/100)`. Override recalcs off `Pre_COLA_Price__c`.
- Relationship: `QuoteLineItem → QuoteAction → Asset → Product2 → ProductCategory`.

**Three-tier override hierarchy** (highest wins, recorded in `COLA_Source__c`):
1. **Line Override** — user edits `QuoteLineItem.COLA_Uplift_Percent__c`.
2. **Contract Override** — `Contract.COLA_Override_Percent__c` set AND `COLA_Override_Persist_Until__c` valid (null = next renewal only; future = until that date; past = expired → ignored). Path extends `Asset → AssetContractRelationship → Contract` (Status `Activated` only). Method `getContractOverrides()`.
3. **CMDT Lookup** — default by Solution Category.

**COLA rates by Solution Category** (Solution Design v2.0):

| % | Solution Categories |
|---|---|
| 9.85 | Robotic Process Automation |
| 7.85 | Network Monitoring, GoAnywhere, Globalscape, Systems Management, Doc Management, Business Intelligence, Cybersecurity, Powertech IAM (BoKS) |
| 6.20 | Vulnerability Management, Offensive Security |
| 5.00 | Email Security, Brand Protection, Human Risk Management, Cloud Data Protection, File Integrity Monitoring |
| 4.70 | Data Protection, Core IGA, Capacity Management |
| 0 | Fortra Platform (IPP) / Default (no match) |

> The granular **`Cola Increase Table`** has Solution-level exceptions, notably **Systems
> Management → MessengerConsole / MessengerPlus / PeekPlus = 12.00%** (vs 7.85% for the rest of
> Systems Management), and Cybersecurity SecureCare/SSO Managed Services = 4.70%. When in doubt,
> check that table for per-Solution overrides.

### 5.4 Partner Pricing V2

Selects the partner pricing model **per quote line** by product hierarchy, and uses a separate
discount field set for **Fortra-Originated** deals. (Tech req last modified 2026-04-24.)

- **`Partner_Pricing_Model__c`** fields: `Account__c`, `Model_Type__c` (Discount | Guaranteed Margin), `Is_Active__c`, `Effective_Start/End_Date__c`; standard `Software_/Subscription_/New_Maintenance_/Renewal_Maintenance_/Services_Percent__c`; hierarchy `Unit__c`/`Solution_Group__c`/`Solution_Category__c` (**one level populated per record**, blank = fallback); `Non_Orig_*_Pct__c` mirror set (used only when `Deal_Type__c = Fortra Originated`).
- **Hierarchy resolution order:** Solution Category → Solution Group → Unit → blank fallback → else 0% (pricing still succeeds). Duplicate at same level → newest `CreatedDate` wins.
- **Participation:** *Discount* = billing partner only. *Guaranteed Margin* = billing partner + reseller + distributor + referral partner (each contributes a positive margin; sum capped at 100%: `List × (1 − total margin)`).
- **Apex assets (DP2 chain):** `PartnerPricingServiceV2`, `PartnerPricingPrehookV2` (+ tests). Keep V1 classes for rollback.
- **Context (`QuoteEntitiesMapping`)** must expose: SalesTransaction → `Partner_Pricing_Model__c`, `Deal_Type__c`, `Billing_Partner__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c`; SalesTransactionItem → `Fortra_Product_Type__c`, `Unit__c`, `Solution_Group__c`, `Solution_Category__c`.
- **Cutover = one line** in `RegionalServicesPricingPrehook.executePartnerPricing()`: `new PartnerPricingPrehook()` → `new PartnerPricingPrehookV2()`. Validate with V2 tests + `RegionalServicesPricingPrehookTest`.
- **Pricing chain order:** List Price → Regional (Services) Pricing → Partner Pricing. Outputs: `Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c`, `Partner_Margin_Detail__c` (JSON), `PartnerUnitPrice`, `PartnerDiscountPercent`.
- **Product-type → percent field map:** Software/Perpetual→Software; New Maintenance→New_Maint; Renewal Maintenance→Ren_Maint; Subscription/SaaS Subscription→Subscription; Services/Professional/Renewal Services→Services.

---

## 6. Quote-to-Order & Order Orchestration

### 6.1 Step-by-step (quote → invoice)

1. Sales rep fills out the **Sales Order Form**.
2. **CSL automation** runs (export screening — §8.3).
3. Routed to **Customer Operations** queue/task by product family.
4. Opportunity → **"Ready to Review for Order"** → screening cleared → Closed Won.
5. **Convert to Order** (auto): Order + OrderItems created, details copied from quote.
6. **Activate Order** (manual).
7. **Staged Assetize** → **Callout: invoice detail to Workday = Point of No Return**.
8. Assets/Contracts/Renewal Opportunity created; customer support-portal access coordinated.

### 6.2 Order Orchestration vocabulary (for fulfillment-process design)

- **Fulfillment Process** = a named collection of Steps (Tasks), applicable to one/many actions: **New (Add), Amend, Renew, Cancel**.
- **Step types:** Auto Task, Manual Task, Milestone (can trigger rev-rec), Pause, Callout (external API), Staged Assetize (creates Asset records for lifecycle).
- **Assignment methods:** Context Based (by account/product/geo/value), Least Loaded, Round Robin. *(Fortra examples: License Gen = Least Loaded; Implementation Services = Context Based; Training = Round Robin.)*
- **Execution Trigger:** Source Line Start Date, or Previous Step's Execute Date.
- **Point of No Return** (True/False): marks irreversible steps (ship hardware, provision perpetual license, third-party contract, **Workday invoice callout**). After this, changes require an **Amendment** rather than editing the Order.

### 6.3 Sales Order Form & routing

- **Routing queues by Solution Group:** Tech Power, Tech MFT, Tech RPA, Tech Hybrid (each a generic owner/queue claimed by team members for **New Sales**; **Renewals bypass** the form and are processed by the closing renewals rep), and **Cyber All** (round-robin to Victoria Mullady's team; `cyber.operations@fortra.com`). Multi-group orders route by Opp owner's group association, else by highest $ amount per group.
- Form is **consolidated** with brand-specific sections (Power, MFT, MFTaaS, GoAnywhere, Clearswift, FileCatalyst, Globalscape, Terranova, Vulnerability Management/beSTORM, etc.).
- **Deal Desk approval PDF required** for ~20 exceptions: Perpetual SW, Annual Increase Change (COLA), Channel MSP Discount, Displaced/Swap ARR, Emailed Quote Acceptance, Hardware Change Fee, Legal Non-Standard (SaaS/On-Prem), Non-Standard Legal Terms, Maintenance Discount, MYCAP, Net Terms, Non-Standard License Type, Offline Quote, Perpetual/Subscription License Discount, SAARC, Services Discount, Subscription Start Date >30 days.
- Indicating services CCs `services.ops@fortra.com`; start date must be the **1st of the month**.

### 6.4 Power Order Splitting / Branching

When a **Power** (`Solution_Group__c = 'Power'`) order line has **Quantity > 1**, split into
qty-1 lines. Behavior is set per SKU via **`Product2.Power_Split_Type__c`**:

| Split Type | Order lines | Hardware | Partitions |
|---|---|---|---|
| **Order Line Only** | split to qty 1 | **SHARED** (all lines → one original `Hardware__c`) | **CLONED** (each line its own `Partition__c`) |
| **Order Line and Hardware** | split to qty 1 | **CLONED** (each line its own hardware) | **CLONED** |

- `Manual_Discount__c` and `Displaced_ARR__c` divided **evenly** across split lines (remainder → first line; rounded to 2 dp).
- `OrderItem` fields: `Hardware__c`, `Partition_Record__c`, `Manual_Discount__c`, `Displaced_ARR__c`, `Is_Split_Line__c`, `Original_Order_Item__c` (audit self-ref).
- Implemented as **`PowerOrderSplittingService`** (`@InvocableMethod`, called from the Quote-to-Order flow post-conversion; bulk-safe, single transaction, ≤4 SOQL). Custom objects: `Hardware__c`, `Partition__c`.

### 6.5 New-sales Start Date defaulting

- Default start date for new sales (current rule: 1st of month; proposed: within first ~5 days → 1st of current month, else 1st of next month — **pending Victoria Mullady's confirmation**).
- Operations can **override** start date during order processing **before contract creation**.
- Validation: **quote expiration date can't exceed line-item start date**; if start date has passed, treat the quote as expired and force correction. (Enforcement location TBD — open for BSI.)

---

## 7. Renewals

### 7.1 Automated Renewals (Salesforce + Workday)

- **Auto-create** renewal quotes **≥ 90 days** before contract expiration.
- **Auto-deliver** controlled by a **solution-level "Send Quote Yes/No"** default with **contract-level override** (Customer Operations only).
- **1–2 business days** between quote creation and delivery (review window). Creation may run on the 1st; delivery on EOD of 1st/2nd business day.
- **Batch/manual release** (e.g. select ~200 in a list view) when auto-delivery is off or during stabilization. Decision: auto-delivery **off for first 1–2 months** post go-live, bulk-send ~200 at a time.
- Renewal flow ends in SF at **Order activation** (then invoicing in Workday). Guard against duplicate auto-renewals per contract.

### 7.2 Paid-Invoice Status Signal (license-key fulfillment)

Connect Workday "invoice paid" status to a Salesforce indicator so ops know what's ready for
license-key delivery.
- Fields: **Paid/Unpaid** indicator, **Paid On** timestamp, **Keys Delivered** completion field — tracked at **contract or order level** (not per-asset; a contract can hold hundreds of assets).
- Trigger: invoice → Paid in Workday updates the linked SF record; dashboards/lists surface "unpaid→paid" and "paid but pending fulfillment."
- Scope: Tech-side **all contracts** (long-term); Cyber **auto-renewal brands** = Offensive Security, Vulnerability Management, Clearswift.
- **Open:** authoritative key to match Workday invoice ↔ SF record (order #, contract ref, invoice ID).

---

## 8. Legal & Compliance

### 8.1 Legal Entities → Currency → Workday Reference ID

Defaulting for **New Sales**: (1) if Billing **Place** = Philippines → **Fortra LLC**; (2) else use
Billing Place's Default Legal Entity / Default Currency if set; (3) else by **Sales Rep location**
(User record). **Renewals always default to the legacy org's prior entity & currency.** Currency
options are constrained per entity. *(Place-level Default Legal Entity/Currency fields are a future
project — not stored in legacy today; ref SC-3298/BUG-MTC-388 Places↔Workday mapping.)*

| Legal Entity | Default cur. (Allowed) | Workday Ref |
|---|---|---|
| Fortra, LLC (Eden Prairie, MN) | USD (EUR, CAD, GBP, JPY, AUD) | COM003 |
| Fortra Canada Inc. | CAD (USD) | COM048 |
| Fortra International GmbH (Zurich) | EUR (USD, GBP) | COM010 |
| Fortra International Limited (UK) | GBP (USD, EUR, JPY, CHF, AUD, CAD) | COM008 |
| Fortra International PTY LTD (Australia) | AUD (USD, NZD, GBP) | COM009 |
| Fortra Argentina S.R.L. | ARS (USD) | COM026 |
| Fortra Computing Group, S.L.U. (Spain) | EUR (USD) | COM025 |
| Fortra Japan KK | JPY | COM071 |
| Terranova Worldwide Corp (renewal only; HRM only) | CAD (CHF, EUR, USD) | COM079 |
| Tripwire Inc. (renewal only; FIM only) | USD | COM074 |
| Clearswift Limited (data-migration only) | GBP | COM043 |
| CCSS Deutschland GmbH (migration only) | EUR | COM016 |
| SafeStone Technologies BV (migration only) | EUR | COM014 |
| Help/Systems International S.A.S (migration only) | EUR | COM011 |
| Clearswift KK (migration only) | JPY | COM047 |
| Terranova Security Europe S.A.S. (migration only) | EUR | COM080 |

> **Philippines** can only bill from Fortra LLC or Fortra International PTY LTD. Long-term goal:
> consolidate US sales (e.g. Tripwire) into Fortra LLC, Canadian sales (e.g. Terranova) into Fortra Canada.

### 8.2 Quote Terms & Conditions

- **Standard (non-partner), all solution groups:** *"This Quote is subject to the terms and conditions set forth in the Fortra Master Solutions Agreement and applicable Solution Specific Schedule(s) located at www.fortra.com/legal."*
- **Partner quotes** (2 types): if Billing Account is an **MSP** → *"This quote is subject to the Partner agreement between the parties."*; if a **non-MSP partner** → *"The partner will pass through the terms at fortra.com/legal to their customer."*; else standard.
- **Override:** Customer Ops Manager and above.
- Legacy T&C verbiage (D365 / Globalscape SF / Tripwire SF) and the large Standard/Enhanced/Renewal quote-template clause library (Tripwire ExpertOps, Resident Engineer, Hardware Refresh, Coterminous Support, etc.) are catalogued verbatim in the `Quote T&C Historical Detail` doc (`Confluence/Quote+T&C+Historical+Detail.doc`).

### 8.3 Export Control Screenings (CSL) — Descartes/OCR API

- **Account fields:** `Consolidated Screening List` (Not Screened/Approved/On Hold/Additional Screening Needed/Denied — Customer Ops edit only), `Date of Last CSL Run`, `Offensive Security Screening Notes` (hidden; permission group = Victoria Mullady & Alex Guderian).
- **Opportunity field:** `Consolidated Screening Status` (same picklist; greyed/hidden on Renewal Opps).
- **API:** Descartes tool (managed by Legal) → OCR (`ocr-inc.com`) sends Account name/ID/ship-to → returns On Hold or Approved. ICANN lookup is a manual nice-to-have/Phase 2.
- **New-sale flow:** screen at **Opportunity Created** and again at **push to Order/Invoice** (can't advance to invoice until Approved). On Hold → Customer Ops review queue. **Approved + Product of Interest = Offensive Security or Email Security (Secure ICAP/Email Gateway)** → status set to **Additional Screening Needed** → rep completes "Export Screening Request" form (end-user name/title, shipping country, detailed use case) → Customer Ops resolves to Approved/Denied (cascades to Account). All other products auto-Approve.
- **Quarterly bulk re-screen** of all active customers (incl. global ultimate parents); false positives escalate to Legal (`contracts@fortra.com`). Future: nightly re-screen that auto-clears holds when sanctions lift.

### 8.4 Export License Documents (ECJU)

For **Offensive Security** and **Email Security (Secure ICAP/Email Gateway)**, certain customer
countries require an export license document at the Account level before processing (legal req of
the UK Export Control Joint Unit).
- Document record fields: `Status` (Active/Expired/Requested), `Document Type` (End User Undertaking, EU General Export Authorization, Open/Standard Individual Export License, US Export Control License – Offensive Security), `Export Control Category` (multi-select: Secure Email/ICAP Gateway, Cobalt Strike, Core Impact, Outflank), Start/End Date, License Number, Default/Regional License checkboxes, Document Link (URL).
- **Automations:** status → Expired when End Date passes; **weekly Monday** email to `cyber.operations@fortra.com` (cc `cyber.renewals@fortra.com`) listing licenses expiring in 90 days; **quote-level approval flow** blocks activation until Customer Ops Export Approval = Yes (Offensive Security) or until a valid (Active, >30 days) document of the correct type exists for the Solution-3 + ship-to country (Email Security). Country requirements come from the "Country specific Export Control List" spreadsheet.

### 8.5 Customer Tax (Avalara)

- Tax code is per-SKU (`Tax Code`, set by the Tax team, e.g. DC010500 software, SC100222 maintenance) and synced to Workday.
- Avalara sandbox on for Jan–Feb; **Avalara off in Workday until March**. During Jan–Feb, D365/Zuora/OrdersX calculated invoice tax. Open items: full Workday SKU+tax-code list, SaaS single-tax-code problem, services-with-SaaS needing separate SKUs for tax. Tax team verifies via a PowerBI report.

---

## 9. Open / In-Flight Workstreams (as of the doc set)

- **SKU/database backlog** (`Sku Changes Needed…`): Power Secondary requires Primary ownership; GoAnywhere partner price changes; branching-SKU quantity handling; Globalscape perpetual MAP + naming consistency + feature review; full Tax Code review (Ashley J.); tiered pricing; deployment-type / SaaS-vs-Managed-Services review; Fortra VM needs separate On-Prem (FT01005) and SaaS SKUs for tax; bundle changes (HRM Essentials/Advanced/Elite BSS-26012, Offensive Security Training BSS-27582, GoAnywhere BSS-24384, Cyber bundle BSS-26010).
- **Internal naming "Source of Truth"** governance via Innovation Center + OTM, change windows 1–2×/year (`Product Info – Hierarchy Changes`).
- **Renewals automation, paid-invoice signal, start-date rules** all have unresolved questions flagged for **BSI**.

---

## 10. Glossary

| Term | Meaning |
|---|---|
| **RCA** | Salesforce **Revenue Cloud Advanced** — SoT for SKU/price/quote/order |
| **Coastal** | Implementation partner building RCA |
| **BSI** | Business Systems & Innovation — owns integrations |
| **DP2** | The chained pricing design / pricing route in RCA |
| **ALE** | Annual License Equivalent (sales metric on order forms) |
| **MYCAP** | Multi-Year Contract Annually Paid (Deal-Desk-gated) |
| **Displaced/Swap ARR** | Existing Fortra ARR being replaced by an order line |
| **COLA** | Cost of Living Adjustment — annual renewal price uplift |
| **CSL** | Consolidated Screening List — export-control sanctions screening |
| **ECJU** | UK Export Control Joint Unit |
| **Place** | Salesforce `Place`/address entity used for Bill/Ship + legal-entity defaulting |
| **Sub Split / `_LIC` / `_MAINT`** | Subscription revenue split into Workday-only license + maintenance SKUs (RC_41202) |
| **Branching / Split** | Exploding a Power qty>1 order line into qty-1 lines + hardware/partitions |
| **Asset-based ordering** | RCA model where Orders create Assets that drive amendments/renewals |

---

## 11. Source Document Index (`Confluence/`)

| Doc | KB section |
|---|---|
| Fortra's Product Hierarchy; Product Info – Hierarchy Changes; Product Hierarchy Updates (New SKUs / D365) | §2 |
| Salesforce Hierarchy Management Runbook | §3 |
| New Sku Database Requirements; Fortra Sku Database Management; Sku/Product Code; Sku Changes Needed; D365 Sku Review – To Deactivate | §4 |
| Currency Conversion for Pricebooks; Services Regional Pricing; COLA Uplift Feature; Cola Increase Table; Partner Pricing V2 (Business + Technical) | §5 |
| Order Orchestration Process; Step by Step; Sales Order Form – Customer Ops field; Power Order Splitting (+ Coastals dup); Product Branching; New Sales Start Date Defaulting | §6 |
| Automated Renewals Requirements; Paid Invoice Status Signal Integration | §7 |
| Legal Entities; Legal T&C; Quote T&C Historical Detail; Export Control Screenings (CSL); Export License Document; Customer Tax – Avalara | §8 |

---
*Generated 2026-06-02 from the `Confluence/` export. Treat percentages, rates, entity IDs, and
field names as point-in-time; confirm against FortraUAT before acting on a deploy.*
