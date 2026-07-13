# SC-3513 Smoke Test — Real Data, FortraUAT

**Tester:** Liam Jeong · **Org:** FortraUAT (fortra--uat) · **Date:** 2026-07-06 · **Read-only** (observed existing records; no transactions created — creating amendments/renewals needs write authorization).

**Scope constraint that shaped the test:** the stamping flow `Fortra_Asset_Stamp_Line_Description` has **exactly one version, created today 2026-07-06 21:13Z**. So the only assets it could ever have acted on are the **8 conversions created after 21:13** (all today). Everything older (incl. all 16 amended/renewed assets, created Feb–Jun) predates the flow.

---

## Result matrix

| AC | Requirement | Verdict | Basis |
|---|---|---|---|
| **AC-1** | Asset carries a dynamic line-style description of what was purchased, "just like the Line Description" on order/quote | **PASS** | 4/4 genuine conversions: `Asset.Description` === `OrderItem.Description` === `QuoteLineItem.Description`, byte-identical. Flat product included. |
| **AC-2** | Field re-derives "any time the attributes change" — amendment, renewals, manual updates | **FAIL** | Flow is Create-triggered only → cannot fire on `Change`. All 16 amended/renewed/upsold assets have **blank** `Description`. Change source is `OrderItemDetail`, not `OrderItem`. |
| **AC-2 sub-ask** | "Confirm that this is no other trigger event to cause a change" | **NOT DONE** | No trigger-event analysis was produced. |

**Overall: SC-3513 is HALF-met. Do not pass Testing.** Initial population works well; the "keep it updated" half — the reason the ticket exists beyond a one-time script — is absent.

---

## AC-1 — Populate (PASS). Verified end-to-end on real conversions.

**Population of the 8 post-activation assets:** 8/8 have a non-blank `Description`. Of those, **4 are genuine Quote-to-Order conversions** with a resolvable `OrderItem` source; the other 4 (21:18 batch) have an AssetActionSource with a **null** source Id (not standard conversions — their `Description` was present at insert; the flow's `Description IsNull` gate would skip them, so they are excluded from flow-verification).

**The 4 genuine conversions (21:34) — exact match, whole chain:**

| Asset | `QuoteLineItem.Description` | `OrderItem.Description` | `Asset.Description` | Match |
|---|---|---|---|---|
| 02iWC000008kvl6YAA (beSECURE) | `beSECURE - Cloud-Based \| Devices: 1001-2000 \| One Time \| Cloud Based` | *(identical)* | *(identical)* | ✅ |
| 02iWC000008kvl3YAA (BoKS fee) | `BoKS Administration License Fee` | `BoKS Administration License Fee` | `BoKS Administration License Fee` | ✅ |
| 02iWC000008kvl4YAA (BoKS NewMaint) | — | `Powertech Identity & Access Manager (BoKS)-NewMaintenance \| Standard` | *(identical)* | ✅ |
| 02iWC000008kvl5YAA (BoKS perpetual) | — | `Powertech Identity & Access Manager (BoKS) \| 100 Node Bundle \| Standard` | *(identical)* | ✅ |

Full fidelity trace for the beSECURE line: QLI `0QLWC000003lYxP4AU` → OI `802WC00000PppTYYAZ` (Order `801WC00000mREYjYAO`, Quote `0Q0WC000003GMu50AG`) → Asset `02iWC000008kvl6YAA` — all three `Description` values are identical. This is exactly the "just like the Line Description on the order & quote" requirement.

**Sub-checks:**
- **Format fidelity:** pipe-delimited (` | `) config string, matching the Quote/Order Line Description format. ✅
- **Flat / attribute-less product:** "BoKS Administration License Fee" (0 `ProductAttributeDefinition` rows) renders its Product Name through QLI→OI→Asset instead of landing blank — the prehook fix works in the live flow (repo copy is the pre-fix baseline). ✅
- **Writable field:** written to `Asset.Description` (updateable=true); the requested `Asset.ProductDescription` is system-locked (updateable=false) and shows a stale/generic mirror (e.g. `Devices 1-10 | Subscription | Monthly` on a 1001-2000-device one-time line). Delivered field is surfaced on the sole Asset layout. ✅ (field-label substitution still needs business sign-off — see G-4.)

---

## AC-2 — Maintain on change (FAIL). Proven by design; corroborated by outcome.

**Design proof (airtight):** the flow's start is `<object>Asset</object>`, `<recordTriggerType>Create</recordTriggerType>`, gated `Description IsNull=true`. A Create-triggered flow cannot fire on any update. Amendments/renewals/upsells append an `AssetAction Type=Change` to the **existing** Asset (no new Asset row), so there is no create event to catch. No other automation writes `Asset.Description` (only Asset trigger is `AssetMigrationQueueClearTrigger`, unrelated).

**Outcome corroboration — all 16 changed assets are blank:**

`AssetAction Type=Change` = 17 rows (6 Renewals + 11 Upsells) across **16 distinct assets**. `Asset.Description` result: **16 / 16 BLANK.** Range of change dates: 2026-02-27 → 2026-06-29. Examples: Cobalt Strike renewal `02iWC000008dd1hYAA`; SECURE Exchange Gateway upsells `02iWC000008MuWn/o/p/qYAK`; Renewals `02iWC000008ARwn/oYAG`.

**Change source is the wrong shape for the flow (G-2):** the `Change` action's `AssetActionSource.ReferenceEntityItemId` is key-prefix **`14C` = `OrderItemDetail`** (confirmed via `EntityDefinition`), not `802 = OrderItem`. The flow resolves `OrderItem.Id = ReferenceEntityItemId`, which returns nothing for a change. So even widening the trigger to fire on update would **not** resolve the source — the fix must read the `OrderItemDetail`/amendment line, not an `OrderItem`.

**Honest limitation:** because the flow is only hours old, **no create-stamped asset has yet undergone a change**, so I cannot show a live "was populated → went stale after amendment" example from existing data. The 16 blank assets all predate the flow, so their blankness is consistent with *both* "never create-stamped" and "not update-stamped." The decisive evidence for AC-2 is therefore the **Create-only trigger design** + the **OrderItemDetail source mismatch**, not the blank sample alone. A live amendment-then-observe test (write-authorized) is in `VALIDATION_RUNBOOK.md Part B` to confirm.

---

## What would make AC-2 pass
1. Re-stamp on the change signal — recommend an **`AssetAction`-created** (Type=Change) trigger, resolving the amendment line via `AssetActionSource → OrderItemDetail` (not `OrderItem`), and drop the `Description IsNull` gate so it overwrites.
2. Deliver the trigger-event matrix (amend / renew / upsell / downsell / swap / add-product / manual edit) answering the reporter's "no other trigger events" question.
3. (Optional, per business) backfill the installed base.

Reproduction SOQL for every number above: `VALIDATION_RUNBOOK.md Part A` and `evidence/FINDINGS.md`.
