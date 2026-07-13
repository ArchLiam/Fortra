Research complete. Here is my focused, evidence-backed report for the Salesforce official-docs angle.

---

# ANGLE: Salesforce Native Renewal Pricing, Uplift & Derived/Maintenance Pricing on Renewals

Primary source: **RLM Developer Guide v67.0 (Summer '26)** full PDF, extracted and grepped locally (`resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf`). Field-level quotes below are verbatim from that guide. Help-article narrative confirmed via search-index extraction of `help.salesforce.com` (the SPA does not render in WebFetch, but the indexed body text was retrievable).

## 1. How native RLM prices a renewal line ("Run Salesforce Pricing")

Native renewal pricing hinges on one field: **`Asset.PricingSource`** (picklist, API v60+):
> "Pricing source to use when amending or renewing an asset. Valid values are: **LastTransaction**—Last Transaction; **PriceBookListPrice**—Price Book or List Price."

- **LastTransaction** = the renewal line is priced from the asset's *last negotiated net*, carried forward via the pricing procedure. This is the intended default for subscriptions so that a renewal reprices from what the customer actually paid, not from current list.
- **PriceBookListPrice** = renewal reprices to current catalog list (uplift is *ignored* on this setting — confirmed by help/CPQ docs).

The renewal itself is created by the **Initiate Renewal** action (`actions_obj_renew_assets.htm`): inputs `renewAssetIds`, `renewStartDate`, `renewOutputType` (quote/order), `skipPricing`. It produces a `QuoteAction.Type = Renew` (picklist values: `Add, Amend, Cancel, No Change, Renew, Transfer`). "Run Salesforce Pricing" then executes the org's pricing procedure over the renewal lines; `PricingRecalculationType = Force` reprices all lines.

This is exactly the native mechanism Fortra's established facts describe: TermDefined → `QuoteAction=Renew` → LastTransaction priced node → commit. Fortra's defect is that OneTime RNM maintenance can't reach `Renew`/LastTransaction and falls into the derived path.

## 2. Native renewal UPLIFT model (this is the headline — Fortra is reimplementing it)

Salesforce shipped a **first-class renewal-uplift model in Winter '26 (API v65)**, exactly what Fortra hand-rolls as COLA. Two tiers:

**(a) Flat negotiated uplift — `UnitPriceUplift`.** On `AssetStatePeriod` (and carried on `QuoteLineItem`):
> "**UnitPriceUplift** (percent, v65+): Indicates the percentage increase of a line item's unit price."

A rep sets a flat % at time of sale; it is stored on the asset state period (which also holds `Mrr`) and auto-applied when the renewal quote is generated. Requires `PricingSource = LastTransaction` and term subscriptions only.

**(b) Policy/CPI-driven uplift — `PriceRevisionPolicy` + `IndexRate`.** `AssetStatePeriod.PriceRevisionPolicy` (reference, v65+): "Specifies the price uplift policy associated with this asset state period." The **`PriceRevisionPolicy`** object (v65+):
> "Represents the guidelines and methods used to modify prices… incorporating formulas based on… the regional Consumer Price Index (CPI) with a specific adjustment percentage, effective from a defined date, categorized as either a flat adjustment or one directly based on price revision entry data."

Fields: **`PolicyType`** picklist = `Flat` ("can't define a price index-based formula") or `PriceIndex`; **`Formula`** (coded formula, e.g. `MAX(PriceIndex + 5, 8)`); **`Region`**; **`EffectiveFrom` / `EffectiveTo`**. The CPI numbers live in **`IndexRate`** (v65+; fields `Region`, `UsageType=Pricing`, plus rate/dates) and are also surfaced as a delivered **"Index Rate" Decision Table**. At renewal the engine resolves `Formula` → looks up the valid `IndexRate` for the region/period → adds the negotiated spread (`UnitPriceUplift`) → produces the renewal net.

Requirements (help articles `ind.qocal_renewal_price_uplifts.htm`, `ind.qocal_consumer_price_index_and_price_uplifts.htm`): **both uplift methods require `PricingSource = LastTransaction` and work only on term-based subscriptions** — not one-time, evergreen, or usage. This is the same boundary that breaks Fortra's OneTime RNM maintenance.

## 3. Derived / attribute pricing on renewals — native intent

Derived pricing = a product's price is a **formula referencing a *contributor*** (another line/product/asset), e.g. `PERCENTAGE(ListPrice, 10)`. The pricing waterfall exposes `ContributorUnitPrice`, `ContributorSource` (Product/Header), `ContributorScope` (Transactional/NonTransactional), `DerivedPricingAttribute` (IsDerived). A **Discovery Procedure** (AssetDiscovery / Fetch Pricing Rules / Map Products steps) gathers the contributor data before the pricing procedure runs.

Two pieces of evidence that **native derived pricing is amendment-scoped, not standard-renewal-scoped**:

1. The staleness field **`ValidationResult = MissingContributor`** on QuoteLineItem/OrderItem: "the quote contains a derived product but not its pricing source." Native RLM *blocks* a transaction when a derived line can't find its contributor — it does not silently null it. (Fortra's failure mode — silent `NetUnitPrice=null` — is the custom path swallowing what native would flag.)
2. The QuoteLineDetail/OrderItemDetail objects are documented as capturing "negative quantity reductions, early renewals, **derived pricing or repricing during an amendment**, and bundle… reconfigurations." The phrase "derived pricing… during an amendment" recurs 4× and never pairs derived pricing with *standard* renewal. Native renewals lean on **LastTransaction carry**, not re-derivation.

