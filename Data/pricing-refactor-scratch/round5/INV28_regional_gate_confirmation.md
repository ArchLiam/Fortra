# INV-28 / OQ-11 — Regional Net Reconcile Gate: Confirmation on Active V21

**Round 5 · Tab 3 · Read-only ESD close-out · 2026-07-08**
**Verdict: `CONFIRMED-CLOSED` on active V21.** The un-null-guarded `>0` predicate no longer exists on the active version — the defective element was structurally removed, not merely guarded.

---

## 1. Source of truth (fresh retrieve)

Retrieved live from **FortraUAT** today, into the repo:

```
sf project retrieve start -m "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" \
    --output-dir Data/round5-esd -o FortraUAT     # Succeeded, v66 metadata via v67 SOAP
```

Full file: `…/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (124,678 lines · 22 `<versions>` blocks inline). The 5.3 MB full retrieve was deleted after analysis (§6); the evidence is preserved in this folder:
- `active_v21_block_20260708.xml` — the extracted **active V21** block (= full-file lines **110855–117770**).
- `EVIDENCE_inv28_gate_occurrences.txt` — grep-proof of every `RegionalNetReconcileGate` occurrence + the version `<status>` map.

**Version map (by `<status>` line):** V1–V19 `Inactive`; **V20** `Inactive` (backup); **V21 `Active`** = full-file lines **110855–117770** (`<versionNumber>21</versionNumber>`); V22 `Draft`. All full-file line numbers below are reproducible by re-running the retrieve command above.

---

## 2. The defect (recap, for the reader)

Per `project_sc3393_services_add_fail`: adding any of 5 Services/Training products to a US/USD quote failed with `SF-BRF-00004 / SF-Pricing-00006 … RegionalNetReconcileGate#1 isn't valid`. Root cause = a top-level `RegionalNetReconcile` **ListGroup** (introduced V10) whose entry filter `RegionalNetReconcileGate` (`AdvancedListFilter`) did an **un-null-guarded value comparison**:

```
conditionLogic: 1 AND 2
  crit1: AllowRegionalPricing__c  Equals       true      (harmless Boolean — short-circuits non-services)
  crit2: RegionalNetUnitPrice__c  GreaterThan  0         (HAZARD: field is never hydrated on a US line → null → BRF error)
```

The recommended fix (SC-3393) was a **V13** null-guard: insert `RegionalNetUnitPrice__c IsNotNull` → `1 AND 2 AND 3`. Per memory, V13 was built + deployed **Inactive** but **never activated** (user chose Hold). So the open question (OQ-11) was: did anything equivalent make it into the now-active V21?

---

## 3. What the active V21 actually contains — evidence

### 3a. The defective element is GONE from V21
- `RegionalNetReconcileGate` appears **only twice in the whole file**, both in **inactive** blocks: **V10 (line 50959)** and **V11 (line 56901)**. Both carry the un-guarded `1 AND 2` logic verbatim.
- Inside the active V21 block (110855–117770): **`RegionalNetReconcile` = 0 occurrences** (neither the ListGroup nor the gate exists).
- The only 2 `GreaterThan` operators anywhere in active V21 are on **`LineItemQuantity >= 0`** (a `GreaterThanOrEquals`) and **`NetUnitPrice > 0`** — **neither touches the nullable `RegionalNetUnitPrice__c`.**
- `RegionalNetUnitPrice__c` appears exactly **twice** in active V21, both inside a single **AssignmentElement** (as an input and in its mapping JSON) — **never in a filter predicate.**

### 3b. What replaced it in V21 — `ListContainer4` (seq 11), two children
```
RegionalServicesPrice     (AdvancedListFilter, seq 1)   conditionLogic: 1
    crit1: AllowRegionalPricing__c  Equals  true         <-- single Boolean criterion; NO value-comparison on a nullable field
RegionalServicesPrice33   (AssignmentElement,  seq 2)
    assigns  RegionalNetUnitPrice__c  ->  InputUnitPrice  (sectionJsonString2 mapping)
```
The dangerous crit2 (`RegionalNetUnitPrice__c GreaterThan 0`) was **dropped entirely.** The surviving filter is the *harmless* Boolean check that was crit1 in the old gate. `AllowRegionalPricing__c` is a checkbox (always has a value) → `Equals true` cannot raise the null/no-value BRF error. **The INV-28 crash surface is structurally eliminated.**

---

## 4. Answer to OQ-11 (verbatim question)

> OQ-11: *"confirm the un-null-guarded `>0` `RegionalNetReconcileGate` step still exists on active V21 and schedule its null-guard."*

**The premise is false.** The `RegionalNetReconcileGate` step **does not exist on active V21** — nor does its parent `RegionalNetReconcile` group. There is **no `RegionalNetUnitPrice__c > 0` predicate anywhere on the active version.** Nothing to null-guard; **no canvas fix is required.** INV-28 / OQ-11 = **CLOSED.**

**Closure mechanism (important nuance):** it did **not** close by the V13 `IsNotNull` guard carrying forward. It closed because the entire `RegionalNetReconcile` reconcile group (V10–V11/V12 lineage) was **restructured out** and replaced by the `ListContainer4` filter+assignment above. This is a *stronger* form of closure than the guard (the comparison is removed, not merely conditioned). The Hold-state V13 build referenced in SC-3393 memory is **moot / superseded** — no need to activate it.

**Inactive-version residue:** the un-guarded gate is frozen in V10 and V11 (both Inactive). Per §2b (versions cannot be hard-deleted) these remain in the MDAPI payload but are **inert** — they never execute. No action.

---

## 5. Adjacent observation — SEPARATE from INV-28 (not a blocker; flag for owner)

The V21 replacement introduces a *different* shape worth an owner sanity-check (this is **not** the INV-28 crash and does **not** reopen it):

- `RegionalServicesPrice33` unconditionally assigns `RegionalNetUnitPrice__c → InputUnitPrice` whenever the `AllowRegionalPricing__c = true` filter passes.
- On a **US services line** (`AllowRegionalPricing__c = true`, but `RegionalNetUnitPrice__c` null), this is an **assignment of null**, not a value-*comparison* → it does **not** throw `SF-BRF-00004`. So the crash cannot recur here.
- Open runtime question (needs a UI reprice log, out of read-only static scope): does that null propagate to a `$0`/null `InputUnitPrice` on US services lines, or does the engine treat a null assignment as a no-op / is it overwritten downstream? V21 validation runs have services lines pricing correctly, which suggests it is handled — but this was not provable statically. **Recommend the owner confirm on one US-services reprice.** Tracked here only so it is not lost; it is not INV-28 and does not change the CLOSED verdict.

---

## 6. Cleanup note
The 5.3 MB fresh full retrieve (`Data/round5-esd/`) was **deleted after analysis** to avoid repo bloat (a near-identical Jul-6 full copy already exists at `Data/pricing-refactor-scratch/live-esd/`). The load-bearing evidence is preserved small in this folder: `active_v21_block_20260708.xml` (308 KB) and `EVIDENCE_inv28_gate_occurrences.txt`. Re-retrieve with the §1 command to reproduce full-file line numbers.
