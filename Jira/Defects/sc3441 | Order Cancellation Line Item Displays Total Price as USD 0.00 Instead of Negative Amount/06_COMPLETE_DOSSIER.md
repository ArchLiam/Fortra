# SC-3441 — Complete Dossier (everything attempted)

**Ticket:** Order Cancellation Line Item Displays Total Price as USD 0.00 Instead of Negative Amount
**Reporter:** Joe Romo · **Owner (investigation):** Liam Jeong · **Org:** FortraUAT (RLM / Revenue Cloud Advanced)
**Repro:** Order 00095539 / OrderItem `802WC00000OugI7YAJ` (Arcus Hosting, Qty −1, ListPrice 3000, expected TotalPrice −3000). Same defect at the Quote stage (any Cancellation Quote, e.g. 00780682 / 00781318).
**Last updated:** 2026-06-25

---

## 1. The bug in one paragraph

When a user cancels an asset, RLM creates a **Quantity = −1** line. The native pricing procedure (`Rev_Mgmt_Default_Pricing_Procedure`) produces **no priced row** for that negative line, so the line's **`NetUnitPrice` stays null**. The active line-total formula is `NetUnitPrice × LineItemQuantity` → `null × −1 = 0`, so **TotalPrice = USD 0.00** instead of the expected negative credit. On a reprice the procedure step **`StampBaseFilter`** (criterion `NetUnitPrice ≥ 0`, which is *not* null-tolerant) throws **`SF-BRE-00004`**, surfacing as the red toast *"We couldn't refresh the prices… StampBaseFilter#1 isn't valid."*

**Blast radius:** 6/6 real-user cancellation lines over 4 months. Also gates the workflow — a Cancellation Quote stuck at `PriceCalculationFailed` **cannot be converted to an Order** at all.

**Correct value = asset NET × qty** (sourced from `AssetActionSource.NetUnitPrice` via `OrderAction/QuoteAction.SourceAssetId`). 77% of assets have net ≠ list, so a list-price shortcut would over/under-credit — the asset net is required.

---

## 2. ★ MOST IMPORTANT FINDING (2026-06-25, via Simulation) ★

**The pricing procedure is CORRECT. It is not the problem.** A Procedure **Simulation** of the active V18 against the cancel line `802WC00000OugI7YAJ` (with `CancelNetUnitPrice__c = 3000` present in the context) shows the full waterfall succeeding:

| seq | step | result |
|---|---|---|
| 2 | Attribute Discount Entries | Override → NetUnitPrice = 3000 |
| **5** | **Cancel Seed Net** | filter `CancelNetUnitPrice__c != null` → **TRUE** (`= 3000`) → **NetUnitPrice = 3000** |
| 6 | Cancel Seed Input | → InputUnitPrice = 3000 |
| 7 | StampBaseFilter (`NetUnitPrice ≥ 0`) | `3000 ≥ 0` → **passes, no BRE** |
| 10 | Quantity × Price | `3000 × −1` → **−3000** |
| — | **Net Amount** | **−$3,000 ✅** |

**Conclusion:** when `CancelNetUnitPrice__c` is in the evaluation context, the seed block fires and the procedure outputs the correct **−3,000**. The seed block, `StampBaseFilter`, and the line-total math all work.

**→ The remaining gap is purely RUNTIME HYDRATION:** a *live* reprice does **not** carry the saved `CancelNetUnitPrice__c` into the context, so the seed never fires. Independent proof: Force-repricing order 00095604 (which had `CancelNetUnitPrice__c = 3150` persisted) **nulled** `NetUnitPrice` → the seed did not fire → the field was absent from the live context.

This **overturns** the earlier (incorrect) conclusion that "the procedure can't credit cancel lines." It can. The fix is to make a live reprice hydrate `CancelNetUnitPrice__c` — most likely a **context Sync/regenerate** so the runtime hydration query includes the field (the mapping existing in the definition ≠ the compiled runtime query including it).

---

## 3. Everything attempted (chronological)

