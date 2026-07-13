I have a complete picture. Here is my focused report.

---

# RENEWAL AUTOMATION TOPOLOGY — FortraUAT (code + data, read-only)

## 0. The one architectural fact that frames everything

Fortra runs **two competing, co-existing renewal engines** that were never reconciled — every band-aid below is an artifact of the seam between them:

- **Model A (legacy, "December 2024", Contract-Line-Item based):** the **`Fortra_Renewal_Quote_Creation`** screen flow (Renew button on Contract) copies `ContractLineItem`s to a new quote, and the **`COLAUpliftHandler`** trigger prices each line as `Asset.Price × (1 + COLA%)` at before-insert. Author: pre-existing / Marc DeBrey.
- **Model B (current, RCA/Asset based):** native `initiateRenewal` (overridden by **`Fortra_Create_Renewal_Quote`**) copies **Assets** into a quote as `QuoteAction`s, and pricing is committed inside the **pricing procedure + prehook/posthook context-stamping** path during **`Fortra_Quote_Reprice`**. Authors: Nir Kailash + Liam Jeong (Jun–Jul 2026).

Both are **Active** in the org simultaneously. The confirmed RNM→RRM $0 defect lives entirely in the seam: Model B copies the owned OneTime `RNM` asset as `QuoteAction='Amend'/'No Change'`, which never reaches a priced renewal node, so a stack of Apex hooks (below) was bolted on to force the COLA net back in.

---

## 1. Execution topology (Model B — the live renewal path)

```
Contract.Renew  ──►  native initiateRenewal  ──►  OVERRIDE: Fortra_Create_Renewal_Quote (flow, Active)
                                                     • resolves Asset→Order→Quote origin chain
                                                     • creates/reuses standing Renewal Opportunity
                                                     • calls native initiateRenewal action (NOT ContractAssetRenewalInvocable)
                                                     • stamps Fortra fields on new Quote
        │
        ▼  (Quote insert/update)
QuoteTrigger (before ins/upd)
        ├─ QuoteRenewalTypeHandler.applyRenewalQuoteType   → sets Quote_Type__c='Renewal' when OriginalActionType='Renew'
        └─ RenewalQuoteHeaderHandler.applyRenewalQuoteHeaders → copies ~40 header fields from source quote on the contract
        │
        ▼  (QuoteLineItem insert — 6 handlers fire inline, no dispatcher framework)
QuoteLineItemTrigger
   BEFORE insert (order matters, hard-coded):
        1. QuoteLineItemTriggerHandler.handleHardwareLinking
        2. QuoteLineItemCurrencyCorrectionHandler.correctPricebookEntryCurrency   (SC-3384)
        3. RenewalQuoteActionStamp.synthesizeRenewQuoteActions   ★ mints a Type='Renew' QuoteAction on RRM lines, keyed account|Solution_Category__c, sourcing the owned RNM/Perpetual asset — MUST precede #4
        4. COLAUpliftHandler.handleBeforeInsert                  → prices born-net = Asset.Price × (1+COLA%), 3-tier (Line>Contract>CMDT)
   AFTER insert:
        5. RenewalMaintenanceAutoAddHandler.enqueueIfNeeded → RenewalQuoteLineHandler.enqueueCarryoverCleanup → RenewalQuoteLineCleanupQueueable (async delete of New-Maint/Perpetual carryover once RRM present)
        6. RenewalAssetQuantityHandler.enqueueQuantityNormalization → RenewalAssetQuantityQueueable (flips No Change→Renew / →Amend, sets Quantity from asset)
        │
        ▼  (Reprice)
Fortra_Quote_Reprice (flow, Active) — fixed sequence:
        Build_Context → Run_Pricing (Rev_Mgmt_Default_Pricing_Procedure V23, skipDiscovery)
        → PartnerNetPricePosthook (apex)              ★ primary renewal-COLA context commit
        → RenewalMaintenancePricingService (apply)    ★ SECOND COLA-net stamp
        → RenewalMaintenancePricingService (finalizeAfterPricing=true)  ★ THIRD COLA-net stamp
        → Persist_Context
```

Prehooks/posthooks are registered on the procedure via **`ProcedurePlanOption`** (PrimaryObject=Quote): `COLAUpliftPrehook`, `PartnerPricingPrehookV2`, `AmendNetCarryPrehook` run pre-waterfall; `PartnerNetPricePosthook` runs post.

