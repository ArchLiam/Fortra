# SC-3393 — Error Semantics (web research, independent thread)

Independent web/doc research on `SF-Pricing-00006` / `SF-BRF-00004` in Salesforce RLM ExpressionSet/BRF+.
Run 2026-06-11. **Companion to `error_semantics.md`** (the two threads reach the same fix family from slightly
different readings of the present-null-vs-absent nuance — see "Reconciliation" below).

> Sourcing caveat: the literal strings `SF-Pricing-00006` / `SF-BRF-00004` are **not** in any publicly indexed
> Salesforce doc, Trailblazer thread, or Stack Exchange answer (the dev-guide "Pricing Error Response" page is
> JS-rendered and not machine-fetchable). Verdicts below are reasoned from the documented BRE/ExpressionSet/
> Context-Definition architecture + corroborating null-handling docs. Confidence: medium on the codes, high on
> the architecture and the fix posture.

## Q1 — what the codes mean
- An RLM Pricing Procedure **is** an ExpressionSet; ExpressionSets run on the **Business Rules Engine (BRE/BRF+)**
  → pricing failures surface as a `SF-Pricing-*` outer wrapping a `SF-BRF-*` inner. `SF-Pricing-00006` = "this
  pricing step failed"; `SF-BRF-00004` = the underlying "couldn't simulate/evaluate the step — a referenced
  resource had no value to bind."
- A **"resource"** in BRE = any input/output variable, constant, or context attribute referenced by an element.
  The **"evaluation resource"** = the operand a filter/decision criterion is reading — here, `RegionalNetUnitPrice__c`.
- Sources: Use Pricing Elements; Expression Sets; Business Rules Engine (Industries Reference); Pricing Error
  Response (dev guide, could not render).

## Q2 — is a NULL/unvalued numeric resource a cause?
- **Verdict (medium-high): yes.** The ExpressionSet **simulate/evaluate** path is not guaranteed to coerce a
  null operand to "false" the way a *formula field* does. Formula-field null-as-false (CPQ/Flow/Apex) does **not**
  govern the BRE evaluate path. The simulate UI itself requires you to "provide values for the **Input
  Resources**" before it can simulate — an unvalued input is simulate-blocking, not silently false.
- A NULL Currency flowing into a `GreaterThan 0` inside an **AdvancedListFilter** is a textbook trigger for
  "couldn't simulate the step … resources don't have corresponding values."
- Sources: Simulate and Activate Your Expression Set Version; "Salesforce Expression Set Issue" (syncerrors);
  BRE Complete Guide (Jitendra Zaa); Null Relationships & Short-Circuiting (David Reed — scope explicitly
  formula/Flow/Apex, *not* BRE).

## Q3 — missing/unmapped (metadata) vs mapped-but-null (data)?
- **Verdict (medium): the wording "corresponding values" points at the DATA case (mapped attribute, null/unvalued
  at runtime), but the same message can be produced by the METADATA case.** Disambiguate by *which lines fail*:
  a metadata gap fails **uniformly** (every line); a data gap fails **only on lines where the operand is unvalued**
  (here: only `AllowRegionalPricing__c=true` lines, which is the data signature).
- Sources: Activate a Context Definition; RLM troubleshooting (Applikontech); Pricing Error Response.

## Q4 — does the AND short-circuit, or must simulate bind all referenced resources? (crux)
- **Verdict (medium): do NOT assume BRE short-circuit/null-as-false** — that behavior is documented for
  formulas/Flow/Apex, not the ExpressionSet evaluate path. The observed selectivity (only crit1-true lines fail)
  is itself evidence that a true crit1 is precisely what *forces* crit2 to be evaluated against the unvalued
  operand. Criterion-1-false lines never dereference it.
- Sources: Simulate and Activate; Use Pricing Elements; (David Reed, scope-limited).

## Q5 — best practice to guard against null inputs
- **Verdict (high): seed/guard the operand BEFORE the filter.** Converging recommendations:
  1. Preceding **Assignment/Formula element** to default the null to 0 (BLANKVALUE/ISNULL/COALESCE).
  2. **ISNULL()/BLANKVALUE()** in a formula element.
  3. **Field default 0** so the attribute is never null at hydration.
  4. A **constant resource** supplying the fixed 0.
  5. Validate every step's input resources hold values via the **Simulation** tool before activation.
- Sources: Use Pricing Elements (Assignment Element); syncerrors; Jitendra Zaa; Null Values in CPQ; Simulate.

## Q6 — context sync/publish
- **Verdict (high): a Context Definition must be (re)activated/published for new attributes/mappings to be usable
  at runtime, and metadata changes can take up to ~24h (or a context-runtime-schema cache clear) to reflect.**
  If skipped, the procedure references an attribute the active context can't resolve → same SF-BRF-00004 symptom
  (the *metadata* path). **For SC-3393 this path is REFUTED separately** (H2 file): the attributes ARE on the
  active v23 context and pre-gate V9 consumed them — so this is not the operative cause here, but it is the
  standing hardening rule for any procedure/context change.
- Sources: Activate a Context Definition; Use Context Definitions; Applikontech.

## Bottom line
1. A **NULL/unvalued numeric resource that is mapped-but-unvalued at runtime** is the more likely cause of
   "resources don't have corresponding values for evaluation": the phrase targets a *value* gap, and the failure
   correlates with per-line data (`AllowRegionalPricing__c=true` forcing the null `RegionalNetUnitPrice__c > 0`
   test), not a global failure.
2. A truly **missing/unmapped attribute** (or an unsynced context) gives the *same* error class but fails
   uniformly — the alternative ruled out for SC-3393 in the H2 refutation.
3. **Fix posture regardless of branch:** seed the operand to 0 / add an `IsNotNull` guard before the gate; do not
   rely on BRE short-circuit/null-as-false.

## Reconciliation with `error_semantics.md`
The other thread argues, from "How Null Values Are Handled in Expression Sets," that **null is a handled state**
and the error implies **structural absence**. This thread argues the **simulate path treats an unvalued operand
as unsimulatable**. The README's **H1→H2 hybrid** reconciles both: the attribute is *declared/mapped* (so it is
not "missing from the context definition" = H2 dead) but is *input-only and never hydrated* on a US line, so at a
value comparison the engine has **no value to bind** — the data condition (H1) presenting as the "no corresponding
value" message. Both readings → the **same fix** (ensure a value / guard the comparison). The FINEST repro settles
the internal-semantics nuance; it does not change the fix.
