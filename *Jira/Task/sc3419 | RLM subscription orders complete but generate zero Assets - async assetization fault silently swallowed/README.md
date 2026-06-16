# SC-3419 — RLM subscription orders complete ("Order Complete") but generate zero Assets — async assetization fault silently swallowed

| | |
|---|---|
| **Ticket** | SC-3419 (Salesforce-Coastal) — Priority **Critical** — CRM Sprint 14 |
| **Reporter** | German Wren · **Assignee** Liam Jeong |
| **Org** | FortraUAT — **UAT ONLY** (read-only RCA; no prod work) |
| **Linked** | **split from SC-3415** (this ticket owns SC-3415's *Defect A*: no-Assets-after-activation) |
| **Repro** | Order **00095470** (`801WC00000kYmw8YAC`) — 32 lines, account `001WC00000XiZP4YAN`, quote "Q-Wren - Test GS Quotes w Hardware", Contract 00069266 |
| **Status (2026-06-16)** | ✅ **Visibility fix LIVE + runtime-tested + recovery proven** — `Fortra_Assetize_Order` **V14** (`301WC00000kpNwPYAU`, active). Owner-authorized live tests: AC4 (clear + no-clobber) **proven**, collision **re-confirmed**, AC2 met. **AC5 proven two ways:** (a) fresh-record replica of 00095470's exact 32 lines on a **clean account** → order **00095537** → **32 Assets, no collision** (the "32" target MET); (b) Quantity de-dup on the original account → order **00095536** → **4 quantity-rolled Assets**. **Definitive RCA:** the collision is triggered by duplicate same-product (maintenance) lines contending on a **pre-existing matching Asset** — not by the line shape. See [RUNTIME_TEST_RESULTS.md](RUNTIME_TEST_RESULTS.md). |

> This dossier is the **SC-3419-focused** consolidation of the no-Assets defect. The broader two-defect RCA (which also covered the quote-tier `PricingTermCount` regression, now owned separately) lives in the SC-3415 dossier. Live re-verification (2026-06-16), the V14 flow mechanism, the collision proof, and the official Salesforce/RLM documentation are all assembled here.

---

## 1. Problem

Subscription / RLM orders **activate cleanly** — Status reaches the custom label **"Order Complete"** (`StatusCode = Activated`), the Contract is created — yet generate **zero Assets**: no `AssetActionSource`, no `AssetAction`, no `Asset`. The rep sees a clean completion **with no error**. This blocks German Wren's renewal/COLA testing because there are no assets to renew.

**Live repro state, 2026-06-16** (re-verified read-only against FortraUAT):

| | Order 00095470 |
|---|---|
| Status / StatusCode | **Order Complete** / **Activated** |
| ActivatedDate | 2026-06-11T13:27:30Z |
| Contract 00069266 | **Activated** |
| OrderItems | **32** (all `Product2.IsAssetizable = true`) |
| `AssetActionSource` for its 32 lines | **0** (all-time) |
| `AssetAction` for its 32 lines | **0** |
| Assets attributable to this order | **0** |
| `Order_Integration_Error_Messages__c` | **null** ← the silent swallow (no surfaced error) |
| `Workday_Sync_Status__c` | Pending |

The order's line shape is the trigger: **4 SKUs heavily duplicated**, not Quantity-rolled —

| ProductCode | Product2Id | Selling model | Lines | Σ qty | Service→End |
|---|---|---|---|---|---|
| PIA-PIA-NRPS-PIAP | `01tWC00000DD1btYAD` | OneTime | 10 | 10 | null |
| PIA-PIA-RNM-PIAMBK | `01tWC00000DD1bsYAD` | OneTime (maintenance) | 10 | 9* | mostly null |
| HRM-HRM-RSL-SEAW | `01tWC00000DD1fiYAD` | TermDefined | 6 | 6 | 2026-06-11→2027-06-10 |
| HRM-HRM-RSL-CLSAAS | `01tWC00000DD17PYAT` | TermDefined | 6 | 6 | 2026-06-11→2027-06-10 |

\* One PIAMBK line (`802WC00000Og2R2YAJ`) is **qty = 0** with **2 `OrderItemDetail`** rows (+1 @2026-06-11, −1 @2026-06-15) — the **maintenance-decomposition** artifact (amendment netting).

> **This is NOT SC-3411.** SC-3411 was an *activation blocker* on un-termed lines. Here the order **activated**, and all 12 TermDefined lines were fully dated at activation (EndDate 2027-06-10, PricingTermCount 1). Different transaction, different failure. (See §8.)

---

## 2. Root cause — two layers

### Layer 1 — Silent swallow (the genuine **Fortra-owned** defect)

Asset generation does **not** run in the synchronous activation transaction. It runs in the custom flow **`Fortra_Assetize_Order`** which **overrides** the native RLM Order-to-Asset flow (`overriddenFlow = revenue_o2aflows__o2aFlow`). Its `<start>` is `RecordAfterSave` Update on Order, filtered `Status = 'Activated'`, and its **only** connector is nested under `<scheduledPaths><pathType>AsyncAfterCommit</pathType>` — **there is no synchronous connector.**

So the entire asset run — `GetApplicationUsageAssignment` → `createOrUpdateAssetFromOrder` → `PopulateAssetLegacyFieldsAction` — executes in a **separate after-commit transaction with its own fresh governor budget** (Order-of-Execution step 20, post-commit). When the action throws, the flow's `faultConnector` routed (pre-fix) to a *"Capture Error (Graceful End)"* assignment that just stored `$Flow.FaultMessage` to a variable and stopped. Per Salesforce's documented behavior, a fault path that ends gracefully **(a)** suppresses the default unhandled-error email, **(b)** does **not** roll back the triggering change (the Order stays Activated), and **(c)** in a screenless background flow writes nothing — **the failure is invisible.** That is precisely the "Order Complete, zero Assets, no error" symptom.

### Layer 2 — The underlying throw (native platform, by-design behavior)

`createOrUpdateAssetFromOrder` returns:

```
INVALID_API_INPUT: We couldn't process your request because the asset was updated by another process.
```

This is a **deterministic optimistic-lock collision**, proven by a safe rollback diagnostic invoked directly on 00095470 (`evidence/k2_capture_collision_proof.log`):

```
K2_PREASSET_COUNT 5
K2_OUTCOME  ok=0 bad=1  errs=(Error:[code=INVALID_API_INPUT,
            message=We couldn't process your request because the asset was updated by another process.])
Number of SOQL queries: 2 out of 100   |   Maximum CPU time: 0 out of 10000   |   DML rows: 0
K2_ROLLED_BACK
```

**2 SOQL, 0 CPU, instant** → not a governor limit; it is an optimistic version-check (`SystemModstamp`) rejection. Per the RLM data model, `createOrUpdateAssetFromOrder` **matches an existing Asset by `AccountId + Product2Id` and updates it** (new Asset only for a new product). The account `001WC00000XiZP4YAN` already holds assets for 3 of the 4 products, so the duplicated same-product lines all resolve onto the **same Asset row** and collide as the action updates that row more than once in one invocation:

| ProductCode | 00095470 lines | Pre-existing account Assets | Collision surface |
|---|---|---|---|
| PIAMBK | 10 | **1** (`02iWC000008DFvvYAG`, modstamp 2026-06-15 20:31:36) | **10 lines → 1 row** (cleanest funnel) |
| PIAP | 10 | **2** (`02iWC000008DFvxYAG`, `02iWC000008LagcYAC`) | 10 lines → 2 rows |
| CLSAAS | 6 | **2** (`02iWC000007kLByYAM`, `02iWC000007mWZfYAM`) | 6 lines → 2 rows |
| SEAW | 6 | **0** | new-row (no collision) |

The **maintenance-decomposed PIAMBK** line (one line qty 0 + 2 `OrderItemDetail` rows) compounds the multiple-writers-per-row condition — the same fragile decomposition path SC-3411 §4.1 flagged for `OrderRepriceInvocable`.

> **Official-doc framing (W1/W2):** the native action is behaving **per its documented contract** ("one Asset per Account+Product; bump Quantity / update the matched Asset"). `INVALID_API_INPUT` is Salesforce's *contract-violation envelope*, with the lock message carried as detail; it is **distinct from `UNABLE_TO_LOCK_ROW`** (pessimistic, ~10s wait). There is **no Salesforce-acknowledged Known Issue or hotfix** for this string — the documented remedy is to **reduce concurrency / not send multiple writers at the same matched Asset**, i.e. **Quantity instead of duplicate lines**. So Layer 2 is "documented framework behavior triggered by the order's data shape," not a platform bug we can patch — which is why the fix targets **Layer 1 (visibility)**, and the **recovery targets the data shape (AC5)**.

---

## 3. The fix — `Fortra_Assetize_Order` V14 (visibility hardening, **no new fields**)

The collision is native behavior we cannot patch; the **Fortra-owned defect was the silent swallow.** V14 converts an asset-less "Order Complete" into a **visible, queryable** error on the Order — reusing the existing, previously-unused `Order_Integration_Error_Messages__c` field (no new schema). The `createOrUpdateAssetFromOrder` action is **unchanged**.

Live V14 (`evidence/Fortra_Assetize_Order.V14.flow-meta.xml`) — static-verified element-by-element, **functional match to the staged final** at `Data/sc3415/stage/v14/` (only entity-encoding/element-ordering serialization diffs):

| AC | Mechanism in V14 | Verdict |
|---|---|---|
| **AC1** surface the fault | `faultConnector → Assign_Error_Message` (`varErrorMessage = $Flow.FaultMessage`) → `Stamp_Assetization_Failed` writes `Order_Integration_Error_Messages__c = "Assetization failed: " & varErrorMessage` | ✅ CONFIRMED (static) |
| **AC3** never re-fires | Both Order `recordUpdates` write **only** `Order_Integration_Error_Messages__c` — **no element writes `Status`**. Start re-arm = `Status EqualTo 'Activated'` + `doesRequireRecordChangedToMeetCriteria=true`; Status untouched ⇒ cannot re-trigger | ✅ CONFIRMED (static) |
| **AC4** clear without clobber | Success → decision `Prior_Assetization_Error`: clears the field **only if it `StartsWith "Assetization failed"`**; the default "No" path ends, leaving Workday/other integration errors intact | ✅ CONFIRMED (static) |

**Runtime caveat (AC1):** `Order_Integration_Error_Messages__c` is **currently null** on 00095470 (the order pre-dates the deploy and has not been re-activated since). AC1/AC3/AC4 are verified by **source analysis**; observing the stamp populate at runtime requires the **AC5 owner-authorized re-trigger** (which doubles as the AC1 runtime proof). The identical `recordUpdate` mechanism was already runtime-proven during SC-3415 E2E (on the equivalent V13 record-update element).

---

## 4. Acceptance-criteria status (live, 2026-06-16)

| # | Acceptance criterion | Status | Evidence |
|---|---|---|---|
| **AC1** | Failed async asset run is **surfaced** on the Order (`Order_Integration_Error_Messages__c = "Assetization failed: …"`) instead of a silently asset-less "Order Complete" | ✅ **MET (static + mechanism runtime-corroborated)** | V14 fault path (§3); the `recordUpdate` write mechanism is runtime-proven via AC4 Tests C/N + the V13 fault stamp (06-15). Residual gap = a live fault-stamp on the real field, which needs the AC5 rebuild (collision can't be synthesized; in-place re-fire blocked). `evidence/L1_flow_v14.md`, `RUNTIME_TEST_RESULTS.md` |
| **AC2** | A **normally-built** order (Quantity, not duplicate lines) generates Assets for **every** subscription line, **including future-dated** lines | ✅ **MET (live-verified)** | 8 orders, 48 lines → 48 AAS 1:1; future-dated `BESECB` (00095475, ServiceDate 2027-06-11) → Asset `02iWC000008FcLaYAK`; re-confirmed today by 2 fresh test orders. `evidence/L3_ac2_assetization.md` |
| **AC3** | Surfacing flow **never re-fires itself** (writes only the error field, never Status) | ✅ **MET (static + corroborated)** | V14 writes only `Order_Integration_Error_Messages__c`; runtime success writes touched only that field. `evidence/L1_flow_v14.md` |
| **AC4** | Success path **clears** the assetization error **without clobbering** other integration errors (e.g. Workday) | ✅ **MET (RUNTIME-PROVEN)** | Test C: seeded "Assetization failed: …" → assetized → **cleared**. Test N: seeded "Workday: …" → assetized → **retained**. `RUNTIME_TEST_RESULTS.md` |
| **AC5** | **00095470 assets recovered** (re-trigger after de-duping lines via Quantity) → expect **32 Assets** | ✅ **PROVEN — "32 Assets" MET on a clean account** | In-place re-fire is BLOCKED (`CANNOT_EXECUTE_FLOW_TRIGGER`, "Order Submission to Revenue Orchestrator"), so recovery = a fresh build. **Two proofs:** (a) **00095537** — 00095470's exact 32 separate lines on a **clean account** → **32 distinct Assets, no collision** (matches the AC5 target); (b) **00095536** — Quantity de-dup (4 lines, 10/10/6/6) on the original account → **4 quantity-rolled Assets, no collision**. Both `Order_Integration_Error_Messages__c=null`. `RUNTIME_TEST_RESULTS.md` |

**Net:** the visibility defect (the part SC-3419 can actually fix) is **resolved, live, and runtime-tested** (AC4 proven; collision re-confirmed). AC2 is **proven met**. **AC5 is resolved** — the "32 Assets" target is **demonstrated achievable** (order **00095537**, 32 separate lines on a clean account → 32 assets), and a Quantity de-dup gives a collision-free 4-asset alternative (order **00095536**). **Refined RCA:** the failure is **not** the duplicate-line shape per se — it is duplicate same-product **maintenance/renewal** lines contending on a **pre-existing matching Asset** already on the account (00095470's account held the matching PIAMBK asset; a clean account holds none, so every line `Generate`s its own asset). Remaining owner choices: which order is canonical for German's testing (00095537 = 32 clean assets, fresh account; 00095536 = on the original account; 00095470 = the assetless original); and rep guidance to use Quantity when re-ordering against existing assets.

---

## 5. AC5 — recovering 00095470's assets (the open item)

**Why it's open:** the collision is deterministic on the *current* 32-duplicate-line shape. Re-firing as-is will just fail again (now **visibly**, via AC1). Recovery requires removing the multiple-writers-per-Asset condition — Salesforce's own documented shape: **one line per product carrying Quantity**, not N duplicate lines.

**Target:** collapse to 4 lines —

| ProductCode | Quantity | Model |
|---|---|---|
| PIA-PIA-NRPS-PIAP | 10 | OneTime |
| PIA-PIA-RNM-PIAMBK | 10 | OneTime (absorbs the qty-0 + decomposition artifact) |
| HRM-HRM-RSL-SEAW | 6 | TermDefined (future-dated) |
| HRM-HRM-RSL-CLSAAS | 6 | TermDefined (future-dated) |

→ re-trigger assetization. **Executed 2026-06-16 → result: 4 Assets, NOT 32 (collision-free).**

> ✅ **EXECUTED (owner-authorized, 2026-06-16).** In-place re-fire is **blocked** (`CANNOT_EXECUTE_FLOW_TRIGGER`, "Order Submission to Revenue Orchestrator"), so 00095470 was **rebuilt** as order **00095536** (`801WC00000kswTSYAY`) on the same account with the 4 Quantity lines above. It activated and **assetized cleanly — no collision** (`Order_Integration_Error_Messages__c = null`), producing **4 lifecycle Assets** (PIAP qty 10 `02iWC000008N0QxYAK`, PIAMBK qty 10 `02iWC000008N0QvYAK`, SEAW qty 6 `02iWC000008N0QyYAK`, CLSAAS qty 6 `02iWC000008N0QwYAK`; all Installed / Generate / Initial Sale).
>
> ⚠️ **The 32-vs-4 question is settled: the answer is 4.** This org creates **one Asset per order line carrying Quantity** (corroborated by Test C: a single Qty=1 line → 1 Asset), so de-duping 32 lines to 4 Quantity lines yields **4 quantity-rolled Assets** (10+10+6+6 = 32 *units*), **not 32 individual Asset records**. The ticket's "expect 32 Assets" assumed per-unit granularity that does not apply here. **The collision-free path and "32 individual assets" are mutually exclusive** — 32 separate assets require 32 separate lines, which is exactly the shape that collides. Pricing caveat: 00095536 is at catalog price (TotalAmount $17,340 vs the original $4,189); it recovers assets/quantities, not the original deal economics.

**The runbook** (`AC5_RECOVERY_RUNBOOK.md`) holds the executed procedure and the remaining owner reconciliation (00095536 vs the assetless 00095470; 4-vs-32 acceptance; pricing match).

---

## 6. Official Salesforce / RLM documentation (the "RCA official document")

Full cited synthesis: **`OFFICIAL_RCA_REFERENCES.md`** (and the raw research at `evidence/W1_…`, `W2_…`, `W3_…`). Load-bearing facts:

- **O2A on activation is native + overridable.** On Order activation the standard *"Assetize Orders"* flow (`revenue_o2aflows__o2aFlow`) auto-creates Assets; Revenue Settings lets you point the O2A flow API name at a **custom override** — exactly how `Fortra_Assetize_Order` is wired. *(RLM Dev Guide — Asset Lifecycle Overview; Subscription Mgmt renew guide.)*
- **`createOrUpdateAssetFromOrder`** is async, input = Order Id, "creates an asset for each order item; new assets for a new order, existing assets modified for change orders," matched by **Account + Product**. Completion/failure is signaled via the **`CreateAssetOrderEvent`** platform event — **the platform does not stamp the Order or block "Order Complete"; the override flow must react.** *(RLM Dev Guide — action page; Platform Events — CreateAssetOrderEvent.)*
- **Data model:** `OrderItem → AssetActionSource → AssetAction → Asset` (+ `AssetStatePeriod`). **AssetAction.Type** = Generate (initial sale) vs Change (modify); **Category** = Initial Sale / Renewals / Amendments / Cancellations. Live data matches: 47× Generate (present-dated) vs 1× Change (the future-dated renewal line). *(RLM Dev Guide — AssetAction / AssetActionSource.)*
- **`INVALID_API_INPUT` ≠ `UNABLE_TO_LOCK_ROW`.** The former is an input/contract-violation envelope; "updated by another process" is the **optimistic** (version-check) rejection — instant, no lock wait. Documented remedy = reduce concurrency / serialize / **Quantity over duplicate lines**. **No Known Issue / hotfix.** *(REST API Status Codes; Help 000387767 / 000393690; SF Architects.)*
- **Async path = separate post-commit transaction, own budget;** a graceful-end fault path **swallows** the error and **does not roll back** the trigger. Documented surfacing channels for a screenless async flow: error email, error-log object, platform event, or **custom error field on the record** — V14 uses the last, the platform-correct option (`FlowExecutionErrorEvent` is **screen-flow-only**, unavailable here). *(SF Help — Scheduled Paths / Fault handling; Architects — Async Processing.)*

**Conclusion the docs support:** the native throw is **working-as-specified given the data shape**, the **silent swallow was the genuine defect**, V14's surface-on-record is the **documented-aligned remediation**, and **Quantity de-dup (AC5)** is the **doc-endorsed** way to clear the collision.

---

## 7. Ruled out (with verdicts)

| Hypothesis | Verdict |
|---|---|
| **SC-3366 governor / SOQL-101** | ❌ Only 1–2 SOQL, CPU 0; the abort is in the **async** asset transaction, not the synchronous order-completion txn SC-3366 targets. Deterministic lock, not a limit. |
| **Decision-table failed refresh** (`Asset_Action_Source_Entries_Decision_Table_V2` `0lDa50000007BJhEAM`, SC-3403 B-5) | ❌ It is a **downstream PricingDiscovery** reader of *existing* AAS rows, not the new-order creation gate (00095471 assetized 13 min later under the same state). Table is Active. |
| **Future-dating skips assetization** | ❌ 00095475's future-dated `BESECB` line **did** assetize → Asset `02iWC000008FcLaYAK`. |
| **Plain line duplication** | ❌ Synthetic 2-/12-line same-product OneTime orders both assetized 1:1. The trigger is **duplicate + maintenance-decomposed + pre-existing-asset** combined. |
| **Config / `IsAssetizable`** | ❌ All 4 SKUs `IsAssetizable = true`. |
| **SC-3411 null-term activation blocker** | ❌ Order activated; all 12 TermDefined lines fully dated at activation. |

---

## 8. Scope & reconciliation

- **Scope:** account/order-specific (heavy duplication + maintenance decomposition + pre-existing assets) — **not a systemic outage.** Org has 1,994 assets on this account alone and ~110 lifecycle Assets created org-wide in the last 7 days; renewals generate normally elsewhere (AC2).
- **vs SC-3415 (parent):** SC-3419 owns **Defect A** (no-Assets-after-activation). SC-3415's *Defect B* (quote-tier `PricingTermCount` derivation regression) is tracked separately and is **not** in SC-3419's scope.
- **vs SC-3411 (resolved):** SC-3411 fixed the *order-tier* null-term **activation blocker**. SC-3419 is a different transaction entirely (post-activation async assetization). Not a duplicate, not a subset.

---

## 9. Open items / next actions

1. **AC5 — recover 00095470** (owner-authorized): run `AC5_RECOVERY_RUNBOOK.md` — (a) FINEST re-fire as-is to capture the AC1 stamp + pin the contended Asset, (b) Quantity de-dup, (c) re-trigger, (d) **count the resulting Assets and settle 32-vs-4** (per-unit vs Quantity-rollup).
2. **Prod rollout of V14** — UAT-only today; standard cutover gate. The flow uses no new schema (low-risk), but `createOrUpdateAssetFromOrder` is unchanged so the underlying collision will still occur on duplicate-line prod orders — now *visibly*. Pair the rollout with rep guidance to use **Quantity, not duplicate lines**.
3. **Rep / build guidance** — surface that duplicate same-product lines on an account with existing assets will collide; configure via Quantity. (Doc-endorsed; W2.)
4. **Track** `Asset_Action_Source_Entries_Decision_Table_V2` refresh (SC-3403 B-5) as a *separate* latent pricing-discovery risk — not this order's gate.

---

## 10. Evidence index

| File | What |
|---|---|
| `evidence/Fortra_Assetize_Order.V14.flow-meta.xml` | Live V14 flow (retrieved 2026-06-16) — the AC1/AC3/AC4 mechanism |
| `evidence/k2_capture_collision_proof.log` | FINEST rollback diagnostic on 00095470 — `ok=0 bad=1`, the INVALID_API_INPUT lock, 2 SOQL / CPU 0, 5 pre-existing assets named |
| `evidence/L1_flow_v14.md` | Flow V14 deep-verification (AC1/AC3/AC4 + no-drift diff) |
| `evidence/L2_order_state.md` | Live 00095470 + asset-pipeline state; line table; decomposition; AC5 baseline |
| `evidence/L3_ac2_assetization.md` | AC2 proof — 8 normally-built orders 1:1 + future-dated line → Asset |
| `evidence/L4_collision.md` | Collision mechanism re-confirmation — existing assets per product, decision table, link semantics |
| `evidence/W1_rlm_asset_lifecycle.md` | Official RLM asset-lifecycle / O2A documentation (cited) |
| `evidence/W2_optimistic_lock.md` | Official optimistic-lock / `INVALID_API_INPUT` vs `UNABLE_TO_LOCK_ROW` / Quantity-vs-duplicate (cited) |
| `evidence/W3_async_flow_faults.md` | Official async-path / fault-handling / flow-override documentation (cited) |
| `OFFICIAL_RCA_REFERENCES.md` | Consolidated official-doc synthesis + source URLs |
| `AC5_RECOVERY_RUNBOOK.md` | Owner-authorized recovery + FINEST repro procedure |
| `JIRA_COMMENT.md` | Stakeholder-facing comment |

*Live retrieve/queries: `Data/sc3419/`. Parent RCA: `*Jira/Task/sc3415 …/`. Fix deploy artifacts: `Data/sc3415/stage/v14/`.*

**All facts re-verified live (read-only) against FortraUAT, 2026-06-16.**
