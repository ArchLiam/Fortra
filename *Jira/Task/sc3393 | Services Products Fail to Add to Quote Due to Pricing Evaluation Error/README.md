# SC-3393 — Services Products Fail to Add to Quote Due to Pricing Evaluation Error

**Type:** Critical | **Reporter:** German Wren | **Assignee:** Liam Jeong | **Org:** FortraUAT
**Investigation:** 2026-06-11, READ-ONLY (SOQL + metadata retrieve; no DML, no deploy, no record edits)

---

## TL;DR / Summary

Adding any of five **Services/Training products** to a US/USD quote fails with a managed RLM pricing-engine
error and the quote keeps **0 lines**. The failure was introduced on **2026-06-10** by version **V10** of
the active pricing procedure `Rev_Mgmt_Default_Pricing_Procedure`, which added a new top-level **`RegionalNetReconcile`**
ListGroup whose entry filter **`RegionalNetReconcileGate`** does an **un-null-guarded `GreaterThan 0` comparison
on `RegionalNetUnitPrice__c`**.

The five products carry `Allow_Regional_Pricing__c = TRUE` (a "Services only" flag). On a quote line this
makes the gate's first criterion (`AllowRegionalPricing__c Equals true`) pass, so the engine must evaluate the
second criterion (`RegionalNetUnitPrice__c GreaterThan 0`). On a **US** line `RegionalNetUnitPrice__c` is **never
populated** — the source field `QuoteLineItem.Regional_NetUnit_Price__c` has **no default** (null on a fresh line)
and `RegionalServicesPricingPrehook` is a **no-op for US** (multiplier 1.0, writes nothing). The gate's
value-comparison resource therefore has **no value to evaluate**, producing:

- `SF-Pricing-00006` (outer, pricing orchestrator) → `SF-BRF-00004` (inner, BRF+ rules engine): *"couldn't
  simulate the step because one or more specified resources don't have corresponding values for evaluation."*

Non-Services products (`Allow_Regional_Pricing__c = false`) fail criterion 1 and **short-circuit** — never reaching
the broken comparison — which is exactly why only the Services products break, and why everything else still adds fine.

**Root mechanism (refined):** an **un-null-guarded value comparison on a never-hydrated input resource**. The
context attribute *is* present in the active runtime context (H2 refuted), but on a US line nothing ever writes a
value into it, so at the gate it presents as a resource with **no corresponding value** — the literal text of the error.

**Recommended fix (see `02_ROOT_CAUSE_AND_FIX_SPEC.md`):** make the gate null-safe by adding a leading
`RegionalNetUnitPrice__c IsNotNull` guard (procedure-only change, no data/context republish). The data default
(`Regional_NetUnit_Price__c` default = 0) is a strong, low-risk complement.

---

## The Error

Surfaced in the quote UI on Add-Product:

> Your quote was not updated. **SF-Pricing-00006**: The value specified for the evaluation resource for
> **RegionalNetReconcileGate#1** isn't valid. Enter a valid value for the evaluation resource and try again.
> **SF-BRF-00004**: We couldn't simulate the step because one or more specified resources don't have
> corresponding values for evaluation.

Two layers, wrapping each other:

| Code | Layer | Meaning |
|------|-------|---------|
| `SF-BRF-00004` | BRF+ / Business Rules engine (inner) | Tried to **simulate** an ExpressionSet step; a resource the step names has **no corresponding value** in the evaluation bag. |
| `SF-Pricing-00006` | RLM pricing orchestrator (outer) | Caught the BRF failure on a named step (`RegionalNetReconcileGate#1`) and re-surfaced it as an invalid evaluation resource. |

`#1` = criterion-level reference inside the gate's `AdvancedListFilter`. The error is raised **inside the managed
pricing engine** and does **not** emit to Apex debug logs (confirmed: the literal strings appear in zero Apex logs today).

---

## Reproduction Context