---

## 2. Component inventory (provenance from org `ApexClass`, live/dead verified by cross-reference)

### Triggers (2 — direct-call, no handler framework)
| File | Role | Assessment |
|---|---|---|
| `triggers/QuoteLineItemTrigger.trigger` | Entry for 6 renewal handlers, hard-coded order | **Band-aid magnet** — 6 unrelated concerns inline; ordering comments ("MUST run before…") are load-bearing and fragile |
| `triggers/QuoteTrigger.trigger` | 2 renewal header handlers | Clean, thin |

### Renewal quote/line handlers
| Class (CreatedBy) | Live? | Role | Assessment |
|---|---|---|---|
| `QuoteRenewalTypeHandler` (Nir) | **LIVE** via QuoteTrigger | normalize `Quote_Type__c='Renewal'` | Clean, single-purpose |
| `RenewalQuoteHeaderHandler` (Nir) | **LIVE** via QuoteTrigger | copy ~40 header fields from source quote | Necessary because Model B `initiateRenewal` yields a bare quote — a **compensator for a platform gap** |
| `RenewalQuoteActionStamp` (Liam, Jun 15) | **LIVE** via QuoteLineItemTrigger | synthesize `Renew` QuoteAction for RRM lines | **The keystone band-aid** — the proven RNM→RRM fix; cross-product asset match by `account|Solution_Category__c` |
| `RenewalAssetQuantityHandler` + `…Queueable` (Nir) | **LIVE** via QuoteLineItemTrigger | flip No Change→Renew/Amend, set qty from asset | Band-aid for platform Qty=0 on copied maintenance lines |
| `RenewalQuoteLineHandler` + `…CleanupQueueable` (Nir) | **LIVE** via RenewalMaintenanceAutoAddHandler | async-delete New-Maint/Perpetual carryover once RRM present | Band-aid; deletes-then-rebuilds is inherently race-prone (guarded by "don't re-run on reprice") |
| `RenewalMaintenanceAutoAddHandler` (Nir) | **PARTIALLY DEAD** | `enqueueIfNeeded` live; `ensureRenewalMaintenancePresent` (its actual auto-add) **orphaned** — self-ref only. Class header says "Production trigger path no longer calls this handler." | Dead auto-add logic left in place |
| `RenewalMaintenanceFlip` (Liam, Jun 15) | **DEAD/ORPHANED** | Invocable "Renew Maintenance Carryover" flip No Change→Renew | Superseded by `RenewalQuoteActionStamp`; **no trigger/flow/class reference anywhere** |
| `ContractAssetRenewalInvocable` (Nir, Jun 24) | **DEAD/ORPHANED** | Invocable wrapper for `initiateRenewal` w/ `skipPricing=true` | **Not referenced by any flow** — `Fortra_Create_Renewal_Quote` calls the native action directly instead |
| `RenewalQuoteAutoCreator` (Marc, Jun 24) | **DEAD as designed** | Schedulable headless renewal creator (90-day window) | **Not scheduled** (no CronTrigger); the scheduled job is the *flow* `Fortra_Contract_Renewal_Window_Monitor` instead. Settings `Renewal_Automation_Settings__mdt.Default` = enabled/90d but nothing invokes it except manual `runForContract` |

### COLA / maintenance pricing (the duplicated core)
| Class (CreatedBy) | Live? | Role |
|---|---|---|
| `COLAUpliftHandler` (Marc, Jan 30) | **LIVE** trigger | 3-tier COLA % + `Asset.Price×(1+COLA%)` (Model A math), Line-Override detection |
| `COLAUpliftPrehook` (Marc, Jan 30; 41KB) | **LIVE** via ProcedurePlanOption | pre-waterfall context COLA stamp + MyCAP eligibility; has its **own** `computeStampedMaintenanceColaNet` |
| `COLAUpliftCalculator` (Liam, Jul 8) | **LIVE** | **D-13 consolidation** — shared `resolveTier`/`isManualLineOverride`/`buildMaintenanceColaItemUpdate` engine used by BOTH handler and prehook. *The correct direction.* |
| `PartnerNetPricePosthook` (Nir, Jun 8; **86KB, ~2,500 lines**) | **LIVE** via reprice flow | primary renewal-COLA commit + partner + new-maint + contributor carry-forward |
| `RenewalMaintenancePricingService` (Nir, Jun 11) | **LIVE** via reprice flow (called **twice**) + AmendNetCarryPrehook + posthook | post-DPP context COLA stamp; has a **third** `computeColaNet` |
| `RenewalMaintenanceColaCalculator` (Liam, Jul 7) | **LIVE** via posthook | pure COLA net "extracted verbatim from PartnerNetPricePosthook" (Wave-2 decomposition) |
| `AmendNetCarryPrehook` (Liam, ~Jul 9, uncommitted) | **LIVE** via ProcedurePlanOption | Amend-line net carry (SC-3501); explicitly supersedes procedure `AmendSeedNetUnit/Total` steps |

