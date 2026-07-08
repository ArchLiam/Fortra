# Partner Pricing V2 — Two Open Issues for Resolution Before Build

**Purpose:** Pre-build issues memo (prepared for Fortra, April 28, 2026) that raises **two unresolved issues** found in the *Partner Pricing V2 Change Summary* (dated April 24, 2026). Each issue is stated in plain language with its business consequence and a recommended fix. This is a **decision/open-issues document, not a solution design** — nothing here is finalized; it flags problems to resolve before the V2 build proceeds.

> AGENT NOTE: This source is an 18-line issues memo. It contains no schema tables, no formulas, no rounding rules, no flow/prehook wiring beyond the field names and behaviors quoted below. Do NOT infer or invent additional fields, formulas, tie-break details, or component names. Where broader Partner Pricing V2 mechanics are needed, consult the actual implementation and the companion *Fortra-Pricing-PartnerPricing-Solution-Design-Doc* — not this memo.

---

## Executive Summary

Partner Pricing V2 introduces a new set of percentage fields on the **Partner Pricing Model** and a new duplicate-record tiebreaker. Two issues block a clean build:

1. **Field-name vs. behavior contradiction.** New fields named with a `Non_Orig_` prefix (reading as "Non-Originating," i.e. deals NOT originated by Fortra) are, per the Change Summary, actually used in the **opposite** case — when the deal type is **"Fortra Originated."** Name and behavior point in opposite directions; the source alone cannot determine which was intended.
2. **Silent duplicate-model selection.** The Change Summary says: *"If duplicates exist, V2 selects the newest created matching record."* Nothing prevents duplicate valid pricing models for the same product hierarchy (no uniqueness rule, no validation, no duplicate detection), so V2 will silently pick one and the affected quote lines price from it — with no notification to anyone.

Recommended resolution for Issue 2: keep the "newest wins" behavior **and** additionally write a **Partner Pricing Warning** onto the affected quote line (reusing the existing warning mechanism) so duplicates are handled but no longer hidden.

---

## Business Requirements / Rules (as stated in source)

- V2 adds percentage fields to the **Partner Pricing Model** for a "Fortra Originated" deal type.
- V2 tiebreaker rule (verbatim): **"If duplicates exist, V2 selects the newest created matching record."**
- The system today already surfaces partner-pricing anomalies by writing an explanation into a **Partner Pricing Warning** field on the affected quote line, visible immediately to Sales and pricing-operations users. V2 should extend this same mechanism to the duplicate case.

---

## Data Model (fields named in source)

Object: **Partner Pricing Model** (custom object). New percentage fields introduced by V2:

| Field API name (verbatim) | Type | Notes from source |
|---|---|---|
| `Non_Orig_Software_Pct__c` | Percent field (percentage) | Name reads as "Non-Originating Software Pct," BUT the Change Summary says it is used when the **deal type is "Fortra Originated."** Contradiction — see Issue 1. |
| `Non_Orig_Services_Pct__c` | Percent field (percentage) | Name reads as "Non-Originating Services Pct," BUT used for **"Fortra Originated"** deals per the Change Summary. Same contradiction. |

Suggested rename (from source, Issue 1 fix — NOT yet decided/implemented): e.g. **`Fortra_Orig_Software_Pct__c`** so name and behavior agree. (The source gives only the Software example; the analogous Services rename is implied but not spelled out.)

Object: **Quote Line** (Quote Line Item). Existing field reused for warnings:

| Field (name as described) | Type | Notes from source |
|---|---|---|
| **Partner Pricing Warning** field on the affected quote line | Text/message field (exact API name not given in source) | Existing mechanism: when something looks off about a quote's partner pricing, the system writes an explanation here; Sales and pricing-ops users see it immediately. Issue 2 fix reuses this. |

> The source does NOT give the exact API name, length, or data type of the Partner Pricing Warning field, nor confirm whether the two new `*_Pct__c` fields are Percent vs. Number type. Verify against the live object before coding. Type "Percent field" is the most consistent reading of the `_Pct__c` suffix + "percentage fields" wording, but treat as unconfirmed.

---

## Business Logic (as described)

- **Percentage fields usage (contested):** `Non_Orig_Software_Pct__c` and `Non_Orig_Services_Pct__c` are applied when **deal type = "Fortra Originated."** (This is the documented behavior that contradicts the `Non_Orig` name.)
- **Duplicate-model tiebreaker:** When two (or more) pricing models validly match the same line/product hierarchy, V2 **selects the newest *created* matching record** (i.e. tiebreak by record creation recency — most recently created wins). No uniqueness constraint, validation, or duplicate detection exists to prevent the duplicates in the first place.
- **No warning today for the duplicate case:** Current V2 (as summarized) picks the newest record **silently** — no notification to the quote owner, pricing desk, or finance. The only discovery path is a human noticing a mis-priced quote and manually tracing the data, typically after the quote has already reached a customer.
- **Recommended enhanced logic (Issue 2 fix):** Still pick the newest record so pricing completes, AND write a Partner Pricing Warning to the affected quote line meaning, in effect: *"two matching pricing models were found; the newest was used."*

