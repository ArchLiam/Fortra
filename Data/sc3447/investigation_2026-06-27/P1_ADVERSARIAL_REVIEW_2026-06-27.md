# SC-3447 P1 — Adversarial Review of the P1 Spec (read-only, 2026-06-27)

Reviewer role: adversarial critic of the proposed P1 spec (make each Power-split clone cheap).
Org: FortraUAT (00DWC000006eUFF2A2). All checks read-only (`sf data query`, `sf sobject describe`,
retrieved flow XML, Read/Grep). No mutations, no deploy.

**Verdict: PARTIALLY-SOUND.** The two coupled changes (describe-hoist + flow-suppression-with-Apex-stamp)
are technically correct, behavior-preserving, and independently verified against live UAT. The cap stance
(keep 200, do not raise on the estimate) is the right call. I found **no correctness showstopper.** The
defects are: (1) a factual ID-labeling error in the spec's "re-verified live" provenance; (2) one
suppression-safety argument that is *under-stated* (the spec doesn't prove reprice can't strand a stale
stamp — I verified it cannot, but the spec should say so); (3) a couple of honesty/scope nuances on the
ceiling and the dead services-branch guard. None block the build.

---

## A. What I independently re-verified live (held / corrected)

| Claim in spec | Live check (2026-06-27) | Result |
|---|---|---|
| Set_Dates active = V6, API 67, RecordBeforeSave, no start filter | Flow tooling + retrieved XML | **CONFIRMED** (version Id `301WC00000knsJNYAY`) |
| Set_Workday active = V11, API 66, RecordAfterSave, no start filter | Flow tooling + retrieved XML | **CONFIRMED** (version Id `301WC00000kUYVFYA4`) |
| Set_Workday V11 = 2 SOQL (Get_Prepaid_Order_Attribute + Get_Product) | recordLookups count in XML | **CONFIRMED** (2 recordLookups, 4 conditional recordUpdates) |
| Set_Workday V11 subsplit from `$Record.Product2.Is_Subsplit_Product__c`, **0** `Original_Order_Item__c` refs | grep active XML | **CONFIRMED** (0 hits for Original_Order_Item__c / Is_Split_Line__c) |
| Set_Dates V6 = 0 SOQL, in-memory $Record writes of 6 fields | recordLookups=0, recordUpdates=3 ($Record) | **CONFIRMED** (writes Billing_Schedule_From/To, End/Start_Date_Calculated, backstop EndDate/PTC) |
| OrderItem 208 total / 149 createable | `sf sobject describe` parse | **CONFIRMED** (208 / 149 / 142 updateable) |
| 7 stamp + 5 customize fields all createable+updateable, none calculated/read-only | describe parse | **CONFIRMED** (all 13 create=T update=T calculated=F) |
| Workday line-type picklist = the exact 4 values | describe picklistValues | **CONFIRMED** (USAGE BASED, PREPAID, FIXED AMOUNT BILLING ONLY, FIXED AMOUNT) |
| 0 OrderItem triggers, 0 OrderItem VRs | Tooling ApexTrigger / ValidationRule | **CONFIRMED** (0 / 0) |
| Convert flow active = V28, API 62 | Flow tooling | **CONFIRMED** (version Id `301WC00000lmnmfYAA`) |
| P3-eligible split population = 4 OrderItems, all qty=3 (N=2) | live COUNT | **CONFIRMED** (4 rows, max qty 3) |
| Total Power qty>1 lines | live COUNT | **CONFIRMED** = 3,816 |
| Reprice tail O(N+L): 1 RecordWithReferenceRequest/OI + Force + double persistFromWork + posthook | `OrderRepriceInvocable_live.cls` | **CONFIRMED** |
| No compound (address/location) fields on OrderItem | describe parse | **CONFIRMED** (no compound-copy hazard) |

---

## B. CRITICAL ISSUES (try hard to break it)

### B1 — FACTUAL: the spec's "re-verified live" Flow IDs are FlowDefinition IDs, not version IDs (provenance overstated)

