# SC-3441 FIX ROADMAP — Order Cancellation Line Item Displays Total Price as USD 0.00 Instead of Negative Amount

**Ticket:** SC-3441 | **Reporter:** Joe Romo | **Org:** FortraUAT (native Revenue Cloud Advanced / RLM) | **Shared procedure:** `Rev_Mgmt_Default_Pricing_Procedure` (Quote + Order) | **Date:** 2026-06-24 | **Status:** OPEN (now also hard-errors on reprice)

---

## EXECUTIVE SUMMARY

A user-initiated cancellation line (e.g. OrderItem `802WC00000OugI7YAJ`, Order `00095539`, Arcus Hosting, Qty −1, ListPrice 3000) displays **TotalPrice $0.00** instead of the expected **−$3000 credit**. Root cause: the native RLM waterfall produces no priced row for the cancel line (`PriceWaterFall`/`PriceWaterfallIdentifier` null), so the **`NetUnitPrice` field stays null**; the active V16 line-total formula computes `NetUnitPrice * LineItemQuantity` = `null * −1 = 0` → TotalPrice 0. The correct credit value is the asset **NET** (`AssetActionSource.NetUnitPrice`), not catalog list (77% of asset-source rows have net≠list; 907 have ListPrice 0 with nonzero net). A recently-deployed context-fetch fix unblocked the reprice far enough to surface a **new hard failure**: V16 step `StampContributorBaseFilter` throws SF-BRE-00004 ("resources don't have corresponding values for evaluation") because its criterion 5 (`NetUnitPrice GreaterThan 0`) cannot evaluate a null. **The fix must result in a non-null `NetUnitPrice` on the cancel line BEFORE `StampContributorBaseFilter` (seq 14) and before the line-total step `QuantityPrice64` (seq 26).** The roadmap below first runs a decisive **native-path probe** (is `Asset.PricingSource = 'LastTransaction'`, and can the existing native carryover branch be made to fire?) because the platform already has the field, context hydration, and procedure branch wired; only if the native path is proven unfixable do we fall back to a custom prehook + `CancelNetUnitPrice__c` staging field seeded on the **NetUnitPrice field**, gated tightly to full-cancel lines, with both-objects + both-context-node + FLS discipline, an interim BRE null-guard stopgap, a full regression battery, Workday/DocGen downstream checks, single-active-version + live-re-pull discipline, a named rollback version, and explicit test-coverage / prod-promotion / durability gates.

---

## CRITICAL PATH (one line)

**Phase 0 (re-verify live single-active V16) → Phase 1 (FINEST log + native-LastTransaction probe = DECISION GATE on fix shape) → Phase 2 (build: native lever OR custom seed; fields/context/FLS/prehook/procedure delta) → Phase 3 (validate on a FRESH DRAFT cancel + regression battery + downstream) → Phase 4 (deploy UAT with fresh ack, named rollback) → Phase 5 (durability verifier + prod reconciliation + coverage gate).**

Decision gates are bolded inline. Do not proceed past a gate without its exit criteria met.

---

## CORRECTED ROOT-CAUSE ONE-LINER

> The cancel line reaches the V16 line-total step with a **null `NetUnitPrice` field** (the native waterfall returns no priced row because the line never takes the asset **LastTransaction** carryover branch — `Asset.PricingSource` is null/List on the source asset), so `TotalPrice = NetUnitPrice × LineItemQuantity = null × −1 = 0`; the fix is to ensure the line arrives at `QuantityPrice64` with a non-null `NetUnitPrice` equal to the **asset NET** (`AssetActionSource.NetUnitPrice`), seeded **before** `StampContributorBaseFilter` (seq 14, whose `NetUnitPrice > 0` criterion otherwise hard-errors SF-BRE-00004).

---

## KEY DECISIONS (adjudicated)

1. **Field, not formula.** TotalPrice is computed from the **`NetUnitPrice` FIELD** (`QuantityPrice64`: `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity` → `Assignment108` → `ItemTotalPrice` → `TotalPrice`). `InputUnitPrice` feeds only `ItemSubtotal`. **Therefore the drafted-Inactive V17 / any ListPrice→InputUnitPrice seed CANNOT fix TotalPrice. Do NOT activate V17 expecting a fix.** (Unanimous across all four critiques — KEEP.)

2. **Asset NET, not catalog list.** Correct credit = `AssetActionSource.NetUnitPrice` resolved via the action's `SourceAssetId`. Evidence: 77% (1539/1999) of `AssetActionSource` rows have net≠list; 907 have ListPrice 0 with nonzero net; 2 of the 6 broken lines have ListPrice 0. A list-based seed over/under-credits. `−3000` is correct for 00095539 **only because that sale was undiscounted**. (Unanimous — KEEP.)

