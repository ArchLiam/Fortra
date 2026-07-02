# SC-3441 — Fix Implementation Log (what was actually built & deployed)

**Status as of 2026-06-25: BUILT + DEPLOYED, but NOT yet producing −3000. Cancel line still errors/zeroes.**
**Approach taken:** Roadmap Option A (custom prehook + `CancelNetUnitPrice__c` staging field + gated procedure AssignmentElement). The native-LastTransaction probe (roadmap Phase 1) was NOT proven workable, so we proceeded with the custom fallback.

This log records every component that was created, deployed, and (where possible) verified, plus the exact point at which the fix currently stalls.

---

## 0. The chosen mechanism (custom seed path)

```
PREHOOK (CancelLineNetSeedPrehook)                  PROCEDURE (V18 active)                       RESULT
─ for cancel/neg-qty lines only:                    ─ new top-level ListGroup CancelNetSeed-      ─ NetUnitPrice = 3000 on the
  resolve asset NET via                               Container (seq 13), runs BEFORE              cancel line  →
  OrderAction.SourceAssetId →                         StampBaseFilter (seq 14) & QuantityPrice64  ─ TotalPrice = NetUnitPrice ×
  AssetActionSource.NetUnitPrice                       (seq 26):                                    LineItemQuantity
─ write that value into the                          • CancelNetSeedFilter (gate)                  = 3000 × −1 = −3000  ✅(intended)
  CONTEXT staging attribute                           • CancelSeedNet:  CancelNetUnitPrice__c
  CancelNetUnitPrice__c                                  → NetUnitPrice
  (via updateContextAttributes —                      • CancelSeedInput: CancelNetUnitPrice__c
   NOT SObject DML)                                       → InputUnitPrice
─ positive lines: never touched
```

The staging field is required because the cancel `OrderItem` has **no runtime pointer to the asset net** (`Asset__c` / `OriginalOrderItemId` / `PriceRevisionPolicyId` all null), so the procedure cannot reach `AssetActionSource.NetUnitPrice` declaratively — only the prehook (Apex SOQL) can resolve it.

---

## 1. Custom field — `CancelNetUnitPrice__c` (DEPLOYED ✅)

Created on **BOTH** objects (shared-procedure rule; proven mandatory by the `Pre_Partner_Price__c` context-fetch incident — see `project_v16_order_pricing_contextfetch_incident`):

| Object | Path | Type |
|---|---|---|
| OrderItem | `force-app/main/default/objects/OrderItem/fields/CancelNetUnitPrice__c.field-meta.xml` | Currency(18,2) |
| QuoteLineItem | `force-app/main/default/objects/QuoteLineItem/fields/CancelNetUnitPrice__c.field-meta.xml` | Currency(18,2) |

- Deploy package: `Data/sc3441/deploy_seed_fields/` (package.xml v66).
- `description`/`inlineHelpText` mark it system-managed, not user-edited.
- **FLS:** mirrored from the proven `Pre_Partner_Price__c` grants onto both objects via permission sets only (script `scratchpad/mirror_cancel_fls.apex` — copies Read/Edit from every non-profile FieldPermissions parent). Profiles untouched.

## 2. Context definition — `SalesTransactionContextExt_v2` (DEPLOYED ✅, active ctxV23)

`CancelNetUnitPrice__c` added in two places, on **both** nodes:
- **Structure** (`<contextAttributes>`): the attribute itself.
- **Mappings** (`<contextAttributeMappings>` → `<contextAttrHydrationDetails>`): hydrated `objectName=OrderItem`/`QuoteLineItem`, `queryAttribute=CancelNetUnitPrice__c`, on node `SalesTransactionItem` for **both** QuoteEntitiesMapping AND OrderEntitiesMapping.
- Retrieve/deploy artifacts: `Data/sc3441/contextdef*/`. Active version **ctxV23** (lastMod 2026-06-04 baseline; our edit layered on top).

> ⚠️ Open question flagged below (§6): whether our hydration edit actually **republished** into the running context. "Path A" (delete + re-add mapping, reprice) was attempted and **did not change the outcome**.

## 3. Prehook Apex — `CancelLineNetSeedPrehook` (DEPLOYED ✅)

