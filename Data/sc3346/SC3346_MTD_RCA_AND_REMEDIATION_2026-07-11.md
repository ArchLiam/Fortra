# SC-3346-MTD — Derived New-Maintenance line prices $0 (missing tier attribute)

**Date:** 2026-07-11 · **Org:** FortraUAT · **Active proc:** Rev_Mgmt_Default_Pricing_Procedure **V25** (untouched)
**Repro quote:** `0Q0WC000003JXMj` · **Subject line:** 04267561 (`FIM-FIM-RNM-DPEENM`, Device Profiler Ev Express-NewMaintenance, qty 1, **EUR**)

---

## 1. Root cause — VERIFIED LIVE (confidence: confirmed, not just plausible)

The pricing **engine is correct**. The $0 is a **catalog classification gap**, not an engine bug.

The posthook that fills a derived New-Maintenance net keys the tier **strictly** on the
`Maintenance Type Defn` QuoteLineItemAttribute (QLIA). No QLIA → null tier → null rate → the line
is skipped → it keeps the procedure's $0.

**Live evidence chain (each link queried against FortraUAT):**

| Link | Finding | Source |
|---|---|---|
| $0 line's QLIAs | `{Feature Options, Number of Units, Unit Type, Unit Volume}` — **no Maintenance Type Defn** | `QuoteLineItemAttribute` on 0QLWC000003p0U54AI |
| Working sibling QLIAs | BoKS 04267516/17 carry **Maintenance Type Defn = Standard** → net 71 | `QuoteLineItemAttribute` |
| $0 product classification | `FIM-FIM-RNM-DPEENM` → **FEAT_UTYPE_NUMUNITS** (11BWC0000037mB42AI) | Product2.BasedOn |
| That classification's PCAs | Feature Options, Number of Units, Unit Type, Unit Volume — **NO Maintenance Type Defn PCA** | `ProductClassificationAttr` |
| Working product classification | `PIA-PIA-RNM-PIAMBK` → **MTYPE_ONLY**, which **HAS** the MTD PCA (0tjWC000000096bYAA) | `ProductClassificationAttr` |
| PAD that stamps the QLIA | BoKS product has an MTD `ProductAttributeDefinition` **DefaultValue='Standard'**; the FIM product has PADs only for its 4 non-tier attributes | `ProductAttributeDefinition` |
| Code skip point | `PartnerNetPricePosthook.loadNewMaintenanceLines` (L1544-1558) queries QLIA `WHERE AttributeName='Maintenance Type Defn'`; `NewMaintenanceInputResolver.resolveTierRate(null,…)` returns null → `continue` | Apex |

**Precise framing (corrects the ticket wording):** the RLM configurator is **not** dropping an
attribute. It faithfully applies each product's PADs. `FIM-FIM-RNM-DPEENM`'s classification simply
**does not model a maintenance tier** — there is no MTD PCA on the classification and no MTD PAD on
the product, so there is nothing to stamp and no picker for a rep to select. The line is therefore
**permanently $0-by-config**, with no in-app path to correction.

## 2. Blast radius — VERIFIED LIVE (matches the A-07 escalation exactly)

| Population | Count |
|---|---|
| Active New-Maintenance `Product2` | **1,683** |
| …with an MTD PAD (can carry a tier) | **207** |
| …**without** an MTD PAD (price $0 when a line is derived) | **1,476** |
| ↳ of those: no classification at all (`BasedOnId=null`) | 935 |
| ↳ of those: classified but classification has no MTD PCA (e.g. FEAT_UTYPE_NUMUNITS) | 541 |
| New-Maintenance products with a `PricebookEntryDerivedPrice` contributor mapping | 193 |

**Tier distribution among the 207 that DO carry MTD** (this is the key decision input):

| Default tier | Count | Rate |
|---|---|---|
| Standard | 120 (58%) | 0.20 |
| Professional | 50 (24%) | 0.20 |
| **Premier** | **35 (17%)** | **0.30** |
| Premium | 2 (1%) | — |

→ **~17% of tagged products are Premier (0.30).** A blanket "default untagged to Standard 0.20"
would silently **under-price ~1 in 6** of the 1,476 gap products by 33% (0.20 vs 0.30), with no
rep-visible attribute to catch or correct it.

## 3. Immediate live-line remediation — DONE & VERIFIED ✅

Reproduced the ticket's proof that the engine prices correctly once the tier attribute is present:

