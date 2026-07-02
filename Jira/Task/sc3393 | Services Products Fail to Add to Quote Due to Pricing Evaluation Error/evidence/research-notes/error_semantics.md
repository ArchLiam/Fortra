# SC-3393 — Error Semantics Research (web + platform docs)

Thread question: In Salesforce Revenue Cloud / RLM ExpressionSet (BRF+) pricing, what triggers
- `SF-Pricing-00006: The value specified for the evaluation resource for <stepName>#1 isn't valid. Enter a valid value for the evaluation resource and try again.`
- `SF-BRF-00004: We couldn't simulate the step because one or more specified resources don't have corresponding values for evaluation.`

Critical RCA fork: does a **NULL value** for a referenced resource (a Currency field in a `GreaterThan` compare) cause this, or does it require the resource to be **ABSENT/unmapped from the runtime context** (an unsynced/unpublished context version)?

Research date: 2026-06-11. Note: the literal error codes `SF-Pricing-00006` / `SF-BRF-00004` are **not publicly documented** (no KB, release note, Trailblazer thread, or Stack Exchange hit returns them verbatim — confirmed across ~12 targeted searches). Conclusion below is built from the **architecture of the two error layers**, the message wording, and the documented null-handling semantics of Expression Sets. Confidence is therefore **medium**, not high.

---

## 1. What the two codes are, by layer

The two codes are emitted by **different layers** that wrap each other:

- **`SF-BRF-00004`** — prefix = **BRF / Business Rules engine** (the BRE/BRF+ evaluation runtime that actually executes ExpressionSet "steps"). The verb is **"simulate the step"** — BRF+ executes each ExpressionSet step by *simulating* it against the supplied resource bag. The complaint is structural: *"one or more specified resources don't have **corresponding values for evaluation**."* This is the **inner** error.
- **`SF-Pricing-00006`** — prefix = **Pricing** (the RLM pricing-procedure orchestrator that drives the ExpressionSet on the pricing context). It is the **outer** error: the pricing layer caught the BRF failure on a named step (`RegionalNetReconcileGate#1`) and re-surfaced it as *"the value specified for the **evaluation resource** … isn't valid."*

So the chain is: Pricing procedure → runs ExpressionSet step `RegionalNetReconcileGate` (an `AdvancedListFilter`) → BRF+ tries to evaluate the filter's `criteria` against the context resources → BRF+ reports that a **resource referenced by the step has no corresponding value** → Pricing wraps it as SF-Pricing-00006.

Key vocabulary: BRF+'s phrase **"resources don't have corresponding values for evaluation"** is about the **resource ↔ value binding**, i.e. a resource the step *names* has **no value entry in the evaluation bag** — not about a resource whose value is the literal null.

## 2. The decisive distinction: NULL is a first-class, handled state; ABSENT is the error condition

Salesforce documents an entire page on this — **"How Null Values Are Handled in Expression Sets"** (`ind.how_null_values_are_handled_in_expression_sets`). Its existence and content show **null is a supported, evaluatable value**, not an error trigger:

- You can use **`IsNull` / `IsNotNull` operators and functions in the condition, list filter, and calculation steps** — i.e. the engine is explicitly designed to let a step *evaluate* a null input. A step that can ask "is this null?" does not crash on null.
- There is an **"Initialize resources to default values"** toggle: OFF preserves null; ON overwrites null with the configured default (Number/Currency/Percent → 0, Boolean → False, Text → ""). So a null Currency input is, by design, either *kept as null* or *coerced to 0* — **both are values the engine evaluates**, neither is the "no corresponding value" condition.
- For lookups: **"When the decision table doesn't have any matching row, the variables retain their previous values."** Again — graceful, not an error.

This is corroborated by **"Considerations for Calling Expression Sets"** (`ind.considerations_for_calling_expression_sets`): when an input variable is **omitted**, the configured/system default applies (Currency → 0); when null is **explicitly passed**, the engine **uses that null**. Null is consumed, not rejected.

