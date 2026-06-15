# SC-3346 Renewal-Maintenance Commit Defect — Deep RCA (FortraUAT, V14, 2026-06-14)

> ## ⭐ TEST-RESULT ADDENDUM (2026-06-14, post-RCA authorized live test) — H5 lever-d REFUTED as a fix
> An authorized offline test (deactivate V14 → deploy the `RenMaintCOLA` `resultIncluded=true` committer built drift-safe from a fresh retrieve → reactivate → reprice → rolled back clean) settled the one CONTINGENT hypothesis:
> - **Proven (solid):** deploying + activating the procedure-side committer produced **ZERO change** — the canary's committed `NetUnitPrice` stayed **60.64**, the two `$0` lines stayed **0**; regression clean (control 67.38 / NB-derive 71 / perpetual 355 unchanged; Accepted line untouched). **Lever-d does not heal existing fossils.**
> - **Honesty correction:** I initially read the canary's `InputUnitPrice={e2Sn4AI=67.38}` map as proof the element executed. It is **not** — that 67.38 is **prehook-sourced**, present identically in all three logs (stale-runtime / lever-d-active / post-rollback are byte-identical). So the test **cannot** confirm the element fired; it cannot distinguish "element ran but the `NetUnitPrice` write was discarded on the settled derived node" from "element didn't fire on these nodes." Both confirm lever-d is ineffective.
> - **What this establishes:** **no reprice-time mechanism tried — the posthook (H2) *or* a `resultIncluded=true` procedure committer — moves the committed `NetUnitPrice` on a settled derived (`ItemIsDerived`) QA-less line.** Strong empirical support that `NetUnitPrice` is effectively locked post-settlement; the exact micro-mechanism is not independently pinned (future disambiguation: have the element write a *custom* field to prove execution).
> - **Net (unchanged, now solid by elimination):** the **only** viable fix is **H3 born-net at creation** (Renew QuoteAction → priced node) or **de-derive**. No reprice-time change heals existing fossils. Operational notes: ESD deploy requires V14 deactivated first; the UI **reactivate** step is what republishes the runtime (a deploy auto-showing "Active" does *not* recompile it — the first reprice ran stale). Procedure restored to exact pre-test baseline (1416 steps, 0 `RenMaintCOLA`).
>
> *The body below is the pre-test RCA; this addendum overrides its "Fix Option 2 (lever-d, contingent)" and "Recommended path step 2".*

**Org:** FortraUAT `00DWC000006eUFF2A2` (`liam.jeong.c@fortra.com.uat`) — *not* the empty `5sinfusion--uat` org that the bare `uat` alias resolves to (DF3 drift trap).
**Scope:** BoKS `PIA-PIA-RRM-PIAM` (Product2 `01tWC00000DD1buYAD`) renewal-maintenance lines.
**Active pricing procedure:** `Rev_Mgmt_Default_Pricing_Procedure` ExpressionSetVersion `9QMWC00000023eX4AQ` **V14**, sole Active (MF1, confirmed live via MDAPI; ESV not SOQL-queryable). Always re-confirm V14 + 0 lever-d elements immediately before any deploy — the procedure is co-owned (Marc/Nir) and churns.
**Authoritative source copies:** `Data/sc-maint/sc3346_fix/rn_partner_dd/live_apex/` (byte-identical to live except trailing newline), **not** `Org Data/_src/` (stale). Re-retrieve `COLAUpliftPrehook` fresh — live LMD `2026-06-14T14:40:21Z` postdates the 12:23 retrieve.

---

## Executive verdict — the ONE root cause

A BoKS renewal-maintenance line commits the correct COLA net (67.38) **if and only if it carries a `Type='Renew'` QuoteAction at birth**; every line that lacks one (the configurator-auto-added RRM lines, which is all of them except one hand-built control) is a **QuoteAction-less derived node whose committed `NetUnitPrice` the pricing stack cannot durably write** — so it freezes at whatever value the *pre-v1.5* posthook's partner-double-discount stamped into it (60.64 = 67.38×0.90, or 54.58, or $0). The upstream cause is a **SKU mismatch**: customers own `PIA-PIA-RNM-PIAMBK` (New-Maint) assets but the renewal line is the `PIA-PIA-RRM-PIAM` (Renewal-Maint) SKU auto-added by Year-2 PCR `14OWC0000022Eyb2AE`, so `initiateRenewal` can never SKU-match an RRM asset to mint the Renew QuoteAction (**H3**). The proximate writer that *created* the wrong value (the posthook deferred re-discount, **H1**) is **already fixed in live v1.5**; what remains is a **frozen fossil on a node where every post-procedure corrective write no-ops** (**H2**), proven by a post-v1.5 FINEST log in which the posthook emits `Net=67.38` yet all 96 `NetUnitPrice` dumps stay 60.64.

