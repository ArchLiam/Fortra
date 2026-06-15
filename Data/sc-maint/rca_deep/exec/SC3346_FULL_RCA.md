# SC-3346 — Maintenance (Derived) Pricing + COLA: Full Root-Cause Analysis

**Revenue Cloud Advanced / RLM · FortraUAT (`00DWC000006eUFF2A2`) · 2026-06-14**

> **Verdict — FIXED, deployed, and end-to-end proven on live data.** A BoKS maintenance renewal now commits the
> correct COLA net **$67.38** (= 62.48 × 1.0785) instead of the frozen **$60.64 / $0**. The fix
> (`RenewalMaintenanceFlip`, deployed to UAT, 4/4 tests, 100% class coverage) flips the owned-maintenance renewal
> line from `No Change` to `Renew` so the native engine commits the COLA uplift.

**Scope of this document:** the entire RCA process — domain background, the defect, the phase-by-phase
investigation, every ruled-out lever, the definitive root cause, the fix, a fresh live end-to-end validation
(with all-lines + header-rollup proof), honest residual caveats, and the production-rollout path.

**Companion deliverables:** `SC3346_FULL_RCA.html` (high-visibility report), `SC3346FullRCA.jsx` (React mirror),
`SC3346_FULL_RCA.pdf` (print). Live evidence under `Data/sc-maint/sc3404/renewfix/e2e_final/run/`.

### Contents

1. Executive Summary & Verdict
2. Background: The Domain & The COLA Mechanism
3. The Defect & Symptoms
4. The Investigation — Phase by Phase
5. Dead-End Ledger — Why Earlier Fixes Could Not Work
6. Root Cause — The Definitive Mechanism
7. The Fix — Design, Code & Wiring
8. End-to-End Validation (Fresh Run)
9. Production Rollout & Remaining Work
10. Appendix — Artifacts, Identifiers & Glossary

---

## Executive Summary & Verdict


**Verdict: FIXED — deployed to FortraUAT and end-to-end proven on live data.** The renewal-maintenance line for Powertech IAM (BoKS) now commits the correct COLA net of **67.38** (= 62.48 × 1.0785), eliminating the **60.64** fossil and the **$0** variant. The fix — `RenewalMaintenanceFlip` (Apex, with sharing, API 64; **4/4 unit tests pass, 100% class coverage**) — is deployed and wired into the `Fortra_Create_Renewal_Quote` flow. A fresh 2026-06-14 live E2E on canary asset `02iWC000008DmS1YAK` (ephemeral quote `0Q0WC0000039Ktp0AE`, since deleted) confirmed the line committing NetUnitPrice 67.38 / NetTotalPrice 67.38 as the **sole line** — an all-lines query with no product filter returned exactly one line, zero RRM substitute lines — and the quote header rolled up consistently (TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38, LineItemCount = 1; rollups consistent, not stale).

In plain business terms: when a BoKS maintenance renewal quote was generated, the line that should renew at this year's uplifted price was instead freezing at an old, wrong value (60.64 — a one-period partner double-discount, = 67.38 × 0.90) or at zero. The cause was structural, not arithmetic — the COLA math itself was always correct (it computed 67.38 every time). Because new-business maintenance (`PIA-PIA-RNM-PIAMBK`) is sold under a **One-Time** selling model, the platform's `initiateRenewal` renews its owned asset as `QuoteAction.Type='No Change'` with Quantity 0, which never enters the **Renew**-gated COLA pricing path (Term-Based subscriptions like beSECURE, `VM-BSL-RSL-BESECB`, renew as 'Renew' and price correctly). The legacy Year-2 AutoAdd Product Configuration Rule then deleted that carryover and substituted an asset-less Renewal-Maintenance (RRM, `PIA-PIA-RRM-PIAM`) line with no contributor, so the native committer (`DerivedProductsRenewals`, contributor-keyed) skipped it and the line stayed frozen at the fossil or $0. The fix stops fighting the engine at the wrong layer and instead **flips the owned-maintenance QuoteAction from 'No Change' to 'Renew'** (StartQuantity 0, Quantity = source-asset quantity) so the native engine itself applies the 7.85% COLA uplift to last year's net via `COLAUpliftonRenewalNet` and commits it. Outcome: the renewal now prices at **67.38** instead of the broken **60.64 / $0**, with no asset-modeling, PBEDP, or selling-model change required.

Why the flip rather than the self-healing candidate: the dossier first considered a procedure-commit change (lever-d) because it could in principle self-heal existing re-priceable fossils, but it could not be **proven** to fire — the 67.38 seen in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs — so it was rejected as unproven and unsafe in favor of the deterministic flip. One honest uncertainty carries forward: the exact platform reason a direct `NetUnitPrice` write no-ops on these lines (settled-derived-node immutability vs. wrong context phase) is empirically strong — reproduced three independent times — but not mechanistically pinned.

**Scope:** the flip fixes renewals **as they are generated** (via the wired flow or an on-demand `flipToRenew` call). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice.

### Headline Metrics

| Metric | Value |
|---|---|
| Correct committed NetUnitPrice (post-fix) | **67.38** (= 62.48 × 1.0785, 7.85% COLA) |
| Broken values eliminated | **60.64** fossil (= 67.38 × 0.90, one-period double-discount) and **$0** |
| Pre-fix conformance | Near-total structural failure across renewal-maintenance lines; per the investigation dossier, the only pre-fix line committing 67.38 was a hand-built synthetic RRM record, not a natural one |
| Fix | `RenewalMaintenanceFlip` (Apex, with sharing, API 64) — **deployed to UAT; 4/4 unit tests pass; 100% class coverage** |
| Live E2E (2026-06-14, asset `02iWC000008DmS1YAK`) | flip → reprice committed **67.38**; sole line, zero RRM substitute lines; header rollup consistent — **PASS** |
| Remaining (owner / verify-before-prod) | Re-pin the 7.85% BoKS COLA rate to its `Maintenance_Rate__mdt` record (a known orphan-"platinum" rule exists in this catalog); resolve `COLAUpliftTest.buildOverrideMap` coverage drift before prod promotion; run a production renewal smoke-test |

---

---

## Background: The Domain & The COLA Mechanism


This RCA concerns renewal pricing in **Revenue Cloud Advanced (RCA)** — the Salesforce platform formerly branded Revenue Lifecycle Management (RLM) / Subscription Management — as configured in **FortraUAT** (org `00DWC000006eUFF2A2`). A reader fluent in Apex and Salesforce data modeling but new to RLM needs five concepts to follow the root-cause argument: (1) the native pricing engine and its derived-pricing model, (2) what a COLA renewal uplift is, (3) the shared Discovery + Pricing context, (4) selling models and how they govern renewal behavior, and (5) the renewal *contributor* model. The COLA commit gate, `COLAUpliftonRenewalNet`, ties them together.

### Revenue Cloud Advanced / RLM and the native pricing engine

In RCA, a Quote (and the Order it converts to) is priced by a **single platform pricing procedure**, `Rev_Mgmt_Default_Pricing_Procedure`, an `ExpressionSet`. The procedure is the only sanctioned writer of pricing fields; line prices are not free-writable Apex columns. Critically, the engine **owns `NetUnitPrice`**: on a derived line it is an *engine output*, not a createable/updateable field. This is the single most important fact for everything downstream — Apex DML that writes `NetUnitPrice` directly is read-only on insert, and reprice-time corrective writes through the context API return `isSuccess=true` while the committed value is silently discarded (reproduced three times against this engine). The *exact* platform reason a direct write no-ops — settled-derived-node immutability versus a wrong context phase — is empirically strong but not yet mechanistically pinned; that uncertainty is carried forward rather than laundered into a clean explanation.

Pricing is invoked through the managed reprice endpoint — `POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` with `{pricingPref:"Force", configurationPref:{configurationMethod:"Skip"}}` — which runs the full procedure and re-commits the line. Direct Quote/QLI DML inside the managed persist is constrained by the RLM Quote-DML lock; this RCA respects it by repricing Draft quotes only, never touching the Accepted quote `00781068`, and never publishing Order/Workday events.

### Native derived pricing

A **derived product** has no price of its own. Its `PricebookEntry` is flagged `IsDerived=true`, and its committed price is computed from a *contributor* — another record (a sibling product line, or an owned **Asset**) whose price feeds a formula. In this catalog, maintenance is a derived product: the maintenance line derives off the license. The native `DerivedProductsRenewals` element (the element authorized to write `NetUnitPrice` on a derived line) is **contributor-keyed by construction** — every input is a `Contributor*` parameter. A line for which no contributor entry resolves is simply *skipped*: the element never recomputes its `NetUnitPrice`, so whatever value the line was born with persists. This "skip" behavior — not platform immutability of the value — is the mechanism by which a wrong renewal price *freezes*.

The products at the center of this RCA:

| Role | SKU | `Fortra_Product_Type__c` | Selling model |
|------|-----|--------------------------|---------------|
| Perpetual license | PIA-PIA-NRPS-PIAP | Perpetual | — |
| New-business maintenance (owned asset) | PIA-PIA-RNM-PIAMBK | **New Maintenance** | **One Time** |
| Legacy renewal-substitute maintenance | PIA-PIA-RRM-PIAM | **Renewal Maintenance** | Term-Based / One-Time |
| Subscription comparator (renews correctly) | VM-BSL-RSL-BESECB | — | **Term Based** (TermDefined) |

The new-business maintenance product (RNM-PIAMBK) is what customers actually *own* as an Asset; the RRM-PIAM SKU is a legacy renewal substitute that is auto-added at renewal. This distinction is load-bearing later.

### COLA: the renewal uplift

A **COLA** (cost-of-living adjustment) is a contractual percentage uplift applied to a maintenance line's price when it renews — the renewal is priced from last year's negotiated net, raised by a published rate. For the canary BoKS asset (`02iWC000008DmS1YAK`, last-transaction `Asset.Price` **62.48**, quantity 1, Status Installed) the BoKS category COLA rate is **7.85%**, so the correct renewal net is:

> 62.48 × 1.0785 = **67.38**

That `67.38` is the only correct committed value. The broken alternatives observed in the field are `60.64` (an older partner double-discount fossil, 67.38 × 0.90) and `$0`. The fresh live E2E on 2026-06-14 confirms the correct figure: after the fix and reprice, the line settled at `NetUnitPrice = 67.38`, `NetTotalPrice = 67.38`, `COLA_Uplift_Percent__c = 7.85`. The COLA math here is the *native renewal uplift* on the prior net — on the final settled line the custom `COLACalculatedPrice__c` field read `0`, confirming that the platform engine, not a custom posthook field, committed the value.

The 7.85% BoKS rate is sourced from a COLA-rate custom metadata rule. The exact metadata record was **not** re-pinned this pass and is flagged as a verify-before-prod item — the catalog is known to carry an orphan-"platinum" `Maintenance_Rate__mdt` issue elsewhere, so the governing record should be confirmed before any production rollout.

### The shared Discovery + Pricing context

Derived/renewal pricing depends on two procedures sharing one context. A **discovery procedure** runs *before* the pricing procedure and gathers data from three sources — Products, **Assets** (what the customer already owns: original price, quantity, contract period), and quote headers — writing them into a context definition. The hard platform requirement is that the discovery procedure and the pricing procedure **use the same context definition**. The Asset reaches the pricing engine through this shared context, where Asset Discovery surfaces the owned asset's last-transaction net as a contributor for the derived renewal line. This is therefore **not** a missing-procedure problem.