⇒ A Currency resource whose **value is null** does **not** produce SF-BRF-00004. A `GreaterThan 0` compare against a null Currency that is *present in the context* evaluates deterministically (null treated as "no/empty" → condition false, OR coerced to 0 → 0 > 0 false). Either way the gate just returns **false** and the row is filtered out — **no error, line adds**.

## 3. What DOES produce "no corresponding values for evaluation" = the resource is ABSENT from the runtime context

The error fires when the step **names a resource the evaluation bag has no slot for** — i.e. the attribute/resource is **not present in the active, published context version** that the pricing run hydrated. Convergent evidence:

- BRF+ lineage: the SAP BRF+ analog **"Data object … from rule is missing in the ruleset context"** (SAP KB 3396103) fires on **structural absence** (the object isn't assigned to the context), explicitly *not* on a null value. Salesforce's BRF+ inherits this model; the message family "specified resources don't have corresponding values for evaluation" is the same "not in the context" check.
- RLM field reports describe the **structural** failure mode with a *different, characteristic* signature than a data/null problem: **"Something went wrong while hydrating additional context fields: Cannot invoke … DefaultContextRuntimeEntityAttribute.getTags() … return value of Map.get(Object) is null"**, fixed by **correcting Context Definition mappings / re-activating the definition** (Applikontech RLM troubleshooting guide). That is the "attribute not in the published context" class.
- The "Three-Part Pricing Problem" (2creative.ca) draws the exact architectural line this RCA needs:
  - **Out-of-sync / unpublished attribute** = *structural* — *"the system cannot locate the tagged attribute the procedure expects."* → engine error.
  - **Null value** = *data* — *"a field exists in the context definition but contains no data … defaults to null values, resulting in broken prices."* → wrong numbers, **not** an engine error.
- ExpressionSet author guidance ("Considerations for Calling Expression Sets", BRE complete guide): the design-time and runtime requirement is that **every resource a step references must exist as a resource and be supplied**; an unsupplied/unmapped resource yields a failure to evaluate (the calling layer must provide all referenced resources). Null-but-present does not.

## 4. The "Add Product" path vs full reprice — why it surfaces here

- The RLM "Add Product" action runs the **same pricing procedure / ExpressionSet**, just scoped to the new line (lightweight, single-item pricing) rather than a full-cart reprice. It still hydrates the **pricing context** from the active **context definition version** and executes every top-level step, including the new `RegionalNetReconcile` ListGroup (seq 33).
- RLM KB 001979870 ("We couldn't add the product to Quote because…") confirms the Add-Product failure surface is literally *"the pricing procedure doesn't return an expected price when simulated"* — i.e. Add-Product failures are reported as **pricing-procedure simulation** failures. That's the same "simulate the step" verb as SF-BRF-00004.
- Implication: whatever makes the gate step unsimulatable will block the **add** outright (line fails to attach, quote keeps 0 lines) — exactly the reported symptom — rather than just mispricing it.

## 5. Verdict on H1 vs H2

**The platform error semantics favor H2 (resource ABSENT/unsynced from the runtime context) over H1 (resource present-but-null).**

- **H1 (null value of `RegionalNetUnitPrice__c`) is semantically the WRONG shape for this error.** A null Currency that is *mapped and present* in the context is a fully evaluatable value — the engine has explicit null operators, a default-initialization toggle, and documented null-preservation. A null in a `GreaterThan 0` test yields a clean **false** (gate filters the row out), which would let the line **add** with no error. The reported behavior (hard failure, "no corresponding values for evaluation," 0 lines) does not match "null compared to 0."
- **H2 (the active/published `SalesTransactionContextExt_v2` version does not carry `RegionalNetUnitPrice__c` — i.e. the context attribute the V10/V12 gate references is not in the runtime context bag)** matches the message exactly: the step names a resource for which the evaluation context **has no corresponding value slot** → SF-BRF-00004 → SF-Pricing-00006. This is the same failure class as the prior `project_reprice_contextdef_error` gack (pricing procedure edited/republished without re-syncing the context version).
- This also explains the **"introduced recently"** report cleanly: the `RegionalNetReconcileGate` referencing `RegionalNetUnitPrice__c`/`AllowRegionalPricing__c` was **added in V10 (2026-06-10)**. If the context **definition** carries those attributes at design-time (it does — see §6) but the **active context VERSION** that pricing hydrates was not re-published/synced after the regional rework, the new step references a resource the runtime bag lacks → error appears the moment V10/V12 went live.

### Important caveat that keeps H1 in play as a variant
The data layout *is* consistent with H2's trigger even under an H1-flavored mechanism: the prehook is a **US no-op** and never writes `RegionalNetUnitPrice__c`, and the QLI mapping is **INPUT-only** hydrated from `Regional_NetUnit_Price__c` which is **null on a fresh US line**. If — and only if — the active context version treats an **unwritten/never-hydrated INPUT attribute as "no value supplied"** (absent from the bag) rather than "present = null", then the *effective* trigger is the unhydrated input, which presents to BRF+ as "no corresponding value." That is a **hybrid**: H1's data condition (nothing ever populated the resource) producing H2's error class (resource has no value in the bag). The pure-null reading of H1 (resource present in bag, value = null, compared > 0) is the one the docs rule out.

⇒ **Most-likely root mechanism:** the gate step references a context resource (`RegionalNetUnitPrice__c`, and/or `AllowRegionalPricing__c`) that is **not present with a value in the runtime evaluation context** for a US line — because either (a) the active context version is unsynced/missing the attribute (H2 proper), or (b) the INPUT attribute is never hydrated (prehook no-op + null source field) and the runtime treats unhydrated-input as absent-resource (H1→H2 hybrid). Both reduce to **"resource has no corresponding value for evaluation,"** which is what the message literally says. A **value that is simply null but present** would NOT throw this.

## 6. Cross-checks against the retrieved local artifacts (consistent with the above)

- `regionalnetreconcile_group_v12.xml`: `RegionalNetReconcileGate` is an `AdvancedListFilter`, `conditionLogic "1 AND 2"`, crit1 `AllowRegionalPricing__c Equals true` (Literal), crit2 `RegionalNetUnitPrice__c GreaterThan 0` (Literal). Both `sourceFieldName`s are **context-attribute** references — exactly the things BRF+ must find values for.
- Context def `SalesTransactionContextExt_v2` **DESIGN-TIME** carries the attribute: node-level declaration `RegionalNetUnitPrice__c` `<dataType>currency</dataType>`, `<fieldType>inputoutput</fieldType>`, with `<contextTags><title>RegionalNetUnitPrice__c</title></contextTags>` (lines ~24279-24290). QLI mapping (lines 6665-6672) is **INPUT-only** (`contextInputAttributeName`, no output), hydrated from `Regional_NetUnit_Price__c`. So the attribute is legitimately tagged in the **definition** — the open question is purely whether the **active/published VERSION** the runtime uses carries it. That is the runtime-context thread's job to confirm (`ContextDefinitionVersion`/Setup describe), and it is the linchpin between "H2 proper" and "H1→H2 hybrid."

## 7. Hand-off / what to prove next (out of this thread's scope)
1. Confirm the **active published version** of `SalesTransactionContextExt_v2` actually exposes `RegionalNetUnitPrice__c` (and `AllowRegionalPricing__c`) as runtime resources — if absent → **H2 proper, structural**.
2. If present in the active version, capture a **FINEST/pricing debug log** of an authorized Add-Product repro to see whether BRF+ reports the resource as *missing* (absent) vs *null* — distinguishes hybrid from a deeper config gap (H3).
3. Either way, the **fix lever is the same shape**: make the gate not reference an unvalued resource for US lines — e.g. flip `IsPriceImpacting`/initialization so the INPUT is always hydrated, default `RegionalNetUnitPrice__c` to 0, gate on a guaranteed-present attribute, or re-sync/republish the context version so the attribute is in the runtime bag.

---

## Sources
- Salesforce Help — How Null Values Are Handled in Expression Sets: https://help.salesforce.com/s/articleView?id=ind.how_null_values_are_handled_in_expression_sets.htm&language=en_US&type=5  (null preserved vs default-initialized; IsNull/IsNotNull usable in condition/list-filter/calculation steps; no-match retains previous values)
- Salesforce Help — Considerations for Calling Expression Sets: https://help.salesforce.com/s/articleView?id=ind.considerations_for_calling_expression_sets.htm&language=en_US&type=5  (omitted → default 0/false/""; explicit null is used as-is)
- Salesforce Help — Step Elements to Build Your Expression Sets: https://help.salesforce.com/s/articleView?id=sf.step_elements_in_expression_sets.htm  (List Group / List Filter / Lookup / Calculation / Condition step taxonomy; links the null-handling doc)
- Salesforce Help — Simulate and Activate Your Expression Set Version: https://help.salesforce.com/s/articleView?id=sf.simulate_and_activate_the_expression_set.htm  ("Simulate" provides resource values; missing-resource handling)
- Salesforce Help (RLM KB 001979870) — "We couldn't add the product to Quote because…": https://help.salesforce.com/s/articleView?id=001979870&language=en_US&type=1  (Add-Product failure = pricing procedure doesn't return expected price *when simulated*)
- Applikontech — Troubleshooting Salesforce RLM Issues: https://applikontech.com/enabling-partner-users-and-troubleshooting-salesforce-rlm-issues-a-comprehensive-guide/  (getTags()=null hydration error → fix Context Definition mappings / re-activate; structural-absence class)
- 2Creative — The Three-Part Pricing Problem: https://2creative.ca/the-three-part-pricing-problem/  (out-of-sync = "system cannot locate the tagged attribute" [structural]; null = "field exists but no data" [data] — the H2 vs H1 line)
- ArrayTrail — Fixing Context-to-Context Mapping Deployment Issues in RCA: https://www.arraytrail.com/fixing-context-to-context-mapping-deployment-issues-in-salesforce-rca-summer-25-winter-26/  (mappings can fail to deploy/publish → silent runtime gaps; context version sync matters)
- Jitendra Zaa — Salesforce Business Rules Engine Complete Guide: https://www.jitendrazaa.com/blog/salesforce/salesforce-business-rules-engine-guide/  (missing/unmapped inputs → null/empty; every referenced resource must exist; use Simulation to trace which step lacks a value)
- SAP KB 3396103 — "Data object … is missing in the ruleset context": https://userapps.support.sap.com/sap/support/knowledge/en/3396103  (BRF+ lineage: error = structural absence of the data object from context, not a null value)
- Salesforce Release Notes — Null Value Support in Decision Table Lookups (Spring '24 / 248): https://help.salesforce.com/s/articleView?id=release-notes.rn_bre_null_value_support_in_decision_table_lookups.htm&release=248  (shows nulls were a distinct, separately-handled case in BRE lookups)
- Salesforce Help — Simulation Evaluation Service Input (Industries reference): https://developer.salesforce.com/docs/atlas.en-us.industries_reference.meta/industries_reference/connect_requests_simulation_eval_service_input.htm  (resource value bag supplied to step simulation)

NOTE: the literal codes SF-Pricing-00006 / SF-BRF-00004 are NOT publicly documented; the verdict is inferred from the two-layer architecture, the message wording ("simulate the step", "corresponding values for evaluation"), and the documented Expression-Set null semantics. Confidence: MEDIUM.
