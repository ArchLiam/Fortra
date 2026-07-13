# RCA Core Defects — Jira Ticket Breakdown

**Source:** RCA Full-Functionality Test Report — FortraUAT, run 2026-07-11 (CLI/headless, procedure `Rev_Mgmt_Default_Pricing_Procedure V25`).
**Scope:** the **5 FAIL** rows from that run, each promoted to a parent, with sub-tasks that **articulate the identified issue only** (no proposed solution).
**Owner:** Liam. Drafted for hand-entry into Jira (no Jira integration in this environment).

---

## How to use this doc
Each parent below is an existing SC defect. Each sub-task is a copy-paste block mapping to Jira fields:
`Summary` · `Issue Type` (Sub-task) · `Priority` · `Parent` · `Labels` · `Description`.
The Description states the defect only — **Expected behavior / Observed behavior / Evidence / Impact** — no remediation.

**Legend** — `(org✓/git✗)` = live in FortraUAT, not yet committed to git · Priority = Jira defaults (Highest/High/Medium/Low).

### Parent summary
| Parent | Title | Priority | # sub-tasks |
|---|---|---|---|
| SC-3350 | Renewal COLA uplift not applied to Net Unit Price | Highest | 2 |
| SC-3346 | Derived new-maintenance prices $0 | High | 3 |
| SC-3398 | Non-USD lines not priced by currency conversion | Highest | 2 |
| SC-3384 | Non-USD Subtotal / line values still in USD | High | 3 |
| SC-3505 | Amendment omits original Workday contract ID | Medium | 1 |

---

# SC-3350 — Renewal COLA uplift not applied to Net Unit Price
**Type:** Bug · **Priority:** Highest · **Labels:** `rca-pricing`, `cola`
**Parent note:** Behavior is **identical on V24 and V25** — not introduced by any version change. Reproduces on both the native UI "Reprice All" and the headless flow (not a flow artifact). Open question whether this is by-design or a defect — pending product confirmation.

### Sub-tasks

**[Sub-task] SC-3350-1 · Net Unit Price stays at the pre-COLA base despite a correctly-computed COLA uplift**
- Priority: Highest · Labels: `rca-pricing`, `cola`
- Expected behavior: `NetUnitPrice` = prior × (1 + COLA) = **98700** (5%) / **63720** (6.2% CMDT).
- Observed behavior: `NetUnitPrice` stays at **94000 / 60000**. `COLACalculatedPrice` holds the correct 98700 / 63720, but that value is not reflected in the net price.
- Evidence: quote `Ibx3` (renewal, Draft); reprice ×2 idempotent; D-18 exception log clean.
- Impact: renewals bill at the pre-uplift base — the COLA increase is never charged.

**[Sub-task] SC-3350-2 · COLA figure appears transiently on Unit Price / Subtotal, then is not persisted**
- Priority: Medium · Labels: `rca-pricing`, `cola`
- Expected behavior: any COLA value shown on `UnitPrice` / `Subtotal` matches the persisted net.
- Observed behavior: `UnitPrice` / `Subtotal` briefly display the COLA figure as a stale pre-reprice leftover; after reprice it is not carried to net — the display is misleading.
- Evidence: quote `Ibx3`.
- Impact: the UI can imply the uplift applied when it did not.

---

# SC-3346 — Derived new-maintenance prices $0
**Type:** Bug · **Priority:** High · **Labels:** `rca-pricing`, `derived-maint`, `sc-3346`

### Sub-tasks

**[Sub-task] SC-3346-1 · Attribute-less new-maint line prices $0 (missing `Maintenance Type Defn`)**
- Priority: High · Labels: `rca-pricing`, `derived-maint`
- Expected behavior: maint = Base × 0.20 (non-zero).
- Observed behavior: `NetUnitPrice` = **0**. The auto-added derived new-maintenance line has no `Maintenance Type Defn` QLI attribute, so the maintenance tier resolves to 0.
- Evidence: quote `JXMj`, line `Device Profiler-NewMaint` qty1.
- Impact: derived maintenance sells at $0.

**[Sub-task] SC-3346-2 · $0 renewal-maintenance lines reach Workday with no flag or block**
- Priority: Highest · Labels: `rca-pricing`, `derived-maint`, `revenue-leak`
- Expected behavior: a $0 renewal-maintenance line is surfaced before it can be submitted downstream.
- Observed behavior: $0 renewal-maint lines are submitted silently — no error, no flag (D-18 confirms the swallow is invisible).
- Evidence: live impact — **132,823 / 486,584** renewal-maint lines at $0 (27% all-time; 13/18 = 72% last 30d).
- Impact: silent revenue leak — $0 maintenance flows through to billing/Workday.

**[Sub-task] SC-3346-3 · qty>1 renewal maintenance inflated (~100×); one line already escaped to Workday**
- Priority: High · Labels: `rca-pricing`, `derived-maint`, `workday`
- Expected behavior: per-unit = `Asset.Price ÷ Quantity × (1 + COLA)`.
- Observed behavior: the extended (total) amount is used as the per-unit price on qty>1 lines → inflation. Escaped order `00095510` shows **157,500 vs expected ~1,575**.
- Evidence: order `00095510` (already synced to Workday).
- Impact: over-billing on qty>1 maintenance; an incorrect value has already reached Workday.