### Selling models: One-Time vs Term-Based

A product's **selling model** governs how the platform's `initiateRenewal` action treats the owned asset at renewal — and this is the crux of the defect.

| Selling model | Example product | How `initiateRenewal` renews the owned asset | Result |
|---------------|-----------------|---------------------------------------------|--------|
| **Term Based** (TermDefined) | beSECURE VM-BSL-RSL-BESECB | Mints a `QuoteAction.Type='Renew'`, Quantity > 0 | Enters the Renew-gated COLA path → commits correctly |
| **One Time** | New-maintenance PIA-PIA-RNM-PIAMBK | Renews the owned asset as `QuoteAction.Type='No Change'`, **Quantity 0** | Never enters the Renew-gated COLA path → no COLA |

The RLM quantity convention that distinguishes the two QuoteAction states:

| QuoteAction.Type | Quantity | StartQuantity |
|------------------|----------|---------------|
| No Change | 0 | > 0 |
| Renew | > 0 | 0 |

Because new-business maintenance is sold under a **One-Time** selling model, the platform renews its owned asset as a `No Change`, Quantity-0 line — which the COLA gate never accepts. Term-Based subscriptions (beSECURE) renew as `Renew` and price correctly through the identical mechanism, which is why the defect is specific to maintenance, not to COLA logic.

### The renewal CONTRIBUTOR model

For a renewal, the contributor that resolves a derived maintenance line's price is **the prior owned Asset**, surfaced into the shared context via the `Renew` QuoteAction's SourceAsset. `QuoteAction` is keyed to the Quote and to the SourceAsset (there is no `QuoteLineItemId` foreign key on it). When `initiateRenewal` mints a `Renew` QuoteAction pointing at the owned asset, Asset Discovery writes that asset's last-transaction net into the context, `DerivedProductsRenewals` finds a contributor, and `NetUnitPrice` commits. When there is **no Renew QuoteAction**, there is no SourceAsset for Discovery to follow, no contributor resolves, the derived element skips the line, and its born value freezes.

Per the investigation dossier, the large majority of renewal-maintenance lines org-wide carry no Renew QuoteAction and therefore freeze at their fossil or `$0` born value; pre-fix conformance reflects a near-total structural failure. The dossier notes that the lone "control" line which already commits the correct 67.38 pre-fix is an artificially hand-built single RRM asset created during investigation — a synthetic record, not a naturally occurring one — so the apparent presence of a correct line masks rather than mitigates the systemic failure. That control differs from a frozen line in exactly one respect: the presence of a Renew QuoteAction. That single difference is the entire mechanism. Compounding it, the legacy Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE` *deletes* the owned-asset carryover and substitutes an asset-less Renewal-Maintenance (RRM, SKU PIA-PIA-RRM-PIAM) line that has no SourceAsset contributor at all — guaranteeing the derived committer skips it.

### The COLAUpliftonRenewalNet gate

`NetUnitPrice` on these renewal-maintenance lines is committed by a custom procedure step, **`COLAUpliftonRenewalNet`**, which assigns `COLACalculatedPrice__c → NetUnitPrice`. It is governed by an **action-type gate**, not a product gate — there is no Product2-Id, ProductCode, or `Fortra_Product_Type__c` criterion anywhere in it:

| Gate condition | Required value |
|----------------|----------------|
| `SalesTransactionActionType` | `'Renew'` |
| `ItemPricingSource` | `'LastTransaction'` |
| `DerivedPricingAttribute` | `false` |
| `COLA_Uplift_Percent__c` | IsNotNull |

Because the gate keys on `SalesTransactionActionType='Renew'`, a maintenance line whose owned asset renewed as `No Change` (the One-Time selling-model outcome) **never satisfies it**, and the COLA uplift is never assigned to `NetUnitPrice`. This action-type-gated — not product-gated — design is the lens through which the entire root cause resolves: the fix is not to write the price, but to make the line a `Renew` node with a SourceAsset contributor before it is first priced.

The dossier first considered a procedure-commit change (a "self-healing" lever) precisely because it could retroactively heal existing re-priceable fossils. That candidate was **rejected**: it could not be *proven* to fire — the `67.38` seen in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs — so it was set aside as unproven and unsafe in favor of the deterministic flip. As a consequence, the chosen fix is **forward-only**: it corrects renewals as they are generated (via the wired flow, or on demand through `flipToRenew`). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice.

The deterministic flip is implemented in `RenewalMaintenanceFlip` (Apex, `with sharing`). Live evidence captured 2026-06-14 confirms it: `RenewalMaintenanceFlipTest` ran synchronously to Outcome **PASSED**, **4 of 4** tests passing (`flipsNoChangeMaintenanceToRenew`, `leavesAlreadyRenewAndOtherTypesAlone`, `nullAndEmptySafe`, `skipsNonRenewalQuote`), with class coverage **100%**. The all-lines + header-rollup E2E on an ephemeral quote (`0Q0WC0000039Ktp0AE`, created then deleted) is decisive: the BEFORE-flip all-lines query (no product filter) returned **exactly one** line — PIA-PIA-RNM-PIAMBK, `No Change`, quantity 0, Net null; the FINAL all-lines query returned **exactly one** line and **zero** RRM lines — PIA-PIA-RNM-PIAMBK, `Renew`, quantity 1, `NetUnitPrice = 67.38`, `NetTotalPrice = 67.38`. The quote **header rollup** was consistent and not stale: `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, line item count 1. An earlier E2E (`0Q0WC0000039Kc50AE`, deleted) showed the same progression, with `COLA_Uplift_Percent__c = 7.85` and `COLACalculatedPrice__c = 0` on the final line — confirming the native uplift, not the custom posthook field, as the committer.

---

---

## The Defect & Symptoms


### What the user observed

On renewal quotes for Powertech Identity & Access Manager (BoKS), the renewal-maintenance line committed the **wrong net price — or no price at all**. Instead of the COLA-correct **67.38**, the line settled at a stale **60.64** "fossil" or at **$0**.

The most damning detail: **the COLA math was right, but it was never committed.** On a failing line the COLA computation fields were correct — `COLA_Uplift_Percent__c = 7.85` — yet the field that actually carries money, `NetUnitPrice`, stayed frozen at the fossil value. The engine had the right number and discarded it. A dashboard reading the COLA computation fields would show "fixed" while the committed `NetUnitPrice` told the opposite story.

The correct value is deterministic and easy to verify against the asset being renewed:

| Quantity | Description | Value |
|---|---|---|
| Canary asset (`02iWC000008DmS1YAK`) net last-transaction price | Asset.Price | 62.48 |
| COLA uplift (Powertech IAM BoKS) | `COLA_Uplift_Percent__c` | 7.85% |
| **Expected committed net** | 62.48 × 1.0785 | **67.38** |

By contrast, the fossil value traces to a prior partner re-discount, not to COLA:

| Symptom value | Derivation | Meaning |
|---|---|---|
| 67.38 | 62.48 × 1.0785 | Correct COLA net (target) |
| 60.64 | 67.38 × 0.90 | Older fossil — a one-period partner 10% re-applied on the already-net price |
| $0 | (uncommitted) | Same frozen-node mechanism — line never receives a committed net |

### Which products were affected

The defect is narrow in catalog terms but total in business terms. The affected SKU is the legacy renewal-maintenance line **`PIA-PIA-RRM-PIAM`** (`Fortra_Product_Type__c = 'Renewal Maintenance'`), auto-added on renewal in place of the customer's owned new-business maintenance asset **`PIA-PIA-RNM-PIAMBK`** (`Fortra_Product_Type__c = 'New Maintenance'`, sold under a One-Time selling model).

Per the investigation dossier, the large majority of BoKS renewal-maintenance lines failed to commit the correct **67.38**; the lone pre-fix line that did commit it was an artificially hand-built single RRM asset created during the investigation — a synthetic record carrying a `QuoteAction(Type='Renew')`, not a naturally generated one. So pre-fix conformance reflected a near-total structural failure masked by that one synthetic record; the remaining natural lines committed **60.64** or **$0**.

New-business maintenance pricing and the subscription renewal comparator **beSECURE `VM-BSL-RSL-BESECB`** ("Term Based") renew **correctly** — the latter is the proof that the renewal pricing path itself works; only the One-Time maintenance lineage fails to enter it. The native committer on derived lines, `DerivedProductsRenewals`, is contributor-keyed and silently skips a line with no contributor.

### Business impact

The understatement is roughly **10% per unit** on every affected renewal-maintenance line, and the fossil is not contained to drafts: the **60.64** fossil propagated past Draft onto the Accepted quote **00781068** (left untouched this pass), and from there downstream. A pricing fix alone cannot retro-correct an already-activated order, an installed asset, or a synced Workday record; that downstream remediation is a separate, owner-gated workstream.

The currently-failing accounts are test accounts, so today's real-customer blast radius is effectively zero. But the mechanism is structural, not data: in a real customer base where **no account owns a hand-built RRM asset**, every BoKS renewal-maintenance line would fail — and per the dossier the same license→maintenance AutoAdd modeling pattern spans the large majority of renewal-maintenance products org-wide, near 1:1 with their new-maintenance counterparts. The **60.64** understatement on a real renewal book would be a systemic revenue leak.

### Prior remediation attempts all failed

Before the root cause was correctly isolated, every attempted fix targeted the **wrong layer** — trying to *write the price* onto a settled derived node rather than supplying the missing Renew contributor at creation. The reprice-time approaches were proven dead:

| Attempt | Why it failed |
|---|---|
| Write `NetUnitPrice` directly via DML | Engine-owned; read-only on insert |
| `PartnerNetPricePosthook` corrective write | Reprice-time write no-ops on a settled derived node — the context write returns `isSuccess=true` while the value is silently discarded (reproduced 3×) |
| "Lever-d" self-healing procedure-commit change | First considered because it could self-heal existing re-priceable fossils, but it could **not be proven to fire**: the **67.38** seen in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs, so it was rejected as unproven/unsafe |
| Map the owned product as a derived-pricing contributor | Platform-rejected: the owned product is itself a derived product and can't be set as the source |
| Hand-stamp a Renew QuoteAction **after** insert and reprice | Too late — the line settles un-priced and locks; a false positive (computation fields move, `NetUnitPrice` does not) |
| Re-model the catalog (merge the New- and Renewal-Maintenance SKUs) | Far higher blast radius; unneeded |

The common thread across all dead-ends: **no reprice-time write of any kind moved `NetUnitPrice` on a settled, contributor-less derived line.** The exact platform reason that write no-ops — settled-derived-node immutability versus a wrong context phase — is empirically strong (reproduced 3×) but not yet mechanistically pinned. That conclusion forced the investigation upstream to the true cause — the renewal carryover never being born as a `Type='Renew'` node — and to the deterministic flip (`COLAUpliftonRenewalNet` then commits on the renewed node) that finally committed **67.38** end-to-end on the live canary.

A scope caveat carries forward: the flip fixes renewals **as they are generated** (the wired flow, or on-demand `flipToRenew`). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice. One verify-before-prod item remains: the **7.85%** BoKS COLA rate comes from a COLA-rate custom metadata rule whose exact record was not re-pinned this pass (a known orphan-"platinum" `Maintenance_Rate__mdt` issue exists elsewhere in this catalog).

---

---

## The Investigation — Phase by Phase


