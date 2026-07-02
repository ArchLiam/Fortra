# SC-3390 — Platform Research Addendum (Salesforce RLM/Revenue Cloud) + Instant Pricing finding

> **⚠️ SUPERSEDED by `06_FIX.md` (2026-06-11).** This doc recommends trialing **(e) Instant Pricing** first.
> Both (e) and (a) were later validated live; the team **shipped (a) `IsPriceImpacting=true`** (scoped, no global
> behavior change). Instant Pricing remains a viable alternative. The platform findings here are still accurate.

**Ticket:** SC-3390 — "Tiered Pricing Product Requires Update Price to Be Clicked Twice After Quantity Change"
**Date:** 2026-06-11 · **Scope:** read-only (web research + org cross-check, no DML/deploy)
**Why this doc exists:** the original RCA (`02_ROOT_CAUSE_AND_FIX_SPEC.md`) is entirely org/code-internal. This addendum runs the one
resource that pass skipped — **external Salesforce platform documentation / community** — to see whether the
"reprice-twice" symptom is documented platform behavior, and whether the docs point to a corroboration, a
refutation, or a cleaner fix. It also adds **one new org-verified fact** (Instant Pricing is not enabled on the
quote page) that the docs make load-bearing.

> Read `02_…` first for the full RCA. This doc only adds the external dimension and the two new fix levers it surfaces.

---

## 1. Headline additions (what this changes)

1. **NEW org-verified fact — Instant Pricing is NOT enabled on the quote line editor.** The
   `runtime_revenue_foundation:transactionLineTable` component on `Quote_Record_Page` declares **only**
   `enableQuickAdd`, `enableSidepanel`, `sidepanelDetailFields` — there is **no Instant Pricing property set**
   (`Data/sc3390/evidence/ui-flexipages/.../Quote_Record_Page.flexipage`, lines 158–168). Per Salesforce's own
   docs, with Instant Pricing **off**, *"the inline edits that you make to your quote such as **updating the
   quantity** or applying a manual discount, are priced **when you save the changes**"* — i.e. a manual reprice
   ("Update Price") is **required by design**, edits are not priced on change. This is the platform-documented
   **macro-reason a reprice is needed at all**, and it surfaces a clean candidate fix (see §4, fix **(e)**).

2. **External corroboration of the "first pass reads null/stale → wrong price, silently"** mechanism.** An
   independent RLM practitioner writeup describes exactly the §2.4 / §4 failure shape: *"the procedure cannot
   retrieve necessary inputs on the **first calculation pass**, so it **defaults to null values, resulting in
   broken prices**."* That is the same fingerprint as `AttributeVolumePricingPrehook`'s null-volume **silent
   reset to List Price** (`cls:282`). It does not *prove* SC-3390's timing, but it shows the "first-pass-reads-
   nothing-then-converges" mode is a recognized RLM pricing pathology, not a Fortra-only theory.

3. **NEW org-verified fact — the volume is hydrated from the PERSISTED `QuoteLineItemAttribute.AttributeValue`
   column, and the node is already bidirectional.** I retrieved the active context definition
   (`SalesTransactionContextExt_v2`, read-only) and traced the exact hydration path
   (`evidence/context-mapping-qlia-hydration.txt`): the `SalesTransactionItemAttribute` context node maps to
   `QuoteLineItemAttribute`, and its **`AttributeValue`** context attribute hydrates from the persisted DB column
   **`QuoteLineItemAttribute.AttributeValue`** (`queryAttribute=AttributeValue`), with the attribute name
   resolved from `AttributeDefinition.DeveloperName` (= `Attribute_Volume`). The whole Quote mapping block
   carries **all four mappingIntents — hydration + persistence + association + translation** → the node is
   **already bidirectional** (the "Input+Output" equivalent). **This refutes the naive "Direction is set wrong"
   fix** and instead **pins the §2.4 window precisely**: because the volume is read from the *persisted*
   `AttributeValue` column at price-contexts build time, the first "Update Price" prices the **old/null** value
   **iff the side-panel Unit Quantity edit has not yet committed to that column** when price-contexts hydrates;
   the second click (value now committed) hydrates the new value → correct tier. This is the concrete data path
   behind the RCA's "surviving narrow variant" (`02_…§3`, configurator-commit footnote) — **not** a race inside
   the place txn (correctly refuted; place prices the already-built transient context), but a
   **side-panel-save → price-contexts-hydrate ordering** question one call earlier. See §4, fix **(f, restated)**.

