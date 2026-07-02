# H4-null-group-id-summary-collision — native-semantics lens (READ-ONLY)
Date 2026-06-28. Org FortraUAT. All read-only SOQL/Tooling + local retrieved metadata.

## Hypothesis
After the only group is deleted, a native group-summary map built pre-delete is looked up
with the surviving lines' null QuoteLineGroupId => Map.get(null).toString() throws the
JEP-358 NPE.

## REFUTED on two independent axes

### Axis 1 — Structural counter-examples (data uniqueness)
The exact structural pattern H4 needs = "quote has ONE populated group + ungrouped
survivor lines, so deleting the group leaves null-group-id survivors to reprice."
Query: all 52 QuoteLineGroup records -> 42 single-group quotes; cross-joined to their QLIs.
Of those, 4 NON-FAILING quotes match the H4 pattern (populated single group + >=1 ungrouped
survivor) and are not reported failing:
- 0Q0WC0000027oGf0AI (In Review) group "Test Hardware"(hw=F) TermDefined; ungrouped TermDefined
- 0Q0WC0000038GFZ0A2 (Draft) group "Test Hardware"(hw=F) TermDefined; ungrouped TermDefined
- 0Q0WC0000039E8T0AU (Accepted) group "Group"(hw=F) TermDefined; ungrouped TermDefined (+net>>... actually net=list)
- 0Q0WC000003AaoT0AS (Draft) group "Test"(hw=F) TermDefined; ungrouped MIXED OneTime+TermDefined
Each, on "Delete Group", would leave null-QuoteLineGroupId survivors and force a reprice —
the precise H4 trigger. A generic null-group-id Map.get(null) collision would fail all 4.
=> The differentiator is NOT "null-group-id survivors remain"; it is "the GROUP ITSELF
contains a OneTime+TermDefined SM mix" — present ONLY on the failing quote
0Q0WC000002U2020AC (group Test HW1, hw=True, group-SMs={OneTime,TermDefined}).
Evidence: verify/H4/four_comparators_full.json, verify/H4/qlis_single_group_quotes.json,
verify/H4/all_groups.json.

### Axis 2 — Native procedure semantics (the named map does not behave as claimed)
Active pricing-procedure version confirmed V16 via Tooling
(ExpressionSetDefinitionVersion, Status=Active, Id 9QBWC0000000niH4AQ).
The "129 GroupingAndAggregatePricing steps" is a grep-over-all-20-versions artifact
(verify/H1 finding); active V16 has 6 such steps. Of the 6, exactly ONE is keyed by group:
  AggregatePrice106: section-0-group-0 = SalesTransactionItemGroup (Text = the item-group id),
  SUM ItemNetTotalPrice -> ItemGroupSummarySubtotal,
  condition-0 operator = **isNotNull** on SalesTransactionItemGroup.
The other 5 are FLAT (group-count=0, no key). NONE keys on QuoteLineGroupId by that name;
the procedure has ZERO occurrences of QuoteLineGroupId / GroupId / LineGroup
(grep -c = 0 on Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition).
The one group-keyed aggregate's **isNotNull guard EXCLUDES null-group-id (ungrouped)
survivor lines from the map entirely** — they never enter it, so there is no
Map.get(null).toString() over the group key. And the deleted group is gone, so no stale
pre-delete entry is dereferenced.
Evidence: verify/H1_native_semantics_findings.md (sibling),
mission_B/live_source/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition,
verify/H4/active_version.json.

### Axis 3 — Documented native throw site is elsewhere
The only documented RLM sibling of this exact JEP-358 string (applikontech RLM guide,
captured in research-web/MISSION_A_NOTES.md) is in the Industries CONTEXT SERVICE runtime
(DefaultContextRuntimeEntityAttribute.getTags()) during CONTEXT HYDRATION, keyed on
per-line context tags — not a group-summary map keyed by QuoteLineGroupId.

## Verdict: REFUTED
H4's mechanism (Map.get(null over QuoteLineGroupId).toString()) is contradicted by
(a) 4 clean structural counter-examples that would fail under H4 but don't, and
(b) the active procedure's only group-keyed aggregate being isNotNull-guarded so null-
group-id survivors never enter it. SM-mix-inside-the-group, not null-group-id survivors,
is the discriminator. Cannot be 100% closed without a live debug-log repro (DML, out of scope).
