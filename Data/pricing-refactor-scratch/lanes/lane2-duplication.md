# Lane 2 — Duplication / Dead-Code Census (with runtime-binding proof)

Retrieval basis: SHARED GROUND TRUTH, live retrieval 2026-07-06. Read-only. All citations point at
`Data/pricing-refactor-scratch/live-classes/<Name>.cls:<line>`, `soql/<file>`, or `force-app/...`.
Runtime binding = ProcedurePlanSection/Option row or a flow `actionName` / trigger call — NOT source presence.

Line counts below are from `wc -l` on the live-class bodies (differ by 1 from the ground-truth header,
which counted without trailing newline; noted where relevant).

---

## DC-1 — Partner V1 vs V2 FULL STACK  (INVERTED from prior docs — V2 is LIVE)

### Members & live line counts
| Class | Lines | Role |
|---|---|---|
| `PartnerPricingPrehookV2` | 1133 | **LIVE prehook** (seq3) |
| `PartnerPricingServiceV2` | 208 | **LIVE service** — used by V2 prehook |
| `PartnerPricingPrehook` (V1) | 1645 | **DEAD prehook** — unwired |
| `PartnerPricingService` (V1) | 448 | **STILL LIVE service** — used by the posthook (see below) |
| `PartnerNetPricePosthook` | 2562 | LIVE posthook (seq11) — consumes V1 service |

### BINDING PROOF (CONFIRMED)
- `soql/procedure_plan_options.txt:7` — Partner section `ProcedurePlanSectionId 1FRWC0000000a0J4AQ`
  (`plan_sections.txt:7`, Sequence 3, subsection `PreHookPartnerPricing`) binds
  `ProcedurePlanOption 1FYWC0000002W3r4AE → APEXCLASSNAME PartnerPricingPrehookV2 (01pWC000002TL37YAG)`,
  LastModified `2026-07-01T01:53:44Z`. **=> V2 is the runtime partner prehook.**
- `PartnerPricingPrehook` (V1) appears in NO ProcedurePlanOption row (only 9 options exist; none name it).
  **=> V1 prehook is DEAD.** No flow/trigger references it either (grep force-app: only self + `PartnerPricingPrehookTest`).

### Which service does each prehook call?  (CONFIRMED)
- V2 prehook calls **`PartnerPricingServiceV2`** exclusively:
  `PartnerPricingPrehookV2.cls:384` (`getPricingModelCandidates`), `:708/:735` (`selectBestModelForLine`),
  `:715/:742` (`getMarginForProductType`), `:720` (`calculateDiscountPrice`), `:760` (`calculateGuaranteedMarginPrice`).
- V1 prehook (dead) calls **`PartnerPricingService`** (V1): `PartnerPricingPrehook.cls:390,455,457,632,693,777,1146,1152`.

### Is `PartnerPricingService` (V1) still live via the posthook?  **YES — CONFIRMED.**
`PartnerNetPricePosthook` (the LIVE seq11 posthook) calls the V1 service in 14 places:
`PartnerNetPricePosthook.cls:146` (`getPricingModels`), `:159/:161` (`ensureProductTypesLoaded`/`loadProductTypesForTransactionLines`),
`:319,:545,:1112,:2251` (`resolveProductType`), `:569,:581,:1560` (`getMarginForProductType`),
`:574` (`calculateDiscountPrice`), `:591` (`calculateGuaranteedMarginPrice`), `:1480,:1527` (`getPricingModels`).
**=> V1 service CANNOT be deleted.** Only the V1 *prehook* is dead. This is a split verdict: dead class + live service in the same "V1 stack."

### Signature divergence (latent hazard, CONFIRMED)
Two parallel `getMarginForProductType` live simultaneously with different contracts:
- V2: `getMarginForProductType(model, productType, dealType)` — `PartnerPricingServiceV2.cls:114`, Non_Orig-aware.
- V1: `getMarginForProductType(model, productType)` — `PartnerPricingService.cls:253`, 2-arg, **no dealType / no Non_Orig branch.**
The prehook (V2) and posthook (V1) therefore compute partner margin from DIFFERENT field sets on the same line — a real drift source for partner-priced maintenance (matches memory note J-06: posthook `computeNewBusinessMaintenanceNets` is the real lever).

