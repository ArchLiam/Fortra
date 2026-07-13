🔁 Re-review after rework — ⬆️ Much improved, but not ready to close (read-only, FortraUAT, 2026-07-07)

Marc replaced the create-only flow with a new AssetAction-triggered flow (Fortra_AssetAction_Stamp_Line_Description) and deleted the old one. This fixes both HIGH findings:
• ✅ Update path — now fires on AssetAction create for Upsells and Renewals, so amendments/renewals re-stamp the field (not just at asset birth).
• ✅ OrderItemDetail source — now resolves the change's source by hopping OrderItemDetail → parent OrderItem for the description (verified: OrderItemDetail has no Description of its own). Also won't blank an existing value.

Still open before this can pass:
1. ❗ Not verified live — no AssetAction has been created since the flow deployed at 12:09, and the old flow that stamped yesterday's conversions is now deleted. So neither the create path (AC-1) nor the update path (AC-2) has actually run against real data. The 16 previously-changed assets predate the flow and are still blank. Please run one live conversion + one live amendment/renewal to confirm.
2. ⚠️ Category coverage is incomplete — the trigger only covers Initial Sale / Upsells / Renewals. Upgrades, Downgrades, Swaps, Downsells and T&C Changes are excluded, yet they also change what was purchased. (Today's UAT data only has Upsells/Renewals, so it works now, but this is a gap for Production.)
3. ⚠️ "Manual updates on the asset" still not handled (a manual edit doesn't create an AssetAction), and the "confirm no other trigger events" analysis is still owed.
4. Backfill decision — 16 changed + 430k legacy assets are still blank; the flow won't fill them retroactively.
5. Commit the new flow + prehook to source control (currently only in the org).

Net: the architecture is now correct — items 1–3 are what stand between this and a pass. Details: RE_REVIEW_SC3513.md in the peer-review folder.
