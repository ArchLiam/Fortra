# S11 baseline re-based 2026-07-07 (incr 12)

The prior S11_quote.tsv baseline held 2 "Advanced Authentication Modes" lines, but the
live scenario quote 0Q0WC000003GMu5 now carries a different 4-line BoKS product set
(Powertech IAM (BoKS) + NewMaintenance, beSECURE, BoKS Administration License Fee).
A behavior-preserving refactor cannot swap products, so this was test-data drift, not a
regression. The old baseline was never a valid oracle for the current product set.

Re-based to the current converged snapshot, verified by IDEMPOTENCY (reprice 1st == 2nd,
0-delta) under incr-12 code. Attribute-tier + derived-maintenance lines price sanely
(NewMaintenance net 62.48; partner 15/18%). NOTE: this baseline is post-refactor, so it
gates FUTURE regressions only — it is not a pre-refactor oracle.