3. **Native carryover vs custom prehook — ADJUDICATION.** Critique 1 (RLM best-practice lens) is correct that the *canonical* RLM mechanism for cancellation pricing is asset **LastTransaction** carryover (`Asset.PricingSource = 'LastTransaction'` → the existing `ItemPricingSource == 'LastTransaction'` branch, `ListOperation57` in V16), and the platform already has the field, context hydration, AND the procedure branch. Critiques 2/3/4 independently confirm the custom-seed mechanics are sound *if* a custom write is needed. **Resolution: the native path is the PREFERRED mechanism and MUST be probed first (Phase 1 gate). The custom `CancelNetUnitPrice__c` prehook+seed is demoted to a FALLBACK, used only if the native path is proven unfixable.** Rationale: the native lever is config/data (set/backfill `Asset.PricingSource`), has **zero shared-procedure blast radius**, is Gearset/refresh-durable on the data side, applies native proration automatically, and avoids adding a 7th custom staging field to a procedure co-owners rewrite every few days. If a custom path is still required, set **only** `PricingSource`/`ItemPricingSource` in context where possible (let the engine derive net) before resorting to computing and injecting `NetUnitPrice`.

4. **Both-objects + both-context-nodes + FLS is a hard constraint** for ANY custom staging field (proven by the live `Pre_Partner_Price__c` context-fetch incident: QLI-only field → Order pricing hard-failed "couldn't fetch SalesTransactionContextExt_v2"). The cancel **GATE** itself needs no new field (native `SalesTransactionAction.Type`/`StartQuantity`/`EndQuantity`/`SourceAsset` are already on both nodes); only the **VALUE** needs the prehook + staging field in the fallback path.

5. **Sequencing is decisive.** The new seed/assignment must land at a top-level `sequenceNumber ≤ 13` — a NEW top-level ListGroup **before** `ListContainer48`/`StampContributorBaseFilter` (seq 14). **Copying the COLA template placement (seq 24) would NOT prevent the BRE.** It must also run before the `ListContainer10` "NetUnitPrice Value Reset" (seq 22, derived-only) and before `QuantityPrice64` (seq 26).

---

## PHASE 0 — Preconditions & live re-verification (CRITICAL PATH)

**Objective:** Establish a deterministic, single executing procedure version and confirm the context-fetch incident is healed, *as the literal first actions* — the active version is changing minute-to-minute (V14 and V16 were both modified within 24 seconds today).

**Steps (where: FortraUAT, read-only / Tooling API):**
1. Re-pull the live `ExpressionSetVersion` list. Confirm exactly **one Active** version and capture its Id. Verified at 2026-06-24T20:38–20:39: **V16 `9QBWC0000000niH4AQ` = Active (sole)**; **V14 `9QBWC0000000nIT4AY` = Inactive** (flipped 20:38:49); **V17 `9QBWC0000000ntZ4AQ` = Inactive**. Treat this as *unconfirmed until re-queried* — do not trust this snapshot.
2. Record the **last-known-good Active version Id** (V16 today) as the named rollback target. Do NOT delete any inactive version (platform-blocked; keep V14/V17 intact and Inactive).
3. Confirm the partner-field context-fetch fix is live: `Pre_Partner_Price__c` / `Partner_Pricing_Source__c` exist on **OrderItem** and are mapped on **OrderEntitiesMapping/SalesTransactionItem**; reprice one normal positive-qty Order and one normal Quote and confirm context fetch succeeds.
4. Post an owner change-control note (Nir/Marc/Ben) announcing intent to edit this procedure; request a freeze window for the build+activate.

**Exit criteria:** Exactly one Active version (Id recorded as rollback target); context fetch succeeds on both a Quote and an Order reprice; owner freeze window agreed.

---

## PHASE 1 — Runtime diagnosis & FIX-SHAPE DECISION GATE (CRITICAL PATH)

**Objective:** Settle *why* the native LastTransaction path doesn't fire and decide native-lever vs custom-seed BEFORE any build. This is the single highest-leverage step and may change the whole fix shape.

