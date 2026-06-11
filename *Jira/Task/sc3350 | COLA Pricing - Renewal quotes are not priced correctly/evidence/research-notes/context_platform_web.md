# SC-3350 — Context/Platform Mechanism (WEB) research notes

**Date:** 2026-06-10. **Org:** FortraUAT (read-only). **Author stream:** Context/Platform mechanism — WEB.
**Goal:** Ground the ticket's central claim — *"renewal quotes are generated headlessly by RLM and never run a full pricing-procedure reprice, so the COLA prehook + description prehook never fire"* — against official Salesforce platform behavior, and establish the supported fix patterns.

**Primary authoritative source:** Revenue Cloud Developer Guide, **Version 67.0, Summer '26, last updated June 5 2026** (downloaded to `/tmp/rlm_devguide.pdf`, extracted to `/tmp/rlm_devguide.txt`, 239,410 lines). This is current as of the ticket date. Line cites below are into that text extract.

---

## TL;DR — the central claim is DIRECTIONALLY RIGHT but the stated mechanism is IMPRECISE

1. **The platform DOES support running the full pricing procedure during renewal generation.** The standard `initiateRenewal` invocable action has an explicit `skipPricing` boolean: *"Indicates whether the pricing procedure must be skipped (true) or performed (false)."* (devguide L148740 / L148876 / L149041; available API v64.0+). So "renewals can never reprice" is **false as an absolute platform statement** — repricing on renewal is a first-class, supported option.

2. **But the live Fortra renewal flow does NOT request pricing and does NOT reprice afterward.** The active `Fortra_Create_Renewal_Quote` (v6, Marc DeBrey, 2026-04-21) calls `initiateRenewal` passing only `renewAssetIds / renewOutputType=Quote / renewOpportunityId / renewContractId / renewStartDate / renewEndDate` — **`skipPricing` is NOT passed at all**, and there is **no Place Quote / Place Sales Transaction / Reprice / pricing subflow anywhere after the call**. So the renewal's pricing outcome is entirely governed by (a) the platform default for `skipPricing`-when-omitted, (b) `Asset.PricingSource`, and (c) the active pricing procedure / procedure-plan config. (Evidence: live flow retrieve, below.)

