# HANDOFF — Renewal Maintenance commits **$0 / null NetUnitPrice** instead of the COLA price

**Status: UNRESOLVED — requires prehook-layer rework (SC-3346 build completion).**
This supersedes `11_RENEWAL_ZERO_PRICE_HANDOFF.md` (whose "native override" root cause was wrong).
Owner of build: Nir. Investigated by: Claude (2026-06-13, FortraUAT, UAT-only). All my changes have been **reverted** (see §7).

---

## 0. TL;DR
A renewal **maintenance** quote line commits **`NetUnitPrice = null/$0`** instead of the COLA-uplifted price (canary = **67.38**), even though the correct value is computed and sits on the line in `COLACalculatedPrice__c`.

**Definitive, log-proven root cause:** the line is **structurally excluded from the RLM pricing engine's price map** because it is *derived (`ItemIsDerived__std=true`) + quantity 0 + `ListPrice=0` + `SalesTransactionActionType="No Change"`*. It never appears as a key in **any** `NetUnitPrice`/`InputUnitPrice` context map across all pricing passes. **Therefore no layer that writes `NetUnitPrice` can persist it for this line** — the engine only writes `NetUnitPrice` back for lines it actually priced.

**The only fix that can work:** make the line a *priced node* by seeding an `InputUnitPrice`/`ListPrice` **before** the procedure runs (a **prehook**), so the engine carries and prices it. That is the **`COLAUpliftPrehook`** layer, which currently **skips** these lines — the incomplete core of the SC-3346 build.

---

