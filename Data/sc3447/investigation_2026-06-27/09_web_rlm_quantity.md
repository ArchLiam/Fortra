# SC-3447 — Web Research: RLM Quote→Order & Quantity Model (official docs)

**Date:** 2026-06-27
**Researcher:** investigation subagent (read-only)
**Primary authoritative source:** Salesforce *Revenue Management Developer Guide*, **Version 67.0, Summer '26**, last updated 2026-06-25 (matches the org's RLM/API level). Downloaded full PDF (240,061 lines of text) and parsed deterministically to avoid WebFetch truncation/hallucination. Secondary: Salesforce Subscription Management guide + Help/Trailhead.

> NOTE on method: Salesforce Help (`help.salesforce.com`) and the per-page Developer docs render via JavaScript and return only a shell to WebFetch (confirmed empty fetches). All dev-guide quotes below are extracted from the static PDF text. Trailhead/blog corroboration via WebSearch summaries.

---

## BOTTOM LINE FOR SC-3447

Native Revenue Cloud Advanced / RLM models order-line quantity as **one OrderItem with `Quantity = N`**, and one Asset with `Quantity = N` (e.g., seats). It does **NOT** create one order line per unit. The custom `PowerOrderSplittingService.splitPowerOrderLines` (loop `for i=1..qty` → one qty-1 OrderItem + Partition clone per unit, synchronously, inside the convert flow's `CurrentTransaction`) is **a custom reimplementation that fights the native model** and is the direct cause of the Apex CPU blow-up at qty 456 (and is structurally impossible at the client's stated 750,000).

Where Salesforce DOES support "one line per unit," it is:
- at the **Fulfillment Order** layer (Dynamic Revenue Orchestrator), **not** the OrderItem layer;
- **declarative/config-driven** (`DecompositionScope` + `FulfillmentQtyCalcMethod`), not hand-rolled Apex;
- **asynchronous** (`StagedAssetize` fulfillment step, async line creation), not synchronous in one CPU budget.

---

## Q1. How RLM models order-line QUANTITY (Quantity=N on one line vs one line per unit)

**Native pattern = Quantity=N on a single line.** Evidence:

### OrderItem / OrderItemDetail
The breakdown of an order line — including *quantity changes* — is modeled as **detail rows under ONE OrderItem**, never as N separate OrderItems:

> "**OrderItemDetail** — Represents the breakdown details of an order product. Revenue Management generates these records to capture pricing and quantity changes, such as **negative quantity reductions**, early renewals, derived pricing or repricing during an amendment, and bundle or product attribute reconfigurations." (dev guide, OrderItemDetail object; mirrored for `QuoteLineDetail`)

A negative-quantity reduction (e.g., the cancel-credit case in SC-3441) is an **OrderItemDetail row on the same OrderItem**, not a new line — direct proof the platform's unit-of-quantity is the `Quantity` field, with details for breakdown, not row explosion.

### Asset (the post-activation representation)
- `Asset.Quantity` — "**Quantity purchased or installed.** The Quantity field value isn't set by Customer Asset Lifecycle Management. Instead, you can populate the field as you need." (single `double` field).
- `Asset.QuantityIncreasePricingType` — "Specify which pricing type to use when **the quantity of this asset is increased**." (values `LastNegotiatedPrice`, `ListPrice`). A platform field that only makes sense if one asset carries quantity N.
- `AssetStatePeriod` — "Represents a time span when an asset has the **same quantity, amount, and monthly recurring revenue (MRR)**. An asset has as many asset state periods as there are changes to it (asset actions) during its lifecycle."
- Subscription Management *Increase Subscription Quantity* example: 10 licenses → buy 5 more → "The amendment asset state period includes the original and the additional licenses. **Its quantity is 15** and the monthly recurring revenue is $150." → ONE asset, quantity 10→15, NOT 15 asset records.