1. **REST-inserted** (Apex DML is blocked on the managed QLIA) a `Maintenance Type Defn = Standard`
   QLIA onto line 04267561 — cloned from the working BoKS QLIA shape (AttributeDefinitionId
   `0tjWC000000096bYAA`, AttributePicklistValueId `0v6WC0000000A5WYAU`). New record `0zuWC000006OvRaYAK`.
2. **Repriced.** The soft `Fortra_Quote_Reprice` flow returned success **but did not flush** (settled
   line). The full-engine **PST-Force** (`connect/rev/sales-transaction/actions/place`, `pricingPref:Force`)
   **did** flush.
3. **Result:** line 04267561 `NetUnitPrice` **$0 → 60.75** (= source subscription net **303.745 × 0.20**).

**Note on the expected value:** the ticket said "→ 71"; that is the **BoKS** number (355 × 0.20). The
FIM line's contributor is its **own subscription** (`FIM-FIM-RSS-DPEEXS`, 303.745), so the correct
value is **60.75**, which is what the engine produced. The engine is correct.

## 4. The business decision (OPEN — owner's call; must not be silently coded)

Per the Maintenance-Derived-Pricing SDD **RULE 11**, blank/off-list tier → **$0 by design**, and "any
change to fallback behavior is a **deliberate spec decision, not a bug fix**." The SDD's model assumes
the rep **selects** a tier — but for the 1,476 gap products there is **no attribute to select**, so
"surface $0 for manual selection" is not actually reachable in-app for them. That tension is the
decision.

### Options

**A — Apex posthook Standard-0.20 default (interim, blunt).**
In `loadNewMaintenanceLines`/`resolveTierRate`, when a New-Maintenance line has no tier, default to
Standard 0.20 (optionally scoped to sanctioned solution groups). One compliant Apex change; **no
procedure touch, no new version**; fixes all 1,476 at once immediately; reversible.
*Cost:* silently under-prices the ~17% Premier products; removes rep agency (no picker to override);
overrides SDD RULE 11 → **a client decision**.

**B — Catalog remediation (durable, SDD-aligned).**
Add the MTD `ProductClassificationAttr` to the gap classifications (541), then an MTD PAD per product;
classify + PAD the 935 unclassified. Reps then **see and select** the correct tier per product.
*Cost:* a catalog project (A-07, already escalated); we still lack per-product tier data so unknowns
default to Standard anyway; **existing** $0 lines still need per-line QLIA backfill (as demonstrated),
because RCA won't retro-add a new attribute to lines configured before it existed.

**C — Both (recommended).**
Ship A as the **interim revenue-unblock** now (Apex posthook, scoped + telemetry-logged), and pursue
B as the **durable** fix; **retire the default** once the catalog PAD is in place so reps regain tier
selection. This unblocks revenue immediately while converging on the SDD-correct model.

**D — Keep $0-by-design (SDD RULE 11 literal).**
No code change. But it leaves 1,476 products unpriceable-by-config; every occurrence needs the
per-line data op above. Weak, because the rep has no in-app correction path.