**One sentence:** *The committed `NetUnitPrice` is wrong because the auto-added RRM line has no Renew QuoteAction (H3, SKU-mismatch), which (a) denied it the born-net 67.38 path and (b) leaves it a settled derived node that silently rejects the posthook's corrective write — so the pre-v1.5 ×0.90 fossil persists.*

---

## The mechanism, end to end

### Actors (live, verified)
| Component | Id / location | Role |
|---|---|---|
| Year-2 AutoAdd PCR | `14OWC0000022Eyb2AE` (Active, Configurator, Seq 20) | Auto-adds RRM `01tWC00000DD1buYAD` to any Renewal quote carrying the Perpetual license — **no QuoteAction** (MF5) |
| `COLAUpliftHandler` | `01pWC000001wN3iYAE` (api59, Marc, LMD 06-10) | Born-net path; **QuoteAction-gated** (L29-31 early-return, L39 `Type='Renew'`, L280-282 `if QuoteActionId==null continue`). Writes `UnitPrice`+`COLA_Source__c`, **never `NetUnitPrice`** (MF3) |
| `COLAUpliftPrehook` | `01pWC000001wNGbYAM` (api65, LMD 06-14T14:40) | Stamped path `appendStampedRenewalMaintenanceUpdates` L499-542 — **provenance-independent** (`FPT='Renewal Maintenance' AND QuoteTypeText__c='Renewal' AND Base_Price__c>0`). Seeds `COLACalculatedPrice__c` only; **zero `NetUnitPrice` writes** (MF3, MF6) |
| V14 procedure | ESV `9QMWC00000023eX4AQ` | `DerivedPricingRenewals` (seq7, **RI=false**) computes the COLA net; both partner ×0.90 committers (`PartnerDiscountDerivedMaintenance20` seq8, `PartnerDiscount30` seq11, RI=true) are **filter-gated OUT of renewals** (MF1) |
| `PartnerPricingPrehook` | `01pWC000001wAzNYAU` (api65) | `buildPartnerPercentOnlyUpdate` stamps `PartnerDiscountPercent`+`Partner_Pricing_Source__c='System Calculated (Pre-Procedure, Deferred List)'` — **does NOT write `NetUnitPrice`** (RP6, MF6) |
| `PartnerNetPricePosthook` **v1.5** | `01pWC000002VmiLYAS` (api65, **LMD 2026-06-14T02:35:00Z**, Liam) | Computes COLA net + the (now-bypassed) deferred ×0.90 (MF2) |
| `PartnerPricingService` | `01pWC000001wAzPYAU` (api65, Nir) | `getMarginForProductType('Renewal Maintenance')→Renewal_Maintenance_Percent__c`; `calculateDiscountPrice` (MF4) |

### Step diagram

