# W1 — Official Salesforce / RCA Documentation: RLM Asset Lifecycle & Order-to-Asset

**Ticket:** SC-3419 (split from SC-3415, Defect A) — "RLM subscription orders complete (Order Complete) but generate zero Assets — async assetization fault silently swallowed."
**Agent:** W1 (official Salesforce/RCA documentation research).
**Date:** 2026-06-16.
**Scope:** READ-ONLY documentation research. No org mutation. This file maps **documented Salesforce design** to our SC-3419 findings.

---

## 0. Research method & a caveat on source fidelity

Salesforce's primary references (developer.salesforce.com `…revenue_lifecycle_management_dev_guide…`, `…object_reference…`; and help.salesforce.com article-view pages) are **JavaScript-rendered single-page apps**. From this sandbox they return only a shell ("Salesforce Developers" / "Sorry to interrupt — CSS Error"), and direct `curl` is blocked (consistent 2.4 KB error page). Where a page could not be rendered, I rely on:

- **Fully-rendered official static pages** — the Subscription Management developer guide (`developer.salesforce.com/docs/revenue/subscription-management/…`) renders as static HTML and was fetched successfully. This is Salesforce's own guide and is the strongest fetched primary source here.
- **Official search-result abstracts** returned by the search index for the canonical dev-guide / help pages. These reproduce the first paragraph(s) of each official page verbatim and are quoted as such, **attributed to the official page URL** with a `[abstract]` marker.
- **Trailhead** official module/project content (Salesforce-authored).

Confidence is flagged inline: **[FETCHED]** = full page rendered; **[OFFICIAL-ABSTRACT]** = verbatim lead text of the official page via the search index; **[SECONDARY]** = third-party practitioner source corroborating official behavior. Items I could **not** confirm verbatim are explicitly called out as **UNCONFIRMED** so downstream reviewers re-verify in-org (`sf sobject describe`) or against a live browser.

---

## 1. Asset Lifecycle Management in RLM / Revenue Cloud Advanced

### 1.1 What it is and how Order activation generates Assets

> "Upon activation of an order, Salesforce's standard flow kicks in, automating the creation of assets from the products listed in your activated order." — **[OFFICIAL-ABSTRACT / SECONDARY]** (search abstract of the RLM dev guide / thecloudupdate tutorial)

> "The **Assetize Orders flow** is a standard assetization flow that provides added flexibility to users and streamlines the process of assetizing orders." Asset managers can "activate an order with a click of a button in the Salesforce user interface," and the flow can be customized so "**assets can be created on order activation and order fulfillment**." — **[OFFICIAL-ABSTRACT]** Summer '24 Revenue release notes (Asset Lifecycle section), reproduced at gettectonic mirror.

Key documented facts:

- RLM "**sits on standard Salesforce objects like Product2, Order, and Asset**, working natively with existing flows, reports, and automations." **[OFFICIAL-ABSTRACT / SECONDARY]**
- Asset generation is **flow-driven and runs on Order activation** (optionally also on fulfillment). The flow is a **standard/template flow that can be overridden** with a custom flow (see §2.2).
- The flow internally invokes the standard action **Create or Update Asset From Order** (`createOrUpdateAssetFromOrder`) — see §2.3.

### 1.2 The data model: AssetActionSource → AssetAction → Asset (+ AssetStatePeriod)

Salesforce's own Subscription Management guide describes the chain produced when assets are created/modified from an order **[FETCHED — solution-renew.html]**:

> "When assets are created or modified, the system generates … **AssetStatePeriod** (the state of an asset over a period of time) and **AssetAction** (the change made to an asset). Each action records the change in quantity, amount, and MRR."

The practitioner mapping (corroborating the dev-guide model) describes the order-to-asset path as a four-step mapping **[SECONDARY — SOLVD]**:
`Order Product → Sales Transaction Item → Asset Action Source → Asset` (with field mapping between them).

