# Fortra Approvals — Solution Design Document (KB)

> **Source**: `Fortra_Approvals_Solution_Design_Document.txt`
> **Doc date**: 4/9/2026 · **Submitted by**: Aaron Broom · **Confidentiality footer**: "COASTAL CONFIDENTIAL AND PROPRIETARY - 20240405"
> **Domain**: Salesforce Revenue Cloud Advanced (RCA) — Quote/Order Approvals
> **Title**: "Approvals Solution Design Document"
> **One-line purpose**: Transform the traditional sequential quote-approval process into a multi-dimensional, flow-based orchestration that evaluates approval requirements at the **line**, **bundle**, and **quote** levels simultaneously, using Revenue Cloud flow-based approval orchestration plus "Smart Approval" features, while enforcing the **Tech** and **Cyber** business-unit approval matrices.

---

## ⚠️ Fidelity / completeness warning (READ FIRST)

This source document is a **high-level conceptual/marketing-style design narrative**, NOT a build spec. It contains **NO**:
- custom object or field definitions (no API names, no data types, no formulas)
- Apex class / trigger / flow / prehook names
- rounding modes, tier thresholds, numeric discount percentages, or precedence rules
- integration endpoint/sequence specifics

The concrete approval-matrix numbers (Tech and Cyber discount thresholds) are **explicitly delegated to an external artifact**, not stated inline:
> "Please reference **Fortra Approval Matrix - Google Sheets** for Tech and Cyber Approvals noted on the tabs at the bottom."

Any engineer implementing this MUST retrieve the actual thresholds, object model, and flow definitions from that Google Sheet and from the live org — they are **not** in this document. Do not invent them. Everything below is faithful to the source; where the source is silent, this KB says so.

---

## Executive summary

The approval solution replaces a single sequential approval chain with an "intelligent, multi-dimensional system" that:
- Evaluates approval requirements at **line, bundle, and quote levels simultaneously**.
- Uses **Revenue Cloud flow-based approval orchestration** combined with **Smart Approval** features.
- Aims to **reduce approval cycle times** while maintaining compliance with **both Tech and Cyber business-unit approval matrices**.
- Enables **partial approvals**: individual line items can be **rejected without requiring complete quote resubmission** — the stated goal is improved sales velocity and customer experience.

---

## Business requirements / rules

1. **Multi-level evaluation is mandatory**: every submission is evaluated at three distinct levels (line, bundle, quote), each with its own criteria and routing logic.
2. **Partial approval / partial rejection**: individual lines can be rejected without forcing a full quote resubmission. (This is the headline behavioral requirement.)
3. **Two business-unit matrices must both be honored**: **Tech** and **Cyber**. Each has its own discount thresholds that trigger approvals at different organizational levels. Actual threshold values live in the external "Fortra Approval Matrix" Google Sheet (Tech and Cyber on separate tabs).
4. **Tech BU rule (verbatim intent)**: "The Tech business unit maintains specific discount thresholds that trigger approval requirements at different organizational levels." Thresholds "ensure proper oversight while empowering sales teams to operate efficiently within defined parameters." (Numbers not given here.)
5. **Special-scenario validation** at the quote level must cover, by name: **MYCAP** and **Displaced ARR** (see Flow step 4). These are called out as special scenarios requiring validation but the rules are not specified in this doc.
6. **Pre-submission validation**: sales reps must get real-time alerts for approval triggers before submitting.

---

## Data model

**None specified.** The source names no custom objects, no fields, no types, and no formulas. It references generic Salesforce/Revenue Cloud concepts only:
- **Quote / quote line items** (the objects being approved) — standard RCA quoting entities, not defined here.
- **Bundle / bundle components** ("component dependencies", "aggregates component approvals") — implies product-bundle structure but no object/field named.
- **Approval work items** ("Creates approval work items") — implied work-item records, not defined.
- **Platform Events** used for real-time notifications (see Components) — no event object API name given.

> If building this, the data model (objects, fields, types, formulas) must be sourced from the live org / the Google Sheet matrix, not this document.

---

## Architecture components