```
[BIRTH]  Renewal quote on Perpetual license
   │  PCR 14OWC0000022Eyb2AE AutoAdd  →  RRM line 01tWC00000DD1buYAD, QuoteActionId = null
   │        (initiateRenewal CANNOT SKU-match: account owns RNM-PIAMBK, not RRM-PIAM)        ◄── H3 ROOT (MF5/DF3/DF5)
   ▼
[PREHOOK seed]
   COLAUpliftPrehook.appendStampedRenewalMaintenanceUpdates (L499-542, provenance-independent)
   → COLACalculatedPrice__c = (Base_Price 71 − Prior_Partner 8.52 − 0) × (1+7.85/100) = 67.38   ✔ correct
   PartnerPricingPrehook.buildPartnerPercentOnlyUpdate → PartnerDiscountPercent=12, source='Pre-Procedure, Deferred List'
   COLAUpliftHandler born-net path SKIPPED (QuoteActionId==null, L280-282)  → COLA_Source__c stays null
   ▼
[PROCEDURE V14]
   DerivedPricingRenewals (seq7, RI=false): NetUnitPrice ← IF(Renewal, IF(COLACalc>0, COLACalc,…)) = 67.38  (in-engine)
   Partner ×0.90 committers (seq8/seq11) FILTER-GATED OUT of renewals → procedure does NOT produce 60.64   ◄── MF1
   ▼
┌─ PRE-v1.5 (≤06-13)  ────────────────────────────────────────────────┐   ◄── H1, the value-CREATOR
│ PartnerNetPricePosthook v1.4:                                        │
│   buildRenewalMaintenanceColaUpdate → null (procedureNet 67.38 == colaNet 67.38)
│   NO bypass → calculateDeferredPartnerPrice(67.38, 10) → 67.38×0.90 = 60.64
│   committed NetUnitPrice = 60.64   ── PROVEN: skip_reprice_60.64.log L11806        │
│   deferredResult{adjustedPrice:60.64, currentPrice:67.38, totalPercent:10.00}      │
└──────────────────────────────────────────────────────────────────────┘
   ▼  (06-14 02:35Z: v1.5 deployed)
┌─ POST-v1.5 (live now)  ─────────────────────────────────────────────┐   ◄── H2, why it PERSISTS
│ PartnerNetPricePosthook v1.5:                                        │
│   loadRenewalMaintenanceLines (L811-830): SOQL FPT='Renewal Maintenance' AND QuoteTypeText__c='Renewal'
│        → canary IS in renewalMaintenanceByLineId  (NO QuoteActionId predicate — PROVENANCE-INDEPENDENT)
│   BYPASS L232-237: containsKey → return null  →  calculateDeferredPartnerPrice NEVER CALLED            │
│        PROVEN: log_1910_44.log  calculateDeferredPartnerPrice = 0, shouldSkipProcedureOwnedPartner = 0  │
│   buildRenewalMaintenanceColaUpdate: procedureNet=60.64 ≠ colaNet=67.38 → builds corrective update      │
│        emits "RENEWAL MAINT COLA: Line 0QLWC000003e2Sn4AI -> Net=67.38" (log L10990, 1 occurrence)      │
│        submitContextUpdates → updateContextAttributes(NetUnitPrice=67.38) RETURNS CLEAN                 │
│   ENGINE SILENTLY DROPS THE WRITE on the settled QA-null/IsDerived node:                                │
│        all 96 NetUnitPrice dumps = 60.64; zero at 67.38; COLACalculatedPrice__c (custom field) DID land  │
│   committed NetUnitPrice = 60.64 (UNCHANGED)  →  FROZEN FOSSIL                                          │
└──────────────────────────────────────────────────────────────────────┘
```

The 60.64 currently on the canary is a **persisted value written by the v1.4 deferred path before 06-14 02:35Z**; the 19:10:46Z reprice (post-v1.5) re-ran the full stack, suppressed the re-discount, *built* the correct 67.38, and the engine **discarded** it. Critically, the engine accepts the `COLACalculatedPrice__c` custom-field write in the same `updateContextAttributes` batch but rejects the engine-owned `NetUnitPrice` write — the no-op is a property of the attribute × settled-derived-node, not of the Apex.

---

## Reconciling the contradictions — hypothesis-by-hypothesis

### H1 — ACTIVE-DOUBLE-DISCOUNT (posthook re-applies ×0.90 live) → **REFUTED as current, CONFIRMED as the historical value-creator**
- **Tally:** refuted 2 / partial 1.
- **Decisive evidence:** Pre-v1.5 `skip_reprice_60.64.log` (Jun-13 14:07) proves H1 was real under v1.4 — `calculateDeferredPartnerPrice` computed `67.38×0.90=60.64` in-flight (`deferredResult{adjustedPrice:60.64,...,totalPercent:10.00}` L11806). Post-v1.5 `log_1910_44.log` (19:10:44Z, *verified on disk this session*): `calculateDeferredPartnerPrice=0`, `shouldSkipProcedureOwnedPartner=0`, `deferredResult=0` — the deferred path is **never reached** under live v1.5.
- **H1's stated premise is false against live code:** the v1.5 bypass keys on `renewalMaintenanceByLineId` membership, loaded by `loadRenewalMaintenanceLines` SOQL on `FPT + QuoteTypeText__c` with **no QuoteActionId predicate** (grep: 0 QuoteActionId refs in the posthook). The QA-null canary **is** in the map and **is** bypassed. The "auto-added lines fall through" framing was based on log line-numbers that don't match the v1.5 source (the log ran a pre-v1.5 build, mtime Jun-13 16:09 < v1.5 deploy 02:35Z).
- **Resolution:** H1 is the mechanism that *minted* the fossil pre-v1.5; it is code-closed now.

### H2 — BORN-STALE-FROZEN-FOSSIL (write no-ops; reprice doesn't heal) → **CONFIRMED for current live state**
- **Tally:** confirmed 2 / partial 1.
- **Decisive evidence:** `log_1910_44.log` — `NetUnitPrice={...e2Sn4AI=60.64}` enters at the first context dump (before any pricing Apex), the posthook builds + submits the 67.38 corrective update (`buildRenewalMaintenanceColaUpdate` ran; `updateContextAttributes` returned clean), yet **all 96** post-write `NetUnitPrice` dumps remain 60.64 and the committed record is unchanged (LMD 19:10:46Z = the reprice). Independently reproduced by the intermediate forced-write build (`posthook_test.log`: forced `Net=67.38`, quote still committed 60.64).
- **H2's literal "qty-0 / unpriced No-Change node" framing is REFUTED:** the live canary is a **priced qty-1** derived line (`Quantity=1`, `ParentQuoteLineItemId=null`, on derived PBE `01uWC000006XPPBYA4`). The no-op happens on a qty-1 priced node.

