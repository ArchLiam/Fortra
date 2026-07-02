# SC-3393 — Root Cause & Fix Spec

**READ-ONLY investigation; this spec proposes changes but performs NONE. Any deploy/DML needs explicit fresh authorization.**
Org: FortraUAT. Active procedure version: **V12**. The `RegionalNetReconcile` gate was introduced in **V10** (2026-06-10).

---

## Root Cause Statement

The active pricing procedure `Rev_Mgmt_Default_Pricing_Procedure` **V12** contains a top-level `RegionalNetReconcile`
ListGroup (added in **V10**, 2026-06-10) whose entry filter **`RegionalNetReconcileGate`** (`AdvancedListFilter`,
`conditionLogic "1 AND 2"`) performs an **un-null-guarded value comparison** —
`crit2: RegionalNetUnitPrice__c GreaterThan 0` — once `crit1: AllowRegionalPricing__c Equals true` passes.

On a **US** quote line for a **Services/Training** product:
- `Allow_Regional_Pricing__c = true` (copied from `Product2`) ⇒ crit1 passes ⇒ engine must evaluate crit2.
- `RegionalNetUnitPrice__c` is **never populated**: the source field `QuoteLineItem.Regional_NetUnit_Price__c` has
  **no default** (null on a fresh line) and `RegionalServicesPricingPrehook` is a **no-op for US** (multiplier 1.0).
- The comparison resource therefore has **no value to evaluate** ⇒ BRF+ cannot simulate the `GreaterThan` ⇒
  `SF-BRF-00004` wrapped as `SF-Pricing-00006 / RegionalNetReconcileGate#1`. The line fails to add.

Non-Services lines (`Allow_Regional_Pricing__c = false`) fail crit1 and short-circuit the `AND`, never reaching the
broken comparison — hence the failure is exactly scoped to the five flagged Services/Training products.

The gate is the **only** value comparison on a nullable `__c` resource in V12 lacking an `IsNull`/`IsNotNull` guard —
a violation of the procedure's own established null-guard convention, and the single thing that changed (V9→V10) at the
boundary where Services adds went from working (≤ 2026-06-09) to failing (≥ 2026-06-10).

**Correct target behavior any fix must preserve:**
- **US lines must NOT receive regional pricing.** US multiplier is 1.0; the regional group must be a no-op for US.
  Lines must add and price off the standard catalog path.
- **Regional lines (e.g. Italy) must still reconcile.** When `RegionalNetUnitPrice__c > 0` (prehook wrote it for a
  non-default-multiplier country), the group must still run and reconcile NetUnitPrice/InputUnitPrice/totals.

---

## Ranked Fix Options

Ranked by safety (1 = safest/recommended). Options A and C are the strongest; the recommendation is a **layered A+C**.

### Recommended: C (gate null-guard) — primary — optionally layered with A (data default) — defense-in-depth

---

### Option C — Make the gate null-safe (reorder / add an `IsNotNull` guard) — **RECOMMENDED (primary)**
**Change:** In a new procedure version **V13**, change `RegionalNetReconcileGate`'s `conditionLogic` so a missing/null
`RegionalNetUnitPrice__c` short-circuits **before** the value comparison. Add a leading guard criterion:
- crit1: `AllowRegionalPricing__c Equals true`
- crit2: `RegionalNetUnitPrice__c IsNotNull`  *(new)*
- crit3: `RegionalNetUnitPrice__c GreaterThan 0`
- `conditionLogic`: `1 AND 2 AND 3`

Because BRF+/`AdvancedListFilter` `AND` short-circuits, a null `RegionalNetUnitPrice__c` fails crit2 and the engine
never evaluates the `GreaterThan` — the gate returns **false**, the regional group is skipped, and the US line adds and
prices off the standard path.

**Blast radius / risk: LOW–MODERATE.** Procedure-only change; no data migration; no context republish. Touches a single
gate in one group. Must ship as a **new ExpressionSetVersion (V13)** and be activated (existing versions are
delete-blocked; the two `PricingActionParameters` context bindings must remain). One must verify the engine accepts
`IsNotNull` as a guard inside the same `AdvancedListFilter` (it is used elsewhere in V12 on nullable fields — e.g.
`COLA_Uplift_Percent__c IsNotNull` — so the pattern is proven in this very procedure).

**Why it preserves correct behavior:**
- **US:** `RegionalNetUnitPrice__c` null ⇒ crit2 fails ⇒ group skipped ⇒ standard pricing, no regional reconcile. Correct.
- **Regional:** prehook wrote `RegionalNetUnitPrice__c > 0` ⇒ crit2 (`IsNotNull`) and crit3 (`> 0`) both pass ⇒ group
  runs exactly as today. No change to the regional path.