The spec's executive summary and §0 table say:
- "Set_Dates V6 (Flow **300WC00000Qqd9ZYAR**, API67)"
- "Set_Workday V11 (**300WC00000QqP3OYAV**, API66)"
- "Convert V28 (**300WC00000LtlNBYAZ**)"

Those `300WC...` IDs are **FlowDefinition (DefinitionId) IDs**, not the active **Flow (version) IDs**. Live:

| Flow | DefinitionId (300…) | Active version Flow Id (301…) |
|---|---|---|
| Set_Dates V6 | `300WC00000Qqd9ZYAR` | `301WC00000knsJNYAY` |
| Set_Workday V11 | `300WC00000QqP3OYAV` | `301WC00000kUYVFYA4` |
| Convert V28 | `300WC00000LtlNBYAZ` | `301WC00000lmnmfYAA` |

The spec's own quantify docs (P1_01, P1_02) correctly use the `301…` version IDs. So the SPEC is internally
inconsistent with its supporting docs and mislabels the IDs it claims to have "re-verified live 2026-06-27."
**Impact: cosmetic** — the flows are unambiguously identified by name + version, and at deploy you clone the
active version by name regardless. But the spec presents these IDs as precise live evidence, which overstates
precision. **Correction:** relabel as DefinitionId, or replace with the `301…` version IDs.

### B2 — UNDER-STATED suppression safety: spec never proves reprice can't strand a stale clone stamp (it can't — I verified)

The strongest attack on flow-suppression: today (flows active) the **reprice tail re-fires both OI flows on
clones** during its bulk OrderItem UPDATE passes (`persistFromWork`, `OrderCommercialNetService.patch`,
`PartnerNetPricePosthook`). After suppression those re-fires stop on clones. **If reprice changed any field
that Set_Dates derives FROM (ServiceDate/EndDate) or that Set_Workday reads (the product boolean), the clone
would be left with a stale stamp** that the now-suppressed re-fire would have corrected.

I read the live reprice classes to test this:
- `OrderCommercialNetService.patchOrderItemCommercialUnitPrices` updates **only `NetUnitPrice` and `UnitPrice`**
  (lines 44-48 of the live class) — pricing fields, never date/term/product-boolean.
- The Force `PlaceOrderExecutor` reprice recomputes pricing; it does not rewrite `Product2Id`, `ServiceDate`,
  or the Set_Dates date inputs on a clone.
- Set_Dates derives from Order.EffectiveDate / ServiceDate / EndDate / SellingModelType; Set_Workday derives
  from Product2 booleans. **None of these are mutated by the reprice tail.**