No rounding mode, tier-precedence ordering (beyond "newest created wins"), default values, or numeric edge cases are specified in the source.

---

## Components (implied by source; none named as classes/flows)

The memo does **not** name Apex classes, triggers, flows, or prehooks. It only implies:

- A V2 partner-pricing selection routine that matches Partner Pricing Model records to quote lines and applies the "newest created matching record" tiebreak, then applies `Non_Orig_Software_Pct__c` / `Non_Orig_Services_Pct__c` for "Fortra Originated" deals.
- An existing warning-writing mechanism that populates the **Partner Pricing Warning** field on quote lines. (Implementation identity to be confirmed against the codebase — the memo asserts it already exists and works.)

---

## Integration Points & Sequence

Not covered by the source. The memo is scoped to two data/behavior issues; it does not describe integration sequence, Workday sync, pricing-procedure ordering, or prehook wiring.

---

## Assumptions / Dependencies / Open Issues

- **OPEN — Issue 1 (naming vs. behavior):** Unresolved which is correct — the `Non_Orig_` field names or the documented "Fortra Originated" behavior. Decision required before build. Two mutually exclusive resolutions:
  - Keep names as written → future admins/analysts/finance will likely misread "Non-Originating" and assume the percentages apply to **non-Fortra** deals, the opposite of actual behavior.
  - Honor the document's rule → rename the fields (e.g. `Fortra_Orig_Software_Pct__c`) so name matches behavior.
- **OPEN — Issue 2 (silent duplicate selection):** No uniqueness rule / validation / duplicate detection exists on Partner Pricing Model. Duplicates created by a data load, flow, or admin remain valid; V2 silently picks the newest and prices from it with zero notification. Recommended fix: keep newest-wins AND emit a Partner Pricing Warning on the affected quote line.
- **Dependency:** Issue 2 fix depends on the pre-existing Partner Pricing Warning field/mechanism on the quote line.
- Source references the **Partner Pricing V2 Change Summary (April 24, 2026)** as the authority for the contested behavior; this memo is dated **April 28, 2026**.

---

## CODE-GOVERNING RULES (must not be violated by any refactor)

1. **Field names carry semantic weight — do not silently keep a name that contradicts behavior.** If `Non_Orig_Software_Pct__c` / `Non_Orig_Services_Pct__c` are applied for **"Fortra Originated"** deals, the naming contradiction MUST be resolved by an explicit decision (rename to e.g. `Fortra_Orig_Software_Pct__c`, or formally accept the misleading name). Never ship code that relies on `Non_Orig_*` fields for Fortra-Originated deals without that resolution recorded.
2. **The two percentage fields apply on the "Fortra Originated" branch, per the Change Summary.** Any refactor of the deal-type routing MUST preserve exactly which branch consumes `Non_Orig_Software_Pct__c` and `Non_Orig_Services_Pct__c`; do not flip them to a "non-originating" branch on the assumption the name is authoritative — the documented behavior, not the name, is the current spec.
3. **Duplicate tiebreak is "newest CREATED matching record wins" — verbatim.** When multiple Partner Pricing Models validly match, select the most recently *created* record (by creation recency, not last-modified). Do not change the tiebreak key without a spec change.
4. **Pricing MUST still complete when duplicates exist.** The tiebreak exists so a duplicate never blocks pricing — always resolve to one record and proceed.
5. **Do NOT let duplicate selection stay silent.** When more than one eligible Partner Pricing Model matches a line, the code MUST write a **Partner Pricing Warning** to the affected quote line stating (in effect) *"two matching pricing models were found; the newest was used."* Reuse the existing quote-line Partner Pricing Warning mechanism; do not introduce a silent path.
6. **Do not assume uniqueness of Partner Pricing Models.** There is no uniqueness rule, validation, or duplicate detection on the object. Code MUST handle the multi-match case defensively (via rules 3–5) and never assume at most one matching record exists.
7. **Verify unconfirmed schema details against the live org before coding.** The exact API name/type/length of the Partner Pricing Warning field, and the precise data type of the two `*_Pct__c` fields, are NOT specified in this memo — confirm from the object metadata, do not hardcode from assumption.