| # | Attempt | Outcome | Why it didn't (fully) work |
|---|---|---|---|
| 1 | **RCA + version cleanup** — found V16 & V18 both Active (dual-active drift); made V18 sole-active | Resolved drift | Recurs — always re-verify active version before acting |
| 2 | **Procedure seed block** `CancelNetSeed` (V18 seq 13): gate `CancelNetUnitPrice__c IsNotNull`, writes `→ NetUnitPrice` and `→ InputUnitPrice` | ✅ correct (Simulation proves it) | Needs the field present in the context to fire |
| 3 | **Custom field `CancelNetUnitPrice__c`** Currency(16,2) on OrderItem + QuoteLineItem (+FLS) and context mapping on both nodes | Deployed, mapping complete | Mapping present ≠ hydrated at runtime |
| 4 | **RevSignaling prehook** `CancelLineNetSeedPrehook` — resolves asset net, writes to context via `updateContextAttributes` | ❌ never reached the procedure input | Line-level write not routed (`line procedure plan setup = false`); landed too late |
| 5 | **Before-save Apex triggers** — `OrderItemTrigger` (new), `QuoteLineItemTrigger` (modified) → `CancelLineNetSeedHandler` stamps `CancelNetUnitPrice__c` from asset net | ✅ **works** — field persisted (3000/3150), verified | Correct delivery to the *record*; but live reprice still doesn't hydrate it |
| 6 | **Context Sync** hypothesis | Started, then abandoned | Refuted via Connect API showing the mapping present — **but §2 reopens this; the mapping ≠ runtime hydration** |
| 7 | **Procedure recompile** — DML flag-toggle of runtime `ExpressionSetVersion.IsActive`, then UI Deactivate→Activate of V18 | ❌ no change | A flag-flip / re-activate recompiles the procedure, not the context hydration |
| 8 | **Order-side direct `NetUnitPrice` write** (OrderItem.NetUnitPrice is writeable; QLI's is read-only) | ⚠️ **transient** | Correct at *insert* (−3,150, no procedure run); a reprice re-derives & nulls it; `OrderItemDetail` then locks the field |
| 9 | **Quote → Order conversion** as a path to test orders | ❌ blocked | Quote `PriceCalculationFailed` (the BRE) gates conversion entirely |
| 10 | **Simulation (§2)** | ✅ **−3,000** | Proves procedure correct; isolates the gap to live hydration |

### Hard constraints discovered (all proven live)
- `QuoteLineItem.NetUnitPrice` is **read-only** — cannot be stamped directly on quotes.
- `OrderItem.NetUnitPrice` is writeable **only before `OrderItemDetail` records exist** (created during pricing); after that, editing throws `INVALID_FIELD_FOR_INSERT_UPDATE`. So existing detailed cancel lines (incl. 00095539) can never be field-fixed.
- A live reprice **re-derives** `NetUnitPrice` from the waterfall and **nulls** it for cancel lines — so any insert-time write is wiped by the next reprice/activation.
- A Cancellation Quote at `PriceCalculationFailed` **cannot convert to an Order**.
- Procedure & context are **co-owned** (Nir/Marc/Ben/Marc DeBrey); the procedure drifts versions in days; context Sync requires deactivating shared dependencies (pricing V18 + Discovery procedure + Rule Libraries) = a broad pricing+rules window.

---

## 4. Current state of each surface

| Surface | At creation | After a reprice / live | Root |
|---|---|---|---|
| **Quote** total | 0 (NetUnitPrice read-only) | 0 + `PriceCalculationFailed` (blocks conversion) | live hydration gap |
| **Order** total | **−3,150 ✅** (trigger stamps NetUnitPrice at insert) | **0** (reprice re-derives null) | live hydration gap + reprice overwrite |
| **Procedure** (Simulation) | **−3,000 ✅** | n/a | correct — reads `CancelNetUnitPrice__c` |

---

## 5. The fix (current best understanding)

**The procedure already does the right thing.** Two delivery requirements remain:

1. **`CancelNetUnitPrice__c` on the record** — delivered today by the **before-save trigger** (`CancelLineNetSeedHandler`). Working.
2. **Live reprice must hydrate `CancelNetUnitPrice__c` into the context** — the missing piece. Most likely a **context Sync/regenerate** of `SalesTransactionContextExt_v2` so the runtime hydration query includes the field. (Alternative, owner-side: a procedure-internal derivation of the cancel net from a field the engine already hydrates — e.g. via the asset action — so no custom-field hydration is needed.)

**Open question to settle the path:** in the §2 Simulation, was `CancelNetUnitPrice__c = 3000` typed into the Input, or auto-hydrated from the record? Typed → confirms a pure live-hydration gap → **Sync is the fix**. Auto → hydration works in Simulate but not in live reprice → still a stale-runtime/Sync issue.

**Recommended next step:** re-attempt the **context Sync** (deactivate the bound expression-set versions + Rule Libraries, Sync the context, reactivate **only** the previously-active versions — never "Reactivate All"), then Force-reprice 00095604 and confirm NetUnitPrice survives at 3150. This is owner-coordinated (Nir/Marc) given the shared-dependency window.

---

## 6. Apex / config artifacts (inventory)

| Artifact | Type | Status | Disposition |
|---|---|---|---|
| `CancelLineNetSeedPrehook` (+ `...PrehookTest`) | Apex + Plan registration | **DEAD** — replaced by the trigger; never reached the procedure | **REMOVE** (deregister from Plan `Fortra_Pricing_PreHook`, delete classes) |
| `CancelLineNetSeedHandler` (+ `...HandlerTest`) | Apex class | **part of the fix** — stamps `CancelNetUnitPrice__c` that the procedure reads | **KEEP** (recommend dropping the dead order-side `NetUnitPrice` direct-write) |
| `OrderItemTrigger` | Apex trigger (new) | calls the handler | **KEEP** |
| `QuoteLineItemTrigger` | Apex trigger (modified) | one appended `handleQuoteLines` call | **KEEP** the call |
| `CancelNetUnitPrice__c` | field on OrderItem + QuoteLineItem | read by the procedure seed | **KEEP** |
| V18 `CancelNetSeed` block | procedure (ExpressionSetDefinitionVersion) | correct (Simulation) | **KEEP** |
| Context `SalesTransactionContextExt_v2` mapping | context definition | present; needs runtime Sync | **KEEP** + Sync |

**Disposable test data:** Orders 00095602 / 00095603 / 00095604 (Fortra LLC Test), test quotes 00781314/15/18.

---

## 7. Separate items (do NOT fold into SC-3441)
- **2nd repro line `802WC00000OgXD4YAN`** — zero net AND zero list on all AssetActionSource rows → unrecoverable data; separate ticket.
- **MAX clamp `FormulaBasedPricing3`** — zeroes negative `TotalLineAmount`; guard (`Quantity ≥ 0`) once the net is non-null; latent, not the ticketed cause.
- **Dual-active procedure drift** — recurs; re-verify the sole-active version before any procedure work.
