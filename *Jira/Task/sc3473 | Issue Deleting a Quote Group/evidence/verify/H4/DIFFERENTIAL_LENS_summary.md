# H4-null-group-id-summary-collision — DIFFERENTIAL LENS verdict: REFUTED

## H4's mechanism (restated)
Native builds Map<QuoteLineGroupId, groupSummary> from pre-delete state, then iterates surviving
lines calling map.get(survivor.QuoteLineGroupId).toString(). Survivors have QuoteLineGroupId=null,
so get(null) -> null -> .toString() NPE. The throw key, per H4, is the SURVIVORS' null group id.
=> H4 is invariant to the DELETED group's SM-mix / HW-type / markup. It depends ONLY on survivors
   having null group id after the only group is deleted.

## Counter-example attack (read-only, FortraUAT)
D01/D02: 7 quotes have exactly one populated group + null-group survivors (the H4 shape).
Restricting to CLEAN single-group quotes (1 group total incl. empty; deleting it leaves only null survivors):

| Quote              | Status    | DeletedGrp SM | Survivor SM | HW-type | Failing |
|--------------------|-----------|---------------|-------------|---------|---------|
| 0Q0WC000002U2020AC | Accepted  | MIX(OT+TD)    | TermDefined | True    | YES     |
| 0Q0WC0000039E8T0AU | Accepted  | TermDefined   | TermDefined | False   | no      |
| 0Q0WC000003AaoT0AS | Draft     | TermDefined   | MIX(OT+TD)  | False   | no      |
| 0Q0WC0000027oGf0AI | In Review | TermDefined   | TermDefined | False   | no      |
| 0Q0WC0000038GFZ0A2 | Draft     | TermDefined   | TermDefined | False   | no      |

D08: 0Q0WC0000039E8T0AU survivors = 2x TermDefined, null group id, cfg=Allowed — STRUCTURALLY
IDENTICAL survivor profile to the failing quote, SAME Accepted lock-state. Deleting its only
group leaves exactly those null-group survivors to reprice. Not reported failing.

D03: 165,208 quotes org-wide carry null-group lines that reprice through this native engine on
every add/edit/reprice. A generic Map.get(null).toString() intolerance would brick the org.

## Why this REFUTES (not merely fails to confirm)
H4's key is the survivors' null group id. That null is IDENTICAL across all 5 clean single-group
twins. H4's mechanism therefore predicts all 5 throw the same NPE. Only 1 does. The differentiator
that actually tracks the failure (deleted-group OneTime/TermDefined SM-MIX + HW-type=True, Mission E)
lives on the DELETED group — a dimension H4 explicitly does not model. So the thrown null key, if a
map, is NOT keyed by survivors' null group id.

## Honest caveat (cannot be closed read-only)
The 6 twins are "not reported failing," not "delete-verified to succeed" (delete = DML, out of scope).
So this is refutation-by-prediction-mismatch, not by an observed clean delete. To positively confirm a
clean delete of a twin, or to confirm the key is the deleted-group SM-mix, requires a debug-log repro (DML).
