# SC-3447 — Deep Research Report (re-verified against live FortraUAT)

**Ticket:** Quote→Order conversion fails on high-quantity orders — Apex CPU governor limit
**Priority:** Blocker · **Reporter:** Joe Romo · **Assignee:** Liam Jeong · **Label:** CRM-Revenue-Cloud
**This research:** 2026-06-26 · read-only against FortraUAT (`00DWC000006eUFF2A2`) · **no code/data/deploy changes**
**Supersedes/extends:** the 2026-06-18 dossier in `*Jira/Task/sc3447 | …/` (now stale on two points — see §1)

---

## 0. TL;DR

Converting a quote that contains a high-quantity **`Solution_Group__c = 'Power'`** line fails with
`System.LimitException: Apex CPU time limit exceeded` (`error.cause = FLOW_INTERVIEW_LIMIT_EXCEEDED`) and the
whole order rolls back. The convert screen-flow runs **synchronously** (10,000 ms Apex CPU ceiling) and calls
`PowerOrderSplittingService`, which expands a Power line into **(qty − 1) individual qty=1 OrderItem clones**
— each re-triggering the OrderItem record-triggered flows. Record volume and flow-interview count scale **1:1
with quantity**, so the transaction runs out of CPU (and would hit the hard 10,000-DML-row ceiling first at
larger quantities).

**Two material corrections to the original dossier, verified live today:**

1. **The "deprecated Autolaunched Set Workday Contract Line Type" subflow is now INACTIVE** (no active
   version; SC-3366 deactivated it 2026-06-08). It no longer fires per clone, so the original "≈⅓ of the load"
   item is **already resolved** — the per-clone flow load today is **2 flows, not 3**. The dossier analyzed a
   pre-2026-06-08 log. *Net effect:* the CPU ceiling has already moved up several-fold, and the specific repro
   quote (Abstract @ 456) **may now convert** — but the architectural defect is unchanged and still fails at
   higher quantity.

2. **The real blast radius is far bigger than "Abstract is mis-tagged test data."** Live data shows Power
   `Quantity` is routinely a **user/seat-license count in the thousands** (e.g. *Powertech Password Self Help*
   @ 7,500; *MFA for IBM i* @ 9,900) and an **"unlimited" sentinel** (9,999 / 99,999 / **999,999**). **Power
   `Quantity` is NOT a physical-machine count.** Per-unit OrderItem splitting is therefore **conceptually
   wrong** for the majority of high-qty Power lines, not merely slow. **134** live OrderItems sit at the
   999,999 sentinel; **419** real Power lines exceed qty 50 (excluding the sentinel).

---

## 1. What changed since the 2026-06-18 dossier (verified 2026-06-26)

| Claim in original dossier | Status today (live-verified) | Evidence |
|---|---|---|
| 3 flows fire per clone (Set Dates, V11 line-type, **deprecated Autolaunched**) | **2 flows.** Deprecated Autolaunched is **INACTIVE** (no active version) and **no live flow invokes it** | `FlowDefinitionView.IsActive=false`; grep of all live flows finds 0 subflow refs |
| "Abstract = Power is likely mis-tagged test data; Endpoint DLP @ 750k isn't Power so it'd convert fine" | True for the *gate*, but **understates scope** — Power is a real 3,406-product catalog group and real Power lines reach qty 999,999 | `Product2` count + `OrderItem`/`QuoteLineItem` qty distribution |
| Per-clone load ≈ 1,293 flow interviews | That count **included the 408 deprecated-flow interviews**; today's per-clone load is ≈ 2 interviews/clone (Set Dates + V11) plus V11's re-entrant re-fire | flow definitions + log |

> **Action implied:** re-run the repro to find the *current* empirical failure threshold (it has moved up).
> Do **not** quote the old 1,293/≈400-clone numbers as current.

---

## 2. Verified architecture — the synchronous convert chain

`Fortra Quote to Order Conversion` (Active flow `301WC00000kSRnZYAW`, `ProcessType=Flow`, screen flow) runs the
following actions, **all `flowTransactionModel = CurrentTransaction` (one synchronous request, 10,000 ms CPU):**

```
Validate_Checklist_Complete (apex: ChecklistValidationService)
  → Call_Create_Order_From_Quote (createOrderFromQuote)         ← inserts Order + OrderItems (originals)
  → MapQuoteLineFieldsToOrderItems (apex: QuoteToOrderFieldMapper)
  → SplitPowerOrderLines (apex: PowerOrderSplittingService)     ← THE EXPANSION
  → Reprice_Order_Before_Activate (apex: OrderRepriceInvocable) ← reprices the now-N×-larger order
  → Activate_Contract / Activate_Order                          ← activation, same transaction
```

