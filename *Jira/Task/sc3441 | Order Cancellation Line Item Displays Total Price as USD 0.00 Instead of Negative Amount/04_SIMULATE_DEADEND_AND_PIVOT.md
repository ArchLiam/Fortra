# SC-3441 — Simulate Dead-End + Pivot Plan

**Date:** 2026-06-25. **Decision:** stop using Procedure Simulate to validate this fix; pivot to a prehook that writes `NetUnitPrice` directly + a queryable debug record for observability.

---

## 1. Why Simulate is a dead end (decisive, confirmed)

Procedure **Simulate** is the only sanctioned tool that shows per-step internals (`simulationStepResults`, the per-step `NetUnitPrice`). We tried to use it to answer the one open question: *does `CancelNetSeedContainer` set `NetUnitPrice=3000` when `CancelNetUnitPrice__c` is provided?* It failed three independent ways:

1. **Endless required variables.** Simulate demanded every required input variable, then every field *inside* each nested array (`SalesTransactionItemAttribute`, `ContributorPriceDetail`, `SalesTrxnItemRelationship` → `Attribute`, `ContributorScope`, `RootItemProduct`, … `MainItemProduct`). Filling them just revealed more.
2. **Placeholder values rejected.** Auto-filled `<<Text>>` / `<<Currency>>` / `<<Boolean>>` placeholders → `INVALID_INPUT`.
3. **★ FATAL — custom fields are not accepted as input keys.** Providing any `__c` field as an input key returns:
   ```json
   { "error": { "errorCode": "INVALID_INPUT",
                 "errorMsg": "Invalid tag attribute name key: Total_Discount_Amount__c" },
     "simulationResults": [], "simulationStepResults": {} }
   ```
   (executionId 3732eea8-c7bc-487f-8039-f8332b39b808). It rejects the **first** `__c` key it hits.

**Why this is fatal for THIS fix specifically:** the entire mechanism hinges on supplying `CancelNetUnitPrice__c = 3000` and observing whether `NetUnitPrice` becomes 3000. If Simulate cannot accept `__c` keys, we **cannot inject the staging value**, so Simulate can never exercise the cancel-seed path. Removing the `__c` fields to satisfy the validator also removes the very input under test. → **Simulate cannot validate a custom-field-based pricing fix. Abandoned.**

---

## 2. The pivot (commitment made to the user)

Replace the indirect, unobservable staging path with a **direct, observable** one:

### Change 1 — Prehook writes `NetUnitPrice` DIRECTLY (drop the staging field + Step 4)
- Have `CancelLineNetSeedPrehook` write the resolved asset net **straight onto the context `NetUnitPrice` attribute** for cancel lines, instead of into `CancelNetUnitPrice__c`.
- This **eliminates three failure points at once**: the `CancelNetUnitPrice__c` field, its dual-object FLS, its context hydration/republish (the part Path A could never confirm), and the gated `CancelNetSeedContainer` AssignmentElement.
- Net result the procedure sees: `NetUnitPrice` already non-null at seq 13 ⇒ `StampBaseFilter` criterion 5 (`NetUnitPrice > 0`) no longer hits null ⇒ BRE-00004 resolved ⇒ `QuantityPrice64` computes `3000 × −1 = −3000`.
- Keep the same guards: cancel/neg-qty only, skip when net null/≤0, never clobber, never touch positive lines.

> Caveat to verify first: writing `NetUnitPrice` from a prehook must be **accepted by the engine** (context attribute is writable in the prehook stage) AND must **survive** the native waterfall (not be overwritten back to null). If the native waterfall later nulls it, write may need to land in a posthook or the seed block must stay. The direct-write removes the hydration dependency regardless.

### Change 2 — Add a QUERYABLE debug record (end the blindness)
- Have the prehook insert/upsert a small debug record (custom object or a `CalculationProcessLog`-style sink) on **every** run capturing: scope (Order/Quote), lineIds seen, qty, whether each line was classed as cancel, the resolved `SourceAssetId`, the resolved `AssetActionSource.NetUnitPrice`, and what it wrote.
- Then: reprice → **query the debug record** → finally *see*, with zero ambiguity, whether the prehook fired, detected the cancel line, resolved 3000, and wrote it.
- This is the observability FINEST and Simulate both denied us.
- **Risk to verify:** RLM prehooks may run in a restricted context where DML throws. The existing prehooks (RegionalServices, COLA) only do SOQL + `updateContextAttributes`, never DML. If prehook DML throws, the swallow-and-return-SUCCESS pattern would hide it — so wrap the debug DML in its own try/catch and confirm a row actually lands on a known reprice before trusting absence-of-row as signal. If DML is disallowed, fall back to `Database.insertImmediate`/Platform Event, or a posthook that records context state.

---

## 3. Decision tree after the pivot

```
reprice the cancel line with the direct-write prehook + debug record
│
├─ debug row shows prehook fired + resolved 3000 + wrote NetUnitPrice
│   ├─ cancel line now −3000  ........................  ✅ DONE
│   └─ cancel line still 0 / still BRE
│        → native waterfall overwrote NetUnitPrice back to null
│        → move the write to a POSTHOOK (after waterfall) or keep the
│          seed block but feed it from the direct context write
│
├─ debug row shows prehook fired but resolved net = null
│   → asset-net SOQL path wrong for THIS line at runtime
│     (dataPath/lineId parse, or SourceAssetId null at prehook time)
│   → fix the resolver; re-run
│
└─ NO debug row at all
    → prehook is NOT firing (plan registration / activation / signal scope)
    → fix Plan Fortra_Pricing_PreHook registration; re-run
```

Every branch is now **observable** via the debug row — no more guessing against an opaque engine.

---

## 4. Why not keep chasing the native LastTransaction path?
The roadmap's preferred Option (native `Asset.PricingSource='LastTransaction'` carryover, zero shared-procedure blast radius) was not proven workable in Phase 1: the org's assets do not carry `LastTransaction` provenance for these cancellations, and forcing it is a data/activation gap of unknown size. The custom path is already built; the pivot makes it observable rather than starting over. Revisit native only if the direct-write prehook also proves unviable.

---

## 5. Open, separate items (do NOT fold into SC-3441)
- **2nd broken line `802WC00000OgXD4YAN`** (zero net AND zero list) — a data defect, separate ticket.
- **Unconditional MAX clamp** `FormulaBasedPricing3` (seq 37) zeroes negative `TotalLineAmount` → will corrupt `Subtotal`/`ItemSubtotal` on cancel lines once `NetUnitPrice` is non-null. Fold the guard (`LineItemQuantity >= 0`) into the fix's validation (Roadmap Option D) — it is NOT the cause of the ticketed `TotalPrice=0`, but it bites next.