### Is there ANY native feature that requires per-unit splitting?
**Yes, but at the fulfillment layer and declaratively** — see Q3/Q5. There is **no** native Revenue Cloud feature that requires per-unit *OrderItem* splitting. Serialized/per-device assets are handled by DRO decomposition into fulfillment lines, not by exploding the sales order line.

---

## Q2. Native quote→order conversion in RLM; async support; order-size limits

Native conversion is **event/async-oriented**, the opposite of the all-synchronous `CurrentTransaction` action chain in `Fortra_Quote_to_Order_Conversion`.

### Native actions
- **`createOrderFromQuote`** (invocable action, API 60.0+): `POST /actions/standard/createOrderFromQuote`, input `quoteRecordId`, returns `requestId` / `orderId`. Completion is signaled by a platform event:
  > "**QuoteToOrderCompletedEvent** — Notifies subscribers when the `/actions/standard/createOrderFromQuote` REST request is complete. If the request is successful, use this event to learn about the Order record. If the request isn't successful, use this event to learn about the errors…" (channel `/event/QuoteToOrderCompletedEvent`, API 56.0+).
- **`createOrdersFromQuote`** (one quote → MANY orders) — explicit large-quote splitting + async:
  > "**CreateSingleOrder** — Creates a single order from a quote. This method creates the order header and order line items **synchronously**.
  > **CreateOrderByGroup** — Create multiple orders based on a quote line group.
  > **CreateOrderByField** — Create multiple orders based on a specified quote line item field.
  > If you're creating multiple orders from a quote, the order header records are created **synchronously** and **order line items are created asynchronously**."

  → Salesforce's native answer to a big quote is: split into multiple orders by group/field, create headers sync, **create lines async**. Notably even the single-order path is documented as creating header + lines synchronously — fine for normal line counts, but not designed for tens-of-thousands of exploded unit lines.

### Place Order / Place Sales Transaction APIs (RLM transaction tier)
- **Place Order (POST)** is **deprecated as of API 63.0**; use **Place Sales Transaction** instead.
- Place Sales Transaction **runs asynchronously**:
  > "This API returns detailed error status and a **retryable payload** from **Place Sales Transaction API that runs asynchronously**." (Retrieve Sales Transaction API Errors GET)
- `PlaceOrderCompletedEvent` (API 63.0+) notifies of order created/updated via Place Order / Place Sales Transaction.
- Apex Place Order/Place Quote responses expose: "Get the **request ID** of the process to query the **asynchronous status** of the Place Order Apex API" and "Get the **asynchronous status URL** of the request." → built-in async-poll pattern.

### Documented order-size limits
The dev guide does not publish a hard "max OrderItems per order" number, but the pricing tier draws the line at **100 line items** (see Q5: `isHighVolumeLineItems`). Async line creation in `createOrdersFromQuote` exists precisely because synchronous creation does not scale.

---

## Q3. Asset/Subscription creation from orders — per-unit, or one asset w/ quantity? Is manual splitting redundant?

**Native = one asset per order line, carrying Quantity=N; creation is asynchronous/staged.** Manual per-unit OrderItem splitting is therefore **redundant and conflicting** with native asset generation.

- **`createOrUpdateAssetFromOrderItem`** / **`createOrUpdateAssetFromOrder`** (invocable, "Assetize Order" perm set): turns activated order items into assets.
- Completion via platform event:
  > "**CreateAssetOrderEvent** — Notifies subscribers that the process started by the `/actions/standard/createOrUpdateAssetFromOrder` or `…createOrUpdateAssetFromOrderItem` request is complete. If the process is successful, use this event to learn about the **new assets**."
- **`StagedAssetize`** fulfillment-step type (API 63.0+): a native DRO step type for **staged / asynchronous assetization** at scale. → Salesforce explicitly provides an async path for asset creation from large orders.
- Quantity handled at asset level: amendments record `AssetAction` (e.g., business category `Swap` on reduced quantity) + new `AssetStatePeriod` on the **same** asset — they do not spawn per-unit asset rows.

