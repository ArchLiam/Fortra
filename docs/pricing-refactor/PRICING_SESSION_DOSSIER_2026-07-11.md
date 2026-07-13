# RCA Pricing Engine — Session Dossier

**Prepared for the pricing walkthrough · 2026-07-11**
**Author:** Liam Jeong · **Source of truth:** live `Rev_Mgmt_Default_Pricing_Procedure` **V24**, retrieved read-only from **FortraUAT** on 2026-07-10, plus the Apex hook/service layer in `force-app`.

> **How this dossier is grounded.** The repo's serialized copy of the pricing procedure was stale (it showed V20 active). Every procedure detail below was reverse-engineered from a **fresh live retrieve of V24** (137,807-line ExpressionSetDefinition, V24 block = 6,472 lines, 120 steps). Every formula string, filter condition, lookup Id, and field name is quoted from that live metadata or from the actual `.cls` files. Where something is only knowable from org config (e.g. the exact `ProcedurePlanOption` that binds a hook), it is called out as such rather than guessed.

---

## How to use this in the meeting (agenda → section map)

| Agenda item | Where to look |
|---|---|
| **Prehook modifications** (code, context elements, context mappings, reason) | **Part 1 — Hooks.** Each hook has: Purpose · Modifications (with reasons) · Context elements (read/write table) · Context mappings & registration · Risks. |
| **Pricing procedure, element by element** (purpose, filter conditions, assignment/custom/formula elements, modifications) | **Part 2 — Procedure walkthrough (V24).** 8 sections following the 43-step waterfall in execution order; each element has purpose, filter, assignment/custom/formula detail, and change provenance. |
| **Fields / Metadata modifications** (what changed and why) | **Part 3 — Fields & Metadata.** |
| Architecture / how it all fits + a consolidated change map | **Part 0 — Architecture & Change Map.** |

---

## Executive summary

**Architecture.** A reprice signal enters through a Flow trigger (`Fortra_Quote_Reprice` / `Fortra_Order_Reprice`), runs the single active RCA pricing procedure **V24** (a ~43-step ExpressionSet waterfall), and is decorated by **nine Apex hooks** — 7 prehooks + 2 posthooks — each implementing `RevSignaling.SignalingApexProcessor`. The hooks are **registered as procedure plugins via org config** (`ProcedurePlanOption` / signal bindings — *not* in the ESD XML or git). Every hook is **fail-open** (downgrades errors to `SUCCESS` so pricing is never blocked) and now emits **D-18 telemetry** on any swallowed error.

**The refactor.** Waves 0–3 of the pricing refactor are complete; Wave 4 is ~85%. Every hook was **thinned into an adapter over a testable `*Calculator`/`*Builder`/`*Resolver` service** (~15+ extracted classes; `ContextTagReader` is the shared context reader). The two duplicate engine clusters were consolidated: **partner margin** onto the deal-aware V2 posthook (D-11) and **COLA** onto a single `COLAUpliftCalculator.resolveTier` (D-13). Hardware/currency tables moved to config-as-code MDT (D-14/D-15), and a **13-scenario golden reprice harness passes 0-delta**.

**Three things to raise first:**
1. 🔴 **Two Active procedure versions.** The org has **both V23 and V24 marked Active** (V24 activated 2026-07-10 02:59; V23 never deactivated) and they are structurally different (~8 KB apart). Confirm V24 is the runtime and **deactivate V23**. Until then, which version prices is ambiguous.
2. 🟠 **Large uncommitted working-tree changes.** `PartnerNetPricePosthook` (~+350 lines) and `CancelLineCreditPosthook` (~+195 lines) plus several calculators have **uncommitted** edits. They need a commit + a golden-gate reprice before they can be trusted as shipped.
3. 🟡 **Owner-gated cleanups:** retire `RenewalMaintenanceFlip` (D-3), decide the currency-change no-op (OQ-2), currency config-as-code (D-21), and cosmetic V24 canvas renames (D-23).

---

## The V24 pricing waterfall at a glance (43 top-level steps, execution order)

Steps run top-to-bottom; `ListGroup` containers run their filter → action children in child order. This is the spine of the Part 2 walkthrough.

| # | Step (name) | Type / actionType | Function |
|---|---|---|---|
| 1 | PricingSetting | PricingSettings | Engine settings |
| 2 | PriceBookEntries | ListPrice | Seed list price / PricebookEntry |
| 3 | PricingEffectiveDates | AssignmentElement | Effective dating |
| 4 | ListContainer | AttributeDiscount | Attribute-based price (contracted) |
| 5 | ListContainer7 | AttributeDiscount | Attribute discount entries (non-contracted) |
| 6 | ListContainer5 | Assignment + Formula | Attribute-value pricing — **Unit Price** mode (+ Net/Base Bridge) |
| 7 | ListContainer6 | Formula | Attribute-value pricing — **Calculated** mode (+ Net/Base Bridge) |
| 8 | ListContainer720 | Assignment + Formula | Attribute-value pricing — **Total Price** mode (+ Net/Base Bridge) |
| 9 | ListContainer25 | BundleDiscount | Bundle-based adjustments |
| 10 | ListContainer28 | VolumeDiscount | Volume-tier discounts |
| 11 | ListContainer4 | AssignmentElement | **Regional services** (country multiplier → list) |
| 12 | ListContainer1 | FormulaBasedPricing | GSA government pricing |
| 13 | SyncInputUnitPriceforDiscountBase | AssignmentElement | Sync `InputUnitPrice` from net |
| 14 | StampContributorBasePreDiscount | Formula + Assignment | **Stamp base / reset net to pre-partner** (D-19, F-07) |
| 15 | DerivedProductsNativePull | DerivedPricing | Pull derived products (renewal vs non-renewal) |
| 16 | ListContainer9 | FormulaBasedPricing | **Derived maintenance net** (SC-3346) |
| 17 | DiscountPercent | FormulaBasedPricing | Discount % |
| 18 | SeedOneTimeNetBeforePartner | FormulaBasedPricing | **Seed one-time net before partner** (SC-3359) |
| 19 | ListContainer3 | ManualDiscount | Partner discount |
| 20 | ListContainer57 | ManualDiscount + Formula | Manual quote-level discounts (amount / percent) |
| 21 | PartnerDiscountDerivedMaintenance | ManualDiscount + Assignment | Partner discount on derived maintenance |
| 22 | ListContainer10 | FormulaBasedPricing | Derived net reset |
| 23 | ListContainer2 | AssignmentElement | **COLA uplift on renewal** (SC-3346/3350/3384) |
| 24 | ListContainer75 | AssignmentElement | Contracted pricing |
| 25 | ListContainer78 | FormulaBasedPricing | Quantity price |
| 26 | ListContainer81 | FormulaBasedPricing | Formula-based line pricing |
| 27 | Evergreen…proration | Proration + Subscription | Evergreen anytime proration + subscription |
| 28–31 | ListContainer88 / 92 / 95 / 98 | Subscription + Assignment | Subscription pricing sub-groups |
| 32–34 | ResetTotal Services/Software/Subscription | FormulaBasedPricing | **K-09 zero-init** of category totals (SC-3345) |
| 35–37 | ListContainer8 ×3 | GroupingAndAggregatePricing | Services / Software / Subscription aggregates |
| 38 | TotalAmount | GroupingAndAggregatePricing | Total amount rollup |
| 39 | FormulaBasedPricing3 | FormulaBasedPricing | Total-level formula |
| 40–41 | AggregatePrice ×2 | GroupingAndAggregatePricing | Grand-total aggregates |
| 42 | ListContainer11 | FormulaBasedPricing | **All-lines null-safe** adjustment |
| 43 | Assignment120 | AssignmentElement | Final assignment |

---

# Part 0 — Architecture & Change Map
## Engine Architecture

**End-to-end flow.** A repricing signal enters through one of two Flow triggers, runs the single active RCA pricing procedure (`Rev_Mgmt_Default_Pricing_Procedure` **V24**, a ~43-step ExpressionSet waterfall), and is decorated by nine Apex hooks registered as procedure plugins via **org config** (`ProcedurePlanOption` / signal bindings — not in the ESD XML or git; the partner prehook is bound on `ProcedurePlanOption 1FYWC0000002W3r4AE`). Every hook implements `RevSignaling.SignalingApexProcessor` with `execute(RevSignaling.TransactionRequest) → RevSignaling.TransactionResponse`, reads/writes the `SalesTransactionContext` through `Context.IndustriesContext.queryTags` / `updateContextAttributes`, is re-entrancy-guarded (`private static Boolean isProcessing`), and **downgrades every error to `TransactionStatus.SUCCESS`** so pricing is never blocked (SDD-mandated; now paired with D-18 telemetry).

```
 Flow trigger layer
   ├─ Fortra_Quote_Reprice           (Quote-scoped reprice)
   ├─ Fortra_Order_Reprice           (Order-scoped reprice)
   └─ Fortra_Quote_Reprice_And_Q2O   (reprice + Quote→Order)
                    │  invokes
                    ▼
 Pricing procedure  Rev_Mgmt_Default_Pricing_Procedure  V24  (~43-step waterfall)
   PREHOOKS (before / mid waterfall)                 in-procedure order: Regional → Partner → COLA
     1. AmendNetCarryPrehook            seeds prior Asset.Price onto Amend lines (net<=0), owns AmendSeedNetUnit/AmendSeedNetTotal
     2. RegionalServicesPricingPrehook  country multiplier → LIST (via RegionalPricingCalculator)
     3. PartnerPricingPrehookV2         Guaranteed-Margin (additive) or Discount model; stamps Pre_Partner_Price__c
     4. COLAUpliftPrehook               renewal COLA uplift tier (via COLAUpliftCalculator.resolveTier)
     5. AttributeVolumePricingPrehook   attribute-volume tier price (via AttributeVolumeCalculator)
     6. HardwareAttributePricingPrehook pGroup × userTier × (1-systemType%) (via HardwarePricingCalculator)
     7. QLDescriptionGeneratorPrehook   line description text (via QLDescriptionCalculator)
   … waterfall steps (ListPrice→NetUnitPrice, StampBaseFilter, proration, derived-maint DPP formulas) …
   POSTHOOKS (after waterfall)
     8. PartnerNetPricePosthook         commercial net = LOWER(procedure net, partner net); stamps PartnerUnitPrice
     9. CancelLineCreditPosthook        negative-qty credit = net × qty onto NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount
```

**Thin-hook → service pattern (Wave-2).** Each hook is now a thin adapter that owns only context I/O + SOQL and delegates pure math/shaping to an extracted, unit-testable service. `ContextTagReader` is the shared canonical reader (`getStringFromTag` / `getIdFromTag` / `getDecimalFromTag` / `getLineItemRecordId`, unwrapping the `{tagValue:…}` shape) used across all hooks. The ~15+ extracted calculator/builder/resolver services:

- **Shared context seams:** `ContextTagReader`, `ContextUpdateNavigator`
- **Partner:** `PartnerMarginDispatcher`, `PartnerParticipationResolver`, `PartnerPricingPayloadBuilder`, `PartnerNetResolutionCalculator`, `PartnerPricingGate`, `ListPriceStampCalculator`
- **COLA / renewal:** `COLAUpliftCalculator` (`resolveTier`, `isPersistedLineOverride`, `computeStampedMaintenanceColaNet`), `RenewalMaintenanceColaCalculator`, `RenewalColaPayloadBuilder`
- **Derived maintenance:** `NewMaintenanceInputResolver`, `NewMaintenanceNetCalculator` (`expectedListNet = contributorNet × rate`; `expectedCommercialNet`), `NewMaintenanceBandCalculator`, `DerivedMaintenanceClassifier`, `ContributorPricingCalculator`, `DerivedMaintenancePayloadBuilder`, `NewBusinessMaintenanceNets` (top-level DTO), `SequentialDiscountCalculator` (`applyDiscountPercent = base × (1 − percent/100)`, scale-2 HALF_UP)
- **Attribute / regional / hardware / cancel / description:** `AttributeVolumeCalculator`, `RegionalPricingCalculator` (`CEILING((listPrice × multiplier)/5) × 5`), `HardwarePricingCalculator`, `CancelLineCreditCalculator`, `QLDescriptionCalculator`
- **Telemetry:** `PricingHookLogger` (`logPrehook` / `logPosthook`) + `ExceptionLogger`

## Refactor Context (Waves 0–4)

The pricing refactor set out to make the hook layer safe, testable, and consolidated without changing pricing outputs: (0) build a **13-scenario golden reprice harness** plus a documented waterfall with named invariants; (1) delete dead code (V1 `PartnerPricingPrehook`, `SourceListPrice*` no-ops, quarantine `scratch_v210.xml`); (2) **thin every hook** into an adapter over a `*Calculator`/`*Builder`/`*Resolver` service (`PartnerNetPricePosthook` alone decomposed across 8 increments); (3) **consolidate the two duplicate engine clusters** — unify partner margin onto the deal-aware V2 posthook path (D-11, `getMarginForProductType(...,dealType)`) and collapse both COLA surfaces onto a single `COLAUpliftCalculator.resolveTier` (D-13); (4) harden — recursion guards, config-as-code MDT for Hardware (`Hardware_Attribute_Pricing__mdt`) and currency maps, Order-side invocable bulkification, and swallow-to-SUCCESS **exception logging** (D-18, `PricingHookLogger`). **Status: Waves 0–3 complete; Wave 4 ~85%** — all engineering shipped and 13/13 golden scenarios pass 0-delta; the remainder is owner-gated governance decisions (D-3, D-21, OQ-2) and cosmetic V24 canvas renames (D-23).

## Consolidated Change Map

| Theme | What changed | Where (hook / step / field) | Ticket / D-item |
|---|---|---|---|
| Partner pricing | Unify margin to deal-aware V2; posthook takes commercial net = LOWER(procedure net, partner net), always stamps `PartnerUnitPrice`; SDD reconciliation | `PartnerNetPricePosthook` (v1.4), `PartnerPricingPrehookV2` (v2.1); `Pre_Partner_Price__c`; `PartnerMarginDispatcher`/`PartnerParticipationResolver` | D-11, D-12, af3a470 |
| Partner pricing | Blank `Non_Orig_*` ⇒ standard band (not 0) affirmed; `effectivePct` fallback kept | posthook `getMarginForProductType(...,dealType)` | A-2/OQ-1, d5063ae, fc10b70 |
| COLA / renewal | Single COLA engine: prehook + handler INSERT both call `resolveTier`; restore `Is_COLA_Overridden__c` formula | `COLAUpliftPrehook`, `COLAUpliftCalculator`; `COLACalculatedPrice__c`, `Pre_COLA_Price__c`, `COLA_Source__c` | D-13, 66b09b1/83cac00/fcf1c13/c4710b0 |
| COLA / renewal | MyCAP treated as out-year floor; COLA audit fields confirmed persisting (no-action) | `RenewalMaintenanceColaCalculator` | A-1, B-1 |
| Derived maintenance | Thin decomposition; J-06 net precedence lifted to calculator; New-Maint amend lines excluded from amend-carry (owned by SC-3346 path) | `NewMaintenanceNetCalculator`, `DerivedMaintenancePayloadBuilder`, `AmendNetCarryPrehook` (`Fortra_Product_Type__c != 'New Maintenance'`) | J-06, SC-3346, 18fda47 |
| Attribute / volume | Extract calculator; D-17 stale attribute Net-Bridge reset-to-list fix | `AttributeVolumePricingPrehook` → `AttributeVolumeCalculator` | D-17/A-4, 6c79166 |
| Regional / GSA | Extract calculator; effective-dating (`isEffectiveOn`); null-`Multiplier__c` Active-row guard → DEFAULT 1.0 | `RegionalServicesPricingPrehook` → `RegionalPricingCalculator` | A-6, 8d1ec19, 3a338ec |
| Hardware | Inline pGroup/userTier/systemType tables → admin MDT (byte-for-byte seed); SDD source label + open-ended top user-band | `HardwareAttributePricingPrehook` → `HardwarePricingCalculator`; `Hardware_Attribute_Pricing__mdt` | D-14, 96a7f62, 173431a |
| Cancellation | Thin posthook; self-resolves asset NET (currency-matched) from `AssetActionSource` when `CancelNetUnitPrice__c` unset; credit = net × qty | `CancelLineCreditPosthook` → `CancelLineCreditCalculator` | SC-3441, a1c26a6 |
| Amendment | New prehook seeds prior `QuoteAction.SourceAsset.Price` onto Amend lines (net<=0) + line total; supersedes AmendSeedNetUnit/NetTotal | `AmendNetCarryPrehook` (Quote-scoped) | SC-3501, 4a497df/b8b25f6 |
| Aggregation / rollup | ARR apportioned on Power splits; Asset-ARR copy moved to Apex | `Order_Line_ARR__c` | A-3, e5ab55b/9125c5c |
| Telemetry | Swallow-to-SUCCESS surfaced via fire-and-forget event logging wired into every hook catch | `PricingHookLogger.logPrehook/logPosthook`, `ExceptionLogger` | D-18, 7876aa0/9bcf2f7 |
| Currency | AttributeVolume tier lookup made currency-aware; auto-add QLI re-pointed to quote-currency PBE; retired dead country-currency path | `AttributeVolumeCalculator`; `QuoteLineItemCurrencyCorrectionHandler`; deleted `CurrencySelectionService` + `Country_Currency_Map__mdt` | SC-3384, D-15/D-10, 255f7c5/43fa4d1/4e5279b |

## Open Items to Raise in the Meeting

