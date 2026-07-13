# SC-3513 Peer Review Report — "Need a field on an Asset to indicate what was purchased"

**Reviewer:** Liam Jeong · **Org:** FortraUAT (fortra--uat) · **Date:** 2026-07-06 · **All org queries read-only (no writes, no deploys).**

**Ticket under review:** SC-3513 — Assignee Liam Jeong, Reporter Dawn Krauss, Status **Testing**.
**Build under review:** "FORTRA-ASSET-001 — Quote Line Description Now Flows Reliably to the Asset" (author Marc DeBrey), reported COMPLETED/verified in fortrauat. Components: `QLDescriptionGeneratorPrehook` (flat-product fix), new Flow `Fortra_Asset_Stamp_Line_Description`, reverted `PopulateAssetLegacyFieldsAction`, and an Asset-layout change surfacing `Description`.

---

## 1. Executive Summary & Verdict

**Verdict: PARTIAL — RETURN FOR THE UPDATE PATH. The initial-population half of SC-3513 is genuinely well built and is verified working live; the second, explicitly-required half — keep the field current when attributes change via amendment / renewal / manual update — is not built at all. As delivered, the field stamps once at Asset birth and never again.**

SC-3513 has two distinct requirements:

1. **Populate** the Asset with a dynamic, line-style description of what was purchased (like the Quote/Order "Line Description"). ✅ **MET and verified.**
2. **Keep it updated** "any time the attributes change … amendment, renewals and manual updates on the asset," and **"confirm that this is no other trigger event."** ❌ **NOT MET.** No update trigger exists, no trigger-event analysis was done, and the installed base is not backfilled.

The build is technically sharp where it exists: it correctly diagnosed that the field the ticket names — **`Asset.ProductDescription`** — is a **system-locked mirror** (`updateable=false, createable=false`, confirmed by describe) and redirected to the writable **`Asset.Description`**; it fixed a real bug where flat/attribute-less products (e.g. "BoKS Administration License Fee") produced no description; and it solved a genuine read-race by stamping from an async after-commit flow. I reproduced the create path live: assets created minutes after deploy carry the correct dynamic value (§5 evidence).

But the flow's trigger is **`recordTriggerType = Create`**, gated on **`Description IsNull = true`**. By construction it cannot fire on any later change. The org already contains **17 `Change` AssetActions** (6 Renewals + 11 Upsells) on existing assets — precisely the events the ticket enumerates — and every one of those assets currently has a **blank `Description`**. So requirement #2 fails both by design and by observed outcome.