Auto-adding derived add-ons is governed by **`enableAutoAddDerivedAsset`** (v62+): "automatically add assets with derived pricing to a quote/order **when contributing products are added to it**" — i.e., new-business/amendment when the contributor line is *added*, not renewal of an already-owned asset. This is the native equivalent of Fortra auto-adding maintenance, and it too is contributor-add-triggered.

**Conclusion for the re-architecture:** Salesforce does *not* intend derived pricing to be the renewal-pricing engine. Derived/contributor pricing is for *composed/bundled* pricing at add-time and for amendments; **renewals are meant to reprice from LastTransaction + an uplift policy.** Fortra's `DerivedProductsNonRenewal` filter (`QuoteTypeText<>'Renewal'`) is actually *aligned* with native intent — the bug is that maintenance is modeled such that it *needs* the derived path on renewal at all.

## 4. Salesforce's guidance: how maintenance/support that renews should be priced

The native pattern for anything that recurs and renews (maintenance, support, SaaS) is: **model it as its own term-based subscription selling model**, set `PricingSource = LastTransaction`, and attach a `UnitPriceUplift` / `PriceRevisionPolicy` for the annual increase. That single asset then renews as `QuoteAction=Renew` at its carried net × uplift. If maintenance must be *derived* from a license list price, native supports that via a derived PBE (`enableAutoAddDerivedAsset`) — but the *derivation happens at sale/amendment*, and the resulting maintenance asset should itself be TermDefined so it **renews on LastTransaction, not re-derives**. Native also offers `enableAsIsRenewal` (v64+) and Billing's `AsIsRenewal` sub-action to renew each schedule at its own quantity/net — the "carry exactly what they had" case with no uplift.