### Recommendation
**C**, with the interim default in **Apex posthook only** (honoring "minimize procedure / no new
version"), **scoped** so it does not price genuinely-uncatalogued products, and **logged** via the
`Pricing_Exception__e` telemetry path (Severity INFO) so every silent default is auditable. Treat the
~17%-Premier under-pricing as the explicit accepted risk of the interim, retired when B lands.

**Immediate action does not require this decision** — the live line is already fixed. The decision only
governs the systemic/go-forward fix.

---

## 5. DECISION: Option C chosen (interim posthook default + catalog remediation)

### 5a. Interim — Apex posthook Standard-0.20 default (DEPLOYED + E2E-PROVEN ✅)

**Deployed to FortraUAT** (deploy `0AfWC00000GoWwL0AV`); validation run was **74/74 tests green**
(the deploy itself used NoTestRun because the sandbox coverage gate needs the full suite, not the 2
specified classes — coverage is unaffected by this change).

**E2E proof on a live line (the real proof, not just the data patch):** deleted the manual QLIA from
line 04267561 so it returned to the pure defect state (`{Feature Options, Number of Units, Unit Type,
Unit Volume}` — **no Maintenance Type Defn**), then PST-Force repriced → the line prices
**NetUnitPrice = UnitPrice = 60.75** purely via the deployed posthook default, with **no tier
attribute present**. Full quote healthy (BoKS 71, subscriptions 303.745, no collateral change). The
quote is left clean — the FIM line now prices via code, not a manual data patch.


No procedure touch, no new proc version. Files changed:

- **`NewMaintenanceInputResolver.cls`** — new pure helper `resolveEffectiveTierRate(tier, rateByType,
  defaultTier)`: returns the line tier's rate; else the default tier's rate; else null. A **blank
  `defaultTier` disables the fallback** (this is the retirement switch — keeps `resolveTierRate`
  untouched for back-compat).
- **`PartnerNetPricePosthook.cls`** — new constant `UNTAGGED_MAINTENANCE_DEFAULT_TIER = 'Standard'`;
  both the Quote-line and Order-item New-Maintenance loops call `resolveEffectiveTierRate(…,
  UNTAGGED_MAINTENANCE_DEFAULT_TIER)` instead of `resolveTierRate`, and emit an INFO trace
  (`NEW MAINT UNTAGGED DEFAULT: …`) when the default is applied. The **rate stays admin-editable** in
  `Maintenance_Rate__mdt`; only the default-tier *selection* is set in code.
- Tests: `NewMaintenanceInputResolverTest.resolveEffectiveTierRate_*` (pure, all branches) +
  `PartnerNetPricePosthookTest.loadNewMaintenanceLines_appliesUntaggedStandardDefault` (bulk 25-line,
  proves untagged lines resolve 0.20 and are no longer skipped).

**Scope guard:** the loader already filters `New Maintenance AND (Base_Price__c>0 OR
Source_List_Price__c>0)`, so a line with no pricing base still stays $0 — the default only fires on
lines that already have a positive base. It **never overrides a real tier** (a resolved tier short-
circuits before the default). **Accepted risk:** the ~17% of gap products whose true tier is Premier
are under-priced at 0.20 until catalog remediation trues them up.

**Audit signal (queryable, no telemetry-pipeline abuse):** a defaulted line = a `New Maintenance` line
with `NetUnitPrice>0` **and no `Maintenance Type Defn` QLIA**. (Deliberately *not* logged per line —
the default is normal business behaviour, not an error, so it belongs in neither the exception-
telemetry pipeline nor a per-line `System.debug`; the queryable signal above is the audit trail.)

**Retirement:** set `UNTAGGED_MAINTENANCE_DEFAULT_TIER = ''` once the catalog models tiers on these
products, so reps' explicit selections (and the correct Premier rates) fully govern again.

**Code-quality cleanups (working tree, deploy HELD).** Two follow-up cleanups to `PartnerNetPricePosthook`
are coded + compile-validated but **not deployed** by owner decision (the file is entangled with a
concurrent, undeployed SC-3398 change — `CurrencyDisplayReconciliationService` — so the next SC-3398 PNPP
deploy carries these too):
- Removed opaque internal-code prefixes from shared-code comments (`J-06`, `D-18`, `Wave-2`/`step N`) per
  apex-compliance §1; removed the `SC3384-DBG` debug trace.
- Replaced `System.debug` in every catch block with `PricingHookLogger.logPosthook(...)` (§9 telemetry on
  swallow-to-degrade); the benign "context not in updatable state" branch is expected control flow (silent
  return); the per-line untagged-default `System.debug` traces were dropped (the default is normal
  behaviour, audited via the queryable signal above — not the error pipeline). No logic changed.

### 5b. Durable — catalog remediation scope (A-07, parallel project)

The 1,476 gap products break down as:

| Bucket | Count | Remediation |
|---|---|---|
| Classified, no MTD PCA on the classification | 541 | Add MTD `ProductClassificationAttr` to the classification, then an MTD PAD per product |
| Unclassified (`BasedOnId=null`) | 935 | Assign a classification first, then PAD |

**The 541 span 17 classifications, heavily concentrated** — remediating just two covers 85%:

| Classification | Gap products |
|---|---|
| STYPE_ONLY | 333 |
| PL_STYPE | 127 |
| DTYPE_STYPE | 18 |
| FEAT_STYPE | 17 |
| FEAT_UTYPE | 15 |
| FEAT_UTYPE_NUMUNITS *(this ticket)* | 6 |
| (11 more) | ≤5 each |

**Prerequisite for correctness:** catalog remediation still needs a **per-product intended-tier
source** (which of these are genuinely Premier?). Absent that, PADs would also default to Standard —
so the tier-data question must be answered with the client for the remediation to add value beyond the
interim. Recommend sequencing: (1) add the MTD PCA to STYPE_ONLY + PL_STYPE (covers 460); (2) source
intended tiers; (3) PAD the products with correct DefaultValues; (4) classify + PAD the 935; (5)
retire the interim default.
