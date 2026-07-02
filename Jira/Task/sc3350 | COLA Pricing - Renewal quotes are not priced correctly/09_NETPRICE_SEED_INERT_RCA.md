# SC-3350 — Why the V11 NetUnitPrice seed is inert (CRACKED) + the multi-quote reprice evidence

**2026-06-10 (late session) · owner Liam · org FortraUAT · this advances §5 of [08_SESSION_CONTEXT_AND_HANDOFF.md](08_SESSION_CONTEXT_AND_HANDOFF.md)
from "cause unknown" → root-caused.** Method: with the user's debug TraceFlag live, repriced 3 renewal quotes
via the **Place Sales Transaction** API and diffed the full pricing logs against the active V11 metadata
(5‑agent verification workflow, 423k tokens, every claim evidence‑cited).

---

## 0. Reprice mechanism (important operational finding)
- The **deprecated Place Quote** REST API (`/commerce/quotes/actions/place`, v60) rejects every one of these
  renewal reprices with `INVALID_FIELD_FOR_INSERT_UPDATE` — **even working‑net quotes** → it's an API‑path
  artifact, NOT the bug. Don't use it.
- The **Place Sales Transaction** API (`/connect/rev/sales-transaction/actions/place`, **v67**,
  `pricingPref:Force`, bare Quote PATCH) **works**, reprices all lines, and emits a full ~2 MB pricing log
  under the user's TraceFlag. This is the headless reprice harness (bodies in `Data/sc3350/reprice-logs/`).

## 1. The three reprices (all under active V11)
| Quote | Line | UnitPrice (COLA'd, correct) | NetUnitPrice | What it proves |
|---|---|---|---|---|
| **003671t** (broken) | Abstract / beSECURE | 4697.946 / 929.25 | **0 / 0** | COLA from asset; net never set |
| **035X6T** (looks OK) | Abstract / beSECURE | 49.611 / 0 | **49.611 / 0** | Abstract net is **stale**; beSECURE has the SAME bug |
| **035LA9** (looks OK) | Automate | **2674.85** (recomputed this run) | **2400** (frozen) | **decisive:** COLA recomputed the list side to 2674.85, but net stayed frozen at the stale stored 2400 |

## 2. Root cause (high confidence, multi‑agent + log + metadata)
**`NetUnitPrice` is an engine‑derived net‑pricing output that no step establishes for a non‑derived,
`SellingModelType=null`, `ItemPricingSource=LastTransaction`, `Renew` line. It enters the pricing context as
the *stored QLI value* and is preserved.** Lines that "work" merely carry a **stale non‑zero stored net**
(proven by 035LA9: list recomputed to 2674.85 this run, net frozen at 2400). Fresh renewal lines carry 0 and
stay 0 → GrandTotal $0.

Every one of the 17 NetUnitPrice‑writers is gated out for this line:
- `DerivedPricing*` (incl. `DerivedPricingRenewals`, the `(Base−priors)×(1+COLA%)` formula) → need
  `DerivedPricingAttribute=true` → **skip** (our line is non‑derived).
- `SubscriptionPricing*` → need `SellingModelType ∈ {TermDefined, Evergreen}`; the only one matching `null`
  (`SubscriptionPricing78`) writes **InputUnitPrice**, not NetUnitPrice → **skip**.
- The canonical `InputUnitPrice→NetUnitPrice` seed (`QuantityPrice49`, an **AssignmentElement**) was gated
  `ItemPricingSource NotEquals 'LastTransaction'` **and was removed entirely from active V11**.
- Discount / proration / regional writers only apply a **delta** to an existing net of 0 → can't create one.

## 3. Why the seed (`SeedNetUnitPriceRenewal`) is inert — the precise mechanism
- The seed's container gate **passes** for our line — *proven*: its ListContainer2 sibling
  `COLAUpliftonRenewal21` (AssignmentElement) successfully wrote **InputUnitPrice=929.25/4697.946** in the same
  container, and `COLACalculatedPrice__c=929.25` is in context the whole time. So it's **not** a gate‑skip and
  **not** a timing problem. (hypotheses a & d refuted)
- No downstream step overwrites it — no `seq>9` step writes NetUnitPrice for this line. (hypothesis c refuted)
- **The decisive asymmetry:** in *the very same container* (ListContainer2), an `AssignmentElement` writing
  **InputUnitPrice persists**, but a write to **NetUnitPrice (Assignment OR FormulaBasedPricing) does not**.
  → `NetUnitPrice` is only committed by the engine's **native net‑pricing path** (PricingSettings / Derived /
  Subscription / the removed renewal‑excluded seed). A custom write to NetUnitPrice from the COLA ListGroup is
  evaluated but **not flushed to the line**. This is why **all 5 in‑ListContainer2 attempts (§4d of doc 08)
  failed** regardless of element type or formula — they were all in the wrong scope.