### Posthook Wave-2 decomposition helpers (all **LIVE**, wired into `PartnerNetPricePosthook`)
`RenewalColaPayloadBuilder`, `DerivedMaintenancePayloadBuilder`, `DerivedMaintenanceClassifier`, `NewMaintenanceNetCalculator`, `NewMaintenanceBandCalculator`, `NewMaintenanceInputResolver`, `NewBusinessMaintenanceNets`, `PartnerParticipationResolver`, `PartnerNetResolutionCalculator`, `PartnerPricingGate` — all Liam, Jul 7-8. **Constructive refactor in progress**: pulling pure, unit-testable logic out of the 86KB posthook. Re-architecture should finish and lean on this.

### Forecast / opportunity
| Class | Live? | Role |
|---|---|---|
| `RenewalForecastAmount` (Marc, Jun 24) | **LIVE** via `Fortra_Contract_Create_Renewal_Opportunity` + `Fortra_Amendment_Sync_To_Renewal_Opp` | Σ MRR×12×COLA standing-opp amount (SC-3500) |

---

## 3. Flow inventory (org activation status verified via `FlowDefinitionView`)

| Flow | Status | Trigger | Role in renewals |
|---|---|---|---|
| `Fortra_Create_Renewal_Quote` | **Active** | override of `quotingAI__createRenewalQuote` | Model B quote creation (asset chain + opp + initiateRenewal) |
| `Fortra_Quote_Reprice` | **Active** | autolaunched | The renewal pricing orchestrator (procedure + posthook + RenewalMaintenancePricingService ×2) |
| `Fortra_Renewal_Quote_Creation` | **Active** | screen (Contract Renew button) | **Model A** quote creation from ContractLineItems + COLAUpliftHandler |
| `Fortra_RCA_Renewal_Enhancement` | **Active** | Quote after-save | creates Renewal/Amend/Cancel Opp via AssetAction lineage; stamps Fortra fields |
| `Fortra_Renewal_Quote_Enhancement` | **Active** | Quote after-save (async) | "enhances bare renewal quotes the broken createRenewalQuote override leaves" — creates fresh Renewal Opp, stamps Opp/LegalEntity/Contract |
| `Fortra_Contract_Create_Renewal_Opportunity` | **Active** | Contract after-save | standing renewal Opp on activation (SC-3500) |
| `Fortra_Contract_Renewal_Window_Monitor` | **Active** | **Scheduled daily 02:00** (CronTrigger `…-2` WAITING) | 120-day window → `Renewal_Status__c='Pending'` |
| `Fortra_Renewal_Contract_Succession` | **Active** | Order after-save | on renewal-order activation → original Contract `Renewal_Status__c='Accepted'` |
| `Fortra_Amendment_Sync_To_Renewal_Opp` | **Active** | after-save | re-computes `RenewalForecastAmount` on amendment |
| `Fortra_Renewal_Quote_Enhancement` vs `Fortra_RCA_Renewal_Enhancement` | both Active | — | **Overlapping** opp-creation/enhancement responsibilities |
| `Fortra_Order_Reprice`, `Fortra_Quote_Reprice_And_Q2O`, `Fortra_Quote_Reprice_Test_NoSkipDiscovery`, `Fortra_Quote_Count_Maintenance_Delete` | **Inactive** | — | dead/experimental variants left in repo |

---

## 4. Pricing procedure sprawl (`Rev_Mgmt_Default_Pricing_Procedure`, V23, **124,679 lines**)

