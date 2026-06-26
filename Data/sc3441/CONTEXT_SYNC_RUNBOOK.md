# SC-3441 — Context Sync / Runtime-Hydration RUNBOOK (read-only research; PREP ONLY)

**Org:** FortraUAT (00DWC000006eUFF2A2) · native RLM / Revenue Cloud Advanced
**Subject:** make a live reprice price a cancel line to the negative credit (NetUnitPrice × −1).
**Date:** 2026-06-25 · **Status of this doc:** research + runbook only. NO DML / NO activation / NO Sync performed.

---

## 0. ★ Live verification that REFRAMES the blocker (do not skip)

Verified live this session against FortraUAT (read-only tooling queries + a fresh `ContextDefinition` retrieve):

| What | Live value (2026-06-25) | Implication |
|---|---|---|
| Active **pricing procedure** version | **V16 (`9QBWC0000000niH4AQ`) = Active**; **V18 (`9QBWC0000000o3F4AQ`) = Inactive** | Drift recurred AND this time V18 was deactivated. **V16 executes live.** |
| Does V16 contain the `CancelSeed` block? | **NO** (`CancelSeed`/`CancelNetUnitPrice` absent from V16 Metadata) | The executing version has no step to consume the field → cancel line never seeded. |
| Does V18 contain the `CancelSeed` block? | **YES** (`CancelSeedNet` writes `CancelNetUnitPrice__c → NetUnitPrice`; `CancelSeedInput → InputUnitPrice`) | The fix lives only in the **inactive** version. |
| Context def active version | `SalesTransactionContextExt_v2` v23 (`11pWC000002TjF7YAK`, `isActive=true`) | Single active context version (no multi-active corruption right now). |
| Is `CancelNetUnitPrice__c` mapped for **runtime hydration** in the live active context? | **YES** — `contextAttrHydrationDetails`→`objectName=QuoteLineItem`/`OrderItem`, `queryAttribute=CancelNetUnitPrice__c`, on **both** Quote and Order `SalesTransactionItem` nodes (fresh retrieve, v23). | The runtime hydration query **already includes** the field. |
| Is the field actually in the live runtime context? | **YES**, reproducibly: `CancelNetUnitPrice__c={802WC00000OugI7YAJ=3000.0}` in `RLM_PRICING_BEGIN` across `log_latest.txt`, `log_1553.txt`, `log_1613.txt`; `={0QLWC000003YOW14AO=350.00}` on a valid **draft** quote line (`log_latest_check.txt`). | Hydration is NOT the gap. |

### Conclusion — the task's stated premise is partially falsified
The premise *"a live reprice does not hydrate `CancelNetUnitPrice__c` into the procedure context (stale runtime context), so the seed never fires"* is **not what the live evidence shows**. The field **is** hydrated into the live runtime context (both nodes, v23, value present in 4 logs). The seed never fires because **the active procedure version (V16) has no seed block** — the seed exists only in inactive V18. A draft cancel with the value in context still priced to 0 precisely because V16 was executing.

**Therefore the decisive action is procedure VERSION ACTIVATION (make V18 the sole-active executing version), not a context Sync.** A context Sync / runtime-schema-cache clear is still worth doing as a belt-and-suspenders step (cheap, supported) to guarantee the compiled runtime schema is current, but it is **secondary**, not the root fix. Run the version-activation path first; only fall to the full Sync if, after V18 is active and a Force-reprice still leaves `NetUnitPrice` null while the field is confirmed in context.

> Re-verify the active version immediately before acting — it oscillates day-to-day and is co-owned (Nir / Marc / Ben / Marc DeBrey).

---

## 1. Pre-checks (read-only; ~15 min)

1. **Re-confirm active procedure version** (it drifts):
   ```
   sf data query --use-tooling-api -o FortraUAT -q "SELECT Id, VersionNumber, Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinitionId='9QAWC0000003mg14AA' ORDER BY VersionNumber DESC"
   ```
   Record which version(s) are `Active` *before* touching anything (you must reactivate exactly these, never "Reactivate All").
