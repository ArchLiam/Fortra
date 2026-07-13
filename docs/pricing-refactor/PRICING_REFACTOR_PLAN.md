# Fortra Pricing Solution — Refactor Plan / Roadmap

**Scope:** the `Rev_Mgmt_Default_Pricing_Procedure` ExpressionSet + the `RevSignaling.SignalingApexProcessor` hook/service layer.
**Nature:** planning & analysis only. This document changes nothing in the org or repo. Every execution step it describes (canvas edits, context resyncs, staged activation, deploys) is **future, human-authorized work** — not performed here.
**Author/analysis session:** read-only investigation of live **FortraUAT** (`00DWC000006eUFF2A2`, user `liam.jeong.c@fortra.com.uat`) + this repo.
**Live retrieval window:** 2026-07-06 T19:39–19:44 Z (initial) with a **freshness re-verify at T20:03 Z** (zero delta — active version + all 7 top-risk classes unchanged; see §10.4).
**Ticket:** none supplied and none derivable read-only → evidence lives under `Data/pricing-refactor-scratch/`; "ticket unresolved" is Open Question **OQ-12**. No `Data/sc<ticket>/` mirror was made (a mirror is created only when a ticket is confirmed).
**Evidence root:** `Data/pricing-refactor-scratch/` — `live-classes/*.cls` (32 live bodies), `live-esd/` (live ESD + extracted `ACTIVE_V21_block.xml` + `ACTIVE_V21_steps.tsv`), `soql/*` (version inventory, bindings, plan wiring, class metadata), `diffs/*`, `lanes/*` (5 analysis-lane outputs + orchestrator cross-checks), `RETRIEVAL_LOG.txt` (timestamped retrieval log).

**Tag legend on every claim:** `CONFIRMED` = verified live/in-source this run · `CORRECTED` = an inherited claim proven wrong this run · `UNVERIFIED` = carried forward, not verifiable read-only.
**Finding IDs:** current-state findings are `INV-n` (§3). Lane-level evidence IDs are cross-referenced: `CG-*` (call graph), `DC-*` (duplication), `WF-*`/`INV-*` (waterfall), `VR-*` (versions), `BC-*` (boundary), `OX-*` (orchestrator cross-check). Every roadmap item in §4–§8 cites the `INV-n` it derives from.

---

## 1. Executive Summary *(read this alone to greenlight or redirect)*

The Fortra pricing engine is **one ExpressionSet procedure shared by Quote and Order** (`Rev_Mgmt_Default_Pricing_Procedure`, active version **V21**, `9QBWC0000000oWH4AY`), wrapped by **nine Apex hooks** wired through a single `ProcedurePlan` (`Fortra_Pricing_PreHook`, active `1CvWC0000005vyX0AQ`). It works, it is co-owned by four engineers, and it changes minute-to-minute. It is also **structurally fragile in exactly the ways that have caused nine tracked production regressions** (§10). This plan makes those failure modes *impossible or loudly detectable* — behavior-preservation first — and pays down duplication/dead-code (Priority A) and waterfall-fragility (Priority B) in **separately-gated waves that never mix "safe" and "behavioral" work.**

**The single prerequisite that gates everything: a golden reprice harness (§9).** The only trustworthy behavioral check in this org is *repricing a Quote **and** an Order and diffing outputs* — unit tests alone are not a valid oracle (SC-3346 passed green while live pricing was broken). No wave may start until that harness is re-baselined against current live state. **The `Data/pricing-v21-validation` harness cited in prior notes does not exist in the repo (INV-31) — the matrix must be built from scratch.**

**The five biggest findings (all live-confirmed this run, several inverting prior grounding):**

1. **The Partner V1→V2 flip already happened, and it is *partial* (INV-4, INV-5).** The runtime partner prehook is now **`PartnerPricingPrehookV2`** (flipped 2026-07-01; `PartnerPricingPrehook` V1 is the dead twin) — the inverse of prior docs. But the seq-11 posthook **still calls the V1 `PartnerPricingService`**, so *both* partner-margin services execute in one reprice with *different* `getMarginForProductType` signatures (V2 is deal-type/`Non_Orig_*`-aware; V1 is not). This is a live per-line inconsistency risk on Fortra-Originated deferred/derived lines, and it is the single biggest structural drift in the codebase.
2. **E-04 is now a live data risk, not a pre-flip blocker (INV-6).** `PartnerPricingServiceV2.getMarginForProductType` returns **0% on null `Non_Orig_*_Pct__c`** — and V2 is live. Fortra-Originated deals with unpopulated partner-model data silently price at list. Needs a data-completeness check + a null→catalog fallback decision (owner-gated, OQ-1).
3. **The waterfall is real and load-bearing but undocumented (INV-3, §7).** True runtime order (by `ProcedurePlanSection.Sequence`): Hardware→Regional→Partner(V2)→AttrVolume→COLA→**ESD procedure**→PartnerNetPricePosthook→QLDescription→CancelLineCredit. Six order edges carry named invariants where a silent reorder = a production incident. §7 makes the order a **machine-diffable table** so future resequencing becomes a gated, visible, behavioral change.
4. **The real duplication target is *intra-version* clutter, not the 22-version tail (INV-18, INV-19).** The 20 dormant versions are frozen inert clutter (hard-delete is platform-blocked — leave them). The active V21 alone carries **16 duplicate `<label>` groups (~50 of 128 steps), 6 overloaded generic `<name>`s covering 61 steps, a 28-member non-contiguous `ListContainer` sprawl, and an explicit `Copy1ofCopy1ofListContainer8` aggregate triad.** Plus Apex doubles: V1 partner prehook (dead), `QuoteCurrencyChangeService_Fixed` (orphan), `SourceListPrice*` (disabled no-ops), `RenewalMaintenanceFlip` (zero refs).
5. **Guard/hardcode asymmetries are the latent-regression surface (INV-11, INV-22).** Seven hooks have sound `try/finally` recursion guards; **Hardware and Regional have *none*** (inverse fragility). The largest inline pricing table is in `HardwareAttributePricingPrehook` (pGroup/user-tier/system-type multipliers, no MDT) — a pricing change there needs an Apex deploy.

**Top risks the plan is built around (each maps to a §10 prior regression):** you cannot delete any ExpressionSet version; in-place active-version edits only (canvas is the runtime truth, MDAPI ≠ runtime); field-signature changes need a dual-object context resync or the whole context hard-fails; activation is UI-only and opens a pricing-offline window; co-owned versions oscillate; RLM blocks Quote/OrderItem DML so verification is a managed reprice only.

