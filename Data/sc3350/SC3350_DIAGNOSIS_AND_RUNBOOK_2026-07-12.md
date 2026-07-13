# SC-3350 — Renewal COLA net: corrected diagnosis + canvas runbook (2026-07-12)

**Supersedes** `SC3350_HANDOFF_NET_COMMIT_WALL.md` and `SC3350_V25_PRICE_REVISION_GUIDE.md` on the root cause.
Org: FortraUAT · Active proc `Rev_Mgmt_Default_Pricing_Procedure` **V25** (`9QBWC0000000pk54AA`, sole Active) · Test quote `0Q0WC000003Ibx3` (lines `npyw`→98700, `npyx`→63720).

---

## 0. Product ruling (answered from the SDDs) — **NetUnitPrice is the field of record; this is a real revenue defect**

The SDDs disagree by *era*, and the live engine settles it:

- **`UnitPrice` (COLA-SDD §4.1, Contract-Renewals §7.2, Order-to-Asset-Lifecycle)** — pre-RCA *trigger-era* carrier. Under RCA, `UnitPrice`/Sales Price is display-only, stamped fill-only by SC-3544. It does **not** drive the customer total.
- **`COLACalculatedPrice__c` (COLA-SDD §3.5 "for pricing waterfall")** — the **transport value**, not the field of record. Computes correctly (98700 = 94000×1.05) and persists in context.
- **`NetUnitPrice`** — what the live procedure sums into the customer total. **Dossier Step 38** `TotalAmount = SUM(ItemNetTotalPrice)` over non-derived lines; **Step 26 (LastTransaction bucket)** `ItemNetTotalPrice = NetUnitPrice × Qty`. So a renewal line bills the uplift **iff `NetUnitPrice` carries it.**
- **Precedent that matches RCA:** Maintenance-Derived-Pricing SDD — a **native procedure Formula produces `NetUnitPrice`; Apex stamps inputs only.** Mirror this. (Partner/Regional SDDs describe Apex-hook net writes — the exact mechanism the trace proves fails on LastTransaction lines; do **not** mirror them.)

**Impact:** Ibx3 GrandTotal should be **162420** vs base **154000**; ~**83** Fortra-Originated renewal lines under-charged today. Real defect. *(ARR caveat: ARR derives from `TotalLineAmount`, but the LastTransaction bucket writes `ItemNetTotalPrice`. Fixing net moves GrandTotal + category rollups for certain; whether `Total_ARR__c` moves needs trace confirmation.)*

---

## 1. Corrected root cause (from live trace `07LWC00000QF2If2AL`, 2026-07-12)

The handoff said "Apex can't commit net; engine discards it." True but incomplete. The real V25 picture:

1. **`NetUnitPrice` is an engine OUTPUT** (SDD §6): context writes persist **only if a procedure step produces the value**. Trace proof: during prehook `NetUnitPrice={npyv=10000, npyw=98700, npyx=63720}`; after procedure+posthook `NetUnitPrice={npyv=10000}` — the two COLA lines are **dropped**. So no Apex hook (pre or post) can commit their net. ✔ confirmed.
2. **There is NO procedure step that produces the COLA net for non-derived (license/subscription) renewals.** The V25 COLA elements live in `ListContainer2`:
   - `COLAUpliftonRenewal` (Assignment, `COLACalculatedPrice__c → InputUnitPrice`) is **gated `DerivedPricingAttribute IsNotNull`** → fires only for **derived maintenance** lines. Ibx3 lines have `DerivedPricingAttribute = null` (confirmed in trace) → **excluded**. That is why `InputUnitPrice` is never populated for them.
   - `COLAUpliftNetonRenewal` (Assignment, `COLACalculatedPrice__c → NetUnitPrice`) has **no gate** but **`resultIncluded=false`** → never commits.
3. **The leftover `COLARenewalNetInputCommit` element the handoff §37 said to delete is ALREADY GONE** from live V25 (retrieved 2026-07-12; 0 matches). So current net=null is structural V25 behavior, and the handoff's "cleanup" step is moot.
4. **Assignments cannot commit net in this Designer (structural).** All **12** `AssignmentElement`s in V25 have `resultIncluded=false`; not one `ri=true` Assignment exists in 106 steps. `ri=true` appears only on `FormulaBasedPricing` and native pricing element types. So the handoff's attempt C (flip the COLA Assignment `ri=true` → null) was a **real structural limit**, not just the leftover-element confound. **Conclusion: an Assignment reads the custom field but can never be the committer; a Formula commits but can't read the custom field → the fix MUST be a two-hop.**