2. **Confirm V18 still has the seed block** (don't trust a snapshot):
   ```
   sf data query --use-tooling-api -o FortraUAT -q "SELECT Metadata FROM ExpressionSetDefinitionVersion WHERE Id='9QBWC0000000o3F4AQ'" --json   # grep CancelSeed
   ```
3. **Confirm context active version + field mapping** (fresh retrieve):
   ```
   sf project retrieve start -o FortraUAT -m "ContextDefinition:SalesTransactionContextExt_v2" -r Data/sc3441/ctx_freshcheck
   # grep <queryAttribute>CancelNetUnitPrice__c</queryAttribute>  → expect 2 (Quote + Order node)
   ```
4. **Confirm the populator is in place** (the before-save trigger that persists `CancelNetUnitPrice__c`): `CancelLineNetSeedHandler` + `OrderItemTrigger` + `QuoteLineItemTrigger.handleQuoteLines`. Package staged at `Data/sc3441/triggers/`. If absent live, deploy it (separate ack) BEFORE the reprice test, else the field will be null and the seed has nothing to read.
5. **Pick a FRESH DRAFT cancel** as the test vehicle — never `00095539` (Activated/frozen) or `00095604`. A draft Cancellation Quote line, or a fresh draft cancel order. `OrderItemDetail`-locked lines can't be re-priced into the field.
6. **Enumerate bound dependencies** that must be deactivated before the context can be deactivated/synced (only needed for the Path B full Sync):
   - Pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` (ESD `9QAWC0000003mg14AA`) — active version (V16/V18).
   - 2nd ExpressionSet bound to the same context: `9QAWC000000C8mb4AC`.
   - Discovery/Rating procedure on the same context (`ProductDiscoveryContextExt` is separate, but verify no discovery proc points at `SalesTransactionContextExt_v2`).
   - Rule Libraries: DRORuleLibrary_v1 `9Q1WC0000000CHJ0A2`; Rule Library V4 `9Q1WC0000000Em90AE`.

---

## 2. PATH A — Procedure version activation (the actual fix; smallest blast radius) · DO THIS FIRST

This makes V18 (with the seed) the executing version. It does **not** touch the context.

1. Setup → **Pricing** (or **Revenue Settings → Pricing Procedures**) → open `Rev_Mgmt_Default_Pricing_Procedure`.
2. **Deactivate V16** via the UI (row action **Deactivate**). *DML flag-flip of `Status`/`IsActive` does NOT recompile — must be the UI action.*
3. **Activate V18** via the UI (row action **Activate**). Confirm V18 shows **Active** and V16 **Inactive** (single-active; no dual-active drift).
4. Confirm Revenue Settings still points the pricing procedure at context `SalesTransactionContextExt_v2` (the activate flow can prompt for the context — keep `SalesTransactionContextExt_v2`).
5. **Offline window:** ~2–5 min (the deactivate→activate gap is the only window; pricing fails for cancel+normal lines in between). Schedule with the co-owners.
6. Go to **§4 verify**. If the cancel line now prices to the negative → **DONE**; Path B (Sync) is unnecessary.

> Landmine to confirm gated out before trusting the result: V18 `DerivedPricingNetUnitPriceValueReset` (gated `ItemIsDerived__std=true`) and the unconditional MAX clamp `FormulaBasedPricing3` (seq ~36 in V18) — both can re-null/zero a now-non-null cancel `NetUnitPrice`/`TotalLineAmount`. The cancel line is non-derived so the reset should not fire; the MAX clamp needs a `LineItemQuantity >= 0` guard (separate, latent — bites the Subtotal, not the per-line TotalPrice).

---

## 3. PATH B — Full Context Sync / regenerate (ONLY if Path A insufficient)

Use ONLY if, after V18 is active, a Force-reprice leaves `NetUnitPrice` null *while the field is confirmed in the runtime context*. Supported by the Salesforce RLM deployment runbook ("Extend and **sync** the SalesTransaction context definition" alongside "confirm pricing procedure active" + "refresh Decision Tables").

### 3a. Lightest lever first — clear the runtime schema cache (no deactivation, no offline window)
The supported, documented action to make a **newly added attribute/mapping** part of the compiled runtime schema without a full deactivate cycle:
```
DELETE /services/data/v67.0/connect/context-runtime-schema/clear
```
The runtime schema cache is rebuilt on the next context-build (next reprice). This is the cheapest "regenerate runtime hydration" lever — try it before any deactivate/Sync. (Reversible; cache simply repopulates.)

### 3b. Sync the context definition (Setup UI action)
The **Sync** button is only enabled for **extended** context definitions that need an upgrade (auto-sync failed). `SalesTransactionContextExt_v2` is an extension of `SalesTransactionContext__stdctx` (see `inheritedFrom` in the metadata), so Sync may be applicable.
1. Setup → quick find **Context Definitions** → open `SalesTransactionContextExt_v2`.
2. If a **Sync** action is enabled (down-arrow next to the definition → **Sync**), run it. This re-pulls inherited structure/mappings into the extension and recompiles. If Sync is greyed out, the definition is already in sync — go to 3c.

### 3c. Full deactivate → edit/confirm mapping → reactivate (heaviest; only if 3a+3b don't recompile)
Rules (Salesforce docs): you can ADD nodes/attributes/mappings to an **active** context def, but the engine may not recompile them into runtime until reactivated; mappings can only be edited on an **inactive** def; a context def **cannot be deactivated while bound to active dependencies**.

**Order (deactivate dependents FIRST):**
1. **Deactivate the bound ExpressionSets** (UI Deactivate, NOT DML):
   - `Rev_Mgmt_Default_Pricing_Procedure` active version.
   - 2nd ExpressionSet `9QAWC000000C8mb4AC` (if active and bound to this context).
   - Any discovery/rating procedure bound to `SalesTransactionContextExt_v2`.
2. **Deactivate the Rule Libraries** bound to those expression sets: `9Q1WC0000000CHJ0A2`, `9Q1WC0000000Em90AE` (only if they block context deactivation).
3. **Deactivate the context definition** `SalesTransactionContextExt_v2` (UI). If it still errors "in use", an active dependency was missed — re-enumerate from the error.
4. With the context inactive, **confirm/re-save** the `CancelNetUnitPrice__c` mapping on both `SalesTransactionItem` nodes (it is already present — re-save forces recompile).
5. **Reactivate the context definition** (UI) — this recompiles the runtime hydration schema.
6. **Reactivate ONLY the dependencies that were active before** (the list recorded in §1.1 / §1.6). **NEVER use "Reactivate All" / `reactivateDependencies(null)`** — it reactivates ALL inactive versions → multi-active corruption. Reactivate the pricing procedure to **V18** (the seed-bearing version), the rule libraries, and any discovery proc, each by its previously-active version.
7. Refresh Decision Tables referenced by the pricing procedure (per the supported runbook) if the Sync touched DT-backed steps.

**Offline window for 3c:** ~15–30 min (all sales-transaction pricing + rules down for the whole org while the context + its expression sets are inactive). Owner-coordinated; this is the broad pricing+rules window the dossier warns about.

---

## 4. VERIFY loop (read-only after each path)

1. On the FRESH DRAFT cancel line, trigger a **Force reprice**:
   ```
   POST /services/data/v67.0/connect/rev/sales-transaction/actions/place
   { "pricingPref": "Force", ... graph for the draft quote/order ... }
   ```
   (`pricingPref:"Force"` = reprice all lines / force pricing — confirmed in the RLM dev guide. In the UI this is the **Reprice All** / **Update Prices** action.)
2. Capture FINEST. Confirm in `RLM_PRICING_BEGIN`:
   - `CancelNetUnitPrice__c={<lineId>=<net>}` present (hydration — already passing).
   - After the waterfall: `NetUnitPrice = <net>` (NOT null) on the cancel line → seed fired.
   - `StampBaseFilter` does NOT throw `SF-BRE-00004` (because `NetUnitPrice ≥ 0` now sees a value).
   - Line-total step: `NetUnitPrice × LineItemQuantity = net × −1 = −net` → **TotalPrice negative**.
3. Read back the saved line:
   ```
   sf data query -o FortraUAT -q "SELECT Id, Quantity, NetUnitPrice, TotalPrice FROM OrderItem WHERE Id='<lineId>'"
   ```
   Expect `TotalPrice = −net` (e.g. −3000).
4. **Decision tree:**
   - `NetUnitPrice` non-null + TotalPrice negative → ✅ DONE (Path A alone was enough).
   - Field in context but `NetUnitPrice` still null → seed gate/write not taking effect under the active version → re-confirm V18 (not V16) is active; if confirmed, run Path B 3a (cache clear) then re-verify; then 3b/3c.
   - Field NOT in context → populator (trigger) didn't persist the field for this line → fix the trigger path (see `Data/sc3441/triggers/`), not the context.

---

## 5. Rollback

- **Path A:** UI Deactivate V18 → UI Activate V16 (restores the prior executing version). 2–5 min.
- **Path B 3a:** none needed — the runtime schema cache simply repopulates on next build.
- **Path B 3c:** reactivate the context + each dependency to its **previously-active** version (the §1 list). If something won't reactivate, leave inactive versions in place (never hard-delete an ExpressionSetVersion — platform-blocked) and escalate. NEVER "Reactivate All."

---

## 6. Estimated offline windows (summary)

| Path | Action | Window |
|---|---|---|
| A | Deactivate V16 → Activate V18 | ~2–5 min |
| B-3a | `DELETE /connect/context-runtime-schema/clear` | ~0 (no pricing outage; cache rebuilds on next reprice) |
| B-3b | UI Sync (if enabled) | ~1–3 min |
| B-3c | Full deactivate dependents → reactivate | ~15–30 min (all pricing + rules down org-wide) |

---

## 7. Sources

**Live (FortraUAT, this session):** `ExpressionSetDefinitionVersion` query (V16 Active / V18 Inactive); V16 Metadata grep (no CancelSeed); V18 Metadata grep (CancelSeed present); `ContextDefinition`/`ContextDefinitionVersion` query (v23 active `11pWC000002TjF7YAK`); fresh `ContextDefinition:SalesTransactionContextExt_v2` retrieve → `Data/sc3441/ctx_freshcheck/...` (CancelNetUnitPrice__c `queryAttribute` on both nodes, `isActive=true` v23); logs `log_latest.txt` / `log_1553.txt` / `log_1613.txt` / `log_latest_check.txt` (field in context); `Data/sc3441/live_debug/V18_block.xml` (CancelSeedNet/CancelSeedInput).

**Salesforce docs:**
- RLM Developer Guide v67 (Summer '26) — deployment runbook "Extend and sync the SalesTransaction context definition"; `pricingPref` (Force/Skip/System); `/connect/rev/sales-transaction/actions/place` (POST); `PricingPreference` (Force = reprices all lines). https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/revenue_lifecycle_management_dev_guide.pdf
- View, Edit, and Delete Saved Context Definitions — Sync only for extended defs needing upgrade; add nodes/attrs/mappings to active def but can't edit/delete existing; runtime schema cache cleared via `DELETE /connect/context-runtime-schema/clear`. https://help.salesforce.com/s/articleView?id=ind.context_service_view_edit_saved_context_definitions.htm
- Context Definitions / Add Context Mapping — mappings only on inactive defs; create a mapping for any newly added attribute. https://help.salesforce.com/s/articleView?id=sf.context_service_context_definitions.htm , https://help.salesforce.com/s/articleView?id=ind.context_service_add_context_mapping.htm
- Activate a Context Definition (down-arrow → Activate). https://help.salesforce.com/s/articleView?id=ind.context_service_activate_context_definition.htm
- Context Definition for Pricing Procedure (applikontech) — if pricing/discovery procedure active, deactivate it, update context, re-activate procedure. https://applikontech.com/context-definition-for-pricing-procedure/
- RLM error "Ensure that the discovery procedure and pricing procedure are associated with same context definition". https://help.salesforce.com/s/articleView?id=002188066