**Wave sequence (behavior-preserving first; each wave gated on the prior's exit):**
- **Wave 0 — Harness + docs (no code).** Build/re-baseline the golden matrix; publish the §7 waterfall artifact; snapshot the boundary contracts. *Gate: matrix reproduces current live outputs.*
- **Wave 1 — Safe non-behavioral cleanup.** Delete provably-unwired dead code (V1 partner prehook, `SourceListPrice*`, `RenewalMaintenanceFlip`, `_Fixed` once its design call is made); rename; document; quarantine `scratch_v210.xml`. *Gate: zero golden delta.*
- **Wave 2 — Hook-thinning.** Extract `execute()` logic into pure, unit-testable services behind unchanged behavior; re-seam characterization tests in lockstep. *Gate: zero golden delta + parallel-run equivalence per hook.*
- **Wave 3 — Duplicate consolidation via parallel-run.** One survivor per concern (unify the two partner margin services; extract one COLA engine both surfaces call). *Gate: retiring + surviving computed side-by-side, equal across the full matrix.*
- **Wave 4 — Hardening.** Null-safety, guard normalization (add Hardware/Regional guards), governor bulkification of the Order-side invocables, config-drive the Hardware/Currency hardcodes, structural idempotency. *Gate: zero golden delta + unchanged governor/CPU counts + unchanged boundary-MDT reads.*

Everything below is traceable evidence → debt → wave. Nothing here authorizes a change to UAT.

---

## 2. Guardrails & Non-Negotiables (binding constraints on every recommendation)

Each constraint below is restated from the investigation brief §1 and **cross-referenced to the wave/decision it governs**. Any later recommendation can be checked against this list; none in this plan violates it.

### 2a. Retrieve-live-first — treat all repo source as possibly stale
- Governs: **Wave 0** (re-retrieve before any analysis is trusted), and the freshness protocol (§10.4). This run **retrieved live first and timestamped every retrieve**; force-app currently matches live for all 32 classes (INV-30, a point-in-time fact, not a standing guarantee).
- Binding rule: no execution wave starts without a fresh retrieve of the target class + active ESD version immediately beforehand; any claim that cannot be re-verified live at execution time is tagged UNVERIFIED and blocks the gate.

### 2b. Pricing-procedure platform realities you cannot design around
- **Cannot hard-delete any `ExpressionSetVersion`** (UI/CLI/REST all HTTP-500 while the two `PricingActionParameters` bindings exist; verified historically by canary-deleting inactive V2). Governs: **§6 consolidation map** (versions are retired *conceptually* only) and **Wave 1** (no version deletion appears in any wave). The two bindings — Order `17gWC000000DeAvYAK`, Quote `17gWC000000DeAwYAK` — **must never be removed** (org-wide outage). CONFIRMED live (`soql/pricing_action_parameters.txt`).
- **In-place active-version edits only** — no new versions, no "clone to a clean V22 and cut over." Governs: **§8 all ESD-touching steps**, **§8 anti-goal**. (Note: a Draft V22 already exists, `9QBWC0000000ofx4AA`; it is *not* a cutover target — INV-1.)
- **MDAPI ≠ runtime.** The ESD MDAPI is a single ~124,657-line full inline export of all 22 versions; a successful deploy updated retrievable metadata while the runtime kept executing pre-fix logic through three deactivate→deploy→reactivate cycles until a direct **canvas edit → Save (in-place) → Activate** recompiled it. Governs: **any §8 step implying an MDAPI edit is flagged unsafe**; the canvas is the source of truth (INV-20, INV-21).
- **Activation is UI-only** (`Status` not API-updateable); deactivate→deploy→reactivate opens a **pricing-offline window**. Never use "Reactivate All Dependencies." Governs: **§10 rollback** (lean on the V20 live-backup, INV-18/VR-3) and the offline-window risk.
- **RLM canvas re-save clobbers deploys** (stale open tab re-serializes over a completed deploy on Activate). Governs: **§10 risk R-3** — mandatory reactivation hygiene (close all tabs, fresh tab, Activate from Versions list, immediately re-retrieve).
- **Deploy mechanics (future execution only):** API 67.0, `--metadata-dir` not `-d`, cannot modify the active version (deactivate→deploy→reactivate). Fenced as future human-authorized work throughout §8/§10.

### 2c. The shared-context spine — the #1 silent-regression surface
- The procedure is bound to context **`SalesTransactionContextExt_v2`** (`11OWC000002m21Z2AQ`) for **both** Quote (`QuoteEntitiesMapping`) and Order (`OrderEntitiesMapping`). CONFIRMED live (`soql/pricing_action_parameters.txt`, `plan_definition_versions.txt`). Every field the procedure/hook references must exist on **both** `QuoteLineItem` and `OrderItem` and be hydrated on both mappings, or whole-context materialization hard-fails ("couldn't fetch SalesTransactionContextExt_v2"). Governs: **Wave 2/3/4 any staging-field change is a dual-object + dual-mapping change** and **§9 every scenario reprices both a Quote and an Order.**
- **Field-signature changes require a context resync** (Context Def Manager: Deactivate All Dependencies → save mapping → Sync → Reactivate) or repricing throws "Specify the contextDefinitionName." **Pure formula-literal edits do NOT need a resync; field-signature edits ALWAYS do** — §8 classifies every proposed change accordingly.
- **Live dual-object asymmetry already exists (INV-17):** `COLAUpliftPercent__c` is on QLI only; `RegionalNetUnitPrice__c` is on OrderItem only (Quote path uses `PrehookRSNetUnitPrice__c`/`Pre_Regional_Price__c`). Safe today only because each side references each field where it exists — any unification of these names must create the missing field first.
- **Discovery-procedure interlock:** deactivating pricing context also takes `Salesforce_Default_Pricing_Discovery_Procedure_v2` offline (shared context lifecycle). Governs: **§10 R-4** and why the discovery procedures are load-bearing though out of refactor scope.
- **RLM blocks standard Quote DML and OrderItem Apex DML** — pricing only materializes via the managed connect/PlaceOrder action. Governs: **§9 every behavioral check is a managed reprice, never DML.**

### 2d. Prior regressions → structural-prevention mandate
The nine tracked regressions (§10.1) are the **safety spine**. Each is named in the risk register (§10) and mapped to the wave that prevents it. Overarching rule, baked into §8: **separate non-behavioral work (rename, document, add tests, delete provably-unreferenced code, extract-method with identical output) from behavioral work (consolidating two live implementations, reordering, altering a calculation); they live in separate, separately-gated waves and never mix.**

### 2e. Team Apex style (any code sketched in §5 honors this)
- No local var declarations inside `for`/`while` bodies — hoist above the loop, reassign per iteration.
- Prefer mutating queried records over `new SObject(...)` per row.
- Never strip load-bearing wiring: the two `PricingActionParameters` bindings, RLM permission-set licenses, or the prehook `ProcedurePlanOption` records.

---

## 3. Current-State Inventory

All line/length figures are **live-measured this run** (`Data/pricing-refactor-scratch/soql/apexclass_meta.json`, `diffs/class_drift.csv`) — no inherited counts trusted. Line numbers cited as `<Class>.cls:<n>` refer to the authoritative live bodies in `live-classes/` (force-app copies are byte-identical this run, INV-30).

### 3a. Hook family — `RevSignaling.SignalingApexProcessor` (runtime-binding verdict per row)

Runtime order is **`ProcedurePlanSection.Sequence`** on `Fortra_Pricing_PreHook` active version `1CvWC0000005vyX0AQ` (`soql/plan_sections.txt`), with each section's class resolved from `soql/procedure_plan_options.txt`. All 8 non-disabled hooks CONFIRMED wired; `SourceListPricePrehook` CONFIRMED unwired.

| Seq | Hook (live lines) | Concern | Wired-at-runtime? (binding evidence) | Verdict / key live fact | Tag |
|---|---|---|---|---|---|
| 1 | `HardwareAttributePricingPrehook` (960) | hardware/Power | **YES** — Section `1FRWC0000000a0H4AQ`, ProcedurePlanOption `1FYWC0000002W3p4AE`→`01pWC000001wAzLYAU` | Multiplies list-price base; **no recursion guard (INV-11)**; largest inline pricing table (pGroup/user-tier/system-type, INV-22) | CONFIRMED |
| 2 | `RegionalServicesPricingPrehook` (436) | regional services | **YES** — Section `1FRWC0000000a0I4AQ`, option `1FYWC0000002W3q4AE`→`01pWC000001wAzRYAU` | Country mult to LIST; writes `RegionalNetUnitPrice__c`(Order)/`PrehookRSNetUnitPrice__c`(Quote); **no recursion guard (INV-11)**. KB `executePartnerPricing()` method does not exist | CONFIRMED / CORRECTED |
| 3 | **`PartnerPricingPrehookV2`** (1134) | partner | **YES** — Section `1FRWC0000000a0J4AQ`, option `1FYWC0000002W3r4AE`→**`01pWC000002TL37YAG`**, LastMod **2026-07-01** | **V2 IS LIVE (flip already done); V1 `PartnerPricingPrehook` (1646) is DEAD** (INV-4). Calls `PartnerPricingServiceV2` only | **CORRECTED** |
| 4 | `AttributeVolumePricingPrehook` (895) | attribute/volume | **YES** — Section `1FRWC0000000a0K4AQ`, option `1FYWC0000002W3s4AE`→`01pWC000001wAzJYAU` | Two-pass bulk vs `Attribute_Tier_Pricing_Storage__c`; **silent reset-to-list on no-match/null-volume (INV-14, SC-3390)**; guard `isUpdating` sound | CONFIRMED |
| 6 | `COLAUpliftPrehook` (1468) | COLA renewal | **YES** — Section `1FRWC0000000a0M4AQ`, option `1FYWC0000002W3u4AE`→`01pWC000001wNGbYAM` | Sole producer of `COLACalculatedPrice__c`; **batch-poison field exclusions are load-bearing (INV-16)**; shares `COLAUpliftHandler.isManualLineOverride` | CONFIRMED |
| 10 | ESD `Rev_Mgmt_Default_Pricing_Procedure` | pricing procedure | **YES** — Section `1FRWC0000000a0L4AQ` (SectionType `PricingProcedure`), option `1FYWC0000002W3t4AE` | Active version **V21** `9QBWC0000000oWH4AY`; 128 steps (INV-18/19) | CONFIRMED |
| 11 | `PartnerNetPricePosthook` (**2563**) | partner/commercial net | **YES** — Section `1FRWC0000000aZl4AI`, option `1FYWC0000002W3w4AE`→`01pWC000002VmiLYAS` | **Largest hook (2563 lines — CORRECTS "682"); calls V1 `PartnerPricingService` → partner-service split (INV-5)**; guard sound (finally reset :82) | **CORRECTED** |
| 12 | `QLDescriptionGeneratorPrehook` (863) | line description | **YES** — Section `1FRWC0000000a0N4AQ` (label `DescriptionLinePrehook`), option `1FYWC0000002W3v4AE`→`01pWC000002LYbrYAG` | **Runs seq-12, AFTER procedure+posthook** despite "Prehook" name; 9-element inline attr list w/ MDT fallback (INV-31 note / BC-11) | CONFIRMED |
| 13 | `CancelLineCreditPosthook` (725) | cancellation credit | **YES** — Section `1FRWC0000000c0T4AQ`, option `1FYWC0000002W3x4AE`→`01pWC000002awnVYAQ` | Writes SAVE-mapped API names (not internal `Item*` tags); self-resolves asset net when `CancelNetUnitPrice__c` null | CONFIRMED |
| — | `SourceListPricePrehook` (16) | derived maint | **NO** — absent from `procedure_plan_options.txt` | Disabled no-op ("SourceListPricePrehook disabled", :10-15); live path is `Stamp_Source_List_Price` flow (INV-9) | CONFIRMED |

*(Sequence gaps 5,7,8,9 are intentionally vacant insertion slots. `plan_sections.txt` shows the ESD `PricingProcedure` at seq-10 sitting between COLA (seq-6) and the posthook (seq-11).)*

### 3b. Supporting service / handler / invocable / batch / queueable map (live line counts; call edges from `lanes/lane1-callgraph.md`)

| Class (lines) | Kind | Called by | Notes |
|---|---|---|---|
| `PartnerPricingService` (449) | service | **posthook** (`PartnerNetPricePosthook` ×14) + dead V1 prehook | **V1 service — STILL LIVE via posthook; do NOT delete** (INV-5). 2-arg `getMarginForProductType`, no `Non_Orig_*` |
| `PartnerPricingServiceV2` (209) | service | **live prehook** (`PartnerPricingPrehookV2`) | 3-arg deal-type-aware `getMarginForProductType`; **0% on null `Non_Orig_*` (INV-6, E-04)** |
| `RenewalMaintenancePricingService` (487) | service/@Invocable | posthook (`resolveColaLineTotal` ×3) + flow | Shared quote-total contract (CG-16); keep static |
| `MaintenanceOrderDecompositionService` (966) | service | `OrderRepriceInvocable` | **DML-in-loop `backfillCarryForwardFieldsBulk` :724-736 (INV-12)** |
| `OrderCommercialNetService` (109) | @Invocable | `OrderRepriceInvocable`; assetization | **SOQL+DML per input in invocable loop (INV-12)** |
| `PowerOrderSplittingService` (486) | @Invocable | `Fortra_Quote_to_Order_Conversion` | **SC-3447 mitigated: `MAX_SYNC_CLONES=200` fail-fast + bulk phases (INV-13)** |
| `OrderRepriceInvocable` (152) | @Invocable | Q2O reprice path | Per-request fan-out incl. `PlaceOrderExecutor.execute(Force)` (INV-12) |
| `QuotePriceStampQueueable` (15) | Queueable | posthook `schedulePostPersistPriceStamp` | Cyclic with posthook static `stampAttributeListPricesForQuote` |
| `Fortra_CurrencyConversionService` (248) | service | `Fortra_BulkPriceUpdateBatch` + flow | **String-formula interpreter over `Currency_Conversion_Formula__mdt` = config-as-code (INV-24)**; no wired-hook caller |
| `CurrencySelectionService` (56) | service | flow only | **14-entry inline country→currency map (INV-23)** |
| `QuoteCurrencyChangeService` (102) | @Invocable | flow `Quote_Handle_Quote_Currency_Change` | **WIRED but is a no-op clone (INV-8)** |
| `QuoteCurrencyChangeService_Fixed` (130) | @Invocable | **none** (orphan) | The one that *actually* converts currency; unwired (INV-8) |
| `CurrencyCodeExtractor` (51), `DatedConversionRateLookup` (105) | @Invocable | flow only | No wired-hook caller |
| `COLAUpliftHandler` (495) | trigger handler | `QuoteLineItemTrigger` + others | **LIVE dual COLA surface — NOT dead (INV-7)** |
| `RenewalAssetQuantityHandler`/`Queueable` (236/16) | handler/queueable | flow; self-cyclic async | Not in wired hook graph |
| `RenewalMaintenanceAutoAddHandler` (184) | handler | flow | Live renewal path (supersedes `RenewalMaintenanceFlip`?) — OQ-3 |
| `QuoteMigrationService` (608) | service | migration | Reads `Migration_Field_Default__mdt`, `Operations_Checklist_Config__mdt` |
| `PricingPrehookTestFixtures` (130) | test fixture | characterization tests | Central `@TestVisible` seam builder (INV-30) |
| `RenewalMaintenanceFlip` (105) | @Invocable | **none** (zero refs) | Orphaned SC-3346/SC-3404 remediation (INV-10) |

### 3c. Class-level call graph (condensed; full detail in `lanes/lane1-callgraph.md`)

```
[seq1] Hardware ──(Hardware__c SOQL)──> (self)
[seq2] Regional ──(Services_Regional_Pricing__mdt)──> (self)
[seq3] PartnerV2 ──> PartnerPricingServiceV2 {getPricingModelCandidates, selectBestModelForLine,
                                              getMarginForProductType(3-arg), calc*}
[seq4] AttrVolume ──(Attribute_Tier_Pricing_Storage__c bulk SOQL)──> (self)
[seq6] COLA ──> COLAUpliftHandler.isManualLineOverride (shared predicate)
             └─enqueue─> MyCAPFlagApplier (Queueable → Quote.Mycap__c)
[seq10] ESD procedure (128 steps)
[seq11] Posthook ──> PartnerPricingService (V1! getMarginForProductType 2-arg)   ◄── INV-5 SPLIT
                 ──> RenewalMaintenancePricingService.resolveColaLineTotal ×3
                 └─enqueue─> QuotePriceStampQueueable ──> Posthook.stampAttributeListPricesForQuote (static)
        Posthook.applyNetPricesToOrder (static) ◄── OrderRepriceInvocable.repriceOne
[seq12] QLDescription ──(QL_Description_Attribute__mdt)──> (self)
[seq13] CancelLineCredit ──(AssetActionSource SOQL)──> (self)

OrderRepriceInvocable.repriceOne ──> MaintenanceOrderDecompositionService.{prepareForReprice,persistFromWork}
                                 ──> OrderCommercialNetService.patchOrderItemCommercialUnitPrices
                                 ──> PartnerNetPricePosthook.applyNetPricesToOrder
                                 ──> commerceorders.PlaceOrderExecutor.execute(Force)
DEAD: PartnerPricingPrehook(V1)→PartnerPricingService; SourceListPricePrehook/Resolver (no-op); RenewalMaintenanceFlip (0 refs)
STANDALONE (flow/trigger only, not in wired pricing graph): all Currency* classes, RenewalMaintenance*Handler, QuoteMigrationService
```

### 3d. Procedure version reality (two axes — full detail `lanes/lane4-versions.md`)

**Axis 1 — per-version proliferation (INV-18).** 22 versions (`soql/esd_versions.txt`): **1 Active (V21 `9QBWC0000000oWH4AY`, LastMod 2026-07-03), 1 Draft (V22 `9QBWC0000000ofx4AA`, "(Deprecated)"), 20 Inactive** — all inactive frozen at one bulk timestamp 2026-06-30T19:30:54Z. **CORRECTION:** the active version's fullName suffix is **`_V210`** (VersionNumber 21, label "V21") — self-consistent; the `_V220` fullName is the *separate Draft V22*, not the active version. `(Deprecated)` prefix is absent (deliberately kept) on V14/V15/V16/**V20** and V21; V20 is the **live-backup** (VR-3). Hard-delete is platform-blocked (§2b) → the 20-version tail is inert clutter to leave in place.

**V20→V21 reconcile by label+function (VR-4, CORRECTS the description literal):** V21 = V20 **minus** the partner-percent ESD trio (`Resolve Partner Discount Percent` / `Partner Percent Resolved Filter` / `Partner Percent Procedure Audit` — moved to Apex, aligning with the J-06 `computeNewBusinessMaintenanceNets` lever) **minus** the `Term-Defined proration filter (Line level)` step, **plus** amend-seed / OneTime-net-seed / K-09 zero-init reset guards. The description's **"+ currency"** clause is stale (currency steps exist identically in V20); **"+ guards"** does *not* mean more `IsNotNull` (V21 has 9 vs V20's 12 — VR-6); and **"reverted to 3-tier"** is **UNVERIFIED at the formula body** — the `Derived Pricing Formula` step is byte-identical V20↔V21 (`IF(QuoteTypeText__c='Renewal', NetUnitPrice, 0)`); tiering is delegated to a decision table (VR-5, INV-25). The word **"DRAFT"** on an Active version is a description-hygiene defect.