---

# SC-3398 — Non-USD lines not priced by currency conversion
**Type:** Bug · **Priority:** Highest · **Labels:** `rca-pricing`, `multicurrency`, `sc-3398`
**Parent note:** same underlying currency defect as SC-3384 (below); observed on EUR quote `xy9`.

### Sub-tasks

**[Sub-task] SC-3398-1 · List price shows USD instead of native EUR**
- Priority: High · Labels: `rca-pricing`, `multicurrency`
- Expected behavior: `List` reads the native EUR price-book entry value.
- Observed behavior: `List` reflects the USD value on the EUR quote.
- Evidence: quote `xy9` (EUR).
- Impact: incorrect list basis for every downstream calculation on non-USD quotes.

**[Sub-task] SC-3398-2 · Non-USD net is only approximated after the fact; the procedure performs no currency conversion**
- Priority: Highest · Labels: `rca-pricing`, `multicurrency`
- Expected behavior: `Net` = USD net × currency rate (0.9346), computed within the procedure; `Subtotal` converted.
- Observed behavior: the procedure has no currency-conversion step; net is only approximated by an interim posthook applied afterward, leaving `Subtotal` and some line nets on USD.
- Evidence: quote `xy9` (EUR).
- Impact: currency correctness is inconsistent across lines and depends on a bolt-on rather than the pricing engine.

---

# SC-3384 — Non-USD Subtotal / line values still in USD
**Type:** Bug · **Priority:** High · **Labels:** `rca-pricing`, `multicurrency`, `sc-3384`
**Parent note:** specific line-level symptoms of the same currency defect as SC-3398.

### Sub-tasks

**[Sub-task] SC-3384-1 · Subtotal is in USD while Net is in EUR on the same line**
- Priority: High · Labels: `rca-pricing`, `multicurrency`
- Expected behavior: `Subtotal` in EUR, consistent with `Net × Qty`.
- Observed behavior: line `04266145` `Subtotal` = **857.75 (USD)** vs `Net` = **801.66 (EUR)** — mixed currencies on one line.
- Evidence: quote `xy9` (EUR, Draft).
- Impact: line and quote totals are wrong on non-USD quotes.

**[Sub-task] SC-3384-2 · EUR maintenance line prices $0**
- Priority: High · Labels: `rca-pricing`, `multicurrency`
- Expected behavior: non-zero EUR net.
- Observed behavior: `beSECURE-Cloud` line net = **0** on the EUR quote.
- Evidence: quote `xy9` (EUR).
- Impact: a saleable line prices at $0 in EUR.

**[Sub-task] SC-3384-3 · Context hydration error on native UI reprice (EUR)**
- Priority: Medium · Labels: `rca-pricing`, `multicurrency`, `context`
- Expected behavior: managed reprice completes without error.
- Observed behavior: "went wrong hydrating the context" fires on native UI reprice; the headless flow does not surface it.
- Evidence: `SalesTransactionContextExt_v2`; native UI reprice on the EUR quote.
- Impact: reprice can fail outright for the user on non-USD quotes.

---

# SC-3505 — Amendment omits original Workday contract ID
**Type:** Bug · **Priority:** Medium · **Labels:** `rca-pricing`, `workday`, `amendment`, `sc-3505`

### Sub-tasks

**[Sub-task] SC-3505-1 · `Workday_Contract_ID__c` carries the amend Order's own Id, not the original contract**
- Priority: Medium · Labels: `rca-pricing`, `workday`, `amendment`
- Expected behavior: the payload carries a distinct reference to the original contract, ≠ the amend Order's own Id.
- Observed behavior: `Workday_Contract_ID__c` = the amend Order's OWN Id (`801WC00000koIE3` / `801WC00000ltUiu`); no original-contract reference is present on the payload.
- Evidence: amend orders `00095512` / `00095642`.
- Impact: Workday cannot tie the amendment back to the original contract.

---

## Appendix A — Lanes not scored this run (UI-only; not identified defects)
Headless CLI could not exercise these; they are unverified, not confirmed issues:
- SC-3346 Path-B renewal committed-NET (renewal quote not located headlessly on V25).
- SC-3346 amend-carryover maintenance dedupe smoke (`IBjF` / `IIT` / `J3en` not exercised; `NewMaintenanceDedupeService` org✓/git✗).
- SC-3384 auto-add maintenance PBE currency correction (committed `43fa4d1`; needs cart add on the UI).
- SC-3501 fresh born-net=0 amend leg (needs the UI Amend button + native reprice; baseline healed).
- SC-3513 Asset.Description re-derive on Upgrade/Downgrade AssetAction (committed `47cb089`; AssetAction not Apex-createable).

## Appendix B — Open items (issue-framed, non-scored)
- **SC-3354** — out-year (year-2/3) COLA value is computed (`Final_Year_COLA`) but referenced 0× in the procedure (INERT); scope undecided (Marc/German).
- **Partner-pricing V2 in UAT** — a V2 prehook was customized in UAT by Fortra off-agreement; whether it contributes to the open partner-pricing issue is unconfirmed.
- **Partner-pricing anomaly (found 2026-07-10)** — observed but not yet scored/repro'd; may be a distinct defect.
