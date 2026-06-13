# HANDOFF — Renewal Maintenance commits **$0** instead of the COLA/B-4 price (67.38)

**New ticket — to be filed (NOT SC-3404; that number is a Done SC-3390 peer review).**
Owner: Liam (builder of V14). Author of this handoff: Claude. Date: 2026-06-13.
Procedure: `Rev_Mgmt_Default_Pricing_Procedure` · ExpressionSet `9QLWC0000015cDl4AI` · **active version V14 (V140)**.

---

## 0. READ THIS FIRST — what is and isn't proven

- **Proven:** B-4's formula `DerivedPricingRenewals` computes the *correct* renewal price (67.38) but is **inert** (`resultIncluded=false`), so it never commits.
- **Proven (empirically):** simply flipping that formula to `resultIncluded=true` did **NOT** fix it — renewal maintenance still showed $0 (Attempt 1). So the formula's value is either not winning or not what's being observed.
- **NOT proven — and contradicted by the static structure:** the earlier working theory was "the native element `DerivedProductsRenewals` overrides B-4's value with $0." **That is almost certainly wrong**, because:
  - The native committer `DerivedProductsRenewals` writes **`ItemNetTotalPrice`** (a *total*), while B-4 writes **`NetUnitPrice`** (a *unit price*) — different fields, no direct overwrite.
  - The native committer is gated by filter `DerivedProductsNonRenewal` = `QuoteTypeText__c NotEquals 'Renewal'` — i.e. it **excludes renewals**. (Confusing naming: the *element* is called "Renewals" but its *filter* excludes them.)
- **Therefore the actual element that writes $0 onto renewal maintenance is NOT identified by static analysis.** The decisive next step is a **live waterfall / explainability trace** (Section 4). Do that *before* editing anything — the two blind in-place edits already cost two reverts.

---

## 1. Current org state (verify before you start)

- Active procedure version: **V14 / V140**, active `<versions>` block = lines **69795–75411** in the pristine file.
- V14 is **reverted to pristine** (no fix staged): `DerivedPricingRenewals.resultIncluded=false`, `DerivedProductsNonRenewal.conditionLogic=1`.
- **If pricing is currently down, V14 may be deactivated — reactivate the single V14 row first** (UI: Pricing Procedure → Versions → activate V14; or `ExpressionSetVersion.IsActive=true` via Apex/Tooling on the V14 row **only**).

Pristine / backup copies (all identical pristine V14):
- Working copy authored against: `Data/sc-maint/sc3404/x/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition`
- Backup: `Data/sc-maint/sc3404/fix/Rev_Mgmt_V14_BACKUP_*.expressionSetDefinition`
- Last-deployed revert package: `Data/sc-maint/sc3404/revert/`

Verify live truth (don't trust this doc's line numbers blindly — always re-retrieve):
```bash
sf project retrieve start -m "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" \
  -o FortraUAT -r Data/sc-maint/sc3404/rchk --api-version 67.0
```

---

## 2. The renewal chain (exact, line numbers in the pristine V14 file `x/...`)

Root containers execute by `sequenceNumber`. The renewal-relevant ones, **in execution order**:

| seq | element | type | resultIncluded | writes | lines | role |
|----:|---------|------|:--------------:|--------|------:|------|
| 5 | `DerivedProductsNativePull` | ListGroup | false | — | 71945–71955 | native-pull container |
| 5›1 | `DerivedProductsNonRenewal` | AdvancedListFilter | false | — | 71956–71977 | filter: `QuoteTypeText__c NotEquals 'Renewal'` → **excludes renewals** |
| 5›2 | `DerivedProductsRenewals` | DerivedPricing (BKM) | **true** | **`ItemNetTotalPrice`** | 71978–72105 | native committer — **runs on NON-renewals only** (per the filter above) |
| 7 | `ListContainer` | ListGroup | false | — | 72426–72436 | container that holds B-4 |
| 7›3 | `DerivedPricingRenewals` (**B-4**) | FormulaBasedPricing (BKM) | **false** ← inert | **`NetUnitPrice`** | 71829–71893 | the correct COLA/renewal formula; parentStep=`ListContainer` |

> Note the two similarly-named elements:
> - `DerivedProductsRenewals` = the **native** DerivedPricing committer (total field, non-renewals).
> - `DerivedPricingRenewals` = **B-4's formula** (unit price, renewals, currently inert).

### B-4 formula (the value we WANT renewal maintenance to commit), output → `NetUnitPrice`:
```
IF ( QuoteTypeText__c = 'Renewal' ,
     IF ( COLACalculatedPrice__c > 0 , COLACalculatedPrice__c ,
          ( IF ( ISNULL ( Base_Price__c ) , 0 , Base_Price__c )
          - IF ( ISNULL ( Prior_Partner_Discount__c ) , 0 , Prior_Partner_Discount__c )
          - IF ( ISNULL ( Prior_Discretionary_Discount__c ) , 0 , Prior_Discretionary_Discount__c ) )
          * ( 1 + ( IF ( ISNULL ( COLA_Uplift_Percent__c ) , 0 , COLA_Uplift_Percent__c ) / 100 ) ) ) ,
     NetUnitPrice )
```
This formula is correct (produces 67.38 for the canary). The problem is **commit / precedence**, not the math.