**Steps (where: FortraUAT, authorized read + one authorized FINEST reprice):**
1. **Asset provenance probe.** `SELECT PricingSource, COUNT(Id) FROM Asset GROUP BY PricingSource`, and specifically on the assets behind all 6 broken cancel lines. Determine whether *any* asset in the org carries `PricingSource = 'LastTransaction'`. If ~none do, the defect is a systemic asset-provenance/activation gap.
2. **Context-hydration probe.** Verify `PricingSource` / `ItemPricingSource` is mapped/hydrated on **OrderEntitiesMapping/SalesTransactionItem** AND **QuoteEntitiesMapping/SalesTransactionItem** (it is mapped on Quote at contextdef ~5897–5899; confirm parity on Order). A missing Order-node mapping would suppress `PricingSource` hydration exactly like the partner-field incident. Also confirm whether `AssetActionSource`/`AssetActionSourceNetUnitPrice` is hydrated under Order/Quote mappings — verified it has **38 refs under AssetEntitiesMapping but ZERO under Order/Quote mappings**, so asset-net is currently unreachable declaratively in the reprice context (justifies a prehook OR a context-def hydration addition if the custom path is taken).
3. **Asset-lifecycle cancel-creation probe.** Inspect the UI `initiateCancellation` / Asset Amendment connect path: does it stamp `ItemPricingSource = 'LastTransaction'` on the new negative line? The migrated "working" lines bypass the procedure with a pre-stamped `UnitPrice`; determine whether real-user cancel lines are *supposed* to inherit `PricingSource = 'LastTransaction'` and aren't.
4. **FINEST pricing-procedure log (authorized reprice of a FRESH DRAFT cancel line — see Phase 2.0 on why not 00095539).** Capture: (a) materialized `ItemPricingSource` on the cancel line; (b) whether the native waterfall returns a `NetUnitPrice` row or null; (c) which line-total container fires — `ListContainer62`/`QuantityPrice64` (full-waterfall) vs `ListContainer70`/`ListOperation57` (LastTransaction branch); (d) the `NetUnitPrice` value at `QuantityPrice64`; (e) how the `OrderItemDetail` `14CWC000001KXDl2AO` carrying `NetUnitPrice=3000` fails to promote to the parent line (the detail-vs-line smoking gun — this may be a promote-back bug, not a never-computed bug, which would change the fix entirely).
5. **Native-lever trial (authorized, data-only).** On the subject source asset, set `Asset.PricingSource = 'LastTransaction'` and re-test a fresh draft cancel reprice. Zero shared-procedure blast radius; reversible.

**DECISION GATE 1 — fix shape:**
- **If** setting `Asset.PricingSource = 'LastTransaction'` (and/or fixing the cancel-line `ItemPricingSource` hydration) makes the native carryover branch price the cancel line at asset net → **adopt the native lever** (Phase 2-Native). Root fix becomes asset-provenance backfill + ensuring order activation stamps `LastTransaction`. Far cheaper, more durable, no procedure surface.
- **Else** (native path genuinely cannot be made to fire) → **adopt the custom seed** (Phase 2-Custom), preferring to set only `PricingSource`/`ItemPricingSource` in context before computing/injecting `NetUnitPrice`.

**Exit criteria:** FINEST log read and the detail-vs-line tension resolved; `Asset.PricingSource` distribution known; native-lever trial result recorded; written, owner-signed decision: `fix shape = {native lever | custom seed}` with justification.

---

## PHASE 2 — Build

### 2.0 Verification vehicle (applies to BOTH branches) — CRITICAL
- **The known repros are NOT repriceable.** Verified live: Order `00095539` = "Order Complete" (Activated 2026-06-16); the other cancel order `801WC00000kZUARYA4` = "Superseded"; the quote-side repro `0Q0WC000003A8PB0A0`/00781173 = "Accepted". RLM reprice runs on **DRAFT** transactions only. **Build a FRESH draft cancellation** (cancel a current asset → Draft Quote and Draft Order) as the live verification vehicle. Draft transactions exist in-org (Draft order 00000102; Draft quotes 00000005/7/9).
- `00095539` is a **documented-but-historically-frozen** record: it will stay $0 unless someone reprices it (likely impossible while Complete). If the business wants the historical line corrected, that is a **separate data-backfill** of its `NetUnitPrice`/`TotalPrice` (OrderItem.NetUnitPrice is updateable; QLI.NetUnitPrice is read-only) — track as a sub-task, not part of the procedure fix.

### 2-Native (if Decision Gate 1 = native lever)
1. Define the remediation surface: backfill `Asset.PricingSource = 'LastTransaction'` on affected assets, and/or fix order-activation to stamp `LastTransaction` so future cancellations inherit it. Confirm currency-awareness: `AssetActionSource.NetUnitPrice` carries a currency; the native path derives in the asset's currency — assert no USD-only lookup mis-credits non-USD cancellations (org has a documented currency-blindness pattern, SC-3384 family).
2. If a context-hydration gap (not a data gap) is the cause, add `PricingSource`/`ItemPricingSource` hydration to the deficient node (Order or Quote) and **Save & Publish** the context def, then republish.
3. **No procedure version edit** if the native branch fires — that is the whole point of this branch.