### E-04 blocker assessment (getMarginForProductType returns 0% on null Non_Orig) — **STILL LATENT ON THE RUNTIME PATH.**
`PartnerPricingServiceV2.cls:123` sets `useNonOriginating = (dealType == 'Fortra Originated')`. When true, every branch
reads `Non_Orig_*_Pct__c` and **defaults to 0 when null** (`:127-149`). So a **Fortra-Originated deal whose
partner model leaves `Non_Orig_*_Pct__c` null yields margin 0% → no partner adjustment silently applied.**
Because DC-1 proves V2 is now the LIVE prehook, this 0%-on-null path is on the runtime surface today (CONFIRMED latent; not merely staged as prior docs assumed). Note the naming inversion is itself suspect (`useNonOriginating` is true for "Fortra Originated") — flag for the owner, but code behavior is as stated.

### Consolidation tactic / verdict
- **DELETE** `PartnerPricingPrehook` (V1, 1645 ln) + its test — dead, no binding.
- **KEEP** `PartnerPricingService` (V1, 448 ln) — load-bearing for the posthook. Do NOT delete.
- **EXTRACT/UNIFY** the two `getMarginForProductType` + calc helpers into one service so prehook and posthook
  share one margin contract (kills the V1/V2 signature drift and centralises the E-04 null-guard fix).
- **FLIP verdict on E-04**: add null→catalog fallback (or a warning) in the unified `getMarginForProductType`;
  do not treat null Non_Orig as 0 on Fortra-Originated deals. (In-scope fix, but a business-rule confirmation
  on the "Fortra Originated ⇒ Non_Orig" mapping is an OPEN QUESTION for the pricing owner — do not guess.)

---

## DC-2 — COLA dual-path: `COLAUpliftHandler` (QLI trigger) vs `COLAUpliftPrehook` (RCA prehook)

### Members & live line counts
| Class | Lines | Surface |
|---|---|---|
| `COLAUpliftPrehook` | 1467 | RCA prehook (seq6) |
| `COLAUpliftHandler` | 494 | QuoteLineItem trigger handler |

### BINDING PROOF (both surfaces LIVE — CONFIRMED)
- Prehook: `soql/procedure_plan_options.txt:10` — `1FYWC0000002W3u4AE → COLAUpliftPrehook (01pWC000001wNGbYAM)`,
  section `1FRWC0000000a0M4AQ` Sequence 6 (`plan_sections.txt:9`).
- Handler: `force-app/main/default/triggers/QuoteLineItemTrigger.trigger:30` calls
  `COLAUpliftHandler.handleBeforeInsert(Trigger.new)` and `:34` `COLAUpliftHandler.handleBeforeUpdate(...)`.
  Also invoked from `COLAUpliftPrehook.cls`, `RenewalQuoteActionStamp.cls`, `RenewalForecastAmount.cls`,
  and flow `Fortra_Renewal_Quote_Creation.flow-meta.xml` (grep).
**=> This is NOT a dead twin — it is a genuine dual-write across two engines (trigger + RCA prehook).**

### 3-tier hierarchy — duplicated, only ONE helper shared (divergence risk CONFIRMED)
Both implement the identical **Line Override > Contract Override > CMDT lookup** hierarchy, and BOTH read
`COLA_Uplift_Rules__mdt` keyed by `Solution_Category__c`:
- Handler: `COLAUpliftHandler.cls:3` (doc "three-tier"), tier logic `:305/:314/:354`, CMDT map `getCOLARulesMap` `:375-397`.
- Prehook: `COLAUpliftPrehook.cls:386` (Tier1) `:390` (Tier2) `:395` (Tier3), CMDT map `:868-886`.
The ONLY shared code is `COLAUpliftHandler.isManualLineOverride(...)`, called from `COLAUpliftPrehook.cls:382`.
Everything else (tier resolution, CMDT read, price recompute) is re-implemented independently in each class
=> two copies of the rule hierarchy that can (and per memory `cola_v16_v20_reconcile` have) drift out of sync.