### H1-vs-H2 resolution — **it is POSTHOOK-VERSION conditioning, NOT line-structure conditioning**
The handoff hypothesized the split was qty-0 (H2 no-op) vs qty-1 (H1 active). **The evidence overturns that.** The *same* qty-1 collapsed canary shows H1 under v1.4 (active 67.38→60.64 in `skip_reprice_60.64.log`) and H2 under v1.5 (frozen no-op in `log_1910_44.log`). H1 and H2 are **sequential, not competing**: H1 (pre-v1.5) **created** the 60.64; H2 (post-v1.5) is **why it persists** because the corrective write no-ops. The qty-0/qty-1 distinction is irrelevant to the bug.

### H3 — NO-RENEW-QUOTEACTION / SKU-MISMATCH (the upstream cause) → **CONFIRMED (unanimous)**
- **Tally:** confirmed 3 / 0.
- **Decisive evidence:** Perfect 1-of-7 correlation (DF1): the only line committing 67.38 (`0QLWC000003dEW24AM`) is the only one with a QuoteActionId (`7ocWC00000u7yf8YAA`, `Type='Renew'`, SourceAsset = the one and only `PIA-PIA-RRM-PIAM` asset org-wide). All 6 wrong lines have `QuoteActionId=null` + `COLA_Source__c=None`. Org-wide: **1 of 498,251** renewal-maint QLIs carries a QuoteAction (DF3). Asset census (DF5): exactly **1** RRM asset org-wide, on the one passing account; the 3 failing accounts own only `RNM-PIAMBK + NRPS-PIAP`. Control and canary are field-for-field identical (Base 71, Prior 8.52, COLA% 7.85, PartnerDiscountPercent 12, COLACalc 67.38, same product, same Discount billing model) **except QuoteActionId** (DF2/MF3/MF4).
- **Refinement:** the discriminator is **line-level QuoteActionId from an RRM-SKU-matched Renew QuoteAction**, *not* "the quote has any Renew QuoteAction" — DPP Test 1 has a Renew QA (for beSECURE) yet its BoKS line still fails (DF3).
- **H3 is upstream-cause; H1 was proximate-writer.** H3 explains *why the line is in the broken cohort and is unhealable*; H1 (pre-v1.5) explains *what number got written*. They compose: H3 → no born-net path + settled QA-null node → H1 fills the void with ×0.90 (pre-v1.5) → H2 freezes it (post-v1.5).

### H4 — $0-UNSEEDED-BASE as a distinct sub-mechanism → **REFUTED (unanimous, 3/0)**
- **Decisive evidence:** the two BoKS $0 RRM lines (`0QLWC000003cN584AE`, `0QLWC000003ck6X4AQ`) both have **`Source_List_Price__c=355`, `Base_Price__c=71`, `COLACalculatedPrice__c=67.38` — fully SEEDED** (DF1/DF2/DF5/MF6). `computeRenewalMaintenanceColaNet` returns 67.38 (does not bail). Their $0 is the **same QA-null no-commit family** as the 60.64 lines.
- The genuine unseeded-base case **exists but is out of scope:** quote `0Q0WC000003735t0AA` is `QuoteTypeText='New'`, its $0 line is `PIA-PIA-RNM-PIAMBK / 'New Maintenance'` with `Source_List_Price__c=null`, built on the **inactive** Standard Price Book (`01sa5000001vuxlAAA`, IsActive=false) whose PBE is `IsDerived=false` with 0 PBEDP (DF4). That is a **pricebook/data misconfiguration**, not the renewal-maint COLA defect, and it fails the `loadRenewalMaintenanceLines` filter entirely.

### H5 — LEVER-D PROCEDURE-COMMIT (ungated RI=true element commits COLACalc→NetUnitPrice) → **CONTINGENT (unanimous, 3/0)**
- **Decisive evidence:** The element was **deployed-then-reverted** (chk_v14 retrieve has `RenMaintCOLACommit`/`RenMaintCOLANet`; chk_revert + current live V14 have 0). **No before/after canary price was ever captured** while active. Validation never passed — `validate_v3.json` FailedValidationError on the **unrelated** `COLAUpliftTest` `buildOverrideMap` drift (the test-suite drift, owner-decided not-to-fix). The crux — *does an ungated RI=true assignment committer overwrite a SETTLED derived/QA-null node?* — is **unverified**, and there is no precedent in V14 (the sole RI=true committer reaching renewals, `DerivedProductsRenewals` seq5, runs *before* the COLA formula and is contributor-gated; all COLA writers are RI=false).
- **Adversarial finding (verifier-3):** `RenMaintCOLANet` writes only `NetUnitPrice`, not `ItemNetTotalPrice`/`NetTotalPrice`/`TotalLineAmount`; the aggregate steps run **after** it, so even a successful overwrite could leave **stale rollups** unless the engine re-derives totals from `NetUnitPrice` between the element and the aggregates — unverified.