**Verification:** see the post-fix validation plan below.

---

### Option A — Default `Regional_NetUnit_Price__c` (and the OrderItem mirror) to **0** — **RECOMMENDED (complement / defense-in-depth)**
**Change:** Add `<defaultValue>0</defaultValue>` to `QuoteLineItem.Regional_NetUnit_Price__c` and the mirroring
`OrderItem.RegionalNetUnitPrice__c`. Then on a fresh US line the attribute hydrates as **0** (a real value), the gate's
`GreaterThan 0` evaluates cleanly to **false**, the regional group is skipped, and the line adds.

**Blast radius / risk: LOW.** Field-metadata change on two fields; no procedure rework; no context republish. The only
caveat: confirm no formula/rollup/flow currently relies on `Regional_NetUnit_Price__c` being **null** to mean
"no regional price" (a `0` would change such logic). Evidence shows the only readers are the prehook (writes, doesn't
read for branching) and the procedure (gate + `RegionalServicesPrice27` assignment). `0 < NetUnitPrice` in the
`RegionalNetUnitPrice` BKM would *select 0 as NetUnitPrice* **IF the group ran** — but with the gate now returning false
for US (whether via this default making crit2 `0 > 0 = false`, or via Option C's `IsNotNull`), the group does not run on
US, so the BKM never sees the 0. This is why A must pair with C, or rely on the gate's own `> 0` filtering the 0 out.

**Why it preserves correct behavior:**
- **US:** value 0 ⇒ `0 > 0` is false ⇒ group skipped ⇒ standard pricing. Correct.
- **Regional:** prehook overwrites the 0 default with the real regional price (> 0) before the gate ⇒ group runs as
  today. (Confirm the prehook writes the context attribute *after* default initialization — it does: it explicitly sets
  `RegionalNetUnitPrice__c` for non-default-multiplier countries.)

**Note:** A makes crit2 evaluate to false on its own merits (`0 > 0`), which **also resolves the error without C**. It is
listed as a complement because C addresses the *structural* convention violation at the gate (robust against any future
field whose value is null), while A addresses the *data* shape. A+C is belt-and-suspenders.

---

### Option B — Upstream Assignment/seed step that sets `RegionalNetUnitPrice__c = 0` before the gate
**Change:** In V13, insert an `AssignmentElement` step ahead of `RegionalNetReconcile` (seq < 33) that seeds
`RegionalNetUnitPrice__c = 0` when it is null (or unconditionally, before the prehook-written value if any).

**Blast radius / risk: MODERATE.** Procedure rework that adds a step and depends on **ordering** relative to the prehook
and to any earlier consumer of `RegionalNetUnitPrice__c` (notably `RegionalServicesPrice27` in the seq-12
`ListContainer4` group, which assigns `RegionalNetUnitPrice__c → InputUnitPrice`). A mis-ordered seed could
unintentionally zero `InputUnitPrice` for US Services lines. More moving parts than C for the same outcome.

**Why it preserves correct behavior:** same logic as A but enforced in-procedure; correct only if the seed runs after
the prehook (so a real regional value is not clobbered) and before the gate. The ordering constraint is the risk.

**Verdict:** Functionally fine but **strictly dominated by A** (simpler, declarative, no ordering risk) and by C
(addresses the structural defect). Not recommended unless field-default changes are organizationally blocked.

---

### Option D — Re-sync / republish the active context version
**Change:** Re-run `ContextDefinitionSync` / republish `SalesTransactionContextExt_v2`.

**Blast radius / risk: HIGH effort, NO expected effect — NOT APPLICABLE.** H2 is **refuted**: the active context v23
already carries both regional attributes as `inputoutput` runtime `ContextAttribute` rows, hydrated from the QLI, and the
pre-gate V9 procedure consumed them successfully. The resource is **present-but-unhydrated on US lines**, not absent.
Republishing changes nothing about a null/unhydrated value and risks collateral disruption to a live context. **Do not
pursue** unless a FINEST repro trace unexpectedly shows the attribute as a missing slot (which would resurrect H2).

---

### Option E — Only set `Allow_Regional_Pricing__c = true` on the QLI when a regional country actually applies
**Change:** Stop blanket-copying the Product2 flag onto the QLI; instead set it `true` only when the account/quote
country has a non-default regional multiplier (e.g. compute in the prehook or a before-save automation).

**Blast radius / risk: HIGH.** This re-architects the meaning of `Allow_Regional_Pricing__c` (currently a static
product attribute, the "Services only" flag) into a context-dependent runtime flag. It would change the semantics relied
on by the prehook, the context mapping, SC-3374's wiring, and any reporting on the flag. It also fights RLM's native
same-name Add-Product copy. High regression surface across the regional cluster.

**Why it would work but is wrong:** US lines would get `AllowRegionalPricing__c = false` ⇒ crit1 fails ⇒ no error. But
it solves a *gate-robustness* problem by mutating a *product master-data* concept, and breaks the clean separation the
design intends ("this product is eligible for regional pricing" vs "this line got a regional price"). **Not recommended.**

---

## Recommendation

**Ship Option C as the primary fix** (add `RegionalNetUnitPrice__c IsNotNull` ahead of the `GreaterThan 0` criterion in
a new **V13** of the procedure). It directly remediates the structural defect — an un-null-guarded value comparison —
aligns the gate with the procedure's own null-guard convention, requires no data migration or context republish, and is
the smallest change that cannot regress the regional path. **Layer Option A** (default `Regional_NetUnit_Price__c = 0`
on QLI + OrderItem mirror) as low-risk defense-in-depth so the attribute is never null at any future consumer.

**Reject D** (H2 refuted — no-op, risky) and **E** (master-data semantics change, high regression). **B** is a
strictly-dominated fallback only if field defaults are blocked.

Both C and A must be deployed to UAT only and validated there first; per project policy, prod promotion is a separate,
explicitly-authorized step.

---

## Exact Repro + Post-Fix Validation Plan

> All steps below are **DML / require authorization**; none were performed in this read-only investigation.

### Pre-fix repro (capture the failure + the decisive trace)
1. On a US/USD Draft quote (e.g. clone `0Q0WC0000037tXV0AY`, OhioHealth, Fortra Price Book), enable a **FINEST** debug
   log (Pricing + Apex categories) for the operating user.
2. Add **24 X 7 X 365 Monitoring** (`01tWC00000DD115YAD`). Expect: `SF-Pricing-00006 / SF-BRF-00004 /
   RegionalNetReconcileGate#1`; quote stays at 0 lines.
3. In the pricing trace, locate the `RegionalNetReconcileGate` step and record how `RegionalNetUnitPrice__c` is
   reported (no-corresponding-value vs present-null). This adjudicates the absent-vs-present-null nuance (does **not**
   change the fix).
4. (Optional confirmatory) On a second clone, pre-populate `Regional_NetUnit_Price__c = 100` on the US Services line and
   Add — expect **success**, confirming the null operand at the gate is the trigger.

### Post-fix validation (after deploying V13 with C [+ A])
**A. US Services lines now add and do NOT get regional pricing (primary acceptance):**
1. On a US/USD quote, add all five products: `24 X 7 X 365 Monitoring`, `CSCO I & II Course`,
   `Administering Automated Password Management`, `AIC Expert Services`, `Automate Expert Services`.
2. Expect: **all five add successfully**, no SF-Pricing/SF-BRF error.
3. Verify pricing: `UnitPrice`/`NetUnitPrice` equal the standard catalog price (no regional multiplier applied);
   `Regional_NetUnit_Price__c` is `0` (Option A) or null (C-only) and unused; line totals match the standard path.
4. FINEST trace: `RegionalNetReconcileGate` evaluates to **false** (skips the regional group) — no simulate error.

**B. Regional (non-US) lines still reconcile correctly (no regression):**
1. On an Italy (or other non-default-multiplier) quote, add a Services product so the prehook writes
   `RegionalNetUnitPrice__c > 0`.
2. Expect: line adds; the `RegionalNetReconcile` group **runs** (gate passes crit `IsNotNull` + `> 0`);
   `NetUnitPrice`/`InputUnitPrice`/`ItemNetTotalPrice`/`TotalLineAmount` reflect the regional reconcile exactly as in
   V12 today. Compare against a pre-fix regional baseline to confirm identical regional output.

**C. Non-Services unaffected (regression guard):**
1. Add a flag-false product (e.g. beSECURE / a hardware SKU) on the US quote. Expect: adds and prices exactly as today
   (crit1 false ⇒ group always skipped — behavior unchanged by the fix).

**D. Data/temporal recheck:**
- After fix, confirm new `Allow_Regional_Pricing = true` QLIs can again be created (the count that has been **zero**
  since 2026-06-10 02:18Z should resume), while flag-false adds continue unaffected.

**Sign-off criteria:** A (all five add, US gets no regional price) **and** B (regional path byte-identical to pre-fix)
**and** C (non-Services unchanged) all pass in UAT before any prod-promotion conversation.
