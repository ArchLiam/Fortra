# SC-3441 - Deep Research: Native RLM/RCA Cancellation-Line Pricing

**Org:** FortraUAT (00DWC000006eUFF2A2) · **Stack:** native Revenue Cloud Advanced / RLM · **Subject:** OrderItem 802WC00000OugI7YAJ, Order 00095539 ("Arcus Hosting"), Asset 02iWC000008MpX7YAK
**Date:** 2026-06-25 · Produced by a multi-agent deep-research workflow (8 research agents — 5 web, 3 internal-artifact — + draft synthesis + 7 adversarial verifier verdicts + final reconciliation).

> **How the verdicts changed the draft (read this first):**
> 1. **Grep=0 "prehook didn't fire" proof is unsound** — all 8 active RevSignaling prehooks also grep to 0 (they run in the opaque managed RLM code unit). The "prehook is not the value source / can be removed" conclusion still holds, but on different grounding (value stable across 3 repricings = hydration signature; prehook writes the same staging field the trigger persists; dossier already classes it DEAD).
> 2. **"Seed never validly tested" is WRONG** — and this *strengthens* the runtime-failure story: a valid **DRAFT** cancel (`log_latest_check.txt`, `CancelNetUnitPrice__c=350` in context) still produced TotalPrice 0. So the failure is **downstream of hydration** — the seed block is not writing `NetUnitPrice` at runtime even on a draft.
> 3. **`LastTransaction` is documented for amend/renew only** — cancel applicability is **unproven**, the single most important unknown.
> 4. PricingSource mapped on both nodes = **confirmed** (but not the *only* blocker — there are two).
> 5. Prehook Apex bugs = **confirmed**; operative bug in the Order log is `TAG_QUANTITY`, not `resolveScope`.
> 6. LastTransaction branch **consumes**, does not **produce**, `NetUnitPrice` = **confirmed**.
> 7. `AssetActionSource.NetUnitPrice` is the correct basis = **confirmed**; the "907" list-0 figure was sample-scoped and is far larger org-wide.
> 8. Prod field asymmetry is a real cutover landmine = **confirmed**.

---

## 1. Executive answer

A cancellation line in RLM/RCA is **supposed** to produce a negative Total Price equal to the *original negotiated net* of the asset (not catalog list). The customer's expectation is correct and matches the documented model. The proximate cause here is proven and simple: the active line-total formula computes `NetUnitPrice (null) × LineItemQuantity (-1) = 0`. The single most likely real fix is **populating `NetUnitPrice` on the cancel line** — and the evidence now shows that **the team's persisted-custom-field path does NOT yet do this even on a valid draft reprice**, which means the remaining work is real and not yet solved by anything currently deployed. There are two candidate solutions to test first: (A) the **native** `Asset.PricingSource = 'LastTransaction'` lever (documented for amend/renew, *unproven for full cancel*), and (B) the **custom seed**, which must be made to actually write `NetUnitPrice` at runtime — a goal the current deployed/working-tree artifacts have **not yet been shown to achieve on a draft cancel**. The previously-leading "context-Sync regenerate" theory is **refuted**: the value already hydrates into the runtime context, so regenerating the context will not help.

---

## 2. How native RLM/RCA prices a cancellation (the supported model)

### 2.1 Cancellation is a first-class lifecycle flow

Native RLM creates a cancellation Quote/Order via the **Initiate Cancellation** action / REST resource (`/connect/revenue-management/assets/actions/cancel`) or the Cancel button on the Asset. This produces:

- `Order.OriginalActionType = Cancel` and a `QuoteAction`/`OrderAction` of `Type = Cancel` carrying `SourceAssetId` (the changed asset). [RLM Dev Guide]
- The line **Quantity automatically set to the negative of the asset's quantity** (`-1` to drive End Quantity to 0). [Trailhead: Manage Customer Asset Renewals and Cancellations]
- `AssetAction` rows (Business Category `Cancellations`) plus `OrderItemDetail`/`QuoteLineDetail` rows that capture "negative quantity reductions." [RLM Dev Guide]