> Residual: the Apex log is a pricing‑engine *boundary* log (only `RLM_PRICING_BEGIN/END` + context‑snapshot
> maps; individual expression‑set step names never appear). The scope conclusion is proven *indirectly* by the
> in‑container InputUnitPrice‑works / NetUnitPrice‑fails asymmetry. The only 100% confirmation is a live test of
> the corrected fix (harness is ready).

## 4. This is NOT a COLA bug
It's the **$0‑net renewal gap** (SC‑3345/SC‑3347 family): any non‑derived `SellingModelType=null` LastTransaction
renewal line has no net‑seed. COLA only surfaced it. The companion beSECURE line in the "working" 035X6T quote
has Net=0 too — same defect, unflagged because the Abstract line's stale net keeps GrandTotal non‑zero.

## 5. Fix direction (the in‑ListContainer2 seed is a proven dead end)
1. **In‑procedure (needs one live test):** add a renewal‑gated net seed in the scope the engine *commits* net
   for non‑derived lines (NOT the COLA ListGroup), set `NetUnitPrice := InputUnitPrice` (InputUnitPrice is
   already COLA'd by ListContainer2 at seq 9), gated `ItemPricingSource Equals 'LastTransaction' AND
   DerivedPricingAttribute=false AND (NetUnitPrice IsNull OR =0)`. Mirror the structure of the removed
   `QuantityPrice49` AssignmentElement. **The right container must be confirmed empirically** — that's the next
   step (reprice 003671t, check Net flips 0→4697.946).
2. **Native (Salesforce‑recommended, bigger change):** `Asset.PricingSource = LastTransaction` + a
   `PriceRevisionPolicy`/`UnitPriceUplift`, with the renewal flow doing a real reprice. Avoids procedure surgery.
3. Coordinate with Marc DeBrey (shared active procedure); never hot‑edit the active version.

## 5b. LIVE-TEST CONCLUSION (the in-procedure seed is a *proven* dead end)
After re-activation, a controlled trace of a **non-renewal** line (`377Cj`, beSECURE Premise) showed exactly
how net is committed: in the single **line-pricing engine pass**, `NetUnitPrice` is seeded to **ListPrice
(824)** then discounted to 593.28. That seed is the platform **`PricingSetting`** element (`actionType=
PricingSettings`, top‑level **seq 1**, outputs `NetUnitPrice` + `price_water_fall` + `Subtotal`,
`V11_active.xml:3695‑3786`). **`NetUnitPrice` is backed by the engine `price_water_fall` that PricingSetting
owns.** A `FormulaBasedPricing`/`AssignmentElement` write to `NetUnitPrice` from the COLA ListGroup
(ListContainer2) updates only the context variable, **not the waterfall**, so the committed net is unchanged —
which is *why all 6 in‑ListContainer2 attempts failed regardless of element type or formula.* (Contrast:
`InputUnitPrice` is **not** waterfall‑backed, so the sibling AssignmentElement's InputUnitPrice write *does*
stick.)

**Why net = 0 for these renewals (full chain):** the line prices `ItemPricingSource=LastTransaction` →
`PricingSetting` sources net from the **prior transaction/asset**, but `Asset.PricingSource = null` and the
renewable assets carry **no net** (`02iWC000008BTEzYAO/F0` Price=4356/875, PricingSource=null) → waterfall net
= **0**. COLA correctly sets the *list* side (InputUnitPrice=4697.946) but cannot touch the waterfall net.

**The procedure already HAS a renewal‑net design that commits net — and COLA bypasses it.**
`DerivedPricingRenewals` (`(Base_Price__c − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) ×
(1+COLA%/100)` → NetUnitPrice, in the **derived pass**) is the engine‑sanctioned renewal‑net mechanism, and it
**does** commit net — but only for lines that are **derived** (`DerivedPricingAttribute=true`) with
**`Base_Price__c` populated**. Our COLA renewal lines are **non‑derived** and have `Base_Price__c=null,
Source_List_Price__c=null` → they hit neither PricingSetting (→0) nor the derived formula.

### Viable fixes (the seed approach cannot work)
- **Option B (existing design — but NOT field-testable, confirmed):** `DerivedPricingRenewals`' container gate
  requires `DerivedPricingAttribute=true AND AttributeDefinitionCode='MDT'` (`V11_active.xml:1698‑1718`), and
  `DerivedPricingAttribute` is a **platform‑derived** context attribute (inherited from std
  `SalesTransactionItem`, `SalesTransactionContextExt_v2.contextDefinition:663‑665`), **not a settable QLI
  field**. **LIVE TEST (data‑only, reverted):** set `Base_Price__c`=4356/875 on 003671t + Force reprice →
  **NetUnitPrice stayed 0** (line never enters the MDT‑derived pass). So Option B requires reconfiguring the
  COLA products as **MDT maintenance‑derived** — a large blast‑radius change that would alter their entire
  pricing model (and likely break the correct list‑side COLA). **Not a quick fix.**
- **Option A (native / data):** carry the prior **net** onto the renewable Asset / set `Asset.PricingSource`
  so `PricingSetting` seeds a non‑zero net base, then COLA uplifts it (native `PriceRevisionPolicy`/uplift).
- **Not viable:** any `FormulaBasedPricing`/`AssignmentElement` seed to `NetUnitPrice` in a regular ListGroup
  (the V11 `SeedNetUnitPriceRenewal` and all 5 prior variants) — proven not to commit.

The inert `SeedNetUnitPriceRenewal` in V11 is **harmless** (Net was 0 before and after) but should be removed
when the procedure is next cleaned, since it does nothing.

## 5c. ✅ FIX FOUND & VALIDATED LIVE — prehook seeds NetUnitPrice (2026-06-11 ~01:00Z)
The one remaining engine-level lever **worked**: the COLA **prehook** (`COLAUpliftPrehook`, a
`SignalingApexProcessor` that runs *inside* the engine) writes `NetUnitPrice` to the `SalesTransactionItem`
context in its **own isolated `updateContextAttributes` batch** — and it **commits** (it is NOT overwritten by
`PricingSettings`). The prehook runs at a point where its `NetUnitPrice` write seeds the net waterfall.

**Live proof (003671t):** Net `{0.0, 0.0} → {929.25, 4697.95}`; **Quote GrandTotal $0 → 5627.2**; debug log
`SC-3350 submitting 2 NetUnitPrice seed updates (isolated batch)` → `Update result {isSuccess=true}` (no poison).
Validated across lines: 365ph Automate `0 → 2674.85`.

**Implementation (in `COLAUpliftPrehook`):**
- `buildNetUnitPriceUpdate(itemWrapper, colaPrice)` builds a 1-attribute node update (`NetUnitPrice = colaPrice`).
- Collected in `pendingNetUnitPriceUpdates` during `buildLineItemUpdates`, submitted as a **separate batch** in
  the caller (so if `NetUnitPrice` ever lacked a hydration mapping and poisoned, the COLA field writes survive).
- **Guard (production-safe):** only seeds when the **stored** `NetUnitPrice` is null/≤0 — added `NetUnitPrice` to
  the renewal SOQL and gated on `renewalQli.NetUnitPrice`. Validated: 003671t (stored non-zero) **preserved**;
  365ph (stored 0) **seeded**. So already-computed / discounted nets are never clobbered.

**Follow-up items — resolved 2026-06-11 (the three "fix it" asks):**
1. **Discounted renewals — investigated, NO code change.** The renewable Asset's authoritative prior value is
   `Price`/`TotalLifecycleAmount` (035LA9 = 2435); `CurrentAmount=0`, `ARR=null` — there is **no asset-level
   discount data** (the "2400" was a stale/one-off quote value, never persisted). So `net = Asset.Price ×
   (1+COLA%)` already uses the correct prior base, and the guard preserves any manually-applied net.
2. **Test coverage — ADDED to `COLAUpliftTest`** (3 tests): `buildNetUnitPriceUpdate` (direct + null/empty
   guards), `NetSeed_SeedsZeroAndGuardsNonZero` (seed when stored net 0; guard skip when non-zero, via JSON
   round-trip to inject the non-updateable `NetUnitPrice`), `NetSeed_ListPriceFallback`. **54/54 pass, prehook
   coverage 76%.**
3. **Null-`Asset.Price` lines — FIXED.** When `SourceAsset.Price` is null/≤0, COLA now **falls back to the
   line's `ListPrice`** (null-safe via `getPopulatedFieldsAsMap`). Genuinely price-less lines (asset=0 *and*
   list=0, e.g. 035X6T beSECURE) correctly stay $0 — bad data, not a pricing gap.

**Remaining (not blocking the UAT fix):**
- **Prod packaging:** `COLAUpliftPrehook`/`COLAUpliftTest` are **live-only**; back-fill into `force-app` before promotion.
- **Test artifact:** the *un-guarded* first deploy clobbered 035LA9 Automate net `2400 → 2674.85` before the guard was added (test quote; 2674.85 = full COLA price).
- Backups: original class at `Data/sc3350/prehook-fix-backup/`; modified (deployed) at `Data/sc3350/prehook-fix/`.

## 6. Artifacts
- Reprice bodies + 3 full pricing logs: `Data/sc3350/reprice-logs/pst_003671t_broken.txt`,
  `pst_035X6T_works.txt`, `pst_035LA9_discount.txt`.
- Live active V11 retrieve: `Data/sc3350/live-v11/V11_active.xml` (+ `V10.xml` for diff).
- Seed = `SeedNetUnitPriceRenewal` (FormulaBasedPricing, ListContainer2 seq 3) at `V11_active.xml:4494‑4558`.