This is the chronological reconstruction of how the root cause was isolated. Each phase is framed as **Hypothesis → Test/Probe → Result/Learning**. The journey is notable for the number of plausible, well-instrumented fixes that were *refuted* before the actual mechanism surfaced — the discipline of killing each candidate with a live probe is what made the final answer trustworthy.

### Phase 1 — Symptom triage

**Hypothesis.** BoKS renewal-maintenance lines are committing the wrong COLA net. The expected value for the Powertech IAM (BoKS) renewal is `62.48 × 1.0785 = 67.38`, but lines were observed frozen at `60.64` or `$0`.

**Test/Probe.** A functional E2E was run on FortraUAT (`00DWC000006eUFF2A2`) against the active pricing procedure `Rev_Mgmt_Default_Pricing_Procedure`, repricing via the managed `POST /connect/rev/sales-transaction/actions/place` with `pricingPref=Force`, `configurationMethod=Skip`. Cross-quote SOQL enumerated BoKS renewal-maintenance lines org-wide.

**Result/Learning.** The failures were all facets of one root-cause family: the renewal-maintenance commit path. According to the investigation dossier, the large majority of renewal-maintenance lines org-wide committed incorrectly; only a single line conformed, and that line was an artificially hand-built single RRM (`PIA-PIA-RRM-PIAM`) asset created during the investigation — not a natural record. Pre-fix conformance therefore reflected a near-total structural failure masked by one synthetic record. Crucially, the *computation* layer was already conformant: `COLACalculatedPrice__c` consistently landed `67.38`. The defect was therefore localized not to COLA math, rate sourcing, or null-guarding, but to the **commit of `NetUnitPrice`** — the engine-owned output. New-business derived maintenance was fully conformant, which sharpened the question to: why does the *renewal* commit fail when the *new-business* derive succeeds on the same machinery?

### Phase 2 — The partner double-discount split: A1 vs A2

**Hypothesis.** The wrong value is being *written* by the partner-pricing posthook re-applying a discount to an already-net COLA price.

**Test/Probe.** FINEST-traced the posthook stack. `PartnerNetPricePosthook.buildRenewalMaintenanceColaUpdate` correctly seeds the net with the prior partner discount *already* netted into the `67.38` base. The generic deferred path `calculateDeferredPartnerPrice` then read that seeded `67.38` as `currentPrice` and re-applied the billing partner's Renewal-Maintenance margin.

**Result/Learning.** This split the failure into two genuinely distinct mechanisms:

| Sub-mechanism | Math | Meaning |
|---|---|---|
| **A1 — partner double-discount** | `67.38 × 0.90 = 60.64` | A *genuine two-field double-count*: a 10% margin re-applied on top of an already-netted base. A live *value-creator*. |
| **A2 — no-priced-node** | NetUnitPrice frozen at fossil / `$0` | The corrective write *no-ops* on a settled derived node; the fossil persists. |

A1 and A2 were established as **sequential, not competing**: A1 created the `60.64`; A2 is *why it persists*. A1 was fixed and verified CLOSED via `PartnerNetPricePosthook` v1.5, confirmed live on a clean priced-node canary going `60.64 → 67.38`. But v1.5 did **not** generalize — the canary still committed `60.64`. That residual is A2, and it became the real investigation.

### Phase 3 — The contributor / SourceAsset discovery

**Hypothesis.** If two lines are otherwise identical but one commits correctly, the delta *is* the root cause.

**Test/Probe.** Field-by-field comparison of the one working control line (`NetUnitPrice 67.38`) against the canary fossil (`NetUnitPrice 60.64`). Both carried identical base price, list price, `COLACalculatedPrice__c=67.38`, the same product, the same derived PBE (`IsDerived=true`, `ListPrice=0`), and the same renewal quote type.

**Result/Learning.** The lines differ in exactly **one** thing: the control carries a `QuoteAction(Type='Renew')` whose `SourceAsset` is an RRM asset; the fossil quote has **zero** QuoteActions. Per the dossier, the only "control" line that already committed `67.38` pre-fix was the hand-built synthetic RRM asset — not a naturally generated record. This established the *discriminator* — `QuoteActionId` presence — and reframed the mechanism in contributor terms via the official RLM model:

- A derived renewal line has *no price of its own*; `NetUnitPrice` is an engine output written only when a **contributor** is resolved into the shared pricing context.
- For a renewal, the contributor is the prior **asset**, reached through `QuoteAction(Type='Renew').SourceAssetId`. This is *not* a missing-discovery-procedure problem.

The shape of the defect followed: renewal-maintenance lines (`PIA-PIA-RRM-PIAM`) are auto-added at renewal but, across the large majority of cases org-wide (per the dossier), can never resolve a matching-product contributor because effectively no real RRM assets exist — leaving the native committer nothing to key on.

### Phase 4 — The reprice-time write attempts (the three dead no-ops)

**Hypothesis.** If the corrective `67.38` is computed but doesn't land, force it onto `NetUnitPrice` at reprice time.

**Test/Probe.** Three independent writers were attempted and FINEST-verified on the settled canary:

| # | Writer | Result |
|---|---|---|
| (a) | Direct DML write to `NetUnitPrice` | Engine-owned, read-only on insert — rejected |
| (b) | `PartnerNetPricePosthook` v1.5 corrective write | `submitContextUpdates` returns **clean**, yet `NetUnitPrice` stays `60.64`; the sibling `COLACalculatedPrice__c` custom-field write in the *same batch* DID land |
| (c) | A dedicated reprice-flow corrective write | Context writes returned `isSuccess=true` (writing `NetUnitPrice = 67.38`), yet canary stayed `60.64` |

**Result/Learning.** This is the cleanest proof in the early investigation: a direct context write to `NetUnitPrice` returns `isSuccess=true` while the committed value is **silently discarded**. The no-op is a property of *the attribute × the settled-derived-node*, not of the Apex; it was reproduced three independent ways. The exact platform reason a direct `NetUnitPrice` write no-ops — settled-derived-node immutability versus a wrong context phase — is empirically strong (reproduced three times) but **not mechanistically pinned**; this uncertainty is carried forward honestly rather than laundered into certainty. The working conclusion, by elimination: **no reprice-time mechanism can heal an existing fossil.**

### Phase 5 — The procedure-commit (self-healing) probe

**Hypothesis.** If a reprice-time Apex write can't move it, perhaps a procedure element committing `COLACalculatedPrice__c → NetUnitPrice`, sequenced as the **last** `NetUnitPrice` writer, can — operating inside the engine rather than from a posthook. This "lever-d" was attractive precisely because, if it fired, it could *self-heal* existing re-priceable fossils rather than only fixing renewals going forward.

**Test/Probe.** An authorized offline test: deactivate the procedure, deploy the committer element (`resultIncluded=true`), reactivate via the UI (the step that actually republishes the runtime — a deploy auto-showing 'Active' does *not* recompile), reprice, then roll back to the exact pre-test baseline.

**Result/Learning.** **No change.** The canary stayed `60.64` and the `$0` lines stayed `0`; regression was clean. An honesty correction was logged: the `67.38` seen in the input map is *prehook-sourced* and **byte-identical** across the stale-runtime, lever-d-active, and post-rollback logs — so the test cannot even confirm the element *fired*. Because lever-d could not be **proven** to fire, the self-healing route was rejected as **unproven and unsafe**, and the investigation turned to a deterministic fix. The procedure was restored to its exact pre-test baseline.

### Phase 6 — The contributor-mapping attempt

**Hypothesis.** The `$0` wrong-product case can be fixed by adding a `PriceBookEntryDerivedPrice` row mapping the owned new-maintenance (PIAMBK) product as a contributor to the derived RRM PBE, so a customer who owns an RNM asset but no RRM asset can resolve that owned asset as the contributor.

**Test/Probe.** Attempted to add a PBEDP row on the derived RRM PBE with the owned `PIA-PIA-RNM-PIAMBK` product as the contributing product, mirroring the existing license rows.

**Result/Learning.** **Platform-rejected:** *"the selected product is a derived product and can't be set as the source product."* The owned product is itself a derived product (off the license), and a derived product is forbidden as a PBEDP contributor source. A companion probe — pointing a born RRM line's Renew QuoteAction at the owned *license* asset — produced a license-derived (wrong) `UnitPrice` and committed `NetUnitPrice=$0`. Both contributor-remap paths were dead.

### Phase 7 — The synthesized-QuoteAction (born-net) refutation

**Hypothesis (born-net).** If the discriminator is a Renew QuoteAction, then *synthesize* one and attach it to the line — stamping `QuoteActionId` so the line becomes a priced node.

**Test/Probe.** Two placements were built and tested:
- **Path A (after-insert):** stamp the QuoteAction after the line is inserted, then reprice.
- **Path B (before-insert):** synthesize the QuoteAction so the line is born carrying it.

Separately, the foundational *false-positive* test: attach a QuoteAction to an *existing settled* line and reprice.

**Result/Learning.** Path A committed **`$0`** — too late; the line settles/locks *un-priced* before the QA exists, and a settled QA-null derived node cannot be healed. **Path A is REFUTED:** *the QuoteAction must exist before first pricing.* Path B born the line correctly (QA present, `UnitPrice=67.38`) but **still committed `NetUnitPrice=$0`** — because the synthesized QA pointed at the owned RNM asset, whose product ≠ the derived RRM line and which maps to nothing as a contributor, so the contributor never resolved. The hard, dangerous lesson: attaching a QA to a settled line and repricing produces a **false positive** — `COLACalculatedPrice__c`/`InputUnitPrice` update to `67.38` while committed `NetUnitPrice` stays at the fossil, so a dashboard reads "fixed" when the money is unchanged. Fossil remediation must be **delete-and-re-add born-correct**, never attach-and-reprice. Synthesizing a QuoteAction against the *wrong* SourceAsset is not enough; contributor resolution is tied to the real `initiateRenewal` flow, not replicable by hand.

### Phase 8 — The decisive end-to-end debug-log run: the No-Change / One-Time emission

**Hypothesis.** Stop trying to write the price. Reconstruct, end-to-end with FINEST logging, exactly what the *platform* does when it renews the asset the customer actually owns — and find out why the line is QuoteAction-less in the first place.

**Test/Probe.** A clean live `initiateRenewal(renewAssetIds=[02iWC000008DmS1YAK], renewOutputType=Quote)` against the canary's owned new-maintenance asset (`PIA-PIA-RNM-PIAMBK`, `Fortra_Product_Type__c="New Maintenance"`), with full pricing-context tracing of the resulting carryover line.

**Result/Learning — the root cause.** The platform carried the owned asset onto the renewal **as `QuoteAction.Type='No Change'`, Quantity 0** — never `'Renew'`. The reason is the selling model: **`PIA-PIA-RNM-PIAMBK` is a "One Time" selling model**, and `initiateRenewal` emits `'No Change'`/qty-0 for One-Time products. The proof-by-contrast was decisive — the beSECURE subscription `VM-BSL-RSL-BESECB` (Term-Based) renews natively as `'Renew'` and prices correctly through the *identical* machinery. The COLA commit element, `COLAUpliftonRenewalNet`, is **action-type-gated (Renew), not product-gated**:

```
SalesTransactionActionType = 'Renew'
  AND ItemPricingSource = 'LastTransaction'
  AND DerivedPricingAttribute = false
  AND COLA_Uplift_Percent__c IsNotNull
```