---

## 3. What was tried, and the exact result (don't repeat these)

**Attempt 1 — flip B-4 to commit.** Set `DerivedPricingRenewals.resultIncluded=true`, nothing else.
→ Renewal maintenance **still $0.** Conclusion: committing the formula's `NetUnitPrice` is not sufficient — either a *later* element overwrites `NetUnitPrice`, or the $0 you observe is a *different field* (a total), or the formula's runtime branch returns 0 for these lines. **This is the core open question.**

**Attempt 2 — make the native pull skip renewals + scope a commit on `COLACalculatedPrice__c`.** Amended the native filter (`conditionLogic` "1 OR 2", added `COLACalculatedPrice__c > 0`) and a scoped commit.
→ Reprice **ERRORED**: `DerivedProductsNonRenewal#1 ... COLACalculatedPrice__c isn't a valid evaluation resource`. **Lesson: line fields like `COLACalculatedPrice__c` are NOT available in the native-pull (contributor) filter context.** Reverted.

**Net lessons:**
- `resultIncluded` flip alone ≠ fix (Attempt 1).
- Do **not** scope on `COLACalculatedPrice__c` in a contributor/native-pull context. Scope on **`QuoteTypeText__c`** there instead (it IS available — the existing native filter uses it).

---

## 4. THE DECISIVE NEXT STEP — get the waterfall trace (do this before editing)

You need to know two things that static analysis can't give you:
1. **Which field** reads $0 on the renewal maintenance line — `NetUnitPrice`? `ItemNetTotalPrice`? `NetTotalPrice`/`TotalLineAmount`?
2. **Which element** wrote that $0, and **at what sequence** (so you know whether to insert *before* it or *after* it).

How:
1. Reactivate V14, open the renewal **canary** (Section 6).
2. Run a UI **Reprice All** with the pricing **waterfall / explainability** panel open on the renewal maintenance line, **or** capture a **FINEST** debug log (`Apex Code=FINEST`, plus the Pricing/Rule-engine categories) during the reprice.
3. In the waterfall, find the renewal maintenance line and read the ordered list of elements that wrote to its price fields. Identify the **last element that set the observed $0 field**.
4. That element + its sequence is your target. Then pick the matching pattern in Section 5.

> If the $0 is on a **total** field (`ItemNetTotalPrice` / `NetTotalPrice` / `TotalLineAmount`) rather than `NetUnitPrice`, the fix is *not* B-4 at all — it's whatever computes that total (likely a `GroupingAndAggregatePricing` `section-count` element, or the native `DerivedProductsRenewals` writing `ItemNetTotalPrice`). B-4 sets unit price; a downstream total recompute from the unit price is the usual healthy path, so confirm the unit price first.

---

## 5. Fix patterns (choose based on what the trace shows)

> In ALL patterns: scope renewal-only logic on **`QuoteTypeText__c = 'Renewal'`** (available everywhere), never `COLACalculatedPrice__c` in a contributor context.

**Pattern A — a *first-writer* commits $0 before B-4 (first-writer-wins engine).**
Insert a committing `FormulaBasedPricing` (the B-4 formula, `resultIncluded=true`, output `NetUnitPrice`) **before** that writer's sequence, scoped to renewals. The cleanest host is a renewal-only filter + formula pair inside a container whose root `sequenceNumber` is **less than** the $0-writer's. Confirm in the trace that no later element re-overwrites.

**Pattern B — a *later* element overwrites B-4's `NetUnitPrice` with $0 (last-writer-wins).**
Move/duplicate B-4 so it runs **after** that element (a container with a higher `sequenceNumber`), `resultIncluded=true`, scoped to renewals. Verify the downstream total recomputes from the corrected unit price.

**Pattern C — the $0-writer simply shouldn't touch renewals.**
Add `QuoteTypeText__c NotEquals 'Renewal'` to **that element's own filter** (same idiom as the existing `DerivedProductsNonRenewal`), AND flip B-4 to `resultIncluded=true` so the formula fills the gap for renewals. Safest when the $0-writer is a single, clearly-identified element with its own filter.

**Pattern D — the $0 is a total, not unit price.**
Target the total-computing element (e.g. the native `DerivedProductsRenewals` writing `ItemNetTotalPrice`, or a `GroupingAndAggregatePricing`). Ensure renewal lines reach it with a correct unit price first (B-4 committing), then let the standard total recompute run — usually no edit to the total element is needed once unit price is right.