**Axis 2 — intra-version clone artifacts (INV-19).** The active V21 = **128 steps: 64 BusinessKnowledgeModel + 32 ListGroup + 32 AdvancedListFilter** (CORRECTS "~122 = 58+32+32"). Within it: **16 non-unique `<label>` groups** (`List Container`×12, `List Operation`×8, `Assignment`×4, `Subscription Pricing`×3, `Partner Discount - Derived Maintenance`×3, plus 11 more) covering ~50 steps; **6 overloaded generic `<name>`s** (`formula-section-0-input`×28, `section-0-input1`×14, `section-count`×6, `AdjustmentType`×5, `Quantity`×4, `PriceAdjustmentScheduleId`×4) covering 61 steps; a **28-member non-contiguous `ListContainer` sprawl** (jumps 11→25→28→57→75→720); the **`Copy1ofListContainer8`/`Copy1ofCopy1ofListContainer8` aggregate triad** (Services/Software/Subscription totals differ only by category filter); the `AttributePricingFilter`+`AttributePricingFilter8` twin; and the "Contacted Pricing" typo (should be "Contracted", propagated ×2). **`<name>` is worthless as a step identity — match by `<label>` + `parentStep` + function only.**

### 3e. Context-definition spine (INV-17)

`SalesTransactionContextExt_v2` (`11OWC000002m21Z2AQ`) is bound for both Quote+Order (§2c). Fields on **both** QLI and OrderItem: `Pre_Partner_Price__c`, `CancelNetUnitPrice__c`, `COLACalculatedPrice__c`, `Hardware__c`, `PricingTermCount`. **Asymmetric (latent hazard):** `COLAUpliftPercent__c` (QLI only), `RegionalNetUnitPrice__c` (OrderItem only). `PricingTermCount` is **engine-only writeable — no Apex/flow backstop** (the SC-3406/3411/3415 cascade root, §10.1 #1). Discovery interlock per §2c.

### 3f. Boundary interface catalog (read-only I/O contracts; full detail `lanes/lane5-boundary.md`)

Per in-scope reader → boundary artifact (never refactor the boundary; map only):

| Boundary artifact | Reader(s) | Reads | Writes-back (staging field) | Evidence |
|---|---|---|---|---|
| `COLA_Uplift_Rules__mdt` | `COLAUpliftHandler`, `COLAUpliftPrehook` | 7 fields WHERE `Is_Active__c=true`, key `Solution_Category__c` | Handler → `COLA_Uplift_Percent__c`, `Default_COLA_Uplift_Percent__c` | BC-1 (`COLAUpliftHandler.cls:378`, `COLAUpliftPrehook.cls:867`) — **duplicated loader (INV-29)** |
| `MyCAP_Rules__mdt` | `COLAUpliftHandler`/`Prehook` | `getInstance('Global')` | `COLA_Outyear_Uplift_Percent__c` (inline `3` fallback, BC-13) | BC-2 |
| `Maintenance_Rate__mdt` | `MaintenanceOrderDecompositionService`, `PartnerNetPricePosthook` | `MaintenanceType__c`,`Rate__c` (all rows) | derived NewMaint list/net on QLI/OrderItem | BC-3 — **CORRECTS "inline 7-tier": rates are MDT-sourced (INV-25); duplicated loader (INV-29)** |
| `Services_Regional_Pricing__mdt` | `RegionalServicesPricingPrehook` | `Country__c`,`Country_Code__c`,`Multiplier__c` WHERE active | `RegionalNetUnitPrice__c`(Order)/`PrehookRSNetUnitPrice__c`,`Pre_Regional_Price__c`(Quote) | BC-4 (default 1.0, acceptable) |
| `Currency_Conversion_Formula__mdt` | `Fortra_CurrencyConversionService` | `Conversion_Rate__c` OR `Conversion_Formula__c` (executable string) | — | BC-5 — **config-as-code: string parsed by `applyFormula` (INV-24). No `0.9346` in Apex (CORRECTED)** |
| `Attribute_Tier_Pricing_Storage__c` (object) | `AttributeVolumePricingPrehook` | 10 fields WHERE Product/PSM IN | `Base_Price__c`, `Attribute_Price_Mode__c`, `Attribute_Multiplier_Pct__c` | BC-7 |
| `QL_Description_Attribute__mdt` | `QLDescriptionGeneratorPrehook` | order/role/match fields (active) | `SalesTrxnItemDescription`→`QLI.Description` | BC-6 (config-with-fallback to inline 9-list) |
| PBE tooling (`Fortra_BulkPriceUpdateBatch`/`Invocable`, `UpdatePricebookEntriesInvocable`, `PricebookEntryCascadeDeleter`, `AttributeLoadingService`/`Batch`) | (write-side batch/admin) | Product2/PBE/QLIA | `PricebookEntry`, `QuoteLineItemAttribute` (DML) | BC-9 — boundary; a pricing refactor must not change their PBE-write contract |
| Reprice flows | `Fortra_Quote_Reprice`, `Fortra_Order_Reprice`, `Fortra_Quote_to_Order_Conversion`, `Stamp_Source_List_Price`, `Quote_Handle_Quote_Currency_Change` | invoke ESD; `skipDiscovery=true` on Quote path | — | BC-10 |
| Discovery procedures (4) | flow ref: `Salesforce_Pricing_Discovery_Procedure` only (skipped) | — | — | BC-10 — map-only |
| LKG subsystem (174 `Lkg*` classes) | `LkgAutomatePointsBuilderFactory` entry | — | — | BC-17 / DC-6 — **OUT OF PRICING SCOPE; map-only, not enumerated; `Legacy`=LT11 is LIVE** |

---

## 4. Anti-Pattern / Technical-Debt Register

Each row is scored **S** (Severity: impact if unaddressed, 1–5), **E** (Effort to fix, 1=cheap … 5=large), **R** (Risk of the fix itself, 1=safe … 5=dangerous). **Composite = S + (6−E) + (6−R)** (range 3–15; higher = better first move — high value, low cost, low danger). Rows are ordered by composite. "Class" column: **Safe** = non-behavioral (Wave 1/2) · **Behavioral** = must be parallel-run-gated (Wave 3/4). Every row cites its `INV-n`.

| # | Debt item (evidence) | Priority | INV | S | E | R | Comp | Class | Wave | Incident link |
|---|---|---|---|---|---|---|---|---|---|---|
| D-1 | **Dead V1 partner prehook `PartnerPricingPrehook`** (1646 ln) unwired; only V2 executes | A | INV-4 | 3 | 1 | 1 | **13** | Safe | W1 | — |
| D-2 | **`SourceListPricePrehook`+`SourceListPriceResolver`** disabled no-ops, superseded by flow | A | INV-9 | 2 | 1 | 1 | **12** | Safe | W1 | — |
| D-3 | **`RenewalMaintenanceFlip`** @Invocable, zero references anywhere | A | INV-10 | 2 | 1 | 1 | **12** | Safe | W1 | SC-3346/3404 |
| D-4 | **`scratch_v210.xml` at repo root is a V20-lineage hybrid** (has retired partner-percent trio; lacks `Reset Amount Base From List`) — deploy = regression | A | INV-20 | 4 | 1 | 2 | **11** | Safe (quarantine) | W1 | §10 #2 |
| D-5 | **Waterfall order is undocumented** (no diffable spec; 6 load-bearing edges implicit) | B | INV-3 | 4 | 2 | 1 | **11** | Safe (docs) | W0 | §10 #2,#3 |
| D-6 | **No golden reprice harness in repo** (`Data/pricing-v21-validation` absent); unit tests not a valid oracle | B | INV-31 | 5 | 3 | 1 | **9** | Safe (build) | W0 | SC-3346 |
| D-7 | **Repo ESD `.xml`+`.bak_preedit` are non-authoritative re-serializations** (cosmetic renumber vs live) | A | INV-21 | 2 | 1 | 2 | **11** | Safe (label/ignore) | W1 | §10 #2 |
| D-8 | **Duplicated MDT loaders** (`COLA_Uplift_Rules__mdt` ×2, `Maintenance_Rate__mdt` ×2) | A | INV-29 | 2 | 2 | 2 | **10** | Safe (extract) | W2 | — |
| D-9 | **Hardware + Regional prehooks have NO recursion guard** (7 peers do) — inverse fragility | B | INV-11 | 3 | 2 | 3 | **10** | Behavioral | W4 | §10 #6 |
| D-10 | **`QuoteCurrencyChangeService_Fixed` orphan clone**, and the WIRED class is a no-op (inversion) | A | INV-8 | 3 | 2 | 3 | **10** | Behavioral (design call) | W1 del / W3 flip | — |
| D-11 | **Partner-service split**: live prehook=V2, live posthook=V1, different `getMarginForProductType` | A+B | INV-5 | 5 | 4 | 3 | **8** | Behavioral | W3 | J-06 |
| D-12 | **E-04: 0% partner margin on null `Non_Orig_*`** now on the live V2 path | B | INV-6 | 4 | 3 | 3 | **8** | Behavioral | W3/W4 | E-04 |
| D-13 | **COLA dual-path** (handler + prehook) re-implements the 3-tier hierarchy twice | A+B | INV-7 | 4 | 4 | 3 | **7** | Behavioral (extract) | W3 | SC-3350 |
| D-14 | **`HardwareAttributePricingPrehook` inline pricing tables** (pGroup/user-tier/system-type, no MDT) | A | INV-22 | 3 | 4 | 3 | **7** | Behavioral | W4 | §10 #4 |
| D-15 | **`CurrencySelectionService` hardcoded 14-country map** (no MDT) | A | INV-23 | 2 | 3 | 2 | **9** | Behavioral | W4 | §10 #4 |
| D-16 | **Order-side invocables un-bulkified** (`MaintenanceOrderDecompositionService` DML-in-loop :724; `OrderCommercialNetService`/`OrderRepriceInvocable` per-request fan-out) | B | INV-12 | 3 | 3 | 3 | **8** | Behavioral | W4 | SC-3366 |
| D-17 | **AttrVolume silent reset-to-list on no-match/null-volume** (no user surface) | B | INV-14 | 3 | 3 | 3 | **8** | Behavioral | W4 | SC-3390 |
| D-18 | **Pervasive swallow-to-SUCCESS** (every hook returns SUCCESS on exception; degrade invisible) | B | INV-15 | 3 | 3 | 3 | **8** | Behavioral | W4 | SC-3390 |
| D-19 | **StampBaseFilter null-safety is per-version** (1 instance in active V21; 6 across file) | B | INV-26 | 3 | 3 | 4 | **7** | Behavioral (ESD) | W4 | K-01/SC-3441/F-12 |
| D-20 | **AdvancedListFilter criteria positional** — any criterion edit renumbers + rewrites `<conditionLogic>` | B | INV-27 | 3 | 3 | 4 | **7** | Behavioral (ESD) | W4/doc | §10 #2 |
| D-21 | **`Currency_Conversion_Formula__mdt` config-as-code** (executable string parsed at runtime) | B | INV-24 | 3 | 4 | 4 | **6** | Behavioral (boundary — OQ) | W4/OQ | §10 #4 |
| D-22 | **`execute()` not unit-testable** — coverage is `@TestVisible` seams only; real validation is manual reprice | B | INV-30 | 4 | 4 | 2 | **8** | Safe (harness) | W0/W2 | SC-3346 |
| D-23 | **Intra-version clone clutter in active V21** (16 dup-label groups, 28-member ListContainer sprawl, Copy-of-Copy triad) | A | INV-19 | 3 | 5 | 4 | **6** | Behavioral (ESD, in-place) | W4 | §10 #2 |
| D-24 | **20-version dormant tail** bloats every MDAPI retrieve (~124k lines) | A | INV-18 | 1 | 5 | 5 | **3** | Cannot fix (delete blocked) | — | §10 #2 |

**"Safe to fix now" (top of the list, Wave 1): D-1, D-2, D-3, D-4, D-7** — all provably-unwired/non-authoritative, deletable/quarantine-able with a reference-proof + parallel-run gate and zero behavior change. **"Behavioral / dangerous" (parallel-run-gated, Wave 3/4): D-9 through D-21, D-23.** D-11 (partner-service split) is the highest-value behavioral item but also mid-risk — it anchors Wave 3.

---

## 5. Target Architecture (before → after)

The north star, made concrete on named classes. Each principle below maps 1:1 to a wave (§8) and closes specific `INV-n` gaps.

### 5.1 Principle: thin hook = adapter over a testable service
- **Before:** `execute()` bodies mix runtime-payload marshalling (`request.ctxInstanceId`, `queryTags`, `updateContextAttributes`) with all decision logic — and `RevSignaling.TransactionRequest/Response` have no public constructor, so `execute()` is **not unit-testable** (INV-30). E.g. `PartnerPricingPrehookV2.execute` (1134 ln) does context I/O *and* margin math.
- **After:** each hook is a ~40-line adapter that (1) reads the context into a plain DTO, (2) calls a pure `*Calculator`/`*Engine` service with plain inputs, (3) writes plain outputs back to context. All math lives in a service unit-testable without the RCA runtime. **Illustrated on `PartnerPricingPrehookV2` → `PartnerMarginEngine`; `COLAUpliftPrehook` → `ColaUpliftEngine` (shared with the trigger, D-13).** Gap closed: INV-30 (testability), enables D-8/D-11/D-13. Honors §2e (no loop-var decls; mutate queried records).

### 5.2 Principle: pure calculation separated from context I/O (reusable across QLI + OrderItem)
- **Before:** the posthook (2563 ln, INV-5) interleaves "read `SalesTransactionContextExt_v2` nodes" with "compute net/price," and the Quote vs Order paths duplicate logic with asymmetric field names (`RegionalNetUnitPrice__c` vs `PrehookRSNetUnitPrice__c`, INV-17).
- **After:** a `PricingLineInput` DTO (object-neutral) feeds one calculator; a thin `QuoteContextReader`/`OrderContextReader` maps each object's fields into the DTO. Math is deterministic and identical for both objects. Gap closed: INV-17 dual-object asymmetry becomes a mapping concern, not a math concern.

### 5.3 Principle: single canonical implementation per concern
- **Before:** two partner margin services (V1 posthook / V2 prehook, INV-5); two COLA hierarchies (handler + prehook, INV-7); `_Fixed` currency clone (INV-8).
- **After:** **one `PartnerMarginService`** with a single `getMarginForProductType(model, productType, dealType)` signature that both prehook and posthook call (kills D-11 and centralizes the E-04 null-guard fix D-12); **one `ColaUpliftEngine`** both the trigger and prehook delegate to, keeping only surface glue (D-13); one currency-change implementation after the design call (D-10). Gap closed: INV-5, INV-6, INV-7, INV-8.

### 5.4 Principle: config-driven reads up to the boundary seam (do NOT restructure the MDTs)
- **Before:** `HardwareAttributePricingPrehook` inlines pGroup/user-tier/system-type tables (INV-22); `CurrencySelectionService` inlines a country map (INV-23); COLA out-year `3` inline (BC-13).
- **After:** these move behind a config read (a new `Hardware_Attribute_Pricing__mdt` / `Country_Currency__mdt` — **net-new boundary, owner-gated OQ-4/OQ-5**), matching the pattern the COLA/Regional/Maintenance/Attribute concerns already use. The plan **maps** the existing MDTs as read-only interfaces and does not restructure them. Gap closed: INV-22, INV-23 (Wave 4, behavioral).

### 5.5 Principle: deterministic/idempotent hooks with structural re-entrancy control
- **Before:** static-flag guards, 7 present + 2 absent (INV-11); reprice non-idempotent history (SC-3390, INV-14); swallow-to-SUCCESS hides degrade (INV-15).
- **After:** every hook normalized to the same guard pattern (add guards to Hardware/Regional, D-9) or, better, structural idempotency (compute from immutable inputs so first-click == second-click); no-match paths write a `*_Warning__c` surface instead of silently resetting to list (D-17/D-18). Gap closed: INV-11, INV-14, INV-15.

### 5.6 Principle: bulk-safe service/invocable/batch layer
- **Before:** Order-side invocables have DML-in-loop / per-request fan-out (INV-12); Power split already mitigated (INV-13).
- **After:** accumulate patches across orders → one DML; keep `OrderRepriceInvocable` one-order-per-call or batch across requests. Gap closed: INV-12 (Wave 4).

### 5.7 Principle: explicit null-safety with documented defaults
- **Before:** the SC-3393 `>0`-on-null defect lives in the **ESD** `RegionalNetReconcileGate` step, not Apex (INV-28, CG-24); StampBaseFilter null-safety is per-version (INV-26).
- **After:** every filter predicate is null-safe with a documented default (list price, not `$0` or throw); the fix is applied to **all instances on the exact active version** (count first). Gap closed: INV-26, INV-28 (Wave 4, ESD).

**Current→target gap list (maps 1:1 to waves):** INV-4/9/10/20/21 → W1 · INV-30/3/31 → W0/W2 · INV-29/17 → W2 · INV-5/6/7/8 → W3 · INV-11/12/14/15/22/23/24/26/28/19 → W4.

---

## 6. Duplication / Dead-Code Consolidation Map

One row per cluster/orphan, with **runtime-binding proof** and a **strangler-fig parallel-run gate** that must pass before any retirement. No class is retired without a proof step; LKG is never folded in.

| Cluster | Members (live ln) | Canonical (keep) | Redundant | Binding proof | Tactic | Parallel-run gate | INV |
|---|---|---|---|---|---|---|---|
| **Partner V1/V2 prehook** | `PartnerPricingPrehookV2` (1134) · `PartnerPricingPrehook` (1646) | V2 | **V1 prehook (DEAD)** | `procedure_plan_options.txt:7` → V2 `01pWC000002TL37YAG`; V1 in no option/flow/trigger | **DELETE V1 prehook + test** (after grep-proof no test/flow refs) | reprice full matrix pre/post-delete → 0 delta | INV-4 |
| **Partner services** | `PartnerPricingServiceV2` (209) · `PartnerPricingService` (449) | **BOTH live** | — | posthook calls V1 ×14 (`PartnerNetPricePosthook.cls:146…`); prehook calls V2 | **UNIFY into one `PartnerMarginService`** (governance: settle the split) — do NOT delete V1 | compute margin via old V1+V2 vs new unified, side-by-side, equal per line across matrix | INV-5 |
| **E-04 null-Non_Orig** | `PartnerPricingServiceV2.getMarginForProductType` :114-155 | — | — | `:123` `useNonOriginating`; 0-on-null :127-149 | **GOVERNANCE flip-or-fix**: null→catalog fallback vs 0; + data-completeness audit of `Non_Orig_*` | reprice Fortra-Originated scenarios w/ null vs populated `Non_Orig_*` | INV-6 |
| **COLA dual-path** | `COLAUpliftPrehook` (1468) · `COLAUpliftHandler` (495) | **both entry points** | duplicated 3-tier logic | prehook `procedure_plan_options.txt:10`; handler `QuoteLineItemTrigger.trigger:30,34` | **EXTRACT-SHARED-SERVICE** `ColaUpliftEngine`; keep both surfaces | reprice + trigger-path (QLI insert/update) produce identical COLA fields old vs new | INV-7 |
| **Currency-change** | `QuoteCurrencyChangeService` (102, WIRED no-op) · `_Fixed` (130, orphan converter) | (decide) | `_Fixed` OR the no-op | flow `Quote_Handle_Quote_Currency_Change.flow-meta.xml:8` → non-`_Fixed` | **DESIGN CALL then delete/flip** (OQ-2) — do not leave both | reprice a currency-change scenario; assert intended behavior before retiring either | INV-8 |
| **SourceListPrice** | `SourceListPricePrehook` (16) · `SourceListPriceResolver` (23) | `Stamp_Source_List_Price` flow | both stubs | absent from `procedure_plan_options.txt`; bodies return "disabled" | **DELETE both + tests** | reprice derived-maint scenario pre/post-delete → 0 delta | INV-9 |
| **RenewalMaintenanceFlip** | `RenewalMaintenanceFlip` (105) | AutoAdd path | the flip | zero refs in force-app (grep) | **DELETE-after-confirm** (OQ-3: flip strategy abandoned?) | confirm `RenewalMaintenanceAutoAddHandler`/`…PricingService` fully own renewal-maint | INV-10 |
| **ESD versions** | 22 versions | V21 active (V20 backup) | 20 dormant | `esd_versions.txt`; two bindings pin the *procedure* | **CONCEPTUAL retire only** — collapse content forward in-place; NEVER delete a version (§2b) | n/a (no deletion) | INV-18 |
| **Intra-V21 clones** | 16 dup-label groups, Copy-of-Copy triad, 28-ListContainer sprawl | one canonical per function | the twins | `ACTIVE_V21_steps.tsv` | **In-place canvas consolidation** (behavioral, Wave 4) — merge by label+function, never by `<name>` | full matrix 0 delta after each merge | INV-19 |
| **(BOUNDARY) LKG** | 174 `Lkg*` classes | n/a | n/a | `LkgAutomatePointsBuilderFactory` | **OUT OF SCOPE — map only; do NOT fold in; `Legacy`=LT11 is LIVE** | n/a | BC-17 |

**Look-alikes that are NOT in scope (do not touch):** the LKG tier-builder family; the PBE tooling (`Fortra_BulkPriceUpdateBatch`, `UpdatePricebookEntriesInvocable`, `PricebookEntryCascadeDeleter`, `AttributeLoadingService`/`Batch`); the discovery procedures; the config MDTs themselves.

---

## 7. Waterfall Documentation Artifact *(Priority-B centerpiece)*

The true runtime order, stitched across **ProcedurePlan prehooks → ESD steps → posthooks**, as a **machine-diffable fixed-column table** so future PRs diff by **label + function, never by `<name>`** (INV-19: `<name>` is non-unique). Full 18-row table with per-step reads/writes is in `lanes/lane3-waterfall.md`; the load-bearing skeleton + named invariants are below. **Every load-bearing order edge has a named invariant** — this converts a silent reorder into a gated, visible, behavioral change.

```
label                              | layer        | seq  | invariant
HardwareAttributePricingPrehook    | ProcedurePlan| 1    | INV-HW-FIRST
RegionalServicesPricingPrehook     | ProcedurePlan| 2    | INV-REG-BEFORE-PARTNER
PartnerPricingPrehookV2            | ProcedurePlan| 3    | INV-PARTNER-V2-LIVE
AttributeVolumePricingPrehook      | ProcedurePlan| 4    | INV-ATTRVOL-STAGES-BASE
COLAUpliftPrehook                  | ProcedurePlan| 6    | INV-COLA-PRODUCER
ESD ▸ list → attr/vol → regional bridge → partner staging → derived-maint → COLA bridge → manual → proration → aggregation → FX | ESD | 10 | INV-ESD-* (below)
PartnerNetPricePosthook            | posthook     | 11   | INV-POSTHOOK-AFTER-ONETIME-SEED
QLDescriptionGeneratorPrehook      | posthook*    | 12   | INV-DESCGEN-RUNS-LAST-BUT-ONE
CancelLineCreditPosthook           | posthook     | 13   | INV-CANCEL-WRITES-SAVEMAPPED
```

**Named load-bearing invariants (each CONFIRMED this run):**
- **INV-HW-FIRST** — Hardware multiplies the raw list-price base, so it must precede Regional/Partner or the multiplier compounds onto a discounted number. (`plan_sections.txt` seq1.)
- **INV-REG-BEFORE-PARTNER** — Regional stages `RegionalNetUnitPrice__c`(Order)/`PrehookRSNetUnitPrice__c`(Quote) that Partner reads as its pre-partner base (`PartnerPricingPrehookV2.cls:653,785`). *Hazard:* the two field names are object-asymmetric (INV-17) — a unifying refactor must keep both mappings.
- **INV-PARTNER-V2-LIVE** — **CORRECTED**: `PartnerPricingPrehookV2` is the runtime partner prehook (`procedure_plan_options.txt`, 2026-07-01); V1 + `SourceListPricePrehook` are dead/unwired.
- **INV-COLA-PRODUCER / INV-ESD-COLA-CONSUMER** — `COLAUpliftPrehook` is the *sole* producer of `COLACalculatedPrice__c`; the ESD COLA bridge (ESD container seq-23) and the posthook (reads ×15) are pure consumers — producer-before-consumer.
- **INV-POSTHOOK-AFTER-ONETIME-SEED** — the ESD `SeedOneTimeNetBeforePartner` group (`OneTimeNetSeedFilter`) recomputes NetUnitPrice-from-ListPrice for OneTime/Perpetual lines; a *prehook* partner-net write would be clobbered, so `PartnerNetPricePosthook` **must be a posthook** (seq-11) re-asserting the final net (`PartnerNetPricePosthook.cls:396,1032,1147,2069,2128,2383`).
- **INV-DESCGEN-RUNS-LAST-BUT-ONE** — `QLDescriptionGeneratorPrehook` runs seq-12 (after procedure + posthook) despite the "Prehook" name; it reads final priced quantities.
- **INV-CANCEL-WRITES-SAVEMAPPED** — `CancelLineCreditPosthook` must write `NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal/TotalLineAmount` (save-mapped), never the internal `Item*` tags (`CancelLineCreditPosthook.cls:30-32`).
- **INV-ESD internal order (CORRECTS the pedagogical family order):** inside the ESD the true container order is list → attr/volume → **regional bridge (seq-11)** → partner staging/discount (seq-13-21) → derived-maint (seq-15/16/22) → **COLA bridge (seq-23)** → manual/contracted (seq-20/24) → **subscription/proration (seq-25-31, AFTER partner+COLA+manual)** → aggregation (zero-init seq-32-34 *before* aggregates seq-35-37) → **FX conversion LAST (seq-38-41)**. Named sub-invariants: **INV-ESD-STAMPBASE-NULLGUARD** (StampBaseFilter must null-guard before partner discount, else EUR-derived $0 — D-19), **INV-ESD-ZEROINIT-BEFORE-AGG** (K-09 stale-rollup fix), **INV-ESD-FX-LAST** (all math is USD-base until the terminal FX family — avoids double-FX / J-10), **INV-ESD-DERIVED-3TIER** (V21 derived formula delegates tiering to a decision table — INV-25, UNVERIFIED at formula body).
- **INV-ESD-FILTER-POSITIONAL** (higher-risk-edit flag, D-20) — `AdvancedListFilter` criteria are referenced by **positional `<sequenceNumber>` (1..N reset per block)** wired through `<conditionLogic>` strings (32 blocks, 82 criteria in the active version; e.g. block @360 `1 AND 2 AND 3`). Removing/reordering any criterion renumbers survivors and silently changes semantics. **Any PR touching a filter's criteria set is HIGHER-RISK and must re-verify `<conditionLogic>` by hand.**

**"Good looks like":** every edge above has a named invariant, and the table is diffable by label+function — so a future resequencing PR must show a delta against this artifact and re-run §9. That is the whole Priority-B win: order changes become gated and visible instead of silent.

---

## 8. Risk-Ranked Migration Waves (behavior-preserving first)

Every candidate change is classified **SAFE-NON-BEHAVIORAL** vs **BEHAVIORAL**; the two never share a wave. **Every wave's exit gate: zero golden delta (or an explicitly documented, owner-approved intended delta) + unchanged governor/CPU counts + unchanged boundary-MDT reads.** A wave cannot start until the prior gate is green.

### Wave 0 — Inventory + characterization tests + docs (NO code) — *gates everything*
- **Do:** re-retrieve live (§2a) and **re-baseline the golden matrix against current live state — do NOT trust any recorded run counts as the oracle** (INV-31; the `Data/pricing-v21-validation` harness does not exist — build it, §9). Publish the §7 waterfall artifact. Snapshot the §3f boundary contracts as assertions. Land characterization tests via the `@TestVisible` seams + `PricingPrehookTestFixtures` (INV-30) — tests land FIRST (prevents §10.1 #8).
- **Class:** SAFE (no runtime change).
- **Entry gate:** live retrieve timestamped; active version + top-risk classes re-verified. **Exit gate:** the matrix reprices a Quote AND an Order and reproduces current live `NetUnitPrice/TotalPrice/PricingTermCount/From-To dates/Workday line-type/Asset count` for every scenario (the oracle is now trustworthy).
- **Closes:** D-5, D-6, D-22 (docs/harness). **INV:** INV-3, INV-30, INV-31.

### Wave 1 — Safe non-behavioral cleanup
- **Do:** delete provably-unwired dead code after reference/parallel-run proof — **D-1** (V1 partner prehook), **D-2** (`SourceListPrice*`), **D-3** (`RenewalMaintenanceFlip`, pending OQ-3); **quarantine D-4** (`scratch_v210.xml`) and **D-7** (label/git-ignore the repo ESD `.xml`+`.bak_preedit` as non-authoritative). Renames/docs only otherwise. **`QuoteCurrencyChangeService_Fixed` delete waits on the OQ-2 design call** (may become a Wave-3 flip instead).
- **Class:** SAFE-NON-BEHAVIORAL (zero behavior change by construction).
- **Exit gate:** full matrix 0 delta before/after each deletion; grep-proof of no remaining references.
- **Closes:** D-1, D-2, D-3, D-4, D-7. **INV:** INV-4, INV-9, INV-10, INV-20, INV-21.

### Wave 2 — Hook-thinning (extract, identical behavior)
- **Do:** extract `execute()` decision logic into pure services (`PartnerMarginEngine`, `ColaUpliftEngine`, `HardwarePricingCalculator`, …) behind **unchanged behavior** (§5.1/5.2); re-seam characterization tests in lockstep (prevents §10.1 #8); dedupe the MDT loaders (D-8) into one selector.
- **Class:** SAFE-NON-BEHAVIORAL (extract-method with identical output) — but gated because "identical output" must be *proven*.
- **Exit gate:** full matrix 0 delta + per-hook parallel-run (old `execute` vs new adapter+service) equal.
- **Closes:** D-8, D-22 (testability). **INV:** INV-29, INV-30, INV-17 (prep).

### Wave 3 — Duplicate consolidation via parallel-run
- **Do:** one survivor per concern — **unify the two partner margin services (D-11)** into one `PartnerMarginService` both prehook and posthook call; **settle E-04 (D-12)** with the OQ-1 null→catalog decision; **extract one `ColaUpliftEngine` (D-13)** both COLA surfaces delegate to; **resolve the currency-change design (D-10)** and delete-or-flip. Retire losers only after equivalence proven.
- **Class:** BEHAVIORAL — strangler-fig: run retiring + surviving side-by-side, assert equality across the full matrix before retirement.
- **Exit gate:** parallel-run equivalence per §6 gates; then 0 delta on the survivor alone; any intended delta (e.g. E-04 fix) documented + owner-approved and tracked as an *intended* change, not a regression.
- **Closes:** D-10, D-11, D-13; sets up D-12. **INV:** INV-5, INV-6, INV-7, INV-8.

### Wave 4 — Hardening
- **Do:** normalize recursion guards (add to Hardware/Regional, **D-9**); null-safety on all active-version filter predicates counting instances first (**D-19**, the K-01/SC-3441 lesson) and the ESD `RegionalNetReconcileGate` (**INV-28**); bulkify Order-side invocables (**D-16**); config-drive the Hardware/Currency hardcodes behind new owner-approved MDTs (**D-14, D-15**, OQ-4/5); surface no-match/degrade instead of swallowing (**D-17, D-18**); intra-version ESD clone consolidation in-place by label+function (**D-23**); evaluate the currency config-as-code (**D-21**, OQ-6). Every ESD edit classified formula-literal (no resync) vs field-signature (resync + dual-object, §2c).
- **Class:** BEHAVIORAL — each item independently parallel-run-gated; ESD edits in-place on V21 only (§2b).
- **Exit gate:** 0 golden delta (or documented intended delta) + **unchanged SOQL/CPU counts on 15+-line and high-qty Power scenarios** + unchanged boundary-MDT reads + reprice-idempotency (first==second click).
- **Closes:** D-9, D-14, D-15, D-16, D-17, D-18, D-19, D-20, D-21, D-23. **INV:** INV-11, INV-12, INV-14, INV-15, INV-19, INV-22, INV-23, INV-24, INV-26, INV-27, INV-28.

**"Good looks like":** each wave states exactly what proves it safe to proceed (its exit gate), and no behavioral change ever hides inside a cleanup wave.

---

## 9. Verification / Golden-Scenario Test Strategy *(design only; do NOT execute)*

The only trustworthy behavioral check is **reprice-and-diff**; static reasoning is necessary but never sufficient, and **unit tests alone are not a valid oracle** (SC-3346 passed against stale list-API context while live pricing broke). This section hands off a ready-made acceptance gate.

- **Existing harness — CONFIRMED ABSENT (INV-31).** `Data/pricing-v21-validation` does **not** exist anywhere in the repo (searched this run). The recorded "run3 2026-06-30: 69 pass / 13 fail / 22 blocked" figures cannot be located and are **not** to be trusted as the oracle. **Specify the matrix from scratch and re-baseline against current live state** before Wave 0 relies on it. (`COLAUpliftTest` (109,787 chars) is the largest characterization surface that *does* exist — reuse its fixtures.)
- **Golden pricing-scenario matrix (primary oracle).** Dimensions: new vs renewal; one-time / subscription / perpetual / maintenance (new + renewal-derived); partner net (Discount + Guaranteed-Margin, **incl. Fortra-Originated with populated AND null `Non_Orig_*`** — INV-6); regional / multicurrency; tiered / volume; hardware / Power (incl. high-qty for CPU, INV-13). Snapshot per scenario: **`NetUnitPrice`, `TotalPrice`, `PricingTermCount`, From/To dates, Workday line-type, Asset count.**
- **Reprice BOTH a Quote and an Order** through the managed runtime (`POST /connect/rev/sales-transaction/actions/place`) — never direct DML (RLM lock, §2c). The dual-object failure is the #1 silent regression (INV-17).
- **Parallel-run equivalence** for every duplicate consolidation (Wave 3): compute retiring + surviving side-by-side across the full matrix; assert equality before retirement (D-11, D-13, D-10).
- **Idempotency:** reprice each scenario twice; assert first-click == second-click (guards SC-3390 / INV-14).
- **Null-path scenarios explicit:** null `NetUnitPrice` (cancel/amend-remove), null US-line net, missing optional context fields, null `PricingTermCount`, null `Non_Orig_*` → documented defaults, not `$0` or throws (guards SC-3393/SC-3441/K-01/F-12 / INV-6, INV-26, INV-28).
- **Governor/perf assertions:** SOQL + CPU counts on 15+-line and high-qty Power scenarios must not regress (guards SC-3366/SC-3447 / INV-12, INV-13).
- **Downstream proxies unchanged:** Workday line-type stamping, Assetize Asset count on activation, Order-activation term fields (EndDate/PTC — the engine-only `PricingTermCount` has no Apex backstop, INV-17).
- **Boundary contract tests:** assert hooks still read the same `COLA_Uplift_Rules__mdt` / `Maintenance_Rate__mdt` / `Services_Regional_Pricing__mdt` / `Currency_Conversion_Formula__mdt` / `Attribute_Tier_Pricing_Storage__c` values after refactor (proves the §3f seam undisturbed).
- **Platform reality shaping this:** `execute()` is not directly unit-testable (INV-30) → the net is **`@TestVisible` seam tests (`PricingPrehookTestFixtures`) + headless Force-reprice over the fixed matrix — NOT raw code-coverage %.** The characterization + golden tests captured at plan time are declared **the acceptance gate for the eventual execution phase.**
- **Fortra truth (scope, not blockers):** no evergreen catalog and no contracted pricing exist → those scenarios are **N/A by design, not "blocked"** — track them out of the matrix, not as failures.

---

## 10. Risk Register + Rollback Notes

### 10.1 Prior regressions (the safety spine) — each mapped to its owning wave
1. **Step-deletion silently breaks a line-class** (TermDefined Proration → null `PricingTermCount` → SC-3406/3411/3415; engine-only field, no backstop). → §9 characterizes every line-class before/after any step change; **Wave 4** ESD edits gated on it; INV-17.
2. **Version "merge" silently drops deltas** (V20 activation dropped proration sub-tree, 7→3 tier, two `IsNotNull` guards). → Diff by **label+function, never `<name>`** (INV-19); §7 artifact makes merges visible; **Wave 4**.
3. **Performance edit deletes correctness check** (Workday line-type V9 always-true self-compare). → **Wave 4** bulkifies without deleting checks; §9 governor assertions; INV-12.
4. **Inline rate constants drift/hide gaps** (`DerivedPricingFormula` 3-of-7 tiers → $0 on 1,031+ rows; in-place fix oscillated). → **Wave 4** config-drives hardcodes (D-14/15); note the derived tiering is ESD-formula/decision-table, not Apex (INV-25); INV-22/23.
5. **In-place edit without context resync = org-wide outage** (`Prior_*_Discount__c` / `Pre_Partner_Price__c` on the wrong object). → §2c classifies every change formula-literal vs field-signature; **Wave 2/3/4** dual-object + dual-mapping discipline; INV-17.
6. **Silent reset-to-list / non-idempotency** (SC-3390 two-click). → **Wave 4** surfaces no-match (D-17/18); §9 idempotency test; INV-14.
7. **Null-unsafe filter predicates** (K-01/SC-3441/F-12; 3-of-6 StampBaseFilter). → **Wave 4** counts instances on the active version first (1 in V21 today, INV-26); §9 null-path scenarios; INV-26, INV-28.
8. **Refactor a hook, orphan its test** (SC-3346 `COLAUpliftTest` 41 compile errors). → **Wave 0** lands characterization tests FIRST; **Wave 2** re-seams in lockstep; INV-30.
9. **One in-place edit regresses an unrelated combo** (F-09 double-FX partner net). → §9 full golden re-validation on **every** in-place pricing edit; INV-24, INV-ESD-FX-LAST.

### 10.2 Platform + design risks (likelihood × impact → mitigation → owning wave → §10.1 map)

| ID | Risk | L×I | Mitigation | Wave | §10.1 |
|---|---|---|---|---|---|
| R-1 | Cannot delete any ESVersion (HTTP-500) | H×H | Never delete; consolidate conceptually; keep both bindings | §6/W1 | #2 |
| R-2 | In-place edit clobber / canvas re-save revert (7-min-later) | M×H | Reactivation hygiene: close tabs, fresh tab, Activate from Versions, immediately re-retrieve | W4 | #5 |
| R-3 | Pricing-offline activation window (0 active = org-wide down) | M×H | Keep V20 Inactive as live backup; short window; never "Reactivate All Dependencies" | W4 | #2 |
| R-4 | Context-fetch dual-object/dual-mapping coupling | M×H | Field-signature change = dual-object + dual-mapping + resync; reprice both Quote+Order | W2/3/4 | #5,#1 |
| R-5 | MDAPI ≠ runtime | M×H | Canvas is source of truth; flag any MDAPI-edit step unsafe | W4 | #2 |
| R-6 | Retrieve-live drift (co-owned minute-to-minute) | H×M | Freshness protocol §10.4 before every wave; UNVERIFIED tag blocks gate | all | #5 |
| R-7 | Co-owned version oscillation (in-place fix ping-pong) | M×M | Coordinate a change window (OQ-7); one owner per in-place edit | W3/4 | #4 |
| R-8 | Second-reprice non-idempotency | M×M | Structural idempotency; §9 first==second-click test | W4 | #6 |
| R-9 | RLM DML lock (Quote/OrderItem) | H×M | Verification is managed reprice only; never DML | §9 | #5 |
| R-10 | Stripping load-bearing wiring (bindings/PSLs/ProcedurePlanOptions) | L×H | §2e forbids; the 2 bindings + 9 options are named untouchables | all | — |
| R-11 | Partner-service split ships inconsistent net during transition | M×H | Wave-3 parallel-run equivalence before retiring V1 service; keep V1 until unified | W3 | J-06 |
| R-12 | `scratch_v210.xml` mistaken for deployable V21 (regression if deployed) | M×H | Wave-1 quarantine/delete; it is a V20-lineage hybrid (INV-20) | W1 | #2 |

### 10.3 Rollback notes (future human-authorized execution)
- **Primary rollback lever = the V20 live-backup** (Inactive, clean-labelled, closest sibling to V21 — VR-3). "Restore V20" = activate V20, deactivate V21, from the Versions list (never "Reactivate All Dependencies").
- **Discipline = deactivate→deploy→reactivate-from-Versions** with the R-2 reactivation hygiene, accepting the R-3 offline window (kept short; V20 backup available). All framed as future human-authorized work — not performed here.
- **Apex rollback** is ordinary metadata redeploy (force-app currently matches live, INV-30) — but re-retrieve first (R-6).

### 10.4 Freshness protocol result (this run)
Re-verified at **2026-07-06T20:03:50Z** (~24 min after the initial 19:40Z retrieve): active version still **V21** (`9QBWC0000000oWH4AY`, unchanged 2026-07-03), partner binding still **`PartnerPricingPrehookV2`** (unchanged 2026-07-01), and all 7 top-risk class bodies (`PartnerNetPricePosthook`, both partner prehooks, both partner services, `COLAUpliftPrehook`, `COLAUpliftHandler`) identical `LengthWithoutComments` + `LastModifiedDate`. **Zero delta — all findings current; no re-tagging.** (`RETRIEVAL_LOG.txt`.)

---

## 11. Open Questions for Humans

Each has a **named owner-role** and the decision it unblocks. (Owner *people* inferred from live `LastModifiedBy`: Nir Kailash owns most partner/currency/decomposition classes; Liam Jeong owns COLA/posthook/cancel/renewal; Marc DeBrey owns hardware/regional/currency-selection; Ben Kozlowski wrote `PartnerPricingServiceV2` — confirm ownership before assigning.)

| # | Question | Owner-role | Unblocks |
|---|---|---|---|
| OQ-1 | **E-04:** is "Fortra Originated ⇒ read `Non_Orig_*` percentages" intentional, and should null map to 0% or to catalog list? And is `Non_Orig_*` populated on `Partner_Pricing_Model__c` in UAT+prod today? (INV-6) | Partner-pricing owner (Nir/Ben) + Sales-Ops data owner | D-12 fix + whether the live V2 path is silently zeroing margins now |
| OQ-2 | **Currency-change:** is the intended behavior the no-op clone (wired `QuoteCurrencyChangeService`) or the real PBE reconversion (orphan `_Fixed`)? (INV-8) | Pricing owner (Marc/Joe) | D-10 delete-vs-flip |
| OQ-3 | **Renewal maintenance:** is `RenewalMaintenanceFlip`'s flip strategy abandoned in favor of `RenewalMaintenanceAutoAddHandler`/`…PricingService`? (INV-10) | Renewal owner (Liam) | D-3 delete |
| OQ-4 | **Hardware config:** approve a net-new `Hardware_Attribute_Pricing__mdt` for the pGroup/user-tier/system-type tables now inline? (INV-22) | Pricing config owner + Rev Cloud admin | D-14 |
| OQ-5 | **Currency-selection config:** approve a `Country_Currency__mdt` (or reuse `Services_Regional_Pricing__mdt.Country_Code__c`) to replace the inline 14-country map? (INV-23) | Pricing config owner | D-15 |
| OQ-6 | **Currency config-as-code:** keep `Currency_Conversion_Formula__mdt` executable-string formulas or move to pure `Conversion_Rate__c` decimals? (INV-24) | Pricing/Finance config owner | D-21 (boundary — map-only unless approved) |
| OQ-7 | **Co-owned change window:** who coordinates the in-place V21 canvas edits so Wave-3/4 changes don't oscillate (R-7)? | Pricing-procedure admin (Liam/Nir) | any Wave-4 ESD edit |
| OQ-8 | **Term-Defined proration in V21:** the active `<description>` claims "+COLA proration" yet the `Term-Defined proration filter (Line level)` label is absent in V21 (present in V20). Is it now folded into the single `Proration` BKM step, or a residual COLA regression? (VR-4) | Pricing lead (Nir) | confidence that V21 didn't drop TermDefined proration (§10.1 #1) |
| OQ-9 | **ESD file authority:** should the repo `expressionSetDefinition/*.xml` + `.bak_preedit` be git-ignored/header-flagged as non-authoritative (canvas is truth)? (INV-21) | Pricing engineer (Liam) | D-7 |
| OQ-10 | **`scratch_v210.xml`:** delete or clearly quarantine from repo root so it's never mistaken for deployable V21 (it is a V20-lineage hybrid — regression if deployed)? (INV-20) | Pricing engineer (Liam) | D-4 |
| OQ-11 | **SC-3393 ESD gate:** confirm the un-null-guarded `>0` `RegionalNetReconcileGate` step still exists on active V21 and schedule its null-guard (it is ESD, not Apex — INV-28). | Pricing lead (Nir) | D-19 scope |
| OQ-12 | **Ticket number** for this refactor effort (none derivable read-only → evidence under `Data/pricing-refactor-scratch/`, no `Data/sc<ticket>/` mirror made). | Program owner | evidence-folder placement + optional plan mirror |

*Any out-of-scope root cause hit under the §2 stop rule is recorded here (OQ-1 data, OQ-6 config, OQ-11 ESD) rather than expanded — none triggered enumeration of an out-of-scope subsystem.*

---

### Appendix — Evidence index (all under `Data/pricing-refactor-scratch/`)
- `RETRIEVAL_LOG.txt` — timestamped retrieval + freshness log.
- `soql/` — `esd_versions.txt` (22 versions), `pricing_action_parameters.txt` (2 bindings), `procedure_plan_options.txt` (9 hooks), `plan_sections.txt` (runtime sequence), `plan_definition*.txt`, `apexclass_meta.json` (33-class metadata).
- `live-classes/*.cls` — 32 authoritative live bodies (force-app matches this run).
- `live-esd/` — `unpackaged/…/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` (live, all 22 versions), `ACTIVE_V21_block.xml` (extracted active version), `ACTIVE_V21_steps.tsv` (128 steps).
- `diffs/` — `esd_live_vs_repo.diff` (cosmetic-only), `class_drift.csv` (32× MATCH).
- `lanes/` — `lane1-callgraph.md`, `lane2-duplication.md`, `lane3-waterfall.md`, `lane4-versions.md`, `lane5-boundary.md`, `orchestrator-crosschecks.md`.

*End of plan. This document is read-only analysis; it authorizes no change to FortraUAT.*
