# SC-3420 — PricingTermCount not enterable/derived on Quote lines (pricing-procedure regression)

| | |
|---|---|
| **Ticket** | SC-3420 (Salesforce-Coastal) — Priority **Critical** — CRM Sprint 14 — Labels CRM / CRM-Revenue-Cloud / RCA |
| **Reporter / Assignee** | German Wren → **Liam Jeong** |
| **Split from** | **SC-3415** (this ticket carves out SC-3415 "Defect B" — the quote-tier PricingTermCount root cause — into its own work item) |
| **Upstream origin of** | **SC-3406** (Quote→Order convert fails: "PricingTermCount required for Termed order products") · **SC-3411** (cannot activate Order: termed line missing EndDate/PricingTermCount) |
| **Org** | FortraUAT (`00DWC000006eUFF2A2`) — **UAT only**; this was a **read-only investigation** (metadata retrieve + SOQL describe, no DML, no deploy) |
| **Status** | ✅ **ROOT CAUSE PROVEN + BUILD-READY FIX SPEC** (2026-06-16). Fix itself is **owner-gated** (the active pricing procedure is co-owned and churns) — not deployed here. |

---

## 1. TL;DR

On **TermDefined** (subscription) Quote lines, `PricingTermCount` is **null and cannot be entered**. Every other term field (StartDate, EndDate, SubscriptionTerm, units, PricingTerm) still derives. The null then carries to the Order on convert and breaks the convert (SC-3406) and activation (SC-3411) lifecycle stages.

**Root cause — proven by version-level metadata diff against live FortraUAT:**
> The pricing procedure's **TermDefined Proration element** — the Salesforce-standard step whose *Proration Multiplier* output is mapped to `PricingTermCount` — was **deleted** from `Rev_Mgmt_Default_Pricing_Procedure` during the **V11→V12** "Maintenance Derived Pricing / COLA" rebuild on 2026-06-11. It is **still absent from the live-active version, V14.** With no engine step writing `PricingTermCount` for TermDefined lines, and the field being **platform read-only** (nothing else can write it), TermDefined quote lines are born with `PricingTermCount = null`.

The **OneTime** writer (`Assignment68`) and the **Evergreen** writer (Proration + `Assignment72`) survived the rebuild — which is exactly why **only TermDefined** lines are affected.

**Official Salesforce documentation confirms the intended design:** the Proration element outputs `Proration Multiplier = Actual Subscription Duration / Standard Subscription Term`, and Salesforce's own setup guidance instructs *"map the variable to this context tag: Proration Multiplier → `PricingTermCount`."* Fortra's procedure followed that design through V11; the rebuild dropped it for TermDefined.

**Fix (durable, platform-correct):** re-introduce one Proration element gated to `SellingModelType = 'TermDefined'`, output `ProrationMultiplier → PricingTermCount`, in the next pricing-procedure version. A faithful template (the exact V11 step) is captured in [`evidence/`](evidence/). **A declarative flow backstop is NOT possible at the quote tier** because the field is read-only (proven live, §4).

---

## 2. Symptom (live-confirmed 2026-06-16)

TermDefined QuoteLineItems created **today** under the live-active procedure:

| QLI | Product | PricingTermCount | SubscriptionTerm | EndDate | StartDate | SellingModel | Created |
|---|---|---|---|---|---|---|---|
| `0QLWC000003fF9R4AU` | SECURE Exchange Gateway | **null** | null | 2027-03-31 | 2026-06-16 | TermDefined | 16:24Z |
| `0QLWC000003fD9F4AU` | OCR Feature for SEG | **null** | 12 | 2027-03-31 | 2026-04-01 | TermDefined | 14:53Z |
| `0QLWC000003fBUW4A2` | SECURE Exchange Gateway | **null** | 12 | 2027-03-31 | 2026-04-01 | TermDefined | 14:13Z |

Pattern: `PricingTermCount` is the **universal** null; `EndDate` is always present; `SubscriptionTerm` is present on most but blank on the very newest UI-created lines (a secondary data-entry nuance — see §7). Full snapshot: [`evidence/live_symptom_2026-06-16.md`](evidence/live_symptom_2026-06-16.md).

This corrects the SC-3411 framing that a null `EndDate` propagated from the quote: **EndDate is fine; `PricingTermCount` alone is the gap.**

---

## 3. Why this is the source of the lifecycle chain

`PricingTermCount` null on the quote line is the **single upstream origin** of three lifecycle failures (same regression, three stages):

```
QUOTE (SC-3420, here)            CONVERT (SC-3406)                 ACTIVATE (SC-3411)
PricingTermCount born null  ──►  createOrderFromQuote copies   ──► RLM blocks activation of a
on TermDefined line              the null to OrderItem; native     TermDefined OrderItem with
                                 RLM validation: "PricingTerm-     null PricingTermCount/EndDate
                                 Count is required for Termed
                                 order products"
```