### Consolidation tactic / verdict
- **EXTRACT** a single `ColaUpliftEngine` service owning: CMDT rules map, 3-tier resolution, and percent→price math.
  Have BOTH the handler and the prehook delegate to it (the prehook already borrows `isManualLineOverride`, so a
  shared-service seam exists). **KEEP both entry points** (trigger vs RCA are different runtime moments); collapse
  only the duplicated logic. No delete.

---

## DC-3 — `QuoteCurrencyChangeService` (102 ln) vs `QuoteCurrencyChangeService_Fixed` (130 ln)

### BINDING PROOF (CONFIRMED)
- **`QuoteCurrencyChangeService` (V1) is the WIRED one**: flow `Quote_Handle_Quote_Currency_Change.flow-meta.xml:8`
  `<actionName>QuoteCurrencyChangeService</actionName>` (nameSegment `:32`).
- **`QuoteCurrencyChangeService_Fixed` is the ORPHAN clone** — referenced by NO flow/trigger/class
  (grep hits only `QuoteCurrencyChangeService_Fixed.cls` + its test). Confirms the prompt's hypothesis.

### Correctness inversion worth flagging (CONFIRMED, latent trap)
The WIRED V1 does **not** actually convert currency: it clones lines at the same `UnitPrice`
(`QuoteCurrencyChangeService.cls:35`, self-admitting comment `:37-38` "Actual price conversion would happen
through price book entries" — it never does) and does not update `Quote.CurrencyIsoCode`.
The ORPHAN `_Fixed` is the one that updates `Quote.CurrencyIsoCode` (`:19-20`) and re-prices from the
new-currency `PricebookEntry` (`:39-63`). So the "better" implementation is the one NOT wired — the org runs
the no-op version. (`_Fixed` has its own defect: deletes `oldLines` at `:49` then re-iterates that list at `:54`
to build `newLines` — works off the in-memory list but reads post-delete sObjects; would need review before wiring.)

### Verdict
- **DELETE** `QuoteCurrencyChangeService_Fixed` **only after** deciding the currency-change design. If the intended
  behavior is real reconversion, the correct move is the opposite: fix + wire `_Fixed`'s logic INTO the wired V1 and
  delete V1's no-op body. Flag to owner as an OPEN QUESTION (which behavior is intended) before any delete/flip.
  Whichever is chosen, one of the two must go — do not leave both.

---

## DC-4 — `SourceListPricePrehook` (16 ln) + `SourceListPriceResolver` (23 ln): inert no-ops

### CONFIRMED
- `SourceListPricePrehook.cls:8-15` — body is a stub: returns `SUCCESS` with message `'SourceListPricePrehook disabled'`;
  class doc `:3-6` "DISABLED: logic commented out ... maintenance pricing uses Stamp_Source_List_Price flow".
- `SourceListPriceResolver.cls:18-22` — `resolve(...)` immediately returns `skipReason='SourceListPriceResolver disabled'`,
  never sets `unitPrice`. Doc `:4-5` "DISABLED ... use Stamp_Source_List_Price flow instead."
- **Not wired**: `SourceListPricePrehook` is absent from `soql/procedure_plan_options.txt` (only 9 options; not among them).
- **Live path is the flow**: `force-app/main/default/flows/Stamp_Source_List_Price.flow-meta.xml` exists and owns the
  Source_List_Price stamping (contains NO apex actionName referencing either class — grep returned nothing => pure flow).

### Verdict
- **DELETE** both stubs + their tests (`SourceListPricePrehookTest`, `SourceListPriceResolverTest`) — inert, unwired,
  and self-documented as superseded by `Stamp_Source_List_Price`. Zero runtime risk. (Low priority; harmless if kept.)

---

## DC-5 — `RenewalMaintenanceFlip` (104 ln): orphaned invocable

### CONFIRMED
- `grep -rlin RenewalMaintenanceFlip force-app` (excluding its own `.cls`/`Test`) => **ZERO** references
  across classes/flows/triggers.
- It is an `@InvocableMethod` (`RenewalMaintenanceFlip.cls:41-45`, label "Renew Maintenance Carryover"),
  so it could only be bound by a flow `actionName`. Grep for the label / `flipInvocable` / class name in
  `force-app/main/default/flows` => **none**. **=> Not wired to any flow.**

### Verdict
- **DELETE-after-confirm**: no runtime binding. Caveat before pulling the trigger — the class doc (`:1-20`) says the
  proven SC-3346/SC-3404 renewal-maintenance fix "pairs with disabling the Year-2 AutoAdd PCR (14OWC0000022Eyb2AE)."
  Confirm the current renewal path (`RenewalMaintenanceAutoAddHandler` / `RenewalMaintenancePricingService`, both live)
  fully supersedes this flip approach before deleting. If superseded (likely, given it was never wired) → delete + test.
  OPEN QUESTION for renewal owner: is the flip strategy abandoned in favor of AutoAdd? Do not delete until answered.

---

## DC-6 — LKG: MAP-ONLY (out of pricing scope)

### CONFIRMED (family exists; NOT enumerated per stop-rule)
- Factory entry: `LkgAutomatePointsBuilderFactory` present in `force-app/main/default/classes` (Lkg* family = 358 files
  incl. tests by `ls | grep -ci lkg`).
- Tier builders present: `AutomateTierA/B/C/DPointsBuilder` + Legacy variants (`AutomateTierA/B/CLegacyPointsBuilder`),
  base `AutomatePointsBuilderBase`, context `AutomatePointsBuilderContext`, plus a parallel `Bpa*` tier family
  (`BpaTierALegacyPointsBuilder`, ...). One representative triad exists (Mapper/RecordCreator/RequestBuilder) — not listed.
- **Legacy = LT11 is LIVE, not dead** (Legacy tier builders are an active runtime tier, per ground truth).
- **OUT OF PRICING SCOPE.** No consolidation verdict; ~200+ classes deliberately not enumerated (stop-rule honored).

---

## Summary verdict table
| Finding | Canonical (keep) | Redundant | Verdict | Binding proof |
|---|---|---|---|---|
| DC-1 prehook | `PartnerPricingPrehookV2` | `PartnerPricingPrehook` (V1, 1645) | **DELETE V1 prehook** | procedure_plan_options.txt:7 |
| DC-1 service | both (`...ServiceV2` + `...Service` V1) | — | **KEEP both; unify margin API** | PartnerNetPricePosthook.cls:146+ |
| DC-1 E-04 | — | — | **FIX null-Non_Orig (now live via V2)** | PartnerPricingServiceV2.cls:123-149 |
| DC-2 COLA | both entry points | duplicated tier logic | **EXTRACT shared engine; no delete** | QuoteLineItemTrigger.trigger:30,34 |
| DC-3 currency | (decide) | `QuoteCurrencyChangeService_Fixed` orphan | **DELETE/flip after design call** | Quote_Handle_Quote_Currency_Change.flow:8 |
| DC-4 sourcelist | `Stamp_Source_List_Price` flow | both apex stubs | **DELETE stubs** | not in procedure_plan_options.txt |
| DC-5 flip | AutoAdd renewal path | `RenewalMaintenanceFlip` | **DELETE after confirm** | zero refs in force-app |
| DC-6 LKG | n/a | n/a | **OUT OF SCOPE, map-only** | LkgAutomatePointsBuilderFactory present |

### Cross-cutting open questions (owner-gated; do not resolve read-only)
1. E-04 semantics: is "Fortra Originated ⇒ read Non_Orig_* percentages" intentional, and should null map to 0 or to catalog? (pricing owner)
2. Currency-change: which behavior is intended (no-op clone vs real PBE reconversion)? Determines DC-3 delete vs flip. (pricing owner)
3. Renewal maintenance: is `RenewalMaintenanceFlip`'s flip strategy abandoned in favor of `RenewalMaintenanceAutoAddHandler`? (renewal owner)