4. **No official Salesforce "Known Issue" article** matches the exact "Update Price twice after quantity change
   on a tiered product" symptom (searched Help, Known Issues, Developer Guide, Trailblazer). The behavior is a
   **configuration/timing interaction**, consistent with the RCA's "plausible-unproven, no single KI" conclusion
   — not a published platform bug with a posted fix. Community threads on adjacent reprice issues exist but their
   thread bodies are JS-rendered and not extractable read-only (listed in §5 for a human follow-up).

**Net effect on the RCA:** the leading hypothesis is **strengthened** (now has a platform-documented macro-cause
+ an external corroboration of the silent-null mode), and the fix menu gains **two lower-risk, no-procedure-change
levers** (Instant Pricing; context-mapping Direction) that should be validated **before** the riskier
`IsPriceImpacting` flip. The decisive proof is **unchanged**: still the authorized 49→50 boundary-cross repro.

---

## 2. The Instant Pricing finding in detail

### 2.1 What the platform docs say (verbatim)
> *"Make sure to enable [Instant Pricing] to view the recalculated prices of products after every change. … If
> Instant Pricing isn't enabled, then the inline edits that you make to your quote such as **updating the
> quantity** or applying a manual discount, are priced **when you save the changes**."*
> — Salesforce Trailhead, *Streamline Your Quoting Process with the Transaction Line Editor* (and the
> *View and Edit Quotes in Revenue Cloud* Help article).

So, **Instant Pricing ON** → every edit (quantity/attribute/discount) reprices immediately.
**Instant Pricing OFF** → edits are priced only on **save / explicit reprice** ("Update Price").

### 2.2 What the org shows (read-only, this session)
`Data/sc3390/evidence/ui-flexipages/unpackaged/flexipages/Quote_Record_Page.flexipage`, the TLE component block:

```
158  <name>enableQuickAdd</name>      ...
162  <name>enableSidepanel</name>     ...
166  <name>sidepanelDetailFields</name> ...
168  <componentName>runtime_revenue_foundation:transactionLineTable</componentName>
```

→ **No Instant-Pricing property is present** on the component → Instant Pricing is **not enabled** for the quote
line editor on `Quote_Record_Page`. (Enablement is a Lightning App Builder **component property** on the TLE;
absence = platform default = off. Exact property label to confirm in App Builder — see §6.)

### 2.3 Why this matters for SC-3390
- It explains, with a **platform-documented reason**, why reps must click "Update Price" at all: with Instant
  Pricing off, typing a new Unit Quantity does **not** reprice — it's priced on the next reprice/save. The rep's
  mental model ("I changed the number, the price should follow") is exactly the gap Instant Pricing closes.