### Do-no-harm constraint (all patterns)
There are **31 unstamped, native-priced lines** (3 of them `Renewal Maintenance`) that must keep their current behavior. Any renewal-scoped commit you add must be gated so it only fires for the *stamped* COLA renewal lines — gate on `QuoteTypeText__c = 'Renewal'` AND a stamped-input signal that IS available in the target context (e.g. `COLA_Uplift_Percent__c`/`Base_Price__c` populated, or the COLA stamp flag) — confirm availability in the trace before relying on a field.

---

## 6. Canary + expected result

- **Canary quote:** `0Q0WC0000038aXd0AI` (renewal quote used throughout this work).
- **Expected after fix:** renewal **maintenance** line `NetUnitPrice` = **67.38** (currently $0); the license line stays **301.75**; the 31 unstamped native lines unchanged.
- Always reprice the canary **twice** (tiered/stale-context lag can mask a one-cycle delay).

---

## 7. Deploy / canary / revert runbook (exact)

A helper script is provided: `Data/sc-maint/sc3404/handoff_deploy.sh` (commands below are what it runs).

**Edit the metadata** in `Data/sc-maint/sc3404/x/unpackaged/...expressionSetDefinition` (work in a copy), keeping it inside the V140 block.

**0. Backup current live** (always):
```bash
sf project retrieve start -m "ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure" \
  -o FortraUAT -r Data/sc-maint/sc3404/_live_backup --api-version 67.0
```

**1. Deactivate V14** (UI is safest; the engine won't update an *active* version):
- Pricing Procedure → Versions → deactivate V14. (Do **NOT** use the LWC "Reactivate All Dependencies" button — it set 8 versions active and corrupted state once. Activate/deactivate the **single** V14 row only.)

**2. Deploy your edited V14** (must be **API v67** — v66 throws `Property 'dataType' not valid`):
```bash
# package.xml apiVersion MUST be 67.0
sf project deploy start -d Data/sc-maint/sc3404/<your_deploy_dir> -o FortraUAT --api-version 67.0
```
> The CLI often prints a cosmetic `metadata.transfer:Finalizing` error even when the deploy SUCCEEDED. **Verify by re-retrieving**, not by the exit message.

**3. Reactivate V14** (single row).

**4. Canary reprice** the quote `0Q0WC0000038aXd0AI` (UI Reprice All, twice) → check the maintenance line = 67.38, license = 301.75, 31 native lines unchanged.

**5. If anything breaks — instant revert:**
```bash
# deactivate V14, redeploy pristine, reactivate V14
sf project deploy start -d Data/sc-maint/sc3404/revert -o FortraUAT --api-version 67.0
```
(`revert/` holds the pristine V14. Confirm post-revert: `DerivedPricingRenewals.resultIncluded=false`, `DerivedProductsNonRenewal.conditionLogic=1`.)

---

## 8. Landmines (each one already cost time)

1. **`COLACalculatedPrice__c` is NOT a valid resource in contributor/native-pull filter contexts** → use `QuoteTypeText__c` to scope there. (Attempt 2 break.)
2. **`resultIncluded=true` on B-4 alone does not fix it** (Attempt 1). The precedence/field question must be answered by the trace.
3. **API v67 required** for the criterion schema (`dataType`). v66 fails.
4. **`metadata.transfer:Finalizing` CLI error is cosmetic** — deploy usually succeeded; verify by retrieve.
5. **Engine accepts only `ISNULL` for null-guards** — `BLANKVALUE`/`NULLVALUE`/`ISBLANK` evaluate to 0 here. (That's why B-4 uses nested `ISNULL`.)
6. **`DecisionTable` can't be deployed via mdapi** (round-trip metadata bug) — UI only. **`ExpressionSetDefinition` deploys fine via mdapi.** Don't bundle a DecisionTable into this deploy.
7. **Never "Reactivate All Dependencies"** in the LWC — it activates many versions at once. Activate the single V14 row.
8. **`ExpressionSetVersion` delete is platform-blocked** (UI+API). If you ever clone to a V15 scratchpad, you can only *deactivate* the leftover, not delete it.
9. **Always pull live before scoping** — the active version has drifted (memory once said V12/V13; live is V14). Re-retrieve every session.
10. **Two similarly-named elements** — `DerivedProductsRenewals` (native, total, non-renewals) vs `DerivedPricingRenewals` (B-4, unit price, renewals). Don't edit the wrong one.

---

## 9. My recommendation

Given two in-place attempts already broke reprice, **iterate on a throwaway V15 clone** (safe — no live impact): nail the working change there with the trace, then apply the *exact proven change* to V14 in one clean deploy and deactivate V15. End state is still the fix on **V14**; the only cost is one un-deletable inactive V15. If you'd rather keep editing V14 in place, the runbook above plus the revert package make that survivable — just get the **waterfall trace first** so the next edit is targeted, not blind.