3. **Net:** the *observable outcome* the brief describes (prehooks don't apply COLA/description on renewals) is consistent with the live config, but the precise reason is **NOT "the platform structurally can't reprice renewals."** It is **"the flow neither forces pricing nor sets the renewal to price off the last transaction, so the line lands at list / unrepriced."** This distinction matters because it opens **native, supported fix paths** the brief under-weighted (force pricing via `skipPricing=false`; set `Asset.PricingSource=LastTransaction`; native `UnitPriceUplift` / `PriceRevisionPolicy`).

Confidence: HIGH on items 1–2 (direct doc + live metadata). MEDIUM on the exact platform default of `skipPricing` when omitted (not stated in the guide — see Open Questions / needs-trace).

---

## Q1 — How are renewal quotes generated in RLM, and is a pricing reprice part of that flow by default?

### Platform (devguide)
- **Initiate Renewal Action** — `POST /services/data/v67.0/actions/standard/initiateRenewal`. *"Initiate and execute the renewal of an asset. Specify the IDs of the assets that you want to add to renew by specifying a start date. You can also specify the type of renewal record that you want to create, such as a quote or an order."* (devguide L1756 / extract L148690+). Available v60.0+.
  - Inputs: `renewAssetIds` (Required), `renewContractId`, `renewOpportunityId`, `renewOutputType` (Required; Quote|Order), `renewStartDate`, `renewEndDate`, `rampOptionsDetails`, and **`skipPricing`** (boolean; *"Indicates whether the pricing procedure must be skipped (true) or performed (false)."* v64.0+) — extract L148735-148740, L149036-149041.
  - Outputs: `renewRecordId`, `requestIdentifier`. The renewal runs **async** (`requestIdentifier` is "used to track the async request").
- The sibling actions `initiateAmendment` and `initiateCancellation` carry the **same `skipPricing` boolean with identical wording** (L148535-ish, L148871) — so this is a uniform "do pricing or not" control across amend/renew/cancel.
- **Pricing is therefore an explicit, parameterised step of renewal generation — not unconditionally on, not unconditionally off.** The doc's sample requests all set `"skipPricing": false` (i.e., *perform* pricing) — devguide L148781 / L148921 / L149088.
- **Caveat — renewal can return $0:** the *Get Renewable Assets Summary* action note: *"This action doesn't support providing a summary with procedure plans. As a result, renewal line items may return a price of zero."* (devguide L1749 / extract L148539). This is a documented native footgun where the renewal-summary path and **Procedure Plans** don't interoperate, yielding zero-priced renewal lines — relevant to Fortra's $0 renewal-line observations.

### Live Fortra path (decisive)
- **Two renewal-quote flows exist in UAT** (Tooling query, FlowDefinition):
  | DeveloperName | Active Ver | LastModifiedBy | LastModified |
  |---|---|---|---|
  | `Fortra_Create_Renewal_Quote` | **6** | **Marc DeBrey** | 2026-04-21 |
  | `Fortra_Renewal_Quote_Creation` | 1 | Joe Martinez | 2026-03-30 |
  (SOQL: `SELECT DeveloperName, ActiveVersion.VersionNumber, LastModifiedDate, LastModifiedBy.Name FROM FlowDefinition WHERE DeveloperName LIKE '%Renew%'`.)
- **`Fortra_Create_Renewal_Quote` v6 is the platform-`initiateRenewal` path** referenced by the brief. Retrieved live to `Data/sc3350/research/flows/unpackaged/flows/Fortra_Create_Renewal_Quote.flow`. Its `<description>`: *"Override for quotingAI__createRenewalQuote. Resolves Asset origin chain, creates Opportunity, calls initiateRenewal with pre-resolved OpportunityId and ContractId, then populates Fortra-specific fields on the created Quote."* (flow L257).
  - The single `actionCall` (`Call_Initiate_Renewal`, flow L3-58) passes **only**: `renewAssetIds`, `renewOutputType=Quote`, `renewOpportunityId`, `renewContractId`, `renewStartDate`, `renewEndDate`. **`skipPricing` is absent.**
  - The rest of the flow is `recordCreates` (Opportunity) + `recordUpdates` (stamp `Quote_Type__c=Renewal`, `Renewal_Contract__c`, etc. on the returned Quote). **No Place Quote, no Place Sales Transaction, no Reprice action, no pricing subflow** (grep of all `<actionName>/<actionType>/<flowName>` in the flow → only `initiateRenewal`).
- **`Fortra_Renewal_Quote_Creation` (v1, Joe Martinez)** is a *different*, custom Screen Flow (captured at `Data/cola-renewal-review/live/flow_retrieve/.../Fortra_Renewal_Quote_Creation.flow`). It **does NOT use initiateRenewal at all** — it manually `recordCreates` a Quote and loops `ContractLineItem`s to build QLIs with `UnitPrice = ContractLineItem.UnitPrice` and `Pre_COLA_Price__c = ContractLineItem.UnitPrice`, then bulk-inserts via a plain `recordCreates` (direct Flow DML — fires QLI triggers, **not** the pricing engine). Its success screen literally says *"COLA pricing will be automatically applied to the Quote Line Items via the COLAUpliftHandler."* This flow embodies the trigger-only path. **Which flow is wired to the live Renew button must be confirmed** (the v6 description says it overrides `quotingAI__createRenewalQuote`, suggesting v6 is the production path and `Fortra_Renewal_Quote_Creation` may be legacy/parallel). → **needs-trace.**

**Answer Q1:** Renewal quotes in RLM are generated by the async `initiateRenewal` action (or a fully custom flow). **Pricing on renewal is an explicit option (`skipPricing`), not an unconditional default.** Fortra's active `initiateRenewal` flow **omits `skipPricing` and never reprices afterward**, so renewal pricing depends entirely on the platform default + `Asset.PricingSource` + procedure config — none of which the flow forces. This *operationally* reproduces the "no reprice / prehooks don't fire" outcome, but it is a **config choice, not a platform limitation.**

---

## Q2 — Is there a supported/native way to force pricing on renewal lines?

Yes — several, all first-class:

1. **`skipPricing=false` on `initiateRenewal`** (devguide L148740). The simplest: set the flow to explicitly request pricing during renewal generation. (Whether this alone fires the COLA prehook depends on the procedure/procedure-plan binding — see Q3.)

2. **Place Sales Transaction API with `pricingPref=Force`** (the modern reprice). Place Quote API is **deprecated as of v63.0**; *"In API version 63.0 and later, use the new Place Sales Transaction API"* (devguide L1383 / extract L127367). Pricing preference is controlled by `pricingPref` / `PricingPreference`:
   - `Force` — *"Reprices all lines."*
   - `System` — delta pricing on unprocessed lines (default in Place Quote/Order; *"The default value is Skip"* in some ingestion contexts — extract L127275).
   - `Skip` — skip pricing.
   (devguide `TransactionProcessingType.PricingPreference`, extract L124492-124505; available v65.0+.) A "Reprice/Refresh Prices" button is the standard UI affordance that *"calls the Place Quote/Order APIs to refresh prices on demand"* (arraytrail). → A post-renewal **Place Sales Transaction (`pricingPref=Force`)** step in the flow would force the full procedure (and thus the whole prehook chain) to run.

3. **`Asset.PricingSource`** (devguide L116118-116127): *"Pricing source to use when amending or renewing an asset. Valid values: LastTransaction — Last Transaction; PriceBookListPrice — Price Book or List Price."* (v60.0+). **This is the single most important native control for defect #1.** If renewals resolve to `PriceBookListPrice`, the line is priced at list (exactly the defect-#1 symptom: "priced at plain list price"). Setting `PricingSource=LastTransaction` makes the renewal base = the last paid (contract) price, which is the correct base for a COLA uplift. The cloud-update renewal-uplift article states the native fixed-% uplift *"requires Pricing Source = Last Transaction — if set to List Price, uplift is ignored."*

4. **Invoke pricing in Flow** (Run Pricing / Salesforce Pricing + Salesforce Headless Pricing flow actions) — you supply context-instance IDs, pricing-procedure names, and discovery procedures (per Salesforce help; confirmed by search result text). This is the "force a Reprice-All on renewal creation" the brief proposes — and it IS supported.

**Answer Q2:** Yes. Forcing pricing on renewals is fully supported via (a) `skipPricing=false`, (b) a post-creation **Place Sales Transaction with `pricingPref=Force`** (Place Quote is deprecated v63+), and/or (c) a Run-Pricing flow action — and the *base* is governed by `Asset.PricingSource=LastTransaction`. Any of these would cause the procedure (and the registered prehooks — COLA + `QLDescriptionGeneratorPrehook`) to execute.

---

## Q3 — Correct architectural pattern Salesforce recommends for custom uplift on renewals: pricing-procedure prehook vs trigger?

**Salesforce's recommendation is unambiguously: do it in the pricing layer (procedure element / Apex prehook within the procedure plan), NOT in a trigger.** Two tiers:

### (a) Native, no-code/low-code uplift (preferred where it fits)
- **Fixed % uplift:** native `QuoteLineItem.UnitPriceUplift` (percent) field — *"Indicates the percentage increase of a line item's unit price."* (devguide L118922; v65.0+) — combined with `Asset.PricingSource=LastTransaction`. Per cloud-update: *"when the order is activated, the uplift percentage carries through to the asset."*
- **CPI / index-based uplift (this is COLA):** native **`PriceRevisionPolicy`** + **`IndexRate`** objects and the standard pricing-procedure **`PriceRevision`** element. `PriceRevisionPolicy` = *"the guidelines and methods used to modify product or service prices, often incorporating formulas based on price revision … a flat adjustment or one directly based on the price revision entry data."* (devguide L47231-47235, L49998-50002; v65.0+). `PriceRevision` is a first-class pricing-procedure element type (devguide L62092, listed beside ListPrice/DerivedPricing/PriceAdjustmentMatrix). Cloud-update: *"The standard pricing procedure template includes the Price Revision element … MAX(PriceIndex + 5, 8) … after updating Index Rates, always refresh the decision table."* **Uplift is configured via the pricing procedure's Price Revision element, NOT through prehooks or standalone contract settings.**
  - **Implication for Fortra:** COLA is a textbook **CPI/index uplift on renewal** — there is a **native mechanism purpose-built for it** (`PriceRevisionPolicy`+`IndexRate`+`PriceRevision`). Fortra reimplemented it from scratch in custom Apex (`COLAUpliftPrehook` + `COLAUpliftHandler` trigger + CMDT rate tables). Worth flagging to Marc/German as a "should we use the native Price Revision policy?" architecture question — but note it's v65+ and may post-date the original COLA build.

### (b) Custom Apex uplift — use a pricing-procedure **prehook**, not a trigger
- Apex hooks attach to **Procedure Plans** via the **`RevSignaling.SignalingApexProcessor`** interface (single method `execute(RevSignaling.TransactionRequest) → RevSignaling.TransactionResponse`). The request carries `procedurePlanInstance` + `ctxInstanceId`; you operate on the pricing **context instance**, not on sObjects. (devguide RevSignaling Namespace, extract L60696-60900.) Requires the **"Procedure Plan Orchestration for Pricing"** Revenue Setting toggle (devguide L60711).
- **Prehooks run BEFORE the standard pricing procedure**; posthooks after. They fire **as part of procedure-plan execution during a pricing run** (i.e., during a Place/Reprice/`skipPricing=false` renewal) — *not* on a bare record save/insert. (cloud-update "Apex Hooks": *"Prehooks: Run before the standard pricing procedure … Posthooks: Execute after pricing completes."*; *"hooks execute during pricing procedure runs (reprice/quote placement)."*) cloud-update explicitly frames prehooks as **the recommended approach** over triggers: they *"operate within the pricing transaction context, access attribute values and sales transaction items directly, avoid trigger complexities."*
- **Procedure-plan renewal routing:** Procedure Plans route a transaction to a transaction-type-specific procedure (New Sale / Amendment / **Renewal** / Cancellation) based on criteria such as **`SalesTransaction.OriginalActionType = Renewal`**. The standard field backing this is **`Order.OriginalActionType` / Quote analog** — picklist `Amend|Cancel|Renew|Transfer`, *"Specifies the action that created the order."* (devguide L122932; v61.0+). So a renewal-only uplift procedure/prehook is correctly gated on `OriginalActionType=Renew` (which is exactly how Fortra's V10 procedure gates the COLA step on `ActionType='Renew'` per the brief).

### Why the trigger path is the anti-pattern (and why it's the proximate cause of both defects)
- A trigger fires on QLI **insert/update DML**, which is the path a *headless* renewal insert takes — but it runs **outside** the pricing-context/procedure orchestration, so it can't see the context instance, can't participate in the waterfall, and (critically) **does not cause the registered prehook chain — including `QLDescriptionGeneratorPrehook` — to run.** That is structurally why defect #2 (no description) tracks defect #1: both the COLA prehook and the description prehook live in the procedure/procedure-plan layer, which the trigger-only headless path never enters.
- Salesforce's pattern says: put renewal uplift in the **pricing layer** and ensure the renewal **actually runs pricing** (`skipPricing=false` and/or a forced Place Sales Transaction reprice). Then ONE pricing pass fires native uplift (or the COLA prehook) AND the description prehook — fixing both defects with one architectural change. This corroborates the brief's "unifying fix = force a Reprice-All on renewal creation," and grounds it in supported APIs.

**Answer Q3:** Pricing-procedure **prehook** (within a Procedure Plan, `SignalingApexProcessor`, gated on `OriginalActionType=Renew`) — or better, the **native `PriceRevisionPolicy`/`IndexRate`/`PriceRevision`** mechanism for CPI/COLA — is the Salesforce-recommended pattern. A **trigger is explicitly the wrong layer**. The fix must guarantee a real pricing pass on renewal (`skipPricing=false` or post-creation **Place Sales Transaction `pricingPref=Force`**), with `Asset.PricingSource=LastTransaction` as the base.

---

## Deltas vs the 08:13 brief

- **Brief's central claim is over-stated.** Brief (line 12, 23): renewals "are generated headlessly and **never** run a full pricing reprice through the procedure" — framed as an inherent property of the RLM renewal path. **Platform reality:** `initiateRenewal` has a `skipPricing` toggle (perform vs skip pricing); pricing on renewal is **supported and parameterised**, not structurally impossible. The true root is a **config/flow choice** (flow omits `skipPricing`, never reprices, base not forced to LastTransaction), not a platform incapability. (Confidence HIGH.)
- **Brief named the wrong/over-simplified mechanism.** Brief (line 23) says the standard path is `Fortra_Create_Renewal_Quote → platform initiateRenewal`. That flow IS the `initiateRenewal` path (confirmed) — good — but the brief did not surface (a) that `skipPricing` is omitted, (b) that there is NO post-call reprice, or (c) the *second* flow `Fortra_Renewal_Quote_Creation` (trigger-only, manual QLI insert, no initiateRenewal) which is the literal trigger-only path. Which flow the live Renew button uses is unresolved. (Confidence HIGH on the two-flow finding; MEDIUM on which is production.)
- **New native fix levers the brief omitted:** `Asset.PricingSource` (LastTransaction vs PriceBookListPrice) is the decisive native control for defect #1; `UnitPriceUplift` (native % uplift) and `PriceRevisionPolicy`+`IndexRate`+`PriceRevision` (native CPI/COLA) are purpose-built native mechanisms for this exact uplift use case. Fortra's all-custom Apex COLA stack may be reinventing native v65+ capability. (Confidence HIGH these exist; MEDIUM on whether they fit Fortra's 3-tier override / multi-year model.)
- **Place Quote is deprecated (v63+).** Any "force reprice" fix should target **Place Sales Transaction**, not Place Quote. (Confidence HIGH.)
- **Documented native $0-renewal footgun:** *"Get Renewable Assets Summary … doesn't support providing a summary with procedure plans. As a result, renewal line items may return a price of zero."* — a platform-level reason renewal lines can come back at $0, independent of Fortra code. (Confidence HIGH it's documented; MEDIUM on whether it's in Fortra's path.)
- **Confirms (not contradicts) the brief's unifying-fix direction.** Brief lines 17/34/52: "force a Reprice-All on renewal creation fixes #1 and #2 together." Platform docs support this exactly (Place Sales Transaction `pricingPref=Force`, or `skipPricing=false`), and explain *why* (prehook chain runs only inside a pricing pass). The Marc same-day class edits (AssetContractQueryHelper/QLDescriptionGeneratorPrehook/COLAUpliftHandler/COLAUpliftPrehook/COLAUpliftTest) do **not** change this platform-level conclusion — they live in the trigger/prehook layer, which still only matters once a pricing pass is guaranteed. (I did not diff those classes in this stream — that's the Apex stream's job.)

---

## Open questions / needs-trace

1. **Default of `skipPricing` when omitted** on `initiateRenewal` — the v67 dev guide does NOT state it; all samples set `false`. Need a live debug-log trace of a renewal to confirm whether the procedure runs at all. (If default = skip → brief's outcome holds; if default = perform → the line still lands at list, which would point the root cause at `PricingSource`/procedure config, not "no reprice.") **This is the single highest-value trace.**
2. **Which renewal flow is bound to the live Renew button** — `Fortra_Create_Renewal_Quote` v6 (initiateRenewal) vs `Fortra_Renewal_Quote_Creation` v1 (trigger-only manual insert)? Both are Active. Determines whether the platform pricing engine is even in the picture.
3. **`Asset.PricingSource` value on Fortra renewable assets** — LastTransaction or PriceBookListPrice? If the latter, that alone explains "priced at list" and may be a one-field config fix. (SOQL: `SELECT PricingSource, COUNT(Id) FROM Asset GROUP BY PricingSource`.)
4. **Does Fortra use Procedure Plans** ("Procedure Plan Orchestration for Pricing" toggle) or the legacy single default procedure? Prehook firing semantics differ; the RevSignaling prehook interface requires the toggle ON.
5. **Native vs custom COLA** — is `PriceRevisionPolicy`/`IndexRate` available + viable for Fortra's 3-tier override + multi-year compounding model, or is the bespoke Apex justified? (Architecture decision for Marc/German.)

---

## Sources (URLs)

- Revenue Cloud Developer Guide v67.0 (Summer '26, June 5 2026) — `https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf` (PRIMARY; initiateRenewal/skipPricing, Place Sales Transaction/pricingPref, PricingSource, UnitPriceUplift, PriceRevisionPolicy/IndexRate/PriceRevision, OriginalActionType, RevSignaling/SignalingApexProcessor)
- Initiate Renewal Action — `https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm` (JS-rendered; content via the PDF above)
- Apex Hooks (Customize Procedure Plans) — `https://help.salesforce.com/s/articleView?id=ind.pricing_customize_pricing_procedures_with_apex_hooks.htm`
- Apex Hooks explainer — `https://thecloudupdate.co/apex-hooks-in-salesforce-revenue-cloud/`
- Price Uplift During Renewals (Fixed vs CPI/COLA) — `https://thecloudupdate.co/revenue-cloud-renewal-uplift/`
- Procedure Plans (renewal routing, OriginalActionType) — `https://www.arraytrail.com/automating-complex-pricing-in-salesforce-revenue-cloud-with-procedure-plans/`
- When to Refresh / Reprice (Place Quote/Order, Instant vs Save-time pricing) — `https://www.arraytrail.com/salesforce-revenue-management-formerly-revenue-cloud-advanced-exactly-when-to-refresh-and-how-to-automate-it/`
- Pricing Procedures overview — `https://thecloudupdate.co/pricing-procedures-in-salesforce-revenue-cloud/`

## Live-org / repo evidence artifacts
- Retrieved flow: `Data/sc3350/research/flows/unpackaged/flows/Fortra_Create_Renewal_Quote.flow` (v6, initiateRenewal, no skipPricing, no reprice)
- Captured trigger-only flow: `Data/cola-renewal-review/live/flow_retrieve/unpackaged/flows/Fortra_Renewal_Quote_Creation.flow`
- FlowDefinition tooling query (two active renewal flows) — see Q1 table.