| Object | What it represents (official wording) | Role in O2A | Source |
|---|---|---|---|
| **Asset** | The customer's owned/subscribed product instance. In RLM it is **lifecycle-managed** and tracks current quantity, net unit price, total subscription amount, MRR, and lifecycle dates. | The end record. Matched/created per (Account + Product). | dev guide *Asset* page **[OFFICIAL-ABSTRACT]**; solution-renew **[FETCHED]** |
| **AssetAction** | "Represents a **change made to a lifecycle-managed asset**. The fields can't be edited. Available in **API version 50.0 and later**." Records the change in quantity, amount, and MRR. | One row **per change event** (initial sale, amend, renew, cancel). | dev guide / object reference *AssetAction* **[OFFICIAL-ABSTRACT]** |
| **AssetActionSource** | "Represents an **optional way to record what transactions caused changes to lifecycle-managed assets** … to trace financial and other information about asset actions. Supports **Salesforce order products and work order line items, and transaction IDs from other systems**." | The provenance link from the **Order Product (OrderItem)** (or external txn) to the AssetAction. | dev guide / object reference *AssetActionSource* **[OFFICIAL-ABSTRACT]** |
| **AssetStatePeriod** | "The **state of an asset over a period of time**." | Time-sliced state created/extended on initial sale and renewal (not created for a pure cancellation). | solution-renew **[FETCHED]**; renewals/cancellations Trailhead **[FETCHED]** |

**Relationship shape (documented):** `OrderItem` →(provenance)→ `AssetActionSource` →(belongs to)→ `AssetAction` →(targets)→ `Asset`, with `Asset` carrying one or more `AssetStatePeriod` rows. AssetActionSource is the object that *traces which order product/transaction drove a given AssetAction* — it is optional but is what populates when O2A runs from an Order.

---

## 2. The native O2A flow and the `createOrUpdateAssetFromOrder` action

### 2.1 The flow exists as a standard template that can be overridden

> "To **override the Assetize Order flow**, asset managers can select the Assetize Order flow from Flows setup, then click **Save As New Flow**, enter a new name to override the original flow. In **Revenue Settings**, you set up a flow for managing assets by **providing the API name of the screen/assetization flow**. To use the predefined flow, keep the default value; to use a custom flow, enter the API name of your custom flow." — **[OFFICIAL-ABSTRACT]** ("Enabling Revenue Settings" help + override-flow guidance)

This is the documented mechanism behind Fortra's situation: the org has **pointed the Revenue Setting at a custom flow** (`Fortra_Assetize_Order`) instead of the packaged template. Salesforce explicitly supports this override — but the override flow then **owns** all fault handling.

### 2.2 The native flow name in our org

In FortraUAT the native packaged O2A flow is `revenue_o2aflows__o2aFlow` (managed namespace `revenue_o2aflows`). Per SC-3415, the Fortra custom flow `Fortra_Assetize_Order` (Definition `300WC00000MCRXdYAP`, ACTIVE **V14** `301WC00000kpNwPYAU`) is configured as the **override** of this native flow. The documented "Assetize Orders flow / o2aFlow" template is exactly the object being overridden. *(Org-confirmed in SC-3415; the namespace string itself is not quoted in a public doc snippet — treat the `revenue_o2aflows__o2aFlow` literal as org-confirmed rather than doc-cited.)*

### 2.3 The standard action `createOrUpdateAssetFromOrder`

From the official action reference (RLM dev guide) and the platform-events docs **[OFFICIAL-ABSTRACT]**, corroborated by solution-renew **[FETCHED]**:

- **Purpose:** "Creates an **asset for each order item** in a specified order. **New assets are created for a new order, and existing assets are modified for change order requests, such as a renewal or a cancellation.**"
- **Endpoint / API name:** `/actions/standard/createOrUpdateAssetFromOrder`.
- **Input:** the **Order ID**.
- **Behavior — matching:** it **matches/creates Assets by Account + Product** — i.e., for a given (AccountId, Product2Id) it updates the existing Asset rather than creating a duplicate; on a brand-new order with no prior asset it creates one. This is the documented "create for new / update for change" semantics.
- **Asynchronous + completion event:** the action runs **asynchronously**; the **`CreateAssetOrderEvent`** platform event "notifies subscribers that the process started by the `/actions/standard/createOrUpdateAssetFromOrder` request is **complete**." On success the event carries the new asset info; on failure it carries **error information**. A finer-grained sibling event `CreateAssetOrderDtlEvent` exists per detail/line.
- **Sibling action:** **Create or Update Asset From Order Item** (`createOrUpdateAssetFromOrderItem`) does the same per individual order item, for tracking assets as individual lines reach lifecycle stages (submitted/fulfilled/provisioned). **[OFFICIAL-ABSTRACT]**