The cancellation API does **not** hand you a pre-priced credit — it has a `skipPricing` flag (default `false` = run pricing). The negative line is then priced by the **same** procedure (`Rev_Mgmt_Default_Pricing_Procedure`). Place Sales Transaction cannot create cancellations; the cancellation APIs/invocables must be used. [RLM Dev Guide]

> **Confirmed in this org:** the subject line carries a valid `OrderAction` Type=Cancel with `SourceAssetId`, `OriginalActionType=Cancel`, `SalesTransactionActionType=Cancel` in context (`log_latest.txt:374-410`). **The action shape is native-correct.** `IsReductionOrder=FALSE` is *not* a misconfiguration — that flag belongs to the legacy standard-Orders "Reduction Order" feature, unrelated to the RLM lifecycle. **Do not pivot to a Reduction Order.**

### 2.2 The credit must come from the prior *net* (AssetActionSource.NetUnitPrice)

The intended credit is the original negotiated net the customer paid, **not** catalog list. The source-of-truth is **`AssetActionSource.NetUnitPrice`** ("the final adjusted unit price, inclusive of all adjustments"), vs `AssetActionSource.ListPrice` (inherited from the PriceBookEntry). [RLM Dev Guide]

This is **confirmed and, if anything, understated** at org scale (verifier re-ran the queries live):
- Net ≠ list in **77%** of AssetActionSource rows (reproduced: 1,540/2,000 sample = 77.0%).
- A large population pays a real net on a zero list price: **125,741 of 430,553** fully-populated rows have `ListPrice = 0` with a nonzero net. (The earlier "907" figure was a ~2,000-row sample artifact; the directional conclusion is robust and larger org-wide.)
- For **this** line the original sale was undiscounted, so net == list == 3000 coincidentally (verified: AssetActionSource AAS-000543597 NetUnitPrice=3000 = original OrderItem 802WC00000OtSYxYAN NetUnitPrice=3000).

**Implication:** a list-price-based credit would over-refund discounted cancellations and under-refund the list-0 cases. Asset NET is the only correct basis.

### 2.3 The native carryover lever: `Asset.PricingSource`

`Asset.PricingSource` is a **restricted picklist** (verified live: `RESTRICTED:True`, exactly two values `LastTransaction` and `PriceBookListPrice`, present at API v67; GA circa v60). Its value hydrates into the context as **`ItemPricingSource`**, which gates a real branch in the live procedure.

> **Scope caveat (corrected from draft):** The field's own inline help reads *"Select the pricing source to use when **amending or renewing** an asset."* Salesforce and third-party docs scope `LastTransaction` to **amend/renew** (and renewal uplift / Price Revision Policies). **No documentation establishes that `LastTransaction` governs a full CANCEL / reduction line** — and one source notes promotions "won't apply to negative quantities or cancellations," suggesting cancel is a distinct path. The SC-3441 roadmap itself treats native-cancel applicability as an **unproven probe**, not an established fact. This is the single most important unknown and must be empirically settled before relying on Option A.

### 2.4 Negative amounts are meant to flow — the $0 is a null, not clamping

The asset ledger models cancellations as **signed deltas** (`AssetAction.Amount`, `QuantityChange`, `MrrChange`, `SubtotalChange`, `TotalCancellationsAmount`). [RLM Dev Guide] CPQ prior art shows the same: a zero-quantity cancel yields a negative Net Total at the prior net (cancelling 10 VMs → **-$200,000**). [CPQ Asset Amendment Tip Sheet] Salesforce documents a Known Issue that a Price Action with a **null source field injects a value of zero** — corroborating that the $0 here is the null-`NetUnitPrice` symptom, not platform clamping. [Known Issue a028c00000gAy3aAAC]

---

## 3. Why THIS org cancel line is not priced

### 3.1 Proximate cause (high confidence, proven)