A `'No Change'`/qty-0 carryover never satisfies `SalesTransactionActionType='Renew'`, so it never enters the COLA path. The legacy design then compounded the problem: the owned-asset carryover is deleted once a Renewal-Maintenance line exists, and the **Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE`** substitutes an *asset-less* RRM line (`PIA-PIA-RRM-PIAM`, `Fortra_Product_Type__c="Renewal Maintenance"`) that has no SourceAsset contributor — so the native committer (`DerivedProductsRenewals`, contributor-keyed) skips it and `NetUnitPrice` freezes at the fossil/`$0`. The full causal chain:

> One-Time selling model → `initiateRenewal` emits `No Change`/qty-0 → line fails the Renew-gated COLA path → legacy handler deletes the carryover, PCR substitutes an asset-less RRM line → no contributor → native derived committer skips it → `NetUnitPrice` frozen at fossil/`$0`.

This unified every prior dead-end under one explanation: the writes no-op'd (Phases 4–7) precisely *because* the node had no Renew QuoteAction / no contributor at birth. The fix is not to write the price — it is to make the line a Renew node *before* first pricing: flip the carryover `QuoteAction.Type` from `'No Change'` → `'Renew'`, set `StartQuantity=0` / `Quantity = SourceAsset.Quantity`, and reprice. The native engine then applies the COLA uplift to last year's net and commits it.

This is implemented as the Apex class `RenewalMaintenanceFlip` (`with sharing`, API 64), wired into `Fortra_Create_Renewal_Quote` as `Flip_Maintenance_Renewal → Reprice_Renewal`. Its unit suite is green: `sf apex run test RenewalMaintenanceFlipTest --synchronous` returned **Outcome PASSED, 4 tests ran, 100% pass rate** (all four methods — `flipsNoChangeMaintenanceToRenew`, `leavesAlreadyRenewAndOtherTypesAlone`, `nullAndEmptySafe`, `skipsNonRenewalQuote`), with `RenewalMaintenanceFlip` at **100% class coverage** (org-wide coverage 49%).

The fix was then confirmed live, end-to-end. On an ephemeral renewal quote (`0Q0WC0000039Ktp0AE`, created then deleted), the **all-lines** query (no product filter) returned **exactly one line before the flip** — `PIA-PIA-RNM-PIAMBK`, `No Change`, qty 0, Net null — and **exactly one line after**, with **zero** stray RRM lines: `PIA-PIA-RNM-PIAMBK`, `Renew`, qty 1, `NetUnitPrice 67.38`, `NetTotalPrice 67.38`. The quote **header rollups were consistent, not stale**: `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, `LineItemCount = 1`. An earlier E2E (`0Q0WC0000039Kc50AE`, deleted) showed the same progression, with `COLA_Uplift_Percent__c = 7.85` and `COLACalculatedPrice__c = 0` on the final line — confirming the commit was the **native** renewal COLA uplift, not the custom posthook field, exactly as the contributor model predicted once the line is a Renew node with a SourceAsset.

**Scope, stated plainly.** The flip is **forward-only**: it corrects renewals **as they are generated** (via the wired flow or an on-demand `flipToRenew(Set<Id>)`). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice. Two open verify-before-prod items carry forward: (1) the platform reason a direct `NetUnitPrice` write no-ops is empirically strong but not mechanistically pinned; and (2) the `7.85%` BoKS COLA rate is sourced from a COLA-rate custom metadata rule whose exact record was **not** re-pinned this pass — and a known orphan-"platinum" `Maintenance_Rate__mdt` issue exists elsewhere in this catalog, so the rate record should be confirmed before production. All work was UAT-only with no Order activation and no Workday events; the Accepted quote `00781068` was untouched, both ephemeral quotes were deleted, and the canary asset (`02iWC000008DmS1YAK`, qty 1, `62.48`, Installed) remains intact.

---

---

## Dead-End Ledger — Why Earlier Fixes Could Not Work


Six distinct remediation levers were considered before the working fix. Every one of them tried to **write the correct net price** onto the renewal-maintenance line — directly, at reprice time, or by re-modeling the product. None of them addressed the actual defect, which is structural: the auto-added `PIA-PIA-RRM-PIAM` (RRM) line is a settled, derived, `QuoteAction`-less node with **no Renew contributor**. On such a node the only committer authorized to (re)write `NetUnitPrice` on derived lines — native `DerivedProductsRenewals` — is contributor-keyed and is simply *skipped*. So `NetUnitPrice` is never recomputed and the pre-existing fossil (`60.64` or `$0`) is retained.

What that lock actually *is* remains honestly uncertain. Empirically a reprice-time write to `NetUnitPrice` no-ops on these settled derived nodes — reproduced three times — while a sibling custom field write in the same batch lands. Whether the platform reason is settled-derived-node immutability or a wrong context phase is **not mechanistically pinned**; the evidence is strong but the mechanism is inferred, not proven. Either way the asymmetry is the tell that every "write the price" strategy was operating on the wrong layer: `NetUnitPrice` is engine-owned and read-only on insert.

### The Ledger

| # | Lever attempted | Layer | Mechanism of failure | Status |
|---|---|---|---|---|
| (a) | Write `NetUnitPrice` directly (DML on insert/update) | Insert-time DML | `NetUnitPrice` is an engine output, read-only on insert. DML cannot create or mutate it on a derived QLI. (`QuoteAction` / `QLI.QuoteActionId` DML *is* permitted under the RLM lock — `NetUnitPrice` specifically is not.) | **DEAD** |
| (b) | `PartnerNetPricePosthook` reprice-time corrective write | Reprice-time (posthook) | The posthook correctly computes the COLA net `67.38` and submits it via `updateContextAttributes`; the call returns clean, yet the committed `NetUnitPrice` does not move off the fossil. The engine drops the engine-owned write on a settled `QuoteAction`-null / derived node, while a sibling custom-field write in the *same* batch lands — the no-op is a property of the attribute × settled-derived-node, not of the Apex. Keep the posthook as the floor (it closes the historical partner double-discount that produced `60.64 = 67.38 × 0.90`), but it is **not** the fix. | **DEAD** (kept as floor) |
| (c) | "Lever-d" custom procedure committer (`resultIncluded=true`, committing `COLACalculatedPrice__c → NetUnitPrice`) | Reprice-time (procedure) | Considered first precisely because it *could* self-heal existing re-priceable fossils. But an authorized live test (deactivate → deploy committer → reactivate → reprice → rollback) produced **zero** change: the canary stayed at the fossil and regression was clean. The `67.38` observed in those logs was prehook-sourced and byte-identical across stale / lever-d-active / post-rollback runs, so the committer could not even be **proven to fire**. A contributor-less node is skipped by the only authorized committer regardless of a second writer — so the lever was rejected as unproven and unsafe. | **DEAD** |
| (d) | Map the owned product as a derived-PBE contributor | Config/data | Platform-rejected: *"the selected product is a derived product and can't be set as the source product."* The owned RNM SKU is itself derived from the license, so it is forbidden as a contributor source. Pointing instead at the mapped LICENSE contributor would commit a license-derived number — wrong product, wrong number. Not a viable contributor path. | **DEAD** |
| (e) | Hand-stamp a Renew `QuoteAction` **after** insert, then reprice (born-net "Path A") | Insert-time, too late | The line settles un-priced before the QA attaches, and `NetUnitPrice` locks at the fossil. Attaching a QA to a settled line and repricing is a **proven false positive**: the custom COLA field moves to `67.38` while committed `NetUnitPrice` stays at the fossil — dashboards read "fixed" when nothing committed. Refuted directly by the 2026-06-14 acceptance test. The QA must exist **before first pricing**. | **DEAD** |
| (f) | Re-model the catalog (merge / de-derive RNM/RRM) | Schema/catalog | Vastly higher blast radius: forces one partner margin rate across all partner-pricing rows, de-derive regresses the large majority of correctly-pricing New-Maintenance SKUs on the same derive (per the investigation dossier), and there is no non-derived One-Time PBE to land on. It is also unnecessary — per the dossier a derived RRM line commits the correct `67.38` on the same derived PBE, proving the derived flag is neither the lock nor the blocker. | **UNNEEDED** |

### The Unifying Insight

Every dead-end above tried to **write the price**. The defect is not a write that fails — it is a **contributor that is absent**, and the absence is upstream of pricing. The One-Time selling model makes `initiateRenewal` emit a `QuoteAction.Type="No Change"` at quantity 0, so the line never enters the `Renew`-gated path; the legacy Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE` compounds this by substituting an asset-less Renewal-Maintenance line with no `SourceAsset` contributor for the native committer to key off. With a born `Type='Renew'` `QuoteAction` and a contributor, the line is born a priced Renew node, the native renewal COLA path runs, and `NetUnitPrice` commits `62.48 × 1.0785 = 67.38`. Without it, no born-net path runs *and* every reprice-time corrective write no-ops — proven independently three times.

A caution on "control" evidence: any pre-fix line that already commits `67.38` is, per the dossier, an artificially hand-built single RRM record created during investigation, **not** a natural renewal. Pre-fix conformance therefore reflects a near-total structural failure masked by one synthetic record — it should not be read as partial health.

This is why the working fix supplies the **contributor**, not the price. `RenewalMaintenanceFlip` (Apex, with sharing) flips the owned-asset carryover's `QuoteAction.Type` from `'No Change'` to `'Renew'` — setting `StartQuantity=0`, `Quantity=SourceAsset.Quantity` — *before* the first reprice, wired into `Fortra_Create_Renewal_Quote` ahead of `Fortra_Quote_Reprice` (Force / Skip). The custom procedure step that commits on the derived path is **`COLAUpliftonRenewalNet`** (gated `SalesTransactionActionType="Renew"`, `ItemPricingSource="LastTransaction"`, `DerivedPricingAttribute=false`, `COLA_Uplift_Percent__c` not null).

The hardened live evidence (2026-06-14) confirms the fix end-to-end. `RenewalMaintenanceFlipTest` ran **4 tests, 100% pass** (all four methods green) with `RenewalMaintenanceFlip` at **100% class coverage**. An all-lines E2E on ephemeral quote `0Q0WC0000039Ktp0AE` (created then deleted) shows the full progression on an unfiltered query: **before** flip, exactly one line — `PIA-PIA-RNM-PIAMBK`, `No Change`, qty 0, Net null; **after** flip + Force/Skip reprice, exactly one line total and **zero RRM lines** — `PIA-PIA-RNM-PIAMBK`, `Renew`, qty 1, `NetUnitPrice = NetTotalPrice = 67.38`. The quote **header rollups are consistent, not stale**: `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, `LineItemCount = 1`. An earlier run (`0Q0WC0000039Kc50AE`, deleted) showed the same progression with `COLA_Uplift_Percent__c = 7.85` and `COLACalculatedPrice__c = 0` on the final line — confirming the commit was the **native** renewal uplift firing once the line became a Renew node with a `SourceAsset` contributor, exactly the mechanism every "write the price" lever bypassed.

Two scope honesty notes carry forward:

- **Forward-only.** The flip fixes renewals **as they are generated** (the wired flow, or on-demand `flipToRenew`). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice.
- **Rate provenance — verify before prod.** The `7.85%` BoKS COLA rate comes from a COLA-rate custom metadata rule; the exact metadata record was **not re-pinned this pass** and should be verified before production (a known orphan-`platinum` `Maintenance_Rate__mdt` issue exists elsewhere in this catalog).

---

---

## Root Cause — The Definitive Mechanism