### H6 — PROVENANCE-INDEPENDENT POSTHOOK GATE as the minimal fix → **REFUTED as sufficient / suppression-half CONFIRMED**
- **Tally:** refuted 2 / partial 1.
- **Decisive evidence:** **Both halves are already shipped in v1.5** and the canary still commits 60.64. The suppression half works (deferred path bypassed, `calculateDeferredPartnerPrice=0` post-v1.5) and is safe. The **commit half no-ops**: `buildRenewalMaintenanceColaUpdate` already writes `NetUnitPrice=colaNet` (L876); the post-v1.5 log shows it building + submitting 67.38 and the engine dropping it. A *stronger* H6 (force the commit even when procedureNet≠colaNet) is exactly what already ran and failed — the limitation is `Context.IndustriesContext.updateContextAttributes` rejecting the engine-owned `NetUnitPrice` write on a settled derived node, which **no posthook change can escape**.

### Resolved dossier contradictions
- **"RenewalMaintenancePricingService is unwired dead code"** → **partially false.** Its helper `resolveColaLineTotal` **is wired** (posthook L364/L867, runs at runtime) and the class is referenced by active reprice flow V27 (`301WC00000kan4XYAQ`). Only the standalone `finalizeRenewalMaintenanceAfterPricing` entry path is unwired and gacks at `buildContext('SalesTransactionContextExt_v2')` (`1648396304-208856`). Wiring it is **not** an escape from the no-op wall (same `updateContextAttributes` mechanism).
- **"FINEST log shows deferredResult in-flight ⇒ H1 active on live v1.5"** → **false.** That log is pre-v1.5 (mtime/line-number proof). It proves the v1.4 mechanism only.
- **"canary PBE has 0 PBEDP rows" (FIX_SPEC L23)** → **false.** Derived PBE `01uWC000006XPPBYA4` has a valid PBEDP `182WC000000HNcwYAG` (contributor `PIA-PIA-NRPS-PIAP`, Formula=UnitPrice). Config is correct; lever-b is moot (MF6).
- **"native DerivedProductsRenewals overwrites 67.38→0" (design_fix.js)** → not supported for the 60.64 case (the committer is gated out of renewals; it fails to overwrite, the opposite of overwriting-to-0).

---

## Two sub-mechanisms — kept distinct

### (A) Partner double-discount → 60.64 / 54.58 — **THE defect**
- **What:** `computeRenewalMaintenanceColaNet` already subtracts `Prior_Partner_Discount__c` (8.52 = 12% New-Maint × 71) inside the 67.38 base; the pre-v1.5 deferred path then re-applied the billing partner's `Renewal_Maintenance_Percent__c=10%` → `67.38×0.90=60.64`. A second prior-discretionary (6.25) on a quote yields a compounded `60.64×0.90=54.58`, which also propagates through quote **clone** (`0QLWC000003eMph4AE`, a "Renewal Quote Copy", DF6). It is a genuine double-count of **two different partner percent fields** (12% NewMaint baked + 10% RenMaint re-applied).
- **Margin source (MF4):** **not** the canary account's own model (all-null) — it is the **billing partner** account `001WC00000ZtazZYAR` (`Quote.Billing_Partner__c`), model `aGlWC000000Aa3p0AC` (`Renewal_Maintenance_Percent__c=10`). Note: percentages live on the `Partner_Pricing_Model__c` **SObject**, *not* a CMDT — there is no `Partner_Pricing_Model__mdt`.
- **Status:** the **active writer is closed in v1.5** (bypass fires). What remains is the **persisted fossil** (H2) that the corrective write can't overwrite.

### (B) $0 unseeded base — **a SEPARATE New-business pricebook misconfiguration, NOT part of this defect**
- The BoKS RRM $0 lines are **seeded** and belong to family (A)/H2 (QA-null no-commit), **not** unseeded-base.
- The only true unseeded-base line is the New-Maintenance line on the **inactive Standard Price Book** (DF4) — fix is data/config (build on the active Fortra Price Book, or add derived-PBE+PBEDP to Standard PB), not Apex. Track separately.