The active line-total formula reads the **`NetUnitPrice` field**: `ItemNetTotalPrice = NetUnitPrice * LineItemQuantity`, then `ItemTotalPrice = ItemNetTotalPrice`. With `NetUnitPrice = null` and `LineItemQuantity = -1`, the result is `0`. Confirmed in context: `ItemNetTotalPrice=0.0`, `ItemTotalPrice=0.0`, `ListPrice=3000.0` (`log_latest.txt:374-410`; V18 line-total step).

### 3.2 Root cause: a DATA/PROVENANCE gap (not a malformed line, not a procedure bug)

The native LastTransaction carryover needs two things; the org is missing the data prerequisites:

| Requirement | Native source | This org |
|---|---|---|
| Line materializes with `ItemPricingSource = LastTransaction` | inherited from `Asset.PricingSource` via context | **`Asset.PricingSource = NULL` on ALL ~430k assets** → branch never selected |
| `NetUnitPrice` already populated from the prior transaction | the native PricingSettings waterfall, sourced from the asset/prior transaction | line created with `Asset__c`, `OriginalOrderItemId`, `PriceWaterfallIdentifier`, `UnitPrice`, `NetUnitPrice` **all NULL**; native waterfall returns **no priced row** |

The constellation of nulls matches Salesforce's documented warning that amend/renew/cancel "work only with assets created through the standard lifecycle (order activation); assets migrated or manually created may not have the required data relationships." [help.salesforce.com — qocal_manage_assets] The org's own evidence corroborates: the **only** correctly-priced negative lines were bulk data-migrated with a pre-stamped UnitPrice that bypassed the procedure.

**Answer to the framing question:** primarily a **data/config gap** (`Asset.PricingSource` null + assets not lifecycle-wired with a readable prior net feeding the native waterfall). It is **not** a malformed action (the OrderAction is native-correct) and **not** a procedure defect (the consumer branch exists). There is, however, a genuine **native coverage gap** layered on top: see §3.3.

### 3.3 Even with the lever set, no native step *seeds* NetUnitPrice on a non-derived, non-renewal cancel (confirmed)

