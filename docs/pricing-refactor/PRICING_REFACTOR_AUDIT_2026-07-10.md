# Pricing Refactor — Plan-vs-Actual Completion Audit

**Date:** 2026-07-10 · **Snapshot org:** FortraUAT (live) · **Method:** every `D-n` debt item in `PRICING_REFACTOR_PLAN.md` (2026-07-06) mapped to its commit(s) + current live/repo state. Evidence tagged **CONFIRMED** (verified live/commit this pass) / **UNVERIFIED** (ESD-resident or no commit trail).

Evidence artifacts under `Data/pricing-refactor-scratch/live/` (class body snapshot, `DRIFT_TABLE.txt`); commit index in `/tmp/pricing_commits.txt` (82 pricing commits).

---

## Headline verdict

**Waves 0–3 are complete. Wave 4 is substantially complete (~85%).** Of 23 actionable debt items (D-24 is permanently un-fixable), **~19 are DONE**, and the remainder are **owner-gated governance decisions** (D-3, D-21, OQ-2) plus **cosmetic ESD renames** (D-23) — not blocking hardening.

The entire **Apex hook/service layer refactor is finished**: every hook is thinned to an adapter over a testable `*Calculator`/`*Engine`/`*Builder` service, all dead code removed, both duplicate clusters (partner margin, COLA) consolidated, exception-logging live, and 13/13 golden scenarios pass 0-delta. What remains is a few **owner decisions** and **cosmetic canvas cleanup**.

**Two corrections to the plan's baseline assumptions:**
- Active procedure is **V24** (not V21). `VersionNumber 23 + 24 both = Active` — unusual (expected 1 active + 1 inactive backup); flag to verify.
- `force-app` currently matches live for **all 26 in-scope classes present (0 drift)** — the stale-source risk the plan front-loaded is not currently manifesting (point-in-time, not a standing guarantee).

---

## Wave-by-wave completion

### Wave 0 — Harness + docs — ✅ COMPLETE
| Item | Status | Evidence |
|---|---|---|
| D-5 Waterfall documentation artifact | ✅ Done | §7 of plan + `lanes/lane3-waterfall.md`, 8 named invariants |
| D-6 Golden reprice harness | ✅ Done | `9bcf2f7` D-18 gate = **13/13 golden 0-delta, deployed+validated**. *(13-scenario gate operational; breadth vs full §9 matrix not separately audited.)* |
| D-22 `execute()` testability | ✅ Done | thin calculators unit-testable; `2d7af7a`/`41a4e79` test-harden commits |

### Wave 1 — Safe dead-code cleanup — ✅ COMPLETE (1 deferred by decision)
| Item | Status | Evidence |
|---|---|---|
| D-1 Delete V1 partner prehook | ✅ Done | `ea51906`; `PartnerPricingPrehook` absent live+repo (CONFIRMED) |
| D-2 Delete `SourceListPrice*` no-ops | ✅ Done | `849fdf4`; both absent live+repo (CONFIRMED) |
| D-3 Delete `RenewalMaintenanceFlip` | ⏸ Deferred (OQ-3) | still live, **0 refs in force-app** — dead-but-present; retirement gated on OQ-3 |
| D-4 Quarantine `scratch_v210.xml` | ✅ Done | absent from repo root (was untracked 07-06) |
| D-7 Label repo ESD `.xml`/`.bak_preedit` non-authoritative | ⚠️ Open (minor) | `.bak_preedit` sibling still in force-app; housekeeping, no commit |

### Wave 2 — Hook-thinning — ✅ COMPLETE
| Item | Status | Evidence |
|---|---|---|
| Hook thinning (all 6 hooks + posthook) | ✅ Done | `23c6c4e` COLA, `81426b4` AttrVolume, `9a814b0` Hardware, `0df19e7` Regional, `9383f8f` QLDescription, `a1c26a6` CancelLineCredit; **posthook decomposed into 8 increments** (`fef2655`,`c16fa97`,`166e5ff`,`0feb253`,`5356076`,`dd2065f`,`6b43d81`,`156b021`). ~15 new `*Calculator`/`*Builder` classes live |
| D-8 Dedupe MDT loaders | ❓ Unverified | `ContextTagReader` shared-reader dedup done (`156b021`); MDT-loader-specific dedup (COLA/Maint rate ×2) has no direct evidence |

