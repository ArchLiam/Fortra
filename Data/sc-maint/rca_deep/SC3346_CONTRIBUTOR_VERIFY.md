# SC-3346 Contributor / Discovery-Procedure Verification — the Supported Fix (FortraUAT, 2026-06-15)

## Executive answer — does a discovery procedure exist + share the context? what is the contributor + why does it (not) resolve?

**Yes.** A real, ACTIVE discovery procedure exists (`Salesforce_Default_Pricing_Discovery_Procedure_v2`, ES `9QLWC000003ae0P4AQ` / ESD `9QAWC000000C8mb4AC`, active V1 since 2026-05-30) and it **shares the pricing context** `SalesTransactionContextExt_v2` (ContextDefinition `11OWC000002m21Z2AQ`) with the active V14 pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` (ES `9QLWC0000015cDl4AI`). It carries the 3 documented elements (Asset Discovery / Fetch Pricing Rules / Map Product). So the official mechanism is intact — this is **not** a missing-procedure or native-`DerivedPricingDataRetrieval` (SC-3372) substitution problem. **The contributor for a renewal-maintenance line is the prior ASSET surfaced via `QuoteAction(Type='Renew').SourceAssetId`.** It resolves on the 67.38 control because that quote carries a Renew QuoteAction pointing at an RRM asset with a clean AssetActionSource on the derived PBE; it **fails** on the failing lines for two distinct, verified reasons: (a) the 60.64-fossil line's quote has **zero QuoteActions** (no contributor to surface), and (b) the $0 wrong-product line's Renew QuoteAction points at an **RNM/PIAMBK asset whose product ≠ the derived RRM line** and is mapped nowhere as a contributor.

## Verified config — discovery procedure (or native), Map Products mappings, ContributorScope, AssetActionSource, the assets

**Procedures and context (V1 probe):**
- 5 ExpressionSet procedures. Pricing: `Rev_Mgmt_Default_Pricing_Procedure` (ES `9QLWC0000015cDl4AI`, ESD `9QAWC0000003mg14AA`, **V14 Active**, `contextDefinitions=["SalesTransactionContextExt_v2"]`).
- Discovery (`InterfaceSourceType=DiscoveryProcedure`, read via **standard data API** — this field is null over Tooling): the only one that pairs is `Salesforce_Default_Pricing_Discovery_Procedure_v2` (ESD `9QAWC000000C8mb4AC`), `contextDefinitions=["SalesTransactionContextExt_v2"]`, active V1 ESV `9QMWC000000227N4AQ`. The two older discovery procedures bind to the **v1** context `SalesTransactionContextExt` (`11OWC0000012HsD2AU`) and do NOT pair with the v2 pricing procedure.
- The v2 discovery procedure's 3 elements: **AssetDiscovery** (decision table `Asset Action Source Entries V2`, `0lDa50000007BJhEAM`; outputs `ContributorUnitPrice<-NetUnitPrice`, `ContributorTotalPrice<-TotalPrice`, `ContributorListPrice<-ListPrice`), **FetchPricingRules** (decision table `Derived Pricing Entries`, `0lDa50000007BI5EAM`; keyed on `IsDerived/PBE/PSM/Product`; outputs `ContributorProduct/ContributorScope/ContributorSource/Contributor`), **MapProduct** (thin/native: `IsRealTime=false`, no decision table).

**Map Products (PBEDP) mappings (V2/V5 probes) — for derived RRM PBE `01uWC000006XPPBYA4`:**
| PBEDP | Derived ProductId | Contributing (SOURCE) ProductId | Scope | Source | Formula |
|---|---|---|---|---|---|
| `182WC000000HNcwYAG` | `01tWC00000DD1buYAD` RRM (PIA-PIA-RRM-PIAM) | `01tWC00000DD1btYAD` **LICENSE** (PIA-PIA-NRPS-PIAP) | Both | Product | UnitPrice |
| `182WC000000HNcvYAG` (PBE `01uWC000006XPNZYA4`) | RRM | LICENSE PIAP | Both | Product | UnitPrice |
| `182WC000000FN2tYAG` (PBE `01uWC000005wsbVYAQ`) | RRM | LICENSE PIAP | Both | Product | UnitPrice |

- **All RRM-derived rows map the contributor to the perpetual LICENSE `01tWC00000DD1btYAD`.** The owned **RNM new-maintenance** product **PIAMBK `01tWC00000DD1bsYAD` is a contributor for NOTHING** (0 rows where `ContributingProductId=PIAMBK`). The only PBEDP touching PIAMBK (`182WC000000FN26YAG`) has PIAMBK as the DERIVED side, also contributed by the license.

**ContributorScope (V3 probe):** Not hard-coded. The `DerivedProductsRenewals` element (the only `actionType=DerivedPricing` element, `parentStep=DerivedProductsNativePull`, the **only** element that outputs `NetUnitPrice`) takes `ContributingScope<-ContributorScope` as a **context Parameter** and carries a dedicated **non-transactional channel** `Non-TransactionalListPrice<-ContributorListPrice` alongside `TransactionalListPrice<-ListPrice`. So the element **admits asset (non-transactional) contributor lookups** — there is nothing to relax at the element level.

**AssetActionSource / assets (V4/V5 probes):**
- Control RRM asset `02iWC000008GKPaYAO` (PIA-PIA-RRM-PIAM, Price 60.64, acct **Nir DPP Test 2** `001WC00000kZKNxYAO`): AA `4nLWC00000319M62AI` (Generate/Initial Sale), **AAS `4nMWC0000044n9W2AQ` Subtotal/NetUnitPrice=60.64 on the derived PBE `01uWC000006XPPBYA4`**.
- Canary RNM asset `02iWC000008DmS1YAK` (PIA-PIA-RNM-PIAMBK, Price 62.48): AA `4nLWC0000030EVt2AM` (Initial Sale), **AAS `4nMWC0000043rof2AA` Subtotal/NetUnitPrice=62.48**. → **The RNM asset is NOT missing an AAS** (premise refuted); AAS presence is not the differentiator.
- Asset-level renewal-intent fields (`RenewalTerm`, `PricingSource`, `UnitPriceUplift`, `DoesAutomaticallyRenew`) are **null/false on all three assets, including the working control** — so `Asset.PricingSource=LastTransaction` is **not** the live mechanism.
- **Only one RRM asset exists org-wide** (the control's). The canary account `001WC00000kTYyNYAW` owns PIAP (301.75) + PIAMBK (62.48) and **no RRM asset**.

**Renewal flow (V6 probe):** `Fortra_Create_Renewal_Quote` overrides `quotingAI__createRenewalQuote` and delegates to **platform `initiateRenewal`** (`renewAssetIds<-assetIds`, `renewOutputType=Quote`), which auto-mints the Renew QuoteAction + SourceAssetId. **No flow hand-creates QuoteActions** (zero `recordCreates` on QuoteAction anywhere; `Fortra_RCA_Renewal_Enhancement` only reads them). Org QuoteActions: Renew 53 / No Change 64 / Amend 8 / Cancel 5. Of the 53 Renew, exactly **1 SourceAsset is RRM (valid), 1 is RNM/PIAMBK (the $0 mismatch)**.

## The exact DELTA between the 67.38 control and the failing lines (the ground-truth template)

The control line `0QLWC000003dEW24AM` (quote 00781084 / `0Q0WC00000382MH0AY`) and the fossil line `0QLWC000003e2Sn4AI` (quote 00781109 / `0Q0WC0000038aXd0AI`) are **byte-for-byte identical** on every product/config attribute: same Product2 RRM `01tWC00000DD1buYAD`, same derived PBE `01uWC000006XPPBYA4` (IsDerived, ListPrice=0), same `UnitPrice=67.38`, Qty 1, both `Quote_Type__c=Renewal`. **Map Products, context, and element wiring are identical — they are NOT the delta.**

The delta is **two facts about the contributor**, both present on the control and both absent on the fossil:
1. **A `QuoteAction(Type='Renew')` exists.** Control: `7ocWC00000u7yf8YAA`, SourceAsset `02iWC000008GKPaYAO`. Fossil: **0 QuoteActions** → the per-line context value `SalesTransactionActionType=Renew` never materializes.
2. **The SourceAsset is an RRM asset (product = the derived line) with an AAS on the derived PBE.** Control SourceAsset is itself PIA-PIA-RRM-PIAM with AAS carrying LTP 60.64 on PBE `01uWC000006XPPBYA4`.

**Per-line tell (V4):** NetUnitPrice on these lines is committed by the custom Assignment element **`COLAUpliftonRenewalNet`** (assigns `COLACalculatedPrice__c → NetUnitPrice`), gated by filter **`COLAUpliftonRenewal`** which requires `SalesTransactionActionType IsNotNull AND = 'Renew'`, `ItemPricingSource=LastTransaction`, and `COLA_Uplift_Percent__c IsNotNull`.
- Control line: Net=67.38, `COLACalculatedPrice__c=67.38`, `COLA_Uplift_Percent__c=7.85`, `Pre_COLA_Price__c=60.64`, `COLA_Source__c=CMDT Lookup` → **element fired**.
- Fossil line: Net=**60.64**, `COLACalculatedPrice__c=67.38` (identical compute), but `Pre_COLA_Price__c=null`, `COLA_Source__c=null` → **element never fired** (no QuoteAction ⇒ `SalesTransactionActionType` null ⇒ gate fails ⇒ persisted 60.64 fossil survives).

**Arithmetic check (V4):** 67.38 ≠ 60.64×1.0785 (=65.40). 67.38 / 1.0785 = **62.48 = the RNM/PIAMBK asset price**. So the correct COLA base is the owned new-maintenance asset (62.48), uplifted 7.85% → 67.38; the 60.64 is the prior-renewal fossil, not the base.

## Why each population fails (60.64 no-QA / $0 wrong-asset) in terms of the VERIFIED config

- **60.64 fossil (canary, quote `0Q0WC0000038aXd0AI`):** The quote has **zero QuoteActions**, because the account owns only RNM+perpetual and **no RRM asset** to feed `renewAssetIds`. No QuoteAction ⇒ native discovery (`DerivedProductsNativePull`) has no SourceAsset to surface ⇒ context `SalesTransactionActionType` is null ⇒ the `COLAUpliftonRenewal` gate fails / `DerivedProductsRenewals` does not write ⇒ the persisted 60.64 line-birth value is retained. **This is a renewal-flow/data problem (no Renew QuoteAction), not a config problem.**
- **$0 wrong-product:** A Renew QuoteAction exists but its `SourceAssetId` points at the **RNM/PIAMBK** asset, whose Product2 (`01tWC00000DD1bsYAD`) ≠ the derived RRM line's Product2 (`01tWC00000DD1buYAD`) and which is **mapped as a contributor for nothing** in PBEDP. The contributor cannot resolve to the RRM derived product ⇒ no contributing net ⇒ $0. **This is a Map-Products (PBEDP) mismatch.**
- **67.38 control (works):** Renew QuoteAction → RRM SourceAsset (product = derived line) → AAS LTP on the derived PBE → contributor resolves → COLA uplift fires → Net committed = 67.38. Note (V5 caveat): the control resolves via an **asset whose product equals the derived RRM product itself**, NOT via the PBEDP-declared contributing product (which is the license PIAP). The working reference does **not** exercise the license→RRM mapping.

## THE SUPPORTED FIX — ranked, concrete, least-invasive first

> Cross-cutting principle (all probes agree): **do NOT write `NetUnitPrice` directly and do NOT edit the `DerivedProductsRenewals` element.** Net must stay an engine output; the fix repairs the **contributor inputs**.

**Fix 1 (least invasive, addresses the $0 wrong-product population) — Map Products: add a PBEDP row mapping owned RNM → derived RRM.**
- **What changes (DATA/config):** Add a `PriceBookEntryDerivedPrice` row on the derived RRM PBE `01uWC000006XPPBYA4` with `ProductId=01tWC00000DD1buYAD` (RRM) and **`ContributingProductId=01tWC00000DD1bsYAD` (RNM/PIAMBK)**, `DerivedPricingScope=Both`, `PricingSource=Product`, `Formula=UnitPrice` — mirroring the existing license rows.
- **Why it resolves the contributor:** A customer who owns an RNM (new-maintenance) asset but no RRM asset would then have that owned asset match the derived RRM line through Map Products, surfacing it as the contributor (its AAS LTP is the live 62.48). Today PIAMBK maps to nothing, which is exactly why a Renew QuoteAction pointed at the RNM asset yields $0.
- **Blast radius:** Adds a **second** contributor to the RRM derived product (license PIAP already mapped). Unverified whether two contributors change which last-negotiated price the engine selects. Scope it via `DerivedPricingScope`/effective dates; affects only RRM-derived lines.
- **Type:** Config/data. **Needs a live reprice (FINEST) test** to confirm (a) runtime match is by `ContributingProductId` equality so the owned RNM asset resolves, and (b) the AAS on `02iWC000008DmS1YAK` carries a non-zero LTP so the result is the uplifted net, not another $0.

**Fix 2 (addresses the 60.64-fossil population) — ensure renewal-maintenance lines are created via initiate-renewal so a Renew QuoteAction + SourceAsset exists.**
- **What changes (DATA/flow-data, not flow code):** The fossil line was added to a quote with **no QuoteAction**. The renewal flow itself is correct (`Fortra_Create_Renewal_Quote → platform initiateRenewal`); the gap is **upstream asset selection** feeding `renewAssetIds`. Route the renewal-maintenance line through initiate-renewal off an asset that yields a Renew QuoteAction, OR fix the upstream selection so the maintenance renewal emits a Renew QuoteAction.
- **Why it resolves the contributor:** Replicates the control: a Renew QuoteAction materializes `SalesTransactionActionType=Renew`, the `COLAUpliftonRenewal` gate passes, and `COLAUpliftonRenewalNet` commits the uplifted net (replacing the 60.64 fossil). This is **Official-RCA Option C**.
- **Blast radius:** Process/data only; no metadata change. Affects how renewal-maint lines are seeded.
- **Type:** Data/process (no code change to the flow). **Needs confirmation** of why the canary RRM line was added without a Renew QuoteAction (manual add vs out-of-band build) and whether initiate-renewal in this org auto-creates the QuoteAction for maintenance assets.

**Fix 3 (do NOT pursue) — asset/AAS data fixes or `Asset.PricingSource` edits.**
- **Refuted by V4/V5:** Both control and canary assets are lifecycle-clean with valid AAS; asset-level renewal fields are null even on the working control. There is no missing AAS to seed and no `PricingSource` to set.

**Reconciliation note (important for the owner):** V1/V2/V6 frame the $0 case as a Map-Products gap (Fix 1); V4/V5 prove the **live 67.38 path commits Net via the custom COLA Assignment**, gated by the QuoteAction-derived `SalesTransactionActionType`, and the control's contributor is an **RRM-asset-as-itself** (not the license, not RNM). These are not contradictory: **Fix 2 (QuoteAction) is the verified cure for the 60.64-fossil case; Fix 1 (RNM→RRM PBEDP) is the candidate cure for the $0 wrong-product case** — but Fix 1 is **not yet exercised by any working reference instance** and must be proven by a live reprice before deploy.

## Remaining unknowns / next verification

1. **FINEST reprice trace (canary)** — confirm `SalesTransactionActionType` is null with no QuoteAction (currently inferred from null `Pre_COLA_Price__c`/`COLA_Source__c`), and that seeding a Renew QuoteAction moves the line off 60.64.
2. **FINEST reprice trace ($0 repro)** — build a quote whose Renew QuoteAction `SourceAssetId` = an RNM/PIAMBK asset; confirm $0 mechanism is Map-Products mismatch and that **Fix 1 yields the uplifted net (62.48×1.0785≈67.38), not another $0**. Verify the RNM asset's AAS LTP value.
3. **Which lookup path actually fires for the control** — RRM-asset-as-itself (Asset Discovery, `DerivedPricingScope=Both`) vs the PBEDP license→RRM mapping. The data shows the control does **not** use the declared license contributor; a trace is needed before relying on PBEDP semantics for Fix 1.
4. **What stamps `COLACalculatedPrice__c=67.38` pre-procedure** (identical on control and canary despite no QuoteAction) — likely a prehook/`COLAUpliftHandler` keyed off `Quote_Type__c=Renewal`; confirm it cannot fallback-stamp NetUnitPrice.
5. **PricingActionParameters context mismatch** — the per-object runtime bindings point Quote/Order to **v1** `SalesTransactionContextExt`, while both procedures declare **v2**. Confirm which context the engine instantiates at reprice; a v1/v2 mismatch would be a second-order config defect.
6. **Two-contributor behavior** — adding RNM→RRM alongside the existing license→RRM row: confirm the engine's selection rule and that Subtotal/TotalLineAmount are not regressed.
7. **`ContributorScope` runtime value** for the renewal node of `SalesTransactionContextExt_v2` (transactional vs non-transactional) — not visible in metadata; needs a trace to confirm asset-scope lookups are admitted for a maintenance-only renewal with no license line on the quote.