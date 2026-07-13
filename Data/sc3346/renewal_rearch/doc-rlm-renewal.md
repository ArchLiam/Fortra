I have comprehensive coverage from the authoritative developer.salesforce.com RLM Dev Guide. The help.salesforce.com pages are JS SPAs that render only navigation (as anticipated). Here is my focused report.

---

# ANGLE: Salesforce-Native RLM Renewal Model (Official Docs)

**The platform-intended reference model to re-architect toward.** All quotes are from the Revenue Management Developer Guide v67.0 (Summer '26) unless noted. Evidence is direct-quoted; where official docs are silent I flag it explicitly.

## 1. The end-to-end native renewal flow (as designed)

Native RLM renewal is a **four-stage pipeline**: (1) discover what's renewable → (2) invoke Initiate Renewal → (3) async engine generates a renewal Quote (or Order) with per-line QuoteActions → (4) on activation, Create/Update Asset From Order writes an AssetAction (category "Renewals") and a new asset state period. Each stage has a documented standard invocable action.

```
Get Renewable Assets Summary  →  Initiate Renewal  →  [async] Renewal Quote w/ QuoteActions
        (orderId)                (renewAssetIds…)          ↓ Create Order
                                                    Create/Update Asset From Order (orderId)
                                                          ↓
                                        AssetAction (Category=Renewals) + new Asset State Period
```

Trailhead confirms the UI-driven version of stage 2–4: from an asset the user "click[s] the **Renew** button", the system "generates a renewal quote", the user picks **Create Order**, and on activation "a new Asset Action is created with **Renewals** set as the business category. Additionally, a new Asset Start Period is generated to reflect the updated renewal dates."
(https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations)

## 2. Stage 1 — Get Renewable Assets Summary (discovery)

**Endpoint:** `POST /services/data/v67.0/actions/standard/getRenewableAssetsSummary`
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_get_renewable_assets_summary.htm

- **Input:** `orderId` (ID, required) — "ID of the order related to the assets to check for renewal opportunities." **Note the native design is ORDER-scoped**, not account/contract-scoped.
- **Output:** `renewableAssetsSummary` (Apex-defined) — "Summary of the assets associated with the order, including details about renewal opportunities such as renewal pricing information." Output fields include: `assetId`, `account`, `productId`, `priceBookId`, `priceBookEntryId`, `orderItem`, **`lastAssetAction`, `lastAssetActionSubtype`**, `renewalPriceDetails (quantity, netUnitPrice)`, `rootAssetOpportunity`, `startDate`, `endDate`.
- Constraint: "This action doesn't support providing a summary with procedure plans."

Load-bearing for re-architecture: the native summary keys renewal pricing off the asset's **last AssetAction + subtype** and pre-computes `renewalPriceDetails.netUnitPrice` per asset — i.e., the platform expects the renewable asset itself to carry the priced source.

## 3. Stage 2 — Initiate Renewal action (the core)

**Endpoint:** `POST /services/data/v67.0/actions/standard/initiateRenewal` (available API v60.0+)
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm

| Parameter | Type | Req | Exact description |
|---|---|---|---|
| `renewAssetIds` | string | **Yes** | "The IDs of the assets that you want to renew." |
| `renewOutputType` | string | **Yes** | "Type of renewal record to create such as a quote or an order." |
| `renewStartDate` | datetime | Cond. | "Effective start date of the renewal… Required for early asset renewals and renewing expired assets." (v62.0+) |
| `renewEndDate` | datetime | Opt | "Effective end date of the renewal." (v62.0+) |
| `renewContractId` | string | Opt | "ID of the contract record to sync with the renewal quote." |
| `renewOpportunityId` | string | Opt | "ID of the Opportunity record to sync with the renewal quote." |
| `skipPricing` | boolean | Opt | "Indicates whether the pricing procedure must be skipped (true) or performed (false)." (v64.0+) |
| `rampOptionsDetails` | Apex-defined | Opt | Ramp segment type/duration/count (v67.0+) |

- **Output:** `renewRecordId` ("The ID of the … record that's created") + `requestIdentifier` ("Request ID that's used to track the async request") — **the action is asynchronous**; it returns a tracking ID, and the renewal Quote/Order is materialized by the platform engine, not inline.
- Design notes for re-architecture:
  - `renewOutputType` = **Quote** vs **Order** is the native branch point. Fortra's `Fortra_Create_Renewal_Quote` flow (which "overrides native initiateRenewal") is a substitution for exactly this action.
  - `renewStartDate` is **required for expired/early renewals** — the native path explicitly supports late renewals and trial extensions by choosing new dates (corroborated by Trailhead: "renew expired assets and subscriptions by choosing new start and end dates").
  - `skipPricing=true` is the native lever to create renewal lines **without** running the pricing procedure — relevant because Fortra's defect is precisely that the RNM-derived line never becomes a priced node. Natively you either let the procedure price it or explicitly skip; there is no documented "silently null" path.

**Contrast — Initiate Amendment** (`POST …/initiateAmendment`, v60.0+) requires `amendAssetIds`, `amendStartDate`, `amendOutputType`, **and `quantityChange`** ("Quantity to add to or reduce from the asset's existing quantity"), with optional `amendContractId`/`amendOpportunityId`/`skipPricing`. Key native caveat: for usage products "set this value to Quote" not Order, because direct-to-order "lacks necessary Rate Card Entry records."
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_amend_assets.htm

The takeaway: **Renew and Amend are distinct native actions with distinct endpoints and inputs** (Amend needs a quantity delta; Renew needs a term/date window). Fortra's confirmed defect — a OneTime RNM asset being force-routed to `QuoteAction=Amend` instead of Renew — is a *departure* from the native model, which would only Amend on an explicit quantity-change intent, and would not have a "renew" of a OneTime asset at all (see §6, renewability).

## 4. Stage 3 — QuoteAction (the per-line transaction type)

Object: `QuoteAction`, "Indicates the type of sales transaction that's being quoted; for example, a renewal sale." (API v59.0+)
Source (dev guide): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_quoteaction.htm

**Default behavior (load-bearing):** "If a quote doesn't have a quote action, Salesforce treats it as a quote of the **Add** type. When such a quote is used to create an order, Salesforce automatically creates an order action of the Add type."

Fields:
- `QuoteId` (lookup → Quote) — "The quote related to this quote action."
- `SourceAssetId` (lookup → Asset, nillable) — "The asset changed by this sales transaction. For example, if the quote action is a quantity amendment, this field contains the ID of the asset that's amended." **This is the native asset-provenance link** — the analogue of what Fortra's `RenewalQuoteActionStamp` synthesizes.
- `Type` (restricted picklist): **Add, Amend, Association (v66.0+), Cancel, No Change, Renew, Transfer (v65.0+)**.
- `Subtype` (restricted picklist, nillable) — "The subtype of the action on the quote line item."
- `CurrencyIsoCode` (v66.0+, defaults USD).

**Documentation gap (important for the re-architecture write-up):** the QuoteAction object page enumerates the seven `Type` values but does **not** publish the rule for *when* each is auto-assigned during renewal-quote generation. The help pages that would state this ("Manage Quote and Order Lifecycle Actions", "Amend, Renew, and Cancel Assets") are JS SPAs that WebFetch cannot read. What *is* documented: (a) absence ⇒ Add; (b) `SourceAssetId` names the asset each action operates on; (c) the paired object `AssetAction` records the realized change with a business `Category` (Renewals, Cancellations, etc.). The assignment logic is therefore engine-internal and driven by the asset's selling model (see §6) — which is exactly why Fortra had to reverse-engineer and re-implement it in `RenewalQuoteActionStamp`.

Order side is symmetric: absence of a QuoteAction on a converted quote yields an **OrderAction** of type Add.

## 5. Stage 4 — Create or Update Asset From Order (asset write-back)

**Endpoint:** `POST /services/data/v67.0/actions/standard/createOrUpdateAssetFromOrder` (v60.0+, requires **Assetize Order** perm set)
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order.htm

- Input `orderId` (required); output `requestId` (async).
- "generates assets corresponding to each order item… establishes new assets for fresh orders while revising existing assets for modification requests." Explicitly: "**Modify existing assets for change order requests, such as a renewal or a cancellation.**"
- This is what closes the loop: a renewal order's line, tied via QuoteAction/OrderAction `SourceAssetId` back to the owned asset, drives an *update* of that asset (new state period, extended `CurrentLifecycleEndDate`) rather than minting a duplicate — natively preventing the RNM/RRM two-asset proliferation Fortra sees (22.8k RNM + 91.4k RRM).

## 6. Asset renewability model (why the native path gates on selling model)

Asset lifecycle fields (Object Reference, all **system-populated, read-only / not updateable**):
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_asset.htm

- `HasLifecycleManagement` — "True if this asset is a lifecycle-managed asset, otherwise false." (v50.0+, **not updateable**)
- `LifecycleStartDate` — "the beginning of the asset's lifecycle… inherited from the start date of the earliest asset state period." (read-only)
- `LifecycleEndDate` — "the end of the asset's lifecycle… inherited from the end date of the **final** asset state period." (read-only)
- `CurrentLifecycleEndDate` — "the end of the period shown as current… inherited from the end date of the **current** asset state period." (read-only)
- Renewal defaults (these ARE create/update-able): `RenewalPricingType` = **LastNegotiatedPrice | ListPrice** ("The price used when renewing a subscription"), `RenewalTerm`, `RenewalTermUnit` (Annual/Months).

This confirms the established fact: **renewability is immutable and derived from the asset's state periods / selling model, not a settable flag.** A OneTime selling model produces no end-date-bearing final state period ⇒ not renewable; a TermDefined subscription does ⇒ renewable. `RenewalPricingType`'s two documented options (LastNegotiatedPrice vs ListPrice) are the *only* native renewal-price sources — there is no native "derived pricing" renewal source, which is consistent with why Fortra's derived RNM path has no native home on renewals.

## 7. Provenance objects: AssetAction & AssetActionSource

**AssetAction** — "Represents a change made to a lifecycle-managed asset"; "The fields can't be edited."
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetaction.htm
- Business `Category` enum includes **Renewals**, Cancellations, Upgrades, Downgrades, Upsells, Cross-Sells, Swaps, Transfers, Initial Sale, Terms And Conditions Changes, Other.
- Subtypes (v65.0+): DowngradeFrom/To, UpgradeFrom/To, SwapIn/Out, TransferFrom/To, FieldAmendment, StartDateAdjustment, Rollback.
- Action/effective-date split (load-bearing): "The date the customer cancels the subscription (June) is the **action date** of the asset action. The cancellation's effective date (October) is the **start date of the asset state period**." Links to Asset via `AssetId`.

**AssetActionSource** — "an optional way to record what transactions caused changes to lifecycle-managed assets"; read-only; v50.0+; needs "Access Customer Asset Lifecycle Management APIs."
Source: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm
- `ReferenceEntityItemId` (polymorphic → OrderItem or WorkOrderLineItem): "The ID of an asset action source transaction originating in Salesforce."
- `ExternalReference` / `ExternalReferenceDataSource` for non-Salesforce origins.
- `AssetActionId`: "the change caused by an asset action source transaction."
- `ProductSellingModelId`: "Specifies the product selling model type. Foreignkey to ProductSellingModel entity."

This is the native anchor for the established fact that "selling-model provenance lives on read-only AssetActionSource.ProductSellingModelId." Natively, the renewal engine reads the **selling model off AssetActionSource** to decide Renew vs Amend vs No Change — provenance the platform stamps and never lets you edit. Fortra's `RenewalQuoteActionStamp` re-derives this cross-product by `account|Solution_Category__c` precisely because the native `Asset.Product2Id`-exact match (via the Discovery decision table) can't bridge RNM-asset → RRM-line.

## 8. Native model vs. Fortra — re-architecture implications

| Concern | Native RLM design (documented) | Fortra divergence |
|---|---|---|
| Renewal trigger | `initiateRenewal` action, async, returns `requestIdentifier` | `Fortra_Create_Renewal_Quote` flow overrides it |
| Line transaction type | QuoteAction `Type` engine-assigned from selling model; absent ⇒ Add | Manually synthesized (`RenewalQuoteActionStamp`) because RNM≠RRM Product2Id breaks native match |
| Asset provenance | `QuoteAction.SourceAssetId` + `AssetActionSource.ProductSellingModelId` (read-only) | Re-derived cross-product by account\|category |
| Renewability | Immutable, from state-period end dates / TermDefined selling model | RNM OneTime = not renewable → wrongly Amended |
| Renewal price source | `RenewalPricingType` = LastNegotiatedPrice \| ListPrice only | Derived-pricing path excluded on renewals ⇒ null net |
| Asset write-back | `createOrUpdateAssetFromOrder` *updates* existing asset | Two-catalog RNM/RRM produces parallel assets |

**Direction to re-architect toward:** collapse to one lifecycle-managed asset per subscription that the platform can *update* on renewal (§5); let `initiateRenewal` + engine-assigned QuoteActions do source resolution off `AssetActionSource`/selling model rather than custom stamping (§4, §7); and price renewals through the native `RenewalPricingType` (LastNegotiated/List) contract instead of a derived path the platform excludes on renewals (§6). The single biggest native/Fortra mismatch is that RLM assumes **one renewable TermDefined asset carrying its own priced provenance**, whereas Fortra's two-catalog RNM(OneTime)/RRM(TermDefined) split defeats every native join (Product2Id match, selling-model renewability, and derived pricing exclusion) simultaneously.

### Key source URLs
- Initiate Renewal: developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm
- Initiate Amendment: …/actions_obj_amend_assets.htm
- Get Renewable Assets Summary: …/actions_obj_get_renewable_assets_summary.htm
- Create/Update Asset From Order: …/actions_obj_create_update_asset_from_order.htm
- QuoteAction: …/sforce_api_objects_quoteaction.htm
- AssetAction: …/sforce_api_objects_assetaction.htm
- AssetActionSource: …/sforce_api_objects_assetactionsource.htm
- Asset (lifecycle fields): …/sforce_api_objects_asset.htm
- Trailhead (UI renewal flow): trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations

**Coverage gaps (could not verify from official docs):** (1) the exact engine rule mapping selling-model/asset-state → each QuoteAction `Type` value is not published on the object page and the help articles that would state it are JS-rendered SPAs unreadable via WebFetch; (2) `asset_lifecycle_overview.htm` and the `ind.qocal_*` help concept pages returned only navigation shells. The behavioral gaps were filled from the Trailhead module and the object/action reference pages, which are consistent with the established facts.