---

## Blast radius

**Org-wide, exactly one product family (`PIA-PIA-RRM-PIAM`) and 7 COLA-bearing lines are affected** (the other 117 of 124 RRM QLIs are a 2026-05-04 legacy bulk load with null Net/COLA — out of scope). Of the 7: **1 correct, 6 wrong** (two 60.64, two 54.58, two $0).

**The defect has ESCAPED downstream (DF6) — this raises remediation cost materially:**

| Artifact | Id | Value | Note |
|---|---|---|---|
| Accepted quote | `00781068` / `0Q0WC0000037yTx0AI` | GrandTotal 60.64 | **do-not-touch** |
| Activated Order | `00095475` / `801WC00000kaGBpYAM` | TotalAmount 60.64 | **synced to Workday `COM003`** |
| OrderItem (only RRM OI org-wide) | on 00095475 | Net 60.64 | |
| Installed Asset (only RRM asset org-wide) | `02iWC000008GKPaYAO` | Price 60.64 = 67.38×0.90 | fossil baked into the asset |

**Remediation verdict:** a code/config fix MUST remediate existing records, not only new ones — **5 Draft re-priceable wrong lines + 1 Accepted + 3 committed downstream artifacts** (Order/OrderItem/Asset, one in Workday). A pricing fix alone cannot retro-correct an activated order / installed asset / Workday record; **downstream remediation is separate and owner-gated** (order re-price+re-send via `Order_Completed_WD__e`; asset price correction). Note the failing accounts are DPP **test** accounts (the single passing RRM asset was hand-built by Nir 2026-06-11), so real-customer blast radius is currently zero — but in a real base where no account owns an RRM asset, H3 predicts **every** BoKS renewal-maint line would fail.

---

## Fix options — ranked

Regression surface to guard on any procedure/posthook change: **NB-derived maintenance = tier×SLP = 71**, **perpetual license = 301.75**, **FIM renewal = 462**, **the 1 working line `0QLWC000003dEW24AM` = 67.38**.

### Option 1 — H3 creation-path born-net (the DURABLE root fix) — *owner-gated, new lines only*
- **What changes:** Make the renewal-creation process attach a `Type='Renew'` QuoteAction (SKU-matched to an RRM asset) to every auto-added RRM line. Cleanest config form = set each `*-RNM-*` SKU's renewal/substitution product to its `*-RRM-*` counterpart so `initiateRenewal` renews RNM→RRM with a QuoteAction, **and suppress** the Year-2 AutoAdd PCR `14OWC0000022Eyb2AE`. ⚠️ **DF5 correction:** the Product2 `Renewal_Product__c`/`Substitution_Product__c`/`IsRenewable__c` fields **do not exist** in this org, so the config-flip form is unavailable — it must be done in Apex/configurator (`RenewalQuoteLineHandler` stamp) or via the renewal-flow.
- **Resolves:** the root cause, for all NEW renewals. **Proven** (MAINT_ONLY reversible experiment: a born-Renew-linked line committed 2097.9 and held through Force reprice).
- **Risk/safety:** highest design surface (renewal architecture, Nir-owned); does **not** heal the ~498K existing QA-null lines or downstream artifacts; needs renewal-flow/PCR change + regression of the renewal universe.
- **Owner reactivation / V14 republish:** No V14 change; renewal-flow/PCR/Apex ownership = Nir.

### Option 2 — H5 lever-d procedure commit (the only single change that self-heals existing + new) — *contingent, V14 republish*
- **What changes:** Add a `resultIncluded=true` element gated `FPT='Renewal Maintenance' AND COLACalculatedPrice__c>0`, contributor-ungated, sequenced as the **last** `NetUnitPrice` writer (after seq8/seq11), committing `COLACalculatedPrice__c→NetUnitPrice`. Staged form exists in `deploy_v4/v5`.
- **Resolves:** *potentially* every fossil + new line in one change, regardless of QuoteAction — **if** an ungated procedure-side committer overwrites a settled derived node (which the posthook write cannot).
- **Risk/safety:** co-owned V14 (~100k-line regression sweep); ESV hard-delete is platform-blocked (rollback = re-activate prior version offline); the `COLAUpliftTest.buildOverrideMap` drift must be fixed first or validation keeps failing; **rollup-staleness risk** (element writes `NetUnitPrice` only, not `ItemNetTotalPrice`/totals, which feed the aggregates that run after).
- **Owner reactivation / V14 republish:** **Yes** — offline stage-validate-activate with Nir.
- **Decisive open test (CONTINGENT, forbidden read-only):** In an authorized offline window, re-confirm V14 + 0 lever-d elements, fix the test drift so validate passes, stage `deploy_v4`, activate, then `PlaceQuote {pricingPref:Force}` on Draft canary `0Q0WC0000038aXd0AI` with FINEST logging. **ASSERT:** (1) `0QLWC000003e2Sn4AI` flips 60.64→67.38 AND a $0 line (`0QLWC000003ck6X4AQ`) flips 0→67.38 (overwrite-settled-node crux); (2) the line `ItemNetTotalPrice`/`NetTotalPrice` AND Quote GrandTotal also reflect 67.38, not stale 60.64 (rollup crux); (3) regression guards hold (control 67.38, NB-derived 71, perpetual 301.75, FIM 462). Then revert. If (1) stays 60.64/0 or any guard moves → REFUTED.