**Recommendation:** Keep the create-path work (it's good). Do **not** close SC-3513 on it. Build the update path (design in §7), answer the ticket's "confirm no other trigger events" question explicitly, get business sign-off on the `Description`-vs-`ProductDescription` field/label substitution, and decide on install-base backfill.

**Gaps folded into this report: 7** (2 HIGH, 3 MEDIUM, 2 LOW).

---

## 2. What SC-3513 Requires (verbatim)

> On the Asset, update the 'Product Description' field to be a dynamic string to include the attributes of what was purchased just like how the "Line Description" works on the order & quote.
>
> Additionally, any time the attributes change, this field needs to be updated with the latest and greatest description attribute values. This functionality already works on quotes. We need the same on the Asset field.
>
> I believe the action that can cause it to change are amendment, renewals and manual updates on the asset. Confirm that this is no other trigger event to cause a change.

**Two acceptance obligations, read plainly:**
- **AC-1 (populate):** the Asset field shows the dynamic, attribute-driven line description.
- **AC-2 (maintain):** the field re-derives whenever attributes change — the reporter names **amendment, renewals, manual updates** and asks the builder to **confirm the complete trigger-event set**.

---

## 3. What Was Actually Built (ground truth, not the doc's claims)

| Component | State in live FortraUAT | In committed `force-app`? |
|---|---|---|
| Flow `Fortra_Asset_Stamp_Line_Description` | **Active**, modified 2026-07-06 21:13 (Marc DeBrey) | **Absent** — not committed |
| `QLDescriptionGeneratorPrehook` flat-product fix | **Present** (iterates all lines; emits product-name for attribute-less lines) | **Absent** — local copy is the *pre-fix* baseline |
| `PopulateAssetLegacyFieldsAction` | No Description code (baseline) | Matches |
| `Asset-Asset Layout` "Description Information" section w/ `Description` | **Present**, modified 2026-06-23 (Marc DeBrey) | n/a |

**The flow, exactly as built** (retrieved XML in `evidence/`):

```
Trigger:   Asset, recordTriggerType = Create, RecordAfterSave
Entry:     Description IsNull = true  AND  HasLifecycleManagement = true
Path:      AsyncAfterCommit (scheduled)
Resolve:   Get_Asset_Action  (AssetId = $Record.Id, getFirstRecordOnly, NO Type filter)
        -> Get_Asset_Action_Source (AssetActionId = above)
        -> Get_Source_Order_Item   (OrderItem.Id = AssetActionSource.ReferenceEntityItemId)
Action:    Asset.Description = Get_Source_Order_Item.Description   (only if that Description IsNull = false)
```

Two design-doc↔build discrepancies worth recording: (a) the doc says the AssetAction lookup filters **`Type = Generate`** — **it does not** (AssetId only); (b) the doc describes prose the code doesn't match in the *committed* repo because the fix lives only in the org (see G-6).

---

## 4. Requirement AC-1 (Populate) — MET ✅ (verified live)

The flow (re)deployed at 21:13 today; I sampled `Generate` assets created minutes later (full table in `evidence/FINDINGS.md §5`):

| Asset | `Description` (stamped) | `ProductDescription` (locked mirror) |
|---|---|---|
| 02iWC000008kuVhYAI | `beSECURE - Cloud-Based \| Devices: 1001-2000 \| One Time \| Cloud Based` | `Devices 1-10 \| Subscription \| Monthly` |
| 02iWC000008kvl3YAA | `BoKS Administration License Fee` | `Other` |
| 02iWC000008kvl5YAA | `Powertech Identity & Access Manager (BoKS) \| 100 Node Bundle \| Standard` | `Perpetual \| Standard` |

This proves three things the build got right:
1. **Async create stamp works end-to-end** — `Asset.Description` carries the line-style, pipe-delimited config.
2. **The flat-product fix works** — "BoKS Administration License Fee" (0 `ProductAttributeDefinition` rows) now renders its Product Name instead of landing blank (was a real defect on Quote/Order/Asset).
3. **The writable-field choice is vindicated by the data** — `Description` holds the *purchased* config (`Devices: 1001-2000 | One Time`), while `ProductDescription` shows a stale/generic mirror (`Devices 1-10 | Subscription | Monthly`). The requested field literally cannot show the right value; the delivered field does.

**Field describe confirms the constraint** (`evidence/FINDINGS.md §1`): `Asset.ProductDescription` — `updateable=false, createable=false`; `Asset.Description` — `updateable=true`. Redirecting to `Description` is the correct engineering call. It is surfaced on the sole Asset layout under a "Description Information" section (modified 2026-06-23), so users can see it.

---

## 5. Requirement AC-2 (Maintain on change) — NOT MET ❌ (the core gap)

**By design.** The flow triggers on `Create` only. Salesforce record-triggered flows fire exclusively for their configured trigger type — a `Create` flow never runs on update. There is no update-triggered flow, no Apex, no other automation writing `Asset.Description` (only Asset trigger in the org is `AssetMigrationQueueClearTrigger`, unrelated). Even the entry gate `Description IsNull = true` makes the flow **create-once, never-restamp**.

**By RCA lifecycle.** Amendments, renewals, upsells, downsells, T&C changes do **not** create a new Asset — they append an **`AssetAction` of `Type = Change`** (+ new `AssetStatePeriod`) to the **existing** Asset. Confirmed distribution in the org: `Generate` 430,671 (legacy bulk load) vs **`Change` 17** (`Renewals` 6 + `Upsells` 11) + `Cancel` 3. No `Create` event ⇒ the flow never fires for the very events the ticket lists.

**By observed outcome.** Every one of the 5 sampled changed assets has `Description = null` while its `ProductDescription` shows only static product text (`evidence/FINDINGS.md §4b`): e.g. Cobalt Strike (renewed 07-02) → `Description=null`; two SECURE Exchange Gateway assets (upsold 06-16) → `Description=null`. After a renewal/upsell, the field the ticket is about is **empty**.

**Deeper problem for whoever fixes this:** the `Change` action's source is **not** an OrderItem. `AssetActionSource.ReferenceEntityItemId` on the Upsell action `4nLWC0000038vdi2AA` is key-prefix **`14C`** (not `802`), and querying `OrderItem` by that Id returns 0 rows. So the flow's current resolution chain (`OrderItem.Id = ReferenceEntityItemId`) **would not resolve a Change action even if the trigger were widened to update.** The fix is not "add Update to the trigger" — it must handle the change-path source entity.

**Unanswered ticket ask.** The reporter explicitly asked the builder to **confirm the full set of trigger events**. No enumeration was produced. A correct answer must at minimum cover: amendment orders, renewal orders, upsell/downsell/swap orders (all `Type=Change`), add-product amendments (which *do* create a new Asset and *are* covered by the create path), manual Asset edits, and manual Quote/Order line edits before conversion. This analysis is a deliverable in its own right and is missing.

---

## 6. Gaps / Risks — Ranked

| # | Sev | Title | Evidence | Recommendation |
|---|---|---|---|---|
| **G-1** | **HIGH** | No update on amendment/renewal/manual edit (AC-2 unmet) | Flow `recordTriggerType=Create`, gated `Description IsNull`. 17 `Change` actions on existing assets; all 5 sampled changed assets have `Description=null`. | Build the update path (§7). This is required to satisfy the ticket, not optional polish. |
| **G-2** | **HIGH** | Change-path source is not an OrderItem | `AssetActionSource.ReferenceEntityItemId` on a Change action is prefix `14C`; `OrderItem WHERE Id='14C…'` → 0 rows. | The update solution must resolve the Change-action source entity (14C), not reuse the Generate-path `OrderItem` chain. Confirm what `14C` is (likely a product/asset-relationship item) before designing. |
| **G-3** | **MEDIUM** | "Confirm no other trigger events" was never answered | Ticket asks explicitly; design doc has no enumeration. | Deliver a written trigger-event matrix (amend / renew / upsell / downsell / swap / add-product / manual asset edit / manual line edit) with in/out-of-scope per event. |
| **G-4** | **MEDIUM** | Requested field vs delivered field — needs business sign-off | Ticket names/screenshots **"Product Description"** (`Asset.ProductDescription`, system-locked). Build delivers **`Asset.Description`** under a "Description Information" section (label "Description"). | Confirm with Dawn/business that the value under **"Description"** satisfies the request, and decide whether to relabel the field or remove the now-misleading static `ProductDescription` from the layout (it shows generic text and will read as "wrong"). |
| **G-5** | **MEDIUM** | No install-base backfill | 430k+ legacy assets predate the flow; `Description` cannot be filtered, but sampled legacy/changed assets are blank. | Decide scope: go-forward only, or a one-time backfill of `Asset.Description` from the latest line for existing lifecycle assets. State it explicitly either way. |
| **G-6** | **LOW** | Source-control drift — fix lives only in the org | Flow absent from `force-app`; committed `QLDescriptionGeneratorPrehook` is the pre-fix baseline; doc's "feature branches" not in this checkout. | Commit the flow + the live prehook to source control so the deployed state is reproducible and reviewable; reconcile the version header (still `@version 8.0`) with the actual change. |
| **G-7** | **LOW** | Doc↔build mismatch + non-deterministic AssetAction pick | Doc claims a `Type=Generate` filter; flow filters AssetId only with `getFirstRecordOnly` and no `ORDER BY`. Harmless at create (one action) but wrong if reused for updates. | Add `Type='Generate'` (or an explicit `ORDER BY CreatedDate`) so the lookup is deterministic and correct if the flow is ever extended. |

---

## 7. Recommended Design for the Update Path (my recommendation)

**Add an `AssetAction`-anchored re-stamp so the description follows every lifecycle change, not just birth.**

1. **Trigger on the change signal, not on Asset update.** The reliable, RCA-native signal that "this asset's config changed" is a **new `AssetAction`** (`Type = Change`) — one is created for every amendment/renewal/upsell/downsell/swap. Prefer an **`AssetAction`-created record-triggered flow** (or Apex on `AssetAction`) over an `Asset`-update flow, because Asset field-edits don't reliably reflect config changes and an Asset-update flow risks recursion.
2. **Resolve the current line from the Change action** — `AssetAction (Type=Change) → AssetActionSource → <14C source entity>`. Because `ReferenceEntityItemId` is not an OrderItem here (G-2), first confirm the `14C` object and its description-bearing field; if the amendment/upsell **OrderItem** is reachable another way (e.g. via the Order the AssetAction ties to), source the description from there to match AC-1's format.
3. **Handle manual edits (if in scope per G-3).** If "manual updates on the asset" means a user changing config, decide whether that path exists in RCA at all; if it does, it also emits an `AssetAction` and is covered by step 1. If it means editing raw Asset fields, an Asset-update flow that re-derives from the latest `AssetStatePeriod`/line is the fallback — but scope it carefully to avoid clobbering intentional manual text.
4. **Drop the `Description IsNull` gate for the update path** — an update must overwrite the now-stale value (the create path can keep the gate to avoid double-work).
5. **Backfill decision (G-5).** If the business needs existing assets correct, run a one-time stamp from each asset's latest line.
6. **Deterministic create-path lookup (G-7).** Add `Type='Generate'` to the create flow's AssetAction lookup.

**Why AssetAction-anchored over Asset-update-triggered:** it fires exactly when the config actually changes, uses the same lineage the create path already trusts, covers amend/renew/upsell/downsell/swap uniformly, and sidesteps Asset-update recursion. It also gives a natural home for the trigger-event matrix the reporter asked for.

---

## 8. Peer-Review Disposition

**Disposition: SC-3513 — DO NOT PASS TESTING YET. AC-1 met and verified; AC-2 not built.**

Before this can close, the build must:
1. **Deliver the update path (G-1/G-2)** so amendment/renewal/upsell re-stamp `Asset.Description`. Today those events leave it blank.
2. **Answer the "confirm no other trigger events" question (G-3)** with an explicit event matrix.
3. **Get business sign-off on the field/label substitution (G-4)** — value lives in "Description," not the "Product Description" the ticket circled — and clean up the now-misleading static `ProductDescription` on the layout.
4. **Decide install-base backfill (G-5).**
5. **Commit the deployed artifacts to source control (G-6)** and make the create-path AssetAction lookup deterministic (G-7).

Credit where due: the create-path engineering (locked-field diagnosis, flat-product fix, read-race → async stamp, live verification, layout surfacing) is solid and should be kept as-is. The gap is scope-completeness against a two-part ticket, not code quality on the part that was built.

---

## 9. Caveats & Limitations

1. **Read-only, UAT only.** All findings from `sf sobject describe`, `sf data query`, and metadata retrieve against FortraUAT. No writes/deploys. No Production parity claim.
2. **AC-2 proven by design + outcome, not by a live re-stamp test.** I did not run an amendment/renewal end-to-end (would require org writes; not authorized). The create-only trigger and the blank `Description` on all 17 change-affected assets are together conclusive, but a live amendment-then-observe test is the final confirmation (runbook provides the steps for whoever has write access).
3. **`14C` object not fully identified.** Confirmed it is not `OrderItem` (0 rows) and is the Change-action source; its exact SObject/field was not resolved and should be before building the update path (G-2).
4. **`Asset.Description` is unfilterable** (long textarea) — coverage was assessed by SELECT+inspect on targeted samples, not an aggregate COUNT. The samples are the real recent transactional assets, not a random draw.
5. **Design doc taken at face value for intent**, but every factual claim in it was re-checked against the org; where they diverge (Type=Generate filter; committed-repo state), this report follows the org, not the doc.