### Wave 3 — Duplicate consolidation — ✅ COMPLETE
| Item | Status | Evidence |
|---|---|---|
| D-11 Unify partner margin services | ✅ Done | `fc10b70` "D-11 complete — unify partner margin to V2 (deal-aware posthook)" |
| D-13 Single COLA engine | ✅ Done | `66b09b1`/`83cac00`/`fcf1c13` (+`c4710b0` delta fix); both surfaces call `COLAUpliftCalculator.resolveTier` |
| D-10 Currency-change design call | ✅ Done | `3a338ec` "drop orphan (D-10)"; `QuoteCurrencyChangeService_Fixed` absent live (CONFIRMED) |
| D-12 E-04 null-`Non_Orig` margin | ✅ Resolved | A-2 first ruled reject-fallback (`d5063ae`), then **set aside** at D-11 completion (`fc10b70`) — owner kept the `effectivePct` fallback (blank `Non_Orig` ⇒ **standard band**, not 0) live; posthook made deal-aware (3-arg `getMarginForProductType(...,dealType)`) |

### Wave 4 — Hardening — 🟡 ~70% (7 of 10 done)
| Item | Status | Evidence |
|---|---|---|
| D-9 Add recursion guards Hardware/Regional | ✅ Done | live snapshot: both now have guards (5 guard-hits each; plan recorded 0) |
| D-14 Hardware tables → MDT | ✅ Done | `96a7f62` (behavior-preserving) |
| D-15 Currency map → MDT | ✅ Done | `3a338ec` (+`4e5279b` retire `CurrencySelectionService`) |
| D-16 Bulkify Order-side invocables | ✅ Done | `7ff7fd6` D-16 governor bulkification |
| D-17 AttrVolume silent reset-to-list | ✅ Done | `6c79166` A-4/D-17 RESOLVED (V21 attribute Net Bridge stale-price fix) |
| D-18 Swallow-to-SUCCESS → exception logging | ✅ Done | `7876aa0` observability + `9bcf2f7` gate |
| D-20 AdvancedListFilter positional (doc) | ✅ Done (doc) | §7 INV-ESD-FILTER-POSITIONAL |
| D-19 StampBaseFilter null-safety (all active-version instances) | ✅ Done on active (re-confirm V24) | active V21 already null-safe per K-01/F-12 (2026-06-30): `(NetUnitPrice>0 OR IsNull)`; residual is inactive versions only (out of scope). Re-verify on V24 |
| D-23 Intra-version clone consolidation | 🔵 Rename-only (low urgency) | reduced to cosmetic renames per Round-5 close-out (0 deletions); INV-28 `RegionalNetReconcileGate` already structurally removed on active version |
| D-21 Currency config-as-code (`Currency_Conversion_Formula__mdt`) | ⏸ Deferred (OQ-6) | boundary/owner-gated; no change |
| D-24 20-version dormant tail | ⛔ N/A | delete platform-blocked; permanent |

---

## Remaining actionable work

Nearly all of it is **owner decisions**, not engineering:

1. **D-3 (OQ-3)** — decide whether `RenewalMaintenanceFlip` is abandoned. *Note: deletion was blocked by an obsolete Flow v7 reference (corrects the plan's INV-10 "zero refs") — retire the flow ref first, or keep.*
2. **D-21 (OQ-6)** — decide whether to move `Currency_Conversion_Formula__mdt` off config-as-code (boundary).
3. **OQ-2 (D-10b)** — decide whether Quote currency-change should actually convert prices + activate the currently-Draft flow (today the wired service is a no-op).
4. **A-5** — deferred item (logged, `9125c5c`); revisit only if a non-Power product carries hardware linkage.
5. **D-23** — cosmetic canvas renames when convenient (in-place-only).
6. **Housekeeping:** D-7 (label repo ESD `.bak_preedit` non-authoritative), D-8 (confirm MDT-loader dedup), re-confirm D-19 null-safety on V24.
7. **Verify:** two Active procedure versions (23 + 24) — confirm intended vs. expected 1 active + 1 inactive backup.

## Open-question ledger
| OQ | Topic | Status |
|---|---|---|
| OQ-1 | E-04 null→catalog vs 0 | ✅ Ruled (blank⇒0) |
| OQ-2 | Currency-change design | ✅ Resolved (orphan dropped) |
| OQ-3 | `RenewalMaintenanceFlip` abandon? | ⏸ Open |
| OQ-4/5 | Hardware/Currency MDT approval | ✅ Approved+implemented (D-14/D-15) |
| OQ-6 | Currency config-as-code | ⏸ Open |

## Beyond the original register (follow-on work, 07-07→07-10)
Round-3 design-compliance escalations **all 7 closed** (`a18a8ae`); Round-6 SDD reconciliation (`af3a470`); A-1 (MyCAP out-year floor), A-3 (ARR apportion on Power splits), A-6 (Regional null-mult guard) resolved; B-1 (COLA audit fields) no-action; plus feature tickets SC-3384 (currency-aware tier lookup), SC-3501 (amend pricing), SC-3544 (blank Sales Price) — these drove the V21→V24 procedure progression.