### Option 3 — H6 posthook provenance-independent gate — *ALREADY SHIPPED, insufficient alone*
- **What changes:** Nothing new to ship — v1.5 already implements the provenance-independent gate (`loadRenewalMaintenanceLines` on `FPT+QuoteTypeText__c`) and a `NetUnitPrice=colaNet` write. It correctly **suppresses** the active re-discount (H1 closed, safe) but the **commit no-ops** on settled QA-null derived nodes.
- **Resolves:** the active ×0.90 re-discount on *new* repricings of QA-less lines (real, valuable). Does **not** heal existing fossils or land a fresh net on the QA-null node.
- **Risk/safety:** lowest (already live, no regression observed). **Insufficient** as the standalone fix.
- **Owner reactivation:** None.

### Option 4 — lever-b/lever-c — **REFUTED**, do not pursue
- (b) PBEDP/list-price: derived PBE already has a valid PBEDP; base seeds to 71; config is not the gap (MF6). (c) prehook seed of engine-owned fields: empirically no-ops on QA-less node; the working line itself has `ListPrice=0`. Both dead.

---

## Recommended path

**Ship first (minimal, safe, already live):** **Keep H6/v1.5** — it is correct, safe, and closes the active re-discount channel for all future repricings of QA-less renewal-maint lines. This is the floor, not the fix.

**Then, to actually resolve the committed-money defect, the choice is between two owner-gated tracks — and the evidence points to running the lever-d test first because it is the only single change that heals the existing 5 re-priceable fossils:**

