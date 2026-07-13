All queries complete. Here is my focused report.

---

# ANGLE: Catalog + Selling-Model Model Underpinning Renewals (FortraUAT, read-only)

All figures below are live `sf data query` counts against FortraUAT (`fortra--uat`, API 67) on 2026-07-09.

## 1. The catalog model — maintenance is NOT browsable

Renewal Maintenance is **invisible to the catalog**. This is the single most important structural fact for re-architecture.

| Product type | In a browsable `ProductCategory` (via `ProductCategoryProduct`) | Active total |
|---|---|---|
| Subscription | 948 | 1,767 |
| Perpetual | 851 | 1,521 |
| Services | 278 | 533 |
| **New Maintenance (RNM)** | **1** | 1,683 |
| **Renewal Maintenance (RRM)** | **0** | 1,711 |

Catalogs (`ProductCatalog`): `Cyber` (Sales), `Tech` (Sales), + a test catalog; 188 `ProductCategory` rows. **Zero of 1,711 active RRM and effectively zero of 1,683 RNM are attached to any category.** Maintenance products therefore cannot be reached by catalog browse — they only enter a quote via renewal automation (`Fortra_Create_Renewal_Quote`) or bundle/config attachment. Any re-architecture that expects a rep to "add a renewal maintenance line" from a browsable catalog is fighting the current data model.

## 2. Selling-model catalog (`ProductSellingModel`)

9 models exist; only 5 are Active. **`DoesAutoRenewAssetByDefault = false` on ALL of them, including `Term Based - Annual`.**

- `One Time` — OneTime — Active
- `Term Based - Annual / Monthly / Quarterly / Semi-Annual` — TermDefined — Active
- `Evergreen - Monthly/Quarterly/Semi-Annual/Yearly` — Evergreen — **all Inactive** (confirms Fortra has no evergreen model)

Implication: no selling model natively auto-renews an asset; renewal is driven **entirely** by the custom flow, not by the platform. Official semantics confirmed: `SellingModelType ∈ {OneTime, TermDefined, Evergreen}`; a product may have several `ProductSellingModelOption`s but **exactly one `IsDefault`**, and that default governs pricing/lifecycle ([ProductSellingModelOption, RLM Dev Guide](https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_productsellingmodeloption.htm)).

## 3. RNM/RRM pairing mechanism — convention only, no first-class link

Pairing is **purely a ProductCode naming convention**, not a data relationship:
- Pattern: `<Cat>-<Product>-RNM-<sku>NE` ↔ `<Cat>-<Product>-RRM-<sku>RE` (first two segments identical, `RNM`↔`RRM` token swapped, suffix `NE`→`RE`). Example pair: `BI-ABS-RNM-ABSTNE` ↔ `BI-ABS-RRM-ABSTRE`.
- Token consistency is ~99.8%: New Maint uses `-RNM-` (1,681/1,683); Renewal Maint uses `-RRM-` (1,708/1,711). Anomalies: 2 RRM use `-MAINT-RNW-` (`CS-*-[FORTRA-DEMO]`), 1 RRM carries an `-RNM-` token.
- **There is no product-to-product mapping field.** The paired SKUs merely share `Solution_Category__c` / `Solution_Group__c` / `Solution__c` (the `BI-ABS` pair shares Cat=`Business Intelligence`, Grp=`Power`, Sol=`Abstract` identically). But those attributes are far too coarse to be a 1:1 key: among active RRM there are only **18** distinct `Solution_Category__c`, **5** `Solution_Group__c`, **138** `Solution__c` (≈12 RRM per solution). The runtime asset→line source resolution keys on the coarse `account|Solution_Category__c`; there is no attribute that uniquely resolves one RNM to its one RRM. **A re-model needs an explicit pair/lineage field.**

## 4. Selling-model hygiene — the "100 missing TermDefined" gap, quantified

PSMO cross-tab (product type × `SellingModelType` × `IsDefault`), key rows:

| Product type | Default OneTime | Non-default OneTime | Default TermDefined | Non-default TermDefined |
|---|---|---|---|---|
| **Renewal Maintenance** | **99** | 116 | 1,610 | 1 |
| New Maintenance | 1,642 | 3 | 39 | 0 |
| Subscription | 5 | 3 | 3,142 | 2 |
| Perpetual | 1,518 | 0 | 3 | 86 |

Product-level resolution (active only):
- **Exactly 100 active RRM products have NO TermDefined selling model** → cannot renew via the native path. Composition: **91 are `-TECH` child SKUs**, 9 are non-TECH — of which **7 are real sellable Tripwire/FIM renewal SKUs** (`FIM-FIM-RRM-TIARM`, `-TIVTDCRM`, `-VM18RE`, `FIM-FML-RRM-TSAURM`, `-TVCRM`, `-TVFFRM`, `-TVFNDRM`) and 2 are FORTRA-DEMO. **2 of the 100 have no PSMO at all.**
- 1,611 active RRM do have a TermDefined option (1,611 + 100 = 1,711 ✓).
- Among the 754 active `-TECH` RRM, 663 correctly default TermDefined but **91 default OneTime** — that's where 91 of the 100 gaps live.
- **39 RNM products default to TermDefined** (should be OneTime for new business) — a smaller inverse inconsistency.
- Note: `Product2.Product_Selling_Model_Type__c` (denormalized string) is **stale/unreliable** — it reads `None` for every `-TECH` SKU even though those SKUs have real PSMOs; do not trust it, join to PSMO.