- It reframes the **two-click** part precisely: the first "Update Price" runs the save-then-price cycle, but the
  price it produces is built from a context snapshot that (per the RCA's unproven window) does **not yet** carry
  the just-typed value; the second click prices the now-committed value. **Instant Pricing being off is the
  necessary precondition** for that manual-reprice dependency to exist in the first place.
- **It does not, by itself, prove the first-click-stale step** — that is still the §2.4 unproven window. But it
  means a fix that **removes the manual-reprice dependency entirely** (turn Instant Pricing on) plausibly makes
  the symptom disappear **regardless of which micro-mechanism** (IsPriceImpacting flag vs side-panel save timing
  vs context-mapping Direction) causes the staleness — which is why it is attractive to validate first (§4e).

**Honest caveat:** if Instant Pricing's per-change reprice *also* snapshots before the side-panel value commits,
it could reprice on the stale value too and not help. That is precisely what the §8 repro (now: repro **with**
Instant Pricing toggled) must check. So Instant Pricing is a **high-value candidate fix to test**, not a proven
fix.

---

## 3. Secondary external findings (corroborating / contextual)

| Source theme | What it says | Relevance to SC-3390 |
|---|---|---|
| **Context Definition ⇄ Procedure ⇄ Decision Table** ("three-part problem") | *"the procedure cannot retrieve necessary inputs on the **first calculation pass**, so it defaults to **null values, resulting in broken prices**"*; decision tables go stale → "quoting stale prices"; *"You can't see why a specific price was calculated"* (no recompute audit trail). | External corroboration of the prehook's **null-volume silent reset to List Price** (`cls:282`) and the "no error is shown" risk (`02_…§4`). The "first calculation pass → null" pattern is the same family as SC-3390's first-click staleness. |
| **Context mapping Direction** (Input / Output / Input+Output) | Mapping intents = **Hydration** (object→context), **Persistence** (context→object), **Association/Translation**. Editable TLE fields/attributes must be mapped **Input and Output** *"to flow into the editor for display/editing and out when changes are saved."* | **Org-verified (§1.3):** the `QuoteLineItemAttribute` node is **already bidirectional** (hydration+persistence) and `AttributeValue` hydrates from the **persisted** `QuoteLineItemAttribute.AttributeValue` column → **Direction is NOT the bug**; the lever is **commit-before-hydrate ordering** (§4f restated). |
| **`QuoteLineDetail` dev guide** | RLM emits `QuoteLineDetail` rows on "derived pricing or repricing during an amendment, and **bundle or product attribute reconfigurations**." | Confirms attribute reconfig is a first-class **reprice trigger** in RLM; a place to audit whether the *first* click's QuoteLineDetail carries the old vs new volume (forensic, read-only, once a repro quote exists). |
| **Instant Pricing enablement** | Enabled via **Lightning App Builder** on the TLE component (Action Buttons / component properties panel). | Makes fix **(e)** a **declarative, no-code, no-procedure-version** change — lowest-risk lever to trial. |
| **Official "Known Issue" search** | No Salesforce KI article matches "reprice/Update-Price twice after quantity change on tiered/attribute pricing." | Consistent with RCA: this is a config/timing interaction in *this* org, not a published platform defect with a canned fix. |

---

## 4. Fix options — updated menu

Carry forward `02_…§6` options **(a)–(d)** unchanged, and **add two lower-risk, no-procedure-change levers** that
the platform research surfaces. Recommended trial order now leads with these because they are declarative and
reversible.

### (e) NEW — Enable **Instant Pricing** on the Transaction Line Editor *(declarative; trial first)*
- **Change type:** Lightning App Builder component property on `runtime_revenue_foundation:transactionLineTable`
  (`Quote_Record_Page`). No Apex, no procedure version, no context republish.
- **What it does:** reprices on **every** edit, so a Unit Quantity change is priced immediately — removing the
  manual "Update Price" dependency that the two-click symptom rides on. If the per-change reprice carries the
  fresh value, the symptom disappears at the source.
- **Risk:** Low–Medium. (1) More pricing calls per edit → latency on large quotes (the org has async pricing
  *off* and is synchronous — watch governor/UX on big lines). (2) **Unproven that it fixes the staleness** — if
  the instant reprice also snapshots pre-commit, it won't help (validate with the §8 repro **with Instant Pricing
  on**). (3) Behavioral change for all reps (no longer a manual reprice gate). **Fully reversible.**
- **Validate:** §8 repro with Instant Pricing on — does a 49→50 edit price the 50–99 tier with **no** manual
  click? Spot-check latency on a 15+ line quote (cross-ref SC-3366 SOQL-governor work).

### (f, restated) — Guarantee the side-panel Unit Quantity **commits to `QuoteLineItemAttribute.AttributeValue` before price-contexts hydrates**
> **Note:** the original "fix the context-mapping *Direction*" framing is **closed/refuted** by §1.3 — the node
> is already bidirectional (hydration+persistence) and the value correctly hydrates from
> `QuoteLineItemAttribute.AttributeValue`. The real lever is **commit ordering**, not Direction.
- **Change type:** UI/flow sequencing on the configurator side-panel save (if a custom LWC wrapper exists) — the
  documented `updateRecord → settle → reprice` ordering this codebase already uses in `quoteLineFlexPanel.js`.
  If the side-panel is purely managed, there is **no local seam** → Salesforce/RLM escalation (same as `02_…§6b`).
- **What it does:** ensures the just-typed value is persisted to `AttributeValue` **before** the first
  price-contexts call hydrates it — so click 1 already reads the new volume. This is the mechanism-targeted
  version of "make click 1 see the new value," now backed by the confirmed DB-hydration path
  (`evidence/context-mapping-qlia-hydration.txt`).