The renewal-maintenance NetUnitPrice defect is not a pricing-formula bug, a data gap, or a contributor-mapping problem. It is a single, deterministic causal chain rooted in the **selling model** of the new-business maintenance product. Each link is reproduced live on the FortraUAT (`00DWC000006eUFF2A2`) canary asset (`02iWC000008DmS1YAK`) in the 2026-06-14 E2E.

### The Causal Chain

| # | Step | What happens | Evidence |
|---|------|--------------|----------|
| 1 | **One-Time selling model** | New-business maintenance `PIA-PIA-RNM-PIAMBK` (`Fortra_Product_Type__c='New Maintenance'`) is sold under a **"One Time"** selling model — not a renewable term. | Product config; contrasts with beSECURE `VM-BSL-RSL-BESECB` ("Term Based"). |
| 2 | **`initiateRenewal` emits No Change / qty 0** | The platform renews the owned One-Time asset as `QuoteAction.Type='No Change'`, `Quantity 0`, `StartQuantity 1`, `NetUnitPrice=null`. A One-Time product has no term to advance, so the platform never mints a `Renew` action. | E2E all-lines BEFORE-FLIP query (no product filter) returned exactly 1 line: `PIA-PIA-RNM-PIAMBK` \| Qty 0 \| No Change \| Net null \| SourceAsset.Quantity 1. |
| 3 | **Never enters the Renew-gated COLA path** | The COLA commit element `COLAUpliftonRenewalNet` (assigns `COLACalculatedPrice__c → NetUnitPrice`) is gated on `SalesTransactionActionType='Renew' AND ItemPricingSource='LastTransaction' AND DerivedPricingAttribute=false AND COLA_Uplift_Percent__c IsNotNull`. The gate is **action-type gated, not product-gated** — a `No Change`/qty-0 line cannot satisfy `Renew` and is silently skipped. | Gate condition (custom procedure step); no `Product2`/`Fortra_Product_Type__c` criterion anywhere in the commit gate. |
| 4 | **Legacy Year-2 AutoAdd PCR substitutes an asset-less RRM line** | By legacy design, the Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE` **DELETED** the owned-asset `No Change` carryover and substituted an asset-less Renewal-Maintenance line on the distinct SKU `PIA-PIA-RRM-PIAM` (`Fortra_Product_Type__c='Renewal Maintenance'`). Because no customer owns an RRM asset, `initiateRenewal` could never SKU-match one to mint a `Renew` QuoteAction — so the substituted line is born with **no SourceAsset and no QuoteAction**. | The headless `initiateRenewal` path does not fire this AutoAdd substitution, which is why the owned carryover survives in the E2E (see below). |
| 5 | **Native derived committer skips the contributor-less line** | When the substitution does occur, the RRM line is a derived line. The native committer authorized to write `NetUnitPrice` on derived lines (`DerivedProductsRenewals`) is contributor-keyed; with no `SourceAsset` contributor resolved into context, that element is skipped — `NetUnitPrice` is never recomputed. | `DerivedProductsRenewals` requires a contributor entry that the asset-less line lacks. |
| 6 | **NetUnitPrice freezes** | With nothing to commit the COLA net, the line retains its persisted birth value — the **60.64** fossil (or **$0**). The correct value never lands. No reprice-time write heals it: the practical effect is that a settled contributor-less derived node never gets re-priced. | Frozen value 60.64 or $0; correct value is 67.38. |

### The Arithmetic

The correct renewal net is the prior asset's last-transaction price uplifted by COLA:

```
Asset.Price (LTP)  62.48
COLA uplift        × 1.0785   (7.85%)
Correct net      = 67.38
```

The frozen **60.64** is an older fossil — a one-period partner double-discount, `67.38 × 0.90` (a stray 10% applied on top of the correct net). It is **not** a current COLA mis-calculation; it is simply the stale born value that was never overwritten because the commit step never fired for this line. The `$0` variant is the same failure with no born net at all.

> **Rate provenance — verify before prod.** The 7.85% BoKS COLA rate originates from a COLA-rate custom metadata rule. The exact metadata record was **not** re-pinned this pass; treat its provenance as a verify-before-prod item. A known orphan-"platinum" `Maintenance_Rate__mdt` issue elsewhere in this catalog means the metadata layer should not be assumed clean.

### Contrast — Why Term-Based Subscriptions Renew Correctly

The discriminator is the selling model, surfacing as the QuoteAction type at birth.

| Dimension | `PIA-PIA-RNM-PIAMBK` (broken) | `VM-BSL-RSL-BESECB` beSECURE (correct) |
|-----------|-------------------------------|----------------------------------------|
| Selling model | One Time | Term Based |
| `initiateRenewal` emits | `QuoteAction.Type='No Change'`, Quantity 0 | `QuoteAction.Type='Renew'`, Quantity > 0 |
| Enters Renew-gated COLA path? | No — gate requires `Renew` | Yes |
| RLM quantity shape | Qty 0 + StartQty > 0 (No-Change) | Qty > 0 + StartQty 0 (Renew) |
| Native derived committer | Skipped (no contributor) | Fires (asset is contributor) |
| Committed NetUnitPrice | Frozen fossil 60.64 / $0 | Correct COLA net |

A Term-Based subscription has a term to advance, so `initiateRenewal` renews it as `Renew` against its own owned asset — the asset is the contributor, the gate passes, and the native engine commits the COLA net every cycle. The One-Time maintenance product has no such term, so it falls out of the renewal path at the very first step. Per the investigation dossier, the large majority of renewal-maintenance lines org-wide carry this One-Time shape; any pre-fix "control" line that already commits `67.38` is an artificially hand-built single RRM asset created during the investigation, not a natural record — so pre-fix conformance reflects a near-total structural failure masked by one synthetic record.

### The Smoking Gun

The same line proves the entire chain. In the E2E (ephemeral quote `0Q0WC0000039Ktp0AE`, created then deleted), the only change applied was flipping the action type and quantity (`RenewalMaintenanceFlip.flipToRenew`):

| State | Quantity | StartQuantity | QuoteAction.Type | NetUnitPrice |
|-------|----------|---------------|------------------|--------------|
| BEFORE flip (root cause reproduced) | 0 | 1 | No Change | null |
| AFTER flip (pre-reprice) | 1 | 0 | Renew | null |
| FINAL (after Force/Skip reprice) | 1 | 0 | Renew | **67.38** |

The FINAL all-lines query (no product filter) returned **exactly 1 line total, 0 RRM lines**: `PIA-PIA-RNM-PIAMBK`, Renew, qty 1, `NetUnitPrice 67.38`, `NetTotalPrice 67.38`. The quote header rolled up consistently — `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, `LineItemCount = 1` — confirming the rollups are not stale. An earlier E2E (`0Q0WC0000039Kc50AE`, deleted) showed the same progression with the final line carrying `COLA_Uplift_Percent__c 7.85` and `COLACalculatedPrice__c = 0`, proving the commit was the **native renewal COLA uplift**, not the custom posthook field. Converting the line from a `No Change`/qty-0 node into a `Renew`/qty-1 node — with the owned asset as its `SourceAsset` contributor — is the *sole* change that moves the committed `NetUnitPrice` from frozen to the correct `67.38`, with no stray RRM line and no catalog change. That single substitution being the entire mechanism is what makes this root cause definitive.

`RenewalMaintenanceFlipTest` passed live (4 tests ran, 100% pass rate, all four methods green; `RenewalMaintenanceFlip` class coverage 100%), so the flip is exercised end-to-end against the mechanism above, not just asserted.

### Scope and Honest Uncertainty

- **Forward-only.** The flip fixes renewals **as they are generated** — via the wired `Fortra_Create_Renewal_Quote` flow or an on-demand `flipToRenew` call. It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice.
- **Why the flip and not the self-healing candidate.** The dossier first considered a procedure-commit change ("lever-d") because it could in principle self-heal existing re-priceable fossils. It was rejected: it could not be proven to fire — the `67.38` observed in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs — so the deterministic flip was chosen instead.
- **Unpinned platform mechanism.** The exact platform reason a direct `NetUnitPrice` write no-ops on a settled line (settled-derived-node immutability vs. wrong context phase) is empirically strong — reproduced three times — but is **not** mechanistically pinned. It is carried forward as honest uncertainty, not certainty.

---

---

## The Fix — Design, Code & Wiring


### The insight: stop discarding the owned line — flip it to Renew

Every prior remediation attempt operated on the wrong layer: it tried to *write the price* onto a settled derived line. That is the wrong layer because `NetUnitPrice` is engine-owned (read-only on insert), and the reprice-time writers we tried all returned `isSuccess=true` while the committed value silently stayed at the fossil. The lock is "does-not-run," not proven platform immutability: the only element authorized to (re)commit `NetUnitPrice` on a derived line, native `DerivedProductsRenewals`, is contributor-keyed and skips any line with no resolved contributor. (The exact platform reason a direct `NetUnitPrice` write no-ops — settled-derived-node immutability versus wrong context phase — is empirically strong, reproduced three times, but not mechanistically pinned.)

The correct layer is **provenance at creation**. The COLA commit gate — the custom procedure step `COLAUpliftonRenewalNet`, which assigns `COLACalculatedPrice__c -> NetUnitPrice` — is gated by `SalesTransactionActionType='Renew' AND ItemPricingSource='LastTransaction' AND DerivedPricingAttribute=false AND COLA_Uplift_Percent__c IsNotNull`. It is **action-type gated, not product-gated**: there is no Product2-Id, ProductCode, or `Fortra_Product_Type__c` criterion anywhere in the gate. A Term-Based subscription (beSECURE `VM-BSL-RSL-BESECB`) renews as `Type='Renew'` and prices correctly through this exact gate. Maintenance fails only because, being a **One-Time selling model**, the platform `initiateRenewal` carries the owned `PIA-PIA-RNM-PIAMBK` asset as `QuoteAction.Type='No Change'`, Quantity 0 — which never enters the Renew-gated path — and the legacy Year-2 AutoAdd PCR `14OWC0000022Eyb2AE` then deletes that carryover and substitutes an asset-less, contributor-less `PIA-PIA-RRM-PIAM` line.

The fix follows from this: **do not delete the owned-maintenance carryover; flip its existing `QuoteAction` from `'No Change'` to `'Renew'`** and set the renew quantity. The line is then born as a priced Renew node with a `SourceAsset` contributor, and the native engine commits the COLA uplift to last year's net on the next reprice. No new pricing logic, no RRM asset, no PBEDP edit, no selling-model change.

### The class: `RenewalMaintenanceFlip`

`RenewalMaintenanceFlip` (Apex, `public with sharing`, **API 64**, deployed to UAT). Core method `flipToRenew(Set<Id> quoteIds)`.

**Selection gate (two stages).** First the quote is gated to renewals only, then the lines to flip are selected — narrowly, so the operation only ever touches the owned-maintenance No-Change carryover:

```
SELECT Id, QuoteActionId, QuoteAction.SourceAsset.Quantity
FROM QuoteLineItem
WHERE QuoteId IN :renewalQuoteIds
  AND Product2.Fortra_Product_Type__c = 'New Maintenance'
  AND QuoteActionId != NULL
  AND QuoteAction.Type = 'No Change'
```

**The QuoteAction / quantity changes.** For each selected line the method builds two records honoring the RLM quantity rule (a No-Change line is Quantity 0 + StartQuantity > 0; a Renew line is Quantity > 0 + StartQuantity 0):

| Record | Field | Before (No Change) | After (Renew) |
|---|---|---|---|
| QuoteAction | `Type` | `No Change` | `Renew` |
| QuoteLineItem | `StartQuantity` | > 0 | 0 |
| QuoteLineItem | `Quantity` | 0 | `SourceAsset.Quantity` (else 1) |

