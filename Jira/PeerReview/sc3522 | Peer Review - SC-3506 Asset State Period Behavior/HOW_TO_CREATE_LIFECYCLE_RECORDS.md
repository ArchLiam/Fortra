# How to Create Asset Actions & Asset State Periods (Amend / Renew / Cancel)

**Org:** FortraUAT · base URL `https://fortra--uat.sandbox.lightning.force.com` · **Account:** Fortra, LLC - Test (safe test data).

## Concept (read first)
- You **cannot** hand-create `AssetAction` / `AssetStatePeriod` — they are system-generated and read-only.
- They are written at **one moment: when you ACTIVATE an Order that changes an existing asset.**
- A **brand-new** order only ever produces `Generate / Initial Sale`. To get **Change/Upsells (amendment)**, **Change/Renewals**, or **Cancel/Cancellations**, the transaction must be launched **from an existing asset** (Amend / Renew / Cancel).
- Flow every time: **Existing Asset → Amend/Renew/Cancel → Change Quote → Convert to Order → ACTIVATE → (async) new AssetAction + AssetStatePeriod appear on the Asset.**

## Records to use (each scenario on its own clean contract so they don't interfere)

| Scenario | Contract | Asset to act on | Current state |
|---|---|---|---|
| **Amend** | [00069407](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000Sy7g2YAB/view) | [Cobalt Strike](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008deKLYAY/view) `02iWC000008deKLYAY` | qty 1, mrr 491.67, 2026-06-29→2027-06-28 |
| **Renew** | [00069404](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000SyAafYAF/view) | [Cobalt Strike](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008dd1hYAA/view) `02iWC000008dd1hYAA` + [beSECURE](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008dd1iYAA/view) `02iWC000008dd1iYAA` | qty 1 each, 2026-06-29→2027-06-28 |
| **Cancel** | [00069417](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000T14CBYAZ/view) | [beSECURE](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008eU4RYAU/view) `02iWC000008eU4RYAU` | qty 1, mrr 17.17 |

---

## Scenario A — AMENDMENT (upsell qty 1 → 2)
1. Open Contract [00069407](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000Sy7g2YAB/view).
2. In the **Managed Assets** related component (or the **Amend** button in the highlights panel / ▾ dropdown), select the **Cobalt Strike** line → **Amend**.
3. On the resulting **Amendment Quote**: change Cobalt Strike **Quantity 1 → 2**. Set the amendment **effective/start date to something *after* 2026-06-29** (e.g. **2026-09-01**) so the period splits.
4. Click **Update Prices / Reprice**.
5. **Convert Quote to Order** (button on the Quote).
6. Open the new Order → **Activate**.
7. Open the [Cobalt Strike asset](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008deKLYAY/view) → **Related** → refresh.

**✅ Expected:** Asset Actions = 2 (`Initial Sale` + `Upsells` Δqty +1). Asset State Periods = 2 — first `…→2026-08-31` qty 1, second `2026-09-01→2027-06-28` qty 2; contiguous, no overlap.

---

## Scenario B — RENEWAL
1. Open Contract [00069404](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000SyAafYAF/view).
2. **Renew** (Managed Assets → select assets → Renew, or the `Fortra_Create_Renewal_Quote` flow) → creates a **Renewal Quote** for the next term.
3. Confirm the renewal lines (term = 12 months, next year). **Update Prices**.
4. **Convert to Order** → **Activate**.
5. Open the [Cobalt Strike asset](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008dd1hYAA/view) → **Related** → refresh.

**✅ Expected:** new Asset Action `Change / Renewals`; a **new forward-dated** state period `2027-06-29 → 2028-06-28`, with the prior period unchanged.
**🚩 Defect watch:** renewal period **MRR must be non-zero** (0 = COLA bug SC-3350/3346); **End Date must be ~1 year, not 2039** (12-year = PricingTermCount bug).

---

## Scenario C — CANCELLATION
1. Open Contract [00069417](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Contract/800WC00000T14CBYAZ/view).
2. **Cancel** the **beSECURE** line (Managed Assets → select → Cancel) → creates a **Cancellation Quote** with negative quantity (−1).
3. **Convert to Order** → **Activate**.
4. Open the [beSECURE asset](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Asset/02iWC000008eU4RYAU/view) → **Related** → refresh.

**✅ Expected:** new Asset Action `Cancel / Cancellations` (Δqty −1); **NO new Asset State Period**; Asset `Current Quantity` → 0, `Current MRR` → 0. Status stays *Installed* (expected).

---

## The universal "did it work?" check
On the **Asset → Related tab**: look at **Asset Actions** (one new row per change) and **Asset State Periods** (sort by **Start Date**). Match against the Expected above.

## Gotchas
- **Assetization is async** — after Activate, wait ~10–30 s and refresh. Records appear on their own.
- **Nothing appears after refresh** = the SC-3419 bug (activated with zero assets). Check the Order's `Order_Integration_Error_Messages__c` field; flag it.
- **Effective date == asset start date** → single period, no split. That's *expected*, not a bug.
- These are real UAT writes — only use the Fortra, LLC - Test records above.
