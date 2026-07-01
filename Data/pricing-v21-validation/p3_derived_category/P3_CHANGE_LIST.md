# Portion 3 — Derived + Category Totals — V21 Change List (for the Integrator)

**Branch artifact:** `Data/pricing-v21-validation/p3_derived_category/deploy/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition`
**Baseline:** `Data/pricing-v21-validation/v21_fix_baseline/` (fresh retrieve 2026‑06‑29, **byte‑identical to `proc_retrieve/` 21:57** → stable, not mid‑oscillation). md5 `d403d9618f21a20053b01437a59e16fd`.
**Active proc confirmed:** `Rev_Mgmt_Default_Pricing_Procedure` V21 = **Active** (design `9QBWC0000000oWH4AY`), context `SalesTransactionContextExt_v2` v23.
**Scope:** edits confined to the **V21 (last) `<versions>` block only**; V1–V20 are **byte‑identical** to baseline (verified). XML well‑formed (`xmllint`). Net `+250` lines.
**Patch:** `V21_P3.patch` (raw), `V21_P3_readable.diff` (entity‑unescaped). Re‑apply with `python3 apply_p3_edits.py` on a fresh baseline copy.

> ⚠️ I did **NOT** touch any Stamp step. K‑02 went into **`ListContainer9`** (Derived Pricing Formula's container), not `StampContributorBasePreDiscount`. So **105 (P1), 106 (P2), and 107 (P3) are all content‑identical to baseline** — zero stamp‑step adjacency to reconcile.

---

## The four edits

### 0. 7‑TIER RESTORE  ★ the land‑mine — CRITICAL, do not drop ★
The active V21's `DerivedPricingFormula` (element `DerivedPricingFormula`, parent `ListContainer9`) shipped a **3‑tier** rate chain — the V21 `<description>` literally says *"Derived Pricing Formula reverted to 3‑tier. DRAFT."* That zeroes Basic/Premium/Express/Expert maintenance (×0 ⇒ $0; ~1,031+ historical rows).
- **FROM:** `IF(AttributeValue='Premier',0.30,IF('Standard',0.20,IF('Professional',0.20,0)))`
- **TO (7‑tier, rates verified live vs `Maintenance_Rate__mdt` to the cent):** `IF('Basic',0.15,IF('Standard',0.20,IF('Professional',0.20,IF('Premium',0.24,IF('Express',0.30,IF('Premier',0.30,IF('Expert',0.35,0)))))))`
- Renewal wrapper `IF(QuoteTypeText__c='Renewal',NetUnitPrice,…)` and the base‑resolution tail `* IF(Base_Price__c>0,…)` are **UNCHANGED**. `platinum` intentionally falls to `else 0` (no MDT rate).

### 1. J‑10 — EUR+COLA+partner derived‑renewal nets $0  (CRITICAL)
Root: the COLA net‑assignment group (`ListContainer2`, COLA Uplift Net on Renewal, top‑seq24) is gated by filter **`COLAUpliftonRenewal`** whose **criterion 3 = `DerivedPricingAttribute Equals false`** excludes derived lines, so `COLACalculatedPrice__c` (=3666.90 on the repro) is computed but never assigned ⇒ FX 0×0.9346=0.
- **EDIT:** drop criterion 3; `conditionLogic` `1 AND 2 AND 3 AND 4 AND 5 AND 6` → `1 AND 2 AND 4 AND 5 AND 6`. (Kept crit 2 `DerivedPricingAttribute IsNotNull` per the validation doc's "drop gate 3".)
- After this, derived renewal lines get `NetUnitPrice=COLACalculatedPrice__c` at seq24 (runs *after* the derived formula seq17 + reset seq23, so it sticks), then existing FX → ≈3427.
- **Coordination note:** this is only the *procedure half*. The companion born‑net/QuoteAction Apex (J‑04/F‑02) is **deferred** — J‑10 alone may not populate every renewal‑maint line; verify on the EUR cell regardless.

### 2. K‑02 — missing‑contributor derived line silently $0  (CRITICAL)
New step **`SurfaceMissingContributorK02`** (FormulaBasedPricing) added as a child of **`ListContainer9`** (already derived‑gated by `DerivedMaintenanceNetFilter` ItemIsDerived=true), **seq3**, immediately after `DerivedPricingFormula` (seq2).
- Output: **`ValidationResult`** (confirmed `<fieldType>inputoutput</fieldType>`, dataType string in the active v23 context — writable, **no context change required**).
- Formula (mirrors the derived formula's own base resolution, so it is independent of the seq23 net‑reset entanglement and matches the brief's exact condition):
  `IF(QuoteTypeText__c='Renewal', ValidationResult, IF(Base_Price__c>0, ValidationResult, IF(Pre_Partner_Price__c>0, ValidationResult, IF(InputUnitPrice>0, ValidationResult, 'MissingContributor'))))`
- Effect: non‑renewal derived line with **all** contributor‑base fields ≤0 ⇒ `ValidationResult='MissingContributor'`; every other line passes ValidationResult through unchanged. Distinguishes the missing‑**contributor** case (base=0) from the separate no‑MTD‑tier $0 (tier=0, SC‑3346 A‑07 data gap) — the latter is intentionally NOT flagged.
- **OPEN RISK to verify post‑deploy:** whether a non‑null `ValidationResult` *soft‑surfaces* vs *hard‑blocks* the transaction. Brief endorses the field; confirm UX in the verify step. If blocking is too aggressive the owner may prefer a softer custom message field.

### 3. K‑09 — empty category groups keep stale totals  (SC‑3345 residual)
Category totals are written only by per‑category aggregate groups (`ListContainer8`→`Total_Services__c`, `Copy1ofListContainer8`→`Total_Software__c`, `Copy1ofCopy1ofListContainer8`→`Total_Subscription__c`); a SUM over an empty filtered group writes nothing ⇒ stale prior value persists.
- **EDIT:** 3 new **top‑level** FormulaBasedPricing zero‑inits (formula `0`, modeled on top‑level `DiscountPercent`): `ResetTotalServicesK09`/`ResetTotalSoftwareK09`/`ResetTotalSubscriptionK09` → `Total_Services__c`/`Total_Software__c`/`Total_Subscription__c`.
- **Placement / renumber:** resets given top‑level **seq 33/34/35**; existing top‑level steps **33→36 … 46→49** (+3). Relative order preserved; parent links are by name (unaffected); criteria seqs are filter‑local (unaffected). The resets run before the aggregate containers (now 36/37/38).
- **`Total_Discount_Amount__c` deliberately EXCLUDED** (brief said "mirror for"): in V21 it is **only read** (dead `DiscountPercent` formula at the never‑written `ListPriceBuffer__c`) and **never written by the procedure** — a proc‑side reset has no aggregate to precede and could clobber a value written elsewhere. Flag to owner: its staleness, if real, lives outside this procedure.

---

## Integrator merge notes
- **Renumber is the only cross‑portion touch‑point.** My +3 shift of top‑level seqs 33–49 includes **Portion 2's Currency Conversion steps (were 36–39 → now 39–42)**. P2 edits those by **api name / `<value>`**, not seq, so their formula edits still apply; just take my seq values (or re‑emit the full ordered `steps[]` and assign final seqs). The three reset steps must end up **before** `ListContainer8`/`Copy1…`/`Copy1ofCopy1…`.
- New `<steps>` are inserted **contiguously, before the first `<variables>`** in the V21 block (per the known "Element steps is duplicated" gotcha).
- Keep the 2 `PricingActionParameters` context bindings; never hard‑delete versions. Deploy api **67.0**, `--metadata-dir`, **deactivate → deploy → reactivate** (UI activation only).

## Verify after the integrated deploy (Force‑reprice each, then re‑query)
- **7‑tier:** a Premium/Basic/Express/Expert maintenance line prices `rate×base` (e.g. Premium 0.24×list), not $0. Standard/Premier regression‑clean.
- **K‑02:** Quote `0Q0WC000003FZ5N0AW` (maint‑only, no license) ⇒ `ValidationResult='MissingContributor'`, not silent $0. Control **J‑02** (license present) still prices 71 / 124.25.
- **J‑10:** Quote `0Q0WC000003FZN70AO` ⇒ derived EUR renewal net ≈ **3427**.
- **K‑09:** Quote `0Q0WC000003FbGr0AK` (Software present; Services/Subscription empty) ⇒ empty Services/Subscription totals = **0**, not stale 555/999.
- Then the joint reprice on shared records: BoKS demo `0Q0WC000003FKRJ0A4`, an EUR quote, a maint‑only quote.