Implication for SC-3447: even if `PowerOrderSplittingService` succeeded, exploding to N qty-1 OrderItems would then assetize into N qty-1 Assets — multiplying every downstream lifecycle/amendment/renewal operation by N (456 today, up to 750,000), against a platform built to manage **one** asset with `Quantity=N`.

---

## Q4. Best practice for per-device / per-seat entitlements (assets w/ quantity vs individual records)

Official guidance = **one asset with a quantity field representing seats/devices**; amend the quantity, don't create per-seat records.

- Subscription Management *Increase Subscription Quantity*: "Let customers increase the quantity of their assets partway through a subscription" — modeled as quantity 10→15 on one asset, via `initiate-amend-quantity`.
- Asset amendment guidance (Help / RevenueCloud.info): "a customer buys a subscription service with a number of seats represented by the **quantity value of the Asset**… purchase some additional seats… an amendment to the Asset… resulting in the Asset record being updated with the **new number of seats**."
- **Asset Lifecycle Management** primitives are all quantity-based: `AssetAction` = "a change to **quantity**, amount, and MRR"; `AssetStatePeriod` = span where **quantity** is constant.

**When per-unit/serialized IS warranted** → use **DRO order decomposition** to fulfillment lines (declarative), NOT order-line explosion:
- **`DecompositionScope`** (product / ProductRelatedComponent field, API 61.0+) — "The number of fulfillment order line items that must be generated." Values: `Account`, `Bundle`, `Order`, `OrderLineItem` (one-to-one). (Trailhead: "Order Line Item (Default): a one-to-one mapping… Order: only one fulfillment line item… Bundle… Account: a single instance across orders from the same account.")
- **`FulfillmentQtyCalcMethod`** (API 61.0+) — "Determines whether the **quantity of fulfillment order line items must always be one** or must be aggregated from the source line items." Values: **`Aggregate`** (keep Quantity=N) vs **`AlwaysOne`** (one fulfillment line per unit).

→ The native "one line per unit" knob (`AlwaysOne`) exists, is **declarative**, lives on the **fulfillment** record (downstream of the sales OrderItem), and is driven by DRO orchestration (which can be async). The Fortra split-type label "Order Line Only" mirrors `DecompositionScope=OrderLineItem`; the custom Apex appears to hand-roll, synchronously and at the wrong layer, what DRO does declaratively and asynchronously.

---

## Q5. RLM platform limits relevant to scale (lines, pricing perf, reprice)

- **Pricing API 100-line threshold:** `isHighVolumeLineItems` (Place/Read pricing input, API 63.0+) — "Indicates whether the **pricing API returns pricing details for more than 100 line items** (true) or not (false)." → 100 line items is the native pricing batch boundary; beyond it you must opt into high-volume mode. The Power split produces 456 lines today and up to 750,000 — orders of magnitude past this.
- **Reprice modes (`PricingPreference` on TransactionProcessingType, API 65.0+):**
  - `Force` — "Reprices all lines."
  - `System` — "Performs a **delta pricing** request on the **unprocessed lines** when Delta Pricing is enabled in the org."
  - `Skip` — "Skips the pricing request on all lines."
  → **Delta pricing** (price only changed/unprocessed lines) is the native lever for repricing large transactions efficiently; `OrderRepriceInvocable` with a blanket Force-reprice over hundreds/thousands of exploded lines is the worst case.
- **Async by design across the transaction tier:** Place Sales Transaction async + retryable payload; `createOrdersFromQuote` async line creation; `StagedAssetize`; request-ID/status-URL polling. The platform expects large work to be chunked and asynchronous — directly contradicting the single-`CurrentTransaction` (10,000 ms CPU) action chain in the convert flow.
- **No published hard "max OrderItems/order"** number in the dev guide, but every scaling mechanism (async lines, multi-order split, high-volume pricing flag, staged assetize, delta pricing) signals that synchronous per-unit explosion is unsupported at scale.

