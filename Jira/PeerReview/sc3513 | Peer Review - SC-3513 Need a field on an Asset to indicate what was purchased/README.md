# SC-3513 — Peer Review of "Need a field on an Asset to indicate what was purchased"

**Reviewer:** Liam Jeong · **Reviewing build:** FORTRA-ASSET-001 (Marc DeBrey) · **Reporter:** Dawn Krauss · **Status:** Testing · **Org:** FortraUAT · **Date:** 2026-07-06 · **All org access read-only.**

## What SC-3513 asks
Two things: **(AC-1)** populate the Asset's description field with a dynamic, attribute-driven string like the Quote/Order "Line Description"; **(AC-2)** keep it updated whenever attributes change — the reporter names **amendment, renewals, manual updates** and asks the builder to **confirm the complete trigger-event set**.

## Verdict (one line)
**PARTIAL — RETURN FOR THE UPDATE PATH.** AC-1 is well built and verified live; **AC-2 is not built** — the field stamps once at Asset creation and never re-stamps on amendment/renewal/manual update. The "confirm no other trigger events" question was never answered.

## What was built (and where it really lives)
- **Flow `Fortra_Asset_Stamp_Line_Description`** — Active in FortraUAT (modified 2026-07-06 by Marc). Trigger = **Asset Create only**, async-after-commit, gated `Description IsNull`. Stamps `Asset.Description` from the source `OrderItem.Description` via `Asset→AssetAction→AssetActionSource→OrderItem`. **Not committed to `force-app`.**
- **`QLDescriptionGeneratorPrehook`** — flat/attribute-less products now get their Product Name (real bug fix). Present in the org; **the committed copy is the stale pre-fix baseline.**
- **`PopulateAssetLegacyFieldsAction`** — reverted (no Description code). Matches repo.
- **`Asset-Asset Layout`** — a "Description Information" section surfaces `Description` (modified 2026-06-23).

## The two decisive facts
- **`Asset.ProductDescription` (the field the ticket names/circles) is system-locked** — `updateable=false, createable=false` (a mirror of `Product2.Description`). The build correctly redirected to the writable **`Asset.Description`**. ✅ good call.
- **The flow triggers on `Create` only.** Amendments/renewals/upsells are `AssetAction Type=Change` on the **existing** asset (17 in the org: 6 Renewals + 11 Upsells) — **no new Asset ⇒ the flow never fires.** All 5 sampled changed assets have `Description = null`. ❌ AC-2 fails by design and by outcome.

## Create path works (verified)
Assets created minutes after deploy carry the correct value, incl. the previously-blank flat product:
`beSECURE - Cloud-Based | Devices: 1001-2000 | One Time | Cloud Based`, `BoKS Administration License Fee`, `Powertech … (BoKS) | 100 Node Bundle | Standard`.

## Confirmed gaps
- **HIGH G-1** — no update on amendment/renewal/manual edit (AC-2 unmet).
- **HIGH G-2** — Change-action source is **not** an OrderItem (prefix `14C`); the current resolution chain wouldn't resolve it even if the trigger were widened.
- **MEDIUM G-3** — "confirm no other trigger events" never answered; deliver an event matrix.
- **MEDIUM G-4** — requested "Product Description" vs delivered "Description": needs business sign-off + clean up the misleading static `ProductDescription` on the layout.
- **MEDIUM G-5** — no install-base backfill (430k+ legacy assets blank).
- **LOW G-6** — deployed artifacts not in source control (drift).
- **LOW G-7** — flow's AssetAction lookup has no `Type=Generate`/`ORDER BY` (non-deterministic if reused for updates); design doc misstates it.

## Smoke test (real data, FortraUAT, 2026-07-06)
Ran a read-only smoke test against existing records (`SMOKE_TEST_SC3513.md`). Flow has one version, created today 21:13, so it could only act on the 8 conversions after that.
- **AC-1 PASS** — 4/4 genuine conversions: `Asset.Description` === `OrderItem.Description` === `QuoteLineItem.Description`, byte-identical (incl. the flat "BoKS Administration License Fee").
- **AC-2 FAIL** — all **16/16** amended/renewed/upsold assets have **blank** `Description`; Create-only trigger can't fire on `Change`; change source is `OrderItemDetail` (14C), not `OrderItem`.
- **AC-2 sub-ask NOT DONE** — no trigger-event analysis.

## Files
| File | Purpose |
|---|---|
| `SMOKE_TEST_SC3513.md` | Real-data smoke test: AC pass/fail matrix, the 4-conversion fidelity trace, the 16 blank changed assets, honest limitation. |
| `PEER_REVIEW_REPORT.md` | Full report: what was built, AC-1/AC-2 verdicts with live evidence, ranked gaps G-1…G-7, recommended update-path design, disposition, caveats. |
| `VALIDATION_RUNBOOK.md` | Read-only SOQL to reproduce every claim + a write-path test plan (needs UAT write authorization) to confirm AC-2 live. |
| `JIRA_COMMENT_SC3513.md` | Paste-ready comment for the ticket. |
| `evidence/FINDINGS.md` | Fact table + all record Ids, describe results, query outputs. |
| `evidence/Fortra_Asset_Stamp_Line_Description.flow-meta.xml` | The retrieved live flow (create-only trigger, resolution chain). |
| `evidence/live_QLDescriptionGeneratorPrehook.cls` | The live prehook (with the flat-product fix the committed repo lacks). |
| `evidence/Asset-Asset-Layout.layout-meta.xml` | The live layout (surfaces `Description`, not `ProductDescription`). |
