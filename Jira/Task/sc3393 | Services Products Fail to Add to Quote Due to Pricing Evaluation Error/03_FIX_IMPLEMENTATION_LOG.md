# SC-3393 — Fix Implementation Log & Activation Runbook

**Org:** FortraUAT · **Date:** 2026-06-11 · **Fix:** Option C (gate `IsNotNull` guard) — see `02_ROOT_CAUSE_AND_FIX_SPEC.md`.
Option A (field default 0) was **dropped** — `RegionalNetUnitPrice__c` is read by `PartnerNetPricePosthook` /
`PartnerPricingPrehook` / `PartnerPricingPrehookV2`, so a null→0 data change carries partner-pricing risk. The gate
guard changes **no data**, avoiding that entirely.

---

## CURRENT STATE (as of 2026-06-11) — V13 STAGED, NOT ACTIVE

| Version | Status | Note |
|---|---|---|
| **V12** | **Active** | LIVE — pricing unchanged |
| **V13** | **Inactive** | staged with the fix; **zero live impact** |

Activation is **ON HOLD** by user decision. The org is in its normal state; nothing has changed behaviorally.

---

## What was done (all reversible / zero-impact)

1. **Built V13** = byte-for-byte copy of the active **V12** `ExpressionSetDefinitionVersion` with exactly these edits
   (deterministic build, each edit asserted unique): `label V12→V13`, `status Active→Inactive`, `versionNumber 12→13`,
   and the gate change below. Build script + artifact: `Data/sc3393/v13_build/build_v13.py` →
   `Data/sc3393/v13_build/src/expressionSetVersion/Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default_Pricing_V130.expressionSetVersion`.
2. **Validate-only deploy** (`--dry-run`) → Succeeded 1/1 (Deploy ID `0AfWC00000GIH620AH`).
3. **Real deploy, Inactive** → Succeeded 1/1 (Deploy ID `0AfWC00000GILZR0A5`). V12 untouched.
4. **Verified** via fresh full retrieve (`Data/sc3393/verify_v13/`): V12 = Active, V13 = Inactive, guard present.

### The only logic change (V12 → V13), `RegionalNetReconcileGate`

```diff
-  <conditionLogic>1 AND 2</conditionLogic>
+  <conditionLogic>1 AND 2 AND 3</conditionLogic>
     1) AllowRegionalPricing__c  Equals       true
+    2) RegionalNetUnitPrice__c  IsNotNull                 ← NEW null-guard (evaluated before the compare)
-    2) RegionalNetUnitPrice__c  GreaterThan   0
+    3) RegionalNetUnitPrice__c  GreaterThan   0
```

- **US Services line:** `RegionalNetUnitPrice__c` is null → crit 2 (`IsNotNull`) false → `AND` excludes the line →
  regional group skipped → line adds & prices off the standard catalog path (no regional pricing — correct for US).
- **Regional (e.g. Italy) line:** prehook wrote `RegionalNetUnitPrice__c > 0` → crit 2 & 3 pass → group runs exactly
  as in V12 (no change to the regional path).
- **Non-Services line:** `AllowRegionalPricing__c = false` → crit 1 false → group skipped (unchanged).
- Pattern mirrors 18 existing `IsNull`/`IsNotNull` guards in this same procedure (e.g. `ItemContractAttributePasId
  IsNotNull` as criterion 1) — the procedure's own convention.

---

## ACTIVATION RUNBOOK (run when ready)

### Option 1 — UI activation (recommended, safest)
1. Setup → search **"Pricing Procedures"** (or App Launcher → *Pricing Procedures* / Revenue Settings → Pricing).
2. Open **"Revenue Management Default Pricing Procedure"**.
3. In the version list, open **"Rev Mgmt Default Pricing V13"** (Status = Inactive).
4. Click **Activate**. RLM compiles + activates V13 and auto-deactivates V12 (only one active at a time).
5. Proceed to **Post-Activation Validation** below.

### Option 2 — scripted metadata flip (if you prefer Claude to do it)
Deploy V13 with `<status>Active</status>` and V12 with `<status>Inactive</status>` in one deploy. Artifacts can be
regenerated from `Data/sc3393/v13_build/`. (Less battle-tested than the UI Activate button on a live engine — UI preferred.)

---

## POST-ACTIVATION VALIDATION (do immediately after activating)

**A. Primary acceptance — US Services products now add, with NO regional pricing:**
On a US/USD quote (e.g. clone the failing quote `0Q0WC0000037tXV0AY`, OhioHealth), add all five:
`24 X 7 X 365 Monitoring` · `CSCO I & II Course` · `Administering Automated Password Management` ·
`AIC Expert Services` · `Automate Expert Services`. **Expect:** all five add (no SF-Pricing-00006 / SF-BRF-00004);
`UnitPrice`/`NetUnitPrice` = standard catalog price; `Regional_NetUnit_Price__c` stays null and unused.

**B. Regression guard — regional path still works (CRITICAL):**
On an Italy line where `Regional_NetUnit_Price__c > 0` (e.g. quote 00780873 *24 X 7 X 365 Monitoring*, Regional = 9600),
UI **Reprice All**. **Expect:** the regional reconcile still fires (net == list == regional), identical to V12.

**C. Control — non-Services unaffected:**
Add a flag-false product (e.g. *24 X 7 X 365 Monitoring (Technical)* `01tWC00000FBWonYAH`, or any beSECURE/hardware
SKU). **Expect:** adds and prices exactly as before.

**Read-only post-check (Claude can run):** after you add the lines, `SELECT COUNT(Id) FROM QuoteLineItem WHERE
Allow_Regional_Pricing__c = true AND CreatedDate = TODAY` should be > 0 again (it has been **0** since the V10 gate
went live on 2026-06-10).

**Sign-off:** A (all five add, US gets no regional price) **and** B (Italy path unchanged) **and** C (controls unchanged).

---

## ROLLBACK (instant, if anything misbehaves)
Re-activate **V12** (UI: open V12 → Activate; this auto-deactivates V13). No data to revert — the fix is logic-only.

## Artifacts
- `Data/sc3393/v13_build/build_v13.py` — deterministic builder (+ asserts).
- `Data/sc3393/v13_build/src/` — the deployed V13 package (package.xml + V130 version file).
- `Data/sc3393/verify_v13/` — post-deploy retrieve proving V12=Active / V13=Inactive + guard.
- Deploy IDs: dry-run `0AfWC00000GIH620AH`; real `0AfWC00000GILZR0A5`.
