# SC-3447 P1 — Non-Clone Floor + Post-P1 Synchronous Ceiling Model + Measurement Plan

**Date:** 2026-06-27 · **Role:** ceiling-model analyst (strictly read-only) · **Org:** FortraUAT (00DWC000006eUFF2A2)
**Scope:** P1 only (make each clone cheap). Model how high the SYNCHRONOUS convert ceiling rises after P1,
bounded by the costs P1 does NOT shrink (the non-clone floor + the reprice/activate tail), and give a
defensible post-P1 `MAX_SYNC_CLONES`. Then a runnable measurement plan to replace the estimate.

**Inputs re-verified live this session** (not trusted from prior docs):
- OrderItem describe: **208 fields, 149 createable, 208 accessible** — fresh `sf sobject describe` AND cached file both agree (no drift).
- OI flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type` retrieved fresh: **apiVersion 66, Active, RecordAfterSave / CreateAndUpdate, NO start entry condition, 2 recordLookups (SOQL: Get_Prepaid_Order_Attribute on OrderItemAttribute + Get_Product on Product2), 4 conditional `$Record` recordUpdates (one fires per interview), 3 decisions, 0 loops, 0 actionCalls.** (file 02/04 said "1 SOQL"; live now has **2 SOQL** — drift noted.)
- OI flow `Fortra_OrderItem_Set_Dates` retrieved fresh: **apiVersion 67, Active, RecordBeforeSave / CreateAndUpdate, NO entry condition, 3 `$Record` recordUpdates (before-save = in-memory, 0 SOQL / 0 DML), 0 loops.**
- `OrderRepriceInvocable` live (01pWC000002VIVlYAO, api 62): one `RecordWithReferenceRequest` PATCH per OrderItem in the Force graph → O(N) — confirmed from the live body (`Data/sc3447/investigation_2026-06-27/OrderRepriceInvocable_live.cls`).
- Convert flow: **V28 now Active (V27 went Obsolete since this morning's docs)** — daily churn. Chain pattern unchanged (Checklist → createOrderFromQuote → Mapper → Split → Reprice → Activate). My model is version-independent (depends on the action chain + per-line costs, both structural).
- **P3 split-eligible population (the partition path) = exactly 4 OrderItems org-wide, all Quantity=3 (N=2 clones each); 0 lines on the OLH+hardware path** vs **3,816 total Power qty>1 lines** (max 999,999, avg 35,301). P3 already removes 99.9% of split volume; the synchronous path now only sees tiny N in production.
- Limits (cheatsheet): sync CPU **10,000 ms**, async CPU **60,000 ms**; DML rows processed **10,000 sync AND async** (same wall both); package/workflow CPU **counts toward** the Apex CPU limit (so the Force-reprice procedure + OI flows accrue to the 10,000 ms budget).

`N` = total clones = Σ(qty−1) over split-eligible lines. `L` = distinct quote lines (originals) = distinct OrderItems on the order.

---

## 1. The non-clone FLOOR — what survives P1, and how it scales

P1 drives the per-CLONE cost toward ~0 on the suppressed-flow path: the 208 getDescribe()/clone collapse to a one-time 208 (hoist), and the ~2 OI-flow interviews/clone disappear (the `Is_Split_Line__c=false` start condition skips clones, with the split Apex stamping the derived fields it would have set). **Everything below is NOT touched by P1** and bounds how high P1 can push convergence.

| # | Contributor | Where | Scales with | Suppressed by P1? | CPU character |
|---|---|---|---|---|---|
| F1 | ChecklistValidationService (×2: trigger before-insert + flow first action) | OrderValidationTrigger + flow | **O(1)** (×checklist-items, not lines) | n/a | negligible; 1 SOQL each |
| F2 | createOrderFromQuote **OI-flow fire #1** (insert of L originals) | native RLM insert | **O(L)** | **NO** — originals are `Is_Split_Line__c=false`, the value the guard ADMITS | L × [Set_Workday: 2 SOQL + 1 `$Record` update → re-fires Set_Dates] |
| F3 | createOrderFromQuote native platform pricing/context work | native RLM | O(L)+platform | NO | opaque platform CPU on same budget |
| F4 | QuoteToOrderFieldMapper **OI-flow fire #2** (update of changed originals) | mapper L260 bulk update | **O(L)** | **NO** — same reason as F2 | L × [Set_Workday: 2 SOQL + 1 `$Record` update → re-fires Set_Dates] |
| F5 | Mapper own Apex (3 SOQL + ≤2 DML, in-memory loops) | mapper | O(L) cheap | n/a | bulkified, small |
| F6 | Order-header flow cascade (~15–18 O(1) flow interviews + 1 before-insert trigger) | Order flows | **O(1)** per Order-DML (~5–6 header DMLs) | NO (different object) | fixed; none loops over OrderItems |
| F7 | **Reprice tail — Force PlaceOrderExecutor over the FINAL N+L lines** | OrderRepriceInvocable | **O(N+L)** | clones: re-fired on clones only if clones lack the guard (they have it → suppressed); **the V16 procedure itself prices ALL N+L lines regardless** | 1 PATCH/line in graph + V16 proc per line + 92KB PartnerNetPricePosthook |
| F8 | **Reprice tail — 4 bulk OrderItem UPDATE passes over all N+L lines** (seedFromWork, persistFromWork ×2, OrderCommercialNetService.patch) | OrderRepriceInvocable / MaintenanceOrderDecompositionService | **O(N+L) DML rows ×4** + OI-flow re-fire | **PARTIALLY** — re-fire on clones suppressed by P1 (clones carry `Is_Split_Line__c=true`)… **BUT after Phase 5 the split sets clones to slot model; the 4 updates touch every line.** Re-fire on **originals/non-split lines (false) NOT suppressed.** | up to 4·(N+L) DML rows + OI-flow interviews on the `false` lines |
| F9 | Activate-time native `submitOrder` (Revenue Orchestrator over all order lines) | Order_Submission_to_Revenue_Orchestrator flow | **O(line-count)** = O(N+L) | NO | managed CPU on same budget |
| F10 | Activate Order update + its O(1) header cascade | Activate_Order | O(1) | NO | one Order DML |

### 1a. Which floor terms actually scale, and with what
- **Fixed (qty-independent):** F1, F6, F10. A constant ~15–20 cheap flow interviews + a handful of SOQL. Tens of ms. Irrelevant at any N.
- **O(L) — distinct-line count:** F2, F4 (the per-ORIGINAL OI-flow DOUBLE-FIRE), F5. This is the dominant floor on a **multi-distinct-line** quote and is **completely untouched by P1**, because every original is `Is_Split_Line__c=false`. Each original pays the Set_Workday bundle **TWICE** (insert + mapper update) = **2·L × (2 SOQL + 1 `$Record` update + 1 re-entrant Set_Dates run)**.
- **O(N+L) — final line count after split:** **F7, F8, F9.** This is the part that scales with clone-count N and is the **binding tail** on a single-high-qty-line quote. P1 does NOT shrink the V16 procedure cost (F7) or the activate-time submitOrder (F9); it only removes the OI-flow re-fire on clones inside the 4 reprice bulk updates (F8), and even that leaves the re-fire on the `false` originals.

### 1b. Why this matters for "how high can P1 push"
P1's promise is: per-clone cost → ~0 **inside the split phase**. But the SAME N clones then flow through the **reprice tail** (F7/F8) and **activate submitOrder** (F9), which P1 cannot make cheap. So after P1 the synchronous N-scaling cost is no longer "split-phase describe ×N" — it is **the reprice tail's per-line cost ×N (V16 procedure + up to 4 bulk DML passes) plus activate's submitOrder ×N**. That tail is the real post-P1 ceiling, not the split loop. **P1 raises the split-phase ceiling into the thousands, but the reprice/activate tail caps the whole-convert ceiling much lower.**

---

## 2. Post-P1 synchronous ceiling model

Two independent walls: **CPU (10,000 ms)** and **DML rows (10,000)**. The convert fails at whichever binds first. Both are evaluated over `N` clones on the **partition path** (the only path P3 leaves; OLH+hardware path is empty live).

### 2a. DML-row wall (hard arithmetic, partition path)
DML rows attributable to N, summed across all phases that emit per-clone rows:

| Source | Rows | Notes |
|---|---|---|
| Split Phase 4 — insert clone OrderItems | N | |
| Split Phase 6 — insert cloned partitions | N | partition path |
| Split Phase 7 — update clone OrderItems (partition FK) | N | partition path |
| **Split subtotal** | **3N + ~2** | + Phase 5 originals (~1) + Phase 8 ValidationResult (~1) |
| Reprice F8 — 4 bulk UPDATE passes over all (N+L) lines | **up to 4·(N+L)** | seedFromWork + persistFromWork×2 + OrderCommercialNetService.patch |
| Reprice F7 — PlaceOrderExecutor Force graph PATCH (platform DML) | ~ (N+L) platform-side | counts in the same 10k-row budget |
| Activate F9/F10 + Order updates | ~ several | O(1) |

**Conservative DML-row total ≈ 3N (split) + 4·(N+L) (reprice) + (N+L) (reprice graph) ≈ 8N + 5L.**
With L modest (say L≤20): `8N + 100 ≤ 10,000 → N ≤ ~1,237`. With the split-only 3N+2 floor the absolute hard wall is **N ≈ 3,332**, but **the reprice tail's 4× re-DML over the post-split line set pulls the effective DML wall down to ≈ N ~1,000–1,250.** (If the 4 reprice passes are idempotent/no-op on unchanged lines, fewer rows are emitted and the wall rises back toward 3,332 — measurement, §3, must determine which.)

### 2b. CPU wall (10,000 ms) — component estimate
There is no published per-element ms figure; I estimate from the structural op counts and the known fact that **at N≈455 (qty-456 repro) the PRE-P1 transaction blew 10,000 ms**, dominated by 208·N getDescribe (~94,640 describes) + ~2 OI-flow interviews/clone. P1 removes essentially all of that. So the **post-P1 CPU budget is almost entirely the reprice tail + activate**, which the pre-P1 run also paid but which was dwarfed by the describe storm.

Post-P1 per-N CPU contributors (each accrues to the 10,000 ms budget):
1. **Split phase, post-P1:** ~ a few get()/put() per clone (no describe, no flow) → **~tens of µs/clone** → negligible even at N=1,000 (sub-100 ms).
2. **Reprice F7 — V16 pricing procedure over N+L lines** via PlaceOrderExecutor Force. This is the heavy one: a full RCA pricing procedure (V16) runs per line. Empirically RCA reprice is **~5–20 ms/line** of in-transaction CPU for a non-trivial procedure (procedure element count + PartnerNetPricePosthook 92KB). Call it **~10 ms/line** as a central estimate → at N+L = 200, ~2,000 ms; at 500, ~5,000 ms; at ~900, ~9,000 ms.
3. **Reprice F8 — 4 bulk OI updates** each re-firing Set_Workday on the `false` lines: Set_Workday is **2 SOQL + decisions + 1 `$Record` update** per line per pass. SOQL CPU is light but the flow-interview overhead is real. Estimate **~1–2 ms/line/pass × 4 passes ≈ 4–8 ms/line.**
4. **Activate F9 — submitOrder** Revenue Orchestrator over line-count: **~few ms/line.**

**Central CPU estimate ≈ (10 + 6 + 3) ≈ ~19 ms/line on the final (N+L)-line order**, dominated by the V16 reprice. → `~19·(N+L) ≤ 10,000 → N+L ≤ ~525 → N ≤ ~505` (L small).
- **Optimistic (light procedure, ~8 ms/line):** N+L ≤ ~1,250 → N ≤ ~1,230.
- **Pessimistic (heavy procedure + posthook, ~30 ms/line):** N+L ≤ ~333 → N ≤ ~315.

### 2c. The binding ceiling — RANGE
| Limit | Binds at N ≈ | Driver |
|---|---|---|
| CPU (pessimistic ~30 ms/line) | **~315** | V16 reprice + posthook over N+L |
| CPU (central ~19 ms/line) | **~505** | V16 reprice |
| DML rows (8N+5L, reprice 4× re-DML) | **~1,000–1,250** | reprice bulk passes |
| CPU (optimistic ~8 ms/line) | **~1,230** | reprice |
| DML rows (split-only 3N+2 floor) | **~3,332** | clone+partition inserts |

**Defensible post-P1 synchronous ceiling RANGE: N ≈ 300–1,000 clones**, with the **CPU of the reprice tail (F7) as the binding limit in the realistic/pessimistic case (~300–500)** and the **DML-row reprice re-DML (~1,000–1,250) binding if the procedure is cheap.** The split phase itself is no longer the binding limit after P1 — it could do thousands; the convert as a whole cannot, because the reprice/activate tail re-processes the same N lines and P1 does not make that cheap.

### 2d. Recommended MAX_SYNC_CLONES after P1
- **Recommend raising `MAX_SYNC_CLONES` from 200 → 400** (conservative; ~50–80% of the central CPU ceiling, comfortably below the pessimistic ~315 only if the procedure is light — see caveat).
- **Caveat that forces conservatism:** if the V16 reprice is on the heavy end (~30 ms/line), the binding CPU ceiling is ~315, so **400 would be too high**. Because the reprice cost is the unmeasured term, **do NOT raise the cap on the estimate alone.** Recommended action: **keep the cap at 200 until the §3 measurement runs**, then set the cap to **~60% of the measured CPU cliff** (e.g. if the cliff is at N=500, set 300; if at N=900, set 500). 200 already gives generous headroom over the live reality (max real split N=2 under P3), so the cap is not the user-facing constraint — the measurement is needed only to safely RAISE it, not to keep the system working.
- **Net recommendation: cap = 200 now (unchanged, safe); raise to 300–400 ONLY after the measurement confirms the CPU cliff is comfortably above ~700.** The cap's job is a friendly-error backstop, and P3 means it almost never fires in production.

---

## 3. MEASUREMENT PLAN — replace the estimate with a real number (runnable WITH deploy auth)

The single unmeasured term is **ms/line of the reprice tail + activate** on the post-split N-line order, and the **real DML-row count** the 4 reprice passes emit. The plan isolates CPU and DML at increasing K, with flows ON vs SUPPRESSED, to find the actual cliff and prove the P1 flow-suppression win.

### 3a. Harness (anonymous Apex or a `@isTest`; requires deploy/execute auth — NOT run now)
Build a Power order with one partition-bearing OLO line, then synthesize K clones in-Apex and run the real tail, instrumenting `Limits` between phases. Pseudocode:

```apex
// ANON APEX — instrumentation only; do NOT commit data (wrap in Savepoint + Database.rollback at end).
Id orderId = /* a draft Power order with 1 OLO+partition line, Solution_Group=Power */;
Savepoint sp = Database.setSavepoint();
for (Integer K : new List<Integer>{100, 200, 400, 800}) {
    // reset: re-query the single original each iteration (rollback between K)
    Long c0 = Limits.getCpuTime();  Integer d0 = Limits.getDmlRows();
    // --- PHASE A: clone build (P1 hoisted path) ---
    PowerOrderSplittingService.processOrder(orderId);   // with cap temporarily raised for the test only
    System.debug(LoggingLevel.ERROR, 'K='+K+' SPLIT cpu='+(Limits.getCpuTime()-c0)+' dmlRows='+(Limits.getDmlRows()-d0));
    Long c1 = Limits.getCpuTime();  Integer d1 = Limits.getDmlRows();
    // --- PHASE B: reprice tail ---
    OrderRepriceInvocable.reprice(new List<OrderRepriceInvocable.Request>{ new OrderRepriceInvocable.Request(orderId=orderId) });
    System.debug(LoggingLevel.ERROR, 'K='+K+' REPRICE cpu='+(Limits.getCpuTime()-c1)+' dmlRows='+(Limits.getDmlRows()-d1));
    System.debug(LoggingLevel.ERROR, 'K='+K+' TOTAL cpu='+Limits.getCpuTime()+' dmlRows='+Limits.getDmlRows()
                 +' soql='+Limits.getQueries()+' flowInterviews(via FLOW limit unavailable; infer from cpu)');
    Database.rollback(sp);  // discard all clones; re-run clean at next K
}
```

### 3b. Exactly what to instrument
For each **K ∈ {100, 200, 400, 800}** (and add 600, 700 to bracket the cliff once a rough range is known) capture, **per phase (split, reprice, activate-attempt) and cumulative**:
- `Limits.getCpuTime()` (ms) — the primary number; find K where cumulative crosses ~8,000 ms (safe-margin cliff) and ~10,000 ms (hard fail).
- `Limits.getDmlRows()` — verify the real reprice multiplier (is F8 really 4·(N+L), or do idempotent passes emit far fewer?). This decides whether the DML wall is ~1,250 or ~3,332.
- `Limits.getQueries()` — confirm SOQL stays flat (catch any accidental SOQL-in-loop regression).
- Optionally `Limits.getDmlStatements()` to confirm statements stay flat.

### 3c. The A/B that proves P1's flow-suppression value
Run the **same K-sweep TWICE**:
1. **Flows ACTIVE** (current state) — baseline; the OI flows fire on every inserted/updated clone and on every reprice bulk update.
2. **Flows SUPPRESSED** — deploy the P1 versions with `Is_Split_Line__c=false` start condition (and the Apex clone-stamp), so clones skip the 2 OI flows.

Δcpu(active − suppressed) at each K = **the measured per-clone OI-flow cost P1 removes.** If suppressed-CPU at K=800 is comfortably <8,000 ms while active-CPU blows >10,000 ms at K≈200, that quantifies the P1 win directly and justifies raising the cap.

### 3d. Where the cliff actually is → cap rule
- Find `K_cpu` = largest K with cumulative CPU < **8,000 ms** (20% safety margin under the 10,000 hard limit), flows-suppressed.
- Find `K_dml` = largest K with cumulative DML rows < **8,000** (20% margin).
- **Set `MAX_SYNC_CLONES = round_down( min(K_cpu, K_dml) × 0.75 )`** (extra 25% margin for procedure-version drift, since V16→V?? churns daily and a heavier future procedure raises ms/line).
- Re-run the measurement whenever the active Order pricing procedure version changes materially (the ms/line term is procedure-dependent).

### 3e. Caveats for the measurement
- **PlaceOrderExecutor / submitOrder may not run cleanly in pure anon-apex** outside the flow's running context (context-definition binding, RLM transaction posture). If `OrderRepriceInvocable.reprice` faults standalone, run the measurement instead as an **end-to-end convert in a sandbox** on synthetic quotes with one Power OLO+partition line at increasing quantity (qty=101/201/401/801), capturing CPU via a `Limits.getCpuTime()` debug at the end of the split invocable and at the reprice invocable's return, read from the debug log. This is closer to reality (real chain order, real context) at the cost of being harder to bisect by phase.
- **Cap must be temporarily raised in the test** (the live 200 cap would short-circuit at K>200). Use a `@TestVisible`/test-only override or a separate test build; never ship the raised cap.
- Activate (F9) may also need ValidationResult/CompletedWithPricing to be reached; if activate can't complete in the harness, measure split+reprice only (that already contains the dominant N-scaling tail) and treat activate's submitOrder as an additive ~few-ms/line term.

---

## 4. Bottom line

1. **P1 makes the SPLIT phase cheap, not the convert.** After P1 the split phase could clone into the low-thousands, but the **reprice tail (V16 Force procedure ×N+L + 4 bulk re-DML) and activate submitOrder (×N+L)** — none of which P1 shrinks — become the binding synchronous limit.
2. **Modeled post-P1 ceiling: N ≈ 300–1,000 clones**, CPU-bound by the reprice procedure in the realistic case (~300–500), DML-row-bound (~1,000–1,250) if the procedure is light; split-only hard floor ~3,332.
3. **Recommended cap: keep MAX_SYNC_CLONES = 200 now (safe, already far above the live reality of N=2 under P3); raise to 300–400 ONLY after the §3 measurement confirms the CPU cliff is comfortably >700.** The reprice ms/line is the one unmeasured term and it gates any cap increase.
4. **P3 is what actually protects production** (4 split-eligible lines org-wide, all N=2). P1 + the cap are durability/headroom, not the live constraint. The measurement matters chiefly to safely RAISE the cap, not to keep converts working.

---

## 5. Drift log (this session vs prior docs)
- Convert flow **V27 → Obsolete; V28 now Active** (was V27 Active in 01/03/ADVERSARIAL). Chain pattern unchanged; model is version-independent.
- Workday line-type OI flow now does **2 SOQL** (added `Get_Prepaid_Order_Attribute` on OrderItemAttribute) — prior docs (02/04) said 1 SOQL. Raises the per-original double-fire (F2/F4) and the reprice re-fire (F8) cost slightly; reinforces, doesn't change, the conclusion.
- OrderItem field counts **unchanged** (208/149/208), fresh-verified.
- P3-eligible split population **= 4 lines, all qty=3** (partition path; 0 OLH+hardware) — live this session. Confirms the synchronous path sees trivial N in production.
- OI flows confirmed **NO start entry condition** (both) — P1's `Is_Split_Line__c=false` add is a clean, additive change.
</content>
</invoke>