From the "Approval Architecture Components" table (Component / Purpose / Key Features), verbatim:

| Component | Purpose | Key Features |
|---|---|---|
| **Flow Orchestration Engine** | Core approval orchestration | Visual process builder, conditional branching, parallel processing |
| **Smart Approval Rules** | Intelligent routing logic | AI-based predictions, historical analysis, dynamic assignment |
| **Approval Matrix Configuration** | Business unit specific rules | Tech and Cyber matrices, discount thresholds, special scenarios |
| **Work Guide Interface** | Unified approver experience | Centralized dashboard, mobile support, bulk actions |
| **Platform Events** | Real-time notifications | Instant alerts, status updates, integration triggers |

> These are described as **integrated components working together**; each serves a specific purpose "from initial trigger evaluation through final approval notification." No concrete implementation names (flow API names, event names, LWC names) are provided.

---

## Business logic — Multi-level approval evaluation

From the "Multi-Level Approval Evaluation" table (Approval Level / Trigger Criteria / Evaluation Scope / Processing Mode), verbatim:

| Approval Level | Trigger Criteria | Evaluation Scope | Processing Mode |
|---|---|---|---|
| **Line Level** | Individual product discounts, Special terms | Each quote line independently | **Parallel evaluation** |
| **Bundle Level** | Bundle discount thresholds, Component dependencies | All lines within a bundle | **Sequential after line approval** |
| **Quote Level** | Total value, Payment terms, Contract type | Entire quote aggregate | **Final validation step** |

**Ordering / precedence rule (load-bearing):**
- Line-level approvals run **in parallel** (independent, to prevent bottlenecks).
- Bundle-level evaluation runs **sequentially AFTER line approval** and **aggregates component approvals**.
- Quote-level is the **FINAL validation step** (runs last, after line and bundle).

> No numeric thresholds, rounding modes, or tie-break rules are specified. "Bundle discount thresholds" and "discount thresholds" reference the external matrix.

---

## Approval flow process (orchestration steps, verbatim)

**Flow Orchestration Steps:**

1. **Initial Evaluation**
   - Quote submission triggers flow orchestration
   - System evaluates all line items against approval matrix
   - Identifies required approval levels and approvers
   - Creates approval work items

2. **Parallel Processing**
   - Line-level approvals execute simultaneously
   - Independent evaluation prevents bottlenecks
   - Smart routing based on product type and discount

3. **Bundle Consolidation**
   - After line approvals, bundle-level evaluation
   - Aggregates component approvals
   - Applies bundle-specific business rules

4. **Quote Validation**
   - Final quote-level checks
   - Total value thresholds
   - **Special scenario validation (MYCAP, Displaced ARR)**

5. **Smart Approval Features**
   - AI-powered approval predictions
   - Historical pattern matching
   - Suggested approver recommendations
   - Automatic escalation for time-sensitive deals

> **Sequence is fixed**: submission → (1) evaluate all lines vs matrix → (2) parallel line approvals → (3) bundle consolidation aggregating component approvals → (4) final quote-level checks incl. MYCAP/Displaced ARR → (5) smart features layered on (predictions/escalation). The trigger is **quote submission**.

---

## Integration points & sequence

- **Trigger source**: Quote submission triggers the flow orchestration (step 1).
- **Platform Events**: used for real-time notifications — "Instant alerts, status updates, **integration triggers**." Implies downstream integrations fire off platform events, but **no event API names, payloads, or subscriber systems are named**.
- **External artifact dependency**: the **Fortra Approval Matrix Google Sheet** (Tech tab + Cyber tab) is the authoritative source of thresholds — an integration/config dependency, not an inline spec.
- No Workday, Mule, or other named external system integration is described in this document.

---

## Approver / Sales-rep user experience

**Sales Representative Experience — Key Features (verbatim):**
- **Pre-Submission Validation**: Real-time alerts for approval triggers
- **Status Dashboard**: Visual approval progress tracking
- **Smart Notifications**: Alerts for required actions or updates
- **Approval History**: Access to previous approval patterns
- **Guidance Text**: Context-sensitive help for approval requirements