**Reframe:** the procedure has a COLA-net path for **derived maintenance** (SC-3346's domain); it was **never built for non-derived license/subscription renewals.** We are *adding the missing path*, not fighting a discard wall. This is **additive** and does not touch SC-3346's maintenance path (gate them apart on `DerivedPricingAttribute` / product type).

### Proven-working net-committer patterns in V25 (Duplicate-trick sources)
| Element | actionType | Container (seq) | Formula | ri |
|---|---|---|---|---|
| `OneTime Net Seed` | FormulaBasedPricing | `SeedOneTimeNetBeforePartner` (16) | `IF(NetUnitPrice > 0, NetUnitPrice, InputUnitPrice) → NetUnitPrice` | **true** |
| `Reset Net to Pre-Partner Base` | FormulaBasedPricing | `StampContributorBasePreDiscount` (12) | `IF(PartnerDiscountPercent>0, …, NetUnitPrice) → NetUnitPrice` | **true** |
| `COLAUpliftonRenewal` | AssignmentElement | `ListContainer2` | `COLACalculatedPrice__c → InputUnitPrice` (gated derived-only) | false |

The Designer does **not** expose the `resultIncluded` toggle — you get `ri=true` only by **duplicating** an element that already has it (`OneTime Net Seed`) and editing the copy's formula/gate. Duplicate `COLAUpliftonRenewal` for the Assignment hop.

---

## 2. Canvas runbook — incremental (you drive Designer; I reprice+verify each step)

> In-place edits only: **Deactivate V25 → edit → Reactivate → re-sync `SalesTransactionContextExt_v2`.** Do NOT Save-As / new version. Screenshot the flow before editing (rollback). Metadata deploy is off-limits (touches all 22 versions).

### Gate (both experiments) — non-derived renewal COLA lines only
```
1. ItemPricingSource       Equals      'LastTransaction'
2. SalesTransactionActionType Equals   'Renew'
3. COLACalculatedPrice__c  GreaterThan 0            ← the discriminator; null on non-COLA lines
4. Fortra_Product_Type__c  NotEquals   'Renewal Maintenance'   ← keep off SC-3346's path
   (belt-and-suspenders: DerivedPricingAttribute IsFalse/IsNull)
```

### The fix — two-hop native pair (Assignment feeds a Formula that commits)
Both hops gated as above. Element 1 must execute **before** Element 2, and Element 2 must sit where net **persists** (a proven container or a new top-level one after `Pricing Setting`).

**Hop 1 — Assignment (populate the bridge input):** Duplicate `COLAUpliftonRenewal` (`ListContainer2`). On the copy: keep mapping `COLACalculatedPrice__c → InputUnitPrice`; **replace its gate** with the non-derived gate above (remove `DerivedPricingAttribute IsNotNull`). This makes `InputUnitPrice = 98700/63720` for license renewals (today it's null because the original fires only for derived-maintenance).

**Hop 2 — Formula (produce + commit net):** Duplicate `OneTime Net Seed` (`SeedOneTimeNetBeforePartner`) — this inherits `resultIncluded=true`. On the copy: set formula `IF( InputUnitPrice > NetUnitPrice, InputUnitPrice, NetUnitPrice )`, output `NetUnitPrice`, add the gate above. Place it so it runs **after** Hop 1.

> Placement notes: If Hop-1's `InputUnitPrice` write from `ListContainer2` doesn't survive to Hop 2 (ListGroup var scoping is the open risk — the trace will show it), put **both** hops in one **new top-level container immediately after `Pricing Setting`** (top-level net-producers commit). First reprice tells us which placement holds — I'll read `InputUnitPrice` and `NetUnitPrice` per line from the trace.

Then **reprice Ibx3** → I verify trace + persisted net:
- **Success:** `NetUnitPrice = 98700/63720`, GrandTotal = 162420, idempotent.
- **`InputUnitPrice` populated but net still base/null:** Hop 2 isn't in a persisting position → move both hops to the new top-level container.
- **`InputUnitPrice` still null:** Hop 1's gate/placement didn't fire → adjust gate/order.

### Retire (only after the fix commits + verifies)
- Delete/disable inert `COLAUpliftNetonRenewal` (`ListContainer2`, `→NetUnitPrice`, ri=false — proven dead).
- `COLAUpliftPrehook`: remove the discarded `pendingNetUnitPriceUpdates` net seed (keep audit-field writes).
- `PartnerNetPricePosthook.buildRenewalColaCommitUpdate`: redundant for license lines once the procedure commits — retire after confirmation.

---

## 2b. Canvas walkthrough (click-by-click) — recommended placement: a NEW top-level container

Rationale for a **new top-level container** (vs reusing `SeedOneTimeNetBeforePartner`): its scope is controlled entirely by our gate, so we don't depend on whether the license line enters an existing OneTime/derived container. Top-level net-producers commit (`Pricing Setting` proves it). Downstream net elements pass our value through for renewals (`OneTime Net Seed` keeps `NetUnitPrice>0`; `Reset Net` keeps non-partner; `DerivedPricing…Reset` passes Renewal through), so an early placement (right after `Pricing Setting`) is safe.

**Step 0 — open + deactivate.** Setup → **Pricing Procedures** (or ExpressionSet/Pricing Procedure Designer) → `Rev_Mgmt_Default_Pricing_Procedure` → open **Version 25**. Screenshot the canvas (rollback record). Click **Deactivate** (active = read-only). *Tell me what the top toolbar shows — I want to confirm it's V25 and now editable.*

**Step 1 — add a new top-level container** (a "Group"/"List Group"/"Loop" element, whatever your palette calls a container that iterates lines). Drag it onto the top-level flow so it sits **immediately after `Pricing Setting`**. Name it e.g. `COLA Renewal Net (License)`. Leave its own condition empty (the child elements carry the gate).

**Step 2 — Hop 1 (Assignment: populate InputUnitPrice).** Easiest is to **Duplicate `COLA Uplift on Renewal` (`COLAUpliftonRenewal`)** from `ListContainer2` (its ⋯ / more menu → Duplicate/Clone), then **move the copy** into the new container. On the copy:
- Confirm the Assignment maps **input `COLACalculatedPrice__c` → output `InputUnitPrice`** (that's what the original does). *If your duplicate shows the mapping differently, tell me.*
- Replace its **Condition** with these 4 criteria (logic `1 AND 2 AND 3 AND 4`):
  1. `ItemPricingSource` **Equals** `LastTransaction` (Literal)
  2. `SalesTransactionActionType` **Equals** `Renew` (Literal)
  3. `COLACalculatedPrice__c` **Greater Than** `0` (Literal)
  4. `Fortra_Product_Type__c` **Not Equals** `Renewal Maintenance` (Literal)
- If you can't move the duplicate into the container, instead **add a fresh `Assignment` element** inside the container and set the same input→output + condition.

**Step 3 — Hop 2 (Formula: commit NetUnitPrice).** **Duplicate `OneTime Net Seed`** (in `SeedOneTimeNetBeforePartner`) — duplicating is how the `resultIncluded=true` flag carries over (the UI won't let you toggle it). Move the copy into the new container, **after Hop 1**. On the copy:
- Set the **formula** to: `IF( InputUnitPrice > 0 , InputUnitPrice , NetUnitPrice )`
- Confirm **output = `NetUnitPrice`** and **Include in Result / result is ON** (should be inherited from the duplicate — *confirm you see it enabled; if there's no visible toggle, that's expected, it's carried in metadata*).
- Set the **same 4-criteria Condition** as Hop 1.

**Step 4 — order check.** Within the container: Hop 1 (Assignment) **before** Hop 2 (Formula). *Send me a screenshot of the container's contents and its position in the top-level flow before reactivating — I'll sanity-check order/placement.*

**Step 5 — reactivate + re-sync.** **Activate** V25 (from the Versions list). Then **re-sync the context definition** `SalesTransactionContextExt_v2` (the Designer's context re-sync action). Skipping re-sync causes the "Specify contextDefinitionName" gack.

**Step 6 — ping me.** I force-reprice Ibx3 and read the trace.

## 3. Acceptance (I run after each canvas step)
1. Reprice `0Q0WC000003Ibx3` (Place, `pricingPref:Force`).
2. Committed `NetUnitPrice = 98700 / 63720`; `NetTotalPrice`/`TotalPrice` follow; **GrandTotal = 162420**.
3. Idempotent (reprice twice → identical).
4. No collateral: No-Change line `npyv` net stays 10000; no non-COLA line nulled; no maintenance line touched.
5. Confirm on trace whether `TotalLineAmount`/`Total_ARR__c` also moved (ARR caveat).
6. D-18 clean (no new `Exception_Log__c`).

## 4. Rollback
Deactivate V25 → revert the element(s) (ri back to false / delete new elements) → Reactivate → re-sync context. V24 remains available as ultimate fallback.