Renewal logic is smeared across dozens of **cloned, numbered** steps — a re-architecture red flag:
- **COLA:** `COLAUpliftonRenewal` + 12 numbered clones (`…10/13/16/19/21/26/27/29/65/68/71/75`), `COLAUpliftNetonRenewal` — 225 "COLA" / 230 "Renewal" string occurrences.
- **Derived:** `DerivedProductsNonRenewal` (the `QuoteTypeText<>'Renewal'` exclusion filter, an `AdvancedListFilter` appearing 4×), `DerivedProductsRenewals`, `DerivedPricingRenewals`, plus `DerivedPricing`/`13/31/37`, `DerivedMaintenanceNetFilter`.
- **Partner:** `PartnerDiscountDerivedMaintenance` + ~14 numbered clones (`18-22`, `56-67`).
- **Amend:** `AmendFilter`, `AmendNetCarry`, `AmendSeedNetUnit`, `AmendSeedNetTotal` — now **partly superseded** by `AmendNetCarryPrehook` (procedure steps kept "as fallback").

## 5. Product Configuration Rules (org: 302 total, 202 active)

- **`Renew <Product> Sku`** family — **61 rules, 0 active** (all Inactive, Configurator/Transaction, Seq 10). A whole per-SKU renewal-maintenance auto-add scheme was built and **entirely abandoned** in favor of the Apex `RenewalQuoteActionStamp` born-net approach.
- **`Year 2 Maintenance Sku added to <Perpetual>`** — **98 active**; **`Year 1 Maintenance Sku added to…`** — **99 active**. These per-SKU config rules auto-add RNM/RRM when a perpetual is configured. So maintenance auto-add is split across **~197 near-duplicate PCRs + Apex fallback (`RenewalMaintenanceAutoAddHandler`, now dead) + the born-net stamp** — three generations of the same idea.

---

## 6. What a re-architecture should collapse (evidence-ranked)

1. **COLA-net is computed in ~5 places with drift risk:** `COLAUpliftHandler` (Asset×%), `COLAUpliftPrehook.computeStampedMaintenanceColaNet`, `RenewalMaintenancePricingService.computeColaNet`, `RenewalMaintenanceColaCalculator.computeRenewalMaintenanceColaNet`, and inline in `PartnerNetPricePosthook`. `COLAUpliftCalculator` (D-13) and the Wave-2 calculators are the intended single source — **finish the consolidation, delete the rest.**
2. **The reprice flow stamps renewal-maintenance net THREE times** (`RenewalMaintenancePricingService` apply + finalize, plus `PartnerNetPricePosthook`). Collapse to one commit.
3. **Two renewal quote-creation models run in parallel** (`Fortra_Renewal_Quote_Creation`/Model A vs `Fortra_Create_Renewal_Quote`/Model B). Pick one; Model A's `COLAUpliftHandler` Asset×% math is the legacy one.
4. **Overlapping opp-creation/header-stamp flows:** `Fortra_RCA_Renewal_Enhancement` + `Fortra_Renewal_Quote_Enhancement` + `Fortra_Create_Renewal_Quote` + `RenewalQuoteHeaderHandler` all create/stamp renewal opps & headers — because Model B yields a bare quote. Fix the creation path and delete the compensators.
5. **Delete confirmed dead code:** `RenewalMaintenanceFlip`, `ContractAssetRenewalInvocable`, `RenewalQuoteAutoCreator` (unscheduled), `RenewalMaintenanceAutoAddHandler.ensureRenewalMaintenancePresent`, and the 61 inactive `Renew* Sku` PCRs; retire inactive flows (`Fortra_Order_Reprice`, `Fortra_Quote_Reprice_And_Q2O`, `…_Test_NoSkipDiscovery`).
6. **QuoteLineItemTrigger has 6 order-dependent inline handlers** with load-bearing "MUST run before" comments — introduce an explicit ordered dispatcher or fold into the pricing procedure.
7. **Maintenance auto-add is a 3-way duplication** (~197 active Year-1/Year-2 PCRs + dead Apex auto-add + born-net stamp). Consolidate onto one mechanism.
8. **Procedure V23 renewal logic is dozens of numbered clones** — dedupe COLA/Derived/Partner/Amend step families.

**Key file paths:** all classes under `force-app/main/default/classes/`; triggers under `force-app/main/default/triggers/`; flows under `force-app/main/default/flows/`; procedure at `force-app/main/default/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml`.