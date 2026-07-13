{panel:title=🔎 PEER REVIEW + SMOKE TEST — VERDICT: ⚠️ PARTIAL (DO NOT PASS TESTING)|titleBGColor=#FF8B00|bgColor=#FFFAE6}
*SC-3513 has two halves.* Half 1 (populate the Asset) is built and *verified working*. Half 2 (keep it updated when attributes change) is *not built*.
Reviewed read-only in *FortraUAT*, 2026-07-06. Build = FORTRA-ASSET-001 (Marc DeBrey).
{panel}

h2. ✅ / ❌ Acceptance Criteria

||AC||Requirement||Result||
|*AC-1*|Asset shows a dynamic line-style description "just like the Line Description" on order/quote|(/) *PASS*|
|*AC-2*|Field re-derives "any time the attributes change" — amendment, renewals, manual updates|(x) *FAIL*|
|*AC-2 ask*|"Confirm that this is no other trigger event to cause a change"|(!) *NOT DONE*|

----

h2. (/) What works — AC-1 (verified on real data)

{panel:bgColor=#E3FCEF}
The flow went live today 21:13; the 4 genuine conversions after that are a clean pass. The description flows *byte-identical* down the whole chain:

*Quote Line → Order Line → Asset* — all three equal:
{{beSECURE - Cloud-Based | Devices: 1001-2000 | One Time | Cloud Based}}

* (/) Flat/fee product *"BoKS Administration License Fee"* (no attributes) now carries its name instead of landing blank.
* (/) Correctly writes the *writable* {{Asset.Description}} field. (The "Product Description" field the ticket circles — {{Asset.ProductDescription}} — is *system-locked* / not writable, so it can never hold this value. Good call to redirect.)
{panel}

h2. (x) What's missing — AC-2 (the reason the ticket exists)

{panel:bgColor=#FFEBE6}
The stamping flow is *Create-triggered only* — it fires once when the Asset is born and *never again*.

* Amendments / renewals / upsells do *not* create a new Asset — they change the *existing* one. The flow cannot see those events.
* *Smoke test: 16 of 16* amended/renewed/upsold assets have a *BLANK* {{Description}} today.
* Extra gotcha for the fix: the change's source record is an *OrderItemDetail*, not an *OrderItem* — so the flow's current lookup couldn't resolve it even if we widened the trigger.
* The reporter's explicit ask — *confirm the full set of trigger events* — was never answered.
{panel}

----

h2. 📋 To close SC-3513

# Build the *update path* so amendment / renewal / upsell / manual-edit re-stamp the field (recommend an *AssetAction-anchored* re-stamp resolving the *OrderItemDetail* line — not an Asset-update flow).
# Deliver the *trigger-event matrix* answering "no other trigger events?" (amend / renew / upsell / downsell / swap / add-product / manual edit).
# Get *business sign-off* that the value under the *"Description"* field satisfies the "Product Description" request, and clean up the now-misleading static {{ProductDescription}} on the layout.
# Decide *install-base backfill* (430k+ legacy assets are blank today).
# *Commit* the flow + updated prehook to source control (they live only in the org right now; the repo copy is the pre-fix baseline).

{tip}Full report, evidence, and reproduction SOQL: {{Jira/PeerReview/sc3513 | Peer Review - SC-3513 …/}} — see {{SMOKE_TEST_SC3513.md}} and {{PEER_REVIEW_REPORT.md}}.{tip}

_Note: because the flow is only hours old, no create-stamped asset has been amended yet, so a live "populated → went stale" example isn't observable from existing data. The AC-2 finding rests on the Create-only trigger design + the OrderItemDetail source mismatch. A write-authorized amendment-then-observe test can confirm on request._