- `Data/sc3441/prehook/CancelLineNetSeedPrehook.cls` (822 lines) + `CancelLineNetSeedPrehookTest.cls` (735 lines).
- Implements `RevSignaling` / `SignalingApexProcessor` (`execute()`), writes via `Context.IndustriesContext.updateContextAttributes` — **never** SObject DML.
- **Asset-net resolution (SOQL verified live):**
  - Order line: `OrderItem.Id → OrderAction.SourceAssetId → AssetActionSource.NetUnitPrice` (AssetAction `Type='Generate'`, `CategoryEnum='Initial Sale'`).
  - Quote line: `QuoteLineItem.Id → QuoteAction.SourceAssetId → AssetActionSource.NetUnitPrice`.
  - Verified: `802WC00000OugI7YAJ → 8OAWC000002SxiL4AS (Cancel) → SourceAssetId 02iWC000008MpX7YAK → AAS 4nMWC0000046hkj2AA (Generate/Initial Sale) NetUnitPrice 3000 USD.`
- **Scope/guard logic (mirrors the working `COLAUpliftPrehook`):**
  - `resolveScope()`: `dataPath[0].startsWith('801')` ⇒ Order, `'0Q0'` ⇒ Quote.
  - `collectCancelLines()`: qty<0 via `TAG_QUANTITY='Quantity'`; lineId via `Id.valueOf(dataPath.get(dataPath.size()-1))`.
  - `buildSeedUpdates()`: **skips when seedNet == null || <= 0 — NEVER writes null, never clobbers** a good price, never touches positive lines.
- **Plan registration:** registered as an ordered Apex section in the Procedure Plan **`Fortra_Pricing_PreHook`** (version `1CvWC0000005vyX0AQ`), at the prehook section position. Plan activated. (Prehooks live in the Plan objects, NOT in the procedure metadata.)

## 4. Procedure delta — V18 (DEPLOYED + ACTIVE ✅)

- Active version when work began drifted V14→V16; we cloned **V16 → V18 via the UI** (metadata clone V16→V17 failed: "ExpressionSetDefinitionVersion not found" cross-slot reference). V17 deprecated. V18 = `9QBWC0000000o3F4AQ`, created 2026-06-25T04:15:46Z.
- **Active-version state (live 2026-06-25 — CORRECTS the earlier "V18 sole active"):** user deactivated V16 when V18 went active, but a live `ExpressionSetDefinitionVersion` query found **both V16 (`9QBWC0000000niH4AQ`) and V18 (`9QBWC0000000o3F4AQ`) Active again** — the documented version-drift/oscillation recurred. RLM resolves to the highest number ⇒ **V18 executes**, but V16 should be re-deactivated for determinism (do NOT delete — platform-blocked). Always re-pull the live active-version list before any edit.
- **New top-level ListGroup `CancelNetSeedContainer` (sequenceNumber 13)** — deliberately **before** `StampBaseFilter` (seq 14) and `QuantityPrice64` (seq 26). Children:
  1. `CancelNetSeedFilter` (AdvancedListFilter, seq 1) — gate.
  2. `CancelSeedNet` (AssignmentElement, seq 2): `CancelNetUnitPrice__c → NetUnitPrice`.
  3. `CancelSeedInput` (AssignmentElement, seq 3): `CancelNetUnitPrice__c → InputUnitPrice`.
- **Gate (final, null-safe):** `CancelNetUnitPrice__c IsNotNull AND NetUnitPrice IsNull`.
  - Earlier gate `LineItemQuantity < 0` caused **BRE-00004** (non-null-safe comparison on a null) → replaced with the IsNotNull/IsNull form.
- Structurally **identical to the proven COLA group** (`ListContainer2`/COLA renewal), which is the one known-working declarative writer of the `NetUnitPrice` field.
- Deploy mechanics: api 67 + `--metadata-dir` (orphan `rca_diagnostic.cls-meta.xml` blocks source-format ops); **active version can't be modified** ("deactivate it and try again") → deactivate V18 → deploy → reactivate, in an offline window (user: "i can wait. nobody is using pricing now"). Artifacts: `Data/sc3441/proc_v18/`, `proc_verify2/`, `v18_step4_deploy.json`, `v18_gatefix_deploy*.json`.

---

## 5. CURRENT FAILURE POINT (where it stalls)

After all of the above is deployed and active, repricing the cancel line **still does not yield −3000**. The reprice surfaces an error at:

> **V18 step `StampBaseFilter` (was `StampContributorBaseFilter` in V16), gate criterion 5 = `NetUnitPrice GreaterThan 0` → SF-BRE-00004 / SF-Pricing-00006 "resources don't have corresponding values for evaluation"** — a non-null-safe `>` on a still-null `NetUnitPrice`.