## 5. Pricebook structure

6 pricebooks; two are the operative ones:
- **`Fortra Price Book`** (active quoting book): 83,437 PBE = 81,548 non-derived + **1,889 derived**.
- **`Standard Price Book`** (active): 91,132 PBE (1,561 derived).
- Inactive/legacy: `Cyber Legacy Products`, `Cyber New Products`, `Fortra Derived Pricing` (all inactive), + a test book.

Currency: **10 currencies** in the Fortra book — USD 9,592, and GBP/EUR/CHF/ILS/ARS/AUD/JPY/NZD/CAD **each exactly 8,205**. USD carries ~1,387 more entries than every foreign currency (foreign-currency coverage gap concentrated in Subscription/Perpetual). **RRM currency coverage is complete**: 0 active RRM lack a Fortra-book PBE, 0 lack USD, 0 lack EUR — every RRM is priceable in all 10 currencies.

## 6. Derived pricing (`IsDerived` PBE + `PriceBookEntryDerivedPrice`) — the native mechanism is ~80% unwired and USD-only

- All **1,889 derived PBE in the Fortra book are maintenance** (950 RRM + 939 RNM) and **all are USD** (0 foreign-currency derived PBE). By selling model: 1,041 OneTime + 848 TermDefined.
- **Every one of the 1,887 maintenance products carrying a derived PBE ALSO carries non-derived PBE** in the same book (the "two-book" pattern): USD/one-model is `IsDerived=true`, the other 9 currencies are explicitly priced (`IsDerived=false`). So the "derived marker" is per-currency-inconsistent by design.
- **`PriceBookEntryDerivedPrice` is sparsely populated: only 372 rows total, and all 372 are USD.** Verified linkage: `PBEDP.PricebookEntryId` → the DERIVED maintenance PBE; `ContributingProductId` → the source license. Contributor map:
  - RRM ← Perpetual: 173; RNM ← Perpetual: 173; RNM ← Subscription: 21; RRM ← Subscription: 4; 1 orphan (`None←None`).
  - `Formula` values are `UnitPrice` / `ListPrice` (maintenance derives off the license's unit/list price); `DerivedPricingScope = Both` on all; `PricingSource = Product`. `PricebookId` is unstamped (null) on 198/372 rows (minor inconsistency; `PricebookEntryId` is always populated).
- **Reconciliation gap (headline):** of the 1,889 derived maintenance PBE in the Fortra book, **only 368 (19.5%) have a PBEDP contributor; 1,521 (80.5%) are marked `IsDerived=true` but have no contributor mapping** → they resolve to null/$0 through the native RLM derived-price feature. In practice this means Fortra does **not** rely on native `PriceBookEntryDerivedPrice`; `IsDerived=true` is used as a **routing flag** into the custom pricing procedure (`Rev_Mgmt_Default_Pricing_Procedure` V23, `DerivedProductsNonRenewal` filter), which computes the maintenance price itself. The native contributor object is effectively abandoned (19.5% populated, USD-only). Official object confirms this is the intended native path ([PriceBookEntryDerivedPrice, RLM Dev Guide](https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_pricebookentryderivedprice.htm)).

## 7. Re-architecture implications (from this angle)

1. **Two-catalog RNM/RRM split with no first-class pairing** is the root structural debt: 3,394 maintenance products, paired only by string convention + coarse `Solution_*` attributes. A single maintenance product with a proper renewable selling model, or an explicit pair-lineage field, would collapse this.
2. **Maintenance is un-browsable** (0 category attachment) — the model presumes automation-only insertion; any UI-add path must be built or the catalog must be populated.
3. **Selling-model defaults are the renewal fault line**: 100 active RRM (incl. 7 real FIM SKUs) can't renew natively for lack of a TermDefined default; `DoesAutoRenewAssetByDefault=false` everywhere means renewal is 100% custom-flow-driven.
4. **Derived pricing is USD-only and 80% unwired natively** — the platform feature is bypassed by custom procedure logic; a re-model should decide to either fully populate `PriceBookEntryDerivedPrice` (all currencies, all maintenance) or formally own derivation in the procedure and stop marking PBE `IsDerived` as a mere flag.
5. **Foreign-currency derived pricing has zero data** (0 non-USD derived PBE, 0 non-USD PBEDP) — corroborates the SC-3384 multi-currency maintenance defects from the data layer.