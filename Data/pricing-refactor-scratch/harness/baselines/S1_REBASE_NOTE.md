# S1 re-baseline — 2026-07-09
Orphan New-Maintenance line 04267361 (BoKS, no license contributor → native DerivedPricing left it $0,
the R9 finding) was DELETED as malformed test data. S1 went 6 → 5 lines. Baseline re-captured to the
clean 5-line state; prior baseline preserved at S1_quote.pre_orphan_delete.tsv. Not a code change —
the engine correctly refused to price an orphan derived line.
