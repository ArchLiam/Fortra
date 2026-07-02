# SC-3366 — Order completion exceeds SOQL governor limit (`Too many SOQL queries: 101`) on large orders

> ✅ **RESOLVED in FortraUAT (2026-06-08).** Implemented in 3 phases: **P1** removed the duplicate `Fortra_Autolaunched_Set_Workday_Contract_Line_Type` subflow (deactivated; −flow fan-out + V8 re-fire); **P2** built `OrderSubmissionValidator` (bulk Apex, **97% coverage**, 6/6 tests) replacing the per-field `FieldPopulatedCheck` nested loop; **P3** rewired `Fortra_Order_Submission_Check` (v13, active) to call it. **Validation cost went from `20 + 5×N` (e.g. ~4,210 SOQL on an 838-line order) to a flat ~4 SOQL.** Verified on **9 orders, 109→847 lines** — all complete without `Too many SOQL queries`; **00082734 (671) and 00088127 (847) reached *Order Complete* and transmitted to Workday.** `FieldPopulatedCheck` retained (per request) but no longer called. The downstream **Workday sync failures** (contact communication `Type_Reference`, address data) are a **separate data-quality issue → new ticket** (scoped out of SC-3366, which was the governor limit only).
>
> Space: Salesforce-Coastal (SC) · Type: Bug (RCA) · Priority: **Critical** · Sprint: CRM Sprint 14 · [SC-3366](https://helpsystems.atlassian.net/browse/SC-3366)
>
> 🔬 **Deep RCA complete (FortraUAT, 2026-06-08)** — multi-agent investigation that re-derived the full 101-query
> SOQL budget from the live fault log, audited every flow, and **verified the fix-driving claims against the
> live FortraUAT org**. This RCA **corrects the original framing**: `FieldPopulatedCheck` is the *victim*, not
> the driver — the dominant contributor is a **duplicate, stale line-type subflow**. See §8 for the corrections.

| | |
|---|---|
| **Type** | Bug (RCA) |
| **Status** | In Progress |
| **Priority** | Critical |
| **Component** | Order Submission / Workday Integration (RCA) |
| **Environment** | FortraUAT (UAT-only stack — absent from prod) |
| **Found during** | SC-3347 line-type smoke testing (2026-06-07) |
| **Related** | SC-3143 (Workday epic) · SC-3291 (`FieldPopulatedCheck` / order-submit validation) · SC-3347 (line-type fix V8) |
| **Scope** | Pre-existing scaling defect; integration/platform. **NOT** caused by the SC-3347 line-type fix |
| **Evidence** | `Data/sc3347/fault_log.txt` (order 00069311, 17 lines, 101/100 SOQL) · live-org checks `Data/sc3366_verify/` |

---

## 1. Summary

Completing (**Update Status → Order Complete**) an order with **many lines** fails with a generic Flow error:

> **"An unhandled fault has occurred in this flow."**

The underlying exception is a Salesforce governor limit:

> **`System.LimitException: Too many SOQL queries: 101`**

It reproduces **only on large orders** (~15+ lines); small orders complete normally. This is a **pre-existing
scaling defect** in the order-completion transaction (the screen flow `Fortra_Order_Submission_Check`), surfaced
while testing the SC-3347 line-type fix on big orders. **It is not caused by the line-type fix** — the SC-3347
record-triggered flow is correct and must be *retained*; the defect lives in a **separate, redundant** flow path.

## 2. Reproduction

| Order | Lines | Result |
|---|---|---|
| 00069311 | 17 | ❌ `Too many SOQL queries: 101` (logs `07LWC00000OhKyX2AV`, `07LWC00000OhKwv2AF`; test order since cleaned up) |
| 00095325 | 18 | ❌ large order |
| 00014777 | 11 | ❌ large order |
| 00095354 / 00095363 | 1–3 | ✅ completes fine |

Threshold is **~15+ lines** (exact count varies with referenced contacts/accounts and how many lines carry a
subsplit). **Evidence:** `Data/sc3347/fault_log.txt` (10,403 lines) — log tail ends with
`Number of SOQL queries: 101 out of 100`; the throwing query is the `FieldPopulatedCheck` `SELECT` at line `[133]`.

## 3. Empirical SOQL budget (verified — the headline)

The fault log was re-derived **query-by-query** using the authoritative `LIMIT_USAGE|...|SOQL|N|100` markers
(N = 1…101), **not** `SOQL_ROWS` (a misleading cumulative-rows counter). The 101 queries reconcile **exactly**:

| Source | SOQL | % | Note |
|---|---:|---:|---|
| **Duplicate Autolaunched line-type subflow** `Fortra_Autolaunched_Set_Workday_Contract_Line_Type` | **~40** | ~40% | 17 `Get_Product` + ~6 `Get_Order_Attributes` + ~17 implicit filtered-`recordUpdate` queries. **Pure waste** — see §4.1 |
| **V8 record-triggered line-type flow** `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (SC-3347 — **KEEP**) | **~40** | ~40% | 17 `Get_Product` + 11 `Get_Subsplit_Child_Lines` + 6 `Get_Order_Attributes` + 6 `Get_Prepaid_Order_Attribute` |
| **`FieldPopulatedCheck`** Apex (SOQL-in-loop) | **19** | ~19% | Contact 10 (5 fields × Bill-To + Ship-To), Order 5, Account 4. **The victim that throws #101** |
| Outer screen flow `Fortra_Order_Submission_Check` fixed lookups | **~2** | ~2% | `Get_Order_Submit_Validation` + `Get_OrderItem_s` (+ `Get_Order`) — fixed cost, do **not** scale |
| **Total** | **101** | | failure at the 101st query |

**Cross-checks:** 51 `FLOW_CREATE_INTERVIEW_BEGIN` = 3 OrderItem flows × 17 lines; explicit `FlowRecordLookup`
BEGIN counts = `Get_Product` **34** (= 17 V8 + 17 Autolaunched), `Get_Order_Attributes` 12, `Get_Subsplit_Child_Lines`
11, `Get_Prepaid_Order_Attribute` 6, + 2 outer = **65 explicit**; `82 flow SOQL − 65 explicit = 17` implicit
filtered-`recordUpdate` queries. `ENTERING_MANAGED_PKG = 0` (no RLM/pricing/Vlocity), **0 Apex triggers**, the
**only** Apex issuing SOQL is `FieldPopulatedCheck`. Max DML = 51/150 (not the limiting governor).

> ⚠️ **Order matters:** the SOQL counter was already at **82–83** when the *first* `FieldPopulatedCheck` query
> ran. The per-line flow fan-out consumed the budget; `FieldPopulatedCheck` merely tipped it over the edge.

## 4. Root cause (ranked by SOQL cost)

### 4.1 Duplicate, **stale** Autolaunched line-type subflow ⭐ primary — ~40/101
`Fortra_Order_Submission_Check` invokes `Fortra_Autolaunched_Set_Workday_Contract_Line_Type` **once** as a
subflow ([`Fortra_Order_Submission_Check.flow-meta.xml`](../../../force-app/main/default/flows/Fortra_Order_Submission_Check.flow-meta.xml), node `Fortra_Autolaunched_Set_Workday_Contract_Line_Type_Flow_1`, lines ~1137-1152), passing it the
whole `Get_OrderItem_s` collection. Internally it **loops all 17 lines** (`Loop_Order_Items`), issuing
`Get_Product` + `Get_Order_Attributes` + a filtered `recordUpdate` **per iteration** — a classic SOQL-in-loop.

This work is **discarded**: the record-triggered SC-3347 **V8** flow (`RecordAfterSave` on OrderItem) already
stamped `Workday_Contract_Line_Type__c` correctly *upstream of completion* and overwrites it. The Autolaunched
flow carries **pre-SC-3347 logic** (no subsplit-parent detection) and writes **only** that one field with no
outputs consumed by the parent. It is **net-zero behavior, ~40 wasted queries**, and a latent regression risk.

### 4.2 V8 record-triggered line-type flow — correct & required, but not bulkified — ~40/101
`Fortra_OrderItem_Set_Workday_Contract_Line_Type` (SC-3347 V8) is the **authoritative fix** and **must be kept**.
But as a record-triggered flow it fires once per OrderItem and each `Get Records` keys off `$Record`, so it issues
~2.3 SOQL/line that **does not collapse across the save batch**. This is the residual that re-approaches 100 on
*very* large orders (see §6) — it cannot be deleted, only structurally bulkified (fix P3).

### 4.3 `FieldPopulatedCheck` SOQL-in-loop — the victim — 19/101
[`FieldPopulatedCheck.cls`](../../../force-app/main/default/classes/FieldPopulatedCheck.cls): request loop opens at
**line 81**, the dynamic query is built per-iteration at **lines 128-131** and executed inside the loop at
**line 133** (`Database.query(query)`) — 1 query per request, **not bulk-safe**. It is **amplified** by the flow,
which calls it **once per field** with 1-element request lists from inside loops — the non-OrderItem call sits in
loop `Check_Non_OrderItem_s`; the OrderItem call sits in a **nested** loop `Check_Order_s_Order_Products` ×
`Check_OrderItem_s`, so the OrderItem term scales as **(#lines × #OrderItem-rules)**. In this log it spent 19
queries (and never reached the ~6 OrderItem-side checks — the limit blew at field #19, so the *full* config is ~25).

## 5. Recommended fixes

| # | Fix | SOQL saved | Risk | Confirmed safe? |
|---|---|---|---|---|
| **P0** | **Remove the duplicate Autolaunched subflow call** from `Fortra_Order_Submission_Check` (delete the `<subflows>` node `…_Flow_1` ~lines 1137-1152 and repoint the `Get_OrderItem_s` connector ~line 963 from `…_Flow_1` to `Non_OrderItems`). Optionally also deactivate the Autolaunched flow itself. | **~40** (scales w/ lines) | **Low** | ✅ **CONFIRMED vs live FortraUAT** |
| **P1** | **Eliminate `FieldPopulatedCheck` SOQL.** Move the 11 Order/OrderItem checks to native flow `IsBlank`/`IsNull` on the already-loaded `Get_Order`/`Get_OrderItem_s`. For the 14 related-record checks (4 Account + 10 Contact), add **cross-object spanning formula fields** to `Get_Order` so they ride the parent query at zero extra SOQL. | **~19** (up to ~25) | Med–High | ⚠️ Partial — see caveat |
| **P2** | *Alt to P1:* **Bulkify `FieldPopulatedCheck.cls`** — group requests by object, one `SELECT … WHERE Id IN :ids` per object — **and** rewrite the flow to batch its calls (the two Contact relationships collapse to one query → ~3-4 total). | ~19→~3-4 | Medium | ⚠️ Partial — **0 saved standalone** |
| **P3** | **Structural cap:** bulkify per-line work so completion updates all OrderItems in **one DML** and the V8 lookups operate on the trigger batch (or move line-type derivation into one bulkified, tested Apex / before-save redesign). | Caps SOQL at a constant | High | ❌ Not yet verified (design-level) |

**P0 is the fix to ship first** — cheapest, highest yield, confirmed safe. It resolves the reported repro by itself.

**Caveats that change the work:**
- **P1 is not the trivial "`$Record`" fix the original draft implied.** `Fortra_Order_Submission_Check` is a
  **screen flow** — there is **no `$Record`**. It holds only `Get_Order` (the Order) + `Get_OrderItem_s` — **not**
  Account or Contact records, only their FK Ids. So 14 of 25 checks are on **related** records and need spanning
  formula fields (a real build) to be free; only the 11 Order/OrderItem checks are genuinely in-memory.
- **P2 saves ~0 standalone** — the flow sends N single-element invocations, so per-call bulkification still yields
  N queries unless the flow is *also* rewritten to batch requests.
- **P0/P1/P2 are mutually compatible.** With P0 alone the order completes; P1 is for headroom on larger orders and
  the full ~25-check config (only 19 of ~25 ran before the limit blew).

## 6. Residual after fixes & line-count ceiling

| Scenario | SOQL on a 17-line order | Under 100? |
|---|---:|---|
| Today | 101 | ❌ |
| **P0** (remove Autolaunched, −40) | **~61** | ✅ — resolves the repro |
| **P0 + P1** (also remove `FieldPopulatedCheck`, −19) | **~42** (~58 headroom) | ✅ |

**Not unbounded.** The ~42 residual is dominated by the V8 record-triggered flow at ~2.3 SOQL/line, scaling
linearly: ~40 at 17 lines, **~94 around 40 lines**, re-approaching 100 at **~42+ lines**. "Comfortably under 100"
holds for the reported 17-18 line repros (and up to ~35-38 lines), but the **durable cap for arbitrarily large
orders requires P3** (single-DML bulkification of the V8 lookups).

## 7. Acceptance criteria

- [ ] A 17-18 line order (e.g. 00069311, 00095325 class) completes to **Order Complete** without `Too many SOQL
      queries: 101`; debug-log `LIMIT_USAGE` markers confirm total SOQL < 100 (expect ~61 with P0, ~42 with P0+P1).
- [ ] **No regression to SC-3347 line-type values** after Autolaunched removal: Subsplit Parent → `FIXED AMOUNT
      BILLING ONLY`, children → `FIXED AMOUNT`, plain Perpetual/Maintenance → `FIXED AMOUNT`, Services → `USAGE
      BASED`, Prepaid → `PREPAID`. Validate on a fresh post-V8 subsplit-parent order (00014777 pattern).
- [ ] Order-completion path still works end-to-end: `Get_OrderItem_s` → `Non_OrderItems`, validation runs,
      `Set_Order_Status_Order_Complete` fires with `Workday_Sync_Status__c = Pending`, Workday platform-event flow fires.
- [ ] Test on a deliberately **large order (≥40 lines)** to confirm residual stays < 100 **or** document that P3
      is required; establish the empirical line-count ceiling.
- [ ] If `FieldPopulatedCheck` is modified/its flow calls changed (P1/P2): a `FieldPopulatedCheckTest` class
      reaches **≥75% coverage BEFORE any prod promotion** (currently **0%**, no test class exists — a hard blocker).
- [ ] The full ~25-check config completes (the 5 OrderItem checks + `Order.Workday_Contract_ID__c` that never ran
      at field #19 now execute without breaching the limit).

## 8. Corrections to the original hypothesis

1. **`FieldPopulatedCheck` is NOT the dominant contributor.** It is 19/101 (~19%) and is the *victim* that throws
   the 101st query — the counter was already at 82-83 before its first query ran. 82/101 (~81%) are flow queries.
2. **The single largest contributor is the DUPLICATE Autolaunched line-type subflow (~40/101, ~40%)** — originally
   treated as a stray/minor duplicate; it is the highest-value fix.
3. **The earlier per-source split was wrong.** `Get_Product` = **34 total = 17 (V8) + 17 (Autolaunched)**; the
   outer screen flow has **ZERO** `Get_Product` (it has only 3 lookups: `Get_Order`, `Get_Order_Submit_Validation`,
   `Get_OrderItem_s`). The "28 outer + 17 subflow = 45" attribution is refuted.
4. **A whole contributor was missed:** ~17 **implicit filtered-`recordUpdate`** queries inside the Autolaunched
   loop (`82 flow − 65 explicit lookups = 17`).
5. **"Check populated-ness in-memory from `$Record` (zero SOQL)" is refuted as written** — it's a screen flow with
   no `$Record`, and 14 of 25 checks are on related records the flow doesn't hold (need spanning formula fields).
6. **"Bulkify `FieldPopulatedCheck`" standalone saves ~0** — the flow sends N single-element invocations.
7. The two `FieldPopulatedCheck` actionCalls are **2 distinct elements, not 4** (the `4×` grep counted 2 lines each).
8. **The `force-app` copy of the Autolaunched flow is STALE** — `force-app` shows its fixed-amount branch writing
   `FIXED AMOUNT`, but the **live active UAT version writes `FIXED AMOUNT BILLING ONLY`**. Any fix built off
   `force-app` reasons from the wrong artifact — **re-retrieve before editing**.
9. **No managed-package / RLM / pricing / rollup / trigger SOQL** in this transaction — it's a record-triggered
   *save* context (Order Status → Order Complete), not a reprice. The worry about managed-package contributors
   does not apply to this log.

## 9. Open questions & deploy guards

- **Verify V8 is ACTIVE in the target org at deploy time** with no entry filter added. V8 was confirmed active in
  FortraUAT (def `3ddWC00000QqP3OYAV`, version #8, created 2026-06-08T01:39, `RecordAfterSave`, no entry filters)
  and proven correct on order **00014777** (parent → `FIXED AMOUNT BILLING ONLY`, 9 children → `FIXED AMOUNT`) —
  but **V8 is absent from `force-app`** (lives only in `Data/sc3347/flow_v5/` and `*Jira/sc3211/retrieve/`), so it
  must be re-checked live before deleting the Autolaunched call, else the line type stops being stamped here.
- **Confirm no other caller** invokes the Autolaunched flow before fully deactivating it (the verdict checked the
  submission-flow path only).
- **Determine the precise large-order ceiling** (~42 lines est.) where the post-P0+P1 residual crosses 100, to
  decide whether P3 is mandatory for the customer's real order sizes.
- **Validate Boolean-false semantics if moving checks in-memory (P1)** — `FieldPopulatedCheck` treats `false` as
  *populated*; native flow `IsBlank` may differ. Needs per-field-type parity checks.
- **Confirm in a live Apex log** that after-save V8 `Get Records` truly run once-per-record-per-interview (not
  batched) before committing to P3 scope.

## 10. Notes

- **UAT-only stack.** `FieldPopulatedCheck`, `Order_Submit_Validation__mdt`, and `Fortra_Order_Submission_Check`
  exist only in UAT (absent from prod, per SC-3291). `FieldPopulatedCheck` has **0% coverage**. Per project memory,
  **do not deploy this stack to prod without fresh explicit authorization** — and any UAT change here needs its own ack.
- **Independent of SC-3347** — the line-type fix (V8) is verified working and must be *retained*; this RCA only
  removes a redundant *duplicate* of it.
- The large subsplit orders in §2 also carry *separate* Workday errors (`Standalone_Selling_Price` subelement,
  Company mismatch) — **out of scope** here.
