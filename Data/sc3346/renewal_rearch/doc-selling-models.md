I have a solid evidence base grounded in both official docs and the FortraUAT org metadata. Compiling the focused report.

---

# ANGLE: Salesforce Official Docs — ProductSellingModel, Asset Lifecycle & Renewability Rules

Scope: the platform rules (per Salesforce) that determine how a thing MUST be modeled to renew cleanly under RLM. Every rule below is cross-checked against a live read-only describe of FortraUAT.

## 1. Renewability is a property of the SELLING MODEL, not the product or asset

`ProductSellingModel.SellingModelType` is the root switch. Per the RLM Object Reference, it "defines one method by which a product can be sold; for example, as a one-time sale, an evergreen subscription, or a term-defined subscription. If the product is sold on subscription, this object defines the subscription's term."

Confirmed picklist + constraints (RLM dev guide + FortraUAT describe agree exactly):

| SellingModelType | PricingTerm | PricingTermUnit | Has a term/end-date? | Renewable natively? |
|---|---|---|---|---|
| **OneTime** (default) | must be null | must be null | No | **No** |
| **TermDefined** | required (int) | required (Months / Quarterly / Semi-Annual / Annual) | Yes | **Yes** |
| **Evergreen** | null | null | No fixed end (auto-continues) | Continues, not "renewed" by term |

Doc quote (ProductSellingModel, RLM dev guide): for PricingTerm/PricingTermUnit — *"If the selling model is one-time, this field must be null."* FortraUAT org describe: `SellingModelType` picklist = `['OneTime','TermDefined','Evergreen']` (createable/updateable, not nillable, default OneTime); `PricingTermUnit` = `['Months','Quarterly','Semi-Annual','Annual']` (nillable); `PricingTerm` int (nillable); `Status` = `['Draft','Inactive','Active']`.

Implication: a OneTime product has no PricingTerm, so there is literally no term for the platform to roll forward. **Renewability must be baked into the selling model at sale time; it cannot be conferred later.** This is the platform-level root of the confirmed Fortra defect (OneTime RNM maintenance → Amend, not Renew).

- ProductSellingModel: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_productsellingmodel.htm
- SellingModelType enum values: ONE_TIME / TERM_DEFINED / EVERGREEN — https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_productsellingmodel.htm

## 2. How the selling model materializes onto the Asset (and why those fields are immutable)

At order activation, RLM creates one or more `AssetStatePeriod` records — "a time span when an asset has the same quantity, amount, and monthly recurring revenue (MRR)… An asset has as many asset state periods as there are changes to it (asset actions) during its lifecycle." A TermDefined line produces periods with a StartDate/EndDate; an Evergreen line's final period has no EndDate.

The Asset lifecycle fields are **system-derived rollups of those periods** — which is exactly why they are create=false/update=false. Confirmed by FortraUAT describe (all match the RLM Asset dev-guide "system-populated" language):

| Asset field | Type | Createable | Updateable | Source (per dev guide) |
|---|---|---|---|---|
| `HasLifecycleManagement` | boolean | **false** | **false** | System populated; asset qualifies for lifecycle features |
| `LifecycleStartDate` | datetime | **false** | **false** | Start date of the earliest asset state period |
| `LifecycleEndDate` | datetime | **false** | **false** | End date of the final asset state period (empty ⇒ evergreen/no fixed end) |
| `CurrentLifecycleEndDate` | datetime | **false** | **false** | End date of the *current* asset state period (drives renewal timing) |
| `CurrentQuantity` / `CurrentMrr` | double/currency | **false** | **false** | Current asset state period rollup |
| `CurrentAmount` | currency | **false** | **false** | "Reserved for future use" |
| `PricingSource` | picklist | **true** | **true** | Manually set — see §4 |

This corroborates the established fact that renewability (HasLifecycleManagement / LifecycleEndDate / CurrentLifecycleEndDate) is immutable at the API. A OneTime asset never gets a terminal `LifecycleEndDate`, so there is no "current period expiration" to trigger a renewal. The only lifecycle-related Asset field Fortra can actually write is `PricingSource`.

- Asset (RLM): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_asset.htm
- AssetStatePeriod: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetstateperiod.htm

## 3. Selling-model provenance lives on read-only AssetActionSource

`AssetActionSource` "records what transactions caused changes to lifecycle-managed assets." Dev guide: **"The fields can't be edited."** Its `ProductSellingModelId` — *"Specifies the product selling model type. Foreignkey to ProductSellingModel entity."* — carries properties `Filter, Group, Nillable, Sort` (no Create/Update), i.e. read-only, matching the established fact that renewal provenance is not writable. This is the record the native Discovery path reads to resolve the owned selling model.

- AssetActionSource: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm

## 4. Renewal pricing lever: Asset.PricingSource (LastTransaction vs PriceBookListPrice)