1. **Two Active procedure versions (highest priority).** `Rev_Mgmt_Default_Pricing_Procedure` has **V24 and V23 both Active** and structurally different (~8 KB apart, distinct md5) — V24 activated 2026-07-10 02:59 but V23 was never deactivated. Which version prices is ambiguous. Action (owner, canvas Versions list): confirm V24 is runtime, **deactivate V23** to Inactive backup, then run the golden gate for 0-delta.
2. **D-3 / OQ-3 — retire `RenewalMaintenanceFlip`.** Class is deprecated-in-ApexDoc and fully unreferenced (0 metadata/flow/repo deps), but deletion was blocked by an obsolete **Flow v7 reference** (corrects the plan's "zero refs"). Decide delete-vs-keep; if delete, retire the flow ref first (destructive deploy + golden gate).
3. **OQ-2 / D-10b — currency-change no-op.** The wired `QuoteCurrencyChangeService` is a **no-op** (Draft flow). Business decision: activate + actually convert prices, or delete the dormant path.
4. **D-21 / OQ-6 — currency config-as-code.** Decide whether `Currency_Conversion_Formula__mdt` (runtime-parsed executable string) should stay config-as-code. Boundary item, low urgency.
5. **D-23 — cosmetic V24 canvas renames.** 16 dup-label groups + Copy-of-Copy triad; rename-only (0 deletions), by label/function never `<name>`. Canvas-only, cannot be done via CLI.
6. **Uncommitted working-tree changes need commit + golden gate.** Large uncommitted deltas sit in `PartnerNetPricePosthook.cls` (+350), `CancelLineCreditPosthook.cls` (+195), `CancelLineCreditCalculator.cls` (+104), `AmendNetCarryPrehook.cls` (+58), `NewMaintenanceNetCalculator.cls` (+46), plus ~40 modified calculator/test files and an untracked `COLAUpliftCalculatorParityTest.cls` — these must be committed and run through the 13-scenario 0-delta harness before any V24 activation is finalized.
7. **Re-confirm D-19 null-safety on V24** (StampBaseFilter `NetUnitPrice > 0 OR IsNull`, seq 6 — verified present) and close housekeeping D-7 (`.bak_preedit` non-authoritative) / D-8 (shared MDT-selector dedup for `COLA_Uplift_Rules__mdt` and `Maintenance_Rate__mdt`).


---

# Part 1 — Prehook & Posthook Modifications

_Nine Apex hooks implementing `RevSignaling.SignalingApexProcessor`, in waterfall order: Regional → Partner → COLA prehooks mid-procedure, Amend/Attribute/Hardware/Description around them, and two posthooks after. Each is a thin adapter over an extracted `*Calculator` service._

## Prehooks

### AmendNetCarryPrehook (PREHOOK)

**File:** `force-app/main/default/classes/AmendNetCarryPrehook.cls` · **API 65.0 · Active** (`AmendNetCarryPrehook.cls-meta.xml`) · `global class AmendNetCarryPrehook implements RevSignaling.SignalingApexProcessor`

#### 1. Purpose
Seeds the prior negotiated net onto **Amend** quote lines *before* the pricing waterfall runs. Per the class header, a genuine (non-migrated) amendment line is born with `QuoteLineItem.NetUnitPrice = 0` and "no layer carries the prior negotiated net onto it: the pricing procedure has no SourceAsset read, and Amend is the ONLY lifecycle action with no Apex net-carry hook (Renew has COLAUpliftPrehook, Cancel has CancelLineCreditPosthook)." This is the **sole amend-carry hook under V24**.

- **Pre vs post:** PREHOOK — `execute()` runs before the waterfall so the procedure's `AmendSeedNetUnit` / `AmendSeedNetTotal` steps preserve (no-op over) the prehook-stamped values. Header: the prehook "now owns authoritatively... the procedure steps remain only as a fallback."
- **Quote vs Order:** **Quote-scoped.** `isOrderTransaction(ctxInstanceId)` inspects the root data-path id prefix — `rootId.startsWith('801')` (Order) → returns SUCCESS and skips; "whose SourceAsset carry is on the Order side."
- **Reprice mode:** native Reprice only (fires on the standard RLM pricing-context evaluation for the Quote transaction).
- **Non-blocking:** reentrancy-guarded via `private static Boolean isProcessing`; always returns `RevSignaling.TransactionStatus.SUCCESS` — even in the `catch` block ("Return SUCCESS even on error to avoid blocking pricing").

#### 2. Modifications made (with reasons)
This hook is **self-contained** (no extracted `*Calculator` delegate — unlike the COLA/Cancel siblings it mirrors). All logic lives in the thin hook.

| Change (code-level) | Reason | State |
|---|---|---|
| **Initial hook** (`4a497df`, SC-3501): `execute` → `isOrderTransaction` guard → `seedAmendNets`. For Amend lines with `netUnset = NetUnitPrice == null \|\| <= 0`, `buildAmendSeedUpdate(wrapper, priorNet)` stamped `NetUnitPrice` + `UnitPrice` from `QuoteAction.SourceAsset.Price`. SOQL was `SELECT Id, NetUnitPrice, Fortra_Product_Type__c, QuoteAction.Type, QuoteAction.SourceAsset.Price`. | Amend line born at $0; carry prior negotiated Asset net. Ticket header also notes Layer-1 flow fix (`Fortra_Quote_Reprice` discovery proc → `Salesforce_Default_Pricing_Discovery_Procedure_v2`). | **Committed** |
| **Line-total carry** (`b8b25f6`, SC-3501, "carry line total (net x qty), sole amend-carry under V24"): added `NetTotalPrice, Quantity` to SOQL; introduced `carriedNet = netUnset ? priorNet : qli.NetUnitPrice`; computes `expectedTotal = (carriedNet * qty).setScale(2, HALF_UP)`, stamps total only when `totalStale` (`NetTotalPrice == null \|\| (NetTotalPrice - expectedTotal).abs() > 0.005`). Added 2-arg overload `buildAmendSeedUpdate(itemWrapper, unitNet, lineTotal)` writing the four-attribute total cluster; original 1-arg signature retained as delegating overload. | `AmendSeedNetTotal` preserved a **stale** total on a qty change → line total didn't recalc. Prehook now stamps qty-correct total, superseding the procedure "Amend Net Carry group." | **Committed** |
| **D-18 exception surfacing** (working tree, uncommitted): added `ExceptionLogger.log('AmendNetCarryPrehook', ctxInstanceId, new AmendNetCarryException(...))` in `queryContextItems`, `submitContextUpdates`, and `isOrderTransaction` catch blocks. (`AmendNetCarryException extends PricingException`, defined in `AmendNetCarryException.cls`.) Note `execute()` already carries the committed D-18 hook `PricingHookLogger.logPrehook(...)`. | Surface swallowed degrades (fire-and-forget) per D-18 exception-logging theme. | **Uncommitted** |
| **Docstring de-versioning + author + JavaDoc params** (working tree, uncommitted): stripped `SC-3501` / `V23` / `SC-3350` literals and the inline `AmendSeedNetUnit = IF(NetUnitPrice>0, NetUnitPrice, InputUnitPrice)` formula from the header; added `@author Liam Jeong`; added `@param`/`@return` to methods; file lost trailing newline. | Documentation cleanup; decouple prose from a specific procedure version (now V24). | **Uncommitted** |

#### 3. Context elements

| READS (inputs) | WRITES (outputs) |
|---|---|
| Context store: `ctx.queryTags({contextId, tags:['SalesTransactionItem']})` → raw line item wrappers (`queryContextItems`) | Context store: `ctx.updateContextAttributes({contextId, nodePathAndAttributes: updates})` (`submitContextUpdates`) |
| `itemWrapper.get('dataPath')` (List) — last element parsed as `Id.valueOf(...)` → QLI Id; first element prefix `'801'` → Order detection | **Unit cluster** (when `unitSeed != null`): `NetUnitPrice`, `UnitPrice` — each = `unitNet.setScale(2, HALF_UP)` |
| `request.ctxInstanceId` | **Total cluster** (when `totalSeed != null`): `NetTotalPrice`, `TotalPrice`, `Subtotal`, `TotalLineAmount` — each = `lineTotal.setScale(2, HALF_UP)` |
| SOQL on `QuoteLineItem`: `NetUnitPrice`, `NetTotalPrice`, `Quantity`, `Fortra_Product_Type__c`, `QuoteAction.Type`, `QuoteAction.SourceAsset.Price` | (updates written onto the context node path = `dataPath` with the first element removed) |

Note: this hook does **not** use `ContextTagReader` (no `getDecimalFromTag`) — it reads the prior net from a **SOQL query on QuoteLineItem/QuoteAction.SourceAsset.Price**, not from a context tag. The context read is only `queryTags(['SalesTransactionItem'])` to obtain each line's `dataPath` for id mapping and Order detection.

#### 4. Context mappings

- **Prior net source → line:** `QuoteAction.SourceAsset.Price` (prior Asset net) → context `NetUnitPrice` + `UnitPrice` (`UnitPrice` feeds procedure `InputUnitPrice`). Stamped only when `netUnset` (incoming net null/≤0); an already-priced net is preserved (`carriedNet = qli.NetUnitPrice`).
- **Line total:** `carriedNet × Quantity` → four-attribute total cluster `NetTotalPrice / TotalPrice / Subtotal / TotalLineAmount`. Per docstring this is "the same four-attribute total cluster used by DerivedMaintenancePayloadBuilder / PartnerNetPricePosthook / RenewalMaintenancePricingService," and `TotalLineAmount` is specifically "the `AmendSeedNetTotal` fallback branch, so the seed survives whichever branch that step takes." `NetTotalPrice` feeds `ItemNetTotalPrice`.
- **Update path:** `updatePath = dataPath.clone()` with `updatePath.remove(0)` (drops the root), wrapped as `{nodePath:{dataPath}, attributes:[...]}`.
- **Registration (org-config, NOT in git):** header states "Registered via ProcedurePlanOption (PrimaryObject=Quote) like the sibling hooks." As with all Fortra prehooks, the signal binding lives in org config (ProcedurePlanOption / signal binding), not in the ESD XML or repo. **The specific ProcedurePlanOption Id for this hook is not present in these files** — cannot be confirmed from the class; verify in-org (sibling partner prehook is on `1FYWC0000002W3r4AE`).

#### 5. Key risks / notes
- **Uncommitted delta in working tree:** the D-18 `ExceptionLogger.log` calls and docstring changes are **not committed**. The committed live behavior is `b8b25f6`; the extra `ExceptionLogger` surfacing is not yet in git.
- **Idempotency:** unit seeded only when `netUnset`; total seeded only when `totalStale` (diff > `0.005`) and `qty > 0` — so unchanged-qty reprices are no-ops. Reentrancy guarded by static `isProcessing`.
- **Scoping exclusions:** SOQL filters `QuoteAction.Type = 'Amend'` and excludes `Fortra_Product_Type__c = 'New Maintenance'` (owned by the SC-3346 derived-maintenance path — "a flat prior-net carry there is both overridden by the derive steps and would collide with that fix").
- **Known residual (Software lines):** header/comment — Software lines *are* seeded, but the "subscription pricing steps (unconditional, not ItemPricingSource-gated) recompute the net after this prehook"; carrying them to completion "needs a procedure-level gate (tracked separately), not a class change." So Software amend-carry is **not fully resolved** by this hook.
- **Ordering:** supersedes procedure group `AmendSeedNetUnit + AmendSeedNetTotal` (they become fallbacks/no-ops on prehook-stamped lines). No prior net (no `SourceAsset`) → hook `continue`s and leaves the line to the procedure fallback.
- **Currency:** header claims currency-safe because "Asset.Price is in line currency" — no FX conversion is performed; relies on that assumption.
- **Order path:** entirely skipped; any Order-side amend net-carry is out of scope for this hook and asserted to live on the Order side (not verified here).
- **V23/V24 dual-Active:** hook prose was deliberately de-versioned (uncommitted); it targets the active procedure `Rev_Mgmt_Default_Pricing_Procedure` regardless of the V23/V24 both-Active cleanup item — the binding is by signal/ProcedurePlanOption, not by version literal.


### AttributeVolumePricingPrehook (PREHOOK)

#### 1. Purpose

`AttributeVolumePricingPrehook` is an RCA/RLM pricing-procedure **prehook** — `global class AttributeVolumePricingPrehook implements RevSignaling.SignalingApexProcessor`, entry point `public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request)`. It runs inside the active runtime procedure `Rev_Mgmt_Default_Pricing_Procedure` **V24** (both V23 and V24 currently Active — open cleanup item). As a prehook it fires **before** the native pricing math, seeding attribute/volume-derived price inputs into the `SalesTransactionContext` so downstream procedure steps consume them.

It applies **attribute + volume tiered pricing**: it reads context line items, filters to those flagged `Has_Attribute_Adjustment__c = true`, bulk-loads `Attribute_Tier_Pricing_Storage__c` tier rows, and for each eligible line resolves a tier by `(Product | ProductSellingModel | AttributeName | AttributeValue | Currency)` composite key plus a `Lower_Bound__c/Upper_Bound__c` volume-range check. It then writes one of three price modes back to context (per class header, lines 22-25):
- **Unit Price**: `Base_Price__c` → InputUnitPrice
- **Calculated**: `Base_Price__c * Attribute_Multiplier_Pct__c` → ItemNetTotalPrice
- **Total Price**: `Base_Price__c` → ItemNetTotalPrice

Runs on both quote and order transactions — it is context-node driven (`SalesTransactionItem` / `SalesTransactionItemAttribute` tags), agnostic to QuoteLineItem vs OrderItem. It fires whenever the pricing context is (re)priced, i.e. on native **Reprice**. Recursion is guarded by a `private static Boolean isUpdating` flag (returns SUCCESS "Skipping recursive execution" on re-entry). It never fails the transaction — `execute()` always returns `RevSignaling.TransactionStatus.SUCCESS` even on caught exceptions.

#### 2. Modifications made (with reasons)

Recent history (`git log` on the hook): `255f7c5` (SC-3384 currency-aware), `7876aa0` (D-18 logging), `81426b4` (Wave-2 calculator extraction), `a1fc2b3` (flows). The **hook file has no uncommitted changes**; the **calculator has uncommitted working-tree edits**.

| # | Change (code-level, real identifiers) | Reason / ticket | State |
|---|---|---|---|
| 1 | **Wave-2 thin-hook decomposition** (`81426b4`). All pure tier math + node shaping extracted into `AttributeVolumeCalculator`. Hook keeps only the two `industriesContext.queryTags` reads (`queryLineItems`, `queryLineItemAttributes`), the bulk `Attribute_Tier_Pricing_Storage__c` SOQL, Pass-1/Pass-2 orchestration in `buildItemNodeUpdates(...)`, and the `submitContextUpdates(...)` context write. All former private methods are now `@TestVisible` delegating seams (e.g. `buildTierLookupMap`, `lookupTierFromMap`, `buildResetNodeUpdate`, `buildNodeUpdateForTest`) that forward to `AttributeVolumeCalculator`. Header states the SC-3390/D-17 reset behavior was "moved unchanged, NOT fixed." | Testability / maintainability (hook-thinning). Preserves signatures so `AttributeVolumePricingPrehookTest` is unaffected. | Committed |
| 2 | **SC-3384 currency-aware tier lookup** (`255f7c5`). In hook Pass-1, added `Set<String> currencies` collected from item tag `STICurrencyIsoCode` (lines 167, 191-194). Bulk SOQL gained `AND CurrencyIsoCode IN :currencies` and now selects `CurrencyIsoCode` (lines 214, 218). Pass-2 reads `lineCurrency = ...getStringFromTag(tagMap,'STICurrencyIsoCode')` and passes it into `lookupTierFromMap(..., lineCurrency)` (lines 293-294). In `AttributeVolumeCalculator`, `buildCompositeKey` added a **5th segment** `currencyIso` — key is now `productId|psmId|normalizedName|attrValue|currencyIso` (line 77); `lookupTierFromMap` signature gained `String currencyIso`. | SC-3384: lookup was currency-blind — a EUR/GBP line matched USD tier rows and priced off the USD `Tier_Value__c`. Now a non-USD line matches ONLY its own-currency tier row. | Committed |
| 3 | **D-18 pricing-hook exception logging** (`7876aa0`). In `execute()` catch block: `PricingHookLogger.logPrehook('AttributeVolumePricingPrehook', contextId, e)` (line 65) — fire-and-forget, does not throw, status unchanged. | D-18 observability: surface the silently-degraded path (hook swallows errors and returns SUCCESS). | Committed |
| 4 | **Calculator observability + docs** (uncommitted working tree). `ExceptionLogger.log('AttributeVolumeCalculator', null, new AttributeVolumeException(...))` added inside the catch of `getAttributeVolumeValue` (line 360) and `getDecimalFromTag` (line 442); the parse failures previously only `System.debug`'d. Class header doc rewritten (author now `Liam Jeong`); several method Javadoc `@param/@return` completions. File ends with **no trailing newline** (`\ No newline at end of file`). | D-18-adjacent: instrument the two swallowed `Decimal.valueOf` parse failures. Doc/authorship cleanup. | **Uncommitted** |

Note the **thin-hook adapter** (`AttributeVolumePricingPrehook`) owns all live-context I/O (queryTags, SOQL, `updateContextAttributes`); the **extracted delegate** (`AttributeVolumeCalculator`, `public with sharing`, all-static, no SOQL/DML/context) owns pure tier resolution and node shaping.

#### 3. Context elements (read / write)

| READS (context inputs) | WRITES (context outputs) |
|---|---|
| **`SalesTransactionItem`** tag list — via `queryLineItems()` → `industriesContext.queryTags({tags:['SalesTransactionItem']})`, `queryResult.get('SalesTransactionItem')` | Node-update `attributes` list submitted via `submitContextUpdates()` → `industriesContext.updateContextAttributes({contextId, nodePathAndAttributes})`. Per matched line (`buildNodeUpdate`): |
| **`SalesTransactionItemAttribute`** tag list — via `queryLineItemAttributes()` → `queryTags({tags:['SalesTransactionItemAttribute']})` | • **`Base_Price__c`** = `tierResult.basePrice` (from `Tier_Value__c`) — always |
| Per-item tags (via `AttributeVolumeCalculator.getStringFromTag/getBooleanFromTag`): `Has_Attribute_Adjustment__c` (eligibility gate), `Product`, `ProductSellingModel`, `STICurrencyIsoCode` (SC-3384), `Name`, `HasBundleConfiguration`, `BundleLineItemId` | • **`Attribute_Price_Mode__c`** = `tierResult.priceMode` (from `Price_Mode__c`) — always |
| Per-attribute tags (`AttributeVolumeCalculator.getAttributeValue/lookupTierFromMap`): `Attribute` (name; falls back to `AttributeKeyName`), `AttributeValue`, `ParentReference` (attr→line grouping), and the `Attribute_Volume` attribute value | • **`Attribute_Multiplier_Pct__c`** = `tierResult.multiplier` (from `Multiplier__c`) — **only** when `priceMode == 'Calculated' && multiplier != null` |
| **Reset path** reads item tag **`ListPrice`** (`buildResetNodeUpdate` → `getDecimalFromTag(tagMap,'ListPrice')`) | **Reset node update** (`buildResetNodeUpdate`, when volume null or no tier match): `Base_Price__c` = `ListPrice` (or 0), `Attribute_Price_Mode__c` = `'Unit Price'` |
| `dataPath` array on each node (line-item id = last element; attr parent = second-to-last) | Node targeted by `nodePath.dataPath` = the item's `dataPath` **with element 0 (contextId) removed** (`updatePath.remove(0)`) |

SOQL source object: `Attribute_Tier_Pricing_Storage__c` fields `Product__c, Product_Selling_Model__c, Attribute_Name__c, Attribute_Value__c, Lower_Bound__c, Upper_Bound__c, Tier_Value__c, Multiplier__c, Price_Mode__c, CurrencyIsoCode`.

Explicitly **not written**: `AttributePricingApplied__c` was removed from context writes (calculator lines 203-205: "The QLI field does not exist … may cause the entire node update to silently fail").

#### 4. Context mappings

- **Tier record → context attribute**: `Tier_Value__c → Base_Price__c`; `Price_Mode__c → Attribute_Price_Mode__c`; `Multiplier__c → Attribute_Multiplier_Pct__c` (Calculated mode only). These three context attributes are what the pricing procedure's downstream steps read to compute the line's InputUnitPrice / ItemNetTotalPrice per the three-mode contract in the class header.
- **Context attribute → persisted target**: `Base_Price__c` / `Attribute_Price_Mode__c` / `Attribute_Multiplier_Pct__c` are Context Definition attributes mapped to the corresponding **QuoteLineItem/OrderItem** source fields; the hook writes to the context node (`updateContextAttributes`), not directly to the SObject. The precise Context-Definition-to-QLI/OI field binding lives in the Context Definition mapping metadata, **not determinable from these two Apex files** — the hook only names the context attributes.
- **Attribute-name normalization**: `buildCompositeKey` does `attrName.replaceAll(' ', '_')` — context uses underscores (`Feature_Options`), tier data uses spaces (`Feature Options`); standardized to underscores so both sides key-match.
- **Registration**: This prehook is bound to the pricing procedure via **org config** (`ProcedurePlanOption` / signal binding), **NOT** in the ESD XML or git — same mechanism as the partner prehook (bound on `ProcedurePlanOption 1FYWC0000002W3r4AE`). The specific `ProcedurePlanOption` Id and signal for `AttributeVolumePricingPrehook` are **not present in these files** and must be read from the org config; cannot be confirmed from source.

#### 5. Key risks / notes

- **Uncommitted delegate**: `AttributeVolumeCalculator.cls` has working-tree edits not yet committed (D-18 `ExceptionLogger.log` in the two parse catches, doc rewrite, and a **missing trailing newline**). Deploying the hook without this calculator change ships a different runtime than the working tree; the added logging depends on `ExceptionLogger` and an `AttributeVolumeException` type — verify both exist/compile before deploy.
- **Silent-degrade design**: `execute()` always returns SUCCESS. Errors are only surfaced via `PricingHookLogger.logPrehook` (D-18) and `System.debug`; a failure yields no visible pricing change but no transaction error. `queryLineItemAttributes` additionally **swallows** any `queryTags` failure and continues with zero attributes — every line then hits the reset-to-list path.
- **SC-3384 hard dependency on currency tags**: if a line's `STICurrencyIsoCode` is blank, that currency is never added to `currencies`, so the `AND CurrencyIsoCode IN :currencies` filter can exclude its tier rows → no match → reset to list. Tier data must have a matching `CurrencyIsoCode` row per currency, else non-USD lines silently fall back to `ListPrice`.
- **D-17 / A-4 (Net Bridge stale price) — reset path preserved, not fixed**: on `volume == null` or no tier match, the hook emits `buildResetNodeUpdate` writing `Base_Price__c = ListPrice`, mode `'Unit Price'`. The class header (lines 32-35) is explicit that the SC-3390/D-17 "silent reset-to-list behavior is preserved EXACTLY … moved unchanged, NOT fixed." This reset is the deliberate anti-stale mechanism, but it means any line that loses its `Attribute_Volume` or tier match is forced to list price — a behavior the team should treat as intentional-but-lossy, not a bug fix.
- **Idempotency**: writes are derived purely from tier data + current context tags (no accumulation), so re-running on unchanged input yields the same node updates; the `isUpdating` static additionally blocks recursive re-entry within a transaction.
- **Ordering**: as a prehook it must run before native price computation; it consumes `Has_Attribute_Adjustment__c` and `ListPrice` that upstream steps/flows populate. Relative ordering vs other prehooks (e.g. partner prehook) is governed by the org `ProcedurePlanOption` binding and is **not** visible in these files.
- **First-match semantics**: `lookupTierFromMap` returns the **first** attribute whose composite key exists and whose volume falls in range — if a line has multiple tier-eligible attributes, the result depends on attribute iteration order, not a defined priority.

Files: `/Users/liamjeong/Documents/Code/Fortra/force-app/main/default/classes/AttributeVolumePricingPrehook.cls` (API 64.0, Active), `/Users/liamjeong/Documents/Code/Fortra/force-app/main/default/classes/AttributeVolumeCalculator.cls` (uncommitted edits).


### COLAUpliftPrehook (PREHOOK)

**Runtime:** `global class COLAUpliftPrehook implements RevSignaling.SignalingApexProcessor` — API v65.0, `status Active` (`COLAUpliftPrehook.cls-meta.xml`). Registered as a plugin on the active procedure `Rev_Mgmt_Default_Pricing_Procedure` (documenting **V24**). Delegates all pure math/payload assembly to `COLAUpliftCalculator`; `RenewalMaintenanceColaCalculator` is a sibling calculator that also routes fresh maintenance uplift through the same canonical engine.

#### 1. Purpose
Applies COLA (Cost-of-Living Adjustment) uplift to **renewal** quote lines during the pricing waterfall. It is a **pre**-processor: `execute(RevSignaling.TransactionRequest)` runs before the native pricing/reprice computation, reads `SalesTransactionItem` tags via `Context.IndustriesContext.queryTags`, resolves the COLA rate through a documented hierarchy (line docstring lines 6–9): **1. Line Override (manual QLI edit) > 2. Contract Override (active Contract) > 3. CMDT Lookup (`COLA_Uplift_Rules__mdt` by Solution Category)**, computes the adjusted price, and writes it back with `ctx.updateContextAttributes` so the values survive the reprice cycle. Scope is deliberately narrow:
- **Quote-only.** A `SCOPE GUARD` (lines 69–81) calls `isOrderTransaction(ctxInstanceId)` — which peeks `dataPath[0]` and returns true when the root Id `startsWith('801')` — and short-circuits with SUCCESS on Order transactions, because the COLA context attributes are mapped only on the Quote side of `SalesTransactionContextExt` (Order-side resolution throws "Invalid tag attribute name key").
- **Renewal-only.** The QLI SOQL filters `AND QuoteAction.Type = 'Renew'` (line 256); MyCAP gate reads per-line tag `SalesTransactionActionType != 'Renew'` and `continue`s (line 938).
- It replaces the legacy trigger-based `COLAUpliftHandler` for Revenue Cloud (class docstring line 3).

#### 2. Modifications made (with reasons)
All changes to `COLAUpliftPrehook.cls` itself are **COMMITTED** (working tree clean for this file). The two calculators carry **UNCOMMITTED** working-tree edits (mostly doc/`@author`, plus one behavioral delegation noted below).

| Change (code-level, real identifiers) | Reason / ticket | State |
|---|---|---|
| **D-13 single COLA engine.** Inline 3-tier selection block replaced by delegating call `COLAUpliftCalculator.resolveTier(lineOverridePercent, stampedDefault, cmdtDefault, contractOverridePct)` (prehook lines 394–397), returning `TierResult{percent, source}`. Predicate `isManualLineOverride` + `isPersistedLineOverride` relocated into the calculator so the trigger handler and reprice prehook share one engine. | D-13 / INV-7, SDD BR-003 (commits `66b09b1`, `83cac00`) | Committed |
| **Wave-2 hook-thinning.** `COLAUpliftCalculator` extracted from the hook; prehook methods `buildExplainerText`, `buildItemUpdate`, `buildNetUnitPriceUpdate`, `buildMaintenanceColaItemUpdate`, `computeStampedMaintenanceColaNet`, `extractLineItemData`, `isOrderTransaction(List)`, `buildCOLAContextUpdate` are now thin `@TestVisible` seams that return `COLAUpliftCalculator.<same>(...)`. Tag readers `getStringFromTag`/`getDecimalFromTag`/`extractFieldValue` delegate to shared `ContextTagReader`. | Wave-2 decomposition (commits `23c6c4e`, `156b021`) | Committed |
| **SC-3350 NetUnitPrice seed.** Re-added isolated `pendingNetUnitPriceUpdates` list (line 36); `buildLineItemUpdates` seeds `NetUnitPrice = colaAdjustedPrice` (lines 451–456) and `processLineItems` submits it in its **own** `submitContextUpdates` batch (lines 292–295). Guards: skip maintenance lines (`Fortra_Product_Type__c` = 'Renewal Maintenance'/'New Maintenance') and only seed when stored `NetUnitPrice` is null/≤0. | SC-3350: a prehook NetUnitPrice write is the only mechanism proven live (2026-06-11) to COMMIT the COLA'd net to the waterfall for non-derived renewal lines; maintenance owned by SC-3346 path | Committed |
| **Line-override precedence fix (SC-3384 theme).** Added `isPersistedLineOverride(lineOverridePercent, stampedDefault)` disjunct inside `resolveTier` — a stored `COLA_Uplift_Percent__c` differing from stamped `Default_COLA_Uplift_Percent__c` is honored as a genuine rep override even when it equals the CMDT default (mirrors `Is_COLA_Overridden__c`). | Marc DeBrey 2026-07-07 (x1.03/x1.04); keeps rep's rate on reprice instead of reverting to Contract rate | Committed |
| **SC-3346 stamped renewal-maintenance.** `appendStampedRenewalMaintenanceUpdates` (lines 553–596): for QLIs `Fortra_Product_Type__c='Renewal Maintenance' AND Quote.QuoteTypeText__c='Renewal' AND Base_Price__c>0`, computes `computeStampedMaintenanceColaNet` = `(Base − Prior_Partner_Discount__c − Prior_Discretionary_Discount__c) × (1 + COLA%)` and writes `COLACalculatedPrice__c` for the DPP COLA formula. | SC-3346 renewal-maintenance COLA from stamped Base/Partner/discretionary components (v1.1) | Committed |
| **D-18 exception logging.** `catch` block adds `PricingHookLogger.logPrehook('COLAUpliftPrehook', request.ctxInstanceId, e)` (line 106); status still forced to SUCCESS to avoid blocking pricing. | D-18 observability (commit `7876aa0`) | Committed |
| **RenewalMaintenanceColaCalculator delegation.** `computeRenewalMaintenanceColaNet` fresh-uplift branch now returns `COLAUpliftCalculator.computeStampedMaintenanceColaNet(qli)` instead of an inline `(preColaNet * (1+colaPercent/100))` (claimed byte-identical, guards preserved; `COLAUpliftCalculatorParityTest`). Plus `@author` / javadoc `@param`/`@return` additions on both calculators. | D-13 single-source-of-truth consolidation | **Uncommitted** (working tree) |

#### 3. Context elements (read / write)
Reads are via `ContextTagReader.getDecimalFromTag/getStringFromTag/getBooleanFromTag` on the `SalesTransactionItem` tag payload; writes are `attributeName`/`attributeValue` pairs pushed through `updateContextAttributes`.

| READS (context input tag) | WRITES (context attribute output) |
|---|---|
| `SalesTransactionItem` (list, via `queryTags`) | `COLACalculatedPrice__c` ← `colaAdjustedPrice` (`buildItemUpdate`) |
| `dataPath` (last elem → QLI Id; `[0]` → root/Order-prefix `801`; `[size-2]` → Quote Id) | `Pre_COLA_Price__c` ← `assetPrice` (pre-COLA base) |
| `COLA_Uplift_Percent__c` (stored line override %) | `COLA_Source__c` ← tier label: `Line Override` / `Contract Override` / `CMDT Lookup` / `MyCAP Default` |
| `Default_COLA_Uplift_Percent__c` (stamped applied-tier default) | `COLA_Applied_Date__c` ← `Datetime.now()` |
| `PricingTermCount`, `PricingTermUnit` (=='Annual'), `ItemSubscriptionTerm` (multi-year test) | `COLA_Solution_Category__c` ← `solutionCategory` (when non-blank) |
| `SalesTransactionActionType` (=='Renew' MyCAP gate) | `NetUnitPrice` ← `colaAdjustedPrice` (SC-3350 **isolated** batch, non-maintenance only) |
| `UnitPrice`, `COLA_Solution_Category__c`, `IsCOLAOverridden__c` (MyCAP pass) | `PartnerDiscountPercent`, `Discount` (echoes, maintenance update only) |

**SOQL reads (not context):** `QuoteLineItem` → `QuoteAction.Type`, `QuoteAction.SourceAsset.Price` (COLA base), `SourceAsset.Product2.Solution_Category__c`, `NetUnitPrice`, `Fortra_Product_Type__c`, `Default_COLA_Uplift_Percent__c`, `COLA_Outyear_Uplift_Percent__c`; `AssetContractRelationship` → `Contract.COLA_Override_Percent__c`, `COLA_Override_Persist_Until__c`, `Contract.Status='Activated'`; `COLA_Uplift_Rules__mdt`; `MyCAP_Rules__mdt.getInstance('Global')`; `AttributeDefinition('PS_Service_Type')`/`AttributePicklistValue('Prepaid')`/`QuoteLineItemAttribute` for prepaid bypass.

**Explicitly NOT written** (class docstring 16–18; calculator 295–298): `COLAUpliftPercent__c` / `COLA_Uplift_Percent__c`, `COLAExplainer__c`, `COLAApplied__c` — context-only / not hydration-mapped; including them silently fails the whole `updateContextAttributes` batch. `COLA_Uplift_Percent__c` is synced instead by the `COLAUpliftHandler` trigger.

#### 4. Context mappings
- **Node addressing:** each write targets a node built from `dataPath.clone()` with element `[0]` removed (`updatePath.remove(0)`), packaged as `nodePath => {dataPath: updatePath}` with an `attributes` list — the standard RCA `nodePathAndAttributes` shape submitted to `updateContextAttributes`.
- **Target objects:** the written `attributeName`s map to Quote-side `SalesTransactionContextExt` attributes that hydrate back onto **QuoteLineItem** (`COLACalculatedPrice__c`, `Pre_COLA_Price__c`, `COLA_Source__c`, `COLA_Applied_Date__c`, `COLA_Solution_Category__c`) and to native pricing fields (`NetUnitPrice`, `PartnerDiscountPercent`, `Discount`). Final-year compounding is derived downstream by the QLI formula field `Final_Year_COLA_Calculated_Price__c` (year-1 only computed here). `Quote.Mycap__c` cannot be written from a QLI pricing context, so it is deferred to the `MyCAPFlagApplier` **Queueable** (Quote DML does not re-trigger pricing → no reprice loop).
- **Registration:** bound via **ORG CONFIG** (`ProcedurePlanOption` / signal binding on `Rev_Mgmt_Default_Pricing_Procedure`), **not** in the ESD XML or git — same mechanism as the partner prehook (bound on `ProcedurePlanOption 1FYWC0000002W3r4AE`). The specific ProcedurePlanOption Id binding this COLA prehook is **not determinable from these files** and must be read from the org.

#### 5. Key risks / notes
- **Uncommitted calculator edits.** `COLAUpliftCalculator.cls` and `RenewalMaintenanceColaCalculator.cls` have working-tree changes not yet committed. Most are docs, but `RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet` now **delegates** its fresh-uplift branch to `COLAUpliftCalculator.computeStampedMaintenanceColaNet` — claimed byte-identical (parity test cited) but unverified in-org until committed/deployed. `COLAUpliftCalculator.cls` also ends with **no trailing newline** (`\ No newline at end of file`).
- **V23/V24 both Active.** You are documenting V24, but the org has both V23 and V24 active (open cleanup item); the hook binding must point at the intended version or COLA may run under the wrong procedure.
- **Fail-open by design.** `execute` always returns `SUCCESS`, even on exception (lines 108–110) and on Order/blank-context guards, so COLA silently degrades rather than blocks pricing — D-18 `PricingHookLogger.logPrehook` is the only surface for a swallowed failure. Same fail-open in `isOrderTransaction` (returns false ⇒ treats as Quote) and `getContractOverrides` (empty map on QueryException).
- **Idempotency / recursion.** Static `isProcessing` guard skips re-entrant invocations within a transaction; `pendingNetUnitPriceUpdates` is re-initialized per `processLineItems` call. NetUnitPrice seed is guarded to only fire when stored net is null/≤0, so a repriced/discounted net is not clobbered — but the audit writes (`COLACalculatedPrice__c` etc.) and `COLA_Applied_Date__c = now()` are re-stamped every run.
- **Ordering.** COLA reads `Default_COLA_Uplift_Percent__c` stamped by the `COLAUpliftHandler` trigger; the code notes a **timing gap** (MyCAP section lines 987–992, 1066–1072) where `IsCOLAOverridden__c` isn't set until the trigger fires *after* pricing write-back, so override detection compares context `COLA_Uplift_Percent__c` against persisted default as a fallback. Maintenance nets are intentionally left to the SC-3346 path (`appendStampedRenewalMaintenanceUpdates`), not the NetUnitPrice seed — cross-hook contract that must be preserved.
- **Dead-code caution.** `buildCOLAContextUpdate` (both hook seam and calculator) reverse-derives Pre-COLA from `UnitPrice`; the MyCAP loop comment (D-COLA-6, lines 1102–1116) warns it was removed because it violated the base-price-invariant and must **not** be re-wired without sourcing Pre-COLA from the Asset price.


### HardwareAttributePricingPrehook (PREHOOK)

#### 1. Purpose
Apex **Before Hook** (`implements RevSignaling.SignalingApexProcessor`, `execute(RevSignaling.TransactionRequest)`) that applies **hardware attribute-based pricing for Power (iSeries) products**. Class header states it "Executes AFTER List Price lookup and BEFORE Regional/Partner Pricing in the waterfall" and "Only applies to Power products or products with hardware linkage." It is a **prehook** — it mutates the in-flight `SalesTransactionContext` (via `Context.IndustriesContext.updateContextAttributes`) so downstream native pricing and later hooks consume the adjusted `UnitPrice`; it does not persist SObjects directly. It fires on both quote and order interactions (it operates purely on `SalesTransactionItem` context nodes, agnostic to Quote vs Order), on native Reprice/price-recalc.

The formula (header + `HardwarePricingCalculator.calculate`):
`Hardware_Price = List_Price × pGroup_Multiplier × userTier_Multiplier × (1 − systemType_Discount/100)`, then `.setScale(2, HALF_UP)`.

Attribute resolution is a 3-tier override priority (v3.0), evaluated **per attribute** in `processLineItem`:
1. **Configurator** — `QuoteLineItemAttribute` value from `SalesTransactionItemAttribute` context tag
2. **Hardware Default** — the linked `Hardware__c` record's field
3. **System Default** — constants `DEFAULT_PGROUP='P20'`, `DEFAULT_SYSTEM_TYPE='Production'`, `DEFAULT_USERS=1`

#### 2. Modifications made (with reasons)

| Change (code-level) | Reason / ticket | Status |
|---|---|---|
| **Extract `HardwarePricingCalculator` delegate** (commit `9a814b0`, Wave-2 hook-thinning round 3). `processLineItem` no longer computes math inline; it calls `HardwarePricingCalculator.calculate(currentPrice, pGroup, usersPerPartition, systemType)` (hook line ~631) returning `HardwarePriceResult` (pGroupMultiplier/userTierMultiplier/systemTypeDiscount/combinedMultiplier/adjustedPrice). The old `getPGroupMultiplier`/`getUserTierMultiplier`/`getSystemTypeDiscount` remain on the hook **only as thin `@TestVisible public` wrappers** delegating to the calculator (preserve existing test API). | Hook-thinning: adapter-over-testable-service. Hook = RCA context adapter; calculator = pure input/output. | Committed |
| **D-14: hardcoded tables → `Hardware_Attribute_Pricing__mdt`.** Inside the calculator, the three tables (pGroup multipliers, user-tier bands, system-type discounts) are read from the admin-editable Custom Metadata Type via `Hardware_Attribute_Pricing__mdt.getAll().values()` in `ensureLoaded()` (lazy, once per transaction — `getAll()` not SOQL, to avoid governor cost in the SC-3447-sensitive waterfall). Rows discriminated by `Table_Type__c` ∈ {`pGroup`,`UserTier`,`SystemType`}; keyed by `Attribute_Key__c` / banded by `Min_Users__c`,`Max_Users__c`; value in `Value__c`. Seeded byte-for-byte from prior hardcode (verified: P30=1.5, Staging=25.0, UserTier 501+ = 3.0). | D-14: admin-editable hardware tables; SDD §8 Rules 2/3/4. | Committed (16 `customMetadata/Hardware_Attribute_Pricing.*` records: 7 pGroup, 6 UserTier, 3 SystemType) |
| **SDD-compliance: source label + open-ended top band** (commit `173431a`). Source constant is `SOURCE_CONFIGURATOR='Configurator'` (header comment notes this replaced legacy non-SDD-valid `'User Override'`; SDD §8 Rule 5). Written to `Hardware_Pricing_Source__c` as the single dominant tier. Open-ended top user band: `UserTierRange.maxUsers == null` treated as no upper cap (SDD §8 Rule 3: 501+ = 3.0×) in `getUserTierMultiplier`. | SC-3468 / Hardware SDD §8 Rules 3 & 5. | Committed |
| **D-18: exception observability** (commit `7876aa0`). `execute` catch block adds `PricingHookLogger.logPrehook('HardwareAttributePricingPrehook', contextId, e)` — fire-and-forget, never throws, status still returned `SUCCESS`. | D-18 pricing-hook exception logging. | Committed |
| **Recursion guard** `private static Boolean isProcessing` — re-entrant `execute` returns early with `'Hardware pricing skipped (re-entrant call)'`. | Prevent context-write re-triggering pricing recursion (normalized to other prehooks). | Committed |
| **Calculator javadoc reformat** — working-tree diff on `HardwarePricingCalculator.cls` converts block comments to `@description/@param/@return` javadoc and changes `@author` to Liam Jeong. **No behavior change** (also drops trailing newline). | Doc hygiene. | **Uncommitted** (working tree) |

Note: the hook `.cls` itself has **no uncommitted changes**; all hook modifications are in committed history. SC-3468 (Model Number) surfaces here as `hardware.Model_Number__c` read into `detail.model` (audit only — model does not drive the multiplier). SC-3423 (HW Group) is the upstream `Hardware__c`/pGroup source; not directly referenced in this class.

#### 3. Context elements (read / write)

| READS (context inputs) | WRITES (context outputs) |
|---|---|
| `SalesTransactionItem` tag — queried via `industriesContext.queryTags` | `UnitPrice` — adjusted (rounded) price, consumed downstream |
| `Hardware_Id__c` (per line, `getStringFromTag`) → lookup `Hardware__c` | `Pre_Hardware_Price__c` — original `currentPrice` |
| `ProductId` (`getStringFromTag`) | `Hardware_Price_Multiplier__c` — `combinedMultiplier` |
| `ListPrice` (`getDecimalFromTag`) — primary price | `Hardware_Pricing_Applied__c` — `true` flag |
| `UnitPrice` (`getDecimalFromTag`) — fallback when ListPrice null; `currentPrice = listPrice != null ? listPrice : unitPrice` | `Hardware_Pricing_Source__c` — dominant tier (`Configurator`/`Hardware Default`/`System Default`) |
| `SalesTransactionItemAttribute` tag — `queryConfiguredAttributes` | `pGroup_Applied__c` — resolved pGroup |
| per-attr: `ParentReference` (or dataPath[n-2]), `Attribute`/`AttributeKeyName`, `AttributeValue` | `System_Type_Applied__c` — resolved systemType |
| configured attr keys: `Pgroup`, `Server_Type`, `Users` (const `ATTR_PGROUP`/`ATTR_SERVER_TYPE`/`ATTR_USERS`) | `Users_Per_Partition_Applied__c` — resolved user count |
| `Hardware__c` SOQL: `P_Group_List__c`, `Server_Type__c`, `Users_Per_Partition__c`, `Model_Number__c`, `Name` | `Hardware_Pricing_Detail__c` — `JSON.serialize` audit (version `v3.0`, per-attr value+source, multipliers, price calc) |
| `Hardware_Attribute_Pricing__mdt`: `Table_Type__c`, `Attribute_Key__c`, `Min_Users__c`, `Max_Users__c`, `Value__c` (via calculator) | `HardwareCalculatedPrice__c` — adjustedPrice (primary value consumed by Pricing Procedure Assignment element) |
| | `HardwarePricingExplainer__c` — human-readable string (`buildHardwareExplainerText`, e.g. `Hardware: Group: P30, 50 Users, Mult: 1.50`) |

#### 4. Context mappings & registration
- Reads/writes target the **`SalesTransactionItem` node**. Writes are assembled as `attributeName`/`attributeValue` pairs into a `nodeUpdate` with `nodePath.dataPath = updatePath` (the item's `dataPath` **minus its first element** — `updatePath.remove(0)`), submitted in one batch via `ctx.updateContextAttributes({contextId, nodePathAndAttributes})`.
- Line-item↔attribute join: configured attributes keyed by `parentLineItemId`, derived from `ParentReference` tag, falling back to `dataPath[size-2]`. Line-item id from `dataPath[size-1]`.
- These context fields map onto the corresponding QuoteLineItem/OrderItem (and QuoteLineItemDetail) custom fields of the same API name once the context flushes; `UnitPrice`/`HardwareCalculatedPrice__c` feed the native pricing-procedure Assignment element, so the adjusted price flows into standard downstream pricing.
- **Registration is ORG CONFIG, not in git.** Like the partner prehook (bound on `ProcedurePlanOption 1FYWC0000002W3r4AE`), this hook is wired to `Rev_Mgmt_Default_Pricing_Procedure` **V24** via a ProcedurePlanOption / signal binding — **not** in the ESD XML or this repo. The specific ProcedurePlanOption Id for this hook could **not be determined from the files provided**; confirm in-org before the meeting.

#### 5. Key risks / notes
- **Dual-active procedure versions:** both **V23 and V24 are Active** on `Rev_Mgmt_Default_Pricing_Procedure` (activated 2026-07-10) — open cleanup item; confirm the hook binding is on the intended (V24) version so it doesn't double-apply or drift.
- **Uncommitted calculator diff:** `HardwarePricingCalculator.cls` has working-tree changes (javadoc-only, no behavior change, plus a dropped trailing newline). Commit or revert before deploy to avoid a source-drift surprise; the hook `.cls` itself is clean.
- **Ordering:** self-declared to run after List Price and before Regional/Partner pricing. It **overwrites `UnitPrice`** in context, so any earlier price signal is replaced by hardware-adjusted price; downstream Regional/Partner hooks must layer on top of this value. Ordering is enforced only by the org-config binding sequence, which is not visible in git — verify sequence vs Partner/Regional prehooks.
- **Idempotency:** recomputes deterministically from source attributes and always sources `currentPrice` from `ListPrice` first (not from a previously-written `UnitPrice`), so re-runs are stable **as long as `ListPrice` is present**. If only `UnitPrice` is available on a re-run, `currentPrice` reads the already-adjusted value → **potential compounding** on repeated repricing. Recursion within a single transaction is guarded by `isProcessing`.
- **Silent degrade:** all failures are swallowed — `queryConfiguredAttributes` returns empty map on error (falls back to Hardware/system defaults), `submitContextUpdates` swallows "not in updatable state", and `execute` catches everything returning `SUCCESS`. D-18 `PricingHookLogger` is the only observability; a genuine misprice can pass as green.
- **Seed integrity (D-14):** correctness now depends on the 16 admin-editable `Hardware_Attribute_Pricing__mdt` rows. Any admin edit silently changes pricing; lookup-miss defaults (`1.0` multiplier / `0` discount) mean a mistyped/removed key yields list price, not an error.
- **Model number (SC-3468)** is captured for audit only (`Hardware_Pricing_Detail__c.model`); it does not participate in the multiplier — do not represent it as price-driving.


I have everything needed. Producing the dossier section.

### PartnerPricingPrehookV2 (PREHOOK)

**1. Purpose**

Apex before-hook (`global class PartnerPricingPrehookV2 implements RevSignaling.SignalingApexProcessor`, `execute(RevSignaling.TransactionRequest)` → `RevSignaling.TransactionResponse`) that applies partner pricing to each line inside the RCA/RLM pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` (documented for active runtime **V24**). Per the class header it runs **AFTER Regional Pricing and BEFORE COLA**; it reads the post-Regional price and captures it as `Pre_Partner_Price__c`. It fires on any native reprice of a SalesTransaction context (Quote path — it reads the `SalesTransaction`/`SalesTransactionItem` tags and writes back via `updateContextAttributes`; there is no order-specific branch in the code). Two models are supported (header + `PartnerMarginDispatcher`):
- **Guaranteed Margin (ADDITIVE):** `List x (1 - SUM(all partner margins%))` across Billing + Reseller + Distributor + Referral partners (`PartnerPricingServiceV2.calculateGuaranteedMarginPrice`, caps total at 100%).
- **Discount:** `List x (1 - Billing Partner's Discount%)` (`calculateDiscountPrice`), billing partner only.

Fail-safe by design: every guard and the outer `catch` return `RevSignaling.TransactionStatus.SUCCESS` (never `FAILED`, which could block the procedure). A static `isProcessing` flag prevents re-entrancy. "V2 = 0% on null" is realized in `PartnerPricingServiceV2.getMarginForProductType`/`effectivePct` (return `0` when model/productType blank, or when both preferred and fallback percents are null).

**2. Modifications made (with reasons)**

The hook is a **thin adapter**: `execute` orchestrates context I/O; all pricing logic is delegated to extracted, SOQL-free calculator/helper classes. Recent history (all **committed**; the hook `.cls` has **no uncommitted working-tree change**):

| Change (code-level) | Reason / ticket | Status |
|---|---|---|
| `fc10b70` **D-11 complete — unify partner margin to V2 (deal-aware).** Margin lookup routed through `PartnerPricingServiceV2.getMarginForProductType(model, productType, dealType)`; `dealType` threaded from `quoteData.dealType` through `PartnerMarginDispatcher.resolve(...)`. `useNonOriginating = dealType == DEAL_TYPE_FORTRA_ORIGINATED` selects `Non_Orig_*_Pct__c` vs standard `*_Percent__c`, with `effectivePct` catalog-fallback (E-04). | D-11 unify partner margin; deal-aware net (SC-3359/SC-3384) | Committed (service) |
| `af3a470` **Round-6 SDD reconciliation.** Adds `Result.warning` (D-PARTNER-1/BR-007: participating partner configured but no matching model → `'Missing partner pricing model for: …'`); blank-ctx guard returns SUCCESS not FAILED (D-PARTNER-6/TR-004). | Partner SDD §6.3 conformance | Committed |
| `7876aa0` **D-18 exception logging.** `catch` now calls `PricingHookLogger.logPrehook('PartnerPricingPrehookV2', request.ctxInstanceId, e)` (fire-and-forget, never throws, status unchanged). | D-18 observability | Committed |
| `53823da` **Extract `PartnerMarginDispatcher`** (round-4 incr 3). `processLineItem` Discount/Guaranteed dispatch + margin-detail map build moved to pure `PartnerMarginDispatcher.resolve(...)`; hook threads `QuoteHeaderData` fields as primitives. | Hook-thinning (Wave-2) | Committed |
| `6a6f929` **Extract `PartnerParticipationResolver`** (round-2 incr 2). `collectPartnerIds` and `getPartnerRole` now delegate. | Hook-thinning | Committed |
| `73eae78` **Extract `PartnerPricingPayloadBuilder`.** `processLineItem` builds the context-attribute list via `PartnerPricingPayloadBuilder.buildPartnerPricingAttributes(...)`. | Hook-thinning | Committed |
| `2fe19e7` **De-dup `resolveBasePrice` → `PartnerNetResolutionCalculator.resolvePreProcedurePrice`** (incr 10; "byte-identical"). | Shared calculator extraction | Committed |
| `c349bef` **De-dup tag helpers → `ContextTagReader`** (incr 9). `extractFieldValue`/`getStringFromTag`/`getDecimalFromTag`/`getIdFromTag` now delegate. | Shared reader extraction | Committed |

Delegate calculators named in scope:
- **`PartnerNetResolutionCalculator`** — pure. `resolvePreProcedurePrice(regionalNet, unit, list)` = first-positive precedence **RegionalNetUnitPrice → UnitPrice → ListPrice**; this is the hook's `resolveBasePrice`. (Also exposes `resolveCommercialUnitPrice`, used by `PartnerNetPricePosthook`, not by this hook.) **Working-tree change = javadoc/`@author` only, no behavior change** (uncommitted).
- **`SequentialDiscountCalculator`** — pure `applyDiscountPercent(base, percent)` = `base x (1 - percent/100)` scale-2 HALF_UP, no-op on null/≤0. **NOT referenced by this prehook** — consumed only by `PartnerNetPricePosthook`. Working-tree change = javadoc/`@author` only (uncommitted).
- `PartnerMarginDispatcher` working-tree change = javadoc/`@author` only (uncommitted); no logic delta.

**3. Context elements**

Reads via `Context.IndustriesContext.queryTags` (tags `SalesTransaction`, `SalesTransactionItem`) → unwrapped through `ContextTagReader`; writes via `updateContextAttributes` (`nodePathAndAttributes` → `nodePath.dataPath` + `attributes`), payload from `PartnerPricingPayloadBuilder`.

| READS (input tag/field) | WRITES (output attribute) |
|---|---|
| `SalesTransaction`: `Id` (also from `dataPath[1]`), `Billing_Partner__c`, `Partner_Pricing_Model__c`, `Deal_Type__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c` | `Pre_Partner_Price__c` (= currentPrice, post-Regional base) |
| `SalesTransactionItem`: `_recordId` (from `dataPath` last elem) / `SourceRecordId` / `Id`; `RegionalNetUnitPrice__c`, `UnitPrice`, `ListPrice` (base-price resolution) | `Partner_Adjusted_Price__c` (= adjustedPrice) |
| `SalesTransactionItem`: `Fortra_Product_Type__c`, `Unit__c`, `Solution_Group__c`, `Solution_Category__c` (model selection / margin-by-product-type) | `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c` (`'System Calculated'`) |
| | `Partner_Margin_Detail__c` (JSON audit of partnerId/name/role/marginPercent) |
| | `Partner_Discount_Percent__c` (= totalPercent), `PartnerDiscountPercent`, `PartnerUnitPrice` (= adjustedPrice) |
| | `NetUnitPrice` + `UnitPrice` (= adjustedPrice) — **only when `totalPercent > 0`** (forces OneTime/Perpetual lines; RLM auto-propagates `PartnerUnitPrice`→NetUnitPrice for TermDefined only) |
| | `Partner_Pricing_Warning__c` (D-PARTNER-1 missing-model message or null) |

Base-price precedence note: `resolveBasePrice` prefers `RegionalNetUnitPrice__c` first because Regional Pricing writes there, not to `UnitPrice`. Lines with resolved `currentPrice == null || <= 0` are skipped (return null → no update).

**4. Context mappings**

- Header fields map QuoteLineItem/Quote custom fields → the `QuoteHeaderData` DTO (`billingPartnerId`, `partnerPricingModel`, `dealType`, `resellerId`, `distributorId`, `referralPartnerId`); `hasPartnerPricing()` requires non-null `Billing_Partner__c` **and** non-blank `Partner_Pricing_Model__c`, else `clearPartnerPricingFields` nulls all outputs (see idempotency below).
- Writes target the **SalesTransactionItem** node (`nodePath.dataPath` = original `dataPath` minus the context-instance-id first element); these context attributes map to the QuoteLineItem/QuoteLineItemDetail fields of the same API name (`Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, etc.) plus the standard RLM `NetUnitPrice`/`UnitPrice`/`PartnerUnitPrice`/`PartnerDiscountPercent`.
- **Registration is ORG CONFIG, not in git / not in the ESD XML.** It is bound as a pricing-procedure plugin via a signal binding on **`ProcedurePlanOption 1FYWC0000002W3r4AE`** (the partner-prehook binding). The `.cls-meta.xml` shows only `apiVersion 65.0`, `status Active` — no procedure wiring. The invocation slot (post-Regional, pre-COLA) is asserted by the class header and confirmed by its read of `RegionalNetUnitPrice__c`; the exact ordering guarantee lives in the procedure/plan config, not verifiable from these files.

**5. Key risks / notes**

- **V23+V24 both Active** in the org (open cleanup item) — confirm which plan option the `1FYWC0000002W3r4AE` binding resolves to at runtime before attributing behavior to V24.
- **Idempotent / stale-clear:** on empty partner config or empty partner-id set, the hook nulls the full output field list (`Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, `Partner_Discount_Percent__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c`, `Partner_Margin_Detail__c`, `Partner_Pricing_Warning__c`, `PartnerUnitPrice`, `PartnerDiscountPercent`). Note the clear list does **not** include `NetUnitPrice`/`UnitPrice`, which the success path stamps — so a prior partner-adjusted `NetUnitPrice`/`UnitPrice` is not reverted by the clear path (relies on native reprice re-seeding those).
- **Ordering dependency:** correctness hinges on running after Regional (reads `RegionalNetUnitPrice__c`) and before COLA. If the plan-option order changes, the base-price resolution silently falls back to `UnitPrice`/`ListPrice`.
- **Uncommitted:** only doc/`@author` edits on `PartnerMarginDispatcher`, `PartnerNetResolutionCalculator`, `SequentialDiscountCalculator` are in the working tree — **no behavioral uncommitted change**; the hook `.cls` itself is clean.
- **`SequentialDiscountCalculator` is not in this hook's path** (posthook-only) — do not attribute prehook discount math to it; prehook discount/margin math is `PartnerPricingServiceV2.calculateDiscountPrice` / `calculateGuaranteedMarginPrice`.
- Failures are swallowed to SUCCESS by design; the only signal on degrade is the D-18 `PricingHookLogger.logPrehook` event, so a mis-bound hook fails silently in pricing output.
- `Non_Orig_*_Pct__c` fields are read only inside the `useNonOriginating` branch (ternary short-circuit), so a deal-blind SOQL that omits them avoids `SObjectException` — a fragile coupling worth noting if the service query changes.


### RegionalServicesPricingPrehook (PREHOOK)

**Class:** `RegionalServicesPricingPrehook.cls` (API 64.0, `<status>Active</status>`; header self-labels `@version 13.3`). Delegate: `RegionalPricingCalculator.cls`. Both under the active runtime procedure `Rev_Mgmt_Default_Pricing_Procedure` V24.

#### 1. Purpose
Applies a **country-level regional multiplier to the LIST/base price** of services lines and writes the adjusted value back into the pricing context as `UnitPrice`, so downstream waterfall steps compute net off the regionalized base (net itself stays catalog — no net override written here). Implements `RevSignaling.SignalingApexProcessor.execute(RevSignaling.TransactionRequest)` returning a `RevSignaling.TransactionResponse`. It runs as a **PREHOOK** — it mutates context *before* the native pricing steps via `industriesContext.updateContextAttributes(...)`, so its `UnitPrice` write is "available to subsequent pricing steps in the waterfall" (per the inline comment at line 304). Fires on native Reprice. It reads the header via the `SalesTransaction` tag and lines via `SalesTransactionItem`, so it operates on both quote and order transactions (whatever context the runtime hydrates); nothing in the code branches on quote-vs-order. `response.status` is **always `SUCCESS`** — every failure path degrades to a message string, never a hard error.

Control flow in `execute` (lines 48–78): load multipliers → build `Context.IndustriesContext` → `getShippingCountry` → `getMultiplierForCountry` → **short-circuit if `multiplier == DEFAULT_MULTIPLIER` (1.0)** (line 70, "uses default multiplier (1.0)", no lines touched) → else `processLineItems`.

#### 2. Modifications made (with reasons)

| Change (code-level) | Reason / ticket | Commit / state |
|---|---|---|
| **Wave-2 thin-hook extraction**: `getMultiplierForCountry` and `calculateAdjustedPrice` bodies moved out to new `RegionalPricingCalculator`; hook now holds thin wrappers (`return RegionalPricingCalculator.getMultiplierForCountry(...)` L134, `return RegionalPricingCalculator.calculateAdjustedPrice(...)` L385) that "preserve the existing test API." Adapter (hook) = context I/O; delegate (`RegionalPricingCalculator`) = pure math (`CEILING((listPrice x multiplier)/5) x 5`). | Refactor plan §5.1 "thin hook = adapter over testable service" | `0df19e7` — committed |
| **Effective dating**: `loadRegionalPricingMultipliers` SOQL now `WHERE Is_Active__c = true` on `Services_Regional_Pricing__mdt`, then filters in-memory `if (!RegionalPricingCalculator.isEffectiveOn(record.Effective_Start_Date__c, record.Effective_End_Date__c, today)) continue;` (L118). `isEffectiveOn` uses inclusive bounds; null start/end = unbounded (both null always loads = prior behavior). Comment notes CMDT SOQL "rejects OR disjunctions," hence in-memory eval. | SDD Rule 14 / BR-007 (regional services, SC-3374/SC-3393 theme) | `8d1ec19` — committed |
| **A-6 null-multiplier guard** (in delegate): `getMultiplierForCountry` changed from `containsKey ? get : DEFAULT` to `Decimal multiplier = multipliers.get(country); return multiplier != null ? multiplier : DEFAULT_MULTIPLIER;` — an Active row with null `Multiplier__c` now resolves to 1.0 so the hook's default short-circuit **skips** the line rather than "adjusting a price off a null." Commit notes "provably 0-delta today (0 live rows have a null Multiplier__c)." | A-6 null-mult guard | `3a338ec` — committed (same commit carries **D-15** currency-map→`Country_Currency_Map__mdt`, but that lives in `CurrencySelectionService`, **not** this hook) |
| **D-18 exception logging**: in `execute` catch block, added `PricingHookLogger.logPrehook('RegionalServicesPricingPrehook', contextId, e);` (L84) — "fire-and-forget; never throws; status unchanged." | D-18 observability | `7876aa0` — committed |
| **Doc-only reformat of `RegionalPricingCalculator`**: javadoc rewritten to `@description/@param/@return`, `@author Liam Jeong` added, trailing newline dropped. **No behavior change** (bodies identical). | Documentation | **UNCOMMITTED** working-tree edit on `RegionalPricingCalculator.cls` (`git status: M`). Hook `.cls` itself has **no** uncommitted changes. |

#### 3. Context elements (read / write)

| READS (inputs) | WRITES (outputs) |
|---|---|
| **Header** via `queryTags` tag `SalesTransaction` → `parseShippingCountry`: `getStringFromTag(tagMap,'ShipToPlace_Country__c')`, fallback `getStringFromTag(tagMap,'ShippingCountry')` (L181/187) | Per-line context-node attributes (via `updateContextAttributes`, built in `buildNodeUpdate`): |
| **Lines** via `queryTags` tag `SalesTransactionItem` → per node `getDecimalFromTag(tagMap,'ListPrice')`, `getDecimalFromTag(tagMap,'UnitPrice')` (currentPrice = ListPrice ?? UnitPrice, L262), `getStringFromTag(tagMap,'ProductId')` (L264) | `UnitPrice` = regionalPrice (the load-bearing waterfall write, L305) |
| Node `dataPath` (L256; first element dropped to make path relative, L295–298) | `RegionalNetUnitPrice__c` = regionalPrice ("audit field for TLE display", L311) |
| **CMDT** `Services_Regional_Pricing__mdt`: `Country__c`, `Country_Code__c`, `Multiplier__c`, `Effective_Start_Date__c`, `Effective_End_Date__c`, `Is_Active__c` (L112–117) | `PrehookRSNetUnitPrice__c` = regionalPrice (Assignment-element input, L319) |
| | `RegionalPricingExplainer__c` = `'Regional Services Multiplier: ' + multiplier.setScale(2) + ' (' + country + ')'` (L325) |
| | `RegionalPricingApplied__c` = `true` (flag for conditional Assignment, L332) |
| | `Pre_Regional_Price__c` = currentPrice (original pre-adjust price, L338) |
| | `Regional_Multiplier__c` = multiplier (L344) |

Skip rule: a line with `currentPrice == null || currentPrice <= 0` is skipped (`buildItemUpdates` L267), so no attributes are written for it.

#### 4. Context mappings
- **Input mapping:** header country sourced first from the Places-model field `ShipToPlace_Country__c`, else legacy `ShippingCountry`; line base price from context `ListPrice` (preferred) else `UnitPrice`. Country string is looked up in the CMDT-derived `Map<String,Decimal>` keyed by **both** `Country__c` and `Country_Code__c` (L121–126), so either a full name or an ISO code resolves.
- **Output mapping:** all writes are context-node attribute updates on the line's own `dataPath` (relative path after dropping root segment). `UnitPrice` is the only field that feeds the native pricing math forward; `RegionalNetUnitPrice__c`, `PrehookRSNetUnitPrice__c`, `RegionalPricingExplainer__c`, `RegionalPricingApplied__c`, `Pre_Regional_Price__c`, `Regional_Multiplier__c` are audit / waterfall-visibility / Assignment-driver fields surfaced on the QuoteLineItem/OrderItem (and TLE display). The code writes to **context nodes**, not directly to SObjects — mapping to QuoteLineItem/OrderItem/QuoteLineItemDetail columns is via the context definition's field mapping, which is **not in these files**.
- **Registration:** as a `RevSignaling.SignalingApexProcessor` plugin, this hook is bound to the pricing procedure via **org config (ProcedurePlanOption / signal binding), not in git or the ESD XML** (same mechanism as the partner prehook on `ProcedurePlanOption 1FYWC0000002W3r4AE`). The specific `ProcedurePlanOption` Id for this hook is **not determinable from the source files** — confirm in the org.

#### 5. Key risks / notes
- **Idempotency / recursion:** static `isProcessing` guard (L17,40–46) short-circuits re-entrant calls. But the write is **not mathematically idempotent**: it computes `regionalPrice` from `currentPrice = ListPrice ?? UnitPrice`, then overwrites `UnitPrice`. If the hook re-runs in a context where `ListPrice` is absent and it reads the already-adjusted `UnitPrice` as the base, it would re-multiply and re-round. Safety depends on `ListPrice` remaining present each pass (and `Pre_Regional_Price__c` is written but never read back as a re-entry guard).
- **Rounding is $5-CEILING**, not a pure multiply: `(rawPrice/5).setScale(0, CEILING) * 5`. Always rounds *up*; for multiplier > 1 this can add up to ~$5 beyond the raw regional value. Multiplier is displayed at 2 decimals in the explainer but applied at full precision.
- **Silent-degrade contracts (intentional, preserved byte-for-byte per code comments):** `getShippingCountry` swallows any `queryTags` failure → returns null → "No shipping country found" (still SUCCESS). `submitContextUpdates` swallows only errors containing `'not in updatable state'` and **re-throws** anything else up to `execute`'s outer catch. `execute` never returns non-SUCCESS; failures only appear in `response.message` and (since D-18) via `PricingHookLogger.logPrehook`. A meeting risk: a broken regional adjustment can pass as green.
- **Ordering:** as a prehook writing `UnitPrice`, it must run before native list/net steps and before any other hook that reads `UnitPrice` as its base (e.g., partner net). Relative ordering vs other bound prehooks is defined in **ProcedurePlanOption config, not in code** — cannot be confirmed from these files.
- **Two active versions:** V23 and V24 are both Active on the procedure (open cleanup item); ensure the meeting confirms which version's plugin bindings are live.
- **Uncommitted state:** the only working-tree change is the doc-only edit to `RegionalPricingCalculator.cls` (no behavioral delta; also drops the file's trailing newline). The hook class and all A-6/D-15/D-18/effective-dating logic are **committed**.


### QLDescriptionGeneratorPrehook (PREHOOK)

**Files:** `force-app/main/default/classes/QLDescriptionGeneratorPrehook.cls` (thin hook, API 65.0, `status=Active`) → delegates pure logic to `force-app/main/default/classes/QLDescriptionCalculator.cls` (API 64.0, `status=Active`, `public with sharing`). Class doc self-labels `@version 8.0` / `@author Marc DeBrey`.

#### 1. Purpose
Auto-generates `QuoteLineItem.Description` during Quote pricing by concatenating the product name plus up to 10 configuration-attribute segments into a single `" | "`-separated string. Implements `RevSignaling.SignalingApexProcessor`; entry point `execute(RevSignaling.TransactionRequest request)` returns a `RevSignaling.TransactionResponse` (cls:283). It is a **prehook** and is explicitly documented to run **LAST** in the Quote pricing prehook chain (cls:67). Fires on Quote pricing runs only — a hard scope guard (`isQuoteLineSet`, cls:316/370) bails with SUCCESS if the first line Id is not `QuoteLineItem.SObjectType`, because "Orders do not allow product/configuration changes after conversion, so Description is fixed at conversion time" (cls:62-65). It does not compute price; it only writes descriptive text, so it is order-independent w.r.t. the numeric pricing hooks except that it must run after configuration is settled.

#### 2. Modifications made (with reasons)

| Change | Code-level detail | Reason / theme | Status |
|---|---|---|---|
| **Hook thinning — Calculator extraction** | commit `9383f8f` "refactor(pricing): extract QLDescriptionCalculator from QLDescriptionGeneratorPrehook (Wave-2 thinning)". All pure logic (`buildDescription`, `computeUnitTypeSegment`, `resolveUnitQuantity`, `buildContextUpdate(s)`, `parseConfiguredAttributes`, `parseLineItemDataPaths`, `getStringFromTag`/`extractFieldValue`) moved byte-verbatim into `QLDescriptionCalculator`. The hook keeps only context I/O (`queryTags`/`updateContextAttributes`), SOQL (`Product2.Name`, `QL_Description_Attribute__mdt`), and the `ResolvedConfig` type/config-builders, delegating via thin `@TestVisible` seams (e.g. cls:420, 446, 593). | Wave-2 hook-thinning: make pure assembly unit-testable with hand-built maps without a live RCA context. | Committed |
| **D-18 exception logging (hook)** | commit `7876aa0`. In `execute()` catch, added `PricingHookLogger.logPrehook('QLDescriptionGeneratorPrehook', request.ctxInstanceId, e)` (cls:350) — fire-and-forget, never throws, response stays SUCCESS-with-warnings. | D-18 observability: surface the swallowed degrade path. | Committed |
| **D-18 logging (calculator, working tree)** | Uncommitted diff on `QLDescriptionCalculator.cls`: adds `ExceptionLogger.log('QLDescriptionCalculator', null, new DescriptionGenerationException(...))` inside the two `Id.valueOf` catch blocks — `parseConfiguredAttributes` bad-parent-ref (calc:267) and `parseLineItemDataPaths` bad-last-element (calc:333). Also adds `@author Liam Jeong`, full `@param`/`@return` javadoc, and drops the trailing newline. | Extends D-18 logging into the extracted parser catches; pure doc/observability, no behavior change. | **Uncommitted** |
| **SC-3349 lineage (historical, pre-`44738b2`)** | The `Number_of_Units` fallback (`NUMBER_OF_UNITS_ATTR = 'Number_of_Units'`, cls:156) feeding `resolveUnitQuantity` (calc:115-130) is the SC-3349 line-description unit-count fix. Version history in the header: v5 "Unit Quantity from configuration attribute", v6 "applies to ANY Unit Type", v8 prepends Product Name. | SC-3349: read unit count from a config attribute (Attribute_Volume, else Number_of_Units) — never `QuoteLineItem.Quantity`. | Committed (predates git window; base commit `44738b2` "Jun 267 works") |

Thin-hook vs delegate: `QLDescriptionGeneratorPrehook` is the RevSignaling adapter (context orchestration + SOQL + registration surface); `QLDescriptionCalculator` is the plain-in/plain-out string/payload assembler with **no** SOQL/DML/context dependency (calc:2-11).

#### 3. Context elements

| READS (inputs) | WRITES (outputs) |
|---|---|
| `queryTags` tag `'SalesTransactionItem'` → each line's `dataPath` + Id (`queryLineItemDataPaths`, cls:493; parsed `parseLineItemDataPaths`, calc:294 — Id from `dataPath[last]`) | `updateContextAttributes` with `nodePathAndAttributes` (`submitContextUpdates`, cls:616-634) |
| `queryTags` tag `'SalesTransactionItemAttribute'` → per attribute node: `ParentReference` (fallback `dataPath[size-2]`), `Attribute` (fallback `AttributeKeyName`), `AttributeValue` (`parseConfiguredAttributes`, calc:212-285) | Target context attribute **`SalesTrxnItemDescription`** (`CONTEXT_DESCRIPTION_ATTR`, calc:26/192), `fieldType=inputoutput`, hydration-mapped to **`QuoteLineItem.Description`** |
| Attribute names consumed from the attr map: `Unit_Type`, `Attribute_Volume` (primary qty), `Number_of_Units` (fallback qty), and segments `License_Type`, `PS_Service_Type`, `Feature_Options`, `Maintenance_Type_Defn`, `Deployment_Option`, `Server_Location_Type`, `Power_License_Type`, `Server_Type`, `Group_Number` (cls:115-165) | — |
| SOQL `QuoteLineItem.Product2.Name` for every in-scope line (`queryProductNames`, cls:545-546) — leading segment | — |
| SOQL `QL_Description_Attribute__mdt` (`Attribute_API_Name__c, Role__c, Sort_Order__c, Match_Value__c` WHERE `Active__c=true`, cls:231-236) — optional MDT-driven config override; empty → in-code `defaultConfig()` | — |

Unit-count is read from the **configuration attribute map, not** `QuoteLineItem.Quantity` (calc:85-86). Note: the parsers use calculator-local `getStringFromTag`/`extractFieldValue` (calc:350-378), **not** the shared `ContextTagReader`.

#### 4. Context mappings
- **Write path (no DML):** direct DML is forbidden in the pricing prehook (runtime DML limit 0 — "Too many DML statements: 1", cls:58-60). Description is written by building per-line payloads `{ nodePath:{ dataPath }, attributes:[{ attributeName:'SalesTrxnItemDescription', attributeValue: <text> }] }` (`buildContextUpdate`, calc:183-197) and submitting all lines in one `ctx.updateContextAttributes(...)` call (cls:633). The `nodePath.dataPath` is the line's `dataPath` **with the first element removed** (root entity Id dropped) — same pattern cited from `COLAUpliftPrehook.buildItemUpdate` (calc:184-187, cls:603-606).
- **Field mapping:** `SalesTrxnItemDescription` → `QuoteLineItem.Description` via the context hydration map in `SalesTransactionContextExt.contextDefinition-meta.xml` line 5003 (`fieldType=inputoutput`), per cls:169-173. There is no direct `OrderItem`/`QuoteLineItemDetail` write — the hook is Quote-scoped only.
- **Registration:** as with all RCA pricing hooks, this is bound as a pricing-procedure plugin via **org config** (ProcedurePlanOption / signal binding on active runtime procedure `Rev_Mgmt_Default_Pricing_Procedure` V24, activated 2026-07-10). The binding is **not in git or the ESD XML** and could not be confirmed from these files — the specific ProcedurePlanOption Id for this hook is **not determinable from the source** (only the partner prehook's `1FYWC0000002W3r4AE` is known, which is a different hook).

#### 5. Key risks / notes
- **Uncommitted delta:** `QLDescriptionCalculator.cls` has working-tree changes (D-18 `ExceptionLogger.log` in both parser catches, plus doc/`@author`, and a stripped trailing newline). It depends on `ExceptionLogger` and a `DescriptionGenerationException` type — deploy will fail if those aren't present. Commit before any V24 packaging/deploy so the live path matches git.
- **Two Active procedure versions:** V23 and V24 are both Active in the org (open cleanup item) — ensure the hook binding resolves to V24 for meeting claims.
- **Idempotency:** `buildDescription` overwrites `Description` deterministically on every run from current attributes/product name (cls:47-55), and a static `isProcessing` re-entrancy guard (cls:183, 286) short-circuits nested invocations. Regeneration is safe/repeatable; no accumulation.
- **Fail-soft everywhere:** all context I/O swallows exceptions and downgrades to SUCCESS-with-warnings — `queryTags` failures return empty maps (short-circuit "nothing to generate", cls:307-311), and `updateContextAttributes` "not in updatable state" is silently skipped (cls:636-637). A description that never renders will surface only via the D-18 logger, not as a pricing failure.
- **Ordering:** documented to run LAST in the Quote prehook chain (cls:67); if reordered before configuration attributes are populated, segments (esp. Unit Type / qty) render incomplete. Confirm chain order in the ProcedurePlanOption config.
- **Unverified attribute names (go-live open item):** `License_Type` is a forward-compatible placeholder with no matching `AttributeDefinition.DeveloperName` in fortrauat as of 2026-04-27 (cls:116-123); the others were verified 2026-04-27. Unverified/missing attributes are silently skipped, so a wrong DeveloperName degrades to a missing segment, not an error.


## Posthooks

### CancelLineCreditPosthook (POSTHOOK)

#### 1. Purpose
`CancelLineCreditPosthook` is a `RevSignaling.SignalingApexProcessor` that runs **after** the pricing procedure (`Rev_Mgmt_Default_Pricing_Procedure`, V24) to write a **negative credit** onto cancellation lines — lines carrying a negative `LineItemQuantity`. Per the class header, the RCA engine prices such lines at **$0.00 rather than a negative credit**, and the line net/total fields are "engine-only (not writable by trigger or flow)", so the credit must be applied through the **context update API** (`updateContextAttributes`) inside a posthook. It fires on native **Reprice** for **both Quote and Order** scopes — `resolveScope()` returns `'Quote'` for a `QuoteLineItem.SObjectType` line Id and `'Order'` for an `OrderItem.SObjectType` line Id (derived from the last `dataPath` element). The credit written is `credit = cancelNet * qty` (negative), rounded `setScale(2, HALF_UP)`.

The class is a **thin adapter**: `execute()` forwards `request.ctxInstanceId` to `process(contextId)`, which orchestrates four steps — (1) `fetchSalesTransactionItems` (`ctx.queryTags` on tag `SalesTransactionItem`), (2) `resolveAssetNetsForUnseededLines` (read-only SOQL), (3) `buildCreditUpdates`, (4) `submitContextUpdates` (`ctx.updateContextAttributes`). All pure math/shaping is delegated to `CancelLineCreditCalculator`.

#### 2. Modifications made (with reasons)

| Change | Code-level detail (real identifiers) | Reason / theme | Status |
|---|---|---|---|
| **Original SC-3441 hook** | `execute()`→`process()`; negative-`LineItemQuantity` gate; writes `NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount` via `updateContextAttributes`. Header records the root cause: writing the internal `Item*` tags (`ItemNetTotalPrice`/`ItemTotalPrice`/`ItemSubtotal`) returns SUCCESS but **nothing persists** — must use the **QLI field API names** (save-mapped `ContextInputAttributeName`). | SC-3441 — cancel Qty −1 lines priced $0, not a credit | Committed |
| **v2.1 self-resolution** | Added `resolveAssetNetsForUnseededLines`, `resolveSourceAssetIds` (`OrderItem.OrderAction.SourceAssetId` / `QuoteLineItem.QuoteAction.SourceAssetId`), `resolveAssetNetByCurrency` (`AssetActionSource` where `NetUnitPrice > 0`), `resolveSeedNet`. When staged `CancelNetUnitPrice__c` is null/≤0 (every real UI cancellation, since the seed-prehook branch was abandoned), the hook self-resolves the source asset's original NET. | Removes dependency on any upstream seeder; currency guard (SC-3384) — a foreign-currency asset net is never applied | Committed |
| **Wave-2 extraction** (`a1c26a6`) | All pure logic extracted **verbatim** into `CancelLineCreditCalculator`: `parseLineNodes`, `buildCreditUpdates`, `buildNodeUpdate`, `collectUnseededCancelLines`, `resolveScope`, `applyAssetNetSource`, `resolveSeedNet`, `lineIdFromDataPath`, tag helpers. Hook keeps thin `@TestVisible` delegating seams with identical signatures; `PendingLine` retained hook-local and mapped from `CancelLineCreditCalculator.PendingLine`. `calc` is a **per-execute instance** (comment: the `generateLocked` Set "must not leak between reprices"). | Refactor / testability — hook = adapter (context fetch, SOQL, submit); calc = pure, no SOQL/DML/context API | Committed |
| **D-18 exception logging** (`7876aa0`) | `process()` catch calls `PricingHookLogger.logPosthook('CancelLineCreditPosthook', contextId, e)` (fire-and-forget, status unchanged). | D-18 observability — surface the swallowed degrade | Committed |
| **Uncommitted working-tree change** | (a) Header javadoc **rewritten/condensed** (SC-3441 problem narrative, "REGISTRATION: POST section on Fortra_Pricing_PreHook", version tags removed; author changed to `<liam.jeong@coastalcloud.us>`). (b) Per-method `@param`/`@return` javadoc added throughout. (c) **One functional line**: `fetchSalesTransactionItems` catch now also calls `ExceptionLogger.log('CancelLineCreditPosthook', contextId, new CancelCreditException('fetchSalesTransactionItems failed', e))`. (d) `resolveAssetNetByCurrency` comment de-references "SC-3384". | Doc normalization + additional degrade logging (D-18-adjacent) | **Uncommitted** |

Note: despite the "large uncommitted change" flag, the working-tree diff is **almost entirely javadoc/comment**; the only behavioral delta is the added `ExceptionLogger.log` call in the fetch catch. The calculator (`CancelLineCreditCalculator.cls`) is present but its working-tree diff was not in the supplied diff file.

#### 3. Context elements

| READS (inputs) | WRITES (outputs) |
|---|---|
| `SalesTransactionItem` node list — `ctx.queryTags({'tags':['SalesTransactionItem']})`, parsed by `parseLineNodes` | `NetUnitPrice` = `cancelNet` (positive per-unit) |
| `LineItemQuantity` — `getDecimalFromTag(tagMap,'LineItemQuantity')`; gate: `qty < 0` | `NetTotalPrice` = `credit` (negative) |
| `CancelNetUnitPrice__c` — `getDecimalFromTag(tagMap,'CancelNetUnitPrice__c')`; preferred per-unit net (used iff `> 0`) | `TotalPrice` = `credit` (business need) |
| `STICurrencyIsoCode` — `getStringFromTag(tagMap,'STICurrencyIsoCode')`; currency-matches asset net | `Subtotal` = `credit` |
| `ListPrice` — `getDecimalFromTag(tagMap,'ListPrice')`; **lossy** last-resort fallback net | `TotalLineAmount` = `credit` (carries to Order) |
| `dataPath` — last element = line record Id (`lineIdFromDataPath`); scope + node targeting | `response.status = SUCCESS`, `response.message = 'Credited N cancellation line(s)'` |
| SOQL: `OrderItem.OrderAction.SourceAssetId` / `QuoteLineItem.QuoteAction.SourceAssetId` | (writes emitted as `attributeName`/`attributeValue` pairs under `nodePath.dataPath`) |
| SOQL: `AssetActionSource.NetUnitPrice, AssetAction.Type, CurrencyIsoCode, CreatedDate` (`NetUnitPrice > 0`, `ORDER BY CreatedDate ASC`) | |

Asset-net fold rule (`applyAssetNetSource`): a **`Generate`** row (`PRICED_SALE_TYPES = {'Generate'}`) is **sticky** (only another Generate replaces it), non-Generate rows are newest-wins; only positive nets fold, so a $0 Generate cannot lock a pair at 0.

#### 4. Context mappings
- Node update shape (`buildNodeUpdate`): the line's `dataPath` is cloned and the **first element removed** (the 64-char context path), leaving `[rootId, lineId]` — matching Salesforce's reference posthook (`fullDataPath.get(1)`, `get(2)`). The five attributes above are written using **QLI field API names** (the save-mapped `ContextInputAttributeName` on the QLI node of `QuoteEntitiesMapping`), NOT internal `Item*` tags — this is the documented fix for the earlier no-persist bug.
- Currency mapping (`resolveSeedNet`): (1) asset NET in the line's **own** `STICurrencyIsoCode`; (2) if line has no currency tag and asset is single-currency, that sole net; (3) lossy `ListPrice` (already line-currency); else `null` → line skipped. A foreign-currency asset net is never seeded.
- `TotalLineAmount` is the field that "carries to Order," mapping the Quote-side credit through to the OrderItem on convert.
- **Registration**: as a plugin, the hook is bound via **org config** — the old header stated "POST section on the active Procedure Plan (`Fortra_Pricing_PreHook`), AFTER the PricingProcedure section." This binding lives on `ProcedurePlanOption` / signal binding and is **NOT in git or the ESD XML**. The exact `ProcedurePlanOption` Id for this posthook is not determinable from the source files (only the partner prehook's `1FYWC0000002W3r4AE` is documented elsewhere).

#### 5. Key risks / notes
- **Uncommitted state**: the working tree carries header/javadoc rewrites plus the new `ExceptionLogger.log` in `fetchSalesTransactionItems`. If deployed from git as-committed, that extra fetch-catch logging is absent.
- **Dual-Active procedure ambiguity**: both V23 and V24 are Active in the org (open cleanup item). The registration binds to the Procedure Plan, so which posthook version runs depends on which procedure the runtime resolves — verify the binding points at V24.
- **Swallow contract / false-green**: every failure path downgrades to `SUCCESS` — outer catch returns SUCCESS-with-warnings, `fetchSalesTransactionItems` returns `null`, and `submitContextUpdates` swallows the `"not in updatable state"` message and returns 0. A silently-degraded reprice looks green; the D-18 `PricingHookLogger`/`ExceptionLogger` hooks are the only signal.
- **Re-entrancy**: static `isProcessing` guard — a context update re-triggers pricing; the second entry short-circuits to SUCCESS `'already processing'`.
- **Idempotency**: writes are absolute (`credit = net * qty`), not incremental, so a re-run recomputes the same value — but the `CancelNetUnitPrice__c`-vs-asset-net precedence means the result is stable only if the source asset net is stable.
- **Ordering**: must run AFTER the PricingProcedure section (else there are no priced nodes to overwrite). The per-execute `calc` instance is deliberate — `generateLocked` is instance state and (per the calculator header) "must not be made static," or Generate-lock would leak across reprices.
- **Lossy `ListPrice` fallback**: when no `AssetActionSource` net matches the line currency, the credit is computed from catalog `ListPrice`, which may overstate the credit vs. the originally-sold net.
- Cannot be determined from files: the exact `ProcedurePlanOption` binding Id, and whether the V24 runtime actually has this posthook bound (org-config only).


### PartnerNetPricePosthook (POSTHOOK)

#### 1. Purpose

`PartnerNetPricePosthook implements RevSignaling.SignalingApexProcessor` (`execute(RevSignaling.TransactionRequest)` → `RevSignaling.TransactionResponse`; class file `PartnerNetPricePosthook.cls`, meta `apiVersion 65.0`, `status Active`). It is the **post-procedure** hook for the active runtime procedure `Rev_Mgmt_Default_Pricing_Procedure` (documenting V24). Its own header states the rationale: `PartnerPricingPrehookV2` runs *before* the procedure, but "Rev Mgmt Default Pricing recalculates NetUnitPrice from ListPrice and wipes pre-hook partner writes," and derived-maintenance lines "have UnitPrice/ListPrice = 0 until DPP formulas run in-procedure." So this hook runs **after** the procedure to (per the header): (1) stamp `PartnerUnitPrice` (partner-tier net from `Partner_Pricing_Model__c`), (2) apply deferred partner pricing on derived maintenance, (3) preserve the procedure `NetUnitPrice` when it is **lower** than partner net. The commercial rule is "lower of procedure net vs partner net"; partner net is always retained on `PartnerUnitPrice` for decomposition/COLA.

- **Quote path**: `execute()` → `applyPartnerNetPrices(ctxInstanceId)` operating on the live `SalesTransactionContextExt_v2` context (both `QuoteLineItem` and `OrderItem` line types are handled).
- **Order path**: `applyNetPricesToOrder(Id orderId)` rebuilds the context from the Order via `Context.IndustriesContext.buildContext({contextDefinitionName='SalesTransactionContextExt_v2', sourceRecordId=orderId})`, applies the same logic, then `persistContext(...)` — used after `PlaceOrderExecutor` when the in-procedure context is no longer updatable.
- **Re-entrancy guard**: `private static Boolean isProcessing` short-circuits nested invocations. It fires on **native Reprice / "Reprice All"** signaling (TLE), and the header notes DML stamps must run *after* persist, so it enqueues `QuotePriceStampQueueable` via `schedulePostPersistPriceStamp` (falls back to synchronous `stampAttributeListPricesForQuote` when already async or on enqueue failure).

#### 2. Modifications made (with reasons)

The hook is a **thin adapter/orchestrator** — the bulk of arithmetic is extracted into pure `*Calculator` delegates (Wave-2 decomposition). Per-modification:

| Change (code-level, real identifiers) | Reason / ticket | Status |
|---|---|---|
| **ABA multi-currency correction** — new methods `applyCurrencyCorrection`, `loadKnownUsdValues`, `isKnownUsdValue`, `loadLineInfo`, `mergeCurrencyCorrectionIntoUpdate`, `addAttributeIfAbsent`, `currencyAttr`, seam field `testKnownUsdValues`. `applyCurrencyCorrection` runs first in `applyPartnerNetPrices` (before the partner "lower-of"), localizes ABA raw-USD nets, and **mutates the in-memory `NetUnitPrice` tag**; write carried by `mergeCurrencyCorrectionIntoUpdate`. Largest change (~+350 lines / `@@ +225,298 @@`). | **SC-3384** — the "currency-blind ABA decision table `0lDa50000007BEuEAM`" stamps a raw USD `Override` onto non-USD lines. Gate matches raw net against a per-product union of USD `AttributeBasedAdjustment` (`AdjustmentType='Override'`), USD `PricebookEntry.UnitPrice`, and `Attribute_Tier_Pricing_Storage__c.Tier_Value__c`; provenance snapshot `ABA_Raw_Net__c`. Delegates scaling to `AbaCurrencyCorrectionService.evaluate(...)`. | **UNCOMMITTED** (working tree) |
| **Post-persist `Source_List_Price__c` / Sales-Price (`UnitPrice`) currency guards** — in the stamp path (`stampAttributeListPricesForQuote` / `resolveSalesPrice`): added `CurrencyIsoCode` + `ABA_Raw_Net__c` to the QLI SELECT; new `isUsdLine(String)` helper; `Base_Price__c` (USD-denominated Number) only stamped when `isUsdLine`, else falls through to `Pre_Partner_Price__c`/`NetUnitPrice`; ABA non-USD lines get `UnitPrice` overwritten via `Fortra_CurrencyConversionService.convertPrice(qli.ABA_Raw_Net__c, qli.CurrencyIsoCode)`. | **SC-3384** — prevent the raw-USD `Base_Price__c` leaking onto currency Sales-Price fields; localize the ABA Sales Price the context persist does not own. | **UNCOMMITTED** (working tree) |
| Deferred partner math calls `PartnerPricingServiceV2.getMarginForProductType(model, productType, quoteData.dealType)` (deal-aware, `Deal_Type__c` param) in `calculateDeferredPartnerPrice`, for both `MODEL_DISCOUNT` and `MODEL_GUARANTEED_MARGIN`. | **D-11** deal-aware margin — commit `fc10b70` "D-11 complete — unify partner margin to V2 (deal-aware posthook)". | Committed |
| J-06 New-Maintenance band precedence: authoritative `New Maintenance` band from partner Discount model overrides the license band; lifted into `NewMaintenanceNetCalculator.computeNewBusinessNets(...)` (`nets.partnerPercent = inputsPartnerPercent` when band resolved) and `NewMaintenanceBandCalculator.newMaintenanceBand/bandByQuote/bandByOrder`. | **J-06** partner maint band — commits `e71e51a`, `18fda47`. | Committed |
| D-18 observability: `catch` in `execute()` calls `PricingHookLogger.logPosthook('PartnerNetPricePosthook', ctxInstanceId, e)` (fire-and-forget; status stays SUCCESS). | **D-18** pricing-hook exception logging — commit `7876aa0`. | Committed |
| SC-3544 blank Sales-Price fill: `schedulePostPersistPriceStamp` + `QuotePriceStampQueueable` + `scheduledStampQuoteIds` per-txn guard; fill-only `UnitPrice` stamp post-persist. | **SC-3544** — commit `88c626f`. | Committed |
| **Thin-hook vs delegate split** (Wave-2 decomposition): `getLineItemRecordId`/`getStringFromTag`/`getIdFromTag`/`getDecimalFromTag`/`extractFieldValue` delegate to `ContextTagReader`; `resolveCommercialUnitPrice`/`resolvePreProcedurePrice` → `PartnerNetResolutionCalculator`; `shouldSkipProcedureOwnedPartner`/`needsDeferredPartnerPricing` → `PartnerPricingGate`; classifier logic → `DerivedMaintenanceClassifier`; payload builders → `DerivedMaintenancePayloadBuilder`, `RenewalColaPayloadBuilder`; contributor bases → `ContributorPricingCalculator`; list-price stamp → `ListPriceStampCalculator`; net formula → `NewMaintenanceNetCalculator`. | Refactor increments 3–16 (commits `708e548`…`1a2aa2b`, `c9ea7d6`, etc.). Hook keeps `@TestVisible` seams so ~47 call sites/tests stay unchanged. | Committed |

Note: only two changes are **uncommitted** (both SC-3384). The class header docblock still reads "version 1.7"; it under-states the committed history (it predates D-11/D-18/SC-3544/Wave-2).

#### 3. Context elements (read / write)

Inputs are read via `ContextTagReader.get*FromTag(...)` off the parsed `SalesTransactionItem` (line) and `SalesTransaction` (header) tags; outputs are written as `{attributeName, attributeValue}` entries under a `nodePath.dataPath` (`_updatePath`) submitted via `ctx.updateContextAttributes`.

| READS (context tag / field → source) | WRITES (attributeName on line node / DML target) |
|---|---|
| Line tags: `NetUnitPrice`, `UnitPrice`, `ListPrice`, `Quantity`, `PartnerUnitPrice`, `PartnerDiscountPercent`, `Pre_Partner_Price__c`, `Base_Price__c`, `Fortra_Product_Type__c`, `ItemDiscountPercentage`, `Discount`, `Partner_Discount_Percent__c` | Commercial net set: `NetUnitPrice`, `NetTotalPrice`, `TotalPrice`, `Subtotal`, `TotalLineAmount` (all = `resolveLineTotalFromQuantity(Quantity, commercialUnitPrice)`) |
| SC-3384 line tags: `ABA_Raw_Net__c` (order-path raw source / provenance), `STICurrencyIsoCode` (currency), `Product` (Product2 Id) | `PartnerUnitPrice` (partner-tier net; always stamped for decomposition/COLA) |
| Header tags (`SalesTransaction`): `Billing_Partner__c`, `Partner_Pricing_Model__c`, `Deal_Type__c`, `Reseller__c`, `Distributor__c`, `Referral_Partner__c`, plus `Id`/`SalesTransactionSource` (Order fallback) | Deferred-partner provenance: `Pre_Partner_Price__c`, `Partner_Adjusted_Price__c`, `Partner_Pricing_Model_Applied__c`, `Partner_Pricing_Source__c` (=`'System Calculated (Post-Procedure)'`), `PartnerDiscountPercent` |
| Renewal/COLA QLI (SOQL, `loadRenewalColaLines`): `COLACalculatedPrice__c`, `COLA_Uplift_Percent__c`, `Base_Price__c`, `Prior_Partner_Discount__c`, `Prior_Discretionary_Discount__c`, `Quote.QuoteTypeText__c` | SC-3384 correction writes (via `mergeCurrencyCorrectionIntoUpdate`): `NetUnitPrice`, `UnitPrice`, `NetTotalPrice`, `TotalPrice`, `Subtotal`, `TotalLineAmount`, `ABA_Raw_Net__c` (persisted provenance) |
| Persisted lookups: `QuoteLineItem`/`OrderItem` `.CurrencyIsoCode`, `.Product2Id`; known-USD sets from `AttributeBasedAdjustment`, `PricebookEntry`, `Attribute_Tier_Pricing_Storage__c` | Attribute-tier `ListPrice` restamp (`addAttributeTierListPriceIfNeeded`) |
| Order path: `Order.Quote.Billing_Partner__c` etc. (`enrichPartnerDataFromSourceQuote`) | Post-persist DML on `QuoteLineItem`: `Source_List_Price__c`, `UnitPrice` (Sales Price) via `QuotePriceStampQueueable` |

#### 4. Context mappings

- Line-node writes map to the SalesTransactionItem, which projects onto `QuoteLineItem` (or `OrderItem`) fields of the same name — `NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount` (commercial totals), `PartnerUnitPrice`, `UnitPrice` (Sales Price), `ListPrice`, and the custom provenance fields (`Pre_Partner_Price__c`, `Partner_*__c`, `ABA_Raw_Net__c`). `_updatePath` is derived in `parseLineItemApiResponse` by cloning the `dataPath` and dropping element 0.
- Header reads map `SalesTransaction` → `Quote` (or `Order.Quote`) header fields; the `QuoteHeaderData.hasPartnerPricing()` gate requires both `Billing_Partner__c` and a non-blank `Partner_Pricing_Model__c`.
- **Registration is org-config, not in git.** The hook is bound to `Rev_Mgmt_Default_Pricing_Procedure` (V24) as a signaling posthook plugin via `ProcedurePlanOption` / signal binding in the org — it does **not** appear in the ESD XML or repo. (The paired partner *prehook* binding is known: `ProcedurePlanOption 1FYWC0000002W3r4AE`; the posthook's own binding record Id was **not determinable from the files reviewed** and must be confirmed in org config.)

#### 5. Key risks / notes

- **Uncommitted SC-3384 work** (~+350 lines across `applyCurrencyCorrection`/stamp guards) exists only in the working tree — not committed, not in any tagged version; it must be committed and deployed together or the ABA localization is half-applied (context localizes but the post-persist `UnitPrice`/`Source_List_Price__c` guards would be missing, and vice-versa).
- **Idempotency is explicitly load-bearing and fragile.** `calculateDeferredPartnerPrice` documents DEF-1: on re-reprice `NetUnitPrice` already carries the partner discount, so it prefers the stable `Pre_Partner_Price__c` base to avoid compounding (`x0.82` each pass). The SC-3384 order-path reads persisted `ABA_Raw_Net__c` (not the possibly-already-localized `NetUnitPrice`) for the "collision cohort"; the known-USD gate is what prevents double-localization of a genuinely-localized EUR net.
- **Ordering within the hook matters**: `applyCurrencyCorrection` must run *before* the partner "lower-of" and the COLA/renewal builders because it mutates the in-memory `NetUnitPrice` tag they all read. Renewal-COLA and `shouldSkipProcedureOwnedPartner` (delegated to `PartnerPricingGate`) short-circuit lines the procedure already owns, so partner math is not re-applied.
- **Failures are swallowed by design**: `execute()` always returns `TransactionStatus.SUCCESS` (even on exception — logs via D-18 `PricingHookLogger`), and `submitContextUpdates` silently skips a "not in updatable state" context. A degraded pricing pass therefore does not fail the transaction — observability depends on `Exception_Log__c`.
- **Both V23 and V24 are Active** in the org (open cleanup item). Since binding is org-config, verify the posthook is bound to the V24 procedure and not stranded on V23 before relying on this behavior.
- **Two USD-denominated traps** the SC-3384 guards mitigate: `Base_Price__c` is a plain USD Number (must never stamp onto a currency field on non-USD lines), and the ABA table is currency-blind. The `isUsdLine` helper treats blank currency as USD — safe for single-currency quotes but worth noting for any currency-unknown line.



---

# Part 2 — Pricing Procedure Walkthrough (V24, element by element)

_The live V24 waterfall in execution order. Each element: purpose · filter conditions · assignment/custom/formula detail · what was modified and why (with confidence)._

### P1 — Foundation — Pricing Settings, Price Book Entries, Effective Dates (steps 1-3)

*All three are native RLM `BusinessKnowledgeModel` steps (`<stepType>BusinessKnowledgeModel</stepType>`) at the head of `Rev_Mgmt_Default_Pricing_Procedure` V24. They are the platform-provided foundation of the waterfall: initialize pricing settings, resolve the list price from the PriceBook, then stamp the pricing effective date. Execution order follows `<sequenceNumber>`: PricingSetting (1) → PriceBookEntries (2) → PricingEffectiveDates (3). None of the three carries a `<conditionLogic>`/`AdvancedListFilter` — they run unconditionally on every line. All parameter values below are quoted verbatim from the V24 XML.*

#### [1] PricingSetting
- **Element** — `name`=`PricingSetting`, `<label>`=`Pricing Setting`, `<description>`=`Pricing Setting`. Type: `BusinessKnowledgeModel`, `<actionType>PricingSettings</actionType>`, `selectedFunction`=`Get`. Execution position: `sequenceNumber` **1** (first step of the procedure). `resultIncluded`=`true`.
- **Purpose** — Bootstraps the per-line pricing context: initializes the price waterfall container and seeds the working net figures before any list-price lookup. Being `Get`/`IsRealTime=false`/`IsPropagationEnabled=false`, it reads settings only (no live recompute, no propagation) and establishes the `PriceWaterfall` structure that downstream discount/adjustment steps append to.
- **Custom elements (PricingSettings parameters)** — Inputs (`input=true`, `output=false`): `LineItemId`←`LineItem`; `CurrencyIsoCode`←`CurrencyIsoCode`; `IsDerived`←`DerivedPricingAttribute` (the derived-pricing flag, consumed here so derived lines are recognized from the outset); `ContractId`←`ItemContract`. Literals: `sectionCount`=`0`, `selectedFunction`=`Get`, `IsRealTime`=`false`, `IsPropagationEnabled`=`false`. Outputs (`output=true`): `PriceWaterfall`→`price_water_fall`; `NetUnitPrice`→`NetUnitPrice`; `Subtotal`→`ItemNetTotalPrice`.
- **Context mappings** — Writes context tags `price_water_fall` (waterfall JSON), `NetUnitPrice` (line net working value), and `ItemNetTotalPrice` (line subtotal). These are the same tags the Apex prehooks/posthooks read/write later via `ContextTagReader.getDecimalFromTag(tagData,'NetUnitPrice')` etc., so this step defines their initial state.
- **Modifications & why** — Baseline native element — no recent-change evidence. Not referenced in the KNOWN CHANGE MAP, commit log, or coordination docs; standard RLM `PricingSettings` initializer. (Confidence: High.)

#### [2] PriceBookEntries
- **Element** — `name`=`PriceBookEntries`, `<label>`=`Price Book Entries`, `<description>`=`List Price`. Type: `BusinessKnowledgeModel`, `<actionType>ListPrice</actionType>`, `selectedFunction`=`Get`. Execution position: `sequenceNumber` **2**. `resultIncluded`=`true`.
- **Purpose** — The list-price resolution step. Looks up the PriceBookEntry for the line's Product2 / PriceBook / selling model / currency / quantity via a decision table and stamps `ListPrice` (catalog list) plus the resolved PBE `Id` and the `IsDerived` attribute onto the line. This is the anchor value the entire downstream discount waterfall marks up/down from.
- **Custom elements (ListPrice parameters)** — Inputs: `Product2Id`←`Product`; `Pricebook2Id`←`PriceBooks`; `ProductSellingModelId`←`ProductSellingModel`; `CurrencyIsoCode`←`CurrencyIsoCode` (currency-scoped lookup — relevant to the SC-3384 multi-currency work, though the fix lives in the auto-add/ABA handlers, not here); `Quantity`←`LineItemQuantity`; `ListPriceField`←`Constant_UnitPrice_Price_Book_Entry_Decision_Table_v2_LP`. Decision-table binding literals: `LookUpName`=`Price Book Entries V2`, `LookUpId`=`0lDa50000007BErEAM`, `LookUpApiName`=`Price_Book_Entry_Decision_Table_v2`. Behaviour literals: `IsContractEnabled`=`false`, `HideWaterfall`=`false`, `IsOutputResolutionEnabled`=`false`, `sectionCount`=`0`, `selectedFunction`=`Get`, `IsRealTime`=`false`. Outputs: `Id`→`ItemPricebookEntry` (resolved PBE Id); `IsDerived`→`DerivedPricingAttribute`; `ListPrice`→`ListPrice`; `Subtotal`→`ItemNetTotalPrice`.
- **Context mappings** — Writes `ItemPricebookEntry` (PBE Id), `DerivedPricingAttribute` (drives all `IsDerived` branches later — derived maintenance SC-3346, derived services), `ListPrice`, and `ItemNetTotalPrice`. Note the PBE lookup is via decision table `Price_Book_Entry_Decision_Table_v2` (the "V2" table, id `0lDa50000007BErEAM`).
- **Modifications & why** — Baseline native `ListPrice` element — no recent-change evidence in the change map/commits for this step itself. Adjacent context: the currency-correctness fixes (SC-3384 `QuoteLineItemCurrencyCorrectionHandler`, ABA posthook 43fa4d1/`aba_posthook_fix`) and the Bulk-PBE tool (`bulk_pbe_derived_maint`) all operate on the *PBE records this step consumes*, and the "two-book gotcha" (IsDerived vs non-derived PBEs) affects which row this table returns — but the procedure element is stock. (Confidence: High that the element is baseline; the surrounding PBE data layer is actively maintained.)

#### [3] PricingEffectiveDates
- **Element** — `name`=`PricingEffectiveDates`, `<label>`=`Pricing Effective Dates`, `<description>`=`Assignment`. Type: `BusinessKnowledgeModel`, `<actionType>AssignmentElement</actionType>`. Execution position: `sequenceNumber` **3**. `resultIncluded`=`false` (internal assignment, not surfaced in results).
- **Purpose** — Establishes the pricing effective date for the line so that dated/effective-dated pricing (e.g., effective-dated PBEs, COLA/renewal date logic) resolves against the correct date. It assigns the line's `EffectiveFrom` into the context `PricingDate`.
- **Assignment element** — Input: `section-0-input1`←`EffectiveFrom`. Output: `section-0-output`→`PricingDate`. Assignment logic (from `sectionJsonString2`): a single `whereConditions` mapping `field` = `{dataType:"DateTime", name:"section-0-input1", value:"EffectiveFrom"}` → `value` = `{dataType:"DateTime", name:"section-0-output", value:"PricingDate"}`. In plain terms: **`PricingDate := EffectiveFrom`** (DateTime→DateTime, `allowCompatibleDataTypes:true`). `sectionJsonString1`=`{"whereConditions":[]}` (empty first section — no guard), `sectionCount`=`1`.
- **Context mappings** — Writes context tag `PricingDate` from source `EffectiveFrom`. Downstream date-sensitive elements (proration SC-3297/SC-3420, COLA renewal uplift SC-3346/3350) rely on this `PricingDate` being set.
- **Modifications & why** — Baseline native `AssignmentElement` — no recent-change evidence. Straightforward `EffectiveFrom → PricingDate` copy with no conditional logic; not cited in the change map or commit history. (Confidence: High.)

---
**Section note:** Steps 1-3 are entirely stock RLM foundation elements (no `AdvancedListFilter`, no `FormulaBasedPricing`, no Apex hook bindings in-XML). The Fortra-specific customization (COLA, derived maintenance, partner discount, regional services, K-09 rollups, D-17/D-19 attribute-bridge fixes) begins in the discount/adjustment groups *after* these three; the Apex prehooks/posthooks that read the `NetUnitPrice`/`ListPrice`/`PricingDate`/`DerivedPricingAttribute` tags seeded here are bound via ProcedurePlanOption org-config (e.g., partner prehook on `1FYWC0000002W3r4AE`), not in this XML.


---

### P2 — Attribute-based pricing — attribute discount + attribute-value pricing modes (steps 4-8)

Scope: five sequential `ListGroup` containers (`sequenceNumber` 4→8) that run immediately after list-price seeding. Steps 4–5 apply **attribute-based price adjustments** (decision-table lookups on `Attribute_Based_Adjustment_Decision_Table`), split into a contracted branch and a non-contracted branch. Steps 6–8 apply **attribute-value pricing**, one container per `Attribute_Price_Mode__c` value (`Unit Price` / `Calculated` / `Total Price`). All five groups gate out re-priced lines via `ItemPricingSource != 'LastTransaction'`. Each attribute-value container ends with a paired **Net Bridge → Base Bridge** (D-17/A-4 stale-price fix).

---

#### [4] ListContainer — contracted attribute-based price
- **Element** — name `ListContainer`, label "List Container", type `ListGroup`, execution position `sequenceNumber` 4 (first of this section). Children execute by child `sequenceNumber`: `AttributePricingFilter` (1) → `AttributeBasedPrice` (2).
- **Purpose** — Applies attribute-based price adjustments for lines that carry a **contract-scoped** attribute price-adjustment schedule. This is the contract-aware twin of step [5]; the filter ensures only one of the two branches fires per line.

**child 1/2 — AttributePricingFilter** (`AdvancedListFilter`, seq 1, `resultIncluded=false`, label "Attribute Pricing Filter")
- **Filter conditions** — `conditionLogic = 1 AND 2 AND 3 AND 4`:
  1. `ItemContractAttributePasId` `IsNotNull` — line has a contract attribute PAS id (contracted attribute pricing exists).
  2. `ItemPricingSource` `NotEquals` `'LastTransaction'` — skip lines already carrying a last-transaction/repriced price.
  3. `DerivedPricingAttribute` `IsNotNull`.
  4. `DerivedPricingAttribute` `Equals` `false` — exclude derived-pricing attribute lines (those are handled by the SC-3346 derived-maintenance path downstream).
- **Business scenario** — contracted lines with a real (non-derived) price-impacting attribute.

**child 2/2 — AttributeBasedPrice** (`BusinessKnowledgeModel`, `actionType=AttributeDiscount`, seq 2, `resultIncluded=true`, label "Attribute-Based Price")
- **Custom element** — AttributeDiscount decision-table lookup. Key parameters:
  - `PriceAdjustmentScheduleId` ← `AttributeProductId` (contract/product-scoped PAS — distinguishes this branch from [5]).
  - `ProductId` ← `Product`; `ProductSellingModelId` ← `ProductSellingModel`.
  - `EffectiveFrom` / `EffectiveTo` ← `PricingDate` (both) — effective-dated on the pricing date.
  - `AttributeName` ← `Attribute`; `AttributeValue` ← `AttributeValue`; `Quantity` ← `LineItemQuantity`; `IsPriceImpacting` ← `PriceImpactingAttribute`.
  - `InputUnitPrice` ← `NetUnitPrice` (adjusts the current net).
  - `AdjustmentTypeField` ← `Constant_AdjustmentType_Attribute_Based_Adjustment_Decision_Table_ABP`; `AdjustmentValueField` ← `Constant_AdjustmentValue_Attribute_Based_Adjustment_Decision_Table_ABP`.
  - Lookup: `LookUpName`="Attribute Discount Entries", `LookUpId`=`0lDa50000007BEuEAM`, `LookUpApiName`=`Attribute_Based_Adjustment_Decision_Table`.
  - `IsContractEnabled`=`true` (contract-aware — **the differentiator vs [5]**); `selectedFunction`=`Get`; `IsRealTime`=`false`.
  - **Outputs**: `NetUnitPrice` → `NetUnitPrice`; `Subtotal` → `ItemNetTotalPrice`; `IsContracted` → `IsContracted` (writes contracted flag downstream branches read).
- **Modifications & why** — baseline attribute-discount element; no D-item/SC evidence tying a recent change to this specific step. Confidence: Med (structure is native RLM AttributeDiscount; the contract-vs-standard split predates the refactor window).

---

#### [5] ListContainer7 — non-contracted attribute discount entries
- **Element** — name `ListContainer7`, label "List Container", type `ListGroup`, `sequenceNumber` 5. Children: `AttributePricingFilter8` (1) → `AttributeDiscountEntries` (2).
- **Purpose** — Standard (non-contracted) attribute-based discount lookup against the same `Attribute_Based_Adjustment_Decision_Table`. Handles lines that are **not** contracted, i.e. the complement of step [4].

**child 1/2 — AttributePricingFilter8** (`AdvancedListFilter`, seq 1, label "Attribute Pricing Filter")
- **Filter conditions** — `conditionLogic = (1 OR 2) AND 3`:
  - (`IsContracted` `IsNull` **OR** `IsContracted` `Equals` `false`) — line is not contracted (note this consumes the `IsContracted` flag that step [4]'s BKM can write).
  - `ItemPricingSource` `NotEquals` `'LastTransaction'`.
- **Business scenario** — new-business / non-contracted attribute-priced lines.

**child 2/2 — AttributeDiscountEntries** (`BusinessKnowledgeModel`, `actionType=AttributeDiscount`, seq 2, `resultIncluded=true`, label "Attribute Discount Entries")
- **Custom element** — same decision table as [4], differing parameters:
  - `PriceAdjustmentScheduleId` ← `AttributePASIdConstant` (a global constant PAS, **not** the product/contract PAS).
  - `EffectiveFrom` / `EffectiveTo` ← `EffectiveDate` (both) — note: `EffectiveDate` here vs `PricingDate` in [4].
  - Same `ProductId`/`ProductSellingModelId`/`AttributeName`/`AttributeValue`/`Quantity`/`IsPriceImpacting`, and `InputUnitPrice` ← `NetUnitPrice`.
  - Same `AdjustmentTypeField`/`AdjustmentValueField` constants; same lookup (`LookUpId`=`0lDa50000007BEuEAM`, `Attribute_Based_Adjustment_Decision_Table`).
  - `IsContractEnabled`=`false` (**the differentiator** — non-contracted); `selectedFunction`=`Get`; `IsRealTime`=`false`.
  - **Outputs**: `NetUnitPrice` → `NetUnitPrice`; `Subtotal` → `ItemNetTotalPrice`. (No `IsContracted` output — unlike [4].)
- **Modifications & why** — baseline element; no recent-change evidence. Confidence: Med.

---

#### [6] ListContainer5 — Attribute Value Pricing, **Unit Price** mode
- **Element** — name `ListContainer5`, label "List Container 5", type `ListGroup`, `sequenceNumber` 6. Children by seq: filter (1) → assignment (2) → **Net Bridge (3) → Base Bridge (4)**.
- **Purpose** — For lines whose attribute drives an explicit **unit price** (`Attribute_Price_Mode__c = 'Unit Price'`), promote the attribute-derived `Base_Price__c` into the working `InputUnitPrice`/`NetUnitPrice`, then reconcile the base/net pair via the two bridges.

**child 1/4 — AttributeValuePricingUnitPriceMode** (`AdvancedListFilter`, seq 1, label "Attribute Value Pricing - Unit Price Mode")
- **Filter conditions** — `1 AND 2 AND 3`: `Has_Attribute_Adjustment__c` `Equals` `true` AND `Attribute_Price_Mode__c` `Equals` `'Unit Price'` AND `ItemPricingSource` `NotEquals` `'LastTransaction'`.

**child 2/4 — AttributeValuePricingUnitPriceMode12** (`BusinessKnowledgeModel`, `actionType=AssignmentElement`, seq 2)
- **Assignment** — `section-0-input1` = `Base_Price__c` → `section-0-output` = `InputUnitPrice`. Copies the attribute-value `Base_Price__c` (the picked unit price) into `InputUnitPrice`. `sectionJsonString2` records the mapping field(`Base_Price__c`,Currency)→value(`InputUnitPrice`,Currency).

**child 3/4 — AttributeValuePricingUnitPriceModeNetBridge** (`BusinessKnowledgeModel`, `actionType=FormulaBasedPricing`, seq 3, label "…Unit Price Mode Net Bridge")
- **Formula** — `formula-section-0-input` (type `Parameter`) = `Base_Price__c` → output `NetUnitPrice`. Writes the attribute base price straight onto `NetUnitPrice` (fresh base, not the possibly-stale prior `InputUnitPrice`).

**child 4/4 — AttributeValuePricingUnitPriceModeBaseBridge** (`FormulaBasedPricing`, seq 4, label "…Unit Price Mode Base Bridge")
- **Formula** — `IF ( Base_Price__c > 0 , Base_Price__c , NetUnitPrice )` → output `Base_Price__c`. Back-fills `Base_Price__c` from `NetUnitPrice` only when base is 0/absent, so the base column is never left blank.
- **Modifications & why** — **D-17 / A-4 attribute Net Bridge stale-price fix** (KNOWN CHANGE MAP; audit line "D-17 AttrVolume silent reset-to-list ✅ Done `6c79166`" and commit `6c79166 docs(pricing): A-4/D-17 RESOLVED — V21 attribute Net Bridge stale-price fix (debug-confirmed)`). The bridge pair sources fresh `Base_Price__c` and guards the base back-fill so a tier/attribute change no longer keeps a stale `NetUnitPrice`. Confidence: High (bridge naming + Base_Price__c>0 guard matches the documented fix).

---

#### [7] ListContainer6 — Attribute Value Pricing, **Calculated** mode
- **Element** — name `ListContainer6`, label "List Container 6", type `ListGroup`, `sequenceNumber` 7. Children: filter (1) → calc formula (2) → **Net Bridge (3) → Base Bridge (4)**.
- **Purpose** — For `Attribute_Price_Mode__c = 'Calculated'`, compute the unit price as base × a per-attribute multiplier, then reconcile base/net.

**child 1/4 — AttributeValuePricingCalculatedMode** (`AdvancedListFilter`, seq 1)
- **Filter conditions** — `1 AND 2 AND 3`: `Has_Attribute_Adjustment__c` `Equals` `true` AND `Attribute_Price_Mode__c` `Equals` `'Calculated'` AND `ItemPricingSource` `NotEquals` `'LastTransaction'`.

**child 2/4 — AttributeValuePricingCalculatedMode17** (`FormulaBasedPricing`, seq 2, `resultIncluded=true`)
- **Formula** — `Base_Price__c * Attribute_Multiplier_Pct__c` → output `InputUnitPrice`. Multiplies the attribute base price by the attribute multiplier percentage to derive the working unit price.

**child 3/4 — AttributeValuePricingCalculatedModeNetBridge** (`FormulaBasedPricing`, seq 3)
- **Formula** — `formula-section-0-input` (type `Parameter`) = `InputUnitPrice` → output `NetUnitPrice`. Promotes the freshly-calculated `InputUnitPrice` to `NetUnitPrice`. (Note: unlike Unit-Price/Total-Price modes whose Net Bridge sources `Base_Price__c`, Calculated mode sources `InputUnitPrice` because the multiply already produced it.)

**child 4/4 — AttributeValuePricingCalculatedModeBaseBridge** (`FormulaBasedPricing`, seq 4)
- **Formula** — `IF ( Base_Price__c > 0 , Base_Price__c , NetUnitPrice )` → output `Base_Price__c`. Same guarded base back-fill.
- **Modifications & why** — D-17 / A-4 attribute Net Bridge stale-price fix, same evidence as [6] (`6c79166`). Confidence: High.

---

#### [8] ListContainer720 — Attribute Value Pricing, **Total Price** mode
- **Element** — name `ListContainer720`, label "List Container 7", type `ListGroup`, `sequenceNumber` 8 (last in section). Children: filter (1) → assignment (2) → **Net Bridge (3) → Base Bridge (4)**.
- **Purpose** — For `Attribute_Price_Mode__c = 'Total Price'`, apply the attribute-value price and reconcile base/net.

**child 1/4 — AttributeValuePricingTotalPriceMode** (`AdvancedListFilter`, seq 1)
- **Filter conditions** — `1 AND 2 AND 3`: `Has_Attribute_Adjustment__c` `Equals` `true` AND `Attribute_Price_Mode__c` `Equals` `'Total Price'` AND `ItemPricingSource` `NotEquals` `'LastTransaction'`.

**child 2/4 — AttributeValuePricingTotalPriceMode22** (`AssignmentElement`, seq 2)
- **Assignment** — `section-0-input1` = `Base_Price__c` → `section-0-output` = `InputUnitPrice` (identical mapping shape to Unit-Price mode's assignment). Moves the attribute-value base price into `InputUnitPrice`.

**child 3/4 — AttributeValuePricingTotalPriceModeNetBridge** (`FormulaBasedPricing`, seq 3)
- **Formula** — `formula-section-0-input` (type `Parameter`) = `Base_Price__c` → output `NetUnitPrice`. Writes the fresh attribute base price onto `NetUnitPrice`.

**child 4/4 — AttributeValuePricingTotalPriceModeBaseBridge** (`FormulaBasedPricing`, seq 4)
- **Formula** — `IF ( Base_Price__c > 0 , Base_Price__c , NetUnitPrice )` → output `Base_Price__c`. Guarded base back-fill.
- **Modifications & why** — D-17 / A-4 attribute Net Bridge stale-price fix, same evidence as [6]/[7] (`6c79166`). Confidence: High.

---

**Cross-cutting notes for the meeting**
- All three attribute-value containers ([6]-[8]) share the identical **Base Bridge** formula `IF(Base_Price__c > 0, Base_Price__c, NetUnitPrice)` and run Net Bridge (seq 3) *before* Base Bridge (seq 4) — i.e. net is stamped from the fresh base first, then base is re-derived only if empty. This ordering is the concrete shape of the D-17/A-4 fix.
- Mode dispatch is mutually exclusive via `Attribute_Price_Mode__c` ∈ {`Unit Price`,`Calculated`,`Total Price`} plus the shared gate `Has_Attribute_Adjustment__c = true`; a line takes at most one of [6]/[7]/[8].
- Steps [4] vs [5] differ only by contract-awareness: [4] uses `AttributeProductId` PAS + `IsContractEnabled=true` + `PricingDate`, and its filter requires `ItemContractAttributePasId IsNotNull` and excludes derived-pricing attributes; [5] uses `AttributePASIdConstant` + `IsContractEnabled=false` + `EffectiveDate`, gated on `IsContracted IsNull/false`. Both hit lookup `0lDa50000007BEuEAM` (`Attribute_Based_Adjustment_Decision_Table`).
- Every element in this section carries the `ItemPricingSource != 'LastTransaction'` guard so amend/reprice-from-last-transaction lines bypass re-adjustment.
- Note the audit's D-17 also references `AttributeVolumePricingPrehook`/`AttributeVolumeCalculator` (Tab 3 Apex, coordination doc) — that Apex prehook is the org-config-bound companion to these XML bridges and is **not** present in this ESD section; it is registered via ProcedurePlanOption, not in V24 XML.

Source: ``live V24 ExpressionSetDefinition` (retrieved from FortraUAT)` (lines 584-1668, 2737-2890). Change evidence: `docs/pricing-refactor/PRICING_REFACTOR_AUDIT_2026-07-10.md:60`, commit `6c79166`, `Data/pricing-refactor-coord/COORDINATION.md:105,152`.


---

### P3 — Bundle, Volume, Regional Services, GSA pricing (steps 9-12)

Execution note: these four `ListGroup` containers run in `sequenceNumber` order 9 → 10 → 11 → 12, each after the core list-price / attribute / partner / COLA logic of P1–P2. Each container is a scenario gate (`AdvancedListFilter` child, seq 1) followed by its pricing action (BKM child, seq 2). `NetUnitPrice` is the running carried price threaded through all four via the `InputUnitPrice`/`NetUnitPrice` context tags.

#### [9] ListContainer25 — Bundle-Based Adjustment

- **Element** — `ListContainer25`, label `List Container`, type `ListGroup`, `sequenceNumber` 9. Children execute in child order: `ListOperation` (seq 1, filter) → `BundleBasedAdjustmentEntries` (seq 2, BKM).
- **Purpose** — Applies bundle-based price adjustments (BKM/`BundleDiscount`): looks up the `Bundle_Based_Adjustment_Decision_Table` for a hit on the child product's position inside its parent/root bundle and, if matched, overwrites the running net with the bundle-adjusted price. This is where "buy the bundle, this component is discounted/repriced" logic lands.

  - **Child filter — `ListOperation`** (label `List Operation`, `AdvancedListFilter`, `parentStep` ListContainer25, seq 1)
    - **Filter conditions** — `<conditionLogic>1</conditionLogic>`; single criterion: `ItemPricingSource NotEquals 'LastTransaction'`. Business meaning: skip bundle re-adjustment when the line's price is being carried from the prior transaction (amend/renewal carry-over via `LastTransaction`), so an amend does not re-run bundle math on a line whose net was already seeded from the prior Asset. Fresh New-Business / net-new bundle lines pass.

  - **Child action — `BundleBasedAdjustmentEntries`** (label `Bundle Based Adjustment Entries`, description `Bundle-Based Price`, `stepType` BusinessKnowledgeModel, `actionType` **BundleDiscount**, `parentStep` ListContainer25, seq 2, `resultIncluded=true`)
    - **Custom element (BundleDiscount lookup)** — `selectedFunction=Get`, `LookUpApiName=Bundle_Based_Adjustment_Decision_Table`, `LookUpName='Bundle Based Adjustment Entries'`, `LookUpId=0lDa50000007BGTEA2`, `PriceAdjustmentScheduleId=BundlePASIdConstant`, `IsContractEnabled=false`, `IsRealTime=false`.
    - **Key input parameters (context tag → BKM arg):** `ProductId←Product`, `ParentProductId←MainItemProduct`, `RootBundleId←RootItemProduct`, plus their selling models (`ProductSellingModelId←ProductSellingModel`, `ParentProductSellingModelId←MainItemProductSellingModel`, `RootProductSellingModelId←RootProductSellingModel`) — the bundle-position key. `InclusivePrice←InclusivePrice`, `Quantity←LineItemQuantity`, `EffectiveFrom`/`EffectiveTo←EffectiveDate`. Critically `InputUnitPrice←NetUnitPrice` — the running net feeds the adjustment. Adjustment resolution driven by `AdjustmentTypeField←Constant_AdjustmentType_Bundle_Based_Adjustment_Decision_Table_BBP` and `AdjustmentValueField←Constant_AdjustmentValue_..._BBP`.
    - **Outputs:** `NetUnitPrice→NetUnitPrice` (adjusted per-unit net) and `Subtotal→ItemNetTotalPrice` (extended line net). These are the fields mapped back to QLI/OrderItem net.
    - **Modifications & why** — Baseline native RLM bundle-discount element; no D-item/SC-ticket in the change map or commit log targets it. The one recent-change touchpoint is the shared `ItemPricingSource != 'LastTransaction'` amend-carry guard on the filter, consistent with the amend net-carry work (SC-3501 `AmendNetCarryPrehook`). Confidence: **High** it is baseline; **Med** that the filter guard is the amend-carry protection rather than original native config.

#### [10] ListContainer28 — Volume Discount

- **Element** — `ListContainer28`, label `List Container`, type `ListGroup`, `sequenceNumber` 10. Children: `VolumeDiscounts` (seq 1, filter) → `VolumeDiscountEntries` (seq 2, BKM). Runs immediately after bundle adjustment.
- **Purpose** — Applies quantity-tier (volume) discounting (BKM/`VolumeDiscount`): resolves the line quantity against the `Price_Adjustment_Tier_Decision_Table` and rewrites net to the tier price.

  - **Child filter — `VolumeDiscounts`** (label `Volume Discounts`, `AdvancedListFilter`, `parentStep` ListContainer28, seq 1)
    - **Filter conditions** — `<conditionLogic>(1 OR 2) AND 3</conditionLogic>`:
      1. `IsContracted IsNull` **OR** 2. `IsContracted Equals false` — i.e. line is not on a locked/contracted price; **AND** 3. `ItemPricingSource NotEquals 'LastTransaction'`. Business meaning: apply volume tiers only to non-contracted lines that are not carrying a prior-transaction price — i.e. fresh New-Business quantity pricing, never on contracted or amend-carried lines.

  - **Child action — `VolumeDiscountEntries`** (label `Volume Discount Entries`, description `Volume Discount`, BusinessKnowledgeModel, `actionType` **VolumeDiscount**, `parentStep` ListContainer28, seq 2, `resultIncluded=true`)
    - **Custom element (VolumeDiscount tier lookup)** — `selectedFunction=Get`, `LookUpApiName=Price_Adjustment_Tier_Decision_Table`, `LookUpName='Volume Discount Entries'`, `LookUpId=0lDa50000007BEsEAM`, `PriceAdjustmentScheduleId=VolumePASIdConstant`, `IsContractEnabled=false`, `IsRealTime=false`.
    - **Key input parameters:** the tier band is keyed on quantity — `LowerBound←LineItemQuantity`, `UpperBound←LineItemQuantity`, `Quantity←LineItemQuantity`; product key `Product2Id←Product`, `ProductSellingModelId←ProductSellingModel`; `EffectiveFrom`/`EffectiveTo←EffectiveDate`; `InputUnitPrice←NetUnitPrice` (running net into the tier calc). Tier resolution via `TierTypeField←Constant_TierType_Price_Adjustment_Tier_Decision_Table_VD` and `TierValueField←Constant_TierValue_..._VD`.
    - **Outputs:** `NetUnitPrice→NetUnitPrice`, `Subtotal→ItemNetTotalPrice`.
    - **Modifications & why** — Baseline native volume-discount element. No change-map/commit evidence targets `VolumeDiscountEntries` itself. Note the *attribute*-volume work (D-17, SC-3384 `AttributeVolumeCalculator`/Net Bridge) is a *separate* prehook path, not this native BKM. Confidence: **High** baseline; the `IsContracted`/`LastTransaction` filter is standard native contracted-price + amend-carry gating.

#### [11] ListContainer4 — Regional Services Pricing

- **Element** — `ListContainer4`, label `List Container 4`, type `ListGroup`, `sequenceNumber` 11. Children: `RegionalServicesPrice` (seq 1, filter) → `RegionalServicesPrice33` (seq 2, BKM/Assignment).
- **Purpose** — For services flagged as region-priced, overrides the running `InputUnitPrice` with the pre-computed regional net (`RegionalNetUnitPrice__c`). The country-multiplier math itself is done upstream (Regional prehook → stamps `RegionalNetUnitPrice__c` / `RegionalNetUnitPrice`); this container just assigns that stamped value into the pricing waterfall's input price.

  - **Child filter — `RegionalServicesPrice`** (label `Regional Services Price`, `AdvancedListFilter`, `parentStep` ListContainer4, seq 1)
    - **Filter conditions** — `<conditionLogic>1</conditionLogic>`; single criterion: `AllowRegionalPricing__c Equals true`. Business meaning: only lines whose product is opted into regional pricing (`AllowRegionalPricing__c = true`) get the regional net override; all other lines skip the group and keep catalog net.

  - **Child action — `RegionalServicesPrice33`** (label `Regional Services Price`, description `Assignment`, BusinessKnowledgeModel, `actionType` **AssignmentElement**, `parentStep` ListContainer4, seq 2)
    - **Assignment (source → target)** — Assigns `RegionalNetUnitPrice__c` → `InputUnitPrice`. Encoded in the where-condition JSON: field `section-0-input1 = RegionalNetUnitPrice__c` (Currency) is written into `section-0-output = InputUnitPrice` (Currency); `sectionCount=1`, `sectionJsonString2` carries the `{field: RegionalNetUnitPrice__c, value: InputUnitPrice}` binding. Reason: the country-adjusted regional price (computed and stamped upstream) becomes the line's working unit price so downstream steps price off the regional figure.
    - **Modifications & why** — Maps to **SC-3374 regional services pricing** (commit `ba2e951 "3374 complete"`; supporting refactor `0df19e7` extract `RegionalPricingCalculator`, `8d1ec19` regional effective-dating, `3a338ec` A-6 regional null-mult guard). Per the change map, the country multiplier is applied to **LIST**, net stays catalog, and the reconcile step reads the stamped `RegionalNetUnitPrice__c`. **Confirmed removal:** the old `RegionalNetReconcileGate` (the un-guarded `>0`-on-null gate from SC-3393, commit `0d2cafc`) is **NOT present** in this V24 container — only the filter + assignment remain, matching the INV-28 "gate removed" note. Confidence: **High** (element name, `AllowRegionalPricing__c`/`RegionalNetUnitPrice__c`, and gate-absence all match).

#### [12] ListContainer1 — GSA Government Pricing

- **Element** — `ListContainer1`, label `List Container 1`, type `ListGroup`, `sequenceNumber` 12. Children: `GSAPricing` (seq 1, filter) → `GSAPricing36` (seq 2, BKM/Formula).
- **Purpose** — US GSA government-schedule pricing: for GSA-flagged lines, sets the unit price to a fixed 50% of list, implementing the GSA schedule discount.

  - **Child filter — `GSAPricing`** (label `GSA Pricing`, `AdvancedListFilter`, `parentStep` ListContainer1, seq 1)
    - **Filter conditions** — `<conditionLogic>1</conditionLogic>`; single criterion: `GSW__c Equals true`. Business meaning: only GSA-schedule lines (`GSW__c` = GSA/government flag true) receive the GSA formula; all other lines skip.

  - **Child action — `GSAPricing36`** (label `GSA Pricing`, description `Formula Based Pricing`, BusinessKnowledgeModel, `actionType` **FormulaBasedPricing**, `parentStep` ListContainer1, seq 2, `resultIncluded=true`)
    - **Formula element** — `formula-section-0-input` (type `Formula`): **`ListPrice * 0.5`**; `formulaSectionCount=1`, `selectedFunction=Get`, `IsRealTime=false`. Output: `formula-section-0-output → InputUnitPrice`. Computes half of catalog `ListPrice` and writes it to the working unit price `InputUnitPrice` — i.e. a flat 50% GSA schedule price.
    - **Modifications & why** — Maps to the change map's **GSAPricing → US GSA government schedule pricing**. Baseline formula element; no D-item/SC-ticket commit modifies the `ListPrice * 0.5` expression. Confidence: **High** it is the GSA element as described; **no recent-change evidence** on the formula itself (baseline 50%-of-list).

Cross-section note for the meeting: all four containers share the same amend/contract discipline — Bundle and Volume both gate on `ItemPricingSource != 'LastTransaction'` (don't re-discount carried amend lines), Volume additionally gates on `IsContracted` (null/false only), while Regional and GSA gate purely on product flags (`AllowRegionalPricing__c`, `GSW__c`). Only Regional (SC-3374) has active recent-change evidence in this section; Bundle, Volume, and GSA are baseline native RLM elements. The `RegionalNetReconcileGate` absence in ListContainer4 confirms the INV-28 cleanup is live in V24.


---

### P4 — Sync/Stamp contributor base, Derived-product pull, Derived maintenance, Discount percent (steps 13-17)

This section runs after net has been established by the upstream partner/attribute/COLA logic. It (a) mirrors the settled Net back into `InputUnitPrice` so downstream discount math has a clean base, (b) snapshots the pre-discount contributor base into `Base_Price__c` / `Pre_Partner_Price__c` for non-derived new-business lines (with a partner-aware reset), (c) pulls derived-product prices natively for non-renewals, (d) formula-prices derived maintenance lines, and (e) computes the display discount percent. All five steps execute in `sequenceNumber` order 13→17; ListGroup children run in their own child `sequenceNumber` order.

---

#### [13] SyncInputUnitPriceforDiscountBase

- **Element** — name `SyncInputUnitPriceforDiscountBase`, label "Sync InputUnitPrice for Discount Base", type **ListGroup**, execution position step 13. Children run: `ListOperation38` (filter, seq 1) → `SyncInputUnitPricefromNet` (assignment, seq 2).
- **Purpose** — Re-seeds the line's `InputUnitPrice` from the freshly-settled `NetUnitPrice` so that discount-base and downstream percent calculations operate off the actual net that upstream steps produced, not a stale catalog/manually-entered input. Scoped so it only fires where `InputUnitPrice` is missing and the line is a genuine derived-attribute-driven line.

  **Child — `ListOperation38`** (label "List Operation", **AdvancedListFilter**, seq 1, `parentStep=SyncInputUnitPriceforDiscountBase`)
  - **Filter conditions** — `conditionLogic = 1 AND 2 AND 3 AND 4`:
    1. `InputUnitPrice IsNull` — only lines with no input price yet.
    2. `ItemPricingSource NotEquals 'LastTransaction'` — exclude carry-over/last-transaction-sourced lines (amend/renewal carry).
    3. `DerivedPricingAttribute IsNotNull`.
    4. `DerivedPricingAttribute Equals false`.
  - Business scenario: net-new lines whose input price hasn't been set, that carry a derived-pricing attribute flag evaluating false (i.e., not themselves the derived driver) and are not last-transaction-sourced.

  **Child — `SyncInputUnitPricefromNet`** (label "Sync InputUnitPrice from Net", **BusinessKnowledgeModel / AssignmentElement**, seq 2)
  - **Assignment** — one section: source `section-0-input1 = NetUnitPrice` → output `section-0-output = InputUnitPrice`. The `sectionJsonString2` where-clause confirms the mapping `NetUnitPrice (Currency) → InputUnitPrice (Currency)`. Effect: `InputUnitPrice := NetUnitPrice`.
  - **Modifications & why** — Baseline plumbing element supporting the discount-base refactor; no specific D-/SC- change-map entry ties to it directly. **Confidence: Low** (no commit evidence cited for this element by name).

---

#### [14] StampContributorBasePreDiscount

- **Element** — name `StampContributorBasePreDiscount`, label "Stamp Contributor Base (Pre-Discount)", type **ListGroup**, position step 14. Children run: `StampBaseFilter` (filter, seq 1) → `ResetNettoPrePartnerBase` (formula, seq 2) → `StampBase_PriceandPre_PartnerfromNet` (assignment, seq 3).
- **Purpose** — For non-derived, non-renewal, non-carry lines, snapshots the current Net as the contributor's pre-discount base into `Base_Price__c` and `Pre_Partner_Price__c`. Before snapshotting, it optionally resets Net back up to a pre-partner base so that the partner discount later computes off list/pre-partner price rather than an already-discounted net (the F-07 fix).

  **Child — `StampBaseFilter`** (label "Stamp Base Filter", **AdvancedListFilter**, seq 1)
  - **Filter conditions** — `conditionLogic = (1 OR 2) AND 3 AND 4 AND (5 OR 6)`:
    - (1 OR 2): `ItemIsDerived__std IsNull` **OR** `ItemIsDerived__std Equals false` — line is not a derived product.
    - 3: `QuoteTypeText__c NotEquals 'Renewal'` — new business / amend only, not renewals.
    - 4: `ItemPricingSource NotEquals 'LastTransaction'` — exclude last-transaction carry lines.
    - (5 OR 6): `NetUnitPrice GreaterThan 0` **OR** `NetUnitPrice IsNull`.
  - Business scenario: **non-derived, non-renewal, non-carry lines with a positive-or-null net**. The `(5 OR 6)` null-safe pair is the D-19 / K-01 / F-12 change: criterion became "`NetUnitPrice > 0` OR `IsNull(NetUnitPrice)`" so a null net no longer excludes the line from base stamping. **Confidence: High** (exact match to change map).

  **Child — `ResetNettoPrePartnerBase`** (label "Reset Net to Pre-Partner Base", **BusinessKnowledgeModel / FormulaBasedPricing**, seq 2, `resultIncluded=true`)
  - **Formula** — `formula-section-0-input`:
    `IF ( PartnerDiscountPercent > 0 , IF ( Has_Attribute_Adjustment__c = true , NetUnitPrice , ListPrice ) , NetUnitPrice )`
    Output → `NetUnitPrice` (both `formula-section-0-output` and `Output Variable` write `NetUnitPrice`); `selectedFunction=Get`.
  - **What it computes** — When a partner discount is present (`PartnerDiscountPercent > 0`): if the line has an attribute adjustment, keep the attribute-adjusted `NetUnitPrice`; otherwise reset Net back up to `ListPrice` (the pre-partner base). When no partner discount, leave Net unchanged. This guarantees the subsequent partner-discount step applies its percent to a *pre-partner* base rather than double-discounting an already-netted price.
  - **Modifications & why** — **F-07 "Reset Net to Pre-Partner Base"** (partner base reset). **Confidence: High** (name, label, and behavior match change map exactly). Note the attribute-adjustment branch preserves attribute pricing so this reset doesn't clobber attribute-driven nets.

  **Child — `StampBase_PriceandPre_PartnerfromNet`** (label "Stamp Base_Price and Pre_Partner from Net", **BusinessKnowledgeModel / AssignmentElement**, seq 3)
  - **Assignments** — two sections (`sectionCount=2`):
    - `section-0-input1 = NetUnitPrice` → `section-0-output = Base_Price__c`.
    - `section-1-input1 = NetUnitPrice` → `section-1-output = Pre_Partner_Price__c`.
  - Effect (post-reset): `Base_Price__c := NetUnitPrice` and `Pre_Partner_Price__c := NetUnitPrice`. These become the durable pre-discount base fields consumed downstream (e.g., by `DerivedPricingFormula` at step 16 and partner/discount math).
  - **Modifications & why** — Part of the F-07 / contributor-base refactor (`StampBase_PriceandPre_PartnerfromNet` is named in the change map alongside `ResetNettoPrePartnerBase`). **Confidence: High**.

---

#### [15] DerivedProductsNativePull

- **Element** — name `DerivedProductsNativePull`, label "Derived Products - Native Pull", type **ListGroup**, position step 15. Children: `DerivedProductsNonRenewal` (filter, seq 1) → `DerivedProductsRenewals` (DerivedPricing, seq 2).
- **Purpose** — Uses the native RLM DerivedPricing engine to compute derived-product net from its contributing (parent) line for **non-renewal** transactions. Renewals are excluded here because derived maintenance renewal pricing is handled by the formula path in step 16 (SC-3346 Path B).

  **Child — `DerivedProductsNonRenewal`** (label "Derived Products - Non-Renewal", **AdvancedListFilter**, seq 1)
  - **Filter conditions** — `conditionLogic = 1`: `Quote_Type__c NotEquals 'Renewal'`. Applies the native pull only to new-business / amendment quotes.

  **Child — `DerivedProductsRenewals`** (label "Derived Products - Renewals", **BusinessKnowledgeModel / DerivedPricing**, seq 2, `resultIncluded=true`)
  - **Custom element (DerivedPricing)** — native derived-price computation. Key input mappings (name → bound context field):
    - `Quantity → LineItemQuantity`
    - `ContributingNetUnitPrice → ContributorUnitPrice`
    - `ContributingSubTotal → ContributorTotalPrice`
    - `ContributingSource → ContributorSource`; `ContributingScope → ContributorScope`
    - `TransactionalListPrice → ListPrice`; `Non-TransactionalListPrice → ContributorListPrice`
    - `DerivedFormula → ContributorFormulaInput`
    - `ContributingId → Contributor`; `ContributingProduct → ContributorProduct`
    - `HeaderTotal → TotalAmount`
    - `selectedFunction=Get`, `IsRealTime=false`, `sectionCount=0`.
    - Outputs: `NetUnitPrice → NetUnitPrice`, `Subtotal → ItemNetTotalPrice`.
  - **What it does** — Reads the contributing line's unit price / subtotal / list price and the derived formula string, and lets the native engine compute this derived line's `NetUnitPrice` and `ItemNetTotalPrice`. Despite the label "Renewals," the filter restricts it to **non-renewal** lines; renewal derived maintenance is routed to step 16.
  - **Modifications & why** — Maps to **SC-3346 derived maintenance pricing** (`DerivedProductsRenewals` named in change map). The non-renewal gating reflects the "Path B" split where maintenance renewals were moved to a TermDefined/formula path rather than the native pull. **Confidence: Med** (name matches; the renewal/non-renewal split is inferred from the filter + change-map narrative).

---

#### [16] ListContainer9

- **Element** — name `ListContainer9`, label "List Container 9", type **ListGroup**, position step 16. Children: `DerivedMaintenanceNetFilter` (filter, seq 1) → `DerivedPricingFormula` (formula, seq 2). (Note: an adjacent `DerivedPricingFilter`/`ListContainer10` pair lives at lines 2126-2147 but belongs to a different parent group and is out of this section's scope.)
- **Purpose** — The formula-based pricing path for **derived** lines (derived maintenance). Handles both the renewal case (carry existing net) and the new-business case (tier percent × base), implementing the SC-3346 NB-DERIVED-TIER logic.

  **Child — `DerivedMaintenanceNetFilter`** (label "Derived Maintenance Net Filter", **AdvancedListFilter**, seq 1)
  - **Filter conditions** — `conditionLogic = 1`: `ItemIsDerived__std Equals true`. Applies only to derived lines (derived maintenance).

  **Child — `DerivedPricingFormula`** (label "Derived Pricing Formula", **BusinessKnowledgeModel / FormulaBasedPricing**, seq 2, `HideWaterfall=true`)
  - **Formula** — `formula-section-0-input`:
    `IF ( QuoteTypeText__c = 'Renewal' , NetUnitPrice , IF ( AttributeValue = 'Premier' , 0.30 , IF ( AttributeValue = 'Standard' , 0.20 , IF ( AttributeValue = 'Professional' , 0.20 , 0 ) ) ) * IF ( Base_Price__c > 0 , Base_Price__c , IF ( Pre_Partner_Price__c > 0 , Pre_Partner_Price__c , IF ( InputUnitPrice > 0 , InputUnitPrice , 0 ) ) ) )`
    Output → `NetUnitPrice`; `selectedFunction=Get`, `IsRealTime=false`.
  - **What it computes** —
    - **Renewal** (`QuoteTypeText__c = 'Renewal'`): pass through existing `NetUnitPrice` unchanged (renewal net carried by upstream COLA/carry logic, Path B).
    - **New business**: a maintenance **tier percent** — `Premier → 0.30`, `Standard → 0.20`, `Professional → 0.20`, else `0` — multiplied by a **coalesced base**: first `Base_Price__c` if > 0, else `Pre_Partner_Price__c` if > 0, else `InputUnitPrice` if > 0, else `0`. The coalescing base chain is exactly what steps 13-14 populated (`InputUnitPrice`, `Base_Price__c`, `Pre_Partner_Price__c`), which is why this step depends on them running first.
  - **Modifications & why** — **SC-3346 derived maintenance pricing / NB-DERIVED-TIER** (`DerivedPricingFormula` named in change map; the tiered percent formula is the "7-tier formula" family). The renewal short-circuit is the "maintenance TermDefined Path B" behavior. **Confidence: High** (formula literally encodes the tier logic; note the current live formula collapses to 3 named tiers—Premier/Standard/Professional—rather than 7 distinct branches, consistent with the memory note that the 7-tier formula oscillated on V14 and was simplified).

---

#### [17] DiscountPercent

- **Element** — name `DiscountPercent`, label "Discount Percent", type **BusinessKnowledgeModel / FormulaBasedPricing**, top-level step (no `parentStep`), position step 17, `HideWaterfall=false`.
- **Purpose** — Computes the display/rollup discount percentage for the line from the accumulated total discount amount over the list-price buffer, guarded against divide-by-zero.
- **Formula** — `formula-section-0-input`:
  `IF ( ListPriceBuffer__c > 0 , Total_Discount_Amount__c / ListPriceBuffer__c * 100 , 0 )`
  Output → `Discount__std`; `selectedFunction=Get`, `IsRealTime=false`.
- **What it computes** — When `ListPriceBuffer__c > 0`, `Discount__std = Total_Discount_Amount__c / ListPriceBuffer__c * 100` (percent of list discounted); otherwise `0`. `ListPriceBuffer__c` is the divide-by-zero guard/denominator, `Total_Discount_Amount__c` the numerator, writing the native `Discount__std` field surfaced on the line.
- **Modifications & why** — Baseline discount-percent rollup with an explicit `> 0` denominator guard; no specific D-/SC- entry in the change map names `DiscountPercent`. **Confidence: Low / baseline element — no recent-change evidence.**

---

**Cross-cutting note for the meeting:** steps 13→14→16 form a dependency chain — `SyncInputUnitPricefromNet` (13) seeds `InputUnitPrice`, `StampBase_PriceandPre_PartnerfromNet` (14) seeds `Base_Price__c`/`Pre_Partner_Price__c` (after the F-07 pre-partner reset), and `DerivedPricingFormula` (16) coalesces exactly those three fields as its base. Any reordering or filter regression in 13/14 silently degrades derived-maintenance new-business pricing at 16. Step 15 (native pull) and step 16 (formula) are mutually exclusive by the renewal/`ItemIsDerived__std` filters. Source: ``live V24 ExpressionSetDefinition` (retrieved from FortraUAT)` (lines 2104-2502, 4739-4810, 5221-5820).


---

### P5 — One-time net seed, Partner discount, Manual quote-level discounts, Partner derived-maintenance (steps 18-21)

Scope: this is the discount-application band of `Rev_Mgmt_Default_Pricing_Procedure` **V24** (active 2026-07-10; V23 also still Active — open cleanup item). It runs **after** list/attribute pricing and COLA uplift have established `NetUnitPrice`, and applies, in order: (18) a net seed so One-Time/Perpetual lines have a partner-discountable base, (19) the reseller partner %, (20) manual quote-level line discounts (amount and %), and (21) the partner + manual discount path for **derived maintenance** lines. Partner prehook (`PartnerPricingPrehook`, bound on ProcedurePlanOption `1FYWC0000002W3r4AE`) supplies `PartnerDiscountPercent` upstream via org config — not in this XML.

---

#### [18] SeedOneTimeNetBeforePartner
- **Element** — name `SeedOneTimeNetBeforePartner`, label "Seed OneTime Net Before Partner", type **ListGroup**, `sequenceNumber` 18. Children execute in child order: `OneTimeNetSeedFilter` (seq 1) then `OneTimeNetSeed` (seq 2).
- **Purpose** — Guarantees a non-zero `NetUnitPrice` base exists on One-Time/Perpetual lines **before** the partner discount (step 19) runs, so the partner % applies to a real number instead of null/0.
- **Filter conditions** (`OneTimeNetSeedFilter`, AdvancedListFilter) — `conditionLogic` = `1 AND 2 AND 3 AND (4 OR 5)`:
  1. `SellingModelType NotEquals 'Evergreen'`
  2. `SellingModelType NotEquals 'TermDefined'`
  3. `ItemPricingSource NotEquals 'LastTransaction'`
  4. `DerivedPricingAttribute IsNull` OR 5. `DerivedPricingAttribute Equals false`
  Business scenario: **One-Time / Perpetual** lines (the residual selling model after excluding Evergreen and TermDefined subscription), **not a renewal** (`ItemPricingSource ≠ LastTransaction`), and **not a derived** line. Excludes subscription/renewal/derived-maintenance from this seed.
- **Formula element** (`OneTimeNetSeed`, BusinessKnowledgeModel / `actionType` FormulaBasedPricing):
  - `formula-section-0-input` = `IF ( NetUnitPrice > 0 , NetUnitPrice , InputUnitPrice )`
  - Output `formula-section-0-output` and `Output Variable` both write **`NetUnitPrice`**.
  - Computes: keep the existing net if already priced positive, otherwise **seed net from `InputUnitPrice`** (the catalog list price). Effect: a One-Time/Perpetual line that arrived with net=0/null gets net = list so the downstream partner % is applied to list.
- **Modifications & why** — Maps to **SC-3359** "One-Time/Perpetual partner net = list": partner discount was not being applied because net was null/0 on these lines; seeding net before the partner step fixes it. Confidence **High** (element name `OneTimeNetSeed` / `SeedOneTimeNetBeforePartner` matches the change map, and the filter deliberately targets non-Evergreen/non-TermDefined = One-Time/Perpetual).

---

#### [19] ListContainer3 (Partner Discount)
- **Element** — name `ListContainer3`, label "List Container 3", type **ListGroup**, `sequenceNumber` 19. Children: `PartnerDiscount` (filter, seq 1) then `PartnerDiscount56` (BKM ManualDiscount, seq 2).
- **Purpose** — Applies the reseller/partner margin as a percentage off the current net on standard (non-derived) lines of partner deals.
- **Filter conditions** (`PartnerDiscount`, AdvancedListFilter) — `conditionLogic` = `1 AND (2 OR 3)`:
  1. `Deal_Type__c NotEquals 'Fortra Originated'`
  2. `ItemIsDerived__std IsNull` OR 3. `ItemIsDerived__std Equals false`
  Business scenario: **partner/reseller-originated deals** (any deal type other than "Fortra Originated") on **non-derived** lines. Derived-maintenance lines are deliberately excluded here — they get their own partner path in step 21.
- **Custom element** (`PartnerDiscount56`, ManualDiscount):
  - `AdjustmentType` = `PercentageStringConstant`; `AdjustmentValue` = **`PartnerDiscountPercent`** (supplied by the partner prehook via org config).
  - `Quantity` = `LineItemQuantity`; `InputUnitPrice` = **`NetUnitPrice`** (discount taken off current net, which step 18 just seeded).
  - Outputs: `NetUnitPrice` → **`NetUnitPrice`**; `Subtotal` → **`ItemNetTotalPrice`**.
  - Function: reduces net by the partner % and recomputes the line net total.
- **Modifications & why** — Core partner-margin application; interlocks with SC-3359 (seed) and the F-07 base-reset (step 20). The `ItemIsDerived__std` guard separates standard vs derived-maintenance partner handling (SC-3346 partner-path split). Confidence **Med** (behavior matches the D-11 partner-margin / SC-3346 split described in the change map; no isolated commit in the provided log names `PartnerDiscount56`).

---

#### [20] ListContainer57 (Manual Quote-Level Discounts)
- **Element** — name `ListContainer57`, label "List Container", type **ListGroup**, `sequenceNumber` 20. Children in order: `ManualQuoteLevelDiscount` (filter, seq 1), `NullCheckforLineAdjustment` (seq 2), `ResetAmountBaseFromList` (seq 3), `ManualQuoteLevelAmountBasedLineLevel` (seq 4), `ManualQuoteLevelPercentageBasedLineLevel` (seq 5).
- **Purpose** — Applies rep-entered manual discounts (both fixed-amount and percentage) at the line level after partner margin, with null-safety and a pre-partner base reset so an amount discount is not stacked on an already-partner-discounted net.
- **Filter conditions** (`ManualQuoteLevelDiscount`, AdvancedListFilter) — `conditionLogic` = `1 AND (2 OR 3 OR 4) AND (5 OR 6)`:
  1. `ItemPricingSource NotEquals 'LastTransaction'` (not a renewal/carry line)
  2. `ItemSalesTransactionAction Equals 'Amend'` OR 3. `Equals 'Add'` OR 4. `ItemSalesTransactionAction IsNull`
  5. `ItemIsDerived__std IsNull` OR 6. `ItemIsDerived__std Equals false`
  Business scenario: **new-quote / Add / Amend** transaction lines that are **non-derived** and **non-renewal**. Manual quote-level discounts apply to new business and amendments, not to renewal-carried or derived lines.
- **Formula element** (`NullCheckforLineAdjustment`, FormulaBasedPricing, seq 2):
  - `formula-section-0-input` = `IF ( ISNULL ( ItemTotalAdjustmentAmount ) , 0 , ItemTotalAdjustmentAmount )`; output → **`ItemTotalAdjustmentAmount`**.
  - Null-guards the running line adjustment so a blank does not corrupt/NaN downstream math. Maps to the **AllLinesNullSafeFilter / NullSafeLineAdjustment** null-safety guard. Confidence **Med-High** (formula and label directly match).
- **Formula element** (`ResetAmountBaseFromList`, FormulaBasedPricing, seq 3):
  - `formula-section-0-input` = `IF ( STICurrencyIsoCode = 'USD' , IF ( ItemDiscountAmount > 0 , IF ( PartnerDiscountPercent > 0 , IF ( Pre_Partner_Price__c > 0 , Pre_Partner_Price__c , NetUnitPrice ) , ListPrice ) , NetUnitPrice ) , NetUnitPrice )`; output → **`NetUnitPrice`**.
  - Computes: for **USD** lines only, when a manual **amount** discount is present (`ItemDiscountAmount > 0`) AND a partner discount was applied (`PartnerDiscountPercent > 0`), reset net back to the **pre-partner base** `Pre_Partner_Price__c` (falling back to `NetUnitPrice` if that field is 0); if there's an amount discount but no partner discount, reset to `ListPrice`; otherwise leave `NetUnitPrice` untouched. Non-USD is passed through unchanged.
  - **Modifications & why** — Maps to **F-07 "Reset Net to Pre-Partner Base"** (`ResetNettoPrePartnerBase` / `StampBase_PriceandPre_PartnerfromNet`): a manual amount discount must compute off the pre-partner base rather than the already-partner-discounted net (otherwise double-dipping). `Pre_Partner_Price__c` is the SC-3384/G-01 pre-partner base field. USD gate reflects the multi-currency work (non-USD net handled elsewhere). Confidence **High** for F-07 mapping.
- **Custom element** (`ManualQuoteLevelAmountBasedLineLevel`, ManualDiscount, seq 4):
  - `AdjustmentType` = `AmountStringConstant`; `AdjustmentValue` = **`ItemDiscountAmount`**; `Quantity` = `LineItemQuantity`; `InputUnitPrice` = `NetUnitPrice`.
  - Outputs `NetUnitPrice` → `NetUnitPrice`, `Subtotal` → `ItemNetTotalPrice`. Applies the fixed per-unit/line amount discount.
- **Custom element** (`ManualQuoteLevelPercentageBasedLineLevel`, ManualDiscount, seq 5):
  - `AdjustmentType` = `PercentageStringConstant`; `AdjustmentValue` = **`ItemDiscountPercentage`**; `Quantity` = `LineItemQuantity`; `InputUnitPrice` = `NetUnitPrice`.
  - Outputs `NetUnitPrice` → `NetUnitPrice`, `Subtotal` → `ItemNetTotalPrice`. Applies the rep % discount. Runs after the amount discount, so both can stack on the (reset) base.
- **Modifications & why (group)** — Combines K-09-adjacent null-safety (`NullCheckforLineAdjustment`) and the F-07 base reset with the standard two manual-discount BKMs. Confidence **Med-High** overall; strongest on `ResetAmountBaseFromList`=F-07.

---

#### [21] PartnerDiscountDerivedMaintenance
- **Element** — name `PartnerDiscountDerivedMaintenance`, label "Partner Discount - Derived Maintenance", type **ListGroup**, `sequenceNumber` 21. Children in order: `PartnerDiscountDerivedMaintenance64` (filter, seq 1), `PartnerDiscountDerivedMaintenance65` (BKM ManualDiscount, seq 2), `StampPartnerUnitPriceDerivedMaintenance` (BKM AssignmentElement, seq 3), `ManualDiscountDerivedMaintenance` (BKM ManualDiscount, seq 4).
- **Purpose** — The dedicated discount path for **derived maintenance** lines (the maintenance whose net is derived from the parent license per SC-3346). Because these lines were excluded from steps 19–20 (`ItemIsDerived__std` guards), this group re-applies partner % and manual % to them, and stamps the partner-adjusted unit price.
- **Filter conditions** (`PartnerDiscountDerivedMaintenance64`, AdvancedListFilter) — `conditionLogic` = `1 AND 2 AND 3 AND 4`:
  1. `ItemIsDerived__std Equals true` (derived-maintenance lines only)
  2. `Deal_Type__c NotEquals 'Fortra Originated'` (partner deals)
  3. `ItemPricingSource NotEquals 'LastTransaction'` (not renewal-carried)
  4. `QuoteTypeText__c NotEquals 'Renewal'` (new business, not a renewal quote)
  Business scenario: **new-business derived-maintenance lines on partner deals** — excludes renewals (renewal derived-maintenance pricing is handled by the COLA/derived-renewal band upstream).
- **Custom element** (`PartnerDiscountDerivedMaintenance65`, ManualDiscount, seq 2):
  - `AdjustmentType` = `PercentageStringConstant`; `AdjustmentValue` = **`PartnerDiscountPercent`**; `Quantity` = `LineItemQuantity`; `InputUnitPrice` = `NetUnitPrice`.
  - Outputs `NetUnitPrice` → `NetUnitPrice`, `Subtotal` → `ItemNetTotalPrice`. Applies the partner % to the derived-maintenance net.
- **Assignment element** (`StampPartnerUnitPriceDerivedMaintenance`, AssignmentElement, seq 3):
  - Assigns **`NetUnitPrice` → `PartnerUnitPrice`** (`section-0-input1` = `NetUnitPrice`, `section-0-output` = `PartnerUnitPrice`; `sectionJsonString2` whereConditions map Currency `NetUnitPrice` → Currency `PartnerUnitPrice`).
  - Reason: persists the post-partner-discount net into `PartnerUnitPrice` so the partner-adjusted price is captured on the line for downstream stamping/reporting (feeds the derived-maintenance partner posthook). Maps to **StampPartnerUnitPriceDerivedMaintenance** in the change map.
- **Custom element** (`ManualDiscountDerivedMaintenance`, ManualDiscount, seq 4):
  - `AdjustmentType` = `PercentageStringConstant`; `AdjustmentValue` = **`ItemDiscountPercentage`**; `Quantity` = `LineItemQuantity`; `InputUnitPrice` = `NetUnitPrice`.
  - Outputs `NetUnitPrice` → `NetUnitPrice`, `Subtotal` → `ItemNetTotalPrice`. Applies the rep % manual discount to derived-maintenance lines (parallel to `ManualQuoteLevelPercentageBasedLineLevel` in step 20, but for the derived branch).
- **Modifications & why** — Maps to **SC-3346 derived-maintenance pricing** + the partner double-discount fix: the `ItemIsDerived__std=true` branch was split out so derived maintenance gets partner % + manual % exactly once (not double-discounted through both steps 19/20 and here), and `StampPartnerUnitPriceDerivedMaintenance` records the partner net for the deal-aware posthook (**D-11** unify partner margin). The `QuoteTypeText__c ≠ 'Renewal'` and `ItemPricingSource ≠ 'LastTransaction'` guards keep renewal COLA pricing out of this new-business path. Confidence **Med-High** (element names, `ItemIsDerived__std` gating, and `PartnerUnitPrice` stamp all match the change map; note MEMORY flags Path B derived-maintenance as ~70% deployed/unproven, so treat the derived branch as an active-risk area for the meeting).

---

**Cross-cutting notes for the meeting**
- Every ManualDiscount BKM in this band reads and writes the **same `NetUnitPrice`** and writes `Subtotal`→`ItemNetTotalPrice`, so ordering is load-bearing: seed (18) → partner % (19) → base-reset + manual amount/% (20) → derived-maintenance partner/manual (21). The F-07 `ResetAmountBaseFromList` is the guard that prevents manual-amount stacking on partner-discounted net.
- The `ItemIsDerived__std` (IsNull OR false) guards in steps 19–20 vs `= true` in step 21 are the mechanism that routes standard vs derived-maintenance lines down separate partner/manual paths.
- Change-evidence grep over `pricing_commits_all.txt` and `PRICING_REFACTOR_AUDIT_2026-07-10.md` returned no element-name-level hits for these steps (only Apex-side `DerivedMaintenanceClassifier`/`DerivedMaintenancePayloadBuilder` decomposition), so confidence ratings above lean on the KNOWN CHANGE MAP + MEMORY (SC-3359, SC-3384/`Pre_Partner_Price__c`, SC-3346), not on isolated proc commits.

Source: ``live V24 ExpressionSetDefinition` (retrieved from FortraUAT)` (lines 3235-3327, 3328-3420, 3421-3473, 3474-3566, 3567-3631, 3697-3816, 3817-3943, 3944-4090, 4674-4738, 5003-5013, 5357-5407; ListGroups at 2814-2824, 2847-2857).


---

### P6 — Derived net reset, COLA uplift on renewal, Contracted pricing, Quantity price (steps 22-25)

Waterfall segment executes in `sequenceNumber` order: **22 → 23 → 24 → 25**. All four are `ListGroup` steps (`stepType`), each gated by a leading `AdvancedListFilter` child; the filter conditions the remaining children of that group. Prehook/posthook Apex (COLA calculator, derived-maintenance classifier, partner posthook) run OUTSIDE this XML as ORG-CONFIG signal bindings — the elements below only read the context fields those hooks stamp (e.g. `COLACalculatedPrice__c`, `DerivedPricingAttribute`).

---

#### [22] ListContainer10 — "List Container 10" (ListGroup, seq 22)

Derived-product net-price reset group. Runs only for context lines flagged as derived (maintenance/support derived from a parent license). Contains a filter + a formula-based reset.

- **Element** — `ListContainer10`, label "List Container 10", `stepType=ListGroup`, exec position 22. Children (by child `sequenceNumber`): `DerivedPricingFilter` (1) → `DerivedPricingNetUnitPriceValueReset` (2).
- **Purpose** — Zero out / carry-forward the derived net so a derived maintenance line does not retain a stale computed net from an earlier waterfall step; on Renewal it preserves the already-computed `NetUnitPrice`, on New Business it collapses to 0 (net comes later from the derived tier formula, not from a carried value).

**Child 22.1 — `DerivedPricingFilter`** (label "Derived Pricing Filter", `AdvancedListFilter`, child seq 1)
- **Filter conditions** — `conditionLogic = 1`; single `criteria`: `ItemIsDerived__std Equals true` (Literal). Scenario in business terms: **derived lines only** (RCA-native derived-item flag set on maintenance/support that is priced off a parent). Non-derived lines skip the whole group.
- **Modifications & why** — baseline gating element; part of the SC-3346 derived-maintenance pricing family but no recent-change evidence on the filter itself. Confidence: Med (family attribution), Low (element-level change).

**Child 22.2 — `DerivedPricingNetUnitPriceValueReset`** (label "Derived Pricing - NetUnitPrice Value Reset", `BusinessKnowledgeModel` / `actionType=FormulaBasedPricing`, child seq 2)
- **Formula elements** — `formula-section-0-input` (type Formula):
  `IF ( QuoteTypeText__c = 'Renewal' , NetUnitPrice , 0 )`
  Output param `formula-section-0-output = NetUnitPrice`. Computes: **on Renewal keep the existing `NetUnitPrice`; on any non-Renewal quote type reset net to 0.** `selectedFunction=Get`, `HideWaterfall=false`, `IsRealTime=false`.
- **Purpose** — Prevents a non-renewal derived line from carrying a previously-seeded net into the derived-tier formula (`DerivedPricingFormula`, which lives in sibling `ListContainer9`, applies the 7-tier `IF(AttributeValue='Premier',0.30,…0.20…)` percentage against `Base_Price__c`/`Pre_Partner_Price__c`/`InputUnitPrice`). This reset makes the tier formula authoritative for New Business while the renewal path retains its COLA-upflifted net.
- **Modifications & why** — Maps to **SC-3346 derived maintenance pricing (NB-DERIVED-TIER / "Path B")**: `DerivedPricingNetUnitPriceValueReset` + `DerivedPricingFormula` + `DerivedPricingFilter` are the derived-tier trio. Commit evidence: `5412e1e SC-3410/SC-3412 fix auto-added New-Maintenance derived line priced at zero`; the qty-0/missing-MTD $0 traps documented in memory. The `QuoteTypeText__c='Renewal'` branch is what preserves renewal COLA net vs. NB reset. Confidence: **High** (element name is an explicit change-map entry).

---

#### [23] ListContainer2 — "List Container 2" (ListGroup, seq 23)

COLA-on-renewal application group. Takes the Apex-precomputed `COLACalculatedPrice__c` and stamps it into the live pricing fields for renewal lines that carry a COLA percent.

- **Element** — `ListContainer2`, label "List Container 2", `stepType=ListGroup`, exec position 23. Children by seq: `COLAUpliftonRenewal` (1, filter) → `COLAUpliftonRenewal73` (2, assignment) → `COLAUpliftNetonRenewal` (3, assignment).
- **Purpose** — For renewal maintenance/support lines pulled from a prior transaction, overwrite both the input basis and the net with the COLA-uplifted price the prehook already calculated, so the uplift survives into `InputUnitPrice` (basis for downstream margin math) and `NetUnitPrice` (the sell net).

**Child 23.1 — `COLAUpliftonRenewal`** (label "COLA Uplift on Renewal", `AdvancedListFilter`, seq 1)
- **Filter conditions** — `conditionLogic = 1 AND 2 AND 3 AND 4 AND 5`:
  1. `ItemPricingSource Equals 'LastTransaction'` (line originated from prior contract pull)
  2. `DerivedPricingAttribute IsNotNull`
  3. `SalesTransactionActionType IsNotNull`
  4. `SalesTransactionActionType Equals 'Renew'`
  5. `COLA_Uplift_Percent__c IsNotNull`
  Scenario: **renewal lines carried from last transaction that have a resolved COLA uplift percent** (i.e. recurring items eligible for cost-of-living uplift). Purely additive AND-chain — any null/miss skips the group.
- **Modifications & why** — SC-3346/SC-3350/SC-3384 COLA family. The `IsNotNull` guards on `DerivedPricingAttribute`, `SalesTransactionActionType`, and `COLA_Uplift_Percent__c` are the defensive null-safety pattern used across the refactor. Confidence: **High** (family), Med (specific guard provenance).

**Child 23.2 — `COLAUpliftonRenewal73`** (label "COLA Uplift on Renewal", `BusinessKnowledgeModel` / `actionType=AssignmentElement`, seq 2)
- **Assignment elements** — `section-0-input1 = COLACalculatedPrice__c` → `section-0-output = InputUnitPrice`. `sectionJsonString2` confirms mapping `COLACalculatedPrice__c (Currency) → InputUnitPrice (Currency)`. Reason: reset the **input basis** to the COLA-uplifted figure so any subsequent computation that reads `InputUnitPrice` sees the uplifted number, not the raw carried price.
- **Modifications & why** — COLA renewal uplift (SC-3346/3350). `COLACalculatedPrice__c` is stamped upstream by `COLAUpliftCalculator`/`COLAUpliftPrehook` (commits `23c6c4e`, `83cac00 D-13 wire prehook to COLAUpliftCalculator.resolveTier`, `41b5622 SC-3350`). Confidence: **High**.

**Child 23.3 — `COLAUpliftNetonRenewal`** (label "COLA Uplift Net on Renewal", `BusinessKnowledgeModel` / `actionType=AssignmentElement`, seq 3)
- **Assignment elements** — `section-0-input1 = COLACalculatedPrice__c` → `section-0-output = NetUnitPrice`. `sectionJsonString2`: `COLACalculatedPrice__c (Currency) → NetUnitPrice (Currency)`. Reason: stamp the uplifted price as the **sell net**. Runs after 23.2 so both basis and net end the group equal to `COLACalculatedPrice__c`.
- **Modifications & why** — SC-3346 / SC-3350 / SC-3384 COLA renewal uplift + proration + line-override precedence (per memory `project_sc3384_cola_line_override_fix`: rep line-override must win — that precedence is enforced in the prehook that populates `COLACalculatedPrice__c`, not here; this element merely applies the resolved value). Commit `af3a470 Round-6 Track-1 SDD-reconciliation (Partner + COLA)`. Confidence: **High**.

---

#### [24] ListContainer75 — "List Container" (ListGroup, seq 24)

Contracted-pricing date pin. Label text reads "Contacted" (typo for **Contracted**) throughout (`ContactedPricing`, `ContactedPricing77`).

- **Element** — `ListContainer75`, label "List Container", `stepType=ListGroup`, exec position 24. Children: `ContactedPricing` (1, filter) → `ContactedPricing77` (2, assignment).
- **Purpose** — For contracted lines that do not yet have a pricing date pinned, set the pricing evaluation date to the line's effective date so contracted rates resolve against the correct point in time.

**Child 24.1 — `ContactedPricing`** (label "Contacted Pricing", `AdvancedListFilter`, seq 1)
- **Filter conditions** — `conditionLogic = 1 AND 2 AND 3`:
  1. `IsContracted IsNotNull`
  2. `IsContracted Equals true`
  3. `PricingDate IsNull`
  Scenario: **contracted lines whose `PricingDate` has not yet been set.** Guards prevent re-stamping an already-pinned date.
- **Modifications & why** — No commit-log hit for "Contracted/Contacted" (grep returned only refactor/COLA/PricingTermCount). **Baseline element — no recent-change evidence.** Confidence: High (that it is baseline).

**Child 24.2 — `ContactedPricing77`** (label "Contacted Pricing", `BusinessKnowledgeModel` / `actionType=AssignmentElement`, seq 2)
- **Assignment elements** — `section-0-input1 = EffectiveDate` → `section-0-output = PricingDate`. `sectionJsonString2`: `EffectiveDate (DateTime) → PricingDate (DateTime)`. Reason: pin the pricing-resolution date to the transaction/line `EffectiveDate` for contracted items so contracted price entries resolve as-of that date.
- **Modifications & why** — Baseline element — no recent-change evidence. Confidence: High.

---

#### [25] ListContainer78 — "List Container" (ListGroup, seq 25)

Line-extension calculation. Final step of this segment; computes the extended net total (result-included).

- **Element** — `ListContainer78`, label "List Container", `stepType=ListGroup`, exec position 25. Children: `QuantityPrice` (1, filter) → `QuantityPrice80` (2, formula, `resultIncluded=true`).
- **Purpose** — Multiply unit net by quantity and pricing-term count to produce the line extended amount (`ItemNetTotalPrice`) for non-derived, non-last-transaction lines. This is the output that flows to the QLI/OrderItem net total.

**Child 25.1 — `QuantityPrice`** (label "Quantity * Price", `AdvancedListFilter`, seq 1)
- **Filter conditions** — `conditionLogic = 1 AND 2 AND 3`:
  1. `ItemPricingSource NotEquals 'LastTransaction'` (exclude carried renewal lines already priced by COLA group)
  2. `DerivedPricingAttribute IsNotNull`
  3. `DerivedPricingAttribute Equals false`
  Scenario: **non-derived lines priced fresh this transaction (New Business / Amend / non-renewal)** — derived lines and last-transaction renewal pulls are excluded (they get their extension elsewhere / retain COLA net).
- **Modifications & why** — Baseline gating; ties into PricingTermCount work via its formula sibling. Confidence: Med.

**Child 25.2 — `QuantityPrice80`** (label "Quantity * Price", `BusinessKnowledgeModel` / `actionType=FormulaBasedPricing`, seq 2, `resultIncluded=true`)
- **Formula elements** — `formula-section-0-input` (type Formula):
  `NetUnitPrice * LineItemQuantity * IF ( PricingTermCount > 0 , PricingTermCount , 1 )`
  Outputs: `formula-section-0-output = ItemNetTotalPrice` and duplicate `Output Variable = ItemNetTotalPrice`. `selectedFunction=Get`, `HideWaterfall=false`. Computes the **extended net = unit net × qty × term-count**, with the `IF(PricingTermCount>0,…,1)` guard defaulting term count to 1 when unset so a null/zero term does not zero the extension.
- **Modifications & why** — The `IF(PricingTermCount > 0, PricingTermCount, 1)` guard is the **SC-3420 / SC-3415 PricingTermCount null-safety** fix (memory: PTC null after deleted Proration step zeroed totals; commit `784b674 SC-3420: RCA + guarded fix for PricingTermCount derivation`). This is `resultIncluded=true`, i.e. the segment's authoritative net-total output. Confidence: **High** (guard maps directly to the SC-3420 term-count defense).

---

**Cross-cutting notes for the meeting:**
- Two groups here consume Apex-prehook outputs rather than compute pricing natively: **ListContainer2** reads `COLACalculatedPrice__c` (COLA prehook) and **ListContainer10** reads `ItemIsDerived__std` / relies on `DerivedPricingFormula` in sibling `ListContainer9`. If the org-config signal bindings for those hooks are absent, these groups no-op silently (filters fail on null inputs).
- `DerivedPricingFormula` (the 7-tier `Premier=0.30 / Standard=Professional=0.20` formula writing `NetUnitPrice`) is parented to **`ListContainer9`, not `ListContainer10`** — the reset (22.2) and the tier formula live in adjacent groups; verify their relative sequence when discussing NB-DERIVED-TIER oscillation (memory `project_nb_derived_tier_fix`).
- Source: ``live V24 ExpressionSetDefinition` (retrieved from FortraUAT)` (V24, retrieved 2026-07-10). Both V23 and V24 currently Active — open cleanup item.


---

### P7 — Formula-based line pricing, Evergreen proration + subscription pricing, subscription sub-groups (steps 26-31)

This band runs **after** NetUnitPrice has been settled by the earlier waterfall (list → attribute/tier → partner/COLA/derived). Its job is to compute each line's **total** (`ItemNetTotalPrice` / `TotalLineAmount`) and, where relevant, the proration-adjusted `NetUnitPrice`, by routing every line into exactly one selling-model bucket. The six top-level steps are mutually-exclusive `ListGroup`s selected purely by their child `AdvancedListFilter` (none of the groups carry an inline `<advancedCondition>` of their own — the group `<steps>` blocks at 2924-2989 contain only metadata, so the child `ListOperation` filter is the sole gate). Execution order is the `sequenceNumber` shown: 26 → 27 → 28 → 29 → 30 → 31.

Key context constants referenced below (`OneTimePricingTermCountConstant`, `EvergreenPricingTermCountConstant`, `PricingTermCountValueOneConstant`, `InclusivePriceConstant`) are pre-seeded scalar context values (the "…Count" ones = 1) used to force a proration multiplier of 1 for non-prorated models.

---

#### [26] ListContainer81

- **Element** — name `ListContainer81`, label "List Container", type `ListGroup`, sequence 26. Children (child order): `ListOperation82` (filter, seq 1) → `FormulaBasedPricing` (BKM, seq 2).
- **Purpose** — Handles lines whose price was **carried from a prior transaction** (amendments / renewals where the engine reuses the last-transaction unit price). It re-derives the line extended total from the carried net unit price rather than re-running model-based subscription math.
- **Filter conditions** (`ListOperation82`, `AdvancedListFilter`) — `conditionLogic = 1`; criteria 1: `ItemPricingSource Equals 'LastTransaction'`. Business scenario: **amend/renewal lines carrying the prior asset's net** (the "LastTransaction" pricing source). Contrast: the step at line 2990 (out of this section) is the mirror `ItemPricingSource NotEquals 'LastTransaction'` bucket that feeds the fresh-pricing path.
- **Formula element** (`FormulaBasedPricing`, actionType `FormulaBasedPricing`) — `formula-section-0-input` = **`NetUnitPrice * LineItemQuantity`** (`formulaSectionCount=1`, `selectedFunction=Get`, `IsRealTime=false`). Output: `formula-section-0-output` and `Output Variable` both write **`ItemNetTotalPrice`**. Computes the line extended total = carried net × quantity, with `resultIncluded=true` (result persists to the line).
- **Modifications & why** — Maps to **SC-3501 amend net-carry** (commit `b8b25f6` "SC-3501 amend prehook: carry line total (net x qty), sole amend-carry under V24"; `4a497df` carry prior asset net onto amend lines). The `LastTransaction` branch is the runtime consumer of the net seeded by `AmendNetCarryPrehook`, and this formula is precisely the "line total (net × qty)" the commit describes. **Confidence: High** (formula string `NetUnitPrice * LineItemQuantity` + commit language match exactly).

---

#### [27] EvergreenanytimeprorationfilterLinelevel

- **Element** — name `EvergreenanytimeprorationfilterLinelevel`, label "Evergreen anytime proration filter (Line level)", type `ListGroup`, sequence 27. Children: `ListOperation85` (filter, seq 1) → `Proration` (BKM, seq 2) → `SubscriptionPricing` (BKM, seq 3).
- **Purpose** — The **prorated** subscription path: for Evergreen lines that allow partial periods and carry a transient end date (mid-term co-terming / anytime proration), and for TermDefined lines with an end date, it computes a fractional term multiplier and applies it to net × qty.
- **Filter conditions** (`ListOperation85`) — `conditionLogic = (1 AND 2 AND 3) OR (4 AND 3)`; criteria: (1) `SellingModelType Equals 'Evergreen'`, (2) `AllowPartialProrationPeriods Equals true`, (3) `itemTransientEndDate IsNotNull`, (4) `SellingModelType Equals 'TermDefined'`. Business scenario: **Evergreen with partial-period proration enabled and a set end date**, OR **TermDefined with a set end date** — i.e. any line that needs date-driven proration.
- **Custom element — `Proration`** (actionType `Proration`, seq 2, `resultIncluded=true`) — Inputs: `EffectiveFrom`←`EffectiveFrom`; `EffectiveTo`←`itemTransientEndDate`; `ProrationPeriod`←`PricingTermUnit`; `StartProrationPeriod`/`StartProrationPeriodDay`/`StartProrationPeriodMonth`←like-named context; `AllowPartialProrationPeriods`←`AllowPartialProrationPeriods`; `SellingModelType`←`SellingModelType`; `SubscriptionTermUnit`←`PricingTermUnit`; `SubscriptionTerm`←`ItemSubscriptionTerm`. Output: **`ProrationMultiplier` → `PricingTermCount`** — the computed number of billable periods between EffectiveFrom and the transient end date.
- **Custom element — `SubscriptionPricing`** (actionType `SubscriptionPricing`, seq 3, `resultIncluded=true`) — Inputs: `Quantity`←`LineItemQuantity`; `ProrationMultiplier`←`PricingTermCount` (the value just computed by Proration); `NetUnitPrice`←`NetUnitPrice`. Outputs: **`TotalSubscriptionPrice` → `ItemNetTotalPrice`** and **`SubscriptionNetUnitPrice` → `NetUnitPrice`**. Computes line total = NetUnitPrice × Qty × PricingTermCount and writes back the period-adjusted net unit price.
- **Modifications & why** — Maps to **SC-3297 (billing From/To dates driving `itemTransientEndDate`/EffectiveTo)** and **SC-3420 / SC-3415 PricingTermCount** (commit `784b674` "SC-3420: RCA + guarded fix for PricingTermCount derivation"; `969e4fe`/`b6a2249` SC-3415). The `ProrationMultiplier → PricingTermCount` wiring is exactly the PTC derivation those tickets restored (memory: "PTC null=deleted Proration step (V11→V12); re-add"). **Confidence: High** (element is the Proration step feeding PricingTermCount named in the SC-3420 commit). Underlying Proration/SubscriptionPricing BKMs are native RLM — **baseline** engine components, config-tuned only.

---

#### [28] ListContainer88

- **Element** — name `ListContainer88`, label "List Container", type `ListGroup`, sequence 28. Children: `ListOperation89` (filter, seq 1) → `Assignment` (BKM, seq 2) → `SubscriptionPricing91` (BKM, seq 3).
- **Purpose** — The **One-Time / Perpetual** (non-subscription) bucket: no proration, term count forced to 1, extended amount = unit × qty.
- **Filter conditions** (`ListOperation89`) — `conditionLogic = 1 AND 2`; criteria: (1) `SellingModelType NotEquals 'Evergreen'`, (2) `SellingModelType NotEquals 'TermDefined'`. Business scenario: **everything that is neither Evergreen nor TermDefined** — i.e. One-Time / Perpetual license & hardware lines.
- **Assignment element** (`Assignment`, actionType `AssignmentElement`, seq 2, `resultIncluded=false`) — assigns `section-0-input1` = **`OneTimePricingTermCountConstant`** → `section-0-output` = **`PricingTermCount`** (per `sectionJsonString2` whereConditions mapping input→output). Forces PricingTermCount = 1 for one-time lines so the subscription math produces a single-period total.
- **Custom element — `SubscriptionPricing91`** (actionType `SubscriptionPricing`, seq 3, `resultIncluded=true`) — Inputs: `Quantity`←`LineItemQuantity`; `ProrationMultiplier`←**`PricingTermCountValueOneConstant`** (hard 1, not the assigned PricingTermCount); `NetUnitPrice`←**`InputUnitPrice`**. Outputs: **`TotalSubscriptionPrice` → `TotalLineAmount`** and **`SubscriptionNetUnitPrice` → `InputUnitPrice`**. Computes TotalLineAmount = InputUnitPrice × Qty × 1.
- **Modifications & why** — Term-count-constant assignment ties to **SC-3420/SC-3415 PTC** stabilization (ensuring one-time lines carry a non-null PTC=1 for downstream activation, memory: null PTC blocks activation). The `InputUnitPrice`/`TotalLineAmount` targets (vs Evergreen's `NetUnitPrice`/`ItemNetTotalPrice`) are the native one-time field set. **Confidence: Med** for the SC-3420 linkage (no element-name hit in coord docs; inference from PTC-constant pattern). SubscriptionPricing91 BKM itself — **baseline**.

---

#### [29] ListContainer92

- **Element** — name `ListContainer92`, label "List Container", type `ListGroup`, sequence 29. Children: `ListOperation93` (filter, seq 1) → `Assignment94` (BKM, seq 2).
- **Purpose** — The **non-prorated subscription** bucket: Evergreen without partial-period proration (or with no end date), and open-ended TermDefined. Sets a full-term PricingTermCount but defers the extended-amount math to step 30.
- **Filter conditions** (`ListOperation93`) — `conditionLogic = (1 AND (2 OR 3)) OR (4 AND 3)`; criteria: (1) `SellingModelType Equals 'Evergreen'`, (2) `AllowPartialProrationPeriods Equals false`, (3) `itemTransientEndDate IsNull`, (4) `SellingModelType Equals 'TermDefined'`. Business scenario: **Evergreen that either disallows partial proration or has no transient end date**, OR **TermDefined with no end date** — subscriptions billed on full standard periods, not prorated.
- **Assignment element** (`Assignment94`, actionType `AssignmentElement`, seq 2, `resultIncluded=false`) — assigns `section-0-input1` = **`EvergreenPricingTermCountConstant`** → `section-0-output` = **`PricingTermCount`**. Seeds the standard (non-prorated) term count for these lines; the actual line total is then produced by `SubscriptionPricing97` in step 30 (which this group's members also match).
- **Modifications & why** — Same PTC-derivation family as steps 27/28 (SC-3420/SC-3415). No dedicated element-level change evidence; **baseline element with PTC-constant wiring — Confidence: Low/Med**.

---

#### [30] ListContainer95

- **Element** — name `ListContainer95`, label "List Container", type `ListGroup`, sequence 30. Children: `ListOperation96` (filter, seq 1) → `SubscriptionPricing97` (BKM, seq 2).
- **Purpose** — Computes the **extended line amount for all subscription lines** (Evergreen or TermDefined), applying whatever `PricingTermCount` was set upstream (full term from step 29 or prorated from step 27).
- **Filter conditions** (`ListOperation96`) — `conditionLogic = 1 OR 2`; criteria: (1) `SellingModelType Equals 'TermDefined'`, (2) `SellingModelType Equals 'Evergreen'`. Business scenario: **all subscription lines** (TermDefined or Evergreen).
- **Custom element — `SubscriptionPricing97`** (actionType `SubscriptionPricing`, seq 2, `resultIncluded=true`) — Inputs: `Quantity`←`LineItemQuantity`; `ProrationMultiplier`←**`PricingTermCount`**; `NetUnitPrice`←**`InputUnitPrice`**. Outputs: **`TotalSubscriptionPrice` → `TotalLineAmount`** and **`SubscriptionNetUnitPrice` → `InputUnitPrice`**. Computes TotalLineAmount = InputUnitPrice × Qty × PricingTermCount (the standard subscription extended-amount roll).
- **Modifications & why** — Consumer of the PTC set by steps 27/29, so downstream of **SC-3420/SC-3415**. SubscriptionPricing97 BKM itself is native. **Baseline element — Confidence: Med** on PTC dependency.

---

#### [31] ListContainer98

- **Element** — name `ListContainer98`, label "List Container", type `ListGroup`, sequence 31. Children: `ListOperation99` (filter, seq 1) → `Assignment100` (BKM, seq 2).
- **Purpose** — Overrides the line extended amount for **inclusive-price** lines (bundle-inclusive / $0-billed components whose price is absorbed by a parent), forcing the line total to the inclusive-price constant.
- **Filter conditions** (`ListOperation99`) — `conditionLogic = 1`; criteria 1: `InclusivePrice Equals true`. Business scenario: **lines flagged as inclusive-priced** (typically bundle children rolled into the parent's price).
- **Assignment element** (`Assignment100`, actionType `AssignmentElement`, seq 2, `resultIncluded=false`) — assigns `section-0-input1` = **`InclusivePriceConstant`** → `section-0-output` = **`TotalLineAmount`** (per `sectionJsonString2` mapping). Stamps the inclusive-price constant onto `TotalLineAmount`, overriding whatever the subscription/formula math produced so inclusive components don't double-charge.
- **Modifications & why** — No change-map, commit, or coordination-doc hit for `InclusivePrice`/`Assignment100`. **Baseline element — no recent-change evidence.**

---

**Cross-cutting note for the meeting:** Steps 27-31 collectively implement the selling-model dispatch for line totals — Evergreen-prorated (27), One-Time (28), non-prorated subscription (29→30), and inclusive-price override (31) — all pivoting on `SellingModelType`, `AllowPartialProrationPeriods`, and `itemTransientEndDate`. The single most-touched runtime coupling here is **`PricingTermCount`** (written by `Proration` in 27, by `Assignment`/`Assignment94` constants in 28/29, consumed by `SubscriptionPricing97` in 30), which is the SC-3420/SC-3415 fault surface — a null PTC here nulls `TotalLineAmount` and blocks order activation. Source: ``live V24 ExpressionSetDefinition` (retrieved from FortraUAT)`.


---

### P8 — Category total resets (K-09), category aggregates, grand totals, final null-safety (steps 32-43)

Execution model note: steps 32-34 are flat `BusinessKnowledgeModel` FormulaBasedPricing resets that run per line but write the same category-total context tag to `0`; steps 35-37 are `ListGroup` containers, each with an `AdvancedListFilter` child (seq 1) that scopes the line set by `Fortra_Product_Type__c`, then a `GroupingAndAggregatePricing` child (seq 2) that SUMs into the same category tag. Steps 38-41 are top-level grand-total aggregates, step 42 is the null-safe line-adjustment group, step 43 is the final Assignment that stamps display fields. All aggregates SUM the context tag `ItemNetTotalPrice` (category/grand totals) or `TotalLineAmount` (Subtotal), `RollUpPrice=false`, `write-back-data-type=Text`.

#### [32] ResetTotalServicesK09zeroinit
- **Element** — name `ResetTotalServicesK09zeroinit`, label "Reset Total Services (K-09 zero-init)", type BusinessKnowledgeModel / `actionType=FormulaBasedPricing`, execution position seq 32 (first of the three resets).
- **Purpose** — Force-initializes the Services category total to zero before the category rollup runs, so a quote with no Services lines does not retain a stale prior value in that field.
- **Formula element** — `formula-section-0-input` = literal `0` (type `Formula`), `selectedFunction=Get`, written to `formula-section-0-output` target `Total_Services__c` (a real QuoteLineItem/OrderItem field, not just a context tag). `formulaSectionCount=1`, `IsRealTime=false`.
- **Modifications & why** — K-09 conditional-aggregate stale-rollup fix (SC-3345). The downstream `ServicesAggregatePrice` (step 35) is a conditional SUM; on an empty category a conditional aggregate writes nothing, leaving the prior rollup in place. This zero-init guarantees a clean `0`. Confidence **High** — label literally names "(K-09 zero-init)", target matches `ServicesAggregatePrice.section-0-output`; MEMORY note `project_quote_pricing_rollups` ("conditional aggregates leave STALE on empty; SC-3345") and commit `4cba50f "3345 fixed"` corroborate.

#### [33] ResetTotalSoftwareK09zeroinit
- **Element** — name `ResetTotalSoftwareK09zeroinit`, label "Reset Total Software (K-09 zero-init)", BusinessKnowledgeModel / FormulaBasedPricing, seq 33.
- **Purpose** — Same zero-init pattern for the Software category total.
- **Formula element** — input literal `0`, output target `Total_Software__c`. Identical parameter shape to step 32.
- **Modifications & why** — K-09 / SC-3345 zero-init, paired with `SoftwareAggregatePrice` (step 36) which is a *conditional* SUM (`ItemNetTotalPrice isNotNull`). Confidence **High**.

#### [34] ResetTotalSubscriptionK09zeroinit
- **Element** — name `ResetTotalSubscriptionK09zeroinit`, label "Reset Total Subscription (K-09 zero-init)", BusinessKnowledgeModel / FormulaBasedPricing, seq 34.
- **Purpose** — Zero-init for the Subscription category total.
- **Formula element** — input literal `0`, output target `Total_Subscription__c`.
- **Modifications & why** — K-09 / SC-3345 zero-init, paired with `SubscriptionAggregatePrice` (step 37, conditional SUM). Confidence **High**.

#### [35] ListContainer8
- **Element** — name `ListContainer8`, label "List Container 8", type ListGroup, seq 35. Children execute in child order: `TotalServices` (filter, seq 1) then `ServicesAggregatePrice` (aggregate, seq 2).
- **Purpose** — Scopes the line set to Services lines and rolls their net total up into `Total_Services__c`.
- **Filter conditions — TotalServices** (`AdvancedListFilter`, parent `ListContainer8`): `conditionLogic=1`, single criteria `Fortra_Product_Type__c Equals 'Services'` (Literal). Business scenario: **Services product-type lines only**.
- **Custom element — ServicesAggregatePrice** (`GroupingAndAggregatePricing`, parent `ListContainer8`, seq 2): `section-count=1`, `section-0-group-count=0` (no grouping key — flat total), `section-0-aggr-func=SUM` over `section-0-aggr-func-tag=ItemNetTotalPrice` (Currency), output `section-0-output=Total_Services__c`. **`where-condition-count=0`** — note this aggregate has NO `isNotNull` guard, unlike the Software/Subscription siblings; it relies solely on the parent Services filter and the step-32 zero-init. `RollUpPrice=false`.
- **Modifications & why** — Rollup half of the K-09/SC-3345 pair (zero-init in step 32 + conditional/scoped SUM here). Confidence **High** for the K-09 linkage; the missing `where-condition` on this specific aggregate is an asymmetry worth flagging in the meeting (Services rollup depends entirely on the step-32 reset for empty-category correctness).

#### [36] Copy1ofListContainer8
- **Element** — name `Copy1ofListContainer8`, label "Copy 1 of List Container 8", ListGroup, seq 36. Children: `TotalSoftware` (filter, seq 1), `SoftwareAggregatePrice` (aggregate, seq 2).
- **Purpose** — Scopes to Software lines and rolls their net total into `Total_Software__c`.
- **Filter conditions — TotalSoftware** (`AdvancedListFilter`, parent `Copy1ofListContainer8`): `conditionLogic=1`, `Fortra_Product_Type__c Equals 'Software'`. Scenario: **Software product-type lines only**.
- **Custom element — SoftwareAggregatePrice** (`GroupingAndAggregatePricing`, seq 2): `SUM` of `ItemNetTotalPrice` → `Total_Software__c`. Adds a where-clause: `where-condition-count=1`, `condition-0-input=ItemNetTotalPrice`, `condition-0-operator=isNotNull` (Currency) — only lines with a non-null net contribute. `section-0-group-count=0`, `RollUpPrice=false`.
- **Modifications & why** — K-09/SC-3345 rollup (paired with step-33 zero-init). The `isNotNull` guard is the conditional aggregate that necessitated the zero-init. Confidence **High**.

#### [37] Copy1ofCopy1ofListContainer8
- **Element** — name `Copy1ofCopy1ofListContainer8`, label "Copy 1 of Copy 1 of List Container 8", ListGroup, seq 37. Children: `TotalSubscription` (filter, seq 1), `SubscriptionAggregatePrice` (aggregate, seq 2).
- **Purpose** — Scopes to Subscription lines and rolls their net total into `Total_Subscription__c`.
- **Filter conditions — TotalSubscription** (`AdvancedListFilter`, parent `Copy1ofCopy1ofListContainer8`): `conditionLogic=1`, `Fortra_Product_Type__c Equals 'Subscription'`. Scenario: **Subscription product-type lines only**.
- **Custom element — SubscriptionAggregatePrice** (`GroupingAndAggregatePricing`, seq 2): `SUM` of `ItemNetTotalPrice` → `Total_Subscription__c`, with `where-condition-count=1`, `condition-0 = ItemNetTotalPrice isNotNull`. `section-0-group-count=0`, `RollUpPrice=false`.
- **Modifications & why** — K-09/SC-3345 rollup (paired with step-34 zero-init). Confidence **High**.

#### [38] TotalAmount
- **Element** — name `TotalAmount`, label "Total Amount", BusinessKnowledgeModel / `GroupingAndAggregatePricing`, seq 38 (top-level, no parent group).
- **Purpose** — Computes the transaction grand total of net line amounts, excluding derived-pricing (bundled/derived-maintenance) lines to avoid double-counting.
- **Custom element** — `SUM` of `section-0-aggr-func-tag=ItemNetTotalPrice` (Currency) → `section-0-output=TotalAmount`. `section-0-group-count=0` (flat). Three where-conditions (`where-condition-count=3`): `condition-0 = ItemNetTotalPrice isNotNull` (Currency); `condition-1 = DerivedPricingAttribute isNotNull` (Boolean); `condition-2 = DerivedPricingAttribute isFalse` (Boolean). Net effect: sum only lines whose `DerivedPricingAttribute` is present and false (i.e., non-derived priced lines). `RollUpPrice=false`.
- **Modifications & why** — The `DerivedPricingAttribute isNotNull AND isFalse` exclusion is the SC-3346 derived-maintenance guard (derived maintenance lines are priced off their parent and must not inflate the grand total). Confidence **Med** (pattern matches SC-3346 derived-pricing suppression; no step-specific commit cited).

#### [39] FormulaBasedPricing3
- **Element** — name `FormulaBasedPricing3`, label "Formula Based Pricing 3", BusinessKnowledgeModel / FormulaBasedPricing, seq 39.
- **Purpose** — Per-line reconciliation ensuring the displayed line total is never below the computed net total — takes the greater of net-total vs the running line amount.
- **Formula element** — `formula-section-0-input` = `IF ( ItemNetTotalPrice > TotalLineAmount , ItemNetTotalPrice , TotalLineAmount )`, written to `formula-section-0-output` target `TotalLineAmount`. Computes `max(ItemNetTotalPrice, TotalLineAmount)` and overwrites `TotalLineAmount`.
- **Modifications & why** — Baseline reconciliation element — no recent-change evidence in commit log or coord docs. Note it is the source that feeds `AggregatePrice` (step 40) via `TotalLineAmount`.

#### [40] AggregatePrice
- **Element** — name `AggregatePrice`, label "Aggregate Price", BusinessKnowledgeModel / `GroupingAndAggregatePricing`, seq 40.
- **Purpose** — Computes the transaction `Subtotal` from the reconciled per-line `TotalLineAmount` (output of step 39), again excluding derived lines.
- **Custom element** — `SUM` of `section-0-aggr-func-tag=TotalLineAmount` (Currency) → `section-0-output=Subtotal`. `section-0-group-count=0`. `where-condition-count=3`: `condition-0 = TotalLineAmount isNotNull`; `condition-1 = DerivedPricingAttribute isNotNull`; `condition-2 = DerivedPricingAttribute isFalse`. Same derived-exclusion pattern as step 38 but summing `TotalLineAmount` instead of `ItemNetTotalPrice`, into `Subtotal`. `RollUpPrice=false`.
- **Modifications & why** — Derived-line exclusion consistent with SC-3346 guard; baseline aggregate otherwise. Confidence **Med** for the derived-exclusion linkage.

#### [41] AggregatePrice116
- **Element** — name `AggregatePrice116`, label "Aggregate Price", BusinessKnowledgeModel / `GroupingAndAggregatePricing`, seq 41.
- **Purpose** — Computes a per-item-group subtotal (grouped rollup) — the summary total for each `SalesTransactionItemGroup` (bundle/group), excluding derived lines.
- **Custom element** — `SUM` of `section-0-aggr-func-tag=ItemNetTotalPrice` (Currency), grouped: `section-0-group-count=1`, `section-0-group-0=SalesTransactionItemGroup` (Text) → `section-0-output=ItemGroupSummarySubtotal`. `where-condition-count=3`: `condition-0 = SalesTransactionItemGroup isNotNull` (Text); `condition-1 = DerivedPricingAttribute isNotNull` (Boolean); `condition-2 = DerivedPricingAttribute isFalse` (Boolean). So it rolls net-total per group for grouped, non-derived lines. `RollUpPrice=false`.
- **Modifications & why** — Grouped-subtotal element; derived exclusion per SC-3346 pattern. Baseline otherwise — no step-specific change evidence. Confidence **Med** for derived-exclusion linkage.

#### [42] ListContainer11
- **Element** — name `ListContainer11`, label "List Container 11", ListGroup, seq 42. Children: `AllLinesNullSafeFilter` (filter, seq 1), `NullSafeLineAdjustment` (BKM, seq 2).
- **Purpose** — Final per-line null-safety pass: over all qty≥0 lines, coalesce a null line-level adjustment amount to zero so downstream persistence/display never sees a null adjustment.
- **Filter conditions — AllLinesNullSafeFilter** (`AdvancedListFilter`, parent `ListContainer11`): `conditionLogic=1`, single criteria `LineItemQuantity GreaterThanOrEquals 0` (Literal). Scenario: **all lines with quantity ≥ 0** (effectively every real line; a broad "all lines" gate).
- **Formula element — NullSafeLineAdjustment** (BusinessKnowledgeModel / FormulaBasedPricing, seq 2): `formula-section-0-input` = `IF ( ISNULL ( ItemTotalAdjustmentAmount ) , 0 , ItemTotalAdjustmentAmount )`, written to `formula-section-0-output` target `ItemTotalAdjustmentAmount`. Coalesces null → 0 in place.
- **Modifications & why** — Maps to KNOWN CHANGE MAP "AllLinesNullSafeFilter / NullSafeLineAdjustment → null-safety guard for blank line adjustments." Names match exactly. Confidence **High** for identity; **Low/none** on a specific commit (no dedicated commit found — treat as baseline null-safety guard).

#### [43] Assignment120
- **Element** — name `Assignment120`, label "Assignment", BusinessKnowledgeModel / `actionType=AssignmentElement`, seq 43 (final step of the procedure section).
- **Purpose** — Final display-field stamping: copies the reconciled internal totals onto the customer-facing subtotal/total fields so the persisted line shows the right amounts.
- **Assignment elements** (`sectionCount=2`):
  - Section 0: `section-0-input1 = TotalLineAmount` → `section-0-output = ItemSubtotal`. Assigns the reconciled per-line total to `ItemSubtotal`. (`sectionJsonString2` confirms the mapping `TotalLineAmount → ItemSubtotal`, no where-conditions in `sectionJsonString1`.)
  - Section 1: `section-1-input1 = ItemNetTotalPrice` → `section-1-output = ItemTotalPrice`. Assigns the net total to `ItemTotalPrice` (`sectionJsonString3` confirms `ItemNetTotalPrice → ItemTotalPrice`).
- **Modifications & why** — Baseline terminal assignment — no recent-change evidence in commit log/coord docs. It is the write-out that makes the step 32-41 computed context tags land on the standard `ItemSubtotal` / `ItemTotalPrice` targets (context→QuoteLineItem/OrderItem mapping).

Cross-section flag for the architect: the three category rollups (35-37) are asymmetric — Software (36) and Subscription (37) SUM with an `ItemNetTotalPrice isNotNull` where-clause, but Services (35) has `where-condition-count=0`. All three are made empty-safe only by the step 32-34 K-09 zero-inits, so those resets are load-bearing (removing them re-opens the SC-3345 stale-rollup defect, most acutely on Services which has no in-aggregate guard).


---

# Part 3 — Fields & Metadata Modifications

I have everything needed. Compiling the dossier.

## Fields & Metadata Modifications

*Fortra RCA (Revenue Cloud Advanced / RLM) pricing engine — active runtime procedure `Rev_Mgmt_Default_Pricing_Procedure` **V24** (activated 2026-07-10; V23 also still Active — open cleanup item). Every entry below is grounded in the working-tree metadata under `force-app/main/default/objects/**` and `.../flows/`, cross-checked against `docs/pricing-refactor/`.*

### 1. Custom fields supporting pricing

| Field | Object(s) | Type | Change | Ticket / Reason |
|---|---|---|---|---|
| `ABA_Raw_Net__c` | QuoteLineItem **and** OrderItem | Number(18,2) | Added | **SC-3384.** Stores the raw per-unit **USD** net stamped by the Attribute-Based Adjustment (ABA) step **before** multi-currency localization. Non-null = line was priced by the currency-blind ABA Override decision table `0lDa50000007BEuEAM`. `PartnerNetPricePosthook` reads it to localize (`per-unit = raw × static rate`) and stay idempotent (skips when `NetUnitPrice` already = raw×rate). OrderItem copy carries provenance across convert (order-side reprice doesn't re-run the ESD). |
| `CancelNetUnitPrice__c` | QuoteLineItem **and** OrderItem | Currency(18,2) | Added | **SC-3441.** Staging seed for cancellation / negative-quantity lines. Written into the pricing context by `CancelLineNetSeedPrehook` (from `AssetActionSource.NetUnitPrice`), consumed by the cancel-seed AssignmentElement to set `NetUnitPrice` so a cancel line is a true credit, not $0. System-only. |
| `Model_Number__c` | Hardware__c | Text(100) | Added | **SC-3468.** Free-text hardware model number; part of the dual-write model-display fix. |
| `iSeries_Model__c` | Hardware__c | Picklist (~90 values: 150…890, 20S…RMD) | Added | **SC-3468.** Controlling field of the iSeries dependent picklist; applicable only when Hardware Platform = iSeries. |
| `iSeries_Feature_Code__c` | Hardware__c | Picklist (`controllingField = iSeries_Model__c`) | Added | **SC-3468.** Dependent picklist — feature codes filtered by selected `iSeries_Model__c`. Confirms the dependent-picklist pairing. |
| `Is_COLA_Overridden__c` | QuoteLineItem | **Checkbox — Formula** (`BlankAsZero`) | **Converted trigger-maintained checkbox → formula** | **COLA audit / D-13 (SDD Pricing-COLA §6.2).** Formula: `NOT(ISBLANK(Default_COLA_Uplift_Percent__c)) && NOT(ISBLANK(COLA_Uplift_Percent__c)) && COLA_Uplift_Percent__c <> Default_COLA_Uplift_Percent__c`. Single-definition override classification; guarded so a line with no stamped default isn't flagged. Restored to SDD formula in `c4710b0`. |
| `Default_COLA_Uplift_Percent__c` | QuoteLineItem | Number(5,2) | Present (supporting) | COLA audit. "Original COLA percentage from `COLA_Uplift_Rules__mdt` — preserved for comparison." Feeds the `Is_COLA_Overridden__c` formula. |
| `COLA_Uplift_Percent__c` | QuoteLineItem | Number(5,2) | Present (supporting) | COLA audit. "Applied COLA percentage — editable by sales reps for override." The override-side operand of the formula. |
| `PricingTermCount` | QuoteLineItem | Standard field, `trackHistory=false` | Metadata present (history flag) | **SC-3420 / SC-3411.** Term-count field whose null value (from a deleted Proration step V11→V12) blocked activation; re-added to procedure. Field metadata carried in-repo but only the `<trackHistory>` node is defined — no custom type/formula. |

Additional COLA audit fields present on QuoteLineItem (supporting the same COLA workstream, not all newly added this cycle): `COLA_Applied_Date__c`, `COLA_Modified_By__c`, `COLA_Modified_Date__c`, `COLA_Outyear_Uplift_Percent__c`, `COLA_Override_Reason__c`, `COLA_Solution_Category__c`, `COLA_Source__c`, `COLACalculatedPrice__c`, `Pre_COLA_Price__c`, `Final_Year_COLA_Calculated_Price__c`. Per audit `B-1`, these were confirmed to already persist (no-action, `afa43ba`).

**Note:** the prehook/posthook Apex are **not** in this metadata — they are RCA plugins registered via ORG CONFIG (ProcedurePlanOption / signal binding; e.g. the partner prehook on `1FYWC0000002W3r4AE`), not in the ESD XML or git. The fields above are the persisted *context bridge* between those hooks and the QLI/OrderItem targets.

### 2. Custom Metadata Types (config-as-code pricing)

| CMDT | Configures | Fields | Change | Ticket / D-item |
|---|---|---|---|---|
| `Hardware_Attribute_Pricing__mdt` | Hardware pricing tables moved out of Apex constants into admin-editable rows. `HardwarePricingCalculator` matches on exact strings. | `Table_Type__c` (Text, req — `pGroup`\|`UserTier`\|`SystemType`), `Attribute_Key__c` (Text — P05..P60 / Production,Staging,Test), `Min_Users__c`/`Max_Users__c` (Number,0 — UserTier band; blank Max = open-ended 501+ = 3.0×), `Value__c` (Number(18,4), req — multiplier for pGroup/UserTier, **discount percent** for SystemType) | **Added (behavior-preserving)** — `96a7f62` | **D-14.** 7 pGroup + 6 UserTier + 3 SystemType records present in `customMetadata/`. |
| `COLA_Uplift_Rules__mdt` | Per-solution-category COLA % lookup for the COLA engine | `Solution_Category__c` (Text, **unique externalId** — ProductCategory.Name), `Default_Uplift_Percent__c` (Number(5,2), req, e.g. 7.85), `Is_Active__c` (Checkbox, default true), `Effective_Start_Date__c` / `Effective_End_Date__c` (Date — effective-dating), `Description__c` (Text) | Present / effective-dating in use | COLA engine (D-13). 21 records (one per solution category: GoAnywhere, BoKS, Cybersecurity, …). |
| `MyCAP_Rules__mdt` | Multi-year out-year COLA defaulting + Deal-Desk approval threshold | `Default_Out_Year_Uplift_Percent__c` (Number(5,2), default 3.00), `Minimum_Out_Year_Uplift_Percent__c` (Number(5,2), default 3.00 — below this flags `Quote.Mycap__c` for approval), `Is_Active__c` (feature toggle) | Present (Global record) | **A-1** ruled: MyCAP = out-year floor. 1 record (`MyCAP_Rules.Global`). |
| `Order_Submit_Validation__mdt` | Config-driven required-field checks at order submit (`OrderSubmissionValidator`) | `Active__c` (Checkbox), `Object_API_Name__c`/`Object_Label__c`, `Field_API_Name__c`/`Field_Label__c`, `Relationship_Field_API_Name__c`, `Error_Message__c`, `Link_Message__c` (all Text) | Present | **SC-3291 (UAT-only)** submission-check config. ~42 records `X00001`…`X00043`. |
| `Country_Currency_Map__mdt` | (was) country→currency lookup | — | **RETIRED / deleted** — `4e5279b` (retire dead country-currency path + `CurrencySelectionService`); staged via `3a338ec` (D-15) | **D-15.** No longer exists in `force-app/**` (verified: 0 matches). Per-currency PBE is authoritative, not a country map. |
| `Currency_Conversion_Formula__mdt` | Would move currency-conversion formula off hard-coded FX to config-as-code | — | **DEFERRED — no change** | **D-21 / OQ-6** — owner-gated boundary decision, not implemented. *(Unverified in repo: no `Currency_Conversion_Formula__mdt` directory present — consistent with "deferred, no change".)* |

### 3. D-18 telemetry: `Fortra_Exception__e` / `Pricing_Exception__e` → `Exception_Log__c`

Two platform events, **identical field set**, both must be defined `PublishBehavior = Publish Immediately` (default *Publish After Commit* is discarded on rollback — the exact failing transactions D-18 needs). `Pricing_Exception__e` is the pricing-specific event; `Fortra_Exception__e` is the generalized twin published by `ExceptionLogger.log(...)` for callers without a bespoke event.

**Platform-event fields (both `Fortra_Exception__e` and `Pricing_Exception__e`):**

| Field | Type |
|---|---|
| `Source__c` | Text(80) — class/component that caught it |
| `Exception_Type__c` | Text(255) |
| `Message__c` | LongTextArea(32768) |
| `Stack_Trace__c` | LongTextArea(32768) |
| `Hook_Phase__c` | Text(20) — prehook/posthook phase |
| `Severity__c` | Text(10) — ERROR/WARNING/INFO |
| `Context_Id__c` | Text(18) — raw record/context id (no Quote/Order enrichment in v1) |
| `Transaction_Id__c` | Text(40) |
| `Occurred_At__c` | DateTime |

**Flow to durable store:** `ExceptionLogger` (`public inherited sharing`, author Liam Jeong) is a **never-throw** publisher — `safePublish()` wraps `EventBus.publish` in try/catch and never re-throws, so hooks can call it from catch-blocks that swallow-to-SUCCESS without turning a graceful degrade into a hard failure. It walks `getCause()` to the root, truncates to field lengths, and publishes. Delivery chain:

- `EventBus.publish` (Publish Immediately) → **PE-triggered subscriber Flow** → inserts `Exception_Log__c`.
- `Fortra_Pricing_Exception_Logger.flow-meta.xml` — trigger object `Pricing_Exception__e` → creates `Exception_Log__c` with `RecordTypeId` = **"Pricing Exception"** (looked up via a Get RecordType element). Runs in its own async transaction so it never rolls back with the failed reprice and consumes no pricing-transaction DML.
- `Fortra_Exception_Logger.flow-meta.xml` — generic twin, trigger object `Fortra_Exception__e` → same `Exception_Log__c` sink, same "Pricing Exception" RT.
- `Fortra_Exception_Log_Purge.flow-meta.xml` — **Scheduled**, Active, purges old `Exception_Log__c` rows (raw PE retained ~72h; durability lives in the log rows; design targets ~90-day retention — "[confirm]" in design doc).

**`Exception_Log__c`** (generalized, Record-Type-keyed durable store) mirrors the PE fields exactly: `Source__c`(80), `Exception_Type__c`(255), `Message__c`(LTA 32768), `Stack_Trace__c`(LTA 32768), `Hook_Phase__c`(20), `Severity__c`(10), `Context_Id__c`(18), `Transaction_Id__c`(40), `Occurred_At__c`(DateTime). Wired to all 8 pricing hooks; gate result was 13/13 golden 0-delta (`9bcf2f7`). Per-domain events are the generalization layer so future domains (Integration/Trigger/Batch) can adopt their own event + RT.

---
**Open items for the meeting:** (1) V23 + V24 both Active — cleanup pending; (2) `Currency_Conversion_Formula__mdt` (D-21/OQ-6) deferred, owner decision needed; (3) D-18 90-day retention window marked "[confirm]" in design doc; (4) prod flow-coverage gate before D-18 flows deploy to production (UAT sandbox not gated).

Key source paths: `force-app/main/default/objects/{QuoteLineItem,OrderItem,Hardware__c,Fortra_Exception__e,Pricing_Exception__e,Exception_Log__c,*__mdt}/fields/`, `force-app/main/default/customMetadata/`, `force-app/main/default/classes/ExceptionLogger.cls`, `force-app/main/default/flows/Fortra_{Pricing_,}Exception_Logger.flow-meta.xml` + `Fortra_Exception_Log_Purge.flow-meta.xml`, `docs/pricing-refactor/D18_TELEMETRY_DESIGN.md`, `docs/pricing-refactor/PRICING_REFACTOR_AUDIT_2026-07-10.md`.


---

# Appendix — Provenance & open items

**How V24 was captured for this dossier.** `sf project retrieve start --metadata ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure -o FortraUAT` (read-only) on 2026-07-10 → 137,807-line ExpressionSetDefinition containing all 24 versions inline. V24 (label "Rev Mgmt Default Pricing V24", `status Active`, `startDate 2026-06-18`, activated 2026-07-10 02:59) was extracted (block = 6,472 lines, 120 steps) and parsed into the 43-step execution map above. The repo's committed ESD copy was stale (V20 active) and was **not** used for the walkthrough.

**Open items to close (carried from the Wave-4 checklist & this analysis):**
1. **Deactivate V23** — org has V23 **and** V24 both Active; confirm V24 is runtime, deactivate V23, re-run the golden gate (0-delta).
2. **Commit + gate the working-tree changes** — `PartnerNetPricePosthook` (~+350), `CancelLineCreditPosthook` (~+195), and the COLA/maintenance/attribute calculators carry uncommitted edits; they are documented here as *proposed* until committed and golden-gated.
3. **D-3 / OQ-3** — retire `RenewalMaintenanceFlip` (unreferenced) once the owner rules.
4. **OQ-2 / D-10b** — decide whether Quote currency-change should convert prices (today the wired service is a no-op).
5. **D-21 / OQ-6** — currency config-as-code decision.
6. **D-23** — cosmetic V24 canvas step renames (16 dup-label groups, `Copy1ofCopy1of…` triad); rename-only, in-canvas.

**Standing constraint.** Every ESD edit is in-place on the active version, **canvas-only** (never MDAPI); classify formula-literal (no context resync) vs field-signature (resync + dual Quote/Order mapping). The golden gate requires a human to perform the reprices; snapshot + diff are read-only.

*This dossier was assembled from a 19-agent grounded analysis of the live V24 metadata and the `force-app` hook/service layer. Every quoted formula, filter, and field name traces to the retrieved metadata or a `.cls` file; items only knowable from org config are flagged.*
