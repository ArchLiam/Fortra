# SC-3513 Re-Review — after Marc's rework (2026-07-07)

**Reviewer:** Liam Jeong · **Org:** FortraUAT · **Date:** 2026-07-07 · **Read-only.**
**What changed since the first review:** Marc replaced the create-only stamp flow with an **AssetAction-triggered** flow that also resolves the `OrderItemDetail` change-source — directly addressing the two HIGH findings (G-1, G-2).

---

## Verdict: ⬆️ MAJOR IMPROVEMENT — the architecture is now right, but it is NOT yet verified live and category coverage is incomplete. Still not ready to close.

| AC | First review | Now |
|---|---|---|
| **AC-1** (populate) | ✅ PASS | ✅ PASS *by design* — but re-verify: the stamping flow was swapped and no conversion has run since, so the new flow's create path is unproven live. |
| **AC-2** (update on change) | ❌ FAIL | 🟡 **MOSTLY ADDRESSED** — now fires on Upsells + Renewals and resolves the OrderItemDetail source. But unverified live, and Upgrades/Downgrades/Swaps/Downsells/T&C are excluded. |
| **AC-2 ask** (confirm trigger events) | ⚠️ NOT DONE | ⚠️ STILL OPEN — no trigger-event matrix; manual-edit path still uncovered. |

---

## What Marc fixed (credit)

**New flow `Fortra_AssetAction_Stamp_Line_Description`** — Active, created 2026-07-07 12:09 (Marc). Old `Fortra_Asset_Stamp_Line_Description` **deleted** (clean supersede, no dead code).

- **G-1 (update path) — addressed.** Triggers on **AssetAction Create**, async-after-commit, for `CategoryEnum ∈ {Initial Sale, Upsells, Renewals}`. Amendments/renewals/upsells each create a `Change` AssetAction, so the flow now fires on them — not just at asset birth. One flow now covers both initial population and change events.
- **G-2 (OrderItemDetail source) — addressed correctly.** Loops the AssetAction's sources; for each `ReferenceEntityItemId` it tries an `OrderItem` directly, and if that misses, treats it as an `OrderItemDetail` and hops `OrderItemDetail.OrderItemId → OrderItem` for the Description. Verified against schema: `OrderItemDetail` has **no** Description field of its own and **does** expose `OrderItemId → OrderItem`, so the hop is both necessary and valid.
- **Safety added.** Writes only when a non-blank description is found (`D_Have_Description`), so a description-less change can't blank an existing value. Still writes the writable `Asset.Description`.

This is exactly the design recommended in the first review. Good response.

---

## Residual gaps (ranked)

| # | Sev | Title | Evidence / detail | Recommendation |
|---|---|---|---|---|
| **R-1** | **MEDIUM-HIGH** | Category coverage is incomplete | Trigger filter = Initial Sale / Upsells / Renewals. **Excluded:** Upgrades, Downgrades, Swaps, Downsells, Terms-and-Conditions Changes, Cross-Sells. Several of these change *what was purchased* (an Upgrade/Swap/Downsell changes tier/qty/config), so "any time the attributes change" is not fully met. Today's UAT data only has Upsells/Renewals, so it works now — but this is a latent Production gap. | Broaden the filter to all config-changing categories (add Upgrades, Downgrades, Swaps, Downsells, T&C Changes), or trigger on all AssetAction creates except Cancel/Transfer and let the source-resolution decide. |
| **R-2** | **MEDIUM** | Not verified live — no test data exists | **No AssetAction has been created since the flow deployed (12:09)**, and the old flow that stamped yesterday's 4 conversions is deleted. The 16 existing changed assets predate the flow. So neither the new create path (AC-1) nor the update path (AC-2) has actually run against real data. The logic is sound but unproven. | Run one live Q2O conversion (confirms AC-1 didn't regress) **and** one live amendment/renewal on a stamped asset (confirms AC-2). Steps in `VALIDATION_RUNBOOK.md` Part B. |
| **R-3** | **MEDIUM** | "Manual updates on the asset" + trigger-event confirmation still open | A manual Asset field edit does not create an AssetAction, so the flow never fires on it. The reporter explicitly listed "manual updates" and asked to confirm the full event set. | Deliver the trigger-event matrix; decide whether manual edits are in scope (if so, an Asset-update path is needed) or explicitly out of scope. |
| **R-4** | **MEDIUM** | No backfill | 16/16 previously changed assets remain **blank** (re-confirmed today); 430k+ legacy assets also blank. The create-triggered flow will not retroactively stamp them. | Decide go-forward-only vs a one-time backfill of `Asset.Description` from each asset's latest line. |
| **R-5** | **LOW** | "First source with a description wins" | The loop stamps the first source that resolves to a non-blank description and skips the rest. For an AssetAction with multiple line sources (bundle), the chosen line is order-dependent. | Fine if Asset↔line is 1:1; confirm that assumption, else define which source is authoritative. |
| **R-6** | **LOW** | Semantics: is the parent OrderItem the "latest and greatest"? | For an upsell/amendment, the flow stamps the parent OrderItem's Description. Confirm that OrderItem describes the **full new state** of the asset, not just the incremental change line. | Validate on the first live amendment (part of R-2). |
| **R-7** | **LOW** | Source-control drift persists | New flow is **not** in `force-app`; the committed prehook is still the pre-fix baseline. | Commit the new flow + live prehook so the deployed state is reproducible. |

---

## Bottom line
The hard architectural problem from the first review is solved: the field now re-derives on Upsells and Renewals and correctly resolves the OrderItemDetail source. To close SC-3513: (1) **verify live** — one conversion + one amendment (R-2); (2) **broaden category coverage** to the other attribute-changing events (R-1); (3) **answer the trigger-event / manual-edit question** (R-3); (4) **decide backfill** (R-4); (5) commit to source control (R-7). Items 1–3 are the ones standing between this and a pass.
