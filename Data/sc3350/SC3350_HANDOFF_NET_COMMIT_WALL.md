# SC-3350 — Committing the renewal COLA net: proven facts, dead-ends, and the remaining path

**Status: BLOCKED at the pricing-procedure layer after exhaustive attempts. Escalate to procedure owners (Marc/Nir/German).**
Org: FortraUAT · Active proc: `Rev_Mgmt_Default_Pricing_Procedure` V25 · Test quote: `0Q0WC000003Ibx3` (lines `0QLWC000003npyw4AA`=98700 expected, `npyx4AA`=63720 expected).

## The goal
For a renewal COLA line, the committed `NetUnitPrice` must equal `COLACalculatedPrice__c` (= priorNet × (1+category%) = 98700 / 63720). Today it stays at the asset base (94000 / 60000), so GrandTotal is billed at base. The COLA value is computed correctly and `COLACalculatedPrice__c` persists on the QLI and is present in the pricing context; only the *commit to net* is missing.

## PROVEN facts (all verified live)
1. **Apex can't commit net.** Prehook/posthook `updateContextAttributes({NetUnitPrice})` returns `isSuccess:true` but the engine discards it (trace: 98700 mid-hook → reverts to 94000 between executor phases). `QuoteLineItem.NetUnitPrice/NetTotalPrice/TotalPrice/Subtotal` are `IsUpdatable=false` → no post-persist DML.
2. **The COLA value is in context.** The prehook computes `AssetPrice=94000, COLA%=5, AdjustedPrice=98700` and `COLACalculatedPrice__c` shows `98700.00` in context snapshots. SDD (`docs/RCA Solution Guide/kb/Fortra-Pricing-COLA-Solution-Design-Doc.md` line 105) defines it as *"COLA-adjusted price for pricing waterfall"* — so committing it to net is **design-aligned**.
3. **The sibling Assignment commits `InputUnitPrice`.** `COLAUpliftonRenewal` (Assignment, ListContainer2) maps `COLACalculatedPrice__c → InputUnitPrice` and it flushes (InputUnitPrice = 98700). So the Assignment element **resolves the custom field**.
4. **`resultIncluded=true` is the commit switch** and the Designer UI does NOT expose it for Assignment/Formula elements (only "Exclude Price Waterfall", a different flag). Duplicating an element with `resultIncluded=true` copies the flag; editing its formula preserves it.
5. **Price Revision element = blocked in this org.** Requires `PolicyType=PriceIndex` + `Formula='PriceIndex'` + an `IndexRate` decision-table row matched by Region/Currency/date. Org has **no Region picklist values** and no IndexRate rows; a Flat policy Formula throws `INVALID_PRICE_REVISION_FORMULA`.

## Attempts and results (all → committed `NetUnitPrice = null`)
| # | What | Result | Why |
|---|---|---|---|
| A | Prehook/posthook write NetUnitPrice | base 94000 | Fact 1 — engine discards |
| B | New **Formula** element (top-level & in SeedOneTimeNetBeforePartner) `IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, NetUnitPrice)`, `resultIncluded=true` | **null** | Custom field `COLACalculatedPrice__c` does **not resolve inside a Formula** element (value never enters the waterfall) |
| C | Flip existing inert `COLAUpliftNetonRenewal` **Assignment** (ListContainer2) `resultIncluded=false→true` (metadata deploy) | **null** | 98700 reaches context but does **not persist** — ListContainer2 net-write with `resultIncluded=true` yields null on commit |
| D | New **Formula** element in **ListContainer2** `IF(InputUnitPrice>0, InputUnitPrice, NetUnitPrice)`, `resultIncluded=true` | **null** | Same as C — 98700 in context, null persist. **ListContainer2 cannot commit a net-write regardless of element type.** |

## The precise wall
- **Formula elements** don't resolve the custom field `COLACalculatedPrice__c` (attempt B) — only standard/waterfall fields (`InputUnitPrice`, `NetUnitPrice`) resolve.
- **Assignment elements** resolve the custom field (fact 3) but, in **ListContainer2**, a `resultIncluded=true` net-output persists as **null** (attempts C/D). The value reaches the context (98700 confirmed in the trace) but not the committed/persisted net.
- **Persisting containers** exist — `OneTime Net Seed` / `Reset Net to Pre-Partner Base` (in `SeedOneTimeNetBeforePartner` / `StampContributorBasePreDiscount`) commit `NetUnitPrice` with `resultIncluded=true`. But they are **Formula** elements using standard fields; a Formula there can't read `COLACalculatedPrice__c`, and whether `InputUnitPrice` is already 98700 at those containers' execution point (i.e. after `COLAUpliftonRenewal` runs) is **unverified**.

## The one remaining viable path (untested — for the owner session)
Put a net-committer where net **persists** AND that can read a **resolvable** 98700:
- **Formula element in a persisting container** (mirror `OneTime Net Seed`'s placement) with `IF(InputUnitPrice > NetUnitPrice, InputUnitPrice, NetUnitPrice) → NetUnitPrice`, `resultIncluded=true`, gated `ItemPricingSource='LastTransaction' AND SalesTransactionActionType='Renew'`. **Prereq to verify first:** that the chosen container executes **after** `COLAUpliftonRenewal` (so `InputUnitPrice` = 98700 there). Confirm execution order from a debug trace before placing.
- Fallback: declare `COLACalculatedPrice__c` as an **Input/Formula Variable** on a Formula element so it resolves, then it can be used directly (attempt B's own escape hatch — untested).

## Also open (product ruling)
Whether renewal `NetUnitPrice` should carry COLA at all, or `UnitPrice` is the intended billed field. SDD line 105 ("for pricing waterfall") argues for committing net; GrandTotal being net-based (billed at base today) argues it's a real defect. Confirm with the product owner before further engine surgery.

## Current org state / cleanup
- V25 has: `COLAUpliftNetonRenewal` back to `resultIncluded=false` (inert), PLUS a leftover new element `COLA Renewal Net Input Commit` (`COLARenewalNetInputCommit`, Formula, ListContainer2, `resultIncluded=true`) that commits null. **Delete that element** (canvas `⋯ → Delete`, then Activate + re-sync) to restore the base state (net = 94000).
- Apex `COLAUpliftHandler` stamps `UnitPriceUplift` (now unused by this path — harmless) and the audit fields (`COLACalculatedPrice__c`, etc.) which remain correct. The prehook net-seed / posthook commit are inert (discarded) and can be retired.
- Data staged during the investigation (unused): `PriceRevisionPolicy` `1VCWC0000002fn34AA`, `QLI.UnitPriceUplift`/`PriceRevisionPolicyId` on Ibx3 lines, `Asset.PricingSource='LastTransaction'` on the 2 assets, an `IndexRate` row.
