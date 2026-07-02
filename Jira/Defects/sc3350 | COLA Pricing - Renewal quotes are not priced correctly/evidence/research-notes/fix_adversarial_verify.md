# SC-3350 — Adversarial verification of the InputUnitPrice→NetUnitPrice renewal seed

**Date:** 2026-06-10 (read-only, verified against the live V10 XML).
**Source XML:** `Data/sc3350/retrieve/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition-meta.xml` (52,499 lines, 11 `<versions>` blocks).
**Active block:** `Rev_Mgmt_Default_Pricing_Procedure_V100`, `<status>Active</status>`, **lines 46677–52498** (the LAST `<versions>` block). All 10 other blocks are `Inactive`.
**Method:** extracted active block to a scratch file and parsed step-by-step. All cites below are converted back to ORIGINAL file line numbers where given; element NAMES are the durable anchor.

**Verdict: GO-WITH-CONDITIONS.** The fix concept is correct and the bug is real, BUT a *blanket* `LastTransaction AND DerivedPricingAttribute=false` gate **regresses partner renewals** in the active V10. The gate MUST be tightened, the placement MUST be `ListContainer62` (not the brief's `ListContainer55`), and 3 runtime facts MUST be confirmed on a waterfall before activation.

---

## 0. The version-block trap (this reframes the whole design debate)

The XML compiles the SAME procedure into 11 `<versions>` blocks (V1…V10). **Element names like `ListContainer55`, `ListContainer62`, `PartnerDiscount24`, `COLAUpliftonRenewal21` are REUSED across blocks but wired DIFFERENTLY per version.** Any reasoning that greps the file globally and reads the FIRST match lands in the **V1 block (Inactive, lines 10–4872)** and is wrong for production.

| Block | fullName | status | line range |
|---|---|---|---|
| 1 | …_V1 | Inactive | 10–4872 |
| 2–9 | …V30/V40/…/V90 | Inactive | 4873–46676 |
| **10** | **…_V100** | **Active** | **46677–52498** |

- The brief's / RCA's names (`COLAUpliftonRenewal10`, `QuantityPrice49`, `ListContainer47`, `ListContainer35`, `ListOperation56`, `PartnerDiscount13`, lines ~1408–3473) are **V1-block artifacts** — they describe an INACTIVE version.
- Finding #1's claim "ListContainer55 does NOT exist in V10" is **also wrong**: `ListContainer55` exists in V10 (seq 21) — it is just the **NotEquals-LastTransaction** branch there, not the renewal branch.
- `ListContainer35` and `PartnerDiscount13` genuinely do **NOT** exist in the active V10 block (confirmed: `'PartnerDiscount13' in active_block == False`, `'ListContainer35' children == none`). They are V1-only.

---

## 1. Verified waterfall of the ACTIVE V10 (by ListGroup sequenceNumber)

All NetUnitPrice / InputUnitPrice writers and the relevant gates (active block only):

| seq | ListGroup | gate (filter on the group/child) | what it writes |
|----|-----------|----------------------------------|----------------|
| 7  | `ListContainer` (derived) | DerivedPricingAttribute=true AND AttributeDefinitionCode='MDT' (Path B); DerivedPricingValuesAssignment | InputUnitPrice; **DerivedPricingRenewals → NetUnitPrice** (COLA-net formula) |
| **9** | **`ListContainer2`** | ItemPricingSource=LastTransaction AND DerivedPricingAttribute=false AND ActionType='Renew' AND COLA% NotNull | **COLAUpliftonRenewal21: `COLACalculatedPrice__c → InputUnitPrice`** (Path A — the bug source) |
| **10** | **`ListContainer3`** | **`Deal_Type__c NotEquals 'Fortra Originated'`** (NO ItemPricingSource gate) | **PartnerDiscount24: InputUnitPrice × PartnerDiscountPercent → NetUnitPrice + Subtotal** |
| 17 | `ListContainer43` | ItemPricingSource **NotEquals** LastTransaction AND DerivedPricingAttribute=false | AttributeBasedPrice → NetUnitPrice |
| 18 | `ListContainer46` | (IsContracted null/false) AND ItemPricingSource **NotEquals** LastTransaction | AttributeDiscountEntries → NetUnitPrice |
| 19 | `ListContainer49` | ItemPricingSource **NotEquals** LastTransaction | BundleBasedAdjustmentEntries → NetUnitPrice |
| 20 | `ListContainer52` | (…) AND ItemPricingSource **NotEquals** LastTransaction | VolumeDiscountEntries → NetUnitPrice |
| 21 | `ListContainer55` | child `QuantityPrice` filter: ItemPricingSource **NotEquals** LastTransaction AND DerivedPricingAttribute=false | QuantityPrice57: NetUnitPrice×Qty → ItemNetTotalPrice |
| 22 | `ListContainer58` | ManualQuoteLevelDiscount: `… AND ItemPricingSource NotEquals LastTransaction` | Manual line discounts → NetUnitPrice |
| **23** | **`ListContainer62`** | **`ListOperation63` = ItemPricingSource Equals 'LastTransaction'`** (NO DerivedPricingAttribute, NO Deal_Type gate) | FormulaBasedPricing: **NetUnitPrice×Qty → ItemNetTotalPrice** ← **SEED TARGET** |
| 24 | `TermDefinedSubscriptionFilter…` | SellingModelType Equals 'TermDefined' | SubscriptionPricing: reads NetUnitPrice + PricingTermCount, writes SubscriptionNetUnitPrice → NetUnitPrice + ItemNetTotalPrice |
| 33 | `RegionalNetReconcile` | RegionalNetReconcileGate (regional flag) — NO ItemPricingSource gate | RegionalInputUnitPrice/RegionalNetUnitPrice → InputUnitPrice/NetUnitPrice |

**Container 62 currently has exactly 2 children:** `ListOperation63` (filter, seq 1) and `FormulaBasedPricing` (seq 2). No seed exists today → the fix adds one new Assignment ordered BEFORE FormulaBasedPricing.

---

## 2. Answers to the five pressure-test questions

### Q1 — Does `DerivedPricingAttribute=false` exclude ALL derived renewals? Are there non-derived renewals that *should* get net from a discount path (so a blanket seed overstates net)?

**(a) Derived (Path B) exclusion: YES, the gate is mandatory and sufficient for Path B.**
Path B (`DerivedPricingRenewals`, formula `(Base_Price − Prior_Partner_Discount − Prior_Discretionary_Discount)×(1+COLA%/100) → NetUnitPrice`) is gated `DerivedPricingAttribute=true AND AttributeDefinitionCode='MDT'`. These lines are ALSO `ItemPricingSource=LastTransaction`, so they DO enter `ListContainer62` (whose filter has NO DerivedPricingAttribute gate). Without `DerivedPricingAttribute=false` on the seed, the seed would overwrite the Path-B net with raw InputUnitPrice → **clobbers derived renewals**. The `=false` gate prevents this. **Confirmed: `=false` is non-negotiable, not optional.**

**(b) A real exclusion GAP (pre-existing, not our regression):** a line with `DerivedPricingAttribute=true` but `AttributeDefinitionCode != 'MDT'` gets NEITHER Path B (formula gated to MDT) NOR our seed (`=false` fails). It stays NetUnitPrice=0. This is **a pre-existing hole**, no worse after the fix. Flag, don't block.

**(c) The dangerous "should get net from a discount path" case = PARTNER renewals (see Q2).** A non-derived renewal that legitimately carries a partner discount via `PartnerDiscount24` (seq 10) WOULD be overstated by a blanket seed. This is the load-bearing finding — `DerivedPricingAttribute=false` does NOT exclude it because partner renewals are also non-derived.

### Q2 — Sequencing: if the seed runs before discounts that fire for LastTransaction lines, do we lose them? If after, does something zero it?

**The decisive structural fact:** I enumerated EVERY step that writes NetUnitPrice in active V10 and its group gate. **Every discount/adjustment writer except one is gated `ItemPricingSource NotEquals 'LastTransaction'`** (AttributeBasedPrice@17, AttributeDiscountEntries@18, BundleBasedAdjustment@19, VolumeDiscount@20, ManualQuoteLevel@22). So they DO NOT fire for renewals — the seed cannot lose them, and they cannot re-zero the seed.

**The ONE exception = `PartnerDiscount24` (`ListContainer3`, seq 10).** Its gate is **only** `Deal_Type__c NotEquals 'Fortra Originated'` — there is **no ItemPricingSource criterion**. So a **partner renewal** (LastTransaction + non-Fortra Deal_Type) hits PartnerDiscount24 at seq 10 and gets a correctly discounted NetUnitPrice. Our seed at seq 23 runs AFTER seq 10 and, with the brief's gate, MATCHES that same line → **overwrites the partner-discounted net back to undiscounted InputUnitPrice (list/COLA).** PartnerDiscount24 reads InputUnitPrice but does NOT write it, so InputUnitPrice still = list at seq 23 → the regression is a clean revert-to-list. **THIS IS A REAL PRODUCTION REGRESSION the brief's gate does not prevent.**

**Downstream (after seq 23):** SubscriptionPricing@24 (TermDefined) and RegionalNetReconcile@33 run after the seed. They READ NetUnitPrice and re-derive — they do NOT zero it (they transform). See Q3/Q4.

### Q3 — Does SubscriptionPricing transform NetUnitPrice in a way that makes seeding InputUnitPrice wrong for term/multi-year lines?

`SubscriptionPricing` (parent `TermDefinedSubscriptionFilter…`, seq 24, gate SellingModelType='TermDefined') params:
- inputs: `NetUnitPrice`, `ProrationMultiplier=PricingTermCount`, `Quantity=LineItemQuantity`.
- outputs: `SubscriptionNetUnitPrice → NetUnitPrice`, `TotalSubscriptionPrice → ItemNetTotalPrice`.

It takes the per-unit NetUnitPrice and applies term/proration. This is **exactly the same input contract the engine uses for new-business term lines** — they too arrive at SubscriptionPricing with a per-unit NetUnitPrice (from QuantityPrice57 etc.) and get the term multiplier applied. So seeding a **per-unit** InputUnitPrice (the COLA'd unit price 4697.946, NOT a total) into NetUnitPrice is the correct unit for SubscriptionPricing to consume. **No wrongness for term/multi-year — provided the seed is the per-unit InputUnitPrice (it is; COLAUpliftonRenewal21 writes a unit price).** The current bug is precisely that SubscriptionPricing reads NetUnitPrice=0 → outputs 0. Seeding the unit price fixes it correctly. **No objection on Q3.**

### Q4 — Could this change alter net for the ~40 existing live renewal lines that price "correctly" today (regression)?

- **Fortra-direct non-derived renewals (Deal_Type='Fortra Originated', the RCA Abstract line):** currently $0 (the bug). Seed fixes them. No regression — these are the target.
- **Partner non-derived renewals (Deal_Type≠'Fortra Originated'):** **AT RISK.** If any of the ~40 "correctly priced" lines are partner renewals, they are correct TODAY *because* PartnerDiscount24 ran. A blanket seed would flip them to list. **This is the regression to existing-correct lines.** The Deal_Type='Fortra Originated' clause removes it.
- **Derived/MDT renewals:** excluded by `=false`. No change.
- **Regional renewals:** RegionalNetReconcile (seq 33) runs AFTER the seed and re-derives regional net from its own gate; the seed feeds it a non-zero starting point (improvement, not regression) — but this MUST be validated on an Italy line because the RCA noted the field named "Net" is sometimes wired to list in the regional path.

### Q5 — Did the original designers DELIBERATELY exclude LastTransaction from the seed (is the gap intentional)?

**Partially intentional.** Every discount/list-seed path in V10 is *uniformly* gated `NotEquals 'LastTransaction'`. That is a deliberate design stance: **renewals are NOT meant to be re-priced through the discount engine; they carry net forward from the prior transaction** (COLA-adjusted via Path A on InputUnitPrice, or recomputed via Path B for derived). `ListContainer62` (the LastTransaction branch) deliberately bypasses the whole discount stack and just does NetUnitPrice×Qty.

**The genuine DEFECT is narrow:** Path A (COLAUpliftonRenewal21) writes the renewed unit price to **InputUnitPrice only**, and there is **no LastTransaction-scoped step that copies InputUnitPrice→NetUnitPrice for the non-derived branch.** Path B handles its own NetUnitPrice; the non-derived COLA case fell through a missing seed. So the seed is filling a real hole, NOT overriding an intentional "renewals stay $0" rule. The intentional part (no discount re-application on renewals) is *preserved* by placing the seed in the bypass container and copying the already-final InputUnitPrice — **as long as we don't clobber the one discount (PartnerDiscount24) that legitimately DID run for partner renewals.**

---

## 3. Why the brief's `ListContainer55` placement is wrong in V10 (verified)

- `ListContainer55` in active V10 (seq 21) child `QuantityPrice` filter = **ItemPricingSource NotEquals 'LastTransaction' AND DerivedPricingAttribute=false** → it is the NON-renewal branch. A seed inside it either (a) inherits that filter and never fires for renewals (inert), or (b) carries its own `Equals LastTransaction` filter, producing an unprecedented two-contradictory-filter group whose runtime semantics are not attestable from static XML.
- The TRUE renewal container is **`ListContainer62` (seq 23)**, filter `ListOperation63` = `ItemPricingSource Equals 'LastTransaction'`. Findings #1 and #2 correctly identify this. The brief and the RCA are stale on the container name.

---

## 4. Required conditions before activating V11 (GO-WITH-CONDITIONS)

**MUST (blockers):**
1. **Placement = `ListContainer62` (seq 23)**, new `AssignmentElement` (`InputUnitPrice → NetUnitPrice`, Currency→Currency, mirroring `COLAUpliftonRenewal21`), ordered BEFORE `FormulaBasedPricing` (the NetUnitPrice×Qty step). NOT `ListContainer55`.
2. **Gate = `ItemPricingSource Equals 'LastTransaction' AND DerivedPricingAttribute = false AND Deal_Type__c Equals 'Fortra Originated'`.** The `Deal_Type='Fortra Originated'` clause is the blocker — without it, partner renewals regress to list (Q2/Q4). [Equivalent acceptable guard: `NetUnitPrice = 0` / `NetUnitPrice IsNull`, IF runtime confirms the unwritten default — see condition 4 — but Deal_Type is the safer, deterministic exclusion.]
3. **Build the seed in ALL active-version variants the engine compiles.** Confirmed the active block is the LAST `<versions>` block; verify post-edit that the new step name appears the expected number of times and ONLY inside V10's `ListContainer62` (grep the new step-name count; ensure it is not accidentally added to V1–V9 inactive blocks or to ListContainer55).

**MUST (runtime confirmation on a Reprice-All / Explainability waterfall — cannot be settled statically):**
4. **Null-vs-zero default of NetUnitPrice** on an unseeded LastTransaction line — only matters if you choose the `NetUnitPrice IsNull/=0` guard variant instead of (or in addition to) Deal_Type. If you use the Deal_Type clause alone this is informational, not blocking.
5. **No-COLA renewal InputUnitPrice source:** confirm that a non-derived, Fortra-Originated, `COLA% = null` renewal line has InputUnitPrice = the correct prior unit price at seq 23 (i.e., something upstream seeds InputUnitPrice for it). COLAUpliftonRenewal21 only fires when COLA% is NotNull, so a no-COLA renewal does NOT get InputUnitPrice from Path A. If InputUnitPrice is null/list-garbage for that case, the seed would push wrong net. **This is the principal residual unknown.** (Several upstream InputUnitPrice writers exist — DerivedPricingValuesAssignment@7, GSAPricing18@8, ListContainer40 Assignment@16 — but whether any covers the plain no-COLA renewal must be traced.)
6. **Partner-renewal scope:** confirm whether partner renewals are currently $0 in the field (then PartnerDiscount24 is being bypassed → different RC, revisit) or correctly discounted (then the Deal_Type exclusion is exactly right). Pull a partner renewal line's waterfall.
7. **Regional renewal:** validate one Italy-regional renewal line end-to-end; confirm RegionalNetReconcile@33 produces the intended net after the seed (the "Net field wired to list" caveat).

**PROCESS (per project rules / memory):**
8. Clone active V10 → Draft V11 in the Pricing Procedure Designer (do NOT hand-edit the 52k-line XML to create the version; the Designer Clone path avoids the duplicate-`<versions>` minefield). Use the verified `fix_ui_mapping.md` element targets (ListContainer62 / Assignment), corrected for the gate above.
9. **Coordinate with Marc DeBrey** — this is the shared active `Rev_Mgmt_Default_Pricing_Procedure`; prior in-place edits without re-syncing context `SalesTransactionContextExt_v2` caused gacks. After publishing V11, re-verify/re-sync the context definition and OrderEntitiesMapping.
10. **Any UAT activation (even validate-only) requires a fresh explicit deploy ack** (memory: "Focus on UAT ≠ deploy authorization"). This review is design-only.
11. Build + validate on the RCA's broken renewal quote (`0Q0WC000003671t0AA` per RCA) and confirm the Net track now anchors on the COLA InputUnitPrice (~4697.946) instead of 0.

---

## 5. Rollback

- V11 activation auto-deactivates V10. **Rollback = re-activate V10** (it remains as an Inactive version in the ExpressionSetDefinition) via the Designer / `ExpressionSetDefinitionVersion.Status`. No data migration; pricing is recomputed on next Reprice. Keep V10's version Id recorded before activating V11.
- If the regression surfaces only on partner renewals post-activation, the rollback is immediate version-swap; do not hot-edit V11 in place (would repeat the gack pattern). Fix in a new Draft V12, validate, then swap.

---

## 6. Confidence ledger

| Claim | Confidence | Basis |
|---|---|---|
| Active = last `<versions>` block (V100, L46677–52498); names reused per-version | HIGH | direct grep of `<status>` per block |
| ListContainer62 (seq 23) = true LastTransaction renewal container; ListContainer55 (seq 21) = NotEquals branch | HIGH | `ListOperation63`/`QuantityPrice` filter text in active block |
| PartnerDiscount24 (LC3, seq 10) gated Deal_Type-only, fires for partner renewals, writes NetUnitPrice | HIGH | step params + filter in active block |
| All other NetUnitPrice discount writers gated NotEquals LastTransaction (no renewal collision) | HIGH | enumerated every NetUnitPrice-output step + its group filter |
| Blanket gate regresses partner renewals; Deal_Type='Fortra Originated' fixes it | HIGH | seq 10 < seq 23 + InputUnitPrice unmodified by PartnerDiscount24 |
| `DerivedPricingAttribute=false` mandatory (Path B also enters LC62) | HIGH | LC62 filter has no DerivedPricingAttribute gate; Path B is LastTransaction |
| SubscriptionPricing consumes per-unit NetUnitPrice → seeding unit price is correct | HIGH | step param contract |
| No-COLA renewal InputUnitPrice source | LOW (runtime) | COLA21 only fires COLA%≠null; other InputUnitPrice writers exist but coverage of the plain case not traceable statically |
| Partner renewals currently correct (not $0) in field | MEDIUM (runtime) | structurally PartnerDiscount24 runs; field state needs waterfall |
| Regional renewal net after seed | MEDIUM (runtime) | RegionalNetReconcile@33 has no ItemPricingSource gate; "Net=list" caveat |
