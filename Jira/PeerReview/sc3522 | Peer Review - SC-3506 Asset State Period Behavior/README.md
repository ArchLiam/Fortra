# SC-3522 — Peer Review of SC-3506 (Asset State Period Behavior)

**Reviewer:** Liam Jeong · **Parent:** SC-3506 (RCA Investigation Task — Marc Debrey / Dawn Krauss) · **Org:** FortraUAT · **Date:** 2026-07-01 · **All org access read-only.**

## What SC-3506 asks
Document the *expected* AssetStatePeriod (ASP) creation behavior for **Amendments, Renewals, Cancellations**; verify the FortraUAT implementation matches; identify gaps. Motivation: **license-key generation depends on the latest state-period attributes**.

## Verdict (one line)
**NEEDS REWORK before close.** The *core native ASP mechanics are correct and validated* (amendment period-split, renewal forward-dating, cancellation-no-period). But the deliverable needs 3 factual corrections, re-labeling of the 2 real HIGH defects as **upstream pricing bugs** (not ASP-engine), a corrected LKG section, and an expanded test sample (AC #2 only weakly met — no live Downsell/Cross-Sell/Upgrade/Downgrade/Swap/T&C; cancellation n=1).

## Files
| File | Purpose |
|---|---|
| `PEER_REVIEW_REPORT.md` | Full report: expected-behavior spec, observed-vs-expected per scenario, ranked gaps (post-verification), LKG impact, disposition. |
| `VALIDATION_RUNBOOK.md` | Executable validation: read-only inventory SOQL, per-scenario manual test procedure, pass/fail checklist, regression queries for the 4 anomalies. |
| `evidence/EVIDENCE_BUNDLE.md` | Ground-truth org data captured live (object model, distribution, the 16 lifecycle actions, ASP rows per asset, LKG dependency). |
| `evidence/workflow_findings.json` | Structured output of the multi-agent review (scenario analyses, web claims, LKG, adversarial verdicts). |

## Confirmed gaps (post adversarial verification)
- **HIGH — GAP-1:** 06tCOTYA2 renewal produced a **12-year** period (→2039). Root cause = **upstream `PricingTermCount=12`** (months read as years), cf. SC-3297. *Not* an ASP-engine bug.
- **HIGH — GAP-2:** mrr=0 renewal periods (08FcLaYAK, 08LXfZYAW) = **upstream COLA zero-price**, route to SC-3350/SC-3346.
- **MEDIUM:** stale Asset current rollups (08LXfZYAW header 0/0 vs active period 100/162.5); native uplift mechanism unused (0 PriceRevisionPolicy / UnitPriceUplift / UnitPrice); renew-then-cancel edge undetermined at n=1.

## Corrections the draft must fold in (things that are NOT bugs)
- **Retract** the "overlapping periods on 08LXfZYAW" claim — periods tile contiguously (artifact of sorting by CreatedDate instead of StartDate).
- **Null ASP EndDate on 08DFvvYAG is correct** — BoKS-NewMaintenance is a **OneTime** product (~42% of all ASP rows carry null EndDate). Source license expiry from the **Contract**, not the ASP.
- **Same-day "no split" is expected** — discriminator is *effective date == asset start date*, not calendar day.
- **LKG** reads `Asset.Quantity` + `Asset.LifecycleEndDate` (not ASP, not CurrentQuantity); hardware key path is currently inert → ASP anomalies are prospective/data-integrity risks, not proven mis-issued keys.
