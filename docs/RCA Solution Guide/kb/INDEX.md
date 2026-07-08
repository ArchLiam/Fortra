# RCA Solution Guide — KB Index

Navigable index of the 29 absorbed solution-design KB docs in this folder. Each is a dense, verbatim-preserving synthesis of a Fortra Revenue Cloud Advanced (RCA) solution-design source, written for an AI coding agent doing refactor / RCA migration work.

**Ground-truth caveat:** these are *design-time* docs. Where they touch live pricing, the **live Apex + the active pricing procedure (currently V21) are ground truth** — retrieve before editing. Several docs flag their own source inconsistencies (called out in the invariants section below); those are preserved, not resolved.

**Legend — Refactor?:** `Yes` = contains build-relevant data model / formulas / component names an agent would act on. `Ref only` = near-stub or pointer with no actionable spec.

## Contents
- [Pricing (waterfall + pricing engine)](#pricing-waterfall--pricing-engine)
- [Maintenance (derived pricing)](#maintenance-derived-pricing)
- [Orders](#orders)
- [Quotes](#quotes)
- [Contracts](#contracts)
- [Approvals](#approvals)
- [Migration](#migration)
- [Other (multi-currency, product attributes, stubs)](#other-multi-currency-product-attributes-stubs)
- [Pricing design invariants (cross-cutting)](#pricing-design-invariants-cross-cutting)

---

## Pricing (waterfall + pricing engine)

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra-Pricing-COLA-Solution-Design-Doc.md](Fortra-Pricing-COLA-Solution-Design-Doc.md) | COLA renewal uplift + MyCAP out-year floor | Automated cost-of-living % uplift on renewal quote lines by Solution Category, with Contract/line overrides and a 3% MyCAP multi-year floor. | Yes |
| [Fortra-Pricing-PartnerPricing-Solution-Design-Doc.md](Fortra-Pricing-PartnerPricing-Solution-Design-Doc.md) | Partner margin/discount pre-hook | Applies partner margins (additive Guaranteed Margin) or Billing-Partner discount as waterfall Step 4 via `PartnerPricingPrehook`/`PartnerPricingService`. | Yes |
| [Partner_Pricing_V2_Open_Issues.md](Partner_Pricing_V2_Open_Issues.md) | Partner Pricing V2 pre-build memo | Two unresolved V2 issues: Non-Orig field naming vs behavior contradiction, and silent newest-wins duplicate tiebreak. | Yes |
| [Fortra-Pricing-RegionalPricing-Solution-Design-Doc.md](Fortra-Pricing-RegionalPricing-Solution-Design-Doc.md) | Regional Services country multipliers | Dual Pre/Post-hook applies country multiplier to Services list price, rounds UP to nearest $5, writes NetUnitPrice last. | Yes |
| [Fortra-Pricing-AttributeVolumePricing-Solution-Design-Doc.md](Fortra-Pricing-AttributeVolumePricing-Solution-Design-Doc.md) | Attribute-based volume/tier pricing | Six-dimensional match (Product/PSM/Attr name+value/qty band) sets price via three modes; tiers in `Attribute_Tier_Pricing_Storage__c`. | Yes |
| [Fortra-Products-Hardware-Solution-Design-Doc.md](Fortra-Products-Hardware-Solution-Design-Doc.md) | Hardware attribute pricing (Power) | Prices Power products from hardware attributes (pGroup × user-count × system-type) via `HardwareAttributePricingPrehook` + hardware-group LWC. | Yes |
| [Fortra-Pricing-ARR-Solution-Design-Doc.md](Fortra-Pricing-ARR-Solution-Design-Doc.md) | ARR calculation + propagation | Declarative ARR from PricingTermCount/annualization, propagated QLI→OrderItem→Asset; no Apex. Covers Displaced/Renewal/Amendment ARR. | Yes |

## Maintenance (derived pricing)

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra-Maintenance-Derived-Pricing-Solution-Design.md](Fortra-Maintenance-Derived-Pricing-Solution-Design.md) | Derived maintenance pricing (v1.0, Jun 6) | Original design: price auto-added maintenance lines as source list price × tier rate via `Source_List_Price__c` + Stamp flow + List Container 9 formula; NO Apex prehook. | Yes |
| [Fortra-Maintenance-Derived-Pricing-Solution-Design_(1).md](Fortra-Maintenance-Derived-Pricing-Solution-Design_%281%29.md) | Derived pricing — New Business & Renewals (v1.0, Jun 9) | Hand-off state: new-business branch built+validated (`Base_Price__c` × tier); renewal branch built-unvalidated, blocked on BR-005. | Yes |

## Orders

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra-Orders-Configuration-Solution-Design-Doc.md](Fortra-Orders-Configuration-Solution-Design-Doc.md) | Q2O foundational config | Order types, Legal Entity propagation flow, custom Order/OrderItem fields, FLS, and `AssetContractLinkerAction` (ACR creation) — deploy before downstream. | Yes |
| [Fortra-Orders-MultiCurrency-Solution-Design-Doc.md](Fortra-Orders-MultiCurrency-Solution-Design-Doc.md) | Legal-Entity-driven currency | Account default Legal Entity deterministically drives currency top-down Opp→Quote→Order via two record-triggered flows + conversion framework. | Yes |
| [Fortra-Orders-Ops-Checklist-Solution-Design-Doc.md](Fortra-Orders-Ops-Checklist-Solution-Design-Doc.md) | Q2O operations gate | 37-item ops checklist on Quote (LWC + MDT + services) that hard-blocks Quote-to-Order conversion until every item is checked. | Yes |
| [Fortra-Orders-OrderLineSplitting-Solution-Design-Doc.md](Fortra-Orders-OrderLineSplitting-Solution-Design-Doc.md) | Power line splitting | `PowerOrderSplittingService` decomposes Power OrderItems (Qty>1) into qty-1 lines (one Asset/unit), update-in-place + savepoint; clones Hardware/Partition. | Yes |
| [Revenue_Cloud_Order_to_Asset_Lifecycle.md](Revenue_Cloud_Order_to_Asset_Lifecycle.md) | End-to-end lifecycle | Five-phase Order→assetize→billing→renewal(COLA/succession)→amendment lifecycle; AUA-gated silent-failure design captured. | Yes |

## Quotes

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra-Quotes-Amendments-Solution-Design-Doc.md](Fortra-Quotes-Amendments-Solution-Design-Doc.md) | Contract amendments | Contract "Amend" override builds amendment Quote via asset-origin chain + `initiateAmendment`; co-termination flows + 5 validation rules. | Yes |
| [Fortra-Quotes-Create-New-Quote-Solution-Design-Doc.md](Fortra-Quotes-Create-New-Quote-Solution-Design-Doc.md) | Quote creation flow | Screen Flow with 7-check validation pipeline, Places→address mapping, 30+ Opp→Quote field map, Deal Origin derivation. | Yes |
| [Fortra-Quotes-QuoteManualDiscount-Solution-Design-Doc.md](Fortra-Quotes-QuoteManualDiscount-Solution-Design-Doc.md) | Header manual discount distribution | Quote-level discount distributed across QLIs (Percentage / Amount Equal or Proportionate); per-unit DiscountAmount caps + lock polling. | Yes |
| [Fortra-Quotes-QuoteSubscriptionDates-Solution-Design-Doc.md](Fortra-Quotes-QuoteSubscriptionDates-Solution-Design-Doc.md) | Bulk subscription dates | TLE bulk StartDate/EndDate/Term editor (Date Range / Date & Term modes) for TermDefined lines; partial-success DML + header sync. | Yes |
| [Quote_Line_Auto_Population_Solution_Design_(1).md](Quote_Line_Auto_Population_Solution_Design_%281%29.md) | Companion auto-add/remove | Migrates CPQ Product Rule "Add" to `Quote_Line_Companion_Rule__c` + two flows: auto-add companion QLIs, cascade-remove on delete. | Yes |

## Contracts

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra-Contract-Renewals-Solution-Design-Doc.md](Fortra-Contract-Renewals-Solution-Design-Doc.md) | Contract renewals | Renew action + 120-day window monitor + renewal-Quote enrichment + COLA pricing + MyCAP + contract succession. | Yes |
| [Fortra-Contracts-Configuration-Solution-Design-Doc.md](Fortra-Contracts-Configuration-Solution-Design-Doc.md) | Contract lifecycle config | 19 custom fields, 2 VRs, 6 flows, Path Assistant, role-based amendment restrictions, 120-day renewal automation, calendar-month proration. | Yes |

## Approvals

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Fortra_Approvals_Solution_Design_Document.md](Fortra_Approvals_Solution_Design_Document.md) | Approvals (conceptual) | HIGH-LEVEL multi-dimensional (Line/Bundle/Quote) flow-orchestration approval vision; NO objects/fields/thresholds — thresholds live in external matrix. | Yes |
| [Fortra_Approvals_Maintenance.md](Fortra_Approvals_Maintenance.md) | Approvals (flow build) | 15 approval checkbox fields → per-condition criteria flows → megaflow Cyber/Tech split → Quote Status Approved/Rejected; business-term only (no API names). | Yes |

## Migration

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Quote_QuoteLineItem_Comprehensive_Migration_Guide.md](Quote_QuoteLineItem_Comprehensive_Migration_Guide.md) | Quote/QLI data migration | Field-mapping + population-method spec for Historical vs In-Flight quote loads into RLM; PlaceQuote recalc rules, 8 population codes, AUA requirement. | Yes |

## Other (multi-currency, product attributes, stubs)

| Doc file | Domain | One-line purpose | Refactor? |
|---|---|---|---|
| [Exchange_Rate_Snapshot_Solution_Design.md](Exchange_Rate_Snapshot_Solution_Design.md) | Multi-currency FX snapshot | Captures txn-currency→USD rate at QLI/Opp/OrderItem via one `DatedConversionRateLookup` invocable; 3-phase Apex for Workday downstream. | Yes |
| [Revised_Fortra_Legal_Entity_Solution_Designdocx.md](Revised_Fortra_Legal_Entity_Solution_Designdocx.md) | Legal Entity multi-currency | Decouples currency from Legal Entity via `Legal_Entity_Currency__mdt`; declarative-only (CMDT+flows+VR+quick action), no Apex. | Yes |
| [RCAFeatureOptionSplit.md](RCAFeatureOptionSplit.md) | Product attribute proposal | Near-stub: proposes splitting one "Feature Option" attribute into 24 category-scoped `<Category>_Options` attributes (names only). | Yes |
| [ProductAttributeUpdatesbyFortra.md](ProductAttributeUpdatesbyFortra.md) | Product attribute maintenance | Near-stub runbook mapping 16 attribute/pricing maintenance tasks to RCA objects; "retire" undefined. No fields/formulas. | Yes |
| [Fortra_Product_Mapping_Links.md](Fortra_Product_Mapping_Links.md) | Placeholder | Effectively empty — one line pointing to an external "All Fortra Product Spreadsheet". | Ref only |

---

## Pricing design invariants (cross-cutting)

Load-bearing rules that recur across the pricing docs. Treat these as constraints when refactoring the pricing engine.

### Waterfall order
Canonical conceptual waterfall (per Hardware/Regional/Partner docs):

```
List Price → Hardware Attribute → Regional Services (Pre) → Partner → Attribute Volume → COLA Uplift → Final
                                    (Regional Post-Hook writes NetUnitPrice as LAST writer, after the pricing procedure)
```

- Pre-hook Procedure Plan `Fortra_Pricing_PreHook` sections: **Regional §1, Partner §2, AttributeVolume §3, Price Procedure §4**. Partner is described as "Step 4" in its own doc (after Regional, before COLA) — the section numbering and the conceptual step number differ; preserve both framings, don't collapse.
- Regional runs **twice**: Pre-hook adjusts UnitPrice before the procedure; Post-hook writes NetUnitPrice after (reads `RegionalNetUnitPrice__c` to survive the procedure's PriceRevision step) and chains to `PartnerPricingPosthook` via `Type.forName()`.

### Core formulas (verbatim)
| Feature | Formula |
|---|---|
| COLA | `UnitPrice = Pre_COLA_Price__c × (1 + COLA%/100)` — `Pre_COLA_Price__c` = Asset.Price, preserved across all overrides |
| Partner — Guaranteed Margin | `List × (1 − SUM(all partner margins%))` — **ADDITIVE** (15%+10% = 25% off, NOT compounded) |
| Partner — Discount | `List × (1 − Billing Partner Discount%)` — Billing Partner only |
| Regional | `CEILING((ListPrice × Multiplier) / 5) × 5` — round **UP to nearest $5** |
| Hardware | `List × pGroup_Mult × UserCount_Mult × (1 − SystemType_Discount/100)` |
| ARR | `TotalLineAmount / PricingTermCount × annualization` (Annual 1×, Semi 2×, Quarterly 4×, Monthly 12×); 0 for OneTime/null/zero-term |
| Attribute Volume | Unit Price → `Base_Price__c` to InputUnitPrice; Calculated → `Base_Price__c × AttributeMultiplierPct__c`; Total Price → `Base_Price__c` to ItemNetTotalPrice |
| Maintenance (new business) | `NetUnitPrice = Base_Price__c × tierRate` (Premier 0.30, Standard 0.20, Professional 0.20, else 0) — multiplies the STAMPED field, not NetUnitPrice |
| Maintenance (renewal) | `(Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA/100)` |
| Manual Discount (Amount) | per-unit `DiscountAmount = lineDiscount / Quantity`, capped at UnitPrice; Proportionate `lineDiscount = total × (lineSubtotal / totalSubtotal)` |
| Subscription term ↔ dates | term = `CEILING((EndDate − StartDate + 1) / 30.0)`; endDate = `ADDMONTHS(StartDate, Term) − 1 day` |

### Tier orders / precedence
- **COLA override precedence** — *documented discrepancy, preserved:* Section 6 is **four-tier** `Line Override > MyCAP Default (3% floor) > Contract Override > CMDT Lookup`; Sections 7.1/10.1 (and the Renewals/Lifecycle docs) call the trigger path **three-tier** `Line > Contract > CMDT` with MyCAP injected by the prehook. `COLA_Source__c` stamps the winning tier.
- **Hardware attribute precedence:** `Configurator (QLIA) > Hardware__c defaults > System defaults (P20 / Production / 1 user)`; stamped in `Hardware_Pricing_Source__c`.
- **Maintenance tier rates:** Premier 0.30, Standard 0.20, Professional 0.20, else **0** (the $0 trap for blank/retired tiers).
- **Partner product-type → margin field map:** Software/Perpetual→`Software_Percent__c`; New Maintenance→`New_Maintenance_Percent__c`; Renewal Maintenance→`Renewal_Maintenance_Percent__c`; Subscription/SaaS→`Subscription_Percent__c`; Services/Professional/Renewal Services→`Services_Percent__c`.
- **Contract COLA override date gate:** `COLA_Override_Persist_Until__c` NULL = valid forever; ≥today = valid; past = expired → fall back to CMDT.

### Field types (load-bearing)
- COLA: `COLA_Uplift_Percent__c`, `Default_COLA_Uplift_Percent__c` = **Number(5,2)**; `Pre_COLA_Price__c` = **Currency**. `Is_COLA_Overridden__c` TRUE iff the two percents differ.
- Partner margins: five **Percent(5,2)** fields on `Partner_Pricing_Model__c` (Master-Detail to Account).
- Regional `Multiplier__c` = **Number(4,2)** — *flagged inconsistency:* range includes `1.015` (3 decimals) which the declared type can't hold.
- Exchange rate: `Exchange_Rate_To_USD__c` = **Number(18,10)** on QLI / Opportunity / OrderItem; USD & blank ISO → 1.0, unknown → null.
- Maintenance/derived base: `Source_List_Price__c` / `Base_Price__c` = **Currency**; both **must be hydration-mapped into the `_v2` SalesTransaction pricing context** or the formula reads null.

### Context API / prehook contract
- Prehooks implement `RevSignaling.SignalingApexProcessor`; read via `Context.IndustriesContext.queryTags()`, write via `updateContextAttributes()`. **NO direct DML** in a pricing context (defer to a Queueable, e.g. `MyCAPFlagApplier`).
- Only include **mapped OUTPUT attrs** in `updateContextAttributes` — including an **input-type** attribute silently **poisons the whole batch**.
- Audit fields need **`inputoutput`** directionality on `SalesTransactionContextExt` to survive a reprice; **output-only fields are nullified on reprice**.
- All hooks **always return SUCCESS** (fail-safe — never block pricing) and use a **static Boolean recursion guard**; delete-state / non-updatable-context exceptions are caught and swallowed.
- When pricing does **not** apply, **null out the feature's output fields** on all lines (stale-value clearing) rather than leaving prior values.

### Rounding
- **NOT specified** in source for COLA, Partner, ARR, Attribute Volume, and Maintenance — do not invent one; confirm against live behavior.
- Explicit only where stated: **Regional** = `CEILING` up to nearest $5; **Manual Discount** = `HALF_UP` to 2 decimals; **Subscription term** = `CEILING` on `/30.0`.

### Migration guardrail
- Tier-3 SP fields are calculated by **PlaceQuote** and **MUST NOT be loaded**: `NetUnitPrice`, `NetTotalPrice`, `TotalLineAmount`, `ItemTotalAdjustmentAmount`, `ItemTotalAdjustmentDistAmount`, `TotalPrice`, `TotalTaxAmount`, `RoundedLineAmount`, `ProformaBillingPeriodAmount`, `Subtotal`. Loaded values are overwritten. Every migrated Quote needs an `ApplicationUsageAssignment` with `ApplicationUsageType = 'RevenueLifecycleManagement'`.