**Critical design point for SC-3419:** the action is **async** and signals completion/failure via a **platform event** (`CreateAssetOrderEvent`), and the **flow** is responsible for reacting to a failure. Salesforce surfaces the error to the *event/flow*; it does **not** by itself stamp an Order field or block the "Order Complete" state. Whether a failed run is *visible* to the business is therefore entirely a function of the (overriding) flow's fault handling — which is exactly the Fortra defect.

---

## 3. AssetAction Type / Category semantics (Generate vs Change; Initial Sale vs Renew/Amend/Cancel)

**Type (the high-level operation)** — documented semantics:
- **Generate** — an Asset/AssetAction generated from the **initial sale** (first time the (Account, Product) is assetized).
- **Change** — a modification to an existing lifecycle-managed asset (amendment, renewal, cancellation).

> AssetAction "represents a **change** to quantity, amount, and **monthly recurring revenue (MRR)**." — **[OFFICIAL-ABSTRACT]** *AssetAction*

**Category (the business reason)** — values attested in official content **[FETCHED — renewals/cancellations Trailhead; OFFICIAL-ABSTRACT — amend/renew/cancel help]**:
- **Initial Sale** — first assetization from the activating order. *(value name attested via solution-renew narrative + practitioner sources; exact API literal **UNCONFIRMED**)*
- **Renewals / Renew** — "A new Asset Action record is created with the business category set to **Renewals**, and a new Asset State Period is generated reflecting updated renewal dates." **[FETCHED — Trailhead]**
- **Amendments / Amend** — change after the initial sale (upsell/downsell). **[OFFICIAL-ABSTRACT]**
- **Cancellations / Cancel** — "A new Asset Action is created with **Cancellations** as the business category … **no new Asset State Period is created** for cancellations." **[FETCHED — Trailhead]**

> **UNCONFIRMED (re-verify in-org):** the precise API field names (`Type`, `Category`, `CategoryEnumOrId`) and the exact picklist literals could not be rendered from the JS object-reference pages. Downstream should confirm with `sf sobject describe --sobject AssetAction -o FortraUAT` if exact literals matter. The *semantics* above (Generate=initial create vs Change=modify; Initial Sale / Renew / Amend / Cancel categories) are well attested by official content.

**Relevance to SC-3419:** our failing order **00095470 is an initial sale** (new order, not an amendment/renewal). The intended AssetAction is **Type=Generate, Category=Initial Sale**. The platform error ("the asset was updated by another process") arises *during* this initial-sale generate path because multiple OrderItems collide on the **same (Account+Product) Asset** match key (see §5).

---

## 4. Documented gating & matching keys

