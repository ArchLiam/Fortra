# SC-3346 — Renewal Derived-Maintenance COLA Net = $0

### Root-Cause, Every Fix Attempted, and Salesforce Official Best Practice

**Org:** FortraUAT (`00DWC000006eUFF2A2`) · **Active pricing procedure:** `Rev_Mgmt_Default_Pricing_Procedure` V23
**Author:** Liam (RCA / pricing engine) · **Date:** 2026-07-09
**Related:** `SC3346_FAIL2_BUILD_SPEC.md`, memory `project_sc3346_v23_maint_zero_rca`, `docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md` (SC-3346 §8)

---

## 1. The problem

On a renewal quote, a **derived maintenance** line commits **`NetUnitPrice = $0`** even though its COLA-uplifted net is computed correctly. Example (fresh `initiateRenewal`, BoKS contract, full-engine reprice):

| Line | Selling model / QuoteAction | Derived? | NetUnitPrice |
|---|---|---|---|
| BoKS license `PIA-PIA-NRPS-PIAP` | Perpetual / No Change | no | **312.40 ✓** |
| beSECURE `VM-BSL-RSL-BESECB` | Term-Based / **Renew** | no | **6257.16 ✓** |
| BoKS maint `PIA-PIA-RNM-PIAMBK` | OneTime / Amend | **yes** | **$0 ✗** |

The maintenance line is the **sole** non-committer. Its `COLACalculatedPrice__c` is correct (e.g. `62.48 × 1.0785 = 67.38`); only the commit to `NetUnitPrice` fails.

---

## 2. Root cause (live-verified)

**The line is never a "priced node" (`SalesTransactionItem`) in the pricing context, so the engine has nowhere to write its net.**

Evidence (FINEST debug logs, `Data/sc3346/flush_test.log`, `dg_flipped.log`):
- The reprice flow's `queryTags({tags:['SalesTransactionItem']})` returns **`[]` (empty)** for this line — **before Run_Pricing, after Run_Pricing, and after flipping the line to `Renew`.**
- `RenewalMaintenancePricingService` computes the correct 3-component net and calls `Context.IndustriesContext.updateContextAttributes(...)` → returns **`{isSuccess:true}`** — but writes into an empty context, so the value is **silently discarded**.
- **`NetUnitPrice`, `NetTotalPrice`, `TotalPrice` are all `createable=false, updateable=false`** (verified via describe) — the net can ONLY be set by the pricing engine, never by Flow/DML/UI.

**Why the line isn't a priced node** — two structural facts, true in **every** procedure version (V14 through V23):
1. It is **derived** (`ItemIsDerived=true`): it has no direct-price PBE (its PBEs are `IsDerived`, `UnitPrice=0`); its price is supposed to come from a **contributor** (the license) via `PriceBookEntryDerivedPrice`.
2. On **renewals**, native derived pricing (`DerivedProductsRenewals`, the element that hydrates `DerivedPricingAttribute` and makes a derived line a priced node) is **scoped out** by the `DerivedProductsNonRenewal` filter (`QuoteTypeText NotEquals 'Renewal'`). So on renewal the contributor never resolves → `DerivedPricingAttribute` stays null → not a priced node → no net.

The `QuoteAction.Type` (`Amend`/`No Change`/`Renew`) does **not** change this — flipping to `Renew` was tested and the line stayed absent from the context.

---

## 3. Everything attempted (this investigation) — and why each failed

> All of these were **live-tested** and are **dead ends**. Do not re-attempt.