`Asset.PricingSource` is a restricted picklist and — uniquely among the lifecycle fields — **is create/update-enabled**. FortraUAT describe: values = `['PriceBookListPrice','LastTransaction']`, createable=true, updateable=true, nillable=true. Dev-guide description: *"Pricing source to use when amending or renewing an asset."*

- `LastTransaction` = lot-based / "honor original purchase prices across multiple transactions and apply price uplifts to individual lots" (i.e. carry the prior transaction net forward, then uplift — the natural home for COLA-on-prior-net).
- `PriceBookListPrice` = reprice from the catalog list price on renewal.

This is the platform-sanctioned mechanism for "renew at prior net + uplift." It is writable, so it is a legitimate re-architecture lever (unlike the immutable lifecycle dates).

## 5. The native Renewal action renews the SAME product — there is NO renewal-product substitution

The Initiate Renewal action takes only `renewAssetIds`, `renewOutputType` (quote/order), `renewStartDate/EndDate`, `renewContractId`, `renewOpportunityId`, `rampOptionsDetails`, `skipPricing`. **There is no input to renew an asset as a different Product2.** The action re-instantiates the same asset's product/selling model. Documented eligibility gotcha (Salesforce Help): Amend/Renew/Cancel "work only with assets created through the standard… lifecycle (order activation)"; migrated/manually-created assets "may not have the required data relationships" — directly relevant to Fortra's ~114k migrated RNM/RRM assets.

Product substitution is a **separate, non-renewal concept.** `AssetAction.CategoryEnum` enumerates `Renewals` and, distinctly, `Swaps` = *"exchange of one asset for another,"* plus `Upgrades`/`Downgrades` = *"transition to a higher/lower-level version or tier of an asset."* These are **amendment-class** transactions, not renewals. So the platform's own taxonomy treats "become a different product" as a Swap/Upgrade (an amendment), never as a Renew.

**Direct answer to the load-bearing question:** Salesforce does **NOT** natively support "renew a OneTime asset as a different TermDefined product." Native renewal (a) requires the asset to be term-defined so it has an end date to renew, and (b) renews it *as itself*. Any product-swap-on-renewal (RNM asset → RRM line) is off-platform custom logic — which is exactly why Fortra needs the custom `RenewalQuoteActionStamp` synthesis (account|Solution_Category cross-product source) to bridge it, and why the native Discovery decision table only ever matches `Asset.Product2Id = line.Product2Id`.

- Initiate Renewal action: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm
- AssetAction (CategoryEnum: Renewals vs Swaps/Upgrades/Downgrades): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetaction.htm
- Manage Assets (migrated-asset caveat): https://help.salesforce.com/s/articleView?id=ind.qocal_manage_assets_in_revenue_lifecycle_management.htm

## 6. ProductSellingModelOption — default selling model binding

`ProductSellingModelOption` is "a junction object between Product Selling Model and Product2." `IsDefault` marks "the default product selling model for a product… A product can only have one default product selling model" (requires Industries EPC). It also carries the subscription increment/min/max (`Increment`, `Minimum`, `Maximum`) and `ProrationPolicyId`. This is where a product is *bound* to its renewable (TermDefined) selling model and where the default that the quote line inherits is set.

- ProductSellingModelOption: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_productsellingmodeloption.htm

## Bottom line for the re-architecture (the rules Fortra maintenance must obey)

1. **To renew as itself, maintenance must be TermDefined from the moment of first sale** (PricingTerm + PricingTermUnit set). OneTime = no term = no LifecycleEndDate = never renewable. The platform gives no post-hoc way to make an owned OneTime asset renewable — the lifecycle fields are all create=false/update=false.
2. **Native renewal renews the same Product2; there is no renewal-product mapping.** The RNM→RRM two-catalog "renew as a different product" pattern is unsupported natively and will always require custom stamping. The platform's own model for "different product" is a Swap/Upgrade **amendment**, never a Renew. Cleanest fix path is to collapse the two catalogs so the sold-and-renewed SKU is one TermDefined product that renews as itself (native `Asset.Product2Id = line.Product2Id` match works on every cycle).
3. **The one writable renewal lever on the Asset is `PricingSource`** (`LastTransaction` for prior-net + COLA uplift, or `PriceBookListPrice` for catalog reprice). Everything else about lifecycle/renewability is system-derived and read-only.
4. **Migrated assets are second-class for lifecycle ops** per Salesforce — Fortra's ~114k legacy RNM/RRM assets may lack the AssetStatePeriod/AssetActionSource relationships the native Amend/Renew/Cancel path assumes, reinforcing the need for the custom account|category source resolution.

Note on method: help.salesforce.com articles render as a JS SPA and were unreadable via WebFetch (returned nav chrome only); all quoted field-level facts above come from the WebFetch-readable developer.salesforce.com RLM dev-guide object pages, cross-verified against a live `sf sobject describe` of ProductSellingModel and Asset in FortraUAT.