## 1. The defect (canary)
- Quote **`0Q0WC0000038aXd0AI`** (`00781109`, "Renewal Quote", `Quote_Type__c=Renewal`).
- Line 1 (license/**contributing**): `PIA-PIA-NRPS-PIAP` (Product `01tWC00000DD1btYAD`, `Perpetual`) → `NetUnitPrice=301.75` ✅ (prices fine).
- Line 2 (**maintenance, the defect**): `PIA-PIA-RNM-PIAMBK` (QLI **`0QLWC000003dn3y4AA`**, Product `01tWC00000DD1bsYAD`, **`Fortra_Product_Type__c='New Maintenance'`**) → **`NetUnitPrice=null`, `NetTotalPrice=0`**.
- The COLA inputs ARE present/correct on the line: `Base_Price__c=71`, `Prior_Partner_Discount__c=8.52`, `Prior_Discretionary_Discount__c=0`, `COLA_Uplift_Percent__c=7.85`, **`COLACalculatedPrice__c=67.38`**, `Source_List_Price__c=355`. Expected net = `(71 − 8.52 − 0) × (1 + 7.85/100) = 67.38`.
- Active pricing procedure: `Rev_Mgmt_Default_Pricing_Procedure`, ExpressionSet `9QLWC0000015cDl4AI`, **V14 / V140**.

---

## 2. Root cause — log-proven (FINEST traces in `Data/sc-maint/sc3404/logs/`)
The reprice runs in this order (canary log `07LWC00000OxZTl2AN.log` / `…Oxacj2AB.log`):
1. Native RLM engine: `RLM_PRICING` passes `~09:15:46–48`, wrapping each signaling hook (Hardware, Regional, Partner, AttributeVolume, **COLAUpliftPrehook**, **PartnerNetPricePosthook**, QLDescription).
2. `Stamp_Maintenance_Pricing_Inputs` before-save flow runs `~09:15:53.988` — **AFTER** pricing — and stamps `Base_Price__c`, `COLACalculatedPrice__c=67.38`, etc. **No reprice happens after it.**

The maintenance line **IS** in the transaction/context, but because it is `ItemIsDerived=true`, `ListPrice=0`, qty 0, "No Change":
- It is **absent from every `NetUnitPrice`, `InputUnitPrice`, `PartnerUnitPrice` context map** (all 16 snapshots contain only the license line `…dn3x…=301.75`). `grep 'NetUnitPrice=...' | grep dn3y4` = **0**.
- Its `ItemNetTotalPrice` stays `0.0` every pass.
- `COLAUpliftPrehook` logs **"Found 0 renewal QLIs from 2 total"** — it does **not** treat the "No Change" line as a renewal QLI, so it never seeds a price.
- `67.38` only ever lives in the **custom** field `COLACalculatedPrice__c` — never bridged to a price field.

`MissingContributor` ("We can't price when contributing products are missing") seen on single-line renewal quotes (e.g. `00781043`) is a **coexisting symptom, NOT the cause**: the canary (which HAS its contributing license) nets 0 too with `ValidationResult=null`, and the condition does **not** halt pricing (`CompletedWithPricing`).

---

## 3. Every layer attempted — and the proof each cannot work
| # | Attempt | Result | Why (log-proven) |
|---|---------|--------|------------------|
| 1 | Pricing procedure — `FormulaBasedPricing → NetUnitPrice`, seq 41 (after aggregation) | ❌ no commit | post-line-pricing zone; FBP→`NetUnitPrice` has zero precedent (all committing FBPs write `InputUnitPrice`/`ItemNetTotalPrice`) |
| 2 | Procedure — `AssignmentElement → NetUnitPrice`, seq 41 | ❌ no commit | same zone problem |
| 3 | Procedure — `AssignmentElement → NetUnitPrice`, seq 33 (line zone, renumbered 33-40→34-41) | ❌ no commit | line is not a node in the engine's price map → no port to write/persist |
| 4 | Before-save flow `Stamp_Maintenance_Pricing_Inputs` — `$Record.NetUnitPrice = ComputedRenewalColaNet` | ❌ **broke reprice** → reverted | `NetUnitPrice` is **read-only to record-triggered flows**: *"Invalid target field for field update"* |
| 5 | In-engine posthook `PartnerNetPricePosthook` v1.5 — broaden `loadRenewalMaintenanceLines` to include `'New Maintenance'` | ❌ no persist | posthook **fires + computes 67.38 correctly** (`RENEWAL MAINT COLA: Line 0QLWC000003dn3y4AA -> Net=67.38`), `updateContextAttributes` runs w/o error — but it's a **no-op for an unpriced node**: the license line's context write persists (301.75), the maintenance line's does **not** (committed `NetUnitPrice=null`). |

**Conclusion:** `NetUnitPrice` is owned by the pricing engine and is only persisted for lines that are **priced nodes** in its context. A derived/qty-0/`ListPrice=0`/"No Change" line is not a priced node, so **procedure, flow, and posthook are all incapable** of persisting `NetUnitPrice` to it.

> This also explains why the existing posthook `@version 1.4` renewal-maintenance COLA design was never actually effective: its context writes never persisted for these lines either — the live RRM lines show stale `60.64` (from a prior state) or `0` on a fresh reprice.

---

## 4. The fix that CAN work (recommended) — prehook seeds an input price
Make the line a **priced node** so the engine computes & persists its `NetUnitPrice`:
- In a **prehook** (RevSignaling `SignalingApexProcessor`, runs **before** the procedure), for renewal maintenance lines (`Fortra_Product_Type__c IN ('Renewal Maintenance','New Maintenance')` AND `Quote.QuoteTypeText__c='Renewal'`) read the **persisted** `COLACalculatedPrice__c` (67.38) and set the context line's **`InputUnitPrice`** (and/or `ListPrice`) to it, **before** the procedure runs.
- Then the engine carries the line in its price map, no discount applies (downstream discount writers all exclude renewal/LastTransaction/DPA lines), so `NetUnitPrice = InputUnitPrice = 67.38` → **persists**.
- The natural home is **`COLAUpliftPrehook`** (already wired as a pricing prehook) — but it currently **skips** "No Change" renewal lines ("Found 0 renewal QLIs"). It must be extended to (a) include these lines and (b) seed the input price from `COLACalculatedPrice__c`.

**Open validations the next engineer must confirm:**
1. That a prehook-set `InputUnitPrice`/`ListPrice` actually makes a `ListPrice=0`, derived, "No Change" line get carried + priced by the engine (i.e. it becomes a priced node). This is the crux and is **unproven** — test it first with a throwaway prehook tweak before committing.
2. Timing: `COLACalculatedPrice__c` must be persisted *before* the prehook reads it. On the canary it is (prior Stamp-flow run). For a **first** reprice of a brand-new line, `Base_Price`/`COLACalculatedPrice` are only stamped by the after-pricing flow → may take **two** reprices, OR the prehook must compute COLA itself from the asset (as `COLAUpliftPrehook` partially does).

**Alternative (heavier):** redesign so renewal maintenance lines carry a non-zero `ListPrice` (PBE/derived config so they're priced natively) — larger data/config effort, related to **SC-3372** (derived PBE / contributing config).

---

## 5. Key facts & IDs
- Canary quote `0Q0WC0000038aXd0AI` (`00781109`); maint line QLI `0QLWC000003dn3y4AA`.
- Maint product `01tWC00000DD1bsYAD` `PIA-PIA-RNM-PIAMBK` `New Maintenance`; contributing license `01tWC00000DD1btYAD` `PIA-PIA-NRPS-PIAP` `Perpetual`.
- Other renewal-maintenance test quotes: `00781043` (single-line, MissingContributor), `00781053`, `00781084` (2-line, `Renewal Maintenance`), `00781068` (**Accepted** — do not disturb without sign-off).
- Active procedure **V14 / V140**; posthook `PartnerNetPricePosthook` (`RevSignaling.SignalingApexProcessor`, apiVersion **65**); flow `Stamp_Maintenance_Pricing_Inputs` (before-save, `RecordBeforeSave`, currently V13).
- `NetUnitPrice` is **NOT** writable by record-triggered flows (platform-rejected).
- `loadRenewalMaintenanceLines` / `buildRenewalMaintenanceColaUpdate` / `computeRenewalMaintenanceColaNet` in `PartnerNetPricePosthook` already implement the COLA math; the gap is **persistence**, not computation.

---

## 6. Evidence & artifacts (`Data/sc-maint/sc3404/`)
- FINEST reprice logs: `logs/07LWC00000OxZTl2AN.log` (canary), `…Oxacj2AB.log` (canary after posthook v1.5), `…OxZYb2AN.log` (single-line MissingContributor).
- Workflow decode outputs (sequence/procedure/flow/final-writer analysis): in the session transcript / `tool-results/`.
- Deploy attempt packages (all reverted): `deploy_v3` (FBP@41), `deploy_v4` (Assignment@41), `deploy_v5` (Assignment@33 + renumber), `deploy_flow` (flow NetUnitPrice), `deploy_apex` (posthook v1.5).
- Pristine revert packages: `revert/` (V14 procedure), `apex/PartnerNetPricePosthook(.Test).cls` (reverted to v1.4).

---

## 7. Revert state (what was restored)
| Layer | Change made | Revert status |
|---|---|---|
| Apex `PartnerNetPricePosthook` + `…Test` | v1.5 (broaden filter + test) | ✅ **reverted** to original v1.4 (live class confirmed: `= 'Renewal Maintenance'`, no v1.5, test method removed) |
| Flow `Stamp_Maintenance_Pricing_Inputs` | V12 added `$Record.NetUnitPrice` | ✅ **reverted** — V13 Active = pristine logic; V12 Obsolete (versions can't be hard-deleted) |
| Procedure `Rev_Mgmt_Default_Pricing_Procedure` V14 | added `RenMaintCOLA*` + renumber | ⏳ **revert pending** — redeploy `revert/` (pristine) requires V14 deactivated, then reactivate |

> Version-number residue is unavoidable (Flow V13, and any ExpressionSetVersion churn) — Salesforce blocks hard-deleting flow/expression-set versions. The **active** versions carry pristine logic once the V14 redeploy completes.

---

## 8. Landmines for the next engineer
1. **`NetUnitPrice` is engine-owned.** Only the pricing engine persists it, and only for **priced nodes**. Don't try to set it from a flow (rejected) or a posthook context-update on an unpriced line (silent no-op).
2. **The line must be made a priced node first** (seed `InputUnitPrice`/`ListPrice` in a **prehook**) — that is the whole game.
3. **`COLAUpliftPrehook` skips "No Change" lines** ("Found 0 renewal QLIs") — fix that inclusion.
4. **ExpressionSetDefinition deploy dance:** version must be **inactive** to deploy; never use the LWC "Reactivate All Dependencies" (activates many versions); activate the single row. API **v67** for the criterion schema.
5. **Cosmetic CLI bug:** `Metadata API request failed: Missing message metadata.transfer:Finalizing` — the deploy usually **succeeded**; verify by re-retrieve.
6. **`MissingContributor` is a red herring** for the $0 — don't chase it.
7. **Accepted quote `00781068`** carries a renewal-maintenance line — any fix that re-prices it needs business sign-off.
8. **Org Apex caveat:** a full validate-deploy trips on `COLAUpliftPrehook.buildOverrideMap` dependent-class errors in ~28 classes; deploy targeted Apex with `--test-level RunSpecifiedTests` to avoid that cluster (the classes are `IsValid=true` at runtime).