1. **Authorized offline lever-d (H5) canary test** (Option 2's decisive test). This is the one experiment that can convert "contingent" to a shippable fix and is the only lever that self-heals existing Draft fossils. **If it lands cleanly with no rollup staleness and no regression → ship lever-d as the primary fix.**
2. **If lever-d fails or is unsafe → fall back to H3 born-net (Option 1)** for new lines + explicit data remediation of the existing 6 lines, gated to Nir's renewal-architecture ownership.

**In all cases, downstream remediation is a separate owner-gated workstream:** re-price/re-send Order `00095475` to Workday (publish `Order_Completed_WD__e` with `Order_Id__c`) once the line nets correct, and correct Asset `02iWC000008GKPaYAO` Price. Do **not** touch Accepted quote `00781068` / line `0QLWC000003dAaT4AU`.

**Verification plan (for whichever fix ships):**
- Re-confirm live V14 (sole Active) + 0 lever-d elements immediately before deploy.
- One FINEST `PlaceQuote {pricingPref:Force}` on Draft canary `0Q0WC0000038aXd0AI`; assert `0QLWC000003e2Sn4AI` NetUnitPrice = 67.38 AND `NetTotalPrice`/`Subtotal`/GrandTotal = 67.38 (no stale rollup) AND the corrective write **lands in the post-settle context dump** (not just emitted).
- Heal both $0 lines (`0QLWC000003cN584AE`, `0QLWC000003ck6X4AQ`) → 67.38 (same family, same fix).
- Regression: control line stays 67.38, NB-derived 71, perpetual 301.75, FIM 462.
- Fix the `COLAUpliftTest.buildOverrideMap` 41-error architecture drift before any procedure validate (it is a prod-cutover blocker regardless — 0% compile → 0% coverage).

---

## Remaining uncertainty (not papered over)

1. **The exact platform reason the `NetUnitPrice` write no-ops** (settled-derived-node immutability vs wrong context phase) is observed but not mechanistically proven; the observable fact (submitted, clean return, value unchanged, custom-field sibling lands) is decisive for H2 regardless.
2. **Whether a `pricingPref=Force` reprice differs** from the captured 19:10:44Z reprice — the captured run was a full pricing pass but its pricingPref isn't in the header. The bypass at L232-237 is unconditional on pricing mode, so the H1 refutation is unaffected; the H2 self-heal-under-Force edge is the only residual, resolvable by the Option-2 test.
3. **Lever-d's overwrite-settled-node crux AND rollup-staleness** are both unverified and can only be settled by the authorized offline canary test. Until then, no procedure change should ship.
4. **`COLAUpliftPrehook` is newer than the repo copy** (live LMD 14:40 > 12:23 retrieve) — re-retrieve before trusting its seed logic; not load-bearing for this RCA's posthook/procedure conclusions.

---

## Appendix — evidence map

### Probe → fact
| Fact | Established by |
|---|---|
| H1 active under v1.4 (67.38→60.64 in-flight) | RP5/RP1, `skip_reprice_60.64.log` L11806 |
| H1 closed under v1.5 (deferred path = 0 calls) | DF2 `log_1910_44.log` (verified this session: `calculateDeferredPartnerPrice=0`) |
| H2 no-op write under v1.5 (96 dumps stay 60.64, 1 emit of Net=67.38) | DF2 `log_1910_44.log` (verified this session) |
| v1.5 bypass is provenance-independent (no QuoteActionId predicate) | MF2 (`loadRenewalMaintenanceLines` L811-830) |
| H3 1-of-7 / 1-of-498,251 QuoteAction correlation | DF1, DF3 |
| H3 SKU mismatch (1 RRM asset org-wide; PCR AutoAdd) | DF5, MF5 (PCR `14OWC0000022Eyb2AE`) |
| Born-net path QuoteAction-gated, writes UnitPrice not NetUnitPrice | MF3 (COLAUpliftHandler L29-31/L39/L280-282) |
| Procedure partner ×0.90 committers gated out of renewals | MF1 (seq8 `PartnerDiscountDerivedMaintenance20`, seq11 `PartnerDiscount30`) |
| 10% margin from billing partner model, not CMDT | MF4 (model `aGlWC000000Aa3p0AC`) |
| H4 refuted (RRM $0 lines seeded Base=71/SLP=355) | DF1, DF2, DF5, MF6 |
| True unseeded-base = New-Maint line on inactive Standard PB | DF4 |
| Derived PBE has valid PBEDP (lever-b moot) | MF6 (`182WC000000HNcwYAG`) |
| H5 lever-d deployed-then-reverted, never price-tested | RP3, `chk_v14`/`chk_revert`, `deploy_v3/v4/v5` |
| Blast radius incl. Activated Order 00095475 / Workday COM003 / Asset | DF6 |
| RMPS partially wired (`resolveColaLineTotal` live; finalize gacks) | RP1/RP4/MF2 (posthook L364/L867; gack `1648396304-208856`) |

### Key ids
- **Canary line/quote:** `0QLWC000003e2Sn4AI` / `0Q0WC0000038aXd0AI` (00781109, Draft, NetUnitPrice 60.64)
- **Control line/quote:** `0QLWC000003dEW24AM` / `0Q0WC00000382MH0AY` (00382MH/00781084, Draft, NetUnitPrice 67.38, QuoteActionId `7ocWC00000u7yf8YAA`)
- **$0 lines:** `0QLWC000003cN584AE`, `0QLWC000003ck6X4AQ` (seeded base, no-commit)
- **54.58 lines:** `0QLWC000003cy334AA`, `0QLWC000003eMph4AE` (clone)
- **Accepted (do-not-touch):** `0QLWC000003dAaT4AU` / `00781068`
- **Products:** RRM `01tWC00000DD1buYAD`; RNM `01tWC00000DD1bsYAD`; NRPS license `01tWC00000DD1btYAD`
- **RRM asset (only one):** `02iWC000008GKPaYAO` (Price 60.64); **billing partner:** `001WC00000ZtazZYAR`
- **Procedure:** ESV `9QMWC00000023eX4AQ` V14; **posthook v1.5:** `01pWC000002VmiLYAS` (LMD 2026-06-14T02:35:00Z)
- **Decisive logs:** pre-v1.5 `Data/sc-maint/sc3404/logs/skip_reprice_60.64.log`; post-v1.5 `Data/sc-maint/rca_deep/work/DF2-provenance/log_1910_44.log`

### Formulas
- COLA net: `(Base_Price 71 − Prior_Partner 8.52 − Prior_Discretionary 0) × (1 + 7.85/100) = 62.48 × 1.0785 = 67.38`
- Partner double-discount: `67.38 × (1 − 10/100) = 60.64`; compounded `60.64 × 0.90 = 54.58`
- Prior-partner baked-in: `8.52 = 12% × 71` (New-Maint percent); re-applied 10% = Renewal-Maint percent → genuine two-field double-count
- Asset fossil: `Asset.Price 60.64 = 67.38 × 0.90`; RNM asset fossil `62.48 = 71 × 0.88`