**Approver Experience** — unified **Work Guide interface** consolidating all pending approvals. From the Feature / Benefit table, verbatim:

| Feature | Benefit |
|---|---|
| **Unified Work Queue** | All approvals in one place with priority sorting |
| **Context Panel** | Complete quote details without navigation |
| **Comparison Tools** | Side-by-side analysis with similar deals |
| **Bulk Actions** | Approve/reject multiple items simultaneously |
| **Delegation Options** | Easy reassignment with audit trail |
| **Mobile Optimization** | Full functionality on mobile devices |
| **Analytics Integration** | Personal approval metrics and trends |

---

## Assumptions / dependencies / open issues

- **Dependency (hard)**: Actual approval thresholds for **Tech** and **Cyber** BUs are external — in the "Fortra Approval Matrix" Google Sheet (separate tabs). This doc does not reproduce them.
- **Assumption**: Revenue Cloud flow-based approval orchestration + Smart Approval features are available/licensed in the target org.
- **Open / unspecified**: object & field model, flow API names, platform-event names, "Smart Approval" AI mechanism, MYCAP and Displaced ARR validation rules, numeric discount thresholds, rounding, and precedence tie-breaks are all **undefined in this document**.
- **Confidentiality footer anomaly**: doc header date is 4/9/2026 but the recurring footer/watermark reads "20240405" — treat as a template artifact, not a content date.

---

## CODE-GOVERNING RULES (do not violate)

An engineer implementing or refactoring this approvals system MUST NOT violate the following, each traceable to the source:

1. **Three-level evaluation is required.** Every submission must be evaluated at **Line**, **Bundle**, AND **Quote** levels — not a single sequential chain. (Source: "evaluates approval requirements at the line, bundle, and quote levels simultaneously.")

2. **Processing-mode contract per level is fixed:**
   - Line Level → **Parallel evaluation** (each quote line independently).
   - Bundle Level → **Sequential, AFTER line approval**, scope = all lines within a bundle, and it **aggregates component approvals**.
   - Quote Level → **Final validation step**, scope = entire quote aggregate.
   Do not reorder these or make bundle/quote run before line approvals.

3. **Trigger criteria per level must map exactly:**
   - Line: individual product discounts, special terms.
   - Bundle: bundle discount thresholds, component dependencies.
   - Quote: total value, payment terms, contract type.

4. **Orchestration step order is fixed** (1→5): Initial Evaluation → Parallel Processing → Bundle Consolidation → Quote Validation → Smart Approval Features. The entry trigger is **quote submission**, and step 1 must evaluate **all line items against the approval matrix** and **create approval work items**.

5. **Partial approval MUST be supported.** Individual line items can be **rejected without requiring complete quote resubmission**. Do not implement all-or-nothing quote approval that forces full resubmission on any single-line rejection. (Source: "The design enables partial approvals, where individual line items can be rejected without requiring complete quote resubmission.")

6. **Both business-unit matrices must be enforced**: **Tech** and **Cyber**. Thresholds are the ones defined in the external **Fortra Approval Matrix Google Sheet** (Tech tab, Cyber tab) — the implementation must source them from there, not hardcode invented values.

7. **Quote-level validation MUST include the named special scenarios**: **MYCAP** and **Displaced ARR** (in addition to total-value threshold checks). These cannot be dropped from the final quote validation step.

8. **Notifications go through Platform Events** for real-time alerts / status updates / integration triggers. Do not replace the event-driven notification path with synchronous-only signaling if it breaks the "instant alerts + integration triggers" contract.

9. **Approver interactions run through the unified Work Guide interface** with the specified capabilities (unified queue with priority sorting, context panel, bulk approve/reject, delegation with audit trail, mobile parity, analytics). Bulk actions and delegation-with-audit-trail are explicit requirements, not optional.

10. **Do NOT invent unstated specifics.** No numeric thresholds, object/field API names, formulas, rounding modes, or flow/event names exist in this source. Any such value must come from the live org or the Google Sheet matrix — never fabricated to fill a gap.