So split, **reprice, and activation all share the same 10,000 ms budget**. This matters for the fix: moving
*only* the split to async still leaves reprice/activate to deal with N split lines, and they currently depend
on the split being finished first.

### OrderItem automation that fires on every clone (live, today)

No OrderItem **Apex triggers** exist. Two **active record-triggered flows** fire per OrderItem on
`CreateAndUpdate`:

| Flow | Trigger | Per-record cost | Notes |
|---|---|---|---|
| **`Fortra_OrderItem_Set_Dates`** (V6, `301WC00000knsJNYAY`) | **RecordBeforeSave** | CPU only — `$Record` field assignments, **no extra SOQL/DML** | Sets billing From/To, term EndDate/PricingTermCount backstop (SC-3297/SC-3411). Cheap per record but still an interview each. |
| **`Fortra_OrderItem_Set_Workday_Contract_Line_Type`** (V11, `301WC00000kUYVFYA4`) | **RecordAfterSave** | **1 SOQL `Get_Product`** (+1 `Get_Prepaid_Order_Attribute` for services) **+ 1 `recordUpdate` on `$Record`** | The `recordUpdate` is a **2nd DML on the same record** → re-fires the before-save Set Dates flow → **re-entrancy multiplier**. This is the dominant per-clone flow cost. |
| ~~`Fortra_Autolaunched_Set_Workday_Contract_Line_Type`~~ | — | — | **INACTIVE** (SC-3366, 2026-06-08). No longer a factor. |

---

## 3. Root cause

`PowerOrderSplittingService.processOrders` (`force-app/main/default/classes/PowerOrderSplittingService.cls`,
identical to live except a trailing newline):

- **Gate** (`queryOrderItemsToSplit`, L334-358): `Product2.Solution_Group__c = 'Power' AND Quantity > 1`.
- **Expansion** (L157-170): `for (Integer i = 1; i < qty; i++) { createFullClone(original); … }` — **one clone per
  unit**, so clone count = `Σ(qty − 1)` over Power lines.
- **`createFullClone`** (L363-380): for **every** clone it iterates the full OrderItem field map and calls
  `dfr.getDescribe()` + `isCreateable()` + `get()`/`put()` per field. The describe work is **redone per clone**
  (the field *map* is cached, but the per-field `getDescribe()`/copy loop is not hoisted). ~150-400 field-ops ×
  N clones.
- All clones insert in one `insert newItems` → the two record-triggered flows run **per clone** (bulkified
  SOQL/DML, but **per-record flow-interview CPU is not bulkified**).

**Three compounding flaws (unchanged in essence):**

1. **Per-unit cardinality** — record volume scales 1:1 with `Quantity`. Hits the **10,000-DML-row hard ceiling**
   (absolute, not tunable) and CPU long before realistic top-end quantities.
2. **Redundant per-clone automation + re-entrancy** — V11 (after-save) does SOQL + a `$Record` update that
   re-fires before-save Set Dates. The flows recompute values for every identical qty=1 clone.
3. **Synchronous execution** — split + reprice + activate all run in the user's 10,000 ms request instead of
   async (60,000 ms + chunking).

### Why CPU, not SOQL/DML, is what actually throws

The dead-transaction snapshot was **SOQL 19/100, DML statements 19/150, DML rows 480/10,000, CPU >10,000** —
i.e. SOQL/DML were bulkified fine; **CPU was exhausted by running ~N flow interviews + N deep Apex clones.**
`Maximum CPU time: 8277 / 10000 *** CLOSE TO LIMIT` was the last checkpoint before the breach. This is
consistent with Salesforce's own guidance that **flow-interview and Apex-action CPU accumulates per record even
when DML is bulkified** (see §7 sources).

> ⚠️ **Subtle but important:** split clones are **not reliably pre-stamped**. A live sample of `Is_Split_Line__c=true`
> lines shows a mix of populated and **null** `Workday_Contract_Line_Type__c` / billing dates / `PricingTermCount`.
> So a fix that merely *suppresses* the per-clone flows (without explicitly stamping the derived values in Apex)
> risks shipping split lines that fail activation/Workday. **The clones must be explicitly stamped** (copy from the
> freshly-queried, already-stamped original) — see §6 P1.

---

## 4. Scope / blast radius — the deeper finding

The split gate is `Solution_Group='Power' AND Quantity>1`. `Power` is **not** a niche tag:

- **3,406** Power `Product2` records (**2,782 active**). **3,405** are split-type `Order Line Only`
  (Hardware *shared*, Partitions *cloned*); **exactly 1** is `Order Line and Hardware`. → the hardware-cloning
  branch is effectively dead org-wide; the dominant path clones **partitions** per unit.

**Power `Quantity` in live data is a license/seat count or an unlimited sentinel — not a machine count:**