| # | Attempt | Layer | Result & reason |
|---|---|---|---|
| 1 | **Posthook BoKS-scoped tier default** (`PartnerNetPricePosthook.loadNewMaintenanceLines`, default absent tier → Standard 0.20) | Apex hook | Deployed, then **reverted**. Fired but the context write no-ops on a non-priced node; also this was really the FAIL-1 (new-biz) case, which turned out to be **data** (orphan maint line, no contributor). |
| 2 | **V23 procedure formula backfill** — edited `ListContainer9 → DerivedPricingFormula` renewal branch to `IF(NetUnitPrice>0, NetUnitPrice, IF(COLACalc>0, COLACalc, NetUnitPrice))` | Procedure (canvas) | **NO-GO.** Edit went live (verified in ESD); repriced 7AKH + DOpB → stayed $0. `resultIncluded=false` write to a non-priced node is discarded. |
| 3 | **Route renewal to the Term-Defined RRM product** (selling-model direction) | Catalog | **Refuted by the org's own code.** `RenewalMaintenanceAutoAddHandler` adds RRM as `QuoteAction.Type='Add'` (not `Renew`), asset-less → resolves no contributor. Term-Defined-ness does not confer priced-node status. |
| 4 | **Add Term-Defined selling model to RNM** | Catalog | **Rejected.** `Asset.HasLifecycleManagement` is immutable at asset creation → only helps *future* sales; the existing OneTime RNM asset book keeps renewing as Amend/$0. |
| 5 | **QuoteAction flip `Amend`→`Renew`** (`RenewalMaintenanceFlip`, "PROVEN 2026-06-15") | Apex + data | **Refuted on V23.** Tested on a realistic multi-asset renewal AND the exact 2026-06-15 canary asset, via both PST-Force and the flow-with-compensator: line stayed **$0**. The flipped `Renew` line is *still* absent from `SalesTransactionItem`. |
| 6 | **Relax `ListContainer2 → COLAUpliftonRenewal` gate** (drop `DerivedPricingAttribute IsNotNull`) | Procedure (canvas) | **Futile — proven before editing.** Diagnostic: even a flipped-`Renew` line is not in the context (`SalesTransactionItem:[]`), so there is nothing to gate on or write to. |
| 7 | **Re-add the V14 `DerivedPricing`/`DerivedPricingRenewals`/`DerivedPricingValuesAssignment` group** removed by the refactor | Procedure (canvas) | **LOW confidence / not the fix.** All three were `resultIncluded=false` writing to the same non-priced node; the `DerivedPricingAttribute` hydrator is byte-identical V14↔V23; the "June commit" was almost certainly the Apex compensator, not the procedure. |
| 8 | **Born-net at creation** (stamp the net when the renewal line is created) | Flow / DML | **Impossible.** `NetUnitPrice` is `createable=false, updateable=false`. It cannot be written by any Flow, DML, or UI action. |

### 3a. Prior-session attempts (from memory `project_sc3346_rncola_commit_fix`, V14/V16 era) — also dead
- **Prehook `InputUnitPrice`/`ListPrice` seed** (`COLAUpliftPrehook`) → no-op on non-priced node.
- **Prehook `UnitPrice` seed** → `UnitPrice` landed (writable) but did **not** propagate to `NetUnitPrice`.
- **Posthook net write** (`PartnerNetPricePosthook`, live v1.5) → `updateContextAttributes` returns success, value discarded.
- **In-procedure "lever-d" committer** (`resultIncluded=true` element writing `COLACalc→NetUnitPrice`) → zero observable effect on settled/non-priced nodes; global `resultIncluded` flip would misprice ~513K legacy lines.
- **`RenewalMaintenancePricingService` via the reprice flow** → `updateContextAttributes` success + no change (empty context).
- **PBEDP backfill** (map owned RNM asset → derived RRM PBE) → platform-rejected: *"The selected product is a derived product and can't be set as the source product."*

**Consistent finding across ~30 sessions + this one:** no reprice-time, hook, procedure, Flow, or DML mechanism can commit the net, because the line is not a priced node. The COLA *value* has always been correct; only the *commit* fails.

---

## 4. Salesforce official documentation — what it says (research 2026-07-09)

> Note: `help.salesforce.com` renders as a JS SPA; some exact quotes below are reconstructed from search-result extractions of the official pages, but the object/field names and behaviors are consistent across the Developer Guide object references.

### 4.1 Selling model governs renewability and the renewal action
- **`ProductSellingModel`** — `SellingModelType ∈ {OneTime, TermDefined, Evergreen}`. **OneTime is explicitly not a subscription** and must have null `PricingTerm`/`PricingTermUnit` — a OneTime product **has no term to renew**.
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_productsellingmodel.htm>
- **`QuoteAction`** — `Type ∈ {Add, Amend, Association, Cancel, No Change, Renew, Transfer}`. Only subscription/term lines renew as `Renew`; OneTime lines carry over as `No Change`/`Amend`.
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_quoteaction.htm>
- **Initiate Renewal** action — renewal is an **asset/subscription continuity** operation driven by the Product Selling Model term; `skipPricing=false` runs pricing on the renewal line.
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_renew_assets.htm>
- **CPQ guidance (corroborating):** one-time *"Assets are not renewable products and therefore should not have a value on renewal."* → a OneTime maintenance line renewing to $0 is *expected* platform behavior.

### 4.2 The pricing engine only writes to nodes that exist in the context
- **Run Salesforce Pricing** executes the procedure against a **context instance** holding `SalesTransactionItem` nodes; **`PricingPreference=Force` enforces pricing on existing nodes — it does not create a node for a line that isn't one.**
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_run_salesforce_pricing.htm>
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/apex_enum_RevSalesTrxn_PricingPreferenceEnum.htm>
- **Get Renewable Assets Summary** — documents that **renewal line items may return a price of zero** when the full pricing procedure/procedure-plan is not engaged (corroborates "not a priced node → $0").
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/actions_obj_get_renewable_assets_summary.htm>