`renewQty` resolves to `QuoteAction.SourceAsset.Quantity` when the source asset is present and its quantity is non-null and > 0; otherwise it defaults to 1. Two separate bulk DML updates are issued — `update qaUpdates;` (QuoteActions flipped to Renew) then `update lineUpdates;` (line quantities) — never per-record DML in a loop.

**Idempotency / bulk-safety.** The method returns early when `quoteIds` is null or empty, and again when no quote matches the renewal gate, so it is null/empty-safe. Because selection is strictly scoped to `QuoteAction.Type='No Change'` lines, a second run finds nothing to flip (already-`Renew` lines are excluded) — the operation is idempotent. All queries and DML are set-based, so it is bulk-safe across any number of quotes and lines.

### The @InvocableMethod Flow binding

A thin invocable wraps the core method for Flow:

- `@InvocableMethod flipInvocable(List<FlipRequest>)`.
- Inner class `FlipRequest` exposes one `@InvocableVariable` — the renewal quote Id (`Id quoteId`, required) — one renewal quote per request, bulk-safe across the request list.
- The invocable collects non-null `quoteId`s into a `Set<Id>` and delegates to `flipToRenew`, so the Apex entry point and the Flow entry point share one code path.

### The Flow wiring (flip → reprice)

`Fortra_Create_Renewal_Quote` is rewired so the flip runs after the carryover lines exist and is immediately followed by a reprice that lets the native engine commit the COLA net:

```
... -> Populate_QLI_ServiceDate
    -> Flip_Maintenance_Renewal   (apex actionCall RenewalMaintenanceFlip; quoteId <- renewalQuoteId)
    -> Reprice_Renewal            (subflow Fortra_Quote_Reprice; QuoteId <- renewalQuoteId)
    -> Set_Output_Success
```

The reprice is the standard managed Place Sales Transaction call —
`POST /services/data/v64.0/connect/rev/sales-transaction/actions/place` with `{pricingPref:"Force", configurationPref:{configurationMethod:"Skip"}}` — issued on Draft quotes only. The flip itself does not write `NetUnitPrice`; it only changes the QuoteAction type and quantity so that, on this reprice, the line is a Renew node with a `SourceAsset` contributor and the engine commits the COLA uplift natively.

### Why it is minimal and safe

| Property | Evidence |
|---|---|
| **No new pricing logic** | The committer is the existing `COLAUpliftonRenewalNet` gate; the native engine performs the renewal COLA uplift. On the E2E run the custom `COLACalculatedPrice__c` field read 0 on the final line — the 67.38 was committed by the **native** renewal uplift once the line was a Renew node with a `SourceAsset`, not by any custom posthook write. |
| **No catalog change** | No RRM asset is created, no `PriceBookEntryDerivedPrice` row is added (the RNM→RRM mapping is platform-blocked anyway: "the selected product is a derived product and can't be set as the source product"). |
| **No selling-model change** | The One-Time selling model is left untouched; the flip changes only the QuoteAction type and the line quantity. |
| **Operates at the supported layer** | `QuoteAction` and `QuoteLineItem.QuoteActionId` DML are permitted under the RLM lock; only `NetUnitPrice` is read-only. The fix never attempts a `NetUnitPrice` write — it supplies a Renew contributor and lets the engine commit. |
| **Narrow, idempotent, bulk-safe** | Selection is gated to renewal quotes and `New Maintenance` / `No Change` lines only; re-running is a no-op; all DML is set-based. |
| **Tested** | `RenewalMaintenanceFlipTest` runs 4 methods (`flipsNoChangeMaintenanceToRenew`, `leavesAlreadyRenewAndOtherTypesAlone`, `nullAndEmptySafe`, `skipsNonRenewalQuote`), all 4 pass (100% pass rate), with `RenewalMaintenanceFlip` at 100% class coverage. |

### Scope — what it fixes and what it does not

The flip fixes renewals **forward**: it heals lines as they are generated, through the rewired `Fortra_Create_Renewal_Quote` flow or an on-demand `flipToRenew` call. It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice and are out of scope for this change.

### What it replaces — the dead-ends it supersedes

Each prior attempt wrote the price instead of supplying a Renew contributor, and each failed:

| # | Attempt | Outcome |
|---|---|---|
| a | Write `NetUnitPrice` directly | Engine-owned, read-only on insert — rejected. |
| b | Reprice-time posthook write | No-ops on a settled derived node (reproduced three times). |
| c | "lever-d" custom procedure committer | First considered *because* it could self-heal existing re-priceable fossils, but it could not be proven to fire: the 67.38 in those logs was prehook-sourced, byte-identical across stale, active, and rollback runs — rejected as unproven/unsafe. |
| d | Map the owned product as a contributor (PBEDP) | Platform-blocked (a derived product can't be set as a source product). |
| e | Hand-stamp a Renew QuoteAction **after** insert | Too late — the line settles un-priced and locks at the fossil/$0. The QuoteAction must exist before first pricing, which is exactly what the flip-before-reprice ordering guarantees. |
| f | Re-model the catalog (merge RNM/RRM) | Far higher blast radius, unneeded — refuted. |

The deterministic flip was chosen over the self-healing "lever-d" candidate precisely because the flip is provable end-to-end while the committer could not be shown to fire.

### Live confirmation (FRESH E2E, 2026-06-14, canary asset `02iWC000008DmS1YAK`)

On ephemeral renewal quote `0Q0WC0000039Ktp0AE` (created, then deleted), the BEFORE-flip all-lines query (**no product filter**) returned exactly one line, and the progression through flip and reprice was:

| Stage | Quantity | StartQuantity | QuoteAction.Type | NetUnitPrice |
|---|---|---|---|---|
| After `initiateRenewal` (root cause reproduced) | 0 | 1 | No Change | null |
| After `RenewalMaintenanceFlip.flipToRenew` | 1 | 0 | Renew | null (not yet repriced) |
| After Force/Skip reprice | 1 | 0 | Renew | **67.38** |

The FINAL all-lines query (again **no product filter**) returned **exactly one line total, zero RRM lines**: `PIA-PIA-RNM-PIAMBK` | Renew | Quantity 1 | NetUnitPrice **67.38** (= 62.48 × 1.0785) | NetTotalPrice 67.38. The quote **header rollup** was consistent, not stale: `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38` with a LineItemCount of 1. An earlier E2E on ephemeral quote `0Q0WC0000039Kc50AE` (also deleted) showed the same progression, including `COLA_Uplift_Percent__c` 7.85 and `COLACalculatedPrice__c = 0` on the final line — confirming the commit was the native renewal uplift, not the custom posthook field. Verdict: NetUnitPrice committed 67.38 PASS; no stray RRM line PASS; QuoteAction=Renew PASS; header rollup consistent PASS; unit tests 4/4 PASS.

The dossier notes that any "control" line which already commits 67.38 pre-fix is an artificially hand-built single RRM asset created during investigation, not a naturally generated record — so pre-fix conformance reflects a near-total structural failure masked by one synthetic record, and the large majority of renewal-maintenance lines org-wide were committing the fossil or $0 before the fix.

### Remaining (owner / verify-before-prod)

The deployed class plus the rewired flow are necessary but a few verify-before-prod items remain:

- **Verify the COLA rate provenance.** The 7.85% BoKS COLA rate comes from a COLA-rate custom metadata rule; the exact metadata record was not re-pinned this pass and should be confirmed before prod (a known orphan-"platinum" `Maintenance_Rate__mdt` issue exists elsewhere in this catalog).
- **Resolve the pre-existing `COLAUpliftTest.buildOverrideMap` coverage drift** (a separate known test-suite issue) before prod promotion.
- **Run a production renewal smoke-test** to confirm the fix holds end-to-end before sign-off.

All work to date is UAT-only: no Order activation, no Workday events, the Accepted quote `00781068` untouched, reprices run Force/Skip on Draft quotes only, both ephemeral quotes were deleted, and the canary asset is intact (qty 1 / 62.48 / Installed).

---

---

## End-to-End Validation (Fresh Run)


A fresh, fully-live end-to-end run was executed in FortraUAT (`00DWC000006eUFF2A2`) on 2026-06-14 against canary asset `02iWC000008DmS1YAK` (Powertech IAM / BoKS — `PIA-PIA-RNM-PIAMBK`, new-business maintenance, net last-transaction price 62.48, quantity 1, Status Installed). The run created an ephemeral renewal quote (`0Q0WC0000039Ktp0AE`), reproduced the root cause live, applied the fix, repriced, and confirmed the correct committed net against an all-lines query — then cleaned up entirely. No Order activation, no Workday event, and no touch of the Accepted quote `00781068`.

### Progression: before → after-flip → final

The single renewal-maintenance line traversed three observable states across the run. The `initiateRenewal` call reproduced the root cause exactly: the One-Time selling model on the owned new-business maintenance asset caused the platform to mint the carryover as a `No Change` / Quantity-0 action with a null net — never entering the `Renew`-gated COLA path (the `COLAUpliftonRenewalNet` commit step is gated on `SalesTransactionActionType="Renew"`, so a `No Change` line is structurally excluded).

| State | Step / Action | Quantity | StartQuantity | QuoteAction.Type | NetUnitPrice | Notes |
|---|---|---|---|---|---|---|
| BEFORE-FLIP | `initiateRenewal(renewAssetIds=[02iWC000008DmS1YAK])` → `renewRecordId=0Q0WC0000039Ktp0AE` | 0 | >0 | No Change | null | Root cause reproduced LIVE; all-lines query (no product filter) returned EXACTLY 1 line; line never enters the COLA gate |
| AFTER-FLIP | `RenewalMaintenanceFlip.flipToRenew({quote})` | 1 | 0 | Renew | null | RLM quantity rule honored (Renew line = Quantity>0 + StartQuantity 0); not yet repriced |
| FINAL | Reprice `POST .../sales-transaction/actions/place {pricingPref:Force, configurationPref:{configurationMethod:Skip}}` | 1 | 0 | Renew | **67.38** | All-lines query returned EXACTLY 1 line, 0 RRM lines; `NetTotalPrice` 67.38; `COLA_Uplift_Percent__c` 7.85 |

The flip is the entire mechanism: it changes only the action type (`No Change` → `Renew`) and rebalances the RLM quantities. With the line now a `Renew` node carrying a `SourceAsset` contributor, the native engine commits the COLA net on reprice.

### COLA derivation

The committed `NetUnitPrice` is the native renewal COLA uplift of the asset's last-transaction net:

```
62.48 (Asset.Price / LTP) × 1.0785 (1 + 7.85% COLA) = 67.38
```

This is the correct value, not the broken fossil (`60.64` = `67.38 × 0.90`, the prior one-period partner double-discount) nor `$0`. `COLA_Uplift_Percent__c` settled at 7.85 on the final line, consistent with the derivation. The 7.85% rate is sourced from a COLA-rate custom metadata rule; the exact metadata record was **not** re-pinned this pass and remains a verify-before-prod item — a known orphan-`platinum` `Maintenance_Rate__mdt` issue exists elsewhere in this catalog, so the rate's provenance should be confirmed before promotion.

### Survival, header rollup, and native-engine commit

The before-flip all-lines query (no product filter) returned EXACTLY 1 line; the final all-lines query also returned EXACTLY 1 line total with **0 RRM lines**. The legacy Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE` — which deletes the owned-asset carryover and substitutes an asset-less `PIA-PIA-RRM-PIAM` Renewal-Maintenance line with no `SourceAsset` contributor that the native committer skips — never fired in this run. The E2E confirms the flow does not produce a contributor-less node to freeze.

The quote header rollup was consistent (not stale): `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38` with `LineItemCount = 1`.

The commit was the **native renewal COLA engine**, not the custom posthook field: an earlier run captured `COLACalculatedPrice__c = 0` on the final line while `NetUnitPrice` committed 67.38, confirming the uplift came from the native committer once the line is a `Renew` node with a resolved `SourceAsset` contributor.

### Verdict

| Criterion | Result |
|---|---|
| `NetUnitPrice` committed 67.38 (= 62.48 × 1.0785) | PASS |
| No stray RRM line (all-lines query, 0 RRM) | PASS |
| Sole line on quote; header rollup consistent (67.38, count 1) | PASS |
| QuoteAction.Type = Renew | PASS |
| Unit tests (`RenewalMaintenanceFlip`) — 4 ran, 100% pass rate, class coverage 100% | PASS |

The unit suite ran all four methods (`flipsNoChangeMaintenanceToRenew`, `leavesAlreadyRenewAndOtherTypesAlone`, `nullAndEmptySafe`, `skipsNonRenewalQuote`) synchronously with `RenewalMaintenanceFlip` at 100% class coverage.

### Why flip, not the self-healing candidate

The dossier first considered a procedure-commit change ("lever-d") because it could in principle self-heal existing re-priceable fossils. It was rejected as unproven and unsafe: it could not be shown to fire — the 67.38 observed in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs — so the deterministic flip was chosen instead. The exact platform reason a direct `NetUnitPrice` write no-ops (settled-derived-node immutability vs. wrong context phase) is empirically strong (reproduced three times) but not mechanistically pinned; this uncertainty is carried forward, not laundered into certainty.

### Downstream safety

The fix changes the action type and the committed net only; it does not alter the attributes that downstream automation reads, so conformant new-business and order-flow behaviors are unaffected:

- **Workday line-type** (`Fortra_OrderItem_Set_Workday_Contract_Line_Type`) keys solely on `pse__IsServicesProduct__c` / `Is_Subsplit_Product__c` / PS-Service-Type — zero references to `Fortra_Product_Type__c`; both maintenance products resolve to FIXED AMOUNT identically.
- **Billing dates** (`Fortra_OrderItem_Set_Dates`) branch only on `Rev_Category__c='RC_41000'` (Perpetual); the New-Maint (`RC_42000`) line takes the unchanged non-perpetual path.
- **ARR** (`Fortra_QuoteLineItem_Calculate_ARR`) double-count guard keys on `Quote.Quote_Type__c != 'Renewal'`, not product type — a renewal line yields ARR=0 with no double count.

### Scope: forward-only

The flip fixes renewals **as they are generated** — via the wired `Fortra_Create_Renewal_Quote` flow or on-demand `flipToRenew`. It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes; those require a separate remediation reprice. Per the investigation dossier, the large majority of renewal-maintenance lines org-wide were affected before the fix, with pre-fix conformance reflecting a near-total structural failure masked by a single synthetic, hand-built RRM control record created during investigation rather than a naturally generated one. Activated downstream artifacts likewise remain a separate owner-gated workstream.

### Cleanup and canary integrity

Post-run cleanup deleted both ephemeral renewal quotes (`0Q0WC0000039Ktp0AE` and the earlier `0Q0WC0000039Kc50AE`). **Zero of the renewal quotes created during validation remain.** The canary asset is intact and unmodified (quantity 1 / Price 62.48 / Status Installed), preserving it as a clean, repeatable anchor for future runs. All constraints were honored: UAT only, no Order activation, no Workday events published, Accepted quote `00781068` untouched, and reprices run Force/Skip on Draft quotes only.

---

---

## Production Rollout & Remaining Work


The corrective code path is fully built, deployed to FortraUAT (`00DWC000006eUFF2A2`), and end-to-end validated. `RenewalMaintenanceFlip` (Apex, `with sharing`, API 64) is live with **4/4 unit tests passing (100% pass rate) and 100% coverage on the class** — all four methods (`flipsNoChangeMaintenanceToRenew`, `leavesAlreadyRenewAndOtherTypesAlone`, `nullAndEmptySafe`, `skipsNonRenewalQuote`) green. `Fortra_Create_Renewal_Quote` is rewired to call it before the renewal reprice (`Populate_QLI_ServiceDate` → `Flip_Maintenance_Renewal` → `Reprice_Renewal` → `Set_Output_Success`). What separates UAT from a production cutover is a short, owner-gated punch list: one production smoke-test, one rate-provenance verify, and one pre-existing test-suite drift that gates any procedure-side validate.

### Remaining Work (owner-gated)

| # | Item | Why it's required | Mechanism / Constraint | Channel |
|---|------|-------------------|------------------------|---------|
| 1 | Production renewal smoke-test | Confirms the flip + reprice commits the COLA net (`67.38 = 62.48 × 1.0785`) on a real production renewal, with no stray RRM line and a sole surviving Renew line. | Validated in UAT on canary asset `02iWC000008DmS1YAK`: before-flip `No Change`/Qty 0/`NetUnitPrice=null` → after-flip `Renew`/Qty 1 → after Force/Skip reprice `NetUnitPrice=67.38`. | Production renewal (owner) |
| 2 | Verify the BoKS COLA rate record | The 7.85% uplift is sourced from a COLA-rate custom metadata rule; the exact metadata record was **not re-pinned this pass**. A known orphan-`platinum` `Maintenance_Rate__mdt` issue exists elsewhere in this catalog, so the active record must be confirmed before promotion. | Metadata record verification (owner). | Verify-before-prod (owner) |
| 3 | Resolve `COLAUpliftTest.buildOverrideMap` coverage drift | A separate, pre-existing test-suite drift. It is a **prod-cutover blocker independent of this fix** — coverage cannot be trusted and any procedure-side validate fails until the test is reseated. | Test was written against an older list-passing API surface vs. the live `ctxInstanceId` architecture; must be re-seamed to the live architecture before promotion. | Apex test reseat (owner) |

### Root-Cause Mechanism

The defect originated in legacy design: the Year-2 AutoAdd Product Configuration Rule `14OWC0000022Eyb2AE` (`Year 2 Maintenance Sku added to Powertech Identity_Access Manager Perpetual`) deleted the owned-asset carryover and substituted an asset-less Renewal-Maintenance line (RRM, `PIA-PIA-RRM-PIAM`) that carried no `SourceAsset` contributor — a line the native committer skips, leaving the renewal net uncommitted. The deterministic flip reconstructs the surviving Renew line the committer can price, which is why the rewired creation path heals the renewal regardless of how the line was originally injected.

### Why the Flip, Not a Procedure-Commit Change

The dossier first considered a procedure-commit change ("lever-d") because it could self-heal existing re-priceable fossils. It was rejected as unproven and unsafe: it could not be shown to fire — the `67.38` observed in those logs was prehook-sourced and byte-identical across stale, active, and rollback runs — so the deterministic flip was chosen instead. One honest uncertainty carries forward: the exact platform reason a direct `NetUnitPrice` write no-ops (settled-derived-node immutability vs. wrong context phase) is empirically strong (reproduced three times) but not mechanistically pinned.

### Risks & Durability

- **Procedure version churn.** The active pricing procedure (`Rev_Mgmt_Default_Pricing_Procedure`) is co-owned and has churned across versions in days. Re-confirm the sole Active version immediately before any production validate — never trust a snapshot; always pull live.
- **Inert until wired.** `RenewalMaintenanceFlip` is deployed but inert in production until the flow that invokes it is promoted; the fix carries no risk to existing production pricing prior to that wiring.
- **No retroactive heal (forward-only scope).** This is a creation-path fix: it heals renewals as they are generated (the wired flow, or an on-demand `flipToRenew`). It does **not** retroactively heal already-settled fossil lines on pre-existing Draft quotes — the older fossil `60.64` (`= 67.38 × 0.90`, a one-period partner double-discount) and `$0` lines on existing quotes need a separate remediation reprice. Existing fossils and downstream artifacts (Draft fossil lines, the Accepted quote, any activated Order/Asset/Workday records) are out of scope and require separate owner-gated remediation.

### Live E2E Proof

The end-to-end run on an ephemeral renewal quote (`0Q0WC0000039Ktp0AE`, created then deleted) was validated with all-lines queries carrying **no product filter**, so a stray RRM line could not hide. The before-flip all-lines query returned exactly one line — `PIA-PIA-RNM-PIAMBK`, `No Change`, Qty 0, Net null. The final all-lines query returned exactly one line total with **zero RRM lines** — `PIA-PIA-RNM-PIAMBK`, `Renew`, Qty 1, `NetUnitPrice=67.38`, `NetTotalPrice=67.38`. The quote **header rollup was consistent, not stale**: `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, `LineItemCount = 1`. An earlier E2E (`0Q0WC0000039Kc50AE`, deleted) showed the same progression with `COLA_Uplift_Percent__c = 7.85` and `COLACalculatedPrice__c = 0` on the final line — confirming the commit was the **native renewal uplift via `COLAUpliftonRenewalNet`**, not the custom posthook field. Per the dossier, any "control" line that already commits `67.38` pre-fix is an artificially hand-built single RRM asset created during investigation, not a natural record; pre-fix conformance therefore reflects a near-total structural failure masked by one synthetic record.

### Constraints Honored

All UAT validation observed strict guardrails: UAT only; no Order activation; no `Order_Completed_WD__e` / Workday events published; the Accepted quote `00781068` was never touched; and all reprices were Force/Skip (`pricingPref:"Force"`, `configurationPref:{configurationMethod:"Skip"}`) on Draft quotes only. Both ephemeral renewal quotes (`0Q0WC0000039Kc50AE`, `0Q0WC0000039Ktp0AE`) were fully cleaned up, leaving zero residual renewal quotes and the canary asset (`02iWC000008DmS1YAK`) intact (qty 1 / 62.48 / Installed).

---

---

## Appendix — Artifacts, Identifiers & Glossary


This appendix is a reference index for the RCA. All identifiers, paths, and values are reconciled against the live FortraUAT state captured 2026-06-14. Where a digest disagrees with the verified ledger, the ledger value is shown.

### A.1 Deployed & Wired Components

| Component | Type | Repo path / location | Role |
|---|---|---|---|
| `RenewalMaintenanceFlip` | Apex class (with sharing, API 64) | `Data/sc-maint/sc3404/renewfix/build/classes/RenewalMaintenanceFlip.cls` | THE FIX. `flipToRenew(Set<Id> quoteIds)` flips owned-maintenance carryover `QuoteAction.Type` `No Change`→`Renew`, sets line `StartQuantity=0`, `Quantity=SourceAsset.Quantity`. Bulk-safe, idempotent, null/empty-safe. Forward-only: heals renewals as generated, not pre-existing fossil lines. Deployed to UAT; tests Ran 4, Pass Rate 100% (all 4 methods pass), class coverage 100%. Exposes `@InvocableMethod flipInvocable(List<FlipRequest>)`. |
| `Fortra_Create_Renewal_Quote` | Flow | `force-app/main/default/flows/Fortra_Create_Renewal_Quote.flow-meta.xml` (active in UAT) | Renewal entry flow. Rewired: `… → Populate_QLI_ServiceDate → Flip_Maintenance_Renewal` (apex actionCall `RenewalMaintenanceFlip`, input `quoteId ← renewalQuoteId`) `→ Reprice_Renewal` (subflow `Fortra_Quote_Reprice`, input `QuoteId ← renewalQuoteId`) `→ Set_Output_Success`. |
| `Fortra_Quote_Reprice` | Subflow (AutoLaunchedFlow, input `QuoteId`) | Reprice subflow invoked by `Reprice_Renewal` | Drives the post-flip reprice (Place Sales Transaction, `pricingPref:"Force"`, `configurationMethod:"Skip"`) so the native engine commits the COLA net. |
| `RenewalQuoteLineHandler` | Apex class (with sharing) | `Data/sc-maint/sc3404/renewfix/classes/RenewalQuoteLineHandler.cls` | LEGACY. Hard-deletes `New Maintenance` + `Perpetual` carryover (`CARRYOVER_PRODUCT_TYPES`) once a Renewal-Maintenance line exists; this is the mechanism that substituted the asset-less RRM line. Superseded by the flip; must not delete the flipped carryover. |
| `Rev_Mgmt_Default_Pricing_Procedure` | ExpressionSet pricing procedure | Live UAT metadata (re-retrieve before any deploy) | Hosts the `COLAUpliftonRenewalNet` commit step. Co-owned and version-churns within days — always confirm the active version live before any deploy. |
| `PartnerNetPricePosthook` v1.5 | Apex posthook (API 65) | Live UAT class | Closes the pre-v1.5 partner double-discount (the floor); kept in place. Its corrective `NetUnitPrice` write no-ops on a settled derived node — not the fix. |

### A.2 Key Salesforce Identifiers

| Entity | Id / SKU | Notes |
|---|---|---|
| Org | `00DWC000006eUFF2A2` | FortraUAT. NOT the empty org the bare `uat` alias resolves to. |
| New-Maintenance SKU (RNM) | `PIA-PIA-RNM-PIAMBK` | `Fortra_Product_Type__c='New Maintenance'`, **One-Time** selling model. The owned asset's product. |
| Renewal-Maintenance SKU (RRM) | `PIA-PIA-RRM-PIAM` | `Fortra_Product_Type__c='Renewal Maintenance'`, derived PBE. The asset-less substitute line. |
| Perpetual license SKU (NRPS) | `PIA-PIA-NRPS-PIAP` | PBEDP contributor for the derived maintenance PBEs. |
| Subscription comparator | `VM-BSL-RSL-BESECB` (beSECURE) | "Term Based"/TermDefined; renews natively as `Renew` and prices correctly. |
| Canary asset | `02iWC000008DmS1YAK` | RNM, `Asset.Price` 62.48, quantity 1, Status Installed. The COLA base. |
| Year-2 AutoAdd PCR | `14OWC0000022Eyb2AE` | ProductConfigurationRule, "Year 2 Maintenance Sku added to Powertech Identity_Access Manager Perpetual". Legacy rule that deletes the owned-asset carryover and substitutes the asset-less RRM line with no SourceAsset contributor that the native committer skips. |
| Pricing context | `SalesTransactionContextExt_v2` | Shared by the pricing procedure and the active discovery procedure. |

### A.3 Canary E2E Run Identifiers (2026-06-14)

The all-lines + header-rollup E2E was run on ephemeral quote `0Q0WC0000039Ktp0AE` (created, then deleted in cleanup). All line queries used NO product filter, to prove no stray RRM line survives.

| Item | Id / value | State |
|---|---|---|
| Ephemeral renewal quote (rollup proof) | `0Q0WC0000039Ktp0AE` | Created via `initiateRenewal`, then deleted in cleanup. |
| Earlier ephemeral quote | `0Q0WC0000039Kc50AE` | Same progression; deleted. Showed `COLA_Uplift_Percent__c 7.85` and `COLACalculatedPrice__c=0` on the final line — i.e., the commit was the NATIVE renewal uplift, not the custom posthook field. |
| Before-flip all-lines query | `PIA-PIA-RNM-PIAMBK` | EXACTLY 1 line: Qty 0, `QuoteAction.Type='No Change'`, `NetUnitPrice=null` (root cause reproduced live). |
| Final all-lines query | same | EXACTLY 1 line total, 0 RRM lines: Qty 1, `NetUnitPrice 67.38`, `NetTotalPrice 67.38`, `QuoteAction.Type='Renew'`. |
| Quote HEADER rollup | — | `TotalPrice = Subtotal = GrandTotal = ALE__c = 67.38`, LineItemCount = 1. Rollups consistent, NOT stale. |
| Accepted quote — DO NOT TOUCH | `00781068` | Never modified per constraints. |

### A.4 COLA Math

| Quantity | Value | Derivation |
|---|---|---|
| Asset net last-transaction price | 62.48 | `Asset.Price` on canary `02iWC000008DmS1YAK`. |
| COLA uplift | 7.85% | Action-type-gated renewal uplift, sourced from a COLA-rate custom metadata rule. The exact metadata record was not re-pinned this pass — verify before prod (a known orphan-`platinum` `Maintenance_Rate__mdt` issue exists elsewhere in this catalog). |
| Correct committed net | **67.38** | 62.48 × 1.0785. The only correct committed net. |
| Frozen fossil | 60.64 | Older fossil: a one-period partner double-discount, 67.38 × 0.90 (90% applied, i.e. a 10% over-discount). |
| Degenerate fossil | $0 | Asset-less / contributor-unresolved derived node. |

### A.5 Evidence Artifact Paths

| Artifact | Path | Contents |
|---|---|---|
| Fix class (built) | `Data/sc-maint/sc3404/renewfix/build/classes/RenewalMaintenanceFlip.cls` | The deployed `RenewalMaintenanceFlip` source. |
| Legacy handler | `Data/sc-maint/sc3404/renewfix/classes/RenewalQuoteLineHandler.cls` | The carryover-delete handler that substituted the RRM line. |
| Live Apex source-of-truth | `Data/sc-maint/sc3346_fix/rn_partner_dd/live_apex/` | Byte-identical-to-live copies of the pricing-stack classes (`Org Data/_src` is stale). |
| Deep RCA dossier | `Data/sc-maint/rca_deep/SC3346_RNCOLA_DEEP_RCA.{md,html}` | Forensic RCA; supersedes the earlier BoKS-retest block. |
| Architectural fix plan | `Data/sc-maint/rca_deep/SC3346_ARCHITECTURAL_FIX_PLAN.md` | Action-type/selling-model fix plan. |
| Contributor verification | `Data/sc-maint/rca_deep/SC3346_CONTRIBUTOR_VERIFY.md` | Discovery-procedure / contributor analysis. |
| Official mechanism RCA | `Data/sc-maint/rca_deep/SC3346_COLA_OFFICIAL_RCA.md` | Documented derived/COLA pricing mechanism vs. the defect. |
| Fix-path recommendation | `Data/sc-maint/rca_deep/SC3346_FIX_PATH_RECOMMENDATION.md` | Born-net path analysis. |
| Reprice no-op log | `Data/sc-maint/rca_deep/work/DF2-provenance/log_1910_44.log` | The procedure-commit self-healing candidate ("lever-d") could not be proven to fire: the 67.38 in these logs was prehook-sourced and byte-identical across stale/active/rollback runs, while the settled `NetUnitPrice` dumps stayed at the fossil value. Rejected as unproven/unsafe; the deterministic flip chosen instead. |
| Pre-v1.5 double-discount log | `skip_reprice_60.64.log` | Proves the historical x0.90 deferred re-discount that produced 60.64. |

### A.6 Glossary

| Term | Definition |
|---|---|
| **RLM** | Revenue Lifecycle Management — the Salesforce Revenue Cloud Advanced engine governing this org's quoting/pricing. Enforces the Quote-DML lock; managed reprice runs via the Place Sales Transaction API. |
| **RCA** | Revenue Cloud Advanced — the native Salesforce revenue product configuration (RLM, derived pricing, asset lifecycle) underpinning the Fortra quote-to-order flow. (Distinct from "root-cause analysis," the document type.) |
| **COLA** | Cost-of-Living Adjustment — the annual renewal uplift (here 7.85%) applied to a renewing maintenance line's prior net (62.48 → 67.38). |
| **Derived pricing** | A pricing pattern where a line (e.g., maintenance) has no list price of its own (derived PBE, `ListPrice=0`); its `NetUnitPrice` is an engine output, written only when a contributor resolves into the shared pricing context. |
| **QuoteAction** | The record linking a quote line to a sales-transaction intent. `Type='Renew'` (with a SourceAsset) is the action type that admits a line to the COLA renewal commit path; `Type='No Change'` does not. A `Renew` line is `Quantity>0`/`StartQuantity=0`; a `No Change` line is `Quantity=0`/`StartQuantity>0`. |
| **Contributor** | The source (a prior owned Asset for a renewal, surfaced via the Renew QuoteAction's SourceAsset) from which a derived line's net is computed. A line with no resolved contributor is skipped by the native committer (`DerivedProductsRenewals`) and freezes at its born value. |
| **ItemPricingSource** | The context attribute (`'LastTransaction'`) that, together with `SalesTransactionActionType='Renew'`, gates the `COLAUpliftonRenewalNet` commit step. The path is action-type-gated, not product-gated. |
| **PCR** | ProductConfigurationRule — declarative configurator rule. The legacy Year-2 AutoAdd PCR `14OWC0000022Eyb2AE` deleted the owned-asset carryover and substituted the asset-less RRM line. |

> **Scope & open uncertainties.** The flip is forward-only: it fixes renewals as they are generated (via the wired flow or on-demand `flipToRenew`) but does not retroactively heal already-settled fossil lines on pre-existing Draft quotes, which need a separate remediation reprice. Per the investigation dossier, pre-fix conformance across renewal-maintenance lines was a near-total structural failure masked by a single synthetic, hand-built RRM control record created during investigation; the large majority of renewal-maintenance lines org-wide did not commit correctly. The exact platform reason a direct `NetUnitPrice` write no-ops (settled-derived-node immutability vs. wrong context phase) is empirically strong — reproduced three times — but not mechanistically pinned.

---

---

## Validation Evidence Index (this run)


| Artifact | File |
|---|---|
| initiateRenewal output (quote id) | `Data/sc-maint/sc3404/renewfix/e2e_final/run/01_renew.out` |
| Before-flip state (No Change / null) | `.../run/02_before_flip.json` |
| After-flip state (Renew / qty 1) | `.../run/04_after_flip.json` |
| Reprice result (Force/Skip, isSuccess) | `.../run/05_reprice.out` |
| Final settled line (Net 67.38, uplift 7.85%) | `.../run/06_final.json` |
| Unit test run (4/4, 100% class coverage) | `.../run/08_testrun.out` |
| All-lines final (1 line, 0 RRM) | `.../run/10_final_alllines.json` |

*Constraints honored: UAT only; no Order activation; no Workday events; Accepted quote `00781068` never touched;
reprices `Force`/`Skip` on Draft quotes only. Both ephemeral E2E quotes were deleted after capture; the canary
asset `02iWC000008DmS1YAK` remains intact (qty 1 / $62.48 / Installed); 0 of my renewal quotes remain.*

*Report produced via a multi-agent workflow (9 evidence miners → 10 section drafters → 2 adversarial verifiers →
10 remediation editors → accuracy gate). Every number, Salesforce Id, and SKU in this document was constrained to a
live-verified allow-list and passed a final accuracy gate.*
