# SC-3441 — Order Cancellation Line Item Displays Total Price as USD 0.00 Instead of Negative Amount

**Reporter:** Joe Romo · **Org:** FortraUAT (`00DWC000006eUFF2A2`, native Revenue Cloud Advanced / RLM) · **Shared procedure:** `Rev_Mgmt_Default_Pricing_Procedure` (Quote + Order) · **Owner of fix:** Liam · **Status: OPEN — fix built & deployed, not yet producing −3000.**

---

## The bug in one line
A user-initiated cancellation line (OrderItem `802WC00000OugI7YAJ`, Order **00095539**, Arcus Hosting, Qty **−1**, ListPrice 3000) shows **Total Price USD 0.00** instead of **−3000.00**.

## Root cause in one line
The native RLM waterfall produces **no priced row** for a cancel line (`PriceWaterfallIdentifier` null), so the **`NetUnitPrice` field stays null**; the active line-total formula `QuantityPrice64` computes `NetUnitPrice × LineItemQuantity = null × −1 = 0` → `TotalPrice 0`. No declarative step seeds `NetUnitPrice` on a non-COLA cancel line. **Correct credit = asset NET (`AssetActionSource.NetUnitPrice`), not catalog list** (77% of asset-source rows have net≠list; 907 have list 0 with nonzero net). For 00095539 the original sale was undiscounted ⇒ −3000 (net == list, coincidentally).

## Scope
**Systemic & deterministic:** 6/6 cancellation lines that actually ran the procedure are broken (UI cancellations); the only "working" negative lines are bulk-migrated rows that bypassed the procedure with a pre-stamped `UnitPrice`. Reproduces at Quote AND Order (one shared procedure).

---

## Document index
| File | What it is |
|---|---|
| **`01_RCA.md`** | Full root-cause dossier (incl. 3 adversarial reviews; the "V16 InputUnitPrice regression" rank-1 was corrected — load-bearing cause is null `NetUnitPrice` field). |
| **`02_ROADMAP.md`** | Phased fix roadmap (Phase 0 single-active version → Phase 1 native-vs-custom decision gate → build → validate → deploy → durability). Options A–E ranked. |
| **`03_FIX_IMPLEMENTATION_LOG.md`** | **What was actually built & deployed** (field, context, prehook, V18 block) and the exact point it currently stalls (`StampBaseFilter` BRE-00004). |
| **`04_SIMULATE_DEADEND_AND_PIVOT.md`** | Why Procedure Simulate cannot validate this fix (rejects `__c` input keys) + the committed pivot: prehook writes `NetUnitPrice` directly + queryable debug record. |
| **`JIRA_COMMENT.md`** | Status comment drafted for the ticket. |
| **`HANDOFF.md`** | Concise pick-up-here handoff. |
| `evidence/` | procedure step map, comparators, asset lineage, the failing reprice log, the deployed prehook class. |
| (raw artifacts) | `Data/sc3441/` — retrieves, deploy packages, deploy result JSONs, FINEST logs. |

---

## Current state (2026-06-25)
- ✅ **Built + deployed:** `CancelNetUnitPrice__c` on OrderItem+QuoteLineItem (+FLS); context `SalesTransactionContextExt_v2` hydration on both nodes; `CancelLineNetSeedPrehook` (registered in Plan `Fortra_Pricing_PreHook`); procedure **V18** with `CancelNetSeedContainer` (seq 13) — sole active version.
- ❌ **Not working yet:** reprice of the cancel line still errors at `StampBaseFilter` (criterion `NetUnitPrice > 0` on a still-null value) ⇒ `NetUnitPrice` is **still null** at seq 14 ⇒ the seed block didn't set it ⇒ likely the staging value `CancelNetUnitPrice__c` never reached runtime context (Path A republish failed) **or** the block didn't fire.
- 🔬 **Both diagnostic tools are exhausted:** FINEST can't see RLM pricing internals (opaque external code unit); Simulate rejects `__c` input keys (can't inject the staging value).

## Next step (committed pivot — see `04_…`)
1. **Prehook writes `NetUnitPrice` directly** (drop `CancelNetUnitPrice__c` + the gated Step-4 assignment) — removes the field/FLS/hydration/republish dependency entirely.
2. **Add a queryable debug record** the prehook writes every run — finally makes "did the prehook fire / resolve 3000 / write it" observable, ending the blind debugging.
3. Then reprice → query debug row → follow the decision tree in `04_…`.

---

## Hard constraints / gotchas (carry forward)
- **Each UAT deploy/DML needs a fresh explicit ack** ("Focus on UAT" ≠ deploy authorization).
- **Always re-pull the live active procedure version** — it drifts minute-to-minute (V9→…→V14→V16→V18 observed); co-owned by Nir / Marc DeBrey / Ben Kozlowski.
- **Never delete inactive procedure versions** (platform-blocked); deactivate only. Keep `PricingActionParameters` Quote/Order context bindings intact.
- **Any field used by the shared procedure must exist on BOTH QuoteLineItem AND OrderItem AND be hydrated on BOTH context nodes** (proven by the `Pre_Partner_Price__c` context-fetch hard-fail — see `project_v16_order_pricing_contextfetch_incident`).
- Procedure deploy: api 67 + `--metadata-dir`; orphan `rca_diagnostic.cls-meta.xml` blocks source-format ops; can't modify an ACTIVE version (deactivate→deploy→reactivate offline window); activation is UI-only.
- Procedure + prehooks are **UAT-only, 0% coverage**, prod cutover separately blocked.
