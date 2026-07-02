# SC-3350 — Net-Price Fix Spec (procedure V11)

Vetted by a 4-agent design + adversarial-verification pass, all against the **active V10 block** of
`Rev_Mgmt_Default_Pricing_Procedure` (lines 46677-52498). Verdict: **GO-WITH-CONDITIONS.** Raw analysis:
[evidence/research-notes/fix_ui_mapping.md](evidence/research-notes/fix_ui_mapping.md),
[fix_blast_radius.md](evidence/research-notes/fix_blast_radius.md),
[fix_seed_source.md](evidence/research-notes/fix_seed_source.md),
[fix_adversarial_verify.md](evidence/research-notes/fix_adversarial_verify.md).

## The bug (recap)
Non-derived renewal lines never get `NetUnitPrice` seeded → it stays 0 → quote Grand Total $0. The list side
(InputUnitPrice/Subtotal) is correct. See [NET_PRICE_ZERO_RCA.md](evidence/NET_PRICE_ZERO_RCA.md) + the live
waterfall (Net track anchored on PBE $46, COLA price absent, Net=0).

## The fix
Add **one** pricing element to the renewal branch that seeds `NetUnitPrice` from the (COLA'd) `InputUnitPrice`.

| Property | Value |
|---|---|
| Element type | **Assignment** (metadata `actionType=AssignmentElement`) — mirror of `COLAUpliftonRenewal21` |
| Source | `InputUnitPrice` (Currency) — the post-COLA value 4697.946 / 929.25 |
| Target | `NetUnitPrice` (Currency) |
| Container | **`ListContainer62`** — the renewal container (top-level **seq 23**, filter `ListOperation63` = `ItemPricingSource Equals 'LastTransaction'`) |
| Sequence | **First** in the container — *before* its existing `FormulaBasedPricing` (`NetUnitPrice * LineItemQuantity`) child, and before the SubscriptionPricing group (seq 24) |
| **Gate (REFINED after runtime confirmation — see [evidence/RUNTIME_CONFIRM.md](evidence/RUNTIME_CONFIRM.md))** | `ItemPricingSource Equals 'LastTransaction'` **AND** `DerivedPricingAttribute = false` **AND** `(NetUnitPrice IsNull OR NetUnitPrice <= 0)` |
| Why the guard (not the original blanket gate) | Live data shows some Fortra-Originated renewals carry a **discounted** net (Net ≠ UnitPrice) that a blanket `Net := InputUnitPrice` would erase. The **"only when Net unset" guard** fires solely on genuine zeros — preserving every already-computed/partner/discretionary/stale net. More robust than the Deal_Type clause and covers the partner case too. |
| Optional belt-and-suspenders | `Deal_Type__c Equals 'Fortra Originated'` — guards the rare 100%-discount-to-$0 edge only. |

### Two corrections the adversarial pass made vs the first RCA (important)
1. **Container is `ListContainer62`, NOT `ListContainer55`.** The first RCA used **V1-block** element names
   (`ListContainer55/QuantityPrice49/COLAUpliftonRenewal10`) — those are stale/inactive. In the active V10,
   `ListContainer55` is the *non*-renewal branch (`NotEquals 'LastTransaction'`). Putting the seed there is
   inert or corrupts the group. **Anchor on element names scoped to the active block, never line numbers.**
2. **`Deal_Type__c = 'Fortra Originated'` is non-negotiable.** Without it, the seed **regresses partner
   renewals**: `PartnerDiscount24` (`ListContainer3`, seq 10, gated only `Deal_Type__c NotEquals 'Fortra
   Originated'`) already writes a *discounted* `NetUnitPrice` for partner deals at seq 10; our seed at seq 23
   would overwrite it back to undiscounted list. The `Deal_Type='Fortra Originated'` clause excludes partner
   deals so `PartnerDiscount24` stays authoritative.

## Why it's safe (verified)
- `DerivedPricingAttribute=false` protects **Path B** (derived/MDT maintenance renewals) — they own NetUnitPrice
  via `DerivedPricingRenewals` and are also LastTransaction, so they'd be clobbered without this clause.
- All other NetUnitPrice writers (AttributeBasedPrice, AttributeDiscount, BundleAdjustment, VolumeDiscount,
  ManualQuoteLevel) are gated `NotEquals 'LastTransaction'` → don't fire for renewals → no other regression.
  (The renewal discount-bypass is **intentional** by design; the seed only fills the missing copy.)
- `SubscriptionPricing` (seq 24) consumes the per-unit NetUnitPrice and multiplies by term — seeding the
  per-unit `InputUnitPrice` is the correct unit; runs right after the seed.

## Confirm these 3 runtime facts BEFORE activating V11 (waterfall / debug log)
1. **No-COLA renewal source (principal unknown):** `COLAUpliftonRenewal21` only writes `InputUnitPrice` when
   `COLA_Uplift_Percent__c` is not null. For a Fortra-Originated non-derived renewal with **no** COLA, confirm
   some upstream step still leaves the correct *prior* unit price in `InputUnitPrice` at seq 23 — else the seed
   pushes a wrong net. (If unconfirmed, also gate the seed on `COLA_Uplift_Percent__c IsNotNull`, or use the
   `NetUnitPrice IsNull` guard.)
2. **Partner renewal current state:** is a partner renewal correctly discounted today (then exclude via
   Deal_Type) or already $0 (different root cause)?
3. **Regional (Italy) renewal:** `RegionalNetReconcile` (seq 33, no pricing-source gate) re-derives net after
   the seed — validate an Italy renewal end-to-end.

## Build · validate · rollback
- **Build:** in the Pricing Procedure **Designer**, *Clone/Save As New Version* of active V10 → **Draft V11**
  (drafts don't affect production until activated). Add the Assignment element above. Verify the new step name
  appears **only** in V10's `ListContainer62` (not V1-V9, not `ListContainer55`).
- **Validate (before activation):** Simulate/Reprice the broken renewal **quote `0Q0WC000003671t0AA`** and
  confirm the Net track now anchors on **~4697.946 / 929.25** instead of 0, and Grand Total ≠ $0. Spot-check a
  partner renewal and a derived/MDT renewal show **no change**.
- **Activate** only after: the 3 runtime confirmations, **coordination with Marc DeBrey** (his procedure; prior
  in-place edits without re-syncing context `SalesTransactionContextExt_v2` caused gacks), and a **fresh explicit
  deploy ack**. Activating V11 auto-deactivates V10.
- **Rollback:** record V10's version Id first; rollback = re-activate V10 (retained Inactive). Never hot-edit an
  active version — fix forward in a Draft V12.

## Scope note
This is a **general renewal-net-pricing fix** (helps any Fortra-Originated non-derived renewal), surfaced by
COLA. It is arguably its own ticket in the $0-net family (SC-3345/SC-3347) but is required for COLA renewals to
total correctly.
