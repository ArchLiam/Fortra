**Peer review + smoke test — SC-3513 (build FORTRA-ASSET-001). Verdict: PARTIAL — does not pass Testing yet. Read-only in FortraUAT, 2026-07-06.**

SC-3513 has two parts. Part 1 (populate) is built and verified. Part 2 (keep it updated on change) is not built.

**Smoke test against real data** (the flow has one version, created today 21:13, so it could only act on the 8 conversions after that): **AC-1 PASS** — 4/4 genuine conversions have `Asset.Description` === `OrderItem.Description` === `QuoteLineItem.Description`, byte-identical (incl. the flat "BoKS Administration License Fee"). **AC-2 FAIL** — all **16/16** amended/renewed/upsold assets have a **blank** `Description`.

**✅ AC-1 — Populate: MET and verified live.**
- The build correctly found that the field the ticket circles — **Asset "Product Description" (`ProductDescription`) — is system-locked** (`updateable=false, createable=false`, a mirror of `Product2.Description`), and redirected to the writable **`Asset.Description`**, surfaced on the layout under a "Description Information" section.
- New assets created after deploy carry the correct dynamic string, e.g. `beSECURE - Cloud-Based | Devices: 1001-2000 | One Time | Cloud Based`. The flat/attribute-less bug is fixed too — `BoKS Administration License Fee` now shows its name instead of blank. Good work on the locked-field diagnosis, the flat-product fix, and the async read-race solution.

**❌ AC-2 — "any time the attributes change … amendment, renewals, manual updates": NOT MET.**
- The stamping flow triggers on **Asset Create only** (gated `Description IsNull`) — so it stamps once at asset birth and never again.
- Amendments/renewals/upsells don't create a new asset; they add an `AssetAction Type=Change` to the **existing** asset (the org has 17: 6 Renewals + 11 Upsells). The Create flow never fires for those. Every one of the 5 changed assets I sampled has **`Description = null`** today (Cobalt Strike renewal, SECURE Exchange Gateway upsells, etc.).
- The extra ask — **"confirm that this is no other trigger event to cause a change"** — was not answered; there's no trigger-event analysis.
- Extra wrinkle for the fix: the Change action's source is **not** an OrderItem (`ReferenceEntityItemId` is prefix `14C`, not `802`), so the current `…→OrderItem` chain wouldn't resolve it even if the trigger were widened.

**To close SC-3513:**
1. Build the update path so amendment/renewal/upsell/manual-edit re-stamp the field (recommend an **AssetAction-anchored** re-stamp, not an Asset-update flow — resolving the Change-action `14C` source, not OrderItem).
2. Deliver the trigger-event matrix the reporter asked for (which events are in/out of scope).
3. Confirm with @Dawn that the value under **"Description"** satisfies the "Product Description" request, and clean up the now-misleading static `ProductDescription` on the layout.
4. Decide install-base backfill (430k+ legacy assets are blank today).
5. Commit the flow + live prehook to source control (currently only in the org; the repo copy is the pre-fix baseline).

Full report, evidence, and a reproduction runbook: `Jira/PeerReview/sc3513 | Peer Review - SC-3513 …/`.