**Failing quote** `0Q0WC0000037tXV0AY` ("Q-Wren - Test Services", #00781060, **Draft**, LineItemCount = 0)
- Account: **OhioHealth Corporation** | BillingCountry = **United States** | ShippingCountry = United States
- CurrencyIsoCode = **USD** | Pricebook = "Fortra Price Book" (`01sWC0000022GHFYA2`)
- US/USD ⇒ `RegionalServicesPricingPrehook` is a **NO-OP** (default multiplier 1.0, writes nothing).

**The 5 products that fail** — all `Product2.Allow_Regional_Pricing__c = TRUE`:

| Product2 Id | Name | SKU | Family |
|-------------|------|-----|--------|
| 01tWC00000DD115YAD | 24 X 7 X 365 Monitoring | VM-DDL-NRSU-2X7X3M | Services |
| 01tWC00000DD17hYAD | CSCO I & II Course | OS-COS-NRST-CIICS | Services |
| 01tWC00000DD11VYAT | Administering Automated Password Management | IGA-AAS-NRST-ADMIAP | Training |
| 01tWC00000DD11xYAD | AIC Expert Services | RPA-AUT-RSP-AICEXP | Services |
| 01tWC00000DD148YAD | Automate Expert Services | RPA-AUT-RSP-AUEX | Services |

**Control** `01tWC00000FBWonYAH` "24 X 7 X 365 Monitoring (Technical)" — `Allow_Regional_Pricing__c = FALSE`; adds fine.
Product2 field help text: *"Services products only."*

---

## Mechanism — step-by-step causal chain

1. **Add-Product copies the flag.** RLM's native Add-Product copies `Product2.Allow_Regional_Pricing__c = true`
   (same API name) onto the new `QuoteLineItem.Allow_Regional_Pricing__c`. No flow/trigger/Apex writes this field;
   it is a checkbox defaulting to `false`, set `true` only via the Product2 mirror for Services/Training products.

2. **Context hydration.** The active context `SalesTransactionContextExt_v2` v23 maps, on the `SalesTransactionItem`
   node, `QuoteLineItem.Allow_Regional_Pricing__c → AllowRegionalPricing__c` and
   `QuoteLineItem.Regional_NetUnit_Price__c → RegionalNetUnitPrice__c` (both `inputoutput`, hydrated from real QLI
   fields). On this US line the hydrated values are: `AllowRegionalPricing__c = true`, `RegionalNetUnitPrice__c = null`
   (source field has no default and was never written).

3. **Pricing procedure runs the new gate.** Active version **V12** executes the top-level `RegionalNetReconcile`
   ListGroup (seq 33). Its entry filter `RegionalNetReconcileGate` (`AdvancedListFilter`, `conditionLogic "1 AND 2"`):
   - **crit1:** `AllowRegionalPricing__c Equals true` → **TRUE** (flag copied from Product2).
   - **crit2:** `RegionalNetUnitPrice__c GreaterThan 0` → engine must read `RegionalNetUnitPrice__c` to compare it
     to literal `0`.

4. **The comparison resource has no value.** `RegionalNetUnitPrice__c` was never hydrated on this US line. BRF+
   cannot simulate a `GreaterThan` on a resource with no corresponding value → **SF-BRF-00004**, wrapped by the
   pricing layer as **SF-Pricing-00006 / RegionalNetReconcileGate#1**. The Add fails; the quote stays at 0 lines.

5. **Non-Services short-circuit.** For a product with `Allow_Regional_Pricing__c = false`, crit1 is FALSE; under
   `1 AND 2` the engine never evaluates crit2, so the missing-value condition never arises → the line adds normally.

**Exact resources at the gate:**
- crit1 `sourceFieldName = AllowRegionalPricing__c` (boolean, always present — checkbox, never null)
- crit2 `sourceFieldName = RegionalNetUnitPrice__c` (currency, null/unhydrated on US lines) ← **the unvalued resource**

---

## Why Services-specific

The gate is a `1 AND 2` filter where crit1 keys exactly on the Services flag:
- **Services/Training** products carry `Allow_Regional_Pricing__c = true` (the "Services only" flag) → crit1 passes →
  engine reaches crit2 on the null resource → error.
- **Everything else** carries `Allow_Regional_Pricing__c = false` → crit1 fails → `AND` short-circuits before crit2 →
  no missing-resource condition → adds fine.

This is a clean, deterministic selectivity: the only products that can no longer be added are the
`Allow_Regional_Pricing = true` ones; flag-false products (beSECURE, hardware, PIAMBK, Automate Enterprise, etc.)
added successfully all day on 2026-06-11.

---

## Why recently-introduced ("issue may have been introduced recently")

The `RegionalNetReconcile` group — and therefore the gate — is **absent from V1–V9** and **first appears in V10**
(2026-06-10), persisting through V11 and the active **V12** (step counts: V9 = 103, V10 = 112 = +9 for the new group,
V12 = 118). The gate condition is **identical across V10/V11/V12** (not edited today).

**Temporal smoking gun (live data):**
- Last successful `Allow_Regional_Pricing = true` quote line added: **2026-06-09 18:55Z** (HRM-HRM-NRST-MSPSS), all
  before V10.
- **Zero** `Allow_Regional_Pricing = true` lines created on/after **2026-06-10 02:18Z** (V10 deploy) despite repro
  attempts — while flag-false lines kept adding throughout.
- Two of the five failing products existed as **successful** US lines *before* V10 with `Regional_NetUnit_Price__c = null`
  (CSCO I & II Course 2026-06-09 16:19; Automate Expert Services 2026-06-08) — proving the same null data was harmless
  until the gate was introduced.

The pre-V10 procedure already *read* the same null `RegionalNetUnitPrice__c` (step `RegionalServicesPrice27`, present
since V9, assigns it to `InputUnitPrice`) and never threw — a graceful assignment passthrough tolerates null. The V10
gate is the first place a **value comparison** (`GreaterThan 0`) is performed on that resource **without a null guard**.

**Convention violation:** Every *other* gate in V12 that touches a nullable field guards it with `IsNull`/`IsNotNull`
(e.g. `COLA_Uplift_Percent__c IsNotNull`, `IsContracted IsNull`, `PricingDate IsNull`, `InputUnitPrice IsNull`).
`RegionalNetReconcileGate` is the **sole** gate doing a `GreaterThan` value comparison on a nullable `__c` resource
with **no** preceding `IsNotNull` guard. By the procedure's own established pattern it is structurally defective.

---

## Evidence Table (fact → source)

| # | Fact | Source |
|---|------|--------|
| 1 | Active pricing procedure version = **V12** (only one `<status>Active</status>`); V1–V11 inactive | `evidence/proc_live/.../Rev_Mgmt_Default_Pricing_V120.expressionSetVersion`; `evidence/active_proc_and_gate_inventory.md` |
| 2 | Gate logic `1 AND 2`: crit1 `AllowRegionalPricing__c Equals true`, crit2 `RegionalNetUnitPrice__c GreaterThan 0` | `evidence/regionalnetreconcile_group_v12.xml` (lines 13–28) |
| 3 | `RegionalNetReconcile` group absent V1–V9, first appears V10 (2026-06-10); steps V9=103→V10=112→V12=118 | `evidence/active_proc_and_gate_inventory.md`; `evidence/esdv_v12/{v9_full.json,v12_full.json}` |
| 4 | Gate is the **only** value-comparison (`GreaterThan`) on a nullable `__c` with no `IsNull`/`IsNotNull` guard | `evidence/active_proc_and_gate_inventory.md` (convention-violation section) |
| 5 | `QLI.Regional_NetUnit_Price__c` = Currency(18,2), **no defaultValue** ⇒ null on fresh line | `evidence/RUNTIME_THREAD_FINDINGS.md §3`; live FieldDefinition retrieve |
| 6 | `QLI.Allow_Regional_Pricing__c` = Checkbox default `false`; set `true` via Product2 mirror (no flow/trigger/Apex writes it) | `evidence/RUNTIME_THREAD_FINDINGS.md §3`; H2 refutation file §A |
| 7 | All 5 products `Product2.Allow_Regional_Pricing__c = true`; control `01tWC00000FBWonYAH` = false | `evidence/00_ground_truth.md`; SOQL Product2 |
| 8 | `RegionalServicesPricingPrehook` is a **US no-op** (writes context attrs only for non-default multiplier countries; never writes `AllowRegionalPricing__c`) | `Org Data/_src/classes/RegionalServicesPricingPrehook.cls` (v13.3, lines 58–59) |
| 9 | Context `SalesTransactionContextExt_v2` v23 (`11pWC000002TjF7YAK`, IsActive=true) — both attrs present on `SalesTransactionItem` node, `inputoutput`, hydrated from QLI; no source drift | `evidence/H2_refutation_runtime_context.md §A`; `evidence/fresh_ctx/.../SalesTransactionContextExt_v2.contextDefinition`; tooling `ContextAttribute`/`ContextAttributeMapping` |
| 10 | Pre-gate V9 already consumed both attrs at runtime (`RegionalServicesPrice` filter, `RegionalServicesPrice27` BKM reads null `RegionalNetUnitPrice__c`) and services lines added cleanly | `evidence/H2_refutation_runtime_context.md §B`; `evidence/regionalnetreconcile_group_v12.xml` (lines 171–243) |
| 11 | Temporal boundary: last flag-true add 2026-06-09 18:55Z; zero flag-true adds on/after V10; flag-false adds fine all 2026-06-11 | `evidence/RUNTIME_THREAD_FINDINGS.md §5` ("temporal smoking gun") |
| 12 | Two failing products existed as successful US lines with `Regional_NetUnit_Price__c = null` *before* V10 | `evidence/RUNTIME_THREAD_FINDINGS.md §4` |
| 13 | Failing quote has 0 lines; the SF-Pricing/SF-BRF error appears in **zero** Apex logs (managed-engine error) | `evidence/RUNTIME_THREAD_FINDINGS.md §1–2` |
| 14 | Platform docs: a *present-null* in a `GreaterThan 0` evaluates to false (no error); the "no corresponding value" error fires on a resource with no value supplied | `evidence/research-notes/error_semantics.md §2–3` (Salesforce null-handling + calling-considerations docs) |

---

## Hypotheses considered — adversarial verdicts

### H1 — un-null-guarded comparison on the null/unhydrated `RegionalNetUnitPrice__c` → **SURVIVES (refined)**
**Causal chain: confirmed and live.** Active V12; gate first in V10; airtight temporal boundary (last flag-true add
2026-06-09, zero after V10); error names `RegionalNetReconcileGate`; crit1 boolean always present so Services reach
crit2 while flag-false short-circuit — explaining the exact product selectivity.

**Refinement (the adversarial finding that survived).** H1's original *wording* — "the resource **has no value**
(absent)" — over-claims. The live context proves `RegionalNetUnitPrice__c` is **declared, mapped, and hydrated** from
the QLI; structurally it is **present-with-null-value**, not absent. Two facts force the refinement:
- Platform docs say a *present-null* Currency in `GreaterThan 0` evaluates to **false** (gate filters the row out) and
  the line would add with **no error**.
- Counter-precedent: step `RegionalServicesPrice27` (present since V9, runs before the gate) **reads the identical null
  `RegionalNetUnitPrice__c`** in an assignment and every pre-V10 services add **succeeded**. So "reading a null
  RegionalNetUnitPrice__c" is demonstrably survivable; null *per se* does not throw.

**Reconciliation = the H1→H2 hybrid (most-probable mechanism).** The QLI mapping is **INPUT-only** and on a US line the
prehook never writes the attribute, so it is a **never-hydrated input**. If BRF+ treats an unwritten input-only
attribute as *"no value supplied"* (rather than "present = null"), then the **data condition is H1** (nothing ever
populated the resource) **presenting as the H2 error class** ("resource has no corresponding value"). This precisely
matches the message text. The throw is specific to a **value-comparison (`GreaterThan`) on a never-hydrated operand** —
the one thing the pre-V10 assignment-style consumption avoided.

**Verdict: H1 survives as the operative cause.** The only unresolved fork (does BRF+ treat the never-hydrated input as
"absent" or as "present-null"?) is a *runtime-semantics* detail that does not change the fix shape and cannot be
settled read-only. Either reading points to the same lever: the gate must not perform a value comparison on an
unvalued resource for US lines.

### H2 — active/published context version stale or missing the regional attributes → **REFUTED (high confidence)**
Attacked from its strongest angle (the live runtime objects the engine actually hydrates, not the design-time XML):
- **Structural:** On the active `_v2` v23, runtime `ContextAttribute` rows `AllowRegionalPricing__c` (`11nWC0000D8nZGcYQM`)
  and `RegionalNetUnitPrice__c` (`11nWC0000D8nZH0YQM`) exist on the `SalesTransactionItem` node as `inputoutput`, with
  `ContextAttributeMapping` rows hydrating them from `QuoteLineItem` (`QuoteEntitiesMapping`). The resource is
  **present** in the runtime bag, not absent.
- **Behavioral kill-shot:** The pre-gate **V9** procedure already referenced *both* attributes at runtime and services
  lines added successfully through 2026-06-09. Absent resources would have thrown the identical SF-BRF-00004 under V9 —
  they did not.
- The one pro-H2 fact (a `ContextDefinitionSync` last succeeded 2026-05-31 while regional attribute rows were created
  2026-06-04) is a **red herring**: the live runtime rows the engine reads *do* carry the attributes, and V9 evaluated
  them successfully. This is a **different class** than the prior `project_reprice_contextdef_error` gack (which was a
  genuinely unsynced context). **H2 dead.**

### H3 — input/output misconfiguration or mapping gap on the active version → **REFUTED (high confidence)**
Attacked every structural axis (fieldType direction, duplicate output-only definition, wrong-node evaluation,
mapping-to-missing-field, multi/stale active version):
- On the `SalesTransactionItem` node, `RegionalNetUnitPrice__c` and `AllowRegionalPricing__c` are both
  `fieldType = inputoutput` (readable as input). No output-only definition exists (the lone `<fieldType>output</fieldType>`
  nearby belongs to the *next* attribute, `Attribute_Multiplier_Pct__c` — a grep-adjacency artifact).
- Design-time mappings are valid **input** mappings (`contextInputAttributeName`) hydrated against **real, accessible**
  QLI fields (`Regional_NetUnit_Price__c` Currency(16,2), `Allow_Regional_Pricing__c` Checkbox — neither calculated).
- Exactly **one** active context version (V23), matching the inspected file; no drift.

So the attribute is structurally *available* to the gate as a readable input; the failure is the runtime data-null on a
US line, **not** a design misconfiguration. H3's structural claim is dead either way.

**Net:** the regional cluster of facts (V10 gate, US no-op prehook, null source field, gate selectivity, temporal
boundary) converge on **H1 (refined to the H1→H2 hybrid)**. H2 and H3 are refuted with high confidence.

---

## What remains to confirm (and why it isn't done here)

Only **one** gap remains, and it is *belt-and-suspenders* — it does not change the diagnosis or the fix:

> **A FINEST / RLM pricing-engine simulation trace from an authorized single-line Add-Product repro** (one Services
> product on a US/USD quote). At the `RegionalNetReconcileGate` step it would show whether BRF+ reports
> `RegionalNetUnitPrice__c` as **"no corresponding value / unsimulatable"** (confirms the hybrid mechanism: a
> never-hydrated input is treated as absent at a value comparison) versus evaluating crit2 to **false** and adding the
> line (which would point the throw elsewhere). The managed engine does **not** log this to Apex, so a FINEST pricing
> trace on a live repro is the only way to capture it.

**This requires adding a quote line, which is DML — explicitly out of scope under the read-only rule.** It needs the
user / an authorized operator to perform the repro with debug logging on. The read-only evidence already in hand
(live runtime context rows + V9 precedent + the V10 temporal boundary + the convention violation) is sufficient to
proceed with the fix; the trace would only adjudicate the *absent-vs-present-null* internal-semantics nuance.

An **equivalent settling test** (also DML): clone the quote, pre-populate `Regional_NetUnit_Price__c > 0` on a US
Services line, and Add — if the add succeeds, the null operand at the gate is confirmed as the trigger.

---

## Related tickets / regional-pricing cluster

This is the latest defect in the **regional-services-pricing rework** that has produced a string of incidents over the
past week. All share the V9→V12 regional procedure rework and the `RegionalServicesPricingPrehook` family.

- **SC-3374** (`project_sc3374_workday_regional_pricing`) — Italy regional pricing on the LIST channel; same
  `RegionalServicesPrice27` / `RegionalNetUnitPrice__c → InputUnitPrice` wiring. Established that the field named "Net"
  is wired to the **list** channel and that NET stays catalog (structural `TotalLineAmount ≠ NetTotalPrice`).
- **Reprice contextDefinitionName gack** (`project_reprice_contextdef_error`) — prior incident where a same-day in-place
  edit to the LIVE active pricing procedure was **not re-synced** to the context version, producing a "Specify the
  contextDefinitionName" error. **SC-3393 is explicitly NOT this class** (H2 refuted: the context *is* synced and carries
  the attributes), but it is the cautionary precedent for any procedure/context change.
- **`RegionalServicesPricingPrehook` v13.x** (`project_regional_services_pricing_mechanism`) — the prehook that applies the
  country multiplier and writes `RegionalNetUnitPrice__c` only for non-default-multiplier countries; **US is a no-op**,
  which is precisely why `RegionalNetUnitPrice__c` is never populated on the failing lines.
- **Pricing procedure V10–V12** (`project_pricing_proc_version_delete_blocked`) — the `RegionalNetReconcile` group was
  added in V10 (2026-06-10); V12 is active. Inactive versions cannot be hard-deleted; the two
  `PricingActionParameters` context bindings must not be removed. Any fix must ship as a **new version** (V13).
- **SC-3390** (`project_sc3390_tiered_price_twice`) — adjacent active-procedure/context investigation on the same V12
  procedure; shares the active-version-is-V12 ground truth and the `AttributeVolumePricingPrehook` context-snapshot model.

**Owner note:** the V10 regional rework was authored in the same window Marc DeBrey / Nir Kailash / Ben Kozlowski were
iterating the pricing procedure and context. The fix belongs in that same procedure stream (a V13).