| Example product (Power) | Live qty | Rev cat | Interpretation |
|---|---|---|---|
| Cybersecurity-RenewalMaintenance | **999,999** | — | "unlimited / site" sentinel (134 lines org-wide) |
| Insite Analytics | 99,999 | RC_41000 | sentinel |
| Sequel Repository (Designer) | 9,999 | RC_41000/41202 | sentinel |
| Powertech MFA for IBM i | 9,900 | RC_41202 | **user/seat count** |
| Powertech Password Self Help for IBM i | 7,500 / 5,800 / 4,875 | RC_41202/41000 | **user/seat count** |

- **134** OrderItems at the 999,999 sentinel; **419** real Power lines at qty > 50 (excluding the sentinel);
  **3,682** Power OrderItems at qty > 1 (excluding the sentinel). High-qty Power is **pervasive, not an edge
  case.**

➡️ **Conclusion:** splitting "one OrderItem per unit" is **architecturally mismatched** with how Power
quantities are actually used. For a 7,500-user license or a 999,999 sentinel there is no per-unit physical thing
to track, and persisting that many OrderItems is impossible regardless of async/CPU. The performance fix (P1/P2)
unblocks the *modest* genuine cases; the *design* question (P3) is the real resolution and needs Joe/business
sign-off on **what Power `Quantity` means and when (if ever) per-machine splitting is correct.**

---

## 5. Reproduction & current-state notes

- **Repro quote:** `0Q0WC000003AuQb0AK` (Q-00781200) — line *Abstract* (`01tWC00000DD11GYAT`, Power /
  `Order Line Only` / Family=Subscription / Active) @ qty **456**; other lines (Accelerated MFT @ 3,425; BoKS
  maint) don't split (non-Power or qty 1).
- **Original failure log:** `07LWC00000PCXmd2AH` (19.5 MB, 88,541 lines) — `EXCEPTION_THROWN … Apex CPU time
  limit exceeded`, `FLOW_INTERVIEW_LIMIT_EXCEEDED`. (Raw log not retained on disk; excerpt in
  `*Jira/Task/sc3447/.../evidence/convert_flow_excerpt.log` covers only the pre-split checklist phase.)
- **Now:** with the deprecated flow off, the 456 repro is **borderline / may pass**. The defect persists at
  higher qty and is **guaranteed** to fail on the thousands-qty and 999,999-sentinel Power lines. **Re-test to
  establish the current threshold** before claiming severity changed.

---

## 6. Fix roadmap (concrete, layered)

> All UAT deploy / DML requires fresh explicit authorization ([[feedback_uat_deploy_authorization]]); prod is
> separately gated, and the Workday line-type flow family is prod-promotion-sensitive (coordinate SC-3366 /
> line-type owners). Nothing below is implemented yet.

### P0 — Triage / unblock (hours, no design change)
- Confirm the deprecated Autolaunched flow stays inactive (verified today).
- **Re-run the repro** to find the current empirical clone ceiling.
- For any *business-urgent* blocked order: first decide whether the offending Power line *should* split at all
  (most thousands-qty / sentinel lines should not — see §4). Do **not** "fix" by raising CPU; fix the data/scope.

### P1 — Kill the redundant per-clone cost (biggest safe win, no behavior change) — 1–2 days
1. **Stamp derived fields on clones in Apex** inside `createFullClone`/`processOrders`: explicitly carry
   `Workday_Contract_Line_Type__c`, `Billing_Schedule_From/To_Date__c`, `Start/End_Date_Calculated__c`,
   `EndDate`, `PricingTermCount` from the freshly-queried (already-stamped) original onto each clone. (qty=1
   clones of the same product/date are value-identical to the parent — no recomputation needed.)
2. **Guard both record-triggered flows to skip split clones** — add an entry condition
   `Is_Split_Line__c = false` (or `{!$Record.Is_Split_Line__c} = false`) to `Fortra_OrderItem_Set_Dates` and
   `Fortra_OrderItem_Set_Workday_Contract_Line_Type` so they don't re-run per clone. Removes ≈2N interviews +
   V11's re-entrant re-fire from the sync path. **Must be paired with #1** so suppressed clones still carry
   correct values (see §3 warning).
3. **Hoist the describe work** in `createFullClone`: compute the list of `isCreateable()` field names **once**
   (static, like the field map), then the per-clone loop is a plain `get`/`put` over that list — removes ~N×150
   `getDescribe()` calls.
- *Expected:* clears the synchronous CPU pressure for the modest genuine cases (dozens–low-hundreds of real
  machines) and lifts the ceiling several-fold. Does **not** solve the 10k-DML-row wall for thousands-qty lines.

### P2 — Make the split scale: async + chunk + hard cap — 3–5 days
- **Move splitting off the synchronous convert** into a `Queueable`/`Batchable` (60,000 ms CPU; chunked DML so
  no transaction nears CPU/DML limits; chain queueables). Convert returns; Order shows "line splitting in
  progress".