### 2-Custom (if Decision Gate 1 = custom seed)
1. **Fields (MDAPI staging; the `rca_diagnostic.cls-meta.xml` orphan blocks source-format `sf` ops):** create `CancelNetUnitPrice__c` (Currency 18,2) on **BOTH** `QuoteLineItem` AND `OrderItem`. No persisted flag field — gate on values + native action attributes.
2. **FLS mirror:** copy `CancelNetUnitPrice__c` FieldPermissions (via Apex) to the **same perm-set set that already carries the partner fields** on OrderItem — use the live `Pre_Partner_Price__c` FieldPermissions as the authoritative copy list (Quotes-Edit/Read/Tab, Revenue Cloud Admin/Base, Sales ELT/Executive Ops/Leadership/Operations/User, Security, Services Coordinator/Leadership, Solution Engineers, Strategic Account Manager, Strategy (Pricing), System Admin Full, Technical Support — Elevated/Leadership, …). Grant on **BOTH** QuoteLineItem and OrderItem. Confirm the running pricing-engine / integration user can READ the field on both objects (a missing Order-side integration-user FLS silently nulls the staging field). The draft's "~14 perm sets" undercounts — use the partner-field set as authoritative.
3. **Context def:** add `CancelNetUnitPrice__c` hydration on **BOTH** `QuoteEntitiesMapping` AND `OrderEntitiesMapping` (node `SalesTransactionItem`). **Save & Publish + republish.** Then **gated checkpoint:** reprice one normal positive-qty Quote AND one normal Order and confirm context fetch still succeeds (this is the exact precondition whose absence caused the partner-field hard-fail; do not skip).
4. **Prehook Apex (`CancelLineNetSeedPrehook`, RevSignaling.SignalingApexProcessor) + test class.** Dual-path asset-net resolver:
   - **Order line:** `OrderAction.SourceAssetId` → `AssetAction` → `AssetActionSource.NetUnitPrice`.
   - **Quote line:** `QuoteAction.SourceAssetId` (QLI has NO OrderAction; cancel QLI `0QLWC000003fKAj4AM` carries `QuoteActionId=7ocWC00000upzpBYAQ`) → `AssetAction` → `AssetActionSource.NetUnitPrice`.
   - Secondary lookup: `Replaced_Asset__c` (currently null here). Final fallback: `ListPrice` **only when** asset-net unavailable AND `ListPrice > 0` — document this fallback as **lossy** (under-credits the 907 ListPrice-0/nonzero-net cases; the 2 ListPrice-0 broken lines REQUIRE the asset-net path).
   - **Currency-aware:** resolve net in the line's transaction currency; do not blindly seed a USD asset-net onto a non-USD line.
   - Null-safe at every hop. Write `CancelNetUnitPrice__c` into context via `updateContextAttributes`. Stamp `InputUnitPrice` **only behind the same cancel predicate** (so `ItemSubtotal`/partner-discount base stays consistent without leaking into normal lines).
   - **Test-first:** the test class (asset-net via OrderAction AND QuoteAction, negative-qty detection, null-safety, ListPrice>0 fallback, ListPrice-0 asset-net case, currency case) is a **Phase 2 deliverable**, not a Phase 5 afterthought — it gates deployability (prod ≥75%).
