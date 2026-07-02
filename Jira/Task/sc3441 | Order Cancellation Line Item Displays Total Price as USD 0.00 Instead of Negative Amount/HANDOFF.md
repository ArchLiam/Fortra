# SC-3441 — HANDOFF (pick up here)

**Goal:** make the cancellation line on Order **00095539** / OrderItem `802WC00000OugI7YAJ` show **TotalPrice −3000.00** (currently 0.00).

## Where it stands
- RCA is final (`01_RCA.md`): null `NetUnitPrice` field on cancel lines → `TotalPrice = null × −1 = 0`. Correct value = asset NET `AssetActionSource.NetUnitPrice` = 3000 (net==list here, coincidentally).
- Fix built & deployed via **custom seed path** (`03_FIX_IMPLEMENTATION_LOG.md`): field `CancelNetUnitPrice__c` (OrderItem+QLI+FLS), context hydration on both nodes, prehook `CancelLineNetSeedPrehook` (in Plan `Fortra_Pricing_PreHook`), procedure **V18** (`9QBWC0000000o3F4AQ`) `CancelNetSeedContainer` (seq 13). **Active-version (live 2026-06-25): V16 + V18 BOTH Active again (drift recurred); V18 executes (highest); re-deactivate V16.**
- **Still failing:** reprice errors at `StampBaseFilter` (`NetUnitPrice > 0` on null) ⇒ `NetUnitPrice` still null at seq 14 ⇒ seed block didn't set it ⇒ staging value almost certainly never reached runtime context (Path A republish did nothing) or block didn't fire.

## The wall
- FINEST log: **cannot** see RLM pricing internals (opaque external "Get context price" unit).
- Procedure Simulate: **rejects `__c` input keys** (`INVALID_INPUT: Invalid tag attribute name key`) → can't inject `CancelNetUnitPrice__c` → can't validate this fix. **Dead end.** (`04_…`)

## Do next (the pivot — `04_SIMULATE_DEADEND_AND_PIVOT.md`)
1. **Rewrite the prehook to write `NetUnitPrice` directly** for cancel lines (drop `CancelNetUnitPrice__c` + the seq-13 assignment). Removes field/FLS/hydration/republish dependency at once.
2. **Add a queryable debug record** the prehook writes every run (scope, lineIds, qty, resolved SourceAssetId, resolved AssetActionSource.NetUnitPrice, what it wrote). Wrap its DML in its own try/catch; confirm a row actually lands.
3. Get fresh deploy ack → deploy → **authorized reprice** → query debug row → follow the decision tree in `04_…`:
   - row shows fired+resolved+wrote & line=−3000 → ✅ done;
   - wrote but still 0/BRE → native waterfall re-nulled it → move write to a posthook;
   - resolved net=null → fix resolver;
   - no row → prehook not firing → fix Plan registration.

## Verified runtime facts (don't re-derive)
- `802WC00000OugI7YAJ → OrderAction 8OAWC000002SxiL4AS (Cancel) → SourceAssetId 02iWC000008MpX7YAK → AssetActionSource 4nMWC0000046hkj2AA (Generate/Initial Sale) NetUnitPrice 3000 USD.`
- Quote twin: `0QLWC000003fKAj4AM → QuoteAction 7ocWC00000upzpBYAQ → same asset.`
- Active proc: **V18** `9QBWC0000000o3F4AQ` (re-pull live before any edit — drifts; V16 re-activated 06-25). ExpressionSetDefinition `9QAWC0000003mg14AA`.

## Separate tickets (don't fold in)
- 2nd broken line `802WC00000OgXD4YAN` (zero net AND zero list) = data defect.
- Unconditional MAX clamp `FormulaBasedPricing3` (seq 37) will corrupt `Subtotal` on cancel lines once net is non-null — guard with `LineItemQuantity >= 0`.

## Constraints
Fresh ack per UAT deploy/DML · always re-pull live proc version · never delete inactive versions (deactivate only) · shared-procedure field must be on both objects + both context nodes · proc/prehooks UAT-only 0% coverage, prod cutover blocked.
