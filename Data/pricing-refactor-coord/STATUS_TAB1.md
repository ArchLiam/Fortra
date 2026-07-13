# STATUS — Tab 1 (coordinator)

**Round:** 3 — design-compliance (fix-to-SDD). See COORDINATION.md Round-3 + Rule 6.
**MID-DEPLOY:** no
**Updated:** 2026-07-08

## Tab 1 workstream this round
1. **COLA — DONE (no code change).** Investigated all 3 candidate items → COLA Apex is already SDD-compliant:
   - `COLA_Applied_Date__c` is written ONCE at first-application (handler before-insert :331); `handleBeforeUpdate`
     never re-invokes it and the override path uses `COLA_Modified_Date__c`. KB says "when COLA was FIRST applied" → already correct.
   - Rounding: KB §4.1/§10 says "preserve whatever the current implementation does" → no change.
   - Zero/neg: SDD Rule 4 = 0% is a valid unchanged price; base-price guards are fine → no change.
   - RESIDUAL (escalation tail, NOT Apex): audit-field persistence through reprice needs `inputoutput` on
     `SalesTransactionContextExt` (V21 context config) — goes in the Marc/ESD doc.
2. **Maintenance (derived) SDD-compliance** — IN PROGRESS. Verify KB rule #11 (off-list tiers → $0) + the two
   divergent tier resolvers; fix ONLY if the divergence is a clear bug (Rule 6.1), else escalate. Gate: S4.
3. **Marc-escalation doc** (bucket-C rulings): COLA MyCAP precedence (SDD §6 4-tier vs §7.1 3-tier), Partner E-04
   Non_Orig fallback, ARR Asset.ARR__c vs MRR×12, + the COLA context-config residual. — TODO.
4. **Final full-matrix regression** (ALL scenarios) after Tabs 2/3 mark quiescent. — TODO (last).

## Notes for Tabs 2/3
- All Round-3 target files are tracked + clean (Round-2 "AVOID Hardware/Regional" note is STALE — ignore it).
- Per **Rule 6.1**: verify the KB rule is UNAMBIGUOUS before fixing. Escalate (don't fix) if the SDD is silent/
  self-inconsistent OR if the change risks regressing a shipped ticket (e.g. AttrVolume no-match ↔ SC-3390).
- Commit ONLY your own files. Never `git add -A` (tree has Nir's uncommitted `PartnerPricingService*` + unrelated WIP).