There is **no native concept of a separate "renewal catalog" SKU** (Fortra's RNM→RRM two-catalog design). Native uses one asset whose selling model + PricingSource + uplift policy fully determine renewal behavior. Fortra's RNM/RRM split is a legacy CPQ-era workaround that native RLM was explicitly designed to eliminate.

## 5. Contrast with Fortra — is Fortra reimplementing native? (Yes.)

Direct repo evidence that Fortra hand-rolls what is now native:

- The org **already carries the native uplift fields** — `force-app/main/default/objects/QuoteLineItem/fields/UnitPriceUplift.field-meta.xml` and `PriceRevisionPolicyId.field-meta.xml` exist (they come with the RLM package). **But grep across all Apex classes and Flows for `UnitPriceUplift` / `PriceRevisionPolicy` returns ZERO references.** The native uplift machinery is present and completely unwired.
- COLA is 100% custom: `COLAUpliftHandler`, `COLAUpliftPrehook`, `COLAUpliftCalculator`, `RenewalMaintenancePricingService`, driven by **`COLA_Uplift_Rules__mdt`** with fields `Default_Uplift_Percent__c`, `Solution_Category__c`, `Effective_Start_Date__c`, `Effective_End_Date__c`, `Is_Active__c` — instantiated as 20+ per-category records (Brand_Protection, GoAnywhere, Cybersecurity, …).

`COLA_Uplift_Rules__mdt` is a near-exact hand-built clone of a **`PriceRevisionPolicy` with `PolicyType=Flat`**:

| Fortra custom (`COLA_Uplift_Rules__mdt`) | Native equivalent (`PriceRevisionPolicy` / `UnitPriceUplift`) |
|---|---|
| `Default_Uplift_Percent__c` | Flat adjustment % / `AssetStatePeriod.UnitPriceUplift` |
| `Solution_Category__c` (partition key) | `PriceRevisionPolicy.Region` (partition key) |
| `Effective_Start/End_Date__c` | `EffectiveFrom` / `EffectiveTo` |
| `Is_Active__c` | Effective-date validity window |
| (no CPI — flat only) | `PolicyType=PriceIndex` + `IndexRate` (unused capability) |

Fortra's COLA is a **flat, per-solution-category** uplift — it maps cleanly onto native `PriceRevisionPolicy(Flat)` + `UnitPriceUplift`, and Fortra is *not* using the CPI/`IndexRate` tier at all (so no native capability is lost by adopting; only capability is gained).

## 6. Bottom line for the re-architecture

1. **Adopt native renewal uplift.** The Flat-policy path (`PriceRevisionPolicy` PolicyType=Flat, keyed by a Region-mapped-to-Solution-Category, + `UnitPriceUplift` spread) is a 1:1 replacement for `COLA_Uplift_Rules__mdt` + the COLA Apex/Flow stack. The fields already exist in the org, unused. This retires `COLAUpliftHandler/Prehook/Calculator` and `RenewalMaintenancePricingService`.
2. **The precondition is the same fix Fortra already proved** (2026-07-10): make maintenance renew as `QuoteAction=Renew` on `PricingSource=LastTransaction`. Native uplift *only fires* on LastTransaction + term subscriptions — so maintenance must be a **TermDefined** selling model, not the OneTime RNM. That single modeling change (RNM OneTime → one TermDefined maintenance subscription) simultaneously (a) fixes the null-net defect, (b) eliminates the RNM/RRM two-catalog split, and (c) unlocks native uplift so COLA can be deleted.
3. **Stop routing maintenance through derived pricing on renewals.** Native intent = derive at sale/amendment, renew via LastTransaction. If maintenance stays derived-from-license, ensure the derived maintenance asset is itself TermDefined so it renews on its carried net (native would otherwise raise `MissingContributor` rather than null it — which is the safer failure mode to inherit).

### Cited sources
- RLM Developer Guide v67.0 (Summer '26), full PDF: https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf (PriceRevisionPolicy, IndexRate, AssetStatePeriod.UnitPriceUplift, Asset.PricingSource, ValidationResult=MissingContributor, QuoteAction.Type, RevenueManagementSettings enableAsIsRenewal/enableAutoAddDerivedAsset, Billing SimplifiedRenewal/AsIsRenewal/DeltaPriceAmend)
- Negotiate Price Uplifts for Subscription Renewals: https://help.salesforce.com/s/articleView?id=ind.qocal_renewal_price_uplifts.htm
- Use Consumer Price Index for Automated Renewal Price Uplifts: https://help.salesforce.com/s/articleView?id=ind.qocal_consumer_price_index_and_price_uplifts.htm
- Amending, Renewing, and Canceling Assets: https://help.salesforce.com/s/articleView?id=ind.qocal_manage_assets_in_revenue_lifecycle_management.htm
- Apply Contract Pricing When Amending or Renewing: https://help.salesforce.com/s/articleView?id=ind.qocal_amend_and_renew_assets_with_contract_pricing.htm
- Initiate Renewal Action (dev guide): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm
- Salesforce Pricing overview (dev guide): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/pricing_overview.htm
- Trailhead — Explore Derived Pricing and Discovery Procedures: https://trailhead.salesforce.com/content/learn/modules/advanced-price-management-with-revenue-cloud/explore-derived-pricing-and-discovery-procedures
- Trailhead — Manage Customer Asset Renewals and Cancellations: https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations
- Fixed vs CPI uplift explainer: https://thecloudupdate.co/revenue-cloud-renewal-uplift/ (403 to WebFetch; content via search index)

Local artifacts (for reuse by other angles): extracted dev-guide text at `/private/tmp/claude-501/-Users-liamjeong-Documents-Code-Fortra/1a1c15cd-2cb9-4780-8bf3-c7c97523dce3/scratchpad/rlm.txt` and PDF `rlm_dev_guide.pdf`.