---

## How this maps to SC-3447 specifically

1. **Root design defect:** `PowerOrderSplittingService` explodes one quote/order line of `Quantity=N` into N qty-1 OrderItems (+ N Partition clones), **synchronously**, inside the convert flow's single `CurrentTransaction` request (one 10,000 ms CPU budget). This is contrary to the native model (Quantity=N on one line; per-unit handled at fulfillment layer, async).
2. **CPU is the binding limit** (snapshot: SOQL 19/100, DML 480/10000 rows, CPU >10,000). Per-clone record-triggered flows (`Set_Dates` V6 + `Set_Workday_Contract_Line_Type` V11, the latter re-entrantly re-firing Set_Dates) multiply per-row CPU by N. With Power qty being seat/sentinel counts in the thousands–999,999, the synchronous explosion can never fit in one Apex transaction.
3. **Native alternatives that eliminate the explosion:**
   - Keep `Quantity=N` on a single OrderItem (native model). Let DRO `DecompositionScope`/`FulfillmentQtyCalcMethod=AlwaysOne` generate per-unit *fulfillment* lines **if** per-unit fulfillment is truly required — declaratively, downstream, and async (`StagedAssetize`).
   - If multiple orders are genuinely needed, use native `createOrdersFromQuote` (CreateOrderByGroup/Field) which creates lines **asynchronously**.
   - For large reprice, use `PricingPreference=System` (delta pricing) + `isHighVolumeLineItems`, not blanket Force-reprice over exploded lines.
4. **Confirms the local-investigation hypothesis** that Power "quantity" is a seat/user count (the asset-quantity-of-seats model), not a machine/per-unit count — so per-unit OrderItem rows have no native justification.

---

## Sources (URLs)

- RLM Developer Guide (full PDF, v67.0 Summer '26): https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf
- OrderItemDetail object: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_orderitemdetail.htm
- Create Order From Quote action: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_create_order_from_quote.htm
- Place Order (POST) [deprecated 63.0]: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_resources_place_order.htm
- Place Sales Transaction (POST): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_resources_place_sales_transaction.htm
- Retrieve Sales Transaction API Errors (GET) [async/retryable]: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_resources_retrieve_place_sales_transaction_error.htm
- Transaction Management Business APIs: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/qoc_business_apis.htm
- Dynamic Revenue Orchestrator overview: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/dynamic_revenue_orchestrator_overview.htm
- Subscription Management — Increase Subscription Quantity example: https://developer.salesforce.com/docs/revenue/subscription-management/guide/solution-amend-pos-q.html
- Subscription Management — Assets / initiate-amend-quantity: https://developer.salesforce.com/docs/revenue/subscription-management/references/assets?meta=Initiate+amend+quantity
- The Lifecycle of a Subscription Asset (Help): https://help.salesforce.com/s/articleView?id=sf.lifecycle_mgmt_process.htm&language=en_US&type=5
- Amending/Renewing/Canceling Assets (Help): https://help.salesforce.com/s/articleView?id=ind.qocal_manage_assets_in_revenue_lifecycle_management.htm&language=en_US&type=5
- RLM/Quote & Order capture limits (Help): https://help.salesforce.com/s/articleView?id=ind.qocal_limits.htm&language=en_US&type=5
- Trailhead — Define an Order Decomposition: https://trailhead.salesforce.com/content/learn/modules/complex-order-decomposition-and-orchestration-with-revenue-cloud/define-an-order-decomposition
- Trailhead — Asset Lifecycle Management with Revenue Cloud (amendments/renewals): https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-amendments
- RevenueCloud.info — Asset Amendments (seats as quantity): https://revenuecloud.info/revenue-cloud-asset-amendments-using-attributes-for-price-changes/