So the suppressed re-fire on clones would have produced **byte-identical** values → no stranded stale stamp.
**Conclusion: suppression is safe — but the spec asserts this only by analogy ("clone carries identical
stamped values by copy"), and never addresses the reprice re-fire path.** This is the single most important
safety argument the spec leaves implicit. **Correction:** add the explicit statement that the reprice tail
mutates only pricing fields (NetUnitPrice/UnitPrice/TotalPrice), none of which feed either suppressed flow,
so skipping the clone re-fire during reprice changes no output. Measurement-plan step 4 (equivalence assert
under reprice) is the empirical backstop and must NOT be dropped.

### B3 — CEILING HONESTY: reprice has a `totalsAlreadyMatch` short-circuit that the pessimistic model ignores

The ceiling model (P1_03 + spec §3) bounds the post-P1 ceiling by the reprice-tail CPU (V16 procedure
~30/19/8 ms/line). But the live `OrderRepriceInvocable.repriceOne` **short-circuits the heavy Force reprice +
PartnerNetPricePosthook when `totalsAlreadyMatch`** (lines 45-49, 78-80) — i.e. when quote commercial nets
are already on the order (the common fresh-convert case). On that path the O(N+L) Force-procedure cost (the
binding term in the pessimistic ~30 ms/line model) **does not run at all**; only `persistFromWork` (×2) and
`patchOrderItemCommercialUnitPrices` execute O(N+L).

This cuts **both ways** and the spec is not wrong to be conservative, but it is **incompletely honest**:
- It means the realistic post-P1 CPU ceiling is likely HIGHER than the pessimistic ~315 (the heaviest term
  may be skipped), so "keep 200" is comfortably safe.
- BUT the `totalsAlreadyMatch` path is data-dependent (Power split lines with partner/regional nets may NOT
  match → full reprice runs). So the cap-gating term genuinely IS unmeasured and the "do not raise on the
  estimate" stance is correct.
**Correction:** the model should name the `totalsAlreadyMatch` branch as the reason ms/line is bimodal
(near-zero on the match path, ~8-30 on the no-match path), and the measurement must exercise the no-match
path (mismatched totals) to capture the worst case — otherwise the K-sweep could under-measure the ceiling.

### B4 — DEAD GUARD under P3: the services-branch of `deriveWorkdayLineType` is unreachable for P3-eligible lines

The spec adds `Product2.pse__IsServicesProduct__c` to the query and a services branch in `deriveWorkdayLineType`
(copy parent's WCLT for services). But P3 only admits partition/hardware (per-machine) lines, and P1_02
verified **all P3-eligible Power lines are non-services**. So under P3 the services branch is **dead code**.
**Impact: none harmful** (defensive, no extra SOQL — it's a relationship column). But the spec should label it
as a defensive guard that is currently unreachable, not present it as load-bearing logic. If P1 ever ships
WITHOUT P3 (the spec says it can), the services branch becomes live — at which point "copy parent" is a real
stale-parent exposure for services lines (the very thing re-derive was added to avoid). **Correction:** note
that the copy-parent services fallback re-introduces the stale-parent risk for services lines on a P1-without-P3
deploy; it is only safe because P3 excludes services lines. If P1 ships first, accept that services-line WCLT
is copy-only (matches today's behavior; no regression, but not the hardening re-derive gives non-services).

---

## C. Corrections / refinements (non-blocking)

1. **B1** — Replace the `300WC…` "Flow Id" labels with the `301WC…` active-version IDs (or relabel as
   DefinitionId). The flows are correctly named; only the ID provenance is mislabeled.
2. **B2** — Add the explicit reprice-input-invariance argument (reprice mutates only NetUnitPrice/UnitPrice;
   neither suppressed flow reads those) to the suppression-safety section. Keep equivalence-assert step 4.
3. **B3** — Document the `totalsAlreadyMatch` short-circuit; make the measurement force the no-match path so
   the K-sweep captures the worst-case reprice ms/line, not the short-circuited near-zero path.
4. **B4** — Mark the services branch of `deriveWorkdayLineType` as a defensive, currently-unreachable guard
   (dead under P3); flag the copy-parent stale risk it carries if P1 ships without P3.
5. **Hoist try/catch** — The proposed `createFullClone` correctly KEEPS the per-field try/catch (spec lines
   86-91), so a createable-but-not-queried field still throws-and-skips exactly as today → byte-identical
   output preserved. Confirmed no behavior change. (Verified there are no compound address/location fields
   that would complicate the copy.)
6. **Per-original double-fire floor (spec openRisk #6)** — Honest and correctly scoped OUT of P1. Originals
   are `Is_Split_Line__c=false` (the value the guard admits), so they keep firing both flows on BOTH the
   createOrderFromQuote insert AND the mapper update. On a large-L (many-distinct-line) quote this O(2L) floor
   can bind CPU independent of N; P1 does not touch it. Correctly disclosed.

---

## D. Answers to the five required attack questions

### 1. Suppression safety — does `Is_Split_Line__c=false` on both flows really break nothing?
**YES, safe.** Verified:
- Originals (slot 0) are reset to `Is_Split_Line__c=false` at Phase 5 (L264) → still satisfy the `=false`
  entry condition → still flow-stamped on the Phase-5 update (same as today, where no entry condition exists
  so flows fire on every update). The entry condition does NOT starve originals.
- All normal (non-split) lines default `Is_Split_Line__c=false` (Checkbox) → unaffected.
- Only the qty-1 clones carry `Is_Split_Line__c=true` (set in memory at L193 BEFORE the L245 insert) → skipped.
- 0 OI triggers, 0 OI VRs, no flow/VR/rollup consumes `Is_Split_Line__c` or `Original_Order_Item__c` in the
  active layer (only the page Layout + the Apex class). Active V11 has 0 reverse-lookup refs.
- **Original re-stamp after Phase 5 reset: CORRECT** — the Phase-5 update flips the flag back to false, so the
  flows fire and re-stamp the original. Unchanged from today.
- **Gap the spec under-states (B2):** the reprice re-fire on clones is suppressed too, but reprice mutates
  only pricing fields (not the flow inputs), so no stale stamp is stranded. Verified, but the spec should say
  it explicitly.

### 2. Stamp correctness — copied fields identical per-unit?
**YES.** `Manual_Discount__c`/`Displaced_ARR__c` are blindly copied at full value by `createFullClone`, then
**overwritten** with the `/qty` per-unit value at L191-192 — so the P1 stamp list correctly does NOT touch
them (already handled). Pricing fields (`NetUnitPrice`, `NetTotalPrice`, `TotalLineAmount`, `UnitPrice`,
`Base_Price__c`, `CancelNetUnitPrice__c`, etc.) are copied at full value but `Quantity` is set to 1, so the
pre-reprice clone has inconsistent totals — **but reprice recomputes prices** (Force `PlaceOrderExecutor` +
`OrderCommercialNetService.patch`), so the copy is moot/safe. This is **pre-existing behavior**; P1's
byte-identical hoist preserves it exactly → no new risk. No field "must not be copied" beyond what the
existing overwrite logic and reprice already handle.

### 3. Hoist correctness — static createable list safe across the transaction?
**YES.** `initOrderItemFieldLists()` iterates the same `fields.getMap().keySet()` and applies the same
`isCreateable()`/`isAccessible()` predicates the current loops use, once per transaction. FLS/describe do not
vary per record within a transaction (they are user+schema scoped, not row scoped), so a single static list
is correct. The rewritten `createFullClone` keeps the per-field try/catch, so any createable-but-unqueried
field is skipped exactly as today → byte-identical clone field-set. No compound fields exist to complicate
the copy. Test A1 (byte-identical assert) is the right gate.

### 4. Ceiling honesty — is the cap defensible?
**Mostly yes; honesty is good but incomplete (B3).** The "keep 200, raise only after measurement" stance is
correct and well-justified: P1 shrinks the SPLIT phase, not the reprice/activate tail (F7/F8/F9 all O(N+L),
untouched by P1), so the whole-convert ceiling is bounded by the reprice tail, which is unmeasured. The
estimate-vs-measured table (§7) is honest. **The one gap:** the model ignores the live `totalsAlreadyMatch`
short-circuit that can skip the heaviest reprice term — which means the realistic ceiling may be higher than
the pessimistic ~315 (further supporting "keep 200 is safe"), but also means the measurement MUST force the
no-match path to capture the worst case. The per-original O(2L) double-fire floor is correctly disclosed as
an untouched, separate constraint.

### 5. Interaction with P0 cap and local P3?
**No conflict.** P1 touches only `createFullClone`/`queryOrderItemsToSplit` internals + the clone-customize
block + two flow entry conditions. The P0 cap counts `totalClones` from the (P3-filtered) `itemsToSplit`
before any DML (L137, before first DML at L220) and sets `success=false` on all results — unaffected by the
hoist. The WCLT stamp is added after the cap check. P3's effect (only partition/hardware non-services lines
reach the clone loop) means the WCLT re-derive always takes the non-services product-boolean branch and the
services branch is dead (B4) — consistent with the spec's own claim. **P1 is orthogonal to both.**

---

## E. Bottom line
The P1 spec is buildable and behavior-preserving. Fix the ID labeling (B1), make the reprice-invariance
suppression argument explicit (B2), document the `totalsAlreadyMatch` reprice short-circuit and force the
no-match path in measurement (B3), and label the services branch as a dead/defensive guard under P3 (B4).
Keep the cap at 200 and gate any increase on the measurement. No correctness showstopper.