- `OrderItem.PricingTermCount` **is** writable (createable=true/updateable=true), which is the only reason an *order-tier* patch could exist. SC-3411 shipped that patch: **`Fortra_OrderItem_Set_Dates` V6** (RecordBeforeSave, stamps `PricingTermCount = 1` + EndDate on blank TermDefined order lines). That **masks** SC-3406/SC-3411 in UAT but does **not** restore quote-tier derivation, and **FortraProd has zero versions of it** → prod is fully exposed until either the procedure is fixed (this ticket) or V6 is promoted.
- SC-3420 is the **durable cure**: fix the engine so the null never exists.

---

## 4. The field is platform read-only — no declarative escape hatch

Live `describe` of `QuoteLineItem.PricingTermCount` (FortraUAT, 2026-06-16):

```
createable = false   updateable = false   calculated = false   type = double   formula = none
```

Consequences:
- **Only the native RLM pricing engine can write it** (during a Reprice / PlaceQuote pricing pass).
- A before-save record-triggered flow on QuoteLineItem **cannot** set it (the platform rejects the write). This **resolves the open feasibility question SC-3415 flagged** for an interim declarative backstop — there is **no quote-tier flow workaround**. The fix must be the pricing engine.
- Contrast: `OrderItem.PricingTermCount` is writable — hence the order-tier backstop is possible (SC-3411 V6) but the quote-tier is not.

---

## 5. Root cause — proven by version diff (the core of this RCA)

### 5.1 What the procedure does for PricingTermCount

`Rev_Mgmt_Default_Pricing_Procedure` derives `PricingTermCount` **per selling-model type** with three distinct writer steps:

| Selling model | Writer step (V11 names) | Mechanism | Value |
|---|---|---|---|
| **OneTime** | `Assignment68` (AssignmentElement) | sets PTC = constant | `OneTimePricingTermCountConstant` |
| **Evergreen** | `Assignment72` + `Proration72` | constant + proration | `EvergreenPricingTermCountConstant` |
| **TermDefined** | **`Proration`** (actionType=`Proration`) | **derives** PTC from term/dates | Proration Multiplier (= 1 for a 1-yr annual term) |

The **TermDefined** writer is a `Proration` element gated by the filter container **`TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel`** (`SellingModelType = 'TermDefined'`). Its parameters (verbatim from V11, see [`evidence/V11_removed_TermDefined_Proration_step.xml`](evidence/V11_removed_TermDefined_Proration_step.xml)):

```
actionType = Proration ,  parentStep = TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel
inputs : EffectiveFrom, EffectiveTo, ProrationPeriod=PricingTermUnit, SubscriptionTermUnit=PricingTermUnit,
         SubscriptionTerm=ItemSubscriptionTerm, SellingModelType, StartProrationPeriod*, AllowPartialProrationPeriods
OUTPUT : ProrationMultiplier  (output=true)  →  PricingTermCount    ← THIS writes the field
resultIncluded = true
```

### 5.2 The version-level smoking gun

Retrieved **all live ExpressionSetDefinitionVersions** of the procedure from FortraUAT (metadata API, 2026-06-16). Active = **V14**.

| Version | Status | `PricingTermCount` refs | `actionType=Proration` steps | TermDefined Proration writer present? |
|---|---|---|---|---|
| V1–V11 | Inactive | **18** | **2** (TermDefined + Evergreen) | ✅ **YES** |
| V12 | Inactive | 16 | 1 (Evergreen only) | ❌ **removed** |
| V13 | Inactive | 16 | 1 (Evergreen only) | ❌ removed |
| **V14** | **ACTIVE** | 16 | 1 (Evergreen only) | ❌ **removed** |
| V15 | Draft | 16 | 1 (Evergreen only) | ❌ removed |

The reference-count drop **18 → 16 happens exactly at V11→V12**. Diffing the two PricingTermCount references that disappear:

- **V11** has two `Proration` steps that output `ProrationMultiplier → PricingTermCount`:
  - `Proration` → parent `TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel` (**TermDefined**)
  - `Proration72` → parent `EvergreenanytimeprorationfilterLinelevel` (**Evergreen**)
- **V12 / V14** keep **only one** `Proration` writer — parented to the **Evergreen** filter. The **TermDefined** `Proration` step **and its entire filter container were deleted.**