- **Re-sequence reprice/activate** to run *after* async split completes (they currently follow split inline and
  assume it's done) — e.g. finalize via the queueable chain or a platform-event/async-apex continuation.
- **Hard cap** the synchronous (and even async) split count with a **catchable validation message** instead of a
  raw governor fault to the UI.
- Surface async status/errors on the Order (status field + platform event), replacing today's silent rollback.

### P3 — Design correctness (the real resolution; business-gated) — owner decision required
- **Decide what Power `Quantity` means** (per §4 it is usually seats/users or an unlimited sentinel, not
  machines). Re-scope splitting to only the cases where per-machine/partition tracking is genuinely required,
  driven by **actual Hardware/Partition data**, not raw license quantity.
- For everything else, **represent the count on a single OrderItem** (+ optional aggregated Hardware/Partition
  children) — persisting thousands–millions of OrderItems is infeasible regardless of async (10k-DML-row hard
  ceiling).
- Add a **before-save validation** blocking per-unit Power splits above the agreed cap.

### P4 — Tests + E2E + rollout
- **Apex tests** for `PowerOrderSplittingService`: qty boundaries (1, 2, ~50, cap, cap+1), bulk multi-order,
  both split types, the new Apex stamping (assert clones carry line-type/dates/PTC **without** the flows),
  rollback-on-error, and the `ValidationResult` restore (Phase 8).
- **E2E convert matrix:**
  - small Power (≤10) — splits, all clones fully stamped, converts;
  - medium Power (~100) — within limits;
  - the repro (Abstract 456) — converts;
  - **negative test:** non-Power high-qty (e.g. Endpoint DLP @ 750k) — converts and **does not** split;
  - **guardrail test:** a thousands-qty / 999,999-sentinel Power line — blocked with a clear message (not a
    governor fault).
- Deploy UAT → validate → prod via the standard gated process; coordinate Workday line-type owners.

---

## 7. Governor facts & sources (web-grounded)

- Synchronous Apex CPU limit is **10,000 ms** (UI / web-service / executeAnonymous); async is 60,000 ms. CPU
  time includes **all Apex + declarative automation (flows, triggers)** executed in the transaction.
- **Flow interviews started during bulk Apex DML accrue CPU per record even when their SOQL/DML are bulkified**;
  repeatedly invoking an Apex action / sub-automation per record is a classic CPU-timeout cause — the remedy is
  to make the work bulk-safe and to avoid per-record re-invocation.
- The **10,000 DML-rows-per-transaction** limit is a hard ceiling and is the real wall for genuinely large
  counts (async raises CPU, not DML rows).

Sources:
- [Troubleshoot Apex CPU Time Limit Exceeded Errors — Salesforce Help](https://help.salesforce.com/s/articleView?id=005132111&language=en_US&type=1)
- [Apex CPU Time Limit Exceeded: 5 Causes and How to Fix It — Traction Complete](https://tractioncomplete.com/articles/apex-cpu-time-limit-exceeded-errors-salesforce/)
- [Bulkification in Flows — Beyond The Cloud](https://blog.beyondthecloud.dev/blog/bulkification-in-flows)
- [General Flow Limits — Salesforce Help](https://help.salesforce.com/s/articleView?language=en_US&id=flow_considerations_limit.htm&type=0)

---

## 8. Open questions for Joe Romo / design owners

1. **What does Power `Quantity` represent** — physical machines/LPARs, or user/seat licenses? (Live data points
   strongly to seats/sentinels.)
2. **When is per-machine OrderItem splitting actually required?** Is it ever needed above a few dozen lines?
3. Are the **999,999 / 99,999 / 9,999 sentinels** intended "unlimited/site" markers? If so, splitting them is
   never valid and must be excluded by rule.
4. Acceptable **convert UX** if split goes async (order exists before lines finalize; Workday/activation must
   wait for completion)?

---

## 9. Files

| Path | Contents |
|---|---|
| `Data/sc3447/00_DEEP_RESEARCH_REPORT.md` | this report |
| `Data/sc3447/live_retrieve/` | live FortraUAT retrieve (Apex + 4 flows, 2026-06-26) |
| `*Jira/Task/sc3447 | …/` | original 2026-06-18 dossier (README, 01_EVIDENCE, 02_ROADMAP, JIRA_DESCRIPTION) |

**Related:** [[project_sc3366_soql_governor_rca]] (deactivated the deprecated subflow), [[project_sc3210_workday_linetype]]
& [[project_sc3368_linetype_v9_regression]] (the Workday line-type flow family), [[project_decomp_split_resolution]]
(`Original_Order_Item__c` is the qty-split FK this service sets), [[feedback_org_data_src_can_be_stale]],
[[feedback_uat_deploy_authorization]].