5. **Procedure delta (clone the LIVE active version first — re-pull immediately, it drifts):** add ONE gated `AssignmentElement` as a **NEW top-level ListGroup before `ListContainer48`/`StampContributorBaseFilter` (insert at top-level `sequenceNumber ≤ 13`, alongside/just after `ListContainer47`).** It copies `CancelNetUnitPrice__c` → `NetUnitPrice` (and → `InputUnitPrice`). **Gate (context fields only — the procedure has no OrderAction/QuoteAction pointer at runtime; `Asset__c`/`OriginalOrderItemId` are null on the cancel line):**
   - **Cancel predicate (primary):** `ItemSalesTransactionAction = 'Cancel'` **OR** (`SalesTransactionSourceAsset IsNotNull` AND `StartQuantity > EndQuantity`). Use the correct in-context attribute name **`PriceWaterFall`** (NOT `PriceWaterfallIdentifier`) if referenced, or the gate silently never matches.
   - **Full-cancel restriction:** `EndQuantity = 0` (or `StartQuantity = −LineItemQuantity`). **Explicitly EXCLUDE downgrade/partial-reduction amends** (e.g. StartQty 5→EndQty 3, line qty −2) — seeding the full asset net on those would over-credit; ticket partial-cancellation proration SEPARATELY. (Today's org data is all qty=−1 full cancels among the 6 user lines; the qty=−2/−10/−15 lines are pre-stamped migrations — so this is latent, not yet observed, but must be gated out.)
   - **Idempotency guard:** `NetUnitPrice IsNull` AND `CancelNetUnitPrice__c > 0` — so the seed never clobbers a real waterfall net and only fires when seeded. (Do NOT rely on `NetUnitPrice IsNull AND PriceWaterFall IsNull` *alone* as the gate: at seq 13 a brand-new positive line is also transiently null-net/null-waterfall; the safety rests on the explicit cancel predicate, with the null check as an idempotency guard only.)
6. **Two latent V16 landmines — fold into THIS build, not a later ticket:**
   - **`ListContainer10` "NetUnitPrice Value Reset" (seq 22, gated `ItemIsDerived__std = true`, writes 0 when not Renewal).** The subject line is `IsDerived=false` so it is unaffected, but a **derived/maintenance cancellation** would have its seeded `NetUnitPrice` re-zeroed at seq 22. Mitigation: either re-apply the seed after seq 22 for derived cancels, or re-gate the reset to exclude qty<0 / cancel. Test a derived cancel explicitly (Phase 3).
   - **MAX clamp `FormulaBasedPricing3` (seq 37, UNCONDITIONAL): `TotalLineAmount = IF(ItemNetTotalPrice > TotalLineAmount, ItemNetTotalPrice, TotalLineAmount)`.** Once the seed makes `NetUnitPrice` non-null, this clamp ZEROES any negative `TotalLineAmount` → corrupts `ItemSubtotal`/`Subtotal` on the cancel line (it does NOT cause the ticketed TotalPrice=0 since it writes only `TotalLineAmount`, so it's not the headline — but it WILL produce a correct TotalPrice with a wrong Subtotal). Add a clamp guard `LineItemQuantity >= 0` in this build.
7. **Document the new container's top-level `sequenceNumber`** in the deploy artifact and re-verify after activation (UI edits can renumber sequences).

**Exit criteria (either branch):** chosen mechanism built; fresh draft cancel vehicle exists; (custom) field on both objects + FLS mirrored on both + context mapped on both nodes + context fetch re-confirmed on a Quote AND an Order + prehook test class ≥75% on the new class + seq ≤13 placement documented + both landmines (seq-22 reset, seq-37 clamp) guarded; (native) provenance/hydration remediation built.

---

## PHASE 3 — Validate (UAT, on the FRESH DRAFT vehicle)

**Objective:** Prove the fix on a repriceable draft and prove no regression on the shared Quote+Order procedure.

**Primary success criteria (fresh draft cancel + spot-check of the 6 historical lines):**
- Cancel line `NetUnitPrice` resolves to asset net (3000 for the undiscounted subject), `TotalPrice = −3000`, `Subtotal` correct (seq-37 clamp guarded), and **no `StampContributorBaseFilter` SF-BRE-00004**.

**Mandatory regression battery (each repriced via authorized Force Reprice, on Quote AND Order):**
| # | Case | Expected |
|---|------|----------|
| 1 | Subject full cancel (fresh draft mirroring 00095539) | NetUnitPrice 3000, TotalPrice −3000, no BRE |
| 2 | The 5 other broken cancels, incl. the 2 ListPrice-0 (beSECURE `802WC00000OgXD4YAN`, Automate Enterprise) | Derive **asset net**, not list |
| 3 | Derived/maintenance cancellation (IsDerived=true, non-Renewal) | seq-22 reset does NOT re-zero the seed |
| 4 | Partner derived-maintenance positive line (IsDerived=true, Deal_Type≠'Fortra Originated') | `Base_Price__c`/`Pre_Partner_Price__c`/partner discount UNCHANGED vs pre-fix |
| 5 | COLA renewal line | `COLACalculatedPrice__c`→NetUnitPrice path unchanged |
| 6 | Regional (Italy 0.64) positive line | `RegionalNetUnitPrice__c` unchanged |
| 7 | Normal new-business positive line, list≠net (e.g. list 250 → net 115.5) | net preserved, **seed did NOT fire** |
| 8 | Reduce-quantity DOWNGRADE amend (StartQty>EndQty>0, line qty<0) | **seed MUST NOT fire** (proves gate excludes non-cancel negatives) |
| 9 | Multi-currency cancel (non-USD asset) | credit in correct currency, no USD mis-credit |

**Regression assertions:**
- `StampContributorBaseFilter` SF-BRE-00004 no longer fires; report to the procedure owners that this step converts unpriced lines into hard reprice failures and should null-guard rather than hard-stop (latent bug beyond cancellations).
- The new context-def field does NOT re-trigger "couldn't fetch SalesTransactionContextExt_v2" (reprice one normal Quote AND one normal Order post Save&Publish, before activating any procedure change).
- Idempotency/ordering: seed runs before seq 14 (BRE), before seq 22 (reset, for derived), and before seq 26 (line-total); never clobbers a real waterfall net.

**Downstream checks (explicit, not assumed — known traps):**
- **Workday:** a now-negative line is a NEW payload shape. The Mule bug maps `extendedAmount ← TotalLineAmount` (list) vs net header and is **sign-sensitive** (SC-3374 was a sign-reversal fail). Assert the credit serializes with a **negative `extendedAmount`/`NetTotalPrice`, sign-consistent header vs line**, no sign flip. Re-submit a credit order headlessly: publish `Order_Completed_WD__e` with `Order_Id__c` and confirm Workday accepts (or document the Mule `extendedAmount←NetTotalPrice` fix as a dependency).
- **DocGen:** render a credit quote/order; confirm the negative shows as a **credit**, not $0 and not a fear-driven blank (the JPY/`$`-fear render pattern from SC-3384).

**Exit criteria:** all 9 battery cases pass; all regression assertions hold; Workday credit round-trips (or Mule dependency ticketed); DocGen shows the credit; FINEST log confirms the seeded NetUnitPrice at `QuantityPrice64`.

---

## PHASE 4 — Deploy (UAT) — requires fresh explicit authorization

**Objective:** Land the change with single-active-version discipline and a named rollback.

**Steps:**
1. **Fresh UAT deploy ack required** (read-only inspection done so far does not authorize a deploy; "focus on UAT" ≠ deploy authorization).
2. **Re-pull the live active version immediately before activation.** If it differs from the version you cloned from (a co-owner may have activated between clone and activate — documented repeatedly on this procedure), **ABORT and re-base.** Snapshot the live active version Id at activation time.
3. Deploy fields (MDAPI staging, api 67), FLS (Apex), context-def Save&Publish + republish (custom branch), prehook + test class, then the procedure version. Procedure **activation is UI-only**; observe the deactivate→activate offline window.
4. **Force Reprice** the fresh draft vehicle to verify post-activation.
5. **Re-pull the live active version immediately after activation** to confirm your version is the sole Active and was not clobbered.

**Rollback plan:**
- Named revert target: re-activate the recorded last-known-good Active version (**V16 `9QBWC0000000niH4AQ`** as of today) — keep it **Inactive-but-intact**, never delete (platform-blocked).
- Keep a saved metadata copy of the pre-change version under `Data/sc3441/`.
- **Abort rule:** any regression in the Phase 3 battery, any BRE recurrence, or any context-fetch failure → revert to the named version, leave the additive field/context/FLS in place (safe to leave), and re-base.
- Do NOT remove the `PricingActionParameters` Quote/Order context bindings (context wiring, must stay).

**Exit criteria:** sole Active = the new version (Id recorded); fresh draft cancel reprices to −3000; rollback target confirmed Inactive-but-intact; live re-pull before AND after matches expectation.

---

## PHASE 5 — Durability + prod promotion (decision gates)

**Objective:** Survive co-owner edits / Gearset refreshes, clear prod's coverage gate, and not block or get clobbered at cutover.

### 5.1 Durability verifier (re-runnable artifact under `Data/sc3441/`)
A saved SOQL+Apex assertion that checks: (a) active version Id + presence of the cancel seed AssignmentElement (or, native branch: `Asset.PricingSource` backfill intact); (b) `CancelNetUnitPrice__c` exists on QLI+OrderItem (custom branch); (c) both context-def mappings present; (d) prehook active + registered; (e) one canary reprice of the fresh draft yields TotalPrice −3000. **Re-run after any Gearset job or sandbox refresh** (documented silent-revert risk: PAD flags, procedure versions, NB-DERIVED-TIER oscillation, SC-3390).

### 5.2 Owner coordination / change-control
Bake the delta (seed container + field + context mapping + FLS, or the native provenance remediation) into the **republish source** and hand off to the procedure owner (Nir/Marc/Ben co-iterate this proc — `StampContributorBaseFilter` and the partner block are their recent V16 rework). Confirm a freeze window was honored.

### 5.3 PROD RECONCILIATION — DECISION GATE 2 (the single biggest unstated cutover risk)
- **Prod procedure is a DIFFERENT object:** prod `Rev_Mgmt_Default_Pricing_Procedure` = ExpressionSetDefinition **`9QAaZ00000Bj7S1WAJ`** (UAT = `9QAWC0000003mg14AA`). UAT version Ids (e.g. V16 `9QBWC0000000niH4AQ`) **do not exist in prod**. You cannot push UAT V16 by Id. **Pull prod's live active version, diff vs UAT V16, and decide: port only the cancel-seed delta vs port the whole V16 rework.** Prod likely predates the V16 partner rework (prod LACKS `PartnerNetPricePosthook`/`PartnerPricingPrehookV2`/`SourceListPricePrehook`). Output: written, owner-signed `prod base version = Vx, port plan = {delta only | full V16}`.
- **Prod field asymmetry pre-stages the context-fetch incident:** in prod, `Pre_Partner_Price__c`/`Partner_Pricing_Source__c`/`COLACalculatedPrice__c` exist on QuoteLineItem but **NONE on OrderItem**. The moment the prod procedure references any Order-side staging field, prod Order pricing will hard-fail "couldn't fetch SalesTransactionContextExt_v2" exactly as UAT did. **Prereq: close the existing partner/COLA OrderItem gap in prod FIRST**, and add `CancelNetUnitPrice__c` on BOTH QLI+OrderItem AND on BOTH `OrderEntitiesMapping` and `QuoteEntitiesMapping` (SalesTransactionItem) in the PROD context def (custom branch). **Context-fetch pre-deploy assertion (both orgs):** before activating any version referencing the staging field, assert the field is hydrated on both nodes and exists on both SObjects with FLS.
- **Prehook landscape differs:** confirm `CancelLineNetSeedPrehook` is order-INDEPENDENT of the prod-absent classes (RevSignaling registration order, context-attr write collisions); UAT validation does not transfer if behavior depends on co-resident prehooks.
- **Prod single-active check:** verify prod is single-active before and after (prod has its own lineage; the dual-active concern moves to prod).

### 5.4 Coverage gate — DECISION GATE 3
- **Measure prod's CURRENT org-wide coverage NOW as the baseline to protect.** UAT has 153 zero-coverage classes; the prehook template family is mostly red (PartnerNetPricePosthook 0/1286, PartnerPricingPrehookV2 0/484, AttributeVolumePricingPrehook 0/323, COLAUpliftPrehook ~76%, RegionalServicesPricingPrehook ~79%).
- The new `CancelLineNetSeedPrehook` needs its **own ≥75%** test AND a measured **prod-aggregate-stays-≥75% dry-run (RunLocalTests)** BEFORE the prod field/procedure deploy. **Test-first** is the gate.

### 5.5 Cutover-non-blocking decision — DECISION GATE 4
Decide explicitly: SC-3441 ships as **(1) UAT-only fix now + prod port tracked as a cutover-prereq sub-task**, or **(2) held until cutover**. State the dependency direction so **SC-3441 is not itself a cutover blocker** (the new prehook must not be the class that drags prod aggregate below 75%). Track the interim BRE null-guard (if shipped) as UAT-only-debt that must be carried into the prod port or explicitly retired by the real fix.

**Exit criteria:** durability verifier saved + passing; owner sign-off on prod base/port plan; prod OrderItem field gap closed; prod coverage baseline measured + new-class ≥75% + aggregate-stays-≥75% dry-run green; cutover dependency direction documented.

---

## INTERIM STOPGAP (clearly labeled — NOT a fix)

**Purpose:** stop the SF-BRE-00004 hard reprice failure while the real fix is staged. **It leaves TotalPrice = 0, so it is NOT a resolution of SC-3441.**

- **What:** make `StampContributorBaseFilter` criterion 5 (`NetUnitPrice GreaterThan 0`) null-safe — prepend `NetUnitPrice IsNotNull AND` so the `GreaterThan` is never evaluated on null (it is the ONLY null-unsafe NetUnitPrice filter in V16, so this single guard removes the whole BRE class).
- **Risk framing (do NOT ship as the prod state):** loosening this contributor-base step's gate changes contributor-base behavior for EVERY line transiently null-net — it touches the fragile/oscillating SC-3346/SC-3359/PartnerNetPrice area co-owners rework constantly. Low blast radius for the *subject* cancel line (gated out via the `(1 OR 2)` IsDerived clause), but it is **UAT-only debt** that must be carried into the prod port or retired by the real fix. Because UAT and prod are different-lineage versions, a UAT-only guard does NOT protect prod post-cutover, and a co-owner's next partner edit can silently undo it.
- **Preferred over the BRE guard if an interim is needed at all:** ship the real seed; or, Order-side only, the RCA Option E before-save stamp of `OrderItem.NetUnitPrice` (note QLI.NetUnitPrice is read-only + RLM blocks Quote DML, so this only works Order-side and diverges Quote vs Order). **Demote the BRE null-guard to last-resort.**

---

## EXPLICITLY REJECTED OPTIONS

- **Activate the drafted-Inactive V17 / any ListPrice→InputUnitPrice seed.** Writes the WRONG field — `InputUnitPrice` feeds only `ItemSubtotal` and never reaches the `NetUnitPrice` field that TotalPrice reads. Cannot fix TotalPrice.
- **List-price-based value seed.** Over/under-credits — 77% net≠list; 907 ListPrice-0/nonzero-net rows; 2 of 6 broken lines are ListPrice 0. Asset NET is the value spec.
- **A before-save flow/Apex DML stamp of `QuoteLineItem.NetUnitPrice`.** QLI.NetUnitPrice is engine-managed/read-only and RLM blocks all Quote DML at the platform tier — only the pricing engine (procedure/prehook context writes) can populate it.
- **Hand-rolled proration for partial cancels in this fix.** The full-quantity full-term seed `AssetActionSource.NetUnitPrice × Qty` does NOT prorate; partial/mid-term cancels and qty-reduction amends are gated OUT and ticketed separately (native LastTransaction + PriceRevisionPolicy handles proration if the native lever is adopted).

---

## RISKS / OPEN DECISIONS

1. **Native vs custom (Decision Gate 1)** — unresolved until the FINEST log + `Asset.PricingSource` probe + native-lever trial. The whole fix shape and blast radius hinge on this; do not build before it. *(Conflict between Critique-1's native-best-practice lens and the draft's custom-seed default — adjudicated to probe-native-first.)*
2. **Detail-vs-line tension** — `OrderItemDetail 14CWC000001KXDl2AO` carries `NetUnitPrice=3000` while the parent line is null. If this is a promote-back failure, the fix is different (and a seed could double-count). Settle via the Phase 1 FINEST log before building.
3. **Repro not repriceable** — 00095539 is Complete, the other cancel order Superseded, the quote-side repro Accepted. Verification must use a fresh draft; historical 00095539 correction is a separate data backfill (open question: does the business want it?).
4. **Partial-cancellation / qty-reduction proration** — out of scope here, gated out, ticketed separately. Decision: who owns the proration ticket?
5. **Version drift / co-owner clobber** — V14 and V16 both modified within 24s today; the active version changes minute-to-minute. Mitigated by freeze window + live re-pull before/after + abort-on-drift, but residual risk remains.
6. **Prod port shape (Decision Gate 2)** — prod is a different object on an older lineage with an OrderItem field gap that pre-stages the context-fetch incident. Open: port the delta only vs full V16; close the partner/COLA OrderItem gap first.
7. **Prod coverage (Decision Gate 3)** — prod baseline unmeasured; new prehook must not drag aggregate below 75%. Test-first.
8. **Cutover dependency direction (Decision Gate 4)** — UAT-now-with-prod-port-tracked vs hold-until-cutover; ensure SC-3441 is not itself a cutover blocker.
9. **Workday sign-handling** — negative `extendedAmount`/`NetTotalPrice` is a new payload shape on a known sign-sensitive Mule mapping; may require an `extendedAmount←NetTotalPrice` Mule dependency.
10. **Multi-currency** — asset-net carries a currency; any seed/lookup must be currency-aware to avoid the documented USD-blindness pattern.
11. **StampContributorBaseFilter is a latent platform bug beyond cancellations** — it hard-stops on any legitimately-unpriced line; report to owners to null-guard regardless of this ticket.
12. **Durability** — Gearset/refresh can silently revert fields/flags/versions; the re-runnable verifier (5.1) is the only detection. Native-lever (data) is more durable than a 7th custom staging field on a churned shared procedure.

---

## APPENDIX — load-bearing facts (verified this session)

- **V16 top-level execution order (by sequenceNumber):** `ListContainer47` seed = 13 → `ListContainer48`/`StampContributorBaseFilter` = 14 (BRE site, criterion 5 `NetUnitPrice > 0`) → `PartnerDiscountDerivedMaintenance` = 21 → `ListContainer10` "NetUnitPrice Value Reset" = 22 (gated `ItemIsDerived__std=true`) → `ListContainer2` COLA-seed = 24 → `ListContainer62`/`QuantityPrice64` line-total = 26 → `EvergreenanytimeprorationfilterLinelevel`/SubscriptionPricing = 28 → MAX clamp `FormulaBasedPricing3` = 37 (unconditional). **New seed must land at seq ≤ 13.**
- **TotalPrice routing:** `QuantityPrice64`: `ItemNetTotalPrice = NetUnitPrice × LineItemQuantity` → `Assignment108` → `ItemTotalPrice` → `TotalPrice`. `InputUnitPrice` → `ItemSubtotal` only.
- **Asset-net source:** `AssetActionSource.NetUnitPrice` via `OrderAction.SourceAssetId` (Order) or `QuoteAction.SourceAssetId` (Quote). Hydrated only under `AssetEntitiesMapping` today (0 refs under Order/Quote mappings) → prehook or context-def hydration required for the custom path.
- **Context attribute name is `PriceWaterFall`** (contextdef ~783–785), not `PriceWaterfallIdentifier` — use the in-context name in any gate.
- **Live version IDs:** UAT V16 `9QBWC0000000niH4AQ` (Active), V14 `9QBWC0000000nIT4AY` (Inactive, flipped 20:38:49), V17 `9QBWC0000000ntZ4AQ` (Inactive). UAT ExpressionSetDefinition `9QAWC0000003mg14AA`; PROD `9QAaZ00000Bj7S1WAJ`.
- **Repro states:** Order 00095539 = Order Complete (Activated 2026-06-16T22:09:53); 801WC00000kZUARYA4 = Superseded; quote 0Q0WC000003A8PB0A0/00781173 = Accepted. Cancel QLI `0QLWC000003fKAj4AM` → `QuoteActionId=7ocWC00000upzpBYAQ`.
- **Deploy mechanics:** ExpressionSetDefinition deploy api 67 + MDAPI staging (`rca_diagnostic.cls-meta.xml` orphan blocks source-format `sf` ops); version activation UI-only; context-def Save&Publish + republish; FLS via Apex FieldPermissions; do NOT delete versions (platform-blocked), deactivate only; keep PricingActionParameters Quote/Order bindings.