### 4.3 Derived pricing requires a resolvable contributor
- **`PriceBookEntryDerivedPrice`** / Salesforce Pricing standard objects — a derived line's price comes from a **contributing product** resolved into the context via the **Discovery Procedure** (Fetch Pricing Rules → Map Products → Asset Discovery). The discovery procedure and pricing procedure **must share the same context definition**. A derived product **cannot be its own contributor source**.
  <https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/pricing_std_objects_parent.htm>

### 4.4 Renewal price uplift (the "COLA") is a native, subscription-only capability
- **Negotiate Price Uplifts for Subscription Renewals** — `Renewal Uplift (%)` on Subscription/Contract (Subscription precedence over Contract); `PriceRevisionPolicy`; `Unit Price Uplift`. Committed net = `Last-Transaction Price × (1 + CPI + Renewal Uplift%)`. **Applies only to term subscription products, not one-time/evergreen**, and requires `Asset.PricingSource = LastTransaction`.
  <https://help.salesforce.com/s/articleView?id=ind.qocal_renewal_price_uplifts.htm&language=en_US&type=5>
- **Use Consumer Price Index for Automated Renewal Price Uplifts** — CPI/index-rate escalation for renewals.
  <https://help.salesforce.com/s/articleView?id=ind.qocal_consumer_price_index_and_price_uplifts.htm&language=en_US&type=5>
- **`Asset.PricingSource`** (`LastTransaction` | `PriceBookListPrice`) and **`Asset.HasLifecycleManagement`** (fixed at creation).
  <https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_asset.htm>

### 4.5 Best-practice synthesis
**Anything that renews should be modeled as a Term-Defined (or Evergreen) subscription with its own priceable PBE**, and renewal escalation should use the **native renewal-uplift stack** (`Renewal Uplift %` / `PriceRevisionPolicy` / CPI) on `LastTransaction`-sourced assets. Modeling a renewable charge as a **OneTime + derived** line is off the supported renewal path — exactly Fortra's situation.

---

## 5. The supported fix (a build, not a config/UI change)

Model **renewal maintenance the way subscriptions already work in this org** — the pattern proven live by the beSECURE line that committed 6257.16 on the same quote:

1. **Non-derived, term-based line with a real PBE price.** The renewal maintenance line must be a priced node in its own right (like beSECURE), not a derived line whose contributor fails to resolve on renewal.
2. **Native renewal uplift for the COLA** — `Renewal Uplift (%)` / `PriceRevisionPolicy` / CPI on `Asset.PricingSource=LastTransaction`, instead of the custom `COLACalculatedPrice__c` + out-of-band `updateContextAttributes` write (which cannot commit).
3. **Resolve the RNM→RRM substitution** so the renewal emits the term-based line, and ensure the owned asset is lifecycle-managed so it renews as `Renew`.

This is the **SC-3404 architecture** work. It requires a data-model decision and a per-product pilot + verification, and it is the only path that satisfies the platform's "priced node" requirement documented in §4.2.

### What NOT to do again (documented dead ends)
- Do **not** write `NetUnitPrice` from a Flow, DML, prehook, posthook, or `updateContextAttributes` — it is engine-owned and the write is discarded.
- Do **not** flip `QuoteAction` to `Renew` and expect a commit — the derived line is still not a priced node.
- Do **not** add/relax procedure elements (formula, gate, re-added V14 group) — there is no node to write to.
- Do **not** flip a OneTime product to Term-Defined and expect existing assets to renew — `HasLifecycleManagement` is immutable.

---

## 6. Appendix — verified facts

- `NetUnitPrice` / `NetTotalPrice` / `TotalPrice` on `QuoteLineItem`: **`createable=false, updateable=false`** (engine-owned). `UnitPrice` (Sales Price): writable (display-only; billing/Workday use the net).
- Selling models: master `ProductSellingModel` set is healthy (One Time + 4 Term-Based active; Evergreen inactive). RNM = OneTime by design (39 legit "-Yearly" TermDefined); RRM = TermDefined (1,611) with **100 active RRM products missing a TermDefined model** = a separate catalog-hygiene gap (does not by itself fix this issue).
- "Worked on V14" was **inferred** from a class docstring + memory, **never independently verified**; the V14 procedure elements were all `resultIncluded=false` writing to a non-priced node, so the June commit was most likely the Apex compensator, not the procedure.
- Evidence files: `Data/sc3346/flush_test.log`, `Data/sc3346/dg_flipped.log`, `Data/sc3346/regdiff/` (V14 vs V23 blocks), `Data/sc3346/SC3346_FAIL2_BUILD_SPEC.md`.