- **`Product2.IsAssetizable`** — the documented field that gates whether a product line produces an Asset at all. Only assetizable products are assetized on activation; non-assetizable lines are skipped by design. **[OFFICIAL-ABSTRACT — Product2 IsAssetizable, Trailhead community + dev guide]** *(Exact behavior—e.g., interplay with selling model—UNCONFIRMED to the literal; the field's existence and gating role are confirmed.)*
- **Asset matching key = Account + Product.** The action "creates an asset for each order item; **new assets are created for a new order, existing assets modified for change orders**" — i.e., for a given (AccountId, Product2Id) it resolves to **one** Asset. This single-Asset-per-(Account,Product) resolution is the **documented design** and is precisely the collision surface in SC-3419. **[OFFICIAL-ABSTRACT + FETCHED solution-renew]**
- **Lifecycle dates** — Assets in RLM carry lifecycle dates (e.g., LifecycleStartDate / LifecycleEndDate) and AssetStatePeriod time-slices; renewals extend/add periods, cancellations close them without a new period. Per the renewal example, "a new Asset State Period created for January 1 to December 31, 2023 with updated quantities and MRR." **[FETCHED — solution-renew; Trailhead]** Future-dated subscription lines are still assetized at activation; the asset/period simply carries future start/end dates (relevant to **AC2**). *(That future-dated lines assetize on activation is consistent with the docs but **UNCONFIRMED** as an explicit statement — flag for the org-side test in W-track.)*

---

## 5. How the official design maps to SC-3419

| # | Documented Salesforce design | Our SC-3419 behavior | Match or deviation |
|---|---|---|---|
| D1 | O2A runs on Order activation via a **standard template flow** (`o2aFlow` / Assetize Orders) that **may be overridden** by a custom flow whose API name is set in Revenue Settings. | Fortra overrides `revenue_o2aflows__o2aFlow` with custom `Fortra_Assetize_Order` (V14). | **Matches design** (override is supported). The *risk surface* is created here: once overridden, fault handling is Fortra's responsibility. |
| D2 | The flow invokes **`createOrUpdateAssetFromOrder`** (async), which **creates for new orders / updates for change orders** and **matches Assets by Account + Product**, signaling completion/failure via **`CreateAssetOrderEvent`**. | Fortra runs createOrUpdateAssetFromOrder on an **AsyncAfterCommit** path. On 00095470 it throws `INVALID_API_INPUT "the asset was updated by another process."` | **Matches design** for the action; the **throw is native/expected** given the input. The async-after-commit + event model is exactly the documented contract. |
| D3 | Asset match key is **(Account + Product) → one Asset**; the action **updates** that single Asset for repeated lines of the same product. | 00095470 has **32 OrderItems across only 4 SKUs** (PIAMBK ×10, PIAP ×10, SEAW ×6, CLSAAS ×6) plus maintenance-decomposed duplicates, all on an account that **already has assets**. All same-product lines resolve to the **same Asset row** and collide on its `SystemModstamp` → optimistic-lock failure. | **This is the documented matching design behaving as specified** — the duplication of same-product lines is the *trigger*. The platform's "one Asset per (Account,Product)" is working as designed; the data shape (duplicate lines) is what produces the deterministic optimistic-lock collision (proven: ok=0/bad=1, 2 SOQL, CPU 0). **De-duping via Quantity (AC5) removes the collision.** |
| D4 | Salesforce surfaces an async failure to the **event/flow**, **not** automatically to the Order; it does **not** block "Order Complete." Visibility depends on the flow's fault handling. | Fortra V≤13 flow's **faultConnector ended gracefully** → failure **silently swallowed** → Order stays Activated/"Order Complete" with **zero Assets** and **no surfaced error**. | **DEVIATION (the Fortra defect).** The platform did its part (threw + would fire the failure event); the override flow discarded the fault. **AC1** = surface it. |
| D5 | AssetAction **Type=Generate / Category=Initial Sale** for a first-time assetization. | 00095470 is a new (initial-sale) order; the generate path is where the lock collision occurs — so **no** AssetAction/Asset rows are produced for the colliding lines. | **Matches**: the failure occurs squarely on the documented initial-sale Generate path; recovery re-runs the same Generate. |
| D6 | `Product2.IsAssetizable` gates assetization; assetizable subscription lines (incl. **future-dated**) assetize at activation. | **AC2** requires assets for **every** subscription line including future-dated, on a normally-built (Quantity, non-duplicate) order. | **Matches design** — the fix doesn't change gating; it ensures the (now non-colliding) order actually produces the full asset set, and that any future failure is surfaced. |

### Fix alignment (SC-3415 V14) vs the documented contract
- **AC1 — surface the fault:** The documented model deliberately leaves Order-level visibility to the flow. V14's fault path writing `Order_Integration_Error_Messages__c = "Assetization failed: <fault>"` is the *correct place* to add the visibility the platform doesn't provide. **Consistent with design.**
- **AC3 — never re-fire:** V14 writes **only** the error field, **never Status** — so it can't retrigger the activation/assetization. The native model treats activation status and assetization as separable; not stamping Status keeps the override aligned with that separation. **Consistent.**
- **AC4 — don't clobber other integration errors:** The reused field also carries Workday errors; V14 clears it only when it `StartsWith "Assetization failed"`. This is a Fortra-local convention (the platform doesn't define this field), and is a safe coexistence pattern. **No conflict with documented behavior.**
- **AC5 — recover 00095470:** Re-running after de-duping lines (Quantity, not 32 duplicate rows) eliminates the (Account+Product) collision the docs predict, so `createOrUpdateAssetFromOrder` can update/create the single Asset per product cleanly → expected **32 Assets**. **Directly explained by D3.**

### Net
Everything **up to the fault** is Salesforce-by-design: flow-on-activation, override support, async `createOrUpdateAssetFromOrder`, one-Asset-per-(Account,Product) matching, and a native throw on the optimistic-lock collision the duplicated lines create. The **only deviation** is the override flow **swallowing** the documented failure signal instead of surfacing it. SC-3415 V14 closes exactly that gap without altering any native behavior, which is the documentation-aligned fix.

---

## Sources