Verified against the live V18 procedure: the `ItemPricingSource == 'LastTransaction'` branch that the draft and RCA reference is, in V18, **ListContainer74 / ListOperation75**, whose only pricing child is a FormulaBasedPricing step computing `ItemNetTotalPrice = NetUnitPrice * LineItemQuantity`. It **consumes** `NetUnitPrice` and does **not** seed it. (The brief's "ListContainer70" is the V16-era number for the same branch.)

Enumerating every V18 step that outputs `NetUnitPrice`:
- **PricingSetting** (native PricingSettings waterfall) — the genuine from-scratch producer, but established to return **no priced row** for cancel lines (PriceWaterfallIdentifier null, NetUnitPrice null on the subject line).
- **Derived** writers (DerivedPricingFormula, NetUnitPrice Value Reset, DerivedProductsRenewals) — all gated `ItemIsDerived__std == true`; inapplicable to this non-derived line.
- **COLA renewal** writers — gated `SalesTransactionActionType == 'Renew'`; inapplicable to cancel.
- All discount steps (AttributeBased, Volume, Partner, Manual, Bundle) — **transforms** that bind `InputUnitPrice <- NetUnitPrice` and write it back (null in → null out), not seeders.
- **CancelSeedNet** — the team's **custom** block (writes `CancelNetUnitPrice__c → NetUnitPrice`), not native.

So: if the native PricingSettings waterfall cannot find a priced row for the cancel line, **there is no native declarative step that will seed `NetUnitPrice`** on this non-derived, non-renewal cancel line. This is precisely why Option A's sufficiency is contingent on the platform's waterfall actually populating the net for a cancel when `PricingSource = LastTransaction` — which is the unproven question.

### 3.4 PriceRevisionPolicy is a red herring

`PriceRevisionPolicyId` null is expected and irrelevant. `PriceRevisionPolicy` is a renewal price-uplift (CPI/flat-index) mechanism on `AssetStatePeriod`, not the cancellation-credit carryover. Drop it from this ticket.

---

## 4. Verdict on the team's "context-hydration-gap / context-Sync" theory: **REFUTED**

The dossier's leading theory — *"a live reprice does not carry the saved `CancelNetUnitPrice__c` into the runtime context; the fix is a context Sync/regenerate"* — is **falsified by the team's own captured logs.** The metadata is correct **and** the runtime value is present:

1. **The context def already maps `CancelNetUnitPrice__c` for hydration on BOTH item nodes** — `QuoteEntitiesMapping/SalesTransactionItem` (live ctx line 7052) and `OrderEntitiesMapping/SalesTransactionItem` (live ctx line 12430), active version 23, pulled 2026-06-25.
2. **The value IS in the runtime context, reproducibly:** `CancelNetUnitPrice__c={802WC00000OugI7YAJ=3000.0}` inside `RLM_PRICING_BEGIN` of a genuine LIVE reprice (not a Simulate) — reproduced across **three** logs (`log_latest.txt:400`, `log_1553.txt:399`, `log_1613.txt:400`). It is hydrated from the **persisted record field** (set by the before-save `CancelLineNetSeedHandler` trigger) via the configured `queryAttribute` mapping.

**Therefore the runtime hydration query already includes `CancelNetUnitPrice__c`. A context regenerate/Sync is unnecessary and will not fix this. Do not regenerate the context.**

### 4.1 Two corrections to the draft's grounding (per verifier)

- **The grep proof was logically unsound.** `grep -c CancelLineNetSeedPrehook log_latest.txt = 0` does **not** prove the prehook didn't execute: **all 8 known-active RevSignaling prehooks/posthooks also grep to 0** in the same log, because they run inside the **opaque managed RLM code unit** that does not emit class names. The correct basis for "the prehook is not the source of the value / can be removed" is: (a) the value is **stable across three repricings** (a hydration signature, not a transient write); (b) the prehook writes to the **same staging field the trigger already persists** (redundant); and (c) the team's own dossier classes the prehook as **DEAD** ("never reached the procedure input; line procedure plan setup=false"), with a `destructiveChanges.xml` staged to delete it.

- **The "seed never validly tested" claim is WRONG, and this *strengthens* the runtime story.** The headline failing reprice did run against Order 00095539 (`Status=Order Complete / StatusCode=Activated`, Activated 2026-06-16), which the roadmap correctly flags as not validly repriceable. **But the seed HAS been exercised on a valid DRAFT cancel and STILL failed:** `log_latest_check.txt` is a **draft** Cancellation Quote line (`0QLWC000003YOW14AO`, Qty -1, ActionType=Cancel) with `CancelNetUnitPrice__c={0QLWC000003YOW14AO=350.00}` present in the live `RLM_PRICING_BEGIN` context — and `ItemTotalPrice=0.0` (×13). So the value reaches context on a valid draft and the line *still* prices to zero.

> **Critical reframing for the team:** This means the failure is **downstream of hydration** — the seed block is **not actually writing `NetUnitPrice` from the hydrated `CancelNetUnitPrice__c` at runtime**, even on a draft. The draft report's optimistic claim that "the seed already works via the persisted field, it was just never validly tested" is **not supported**: the one valid draft test we have shows the value in context and the total still zero. The "Simulation proves the seed correct" claim is also not credible — same-day docs record that Simulate **rejects `__c` input keys** ("INVALID_INPUT: Invalid tag attribute name key") and was abandoned, so a custom-field simulation could not have run as described. **The gate/seed must be made to demonstrably fire on a draft cancel; that is unfinished work, not a closed loop.**

---

## 5. Options to make Total Price show the negative amount — ranked

Discriminator (given the shared, co-owned, dual-active procedure and the prod-cutover gap): **blast radius** first, then **proven sufficiency**.

### Option A (NATIVE) — `Asset.PricingSource = 'LastTransaction'` + lifecycle-wired assets · **TEST FIRST (cheapest probe)**
- **What:** Data/config only. Backfill `Asset.PricingSource='LastTransaction'` on lifecycle-managed assets; ensure go-forward order **activation** stamps it. Field + hydration + LastTransaction branch are all already wired (confirmed).
- **Why it might work:** the cancel line materializes with `ItemPricingSource=LastTransaction`; *if* the native PricingSettings waterfall then sources the prior net for a cancel, `NetUnitPrice` populates and the line-total branch computes the negative credit. Zero shared-procedure blast radius, currency-correct.
- **Two unproven contingencies (do NOT assume away):** (1) **Documented scope is amend/renew, not cancel** — native cancel applicability is unverified. (2) Even with the lever set, **no native step seeds `NetUnitPrice` unless the PricingSettings waterfall returns a priced row** (§3.3); whether a migrated asset with `OrderItem.Asset__c = NULL` lets the waterfall locate a readable prior net is unverified.
- **Blast radius/risk:** lowest; reversible (single picklist value). **No prod field/context dependency** — a major point in its favor (see §7).
- **Effort:** ~1 hour to trial on one asset + one fresh draft cancel.
- **Disposition of deployed work:** if A works, **retire** the entire custom stack (field + prehook + seed + triggers).

### Option B (CUSTOM, deployed but UNFINISHED) — make the persisted-field seed actually write NetUnitPrice on a draft cancel · **PARALLEL/FALLBACK**
- **Status correction:** This is **NOT** "closer to working than the dossier claims." The one valid draft test (`log_latest_check.txt`) shows the hydrated value present and the total **still zero** — the seed block did not write `NetUnitPrice` at runtime. The remaining work is to determine **why the seq-13 `CancelNetSeed` gate/write does not take effect** when `CancelNetUnitPrice__c` is in context (gate evaluation, write target, or step-ordering vs the native waterfall that may re-null it).
- **Real, confirmed sub-fixes (necessary but shown insufficient so far):** two ordinary Apex bugs in the prehook are fixed in the working tree but **uncommitted** (`git status: M`, +21/−11): `TAG_QUANTITY 'Quantity'→'LineItemQuantity'` (live tag is `LineItemQuantity`, `log_latest.txt:375`) and `resolveScope` scanning all `dataPath` elements. **Nuance:** in the Order log the operative bug is **TAG_QUANTITY** (the `[0]`-only resolveScope still returns 'Order' correctly for an Order reprice; the resolveScope bug specifically defeats the **Quote** path where the root id sits at dataPath index 1). Both fixes are real and should be committed/deployed, but note the prehook is classed DEAD and is **not** the runtime value source — so these fixes alone will not necessarily make the line price.
- **Blast radius/risk:** medium. 7th custom staging field on a churned, dual-active procedure. **Durability hazards:** version drift/oscillation has recurred; two latent V18 landmines once `NetUnitPrice` is non-null — the Derived "NetUnitPrice Value Reset" (gated `ItemIsDerived__std=true`) and an unconditional MAX clamp — confirm both are gated out of the cancel path before shipping. **Prod dependency:** the OrderItem staging field + mapping must be packaged to prod *before* any procedure reference, or prod Order pricing hard-fails (§7).
- **Effort:** medium — diagnose the runtime seed-write failure, commit+deploy the bug-fixed prehook, retest on a fresh draft cancel.
- **Disposition:** **keep, but treat as unfinished**; do NOT adopt the documented "rewrite to direct-NetUnitPrice-write + debug record" pivot wholesale without first proving where the current seed write is being lost.

### Option C (NATIVE, structural) — dedicated Cancellation `SalesTransactionType` + cancellation-specific procedure
- **What:** Route cancellations to a purpose-built procedure via `SalesTransactionType` (Order/Quote carry `SalesTransactionTypeId`). [RLM Dev Guide]
- **Why:** isolates cancel pricing from the shared procedure, removing blast-radius risk; could host an explicit/custom seed safely.
- **Risk/effort:** medium-high build, low ongoing risk; needs design + cutover. Best as a **strategic follow-up**, especially if B is the only thing that works.

### Option D (FALLBACK justification) — explicit value supply when derivation cannot run
- If the install-base assets genuinely cannot be made lifecycle-wired (no readable prior net for the native waterfall), **supplying** the value is a supported pattern (RLM billing API accepts an explicit price when derivation can't run). The custom seed is the pricing-layer analogue. This is the *justification* for B if A proves impossible — not an independent option.

### NOT recommended
- **Context Sync/regenerate** — premise refuted (§4); high blast radius, no benefit. (The documented `DELETE /connect/context-runtime-schema/clear` lever applies to *unhydrated newly-mapped* fields — moot here since the field hydrates.)
- **Pivot to standard Reduction Order / `IsReductionOrder`** — wrong feature family.
- **Treating B as "done"** — the valid draft test shows it does not yet price the line.

---

## 6. Recommended path + ordered next steps

**Phase 0 — read-only confirmations (no DML, ~30 min)**
1. `SELECT PricingSource, COUNT(Id) FROM Asset GROUP BY PricingSource` (expected: all NULL) and check the 6 broken-line source assets — establishes one-time backfill vs activation-flow fix vs both.
2. Confirm an `AssetActionSource` row with readable `NetUnitPrice` for asset `02iWC000008MpX7YAK` (already verified: AAS-000543597, net=3000).
3. Determine whether `OrderItem.Asset__c` being null breaks the item→asset `PricingSource`/waterfall inheritance, or whether `OrderAction.SourceAssetId` is sufficient for the engine to locate the asset and a priced row. **This is the make-or-break for Option A.**

**Phase 1 — two decisive trials, both on a FRESH DRAFT cancel (never 00095539/00095604)**
4. **Native-lever trial (A):** set `Asset.PricingSource='LastTransaction'` on the subject asset, create a fresh draft cancel, reprice, capture FINEST. Does `ItemPricingSource` become `LastTransaction` AND does the native waterfall populate `NetUnitPrice=3000` / TotalPrice -3000 with **zero custom involvement**? Reversible.
5. **Custom-stack trial (B):** commit+deploy the bug-fixed prehook, create a fresh draft cancel with `CancelNetUnitPrice__c` persisted (via trigger), reprice. **Specifically diagnose**: does the seq-13 `CancelNetSeed` gate evaluate true, and does `CancelSeedNet` actually write `NetUnitPrice` — or is a downstream native step (PricingSettings re-derivation / MAX clamp / Derived reset) re-nulling it? The existing draft test (`log_latest_check.txt`) says the write is currently NOT taking effect, so instrument step-by-step.

**Phase 2 — decide**
6. If A works → retire the custom stack; productionize the data backfill + activation stamping. If only B works → finish B (and confirm the V18 landmines are gated out), then plan Option C to de-risk the shared procedure long-term.

---

## 7. Durability, shared-procedure blast radius, and prod-cutover notes

- **Prod is a different procedure object and has an Order-side field asymmetry (confirmed live).** Prod ESD = `9QAaZ00000Bj7S1WAJ` ("…V1") vs UAT `9QAWC0000003mg14AA`. Prod **has** the staging fields on QuoteLineItem (`COLACalculatedPrice__c`, `Partner_Pricing_Source__c`, `Pre_Partner_Price__c`) but **NONE** of the pricing-stack staging fields on OrderItem (no `CancelNetUnitPrice__c`/`Pre_Partner_Price__c`/`Partner_Pricing_Source__c`/`COLACalculatedPrice__c`/`Source_List_Price__c`/`RegionalNetUnitPrice__c`). The moment the prod procedure references an Order-side staging field that is missing on OrderItem **and/or** unmapped on `OrderEntitiesMapping`, prod Order pricing hard-fails: *"We couldn't refresh the prices… we couldn't fetch the data for SalesTransactionContextExt_v2 context definition."* This is a **directly-observed** failure mode (UAT incident 2026-06-24, order 00095591) and a documented platform error class. **The Option B OrderItem field + context mapping must be packaged to prod before any procedure reference. Option A has no such prod dependency.**
- **UAT-only / 0% coverage / version oscillation.** The procedure + prehooks are UAT-only with 0% coverage; V16 and V18 have both been seen Active. Any kept custom artifacts must be baked into the republish source and ownership coordinated (Nir/Marc churn this procedure same-day).
- **Data-side flags can be silently reverted** by Gearset/refresh — the SC-3390 PAD-flag lesson. Treat an `Asset.PricingSource` backfill as needing a go-forward default/automation (stamp at activation), not a one-shot.

---

## 8. Confidence map + open questions

**High confidence (proven against live artifacts):**
- Proximate cause: `NetUnitPrice` null → `× -1 = 0` (V18 line-total step + context log).
- Customer expectation (negative line at prior net) is the standard model (RLM Dev Guide, CPQ Tip Sheet, Trailhead).
- Asset NET, not list, is the correct credit basis — net ≠ list in 77% of rows; 125,741 rows pay a net on list=0 (re-verified live, understated in the draft).
- `Asset.PricingSource` is a restricted 2-value picklist; NULL on the subject asset and on all ~430k assets → LastTransaction branch never fires.
- Context-Sync theory **refuted**: `CancelNetUnitPrice__c=3000` present in context across 3 live logs; field maps on both nodes (active v23).
- The seed has been tested on a **valid draft** cancel and still produced TotalPrice 0 (`log_latest_check.txt`) — runtime seed-write is currently NOT taking effect.
- Headline failing reprice ran on an Activated order (invalid vehicle) — true, but not the only evidence.
- Prehook bugs fixed in working tree, uncommitted (HEAD `'Quantity'` vs working `'LineItemQuantity'`, +21/−11); operative bug in the Order log is TAG_QUANTITY.
- V18 LastTransaction branch (ListContainer74/ListOperation75) **consumes**, does not produce, `NetUnitPrice`; no native step seeds it on a non-derived, non-renewal cancel.
- Prod procedure is a distinct object with no Order-side staging fields (cutover landmine).

**Medium / speculative:**
- Whether `Asset.PricingSource='LastTransaction'` **alone** prices a full **CANCEL** (vs Renew/Amend) — **documentation scopes it to amend/renew only**; this is the single most important unknown.
- Whether the native PricingSettings waterfall can return a priced row for a migrated asset with `OrderItem.Asset__c` null (only `OrderAction.SourceAssetId` populated).
- **Why** the deployed seed does not write `NetUnitPrice` at runtime on a draft (gate eval vs write target vs downstream re-null) — must be diagnosed for Option B.
- Whether the V18 landmines (Derived "NetUnitPrice Value Reset"; MAX clamp) are gated out of the cancel path once `NetUnitPrice` is non-null.

**Open questions (ordered by decisiveness):**
1. Does `Asset.PricingSource='LastTransaction'` on a fresh draft cancel produce `NetUnitPrice 3000 / TotalPrice -3000` natively? (Settles native-vs-custom.)
2. Why does the seq-13 `CancelNetSeed` write not take effect on a draft cancel with the value in context? (Settles whether B is salvageable as-is.)
3. Is `Asset.PricingSource` null due to migration or because activation never stamps it? (Backfill vs activation-fix vs both.)
4. Can the native waterfall locate the asset/prior net when `OrderItem.Asset__c` is null?
5. Are the V18 landmines gated out of the cancel path?
6. Are amend/renew siblings (`QuantityIncreasePricingType`/`RenewalPricingType`) producing the same defect — a broader asset-provenance gap than cancellations?

---

## 9. Sources

**Primary (Salesforce):**
- RLM Developer Guide — Asset.PricingSource, AssetActionSource.NetUnitPrice, OrderItemDetail, OriginalActionType, Initiate Cancellation/skipPricing, SalesTransactionType: https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf
- AssetActionSource object: https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_assetactionsource.htm
- RevSignaling.SignalingApexProcessor (runs inside managed pricing engine): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/apex_interface_RevSignaling_SignalingApexProcessor.htm
- Trailhead — Manage Customer Asset Renewals and Cancellations (negative quantity = -1): https://trailhead.salesforce.com/content/learn/modules/asset-lifecycle-management-with-revenue-cloud/manage-customer-asset-renewals-and-cancellations
- Amend and Renew Assets with Contract Pricing (LastTransaction scope = amend/renew): https://help.salesforce.com/s/articleView?id=ind.qocal_amend_and_renew_assets_with_contract_pricing.htm
- Manage Assets in RLM (migrated/manual assets lack required relationships): https://help.salesforce.com/s/articleView?id=ind.qocal_manage_assets_in_revenue_lifecycle_management.htm
- Order edit/deletion limitations (activated orders frozen): https://help.salesforce.com/s/articleView?id=sf.order_edit.htm
- CPQ Asset Amendment Tip Sheet (negative Net Total credit shape): https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_cpq_asset_amendment_tip_sheet.pdf
- Known Issue — Price Action null source field injects zero: https://help.salesforce.com/s/issue?id=a028c00000gAy3aAAC
- KB — "We couldn't fetch/refresh the data for … context definition": id=002575856, id=002370787
- thecloudupdate.co — LastTransaction prerequisite for negotiated pricing: https://thecloudupdate.co/revenue-cloud-renewal-uplift/
- revenuecloud.info — standard mapping ItemPricingSource → PricingSource: https://revenuecloud.info/unpacking-the-revenue-cloud-pricing-procedure-part-1-list-price-and-sales-price/

**Internal artifacts (verified this session):**
- `Data/sc3441/log_latest.txt` — :374-410 RLM_PRICING_BEGIN live reprice of 00095539 (Order Complete/Activated 2026-06-16); :400 `CancelNetUnitPrice__c=3000` in context; :375 `LineItemQuantity=-1.0`; ItemTotalPrice=0; PriceCalculationFailed
- `Data/sc3441/log_1553.txt:399`, `Data/sc3441/log_1613.txt:400` — `CancelNetUnitPrice__c=3000.0` reproduced
- `Data/sc3441/log_latest_check.txt` — **valid DRAFT** cancel quote line 0QLWC000003YOW14AO (Qty -1), `CancelNetUnitPrice__c=350.00` in context, ItemTotalPrice=0.0 ×13 (seed write not taking effect)
- `Data/sc3441/log_quote_draft.txt`, `log_quote_v2.txt` — same draft line, field not yet in context, ItemTotalPrice=0
- `Data/sc3441/ctx_livecheck/.../SalesTransactionContextExt_v2.contextDefinition` — `CancelNetUnitPrice__c` queryAttribute Quote node :7052 / Order node :12430; PricingSource Asset:510-512, Quote:5897, Order:11668; ItemPricingSource contextTag; v23
- `Data/sc3441/live_debug/V18_block.xml` — CancelSeedNet/CancelSeedInput (custom seed seq 13); ListContainer74/ListOperation75 LastTransaction line-total (consumer); derived/COLA writers gated; PricingSetting native waterfall
- `Data/sc3441/proc_livecheck/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` — sourceFieldName ItemPricingSource keying LastTransaction branch
- `Data/sc3441/prehook/CancelLineNetSeedPrehook.cls` (working tree, uncommitted +21/−11) vs HEAD — TAG_QUANTITY fix + resolveScope scan-all-dataPath
- `Data/sc3441/triggers/.../CancelLineNetSeedHandler.cls` — persists CancelNetUnitPrice__c (before-save)
- `Data/sc3441/SC-3441_RCA.md`, `SC-3441_ROADMAP.md` (:77 reprice DRAFT-only; native-cancel = unproven probe)
- `*Jira/Task/sc3441 .../03_FIX_IMPLEMENTATION_LOG.md`, `04_SIMULATE_DEADEND_AND_PIVOT.md` (Simulate rejects __c keys; observability built because log can't show prehook firing), `05_CHANGELOG_ROW_V18.md` (refuted "order node leaves ItemPricingSource unmapped" reason), `06_COMPLETE_DOSSIER.md`, `HANDOFF.md`
- Live FortraProd Tooling/FieldDefinition queries — prod ESD 9QAaZ00000Bj7S1WAJ; prod OrderItem missing all staging fields; prod QuoteLineItem has them
- `~/.claude/.../memory/project_v16_order_pricing_contextfetch_incident.md` — observed 2026-06-24 context-fetch hard-fail (order 00095591)