V14's surviving subscription filters confirm TermDefined lines never reach a writer:
- `ListOperation73` (the Proration's gate): `SellingModelType = 'Evergreen' AND AllowPartialProrationPeriods = true AND itemTransientEndDate IsNotNull` → **excludes TermDefined**.
- `ListContainer83` (`SellingModelType = 'TermDefined' OR 'Evergreen'`) does run for TermDefined, but its steps only **read** `PricingTermCount` as a pricing input (`ProrationMultiplier`, input=true) — they never write it.

→ In V14, **no step under any TermDefined-matching filter writes `PricingTermCount`.** Proven.

### 5.3 Why it was dropped (and why it's a regression, not a design change)

The V11→V12 step-name diff shows V12 **added** `DerivedProductsNativePull`, `DerivedProductsNonRenewal`, `PartnerDiscountDerivedMaintenance{,19,20}`, `StampPartnerUnitPriceDerivedMaintenance`, `COLAUpliftNetonRenewal` — i.e. V12 is the **Maintenance Derived Pricing / COLA rebuild** (SC-3346 / SC-3350, Marc DeBrey + Nir Kailash). The TermDefined Proration element was **collateral damage** of that rebuild/re-numbering, not a deliberate removal: dropping it breaks ARR (ARR = TotalLineAmount/PricingTermCount), convert, and activation across **all** TermDefined products — clearly unintended. Same context↔procedure churn family as the *"Specify the contextDefinitionName"* Reprice gack and the SubscriptionTerm hydration issues from that week.

### 5.4 What this corrects from SC-3415

SC-3415 (read-only RCA) correctly localized the break to the V12 churn window but **hypothesized a context-definition de-sync** ("runtime context↔procedure term-hydration binding the republish failed to re-sync"). That hypothesis is **refuted here**: the context definition `SalesTransactionContextExt_v2` **still maps `PricingTermCount` correctly** both ways —
- hydration in: `QuoteEntitiesMapping/SalesTransactionItem/PricingTermCount` (ctx lines 5453-5458),
- write-back: `SalesTransactionItem/PricingTermCount` (ctx lines 728-730).

The plumbing is intact; a restored writer step **will** persist. The break is a **missing procedure step**, full stop. (This also means a "context re-sync" alone would *not* fix it — the step must come back.)

### 5.5 Timeline reconciliation (V11→V12 vs the ticket's "V12→V13")

The ticket title says "V12→V13." The **content** boundary is **V11→V12** (that's where the step disappears). These reconcile cleanly: version *content* and the *active-pointer flip* are separate events, and the labels churned via in-place edits/reactivations that week. SC-3415's data pins the behavioral cutover by line-creation timestamps: last PTC-populated TermDefined line created **2026-06-11 19:16:34Z**, first null **17:05:24Z** — i.e. a PTC-less build went active **~17:00Z on 2026-06-11**. Every version that has existed since (V12, V13, V14-active, V15-draft) lacks the TermDefined writer, so the exact label at the flip moment doesn't change the fix.

---

## 6. Fix specification (durable, build-ready) — owner-gated

**Goal:** restore engine derivation of `PricingTermCount` for TermDefined lines so a newly-priced quote line gets `PricingTermCount = 1` (annual) on Reprice, with no manual entry, and the value carries to the Order on convert.

**Change:** in a **new version of `Rev_Mgmt_Default_Pricing_Procedure`** (built from the live-active V14 / draft V15, never an older base — older bases lack the Derived-Maintenance/COLA work):

1. Re-create a line-level filter gated `SellingModelType = 'TermDefined'` (template: `TermDefinedSubscriptionFilterontheSellingModelTypeLineLevel`, [`evidence/V11_TermDefined_filter_container.xml`](evidence/V11_TermDefined_filter_container.xml)). A dedicated TermDefined-only container is preferred over reusing the combined `TermDefined OR Evergreen` container, so it cannot disturb Evergreen's existing constant-based PTC.
2. Under it, add one **Proration** element (template: [`evidence/V11_removed_TermDefined_Proration_step.xml`](evidence/V11_removed_TermDefined_Proration_step.xml)):
   - inputs `EffectiveFrom`, `EffectiveTo`, `ProrationPeriod = PricingTermUnit`, `SubscriptionTerm = ItemSubscriptionTerm`, `SellingModelType`, `AllowPartialProrationPeriods`;
   - **output `ProrationMultiplier → PricingTermCount`**, `resultIncluded = true`.
   - This matches Salesforce's documented design (Trailhead: *Proration Multiplier → PricingTermCount*).
3. Sequence it **before** the subscription-pricing steps that read `PricingTermCount` (so the read gets the derived value), and after dates are established. In V11 it ran at the same tier as the Evergreen Proration (sequence ~2 inside the subscription filter group).

**Validation (UAT, owner-authorized):**
- Activate the new version; **Reprice** a fresh TermDefined line (e.g. `ACTIDB` / `BESTSU` / `SEG`) → confirm `PricingTermCount` populates to **1.0** (annual, 1-yr term) with **no manual edit**, `CalculationStatus = CompletedWithPricing`.
- Confirm it **survives a second Reprice** and **carries to the Order** on convert (OrderItem PTC = 1) **without** relying on the V6 backstop.
- Regression-check: Evergreen lines still get PTC (Assignment/Proration), OneTime still get PTC (Assignment68), and the Derived-Maintenance/COLA outputs are unchanged.

**Help text (already addressed under SC-3415, AC6):** `inlineHelpText` on `QuoteLineItem.PricingTermCount` + `SubscriptionTerm` directing reps that PTC is system-derived/read-only and to set Subscription Term. Keep.

**Staged candidate (built 2026-06-16, NOT deployed):** `Data/sc3420/stage/` holds a candidate **V16** version (off live V14) with the TermDefined Proration writer re-added + `deploy/` MDAPI package + [`Data/sc3420/stage/CHANGES.md`](../../../Data/sc3420/stage/CHANGES.md). New steps: `TermDefinedProrationFilterLinelevel` (ListGroup, `SellingModelType='TermDefined'`) + `ProrationTermDefined` (`ProrationMultiplier → PricingTermCount`). XML-validated; preferred application is the Pricing Procedure builder UI (auto-sequencing). **Owner review + separate deploy ack required.**

### Constraints & cautions (from project memory)
- **The active procedure is co-owned and churns minute-to-minute** (V9→…→V14 within days; V15 already drafted; observed clobber/re-apply oscillation on related steps). **Always retrieve live before editing; coordinate the new version with Marc DeBrey / Nir Kailash / Ben Kozlowski** so it isn't overwritten by an in-flight republish. Bake the restored step into the canonical republish source, not a one-off edit.
- **Do not hard-delete** inactive versions or touch the two `PricingActionParameters` context bindings (Order/Quote) — platform-blocked and load-bearing.
- After publishing, **re-sync** `SalesTransactionContextExt_v2` if the UI requires it (mapping is already correct, but a republish may need a sync to bind the new version).
- **No prod deploy** without the standard cutover gate + a fresh authorization; prod is pre-cutover and lacks the order-tier backstop too.

---

## 7. Secondary observation — SubscriptionTerm null on newest UI lines

The four lines created 16:24Z today have `SubscriptionTerm = null` (not just PTC). The Proration writer needs `SubscriptionTerm` (`ItemSubscriptionTerm`) as input, so for those specific lines a restored Proration would still compute null until the rep/flow supplies a term. This is a **distinct, smaller data-entry gap** (the UI did not stamp a default term), not the PTC regression — most lines do carry `SubscriptionTerm` and would derive PTC correctly once the step is restored. Track the "default SubscriptionTerm on line create" gap separately (it overlaps SC-3338 "required fields" guidance). It does **not** change this root cause or fix.

---

## 8. Acceptance criteria status

| AC (from ticket) | Status | Note |
|---|---|---|
| Newly-priced TermDefined line derives `PricingTermCount = 1` automatically on Reprice | ⏳ **Fix specified, owner-gated** | §6 — re-add TermDefined Proration element to active procedure |
| Derived value survives Reprice + carries to Order on convert | ⏳ Pending fix | Validation plan in §6 |
| In-UI help text directs reps to Subscription Term (PTC read-only) | ✅ **Done** | Deployed under SC-3415 AC6 (`inlineHelpText` on PTC + SubscriptionTerm) |
| Verified on a fresh quote line (ACTIDB/BESTSU) → PTC = 1.0, no manual edit | ⏳ Pending fix | Final UAT verification step |

---

## 9. Evidence

- **Live metadata retrieve** (all procedure versions + context def): `Data/sc3420/live_retrieve/unpackaged/` (heavy artifacts kept under `Data/`).
- [`evidence/VERSION_DIFF.md`](evidence/VERSION_DIFF.md) — version matrix, PTC-ref counts, step-name add/remove diff, filter-condition trace.
- [`evidence/V11_removed_TermDefined_Proration_step.xml`](evidence/V11_removed_TermDefined_Proration_step.xml) — the exact deleted step (fix template).
- [`evidence/V11_TermDefined_filter_container.xml`](evidence/V11_TermDefined_filter_container.xml) — the deleted `SellingModelType='TermDefined'` filter container.
- [`evidence/live_symptom_2026-06-16.md`](evidence/live_symptom_2026-06-16.md) — live SOQL snapshot + field describe.
- [`evidence/official_proration_docs.md`](evidence/official_proration_docs.md) — Salesforce Proration design (Proration Multiplier → PricingTermCount), with sources.
- **Sibling dossiers:** `sc3415 |` (parent), `sc3406 |` (convert), `sc3411 |` (activate) in the same `*Jira/Task/` directory.

---
*RCA by Liam Jeong, 2026-06-16. Read-only investigation against FortraUAT (metadata retrieve + describe + SOQL; no DML, no deploy). Root cause proven by live version-level metadata diff and validated against official Salesforce Proration documentation.*