Full gate of `StampBaseFilter`: `(1 OR 2) AND 3 AND 4 AND 5`:
1. `ItemIsDerived__std IsNull`  2. `ItemIsDerived__std = false`  3. `QuoteTypeText__c ≠ 'Renewal'`  4. `ItemPricingSource ≠ 'LastTransaction'`  5. **`NetUnitPrice GreaterThan 0`** ← errors on null.

**Interpretation:** `NetUnitPrice` is **STILL NULL** when execution reaches `StampBaseFilter` (seq 14). That means our `CancelNetSeedContainer` (seq 13) **did not set `NetUnitPrice`** — either it didn't execute, or its gate `CancelNetUnitPrice__c IsNotNull` was false because **`CancelNetUnitPrice__c` never arrived in the runtime context**.

### Two candidate causes (not yet isolated)
- **(a) The staging value isn't reaching runtime context.** Either the prehook isn't firing / isn't writing, OR the context hydration of `CancelNetUnitPrice__c` was never actually republished (Path A delete+re-add+reprice **failed to change anything**, which points here). → `CancelNetUnitPrice__c IsNull` at seq 13 → seed gate false → `NetUnitPrice` stays null → BRE at seq 14.
- **(b) The seed block doesn't execute / doesn't write** despite being structurally identical to COLA.

### Tests already run (and their verdict)
- Manual `OrderItem.CancelNetUnitPrice__c = 3000` + reprice → **still failed.** (Consistent with (a)-hydration OR (b); a manually-stamped SObject value still has to be hydrated into context to satisfy the seq-13 gate.)
- FINEST Apex debug log on the reprice → **cannot see procedure internals.** RLM pricing runs as an external managed code unit ("Get context price…") that emits NO internal step detail (only `CalculationStatus Saving → PriceCalculationFailed`). The prehook's own SOQL is inside that opaque unit → not logged. **This is why FINEST cannot confirm whether `NetUnitPrice` changed — confirmed honestly to the user.**
- Procedure **Simulate** (the only sanctioned per-step observability) → **DEAD END.** See `04_SIMULATE_DEADEND_AND_PIVOT.md`: Simulate structurally rejects `__c` custom-field keys (`INVALID_INPUT: Invalid tag attribute name key: <field>__c`), and our entire mechanism is a `__c` field, so Simulate can **never** exercise this fix.

---

## 6. What is PROVEN vs UNPROVEN

**Proven:**
- RCA: null `NetUnitPrice` field, asset net = 3000, systemic (6/6 UI cancellations), value = asset NET not list (77% net≠list). (`01_RCA.md`)
- Asset-net resolution SOQL returns 3000 for the subject line.
- The prehook never clobbers / never writes null / never touches positive lines.
- The seed block is structurally identical to the known-working COLA `NetUnitPrice`-field writer.
- Field + context + prehook + V18 block are all DEPLOYED and V18 is the sole active version.

**Unproven (the gap):**
- Whether the prehook actually **fires** at runtime (unobservable in FINEST).
- Whether `CancelNetUnitPrice__c` is actually **hydrated into the runtime context** (Path A republish failed).
- Whether `CancelNetSeedContainer` actually **executes and writes `NetUnitPrice`**.

All three are blocked by the same wall: **RLM pricing internals are unobservable** in FINEST, and Simulate (the one tool that shows them) won't accept a `__c` input.

---

## 7. Deploy/verify artifact index (under `Data/sc3441/`)

| Artifact | Path |
|---|---|
| Field deploy | `deploy_seed_fields/` |
| Context def retrieve/deploy | `contextdef/`, `contextdef2/`, `contextdef_verify/`, `ctxdef_deploy.json` |
| Prehook class + test | `prehook/`, `prehook_deploy/`, `prehook_deploy_result.json` |
| V18 procedure | `proc_v18/`, `proc_verify2/`, `v18_step4_deploy.json`, `v18_gatefix_deploy*.json` |
| Step-4 templates | `step4/tmpl_{container,filter,assignment}.xml` |
| Failing reprice log | `reprice_v18.log` (snapshot in this dossier's `evidence/`) |
| Live procedure retrieve (V16, 92,611 lines) | `retrieve/unpackaged/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` |
| Step map / comparators / lineage | `procedure_step_map.md`, `comparators.md`, `lineage.md` (in `evidence/`) |
