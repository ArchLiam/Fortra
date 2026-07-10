# SC-3516 Peer Review — Round 3: SC-3505 (re-scoped to "Inbound Asset Stamp As-Built")

**Reviewer:** Liam Jeong · **Org:** FortraUAT (read-only) · **Date:** 2026-07-08 · Reviewing the re-written ticket + Marc's "in-place and ready for re-test" claim.

## Verdict

**NOT READY — and this is a re-scope, not a completion.** Marc has replaced the body of SC-3505 with a **documentation-only as-built of a different automation** — the *inbound* Asset line-reference stamp (`Fortra_OrderItem_Stamp_Asset_Workday_ID`) — and explicitly declared the *outbound* original-contract key (SC-3505's actual subject) out of scope. The as-built write-up is mostly accurate and honest, but:

- it does **not** satisfy SC-3505's own Acceptance Criteria (which are about the outbound original-contract reference),
- "ready for re-test" is inaccurate — the documented flow **has never fired and cannot be exercised**, and
- one **factual claim is wrong** (the Asset field is *not* in source control).

Credit where due: the current-state section is honest (it adopts the "deployed ≠ working, never fired" finding), and the flow mechanics are documented correctly.

---

## BLOCKER 1 — The ticket no longer matches its own Acceptance Criteria

The header + ACs are unchanged and describe the **outbound** concern:
> AC1 "Original Workday contract identifier is stored on the amendment transaction"; AC3 "Workday can identify which existing contract should be amended."

That is `Order.Workday_Contract_ID__c` (SF → Workday). The new body documents `Asset.Workday_Contract_Line_Reference_ID__c` (Workday → SF) and **states the outbound key is out of scope**. Different field, different object, opposite direction.

**So the body neither meets nor addresses AC1–AC3.** A ticket can't be "ready" while its own ACs are untouched. Either (a) rewrite the header + ACs to match the inbound documentation scope, or (b) this content belongs on a *separate* ticket and SC-3505 keeps its original ACs. As it stands the ticket contradicts itself top-to-bottom.

## BLOCKER 2 — "Ready for re-test" is not accurate; there is nothing to test

The documented flow **has never fired.** Re-verified today (2026-07-08):

| Field | Populated | Total |
|---|---|---|
| `OrderItem.Workday_Contract_Line_Reference_ID__c` (source/trigger) | **0** | 230,360 |
| `Asset.Workday_Contract_Line_Reference_ID__c` (destination) | **0** | 430,713 |

The ticket itself says so ("deployed does not mean working… has never fired… dormant by design"), and the Notes admit you must **manually type a value** to test it because the Workday feed doesn't populate the source. A documentation-only ticket describing a dormant flow is not "ready for re-test" — at most it's "ready for doc review." Correct status: **as-built documentation; deployed-but-dormant; not exercisable until the Workday feed lands.**

## BLOCKER 3 — The real SC-3505 requirement is being dropped under cover of the re-scope

SC-3505 is **High priority, "Required for Workday amendment processing,"** and its ACs are the outbound original-contract reference so Workday can amend the right contract. The rewrite punts that to *"track it as its own new ticket if still needed."* Two sessions ago the team agreed to **park** the outbound work pending MuleSoft; now the ticket number has been quietly repurposed to the inbound doc.

**Risk:** if SC-3505 is closed on this documentation, the outbound business requirement silently disappears. Before anything closes, confirm the outbound requirement **and** its parked MuleSoft dependency live in a **real, tracked, linked** ticket — not a sentence. The outbound flow is still unchanged and confirms nothing was delivered on the original ask: `Fortra_Order_Workday_Contract_ID` = **V3 Active, own-Id stamp, last modified 2026-04-27 by Ben Kozlowski.**

## HIGH — Factual error: the source-control claims are wrong (capture gap is bigger than stated)

The ticket says the Asset destination field is *"Tracked in source control at force-app/main/default/objects/Asset/fields/,"* and **AC #7** asserts it *"is present in source control."* **It is not.** A full search of `force-app` finds **neither** field:

| Component | In source control? |
|---|---|
| Flow `Fortra_OrderItem_Stamp_Asset_Workday_ID` | ✅ tracked |
| `Asset.Workday_Contract_Line_Reference_ID__c` (destination) | ❌ **NOT tracked** (ticket claims it is) |
| `OrderItem.Workday_Contract_Line_Reference_ID__c` (source) | ❌ not tracked (ticket admits this) |

So the capture gap covers **both** fields, not just the OrderItem one, and **AC #7 fails as written.** Fix: capture both fields into `force-app` and correct the "Fields & Objects" tracking note.

## HIGH — Unflagged correctness risk: the lineage can stamp the WRONG Asset, and it goes live exactly when MuleSoft turns on

`Get_Asset_Action_Source` takes the **first** `AssetActionSource WHERE ReferenceEntityItemId = OrderItem.Id` with **no ORDER BY and no `AssetAction.Type` filter** (`getFirstRecordOnly=true`, `assignNullValuesIfNoRecordsFound=false`). On live data:

- **~5,846 OrderItems already have more than one `AssetActionSource`** (176,574 rows across 170,728 distinct OrderItems), and
- `AssetAction.Type` in this org = **Generate, Change, Cancel**.

So for any line with multiple asset actions — **amendments / changes / cancels, i.e. exactly the lifecycle this feed is being built for** — the flow can resolve a non-deterministic or non-`Generate` action → **stamp the wrong Asset** (or a Cancel/Change action's asset). That directly breaks **AC #4** ("the exact Asset that order product created — no cross-line bleed"); the guarantee does not hold for multi-action lines.

The sibling Apex that walks the **same** lineage (`PopulateAssetLegacyFieldsAction`, `BackfillAssetHardwareBatch`) both filter `AssetAction.Type='Generate'` **and** `ORDER BY CreatedDate DESC`. This flow does neither — it is strictly less robust than the established pattern. It's latent only because the source field is empty today; the moment MuleSoft starts writing it (the whole point of the ticket), the defect becomes live, and amendments/renewals hit it first. **Recommend:** add `AssetAction.Type='Generate'` (or a deterministic ORDER BY) to the lookup before this is exercised, and if any manual QA is run, use a **multi-asset-action line** specifically to expose it.

## What's accurate (keep)

- Flow mechanics match the deployed metadata exactly: OrderItem trigger, `RecordAfterSave` Create+Update, requires-record-changed = true, entry `Workday_Contract_Line_Reference_ID__c IS NOT null`, `SystemModeWithoutSharing`, API 62.0, and the 3-step lineage `AssetActionSource.ReferenceEntityItemId = OrderItem.Id → AssetAction → Asset`. ✅
- The honest current-state ("never fired, 0 of 230k") — good, and independently re-confirmed. ✅
- Correctly identifies the upstream Workday-feed dependency and flags that the automation "may need revision pending the amendment/renewal/cancellation solution." ✅

## LOW

- AC #2 still says **"Permendor"** — it's MuleSoft / Permender.
- If the scope is truly inbound-only now, the stale header + original-contract ACs must be **removed**, not left contradicting the body.

---

## Disposition & recommendation

**Do not accept as "SC-3505, ready for re-test."** As a standalone piece of documentation the inbound as-built is ~90% sound, but the ticket identity, scope, status label, and one factual claim are wrong.

1. **Split cleanly.** Move this inbound as-built to its own ticket — the body already titles it **FORTRA-CONTRACT-014**. Keep **SC-3505 = the outbound original-contract requirement** (parked: blocked on MuleSoft + SF design rework, per Round 2). Don't reuse SC-3505's number/ACs for a different deliverable.
2. If the team truly wants SC-3505 *to be* the inbound doc, **rewrite the header + ACs** to match and **link a tracked successor** that owns the outbound requirement (+ the parked MuleSoft dependency).
3. **Fix the source-control error** — capture `Asset.Workday_Contract_Line_Reference_ID__c` **and** `OrderItem.Workday_Contract_Line_Reference_ID__c` into `force-app`; correct AC #7 and the Fields table.
4. **Re-label status** — "as-built documentation; deployed-but-dormant," not "ready for re-test."