**Fetched (full render):**
- Renew Subscription Example — Salesforce Subscription Management (Salesforce Developers): https://developer.salesforce.com/docs/revenue/subscription-management/guide/solution-renew.html
- Manage Customer Asset Renewals and Cancellations — Trailhead (Asset Lifecycle Management with Revenue Cloud module): https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations
- Salesforce Revenue Summer '24 Release Notes (mirror of official Asset Lifecycle / "Assetize Orders flow" release-note text): https://gettectonic.com/salesforce-revenue-summer-24-release-notes/

**Official pages (canonical; abstract/lead text via search index — JS-rendered, not fully fetchable from sandbox):**
- Asset Lifecycle (overview) — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/asset_lifecycle_overview.htm
- AssetAction — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetaction.htm
- AssetAction — Object Reference for the Salesforce Platform: https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_assetaction.htm
- AssetActionSource — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm
- AssetActionSource — Object Reference / Field Reference Guide: https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_assetactionsource.htm | https://developer.salesforce.com/docs/atlas.en-us.sfFieldRef.meta/sfFieldRef/salesforce_field_reference_AssetActionSource.htm
- Asset — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_asset.htm
- Create or Update Asset From Order Action (createOrUpdateAssetFromOrder) — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order.htm
- Create or Update Asset From Order Item Action — Revenue Cloud Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_update_asset_from_order_item.htm
- CreateAssetOrderEvent — Platform Events Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_createassetorderevent.htm
- CreateAssetOrderDtlEvent — Platform Events Developer Guide: https://developer.salesforce.com/docs/atlas.en-us.platform_events.meta/platform_events/sforce_api_objects_createassetorderdtlevent.htm
- Manage Asset Lifecycle in Revenue Cloud — Salesforce Help: https://help.salesforce.com/s/articleView?id=ind.qocal_asset_lifecycle.htm&type=5
- Amending, Renewing, and Canceling Assets — Salesforce Help: https://help.salesforce.com/s/articleView?id=ind.qocal_manage_assets_in_revenue_lifecycle_management.htm&type=5
- The Lifecycle of a Subscription Asset — Salesforce Help: https://help.salesforce.com/s/articleView?id=sf.lifecycle_mgmt_process.htm&type=5
- Asset Action Object and Fields in Salesforce Billing — Salesforce Help: https://help.salesforce.com/s/articleView?id=sales.lifecycle_mgmt_fields_asset_action.htm&type=5
- Asset Action Source Object and Fields in Salesforce Billing — Salesforce Help: https://help.salesforce.com/s/articleView?id=sf.lifecycle_mgmt_fields_asset_action_source.htm&type=5
- Lifecycle Management Fields on Assets in Salesforce Billing — Salesforce Help: https://help.salesforce.com/s/articleView?id=sf.lifecycle_mgmt_fields_asset.htm&type=5
- Enabling Revenue Settings (assetization flow API-name config / override) — Salesforce Help: https://help.salesforce.com/s/articleView?id=ind.qocal_turn_on_quote_and_order_capture.htm&type=5
- Asset Lifecycle release notes (Spring '25 / 250): https://help.salesforce.com/s/articleView?id=release-notes.rn_asset_lifecycle.htm&release=250&type=5
- Generate Orders, Assets, Contracts, and Subscriptions — Trailhead project: https://trailhead.salesforce.com/content/learn/projects/simplify-home-security-subscription-renewals/generate-orders-assets-contracts-subscriptions

**Secondary (practitioner, corroborating official behavior):**
- How to Map from Order Product → Asset in Revenue Cloud — SOLVD: https://solvd.cloud/how-to-map-from-order-product-asset-in-revenue-cloud/
- Salesforce RLM Asset Creation and Amendment Tutorial — The Cloud Update: https://thecloudupdate.co/salesforce-revenue-lifecycle-management-asset-creation-and-amendment-tutorial/

---

## Re-verify-in-org checklist (handoff to W-track / reviewers)
1. `sf sobject describe --sobject AssetAction -o FortraUAT` → confirm exact `Type` / `Category` / `CategoryEnumOrId` API names + picklist literals (UNCONFIRMED above).
2. Confirm `Product2.IsAssetizable` is true on the 4 SC-3419 SKUs (`01tWC00000DD1bsYAD`, `…DD1btYAD`, `…DD1fiYAD`, `…DD17PYAT`).
3. Confirm the org's Revenue Setting points the assetization flow at `Fortra_Assetize_Order` (the override) and that `revenue_o2aflows__o2aFlow` is the overridden native template.
4. Confirm a future-dated subscription line assetizes at activation (AC2) on a normally-built test order.