- **Risk:** Medium–High. May be managed-only (no seam); a `sleep`/settle band-aid is the codebase anti-pattern,
  last resort only.
- **Validate:** confirm in the §8 repro that click-1's `cls:280 'Attribute_Volume: …'` reads the **new** value
  and that the place-contexts request hydrated the committed `AttributeValue`.

> **Decision flow:** trial **(e)** (declarative, reversible) → if it resolves the symptom in the repro, ship it;
> if not, pull the context mapping and evaluate **(f)**; **(a)** `IsPriceImpacting` flip remains the deeper
> config fix but is higher-blast-radius (26 PADs) and should be **gated on the repro** showing the flag is the
> window. **(c)** defensive "no silent stale price" guard still ships in parallel regardless.

---

## 5. Sources

- Salesforce Trailhead — *Streamline Your Quoting Process with the Transaction Line Editor* (Instant Pricing behavior; "priced when you save the changes"): https://trailhead.salesforce.com/content/learn/modules/efficient-sales-with-revenue-cloud/work-with-quotes
- Salesforce Help — *View and Edit Quotes in Revenue Cloud* (Instant Pricing / reprice): https://help.salesforce.com/s/articleView?id=sf.qocal_view_and_edit_quotes.htm&language=en_US&type=5
- Salesforce Help — *Reprice All for Quotes and Orders* / *Set Up Delta Pricing* (reprice actions): https://help.salesforce.com/s/articleView?id=ind.qocal_view_and_edit_quotes.htm&language=en_US&type=5
- SOLVD — *How to Make Custom Fields Editable in the Transaction Line Editor (Revenue Cloud Advanced)* (Direction = Input and Output; hydration/persistence): https://solvd.cloud/how-to-make-custom-fields-editable-in-the-transaction-line-editor-revenue-cloud-advanced/
- 2Creative — *The Three-Part Pricing Problem* (first-pass null inputs → broken/stale prices; no recompute audit trail): https://2creative.ca/the-three-part-pricing-problem/
- Applikontech — *Context Definition for Pricing Procedure* (hydration / persistence / association mapping intents): https://applikontech.com/context-definition-for-pricing-procedure/
- Salesforce Developer Guide — *QuoteLineDetail* (attribute reconfiguration → reprice rows): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_quotelinedetail.htm
- Salesforce Developer Guide — *AttributeBasedAdjustment* / *Product Configurator* (IsPriceImpacting attribute adjustments): https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/sforce_api_objects_attributebasedadjustment.htm
- The Cloud Update — *Dynamic Attributes in RLM* (mark attribute "Is Price Impacting" → attribute-based adjustments): https://thecloudupdate.co/dynamic-attributes-in-salesforce-revenue-lifecycle-management-rlm/
- **Community threads for human follow-up (bodies not extractable read-only):** *RLM: Quoteline editor issues* (https://trailhead.salesforce.com/trailblazer-community/feed/0D5KX00000KBTbW0AX); *Reprice All Button in Revenue Cloud* (https://trailhead.salesforce.com/trailblazer-community/feed/0D5KX00000j97yq0AA); *Updating prices on quote line item* (https://trailhead.salesforce.com/trailblazer-community/feed/0D54V00007XITLnSAP)

---

## 6. Open items this addendum leaves for the next (authorized/UI) pass

1. **Confirm the exact App Builder property** that enables Instant Pricing on the TLE component, and that toggling
   it is the intended fix-(e) seam (login-required App Builder; not retrievable as a typed property read-only).
2. ✅ **DONE this pass — context mapping pulled.** `SalesTransactionContextExt_v2` retrieved; the
   `QuoteLineItemAttribute` node is bidirectional and `AttributeValue` hydrates from the persisted column
   (`evidence/context-mapping-qlia-hydration.txt`). Direction is **not** the bug; the lever is commit ordering
   (§4f restated). Remaining sub-item: confirm in a live repro *when* the side-panel `AttributeValue` commit
   lands relative to the price-contexts hydration.
3. **The §8 authorized repro is now a 2×2:** {Instant Pricing off (today) vs on} × {click 1 vs click 2}. This
   single experiment validates fixes (e) and (a) simultaneously and closes the plausible-unproven gap. Capture
   the place-contexts request payload to see whether click-1 carried the committed `AttributeValue`.
