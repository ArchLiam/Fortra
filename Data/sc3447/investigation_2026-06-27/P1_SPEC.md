# SC-3447 P1 — BUILDABLE SPEC: Make Each Power-Split Clone Cheap

**Date:** 2026-06-27 · **Org:** FortraUAT (00DWC000006eUFF2A2) · **Ticket:** SC-3447 (P1)
**Status:** Spec for build. Strictly behavior-preserving. NO Workday-confirmation dependency. Ships independently of P3.
**Subject class:** `force-app/main/default/classes/PowerOrderSplittingService.cls` (local copy = P0 cap + P3 gate; line refs below match THIS file).

P1 = two coupled changes that drop the per-clone fixed cost toward zero so the synchronous convert ceiling
rises into the hundreds:
1. **HOIST the field-describe work** out of the per-clone loop (compute the createable / accessible
   field-name lists ONCE per transaction; per-clone loop becomes pure `get()/put()`).
2. **SUPPRESS the two per-clone OrderItem record-triggered flows** via a `Is_Split_Line__c = false` Start
   entry condition, AND have the split Apex explicitly STAMP the derived fields onto each clone so the
   clones still end up correctly stamped without the flows.

---

## 0. Re-verified live state (2026-06-27, the facts this spec depends on)

| Fact | Value | Source |
|---|---|---|
| Set_Dates active version | **V6**, Flow Id `300WC00000Qqd9ZYAR`, API 67, RecordBeforeSave, CreateAndUpdate, **no start filter** | Tooling `Flow` re-query this session |
| Set_Workday active version | **V11**, Flow Id `300WC00000QqP3OYAV`, API 66, RecordAfterSave, CreateAndUpdate, **no start filter** | Tooling `Flow` re-query this session |
| Convert flow active version | **V28**, Flow Id `300WC00000LtlNBYAZ`, API 62 (was V27 in earlier docs — daily churn) | Tooling `Flow` re-query this session |
| Set_Workday V11 recordLookups (SOQL) | **2**: `Get_Prepaid_Order_Attribute` (OrderItemAttribute) + `Get_Product` (Product2) | retrieved active V11 XML |
| Set_Workday V11 subsplit logic | `$Record.Product2.Is_Subsplit_Product__c` (1 ref); **0 refs to `Original_Order_Item__c`, 0 to `Is_Split_Line__c`** | grep of retrieved active V11 XML |
| OrderItem describe | **208 total / 149 createable / 208 accessible (as convert user)** | `sf sobject describe` (3 agents, no drift) |
| `Is_Split_Line__c` | **Checkbox** (default false), createable | FieldDefinition + describe |
| 7 stamp fields + ServiceDate | all Date/Number/Picklist, all createable + updateable, none formula/rollup/read-only | FieldDefinition + describe (P1_02) |
| OrderItem triggers / active VRs | **0 / 0** | Tooling ApexTrigger / ValidationRule |
| `Is_Split_Line__c` consumers | Order Product Layout + PowerOrderSplittingService(+Test) ONLY | MetadataComponentDependency |
| `Original_Order_Item__c` consumers | Layout + Apex(+Test) + Set_Workday flow **but only in 8 OBSOLETE versions** (active V11 = 0) | MetadataComponentDependency + active-XML grep |

**RE-VERIFY AT BUILD TIME (daily churn):** Set_Dates V6 / Set_Workday V11 still active; active Set_Workday
version still derives subsplit from `$Record.Product2.Is_Subsplit_Product__c` with **no
`Original_Order_Item__c` reverse-lookup** (the reverse-lookup logic survives in the 8 obsolete versions and a
new active version could reintroduce it — that would re-break SC-3210/3368). Convert flow active version (was
V28) — not material to P1 but confirm the Split→Reprice→Activate chain is unchanged.

---

## 1. APEX CHANGES (exact, with method + current-file line refs)

### 1a. HOIST the describe work — two lazily-computed static field-name lists

**Problem (current file):**
- `createFullClone` (**L404–421**) calls `fieldMap.get(fieldName).getDescribe()` once per field **inside the
  per-clone loop** → **208 getDescribe()/clone**. For N clones that is 208×N reflection calls (e.g. N=200 →
  41,600). `getOrderItemFieldMap()` (**L423–428**) caches `fields.getMap()` but NOT the per-field describe
  results, so the describe work repeats every clone. **This is the per-clone amplifier.**
- `queryOrderItemsToSplit` (**L365–399**) runs the same 208-field `getDescribe()/isAccessible()` loop
  (**L368–373**) but only **once per transaction** — not the amplifier; hoist for tidiness + to share the
  static.

**Change — add two lazy statics + an init helper (place near the existing `orderItemFieldMap` static, L31):**

```apex
// Cached field describe for OrderItem
private static Map<String, Schema.SObjectField> orderItemFieldMap;

// SC-3447 P1: hoist the per-field getDescribe() out of the per-clone loop. These lists are computed
// ONCE per transaction (one pass over the 208 OrderItem fields) instead of once PER CLONE. The
// createable list is consumed by createFullClone(); the accessible list by queryOrderItemsToSplit().
private static List<String> createableOrderItemFields;   // all createable field API names
private static List<String> accessibleOrderItemFields;   // all accessible field API names

private static void initOrderItemFieldLists() {
    if (createableOrderItemFields != null) { return; }   // built once
    createableOrderItemFields = new List<String>();
    accessibleOrderItemFields = new List<String>();
    Map<String, Schema.SObjectField> fieldMap = getOrderItemFieldMap();
    for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
        if (dfr.isAccessible())  { accessibleOrderItemFields.add(fieldName); }
        if (dfr.isCreateable())  { createableOrderItemFields.add(fieldName); }
    }
}
```

**Rewrite `createFullClone` (L404–421) — zero getDescribe in-loop:**

```apex
private static OrderItem createFullClone(OrderItem original) {
    OrderItem clone = new OrderItem();
    initOrderItemFieldLists();                       // no-op after first call
    for (String fieldName : createableOrderItemFields) {
        try {
            Object val = original.get(fieldName);
            if (val != null) { clone.put(fieldName, val); }
        } catch (Exception e) {
            // Skip fields that can't be read from the queried record (unchanged behavior)
        }
    }
    return clone;
}
```

**Rewrite the field-collection loop in `queryOrderItemsToSplit` (L366–373) — use the accessible static:**

```apex
private static List<OrderItem> queryOrderItemsToSplit(Set<Id> orderIds) {
    initOrderItemFieldLists();
    List<String> queryFields = new List<String>(accessibleOrderItemFields);
    // Add parent relationship fields needed for split logic  (UNCHANGED + 2 new for P1 re-derive, see 1b)
    queryFields.add('Product2.Power_Split_Type__c');
    queryFields.add('Product2.Solution_Group__c');
    queryFields.add('Product2.Name');
    queryFields.add('Product2.Is_Subsplit_Product__c');        // P1: re-derive WCLT (no extra SOQL)
    queryFields.add('Product2.pse__IsServicesProduct__c');     // P1: services guard for WCLT derive
    ... // rest of method (WHERE clause, ORDER BY, Database.query) UNCHANGED
}
```

**Byte-identical field-set guarantee:** the list MUST be ALL createable field API names (not a hand-curated
subset). `initOrderItemFieldLists()` iterates the exact same `fields.getMap().keySet()` the old loop did and
applies the same `isCreateable()` predicate, so `createableOrderItemFields` is the same set the old loop
copied — the clone field-set stays byte-identical to today's output. (Test A1 asserts this; see §5.) Build
the static via `getOrderItemFieldMap()` (the same cached map), so describes still run AS the convert user.

**Transaction-level describe cost:** 208 + 208×N (today) → **~208 once** (build the two static lists; the
208-iteration pass runs at most once per transaction). In-loop per-clone describes: **208 → 0.**

### 1b. APEX-STAMP the derived fields on each clone (clone-customize block, current L188–201)

Flows write **7 distinct fields** (verified, all createable + updateable, none formula/rollup/read-only — so
all settable via `put()`; NO field needs special read-only handling):

| # | Field | Type | P1 verdict | Why |
|---|---|---|---|---|
| 1 | `Billing_Schedule_From_Date__c` | Date | **COPY (already via createFullClone)** | pure fn of clone's own Order.EffectiveDate/ServiceDate; clone shares parent's Order+ServiceDate → copy == re-derive |
| 2 | `Billing_Schedule_To_Date__c` | Date | **COPY (already)** | same |
| 3 | `End_Date_Calculated__c` | Date | **COPY (already)** | same |
| 4 | `Start_Date_Calculated__c` | Date | **COPY (already)** | same |
| 5 | `EndDate` | Date (std) | **COPY (already)** | SC-3411 termed backstop; same inputs as parent |
| 6 | `PricingTermCount` | Number(16,2) (std) | **COPY (already)** | SC-3411 backstop constant=1; same inputs as parent |
| 7 | `Workday_Contract_Line_Type__c` | Picklist | **RE-DERIVE (do NOT blindly copy)** | per p1:stamp verdict — live data has a STALE parent (OQLFw) whose stored value disagrees with its own product boolean; copy would propagate the stale value to clones. Re-derive matches active V11 logic on 34/34 recent non-split lines. |

**Fields 1–6 (date/term): COPY is sufficient (no-regression).** `createFullClone` already copies every
createable non-null field from the **already-stamped parent** (the convert flow inserts + flow-stamps the
originals in `Call_Create_Order_From_Quote` BEFORE `SplitPowerOrderLines` clones them — all in one
CurrentTransaction sync request, V28). No new code for these 6; they ride the existing copy. **Do NOT
re-derive them** (copy == re-derive here, and re-derive would just duplicate Set_Dates V6 logic in Apex for
no gain). The pre-existing ~36% null EndDate/PTC on OneTime/FIXED-AMOUNT originals propagates by copy but
does NOT regress (clone matches a non-split line) — closing it is **SC-3411/3420 scope; do NOT block P1.**

**Field 7 (`Workday_Contract_Line_Type__c`): RE-DERIVE in the clone-customize block.** Add a private helper
that mirrors active V11's non-services rule, with copy-from-parent as the services fallback:

```apex
// SC-3447 P1: re-derive Workday line type on the clone (mirrors active Set_Workday V11). A clone shares the
// parent's Product2, so the product-boolean derive on the clone == what the suppressed flow would stamp.
// Re-derive (not copy) defends against a STALE parent value (1 live case, OQLFw) that disagrees with its
// own product boolean. RE-VERIFY at build: active Set_Workday version still uses Product2.Is_Subsplit_Product__c
// with NO Original_Order_Item__c reverse-lookup (would re-break SC-3210/3368).
private static String deriveWorkdayLineType(OrderItem original) {
    Boolean isServices = (original.Product2 != null) && original.Product2.pse__IsServicesProduct__c == true;
    if (isServices) {
        // PREPAID vs USAGE BASED needs an OrderItemAttribute lookup; for the services path copy the parent's
        // stamped value (no extra SOQL). NOTE: all P3-eligible (partition/hardware) Power lines are
        // non-services, so this branch is never hit on a genuine per-machine split.
        return original.Workday_Contract_Line_Type__c;
    }
    Boolean isSubsplit = (original.Product2 != null) && original.Product2.Is_Subsplit_Product__c == true;
    return isSubsplit ? 'FIXED AMOUNT BILLING ONLY' : 'FIXED AMOUNT';
}
```

**In the clone-customize block (current L188–201), after `splitItem.Original_Order_Item__c = original.Id;`
(L194), add:**

```apex
splitItem.Workday_Contract_Line_Type__c = deriveWorkdayLineType(original);
```

This requires the 2 relationship columns added to `queryOrderItemsToSplit` in §1a
(`Product2.Is_Subsplit_Product__c`, `Product2.pse__IsServicesProduct__c`) — **relationship columns, no extra
SOQL.** The date/term fields 1–6 are already on `splitItem` from `createFullClone`'s copy, so no further code.

**Read-only / special fields:** none of the 7 stamp fields nor the 5 clone-customize fields
(`Quantity`, `Manual_Discount__c`, `Displaced_ARR__c`, `Is_Split_Line__c`, `Original_Order_Item__c`) are
formula/rollup/read-only — all are createable+updateable, all settable via `put()`/direct assignment. The
existing `createFullClone` already skips any field that throws on `get()` (the try/catch at L415/L410), which
covers any non-readable edge field. **No special read-only handling is required.**

### 1c. Unrelated-but-noted (from adversarial review, NOT new P1 scope)
- P0 cap loop already sets `success=false` on all results (L143–146) — consistent. The savepoint at L117 is
  before the cap check; harmless (no DML on that path). Leave as-is; out of P1 scope.
- `createFullClone` does NOT clone OrderItemAttribute children — unchanged behavior, no automation on
  OrderItemAttribute, not a regression. Out of P1 scope (E2E assert covers it; see §5 A6).

---

## 2. FLOW CHANGES — add `Is_Split_Line__c = false` Start entry condition to BOTH flows

Adding the SAME Start entry filter to both OrderItem flows skips the qty-1 clones (which carry
`Is_Split_Line__c = true`, set in memory at **L193 BEFORE the Phase-4 insert at L244**) with ~0 CPU — no
interview, no SOQL, no recordUpdate DML, no re-entrant re-fire. Originals (set `false` at L264–265) and ALL
normal lines (Checkbox default = false) keep satisfying `=false` → keep running both flows unchanged.

These create **NEW flow versions in the Workday line-type family — COORDINATE WITH BEN KOZLOWSKI** (the
line-type flow owner). Re-verify Set_Dates V6 / Set_Workday V11 are still the active versions at deploy and
clone off the CURRENT active version (do not resurrect an obsolete version that carries the
`Original_Order_Item__c` reverse-lookup — that would re-break SC-3210/3368).

### 2a. Fortra_OrderItem_Set_Dates — new version (clone of V6)

Insert a `<filters>` + `<filterLogic>` into the existing `<start>` block. Current V6 start (retrieved) is:

```xml
<start>
    <locationX>0</locationX>
    <locationY>0</locationY>
    <connector>
        <targetReference>Is_Termed_Blank</targetReference>
    </connector>
    <object>OrderItem</object>
    <recordTriggerType>CreateAndUpdate</recordTriggerType>
    <triggerType>RecordBeforeSave</triggerType>
</start>
```

New start (add filter — `EqualTo false` on the Checkbox):

```xml
<start>
    <locationX>0</locationX>
    <locationY>0</locationY>
    <connector>
        <targetReference>Is_Termed_Blank</targetReference>
    </connector>
    <filterLogic>and</filterLogic>
    <filters>
        <field>Is_Split_Line__c</field>
        <operator>EqualTo</operator>
        <value>
            <booleanValue>false</booleanValue>
        </value>
    </filters>
    <object>OrderItem</object>
    <recordTriggerType>CreateAndUpdate</recordTriggerType>
    <triggerType>RecordBeforeSave</triggerType>
</start>
```

### 2b. Fortra_OrderItem_Set_Workday_Contract_Line_Type — new version (clone of V11)

Current V11 start (retrieved) is:

```xml
<start>
    <locationX>0</locationX>
    <locationY>0</locationY>
    <connector>
        <targetReference>Get_Product</targetReference>
    </connector>
    <object>OrderItem</object>
    <recordTriggerType>CreateAndUpdate</recordTriggerType>
    <triggerType>RecordAfterSave</triggerType>
</start>
```

New start (same filter shape):

```xml
<start>
    <locationX>0</locationX>
    <locationY>0</locationY>
    <connector>
        <targetReference>Get_Product</targetReference>
    </connector>
    <filterLogic>and</filterLogic>
    <filters>
        <field>Is_Split_Line__c</field>
        <operator>EqualTo</operator>
        <value>
            <booleanValue>false</booleanValue>
        </value>
    </filters>
    <object>OrderItem</object>
    <recordTriggerType>CreateAndUpdate</recordTriggerType>
    <triggerType>RecordAfterSave</triggerType>
</start>
```

**Add to BOTH** (not just the after-save). Adding only to Set_Workday would stop the after-save `$Record`
update on clones (and thus its re-entrant Set_Dates re-fire), but the clone's INITIAL before-save Set_Dates
would still run. Filtering both removes all 3 interviews + the SOQL + the DML + the re-entrancy per clone.

**Per `<description>` style:** bump each flow's `<description>` to a single terse line
`2026-06-27: skip split-line clones (entry condition)` — no ticket IDs, no impl detail.

### 2c. Safety of suppression (why it breaks nothing)
- **0 OrderItem triggers, 0 active VRs** (Tooling). Nothing else fires on the clone insert.
- `Is_Split_Line__c` consumed only by the page Layout + the Apex class (MetadataComponentDependency) — no
  flow/VR/rollup/trigger.
- Active V11 derives line type from `$Record.Product2.Is_Subsplit_Product__c` with **0
  `Original_Order_Item__c` reverse-lookup** (re-confirmed this session; that logic lives only in 8 obsolete
  versions). So suppressing on clones cannot break a reverse-lookup that no longer exists in the active flow.
- The Apex now explicitly stamps `Workday_Contract_Line_Type__c` (re-derive) and copies the 6 date/term
  fields, so clones end up identically stamped to what the flows would have produced — the precondition the
  task requires ("suppress ONLY IF clones still end up correctly stamped") is satisfied.

---

## 3. RECOMMENDED MAX_SYNC_CLONES AFTER P1 (data-grounded ESTIMATE)

**Recommendation: KEEP `MAX_SYNC_CLONES = 200` now (unchanged). Do NOT raise it on the estimate alone.**
Raise to **300–400 ONLY after the §4 measurement confirms the CPU cliff is comfortably above ~700.**

**Why 200 stays, and what it sits under:**
- P1 collapses the **split-phase** per-clone cost (208 describes + 3 flow interviews + 1 SOQL + 1 re-entrant
  DML → ~0), an estimated **~4×–10× per-clone CPU reduction**, raising the *split-phase* ceiling into the low
  thousands. **But P1 does NOT shrink the convert as a whole.** The same N clones then flow through:
  - **F7 reprice tail** — the V16 Force pricing procedure prices ALL N+L lines (O(N+L)) + 92KB
    PartnerNetPricePosthook; P1 cannot touch this.
  - **F8 reprice 4× bulk OI re-DML** (seedFromWork + persistFromWork×2 + OrderCommercialNetService.patch),
    O(N+L) DML rows ×4.
  - **F9 activate-time native `submitOrder`** over line-count, O(N+L).
  - Plus the **per-ORIGINAL OI-flow DOUBLE-FIRE floor O(2L)** that P1 structurally CANNOT suppress (originals
    are `Is_Split_Line__c=false`, the value the guard ADMITS).
- **Modeled post-P1 binding constraint = the REPRICE TAIL, not the split-phase describe storm.** Two walls,
  evaluated over N clones on the partition path:

  | Limit | Binds at N ≈ | Driver |
  |---|---|---|
  | CPU 10,000 ms (pessimistic ~30 ms/line reprice) | **~315** | V16 reprice + posthook over N+L |
  | CPU 10,000 ms (central ~19 ms/line) | **~505** | V16 reprice |
  | DML rows 10,000 (8N+5L, reprice 4× re-DML) | **~1,000–1,250** | reprice bulk passes |
  | CPU 10,000 ms (optimistic ~8 ms/line) | **~1,230** | reprice |
  | DML rows (split-only 3N+2 floor) | **~3,332** | clone+partition inserts |

  Defensible post-P1 synchronous ceiling **RANGE: N ≈ 300–1,000 clones**, binding limit =
  **reprice-tail CPU (F7)** in the realistic/pessimistic case.
- **The single unmeasured term is the V16 reprice ms/line.** If it is heavy (~30 ms/line) the CPU cliff is
  ~315 and a cap of 400 would itself cause governor failures. **That is why the cap must NOT be raised on the
  estimate.**
- **200 is already ~100× above live reality:** under the P3 gate exactly **4 OrderItems org-wide are
  split-eligible, all Quantity=3 (N=2 clones)**, out of 3,816 total Power qty>1 lines. The cap is a
  friendly-error backstop that almost never fires in production; **P3 — not P1 or the cap — is what protects
  prod.** Keeping 200 costs nothing in real throughput and is safe under every modeled wall.

**Post-measurement cap rule:** `MAX_SYNC_CLONES = round_down( min(K_cpu@8000ms, K_dml@8000rows) × 0.75 )`
(20% safety margin under the 10k hard limits + 25% extra for procedure-version drift, since the active Order
pricing procedure churns daily and a heavier future procedure silently lowers the real cliff).

**ALL N-ceiling numbers in this section are component ESTIMATES — we were NOT authorized to run a live
convert.** They must be replaced by §4. The only MEASURED inputs are the describe counts (208/149/208), the
flow op-counts (V11 = 2 SOQL + 1 firing recordUpdate; V6 = 0/0), and the live split-eligible population (4
lines, N=2).

---

## 4. MEASUREMENT PLAN (run later WITH deploy/execute auth)

The unmeasured terms are (a) the reprice-tail ms/line and (b) the real DML-row count the 4 reprice passes
emit (4·(N+L) vs far fewer if idempotent). Resolve both with a K-sweep, flows-ACTIVE vs flows-SUPPRESSED.

1. **Harness (anon Apex or `@isTest`, NOT run now):** build a draft Power order with one partition-bearing
   OLO line (Solution_Group=Power), then run split → reprice at increasing K. Wrap in
   `Database.setSavepoint()` + `Database.rollback()` so nothing persists. Temporarily raise the cap for the
   test only (`@TestVisible` override or test build) — NEVER ship the raised cap.
   ```apex
   for (Integer K : new List<Integer>{100, 200, 400, 600, 700, 800}) {
       Savepoint sp = Database.setSavepoint();
       Long c0 = Limits.getCpuTime(); Integer d0 = Limits.getDmlRows(); Integer q0 = Limits.getQueries();
       PowerOrderSplittingService.processOrder(orderId);   // SPLIT phase
       System.debug(LoggingLevel.ERROR,'K='+K+' SPLIT cpu='+(Limits.getCpuTime()-c0)+' dml='+(Limits.getDmlRows()-d0));
       OrderRepriceInvocable.reprice(...);                 // REPRICE tail
       System.debug(LoggingLevel.ERROR,'K='+K+' TOTAL cpu='+Limits.getCpuTime()+' dml='+Limits.getDmlRows()
                    +' soql='+(Limits.getQueries()-q0));
       Database.rollback(sp);
   }
   ```
2. **Instrument per phase + cumulative:** `Limits.getCpuTime()` (primary — find K where cumulative crosses
   ~8,000 ms safe-cliff and 10,000 ms hard-fail), `Limits.getDmlRows()` (is F8 really 4·(N+L) → wall ~1,250,
   or idempotent → wall toward 3,332?), `Limits.getQueries()` (confirm SOQL stays FLAT — catch any
   SOQL-in-loop regression from the hoist), `Limits.getDmlStatements()` (confirm statements flat).
3. **A/B to prove the P1 flow-suppression win:** run the same K-sweep TWICE — (a) flows ACTIVE (baseline),
   (b) flows SUPPRESSED (deploy the §2 versions + §1b Apex stamp). `Δcpu(active − suppressed)` at each K =
   the measured per-clone OI-flow cost P1 removes. Also confirm `Get_Product` SOQL count drops by ~N and DML
   rows drop by the re-entrant ~N.
4. **Equivalence assert (no output drift):** for a fixed K, assert the SUPPRESSED clones carry identical
   `Workday_Contract_Line_Type__c`, the 4 date-calc fields, the 2 billing-schedule fields, and (where the
   parent has them) EndDate/PTC vs the ACTIVE-flows baseline — proving suppression + Apex-stamp == flow output.
5. **Cap rule:** `K_cpu` = largest K with cumulative CPU < 8,000 ms (suppressed); `K_dml` = largest K with
   cumulative DML rows < 8,000; set `MAX_SYNC_CLONES = round_down(min(K_cpu,K_dml) × 0.75)`. Re-run whenever
   the active Order pricing procedure version changes materially.
6. **Caveats:** `OrderRepriceInvocable.reprice` / native `submitOrder` may fault standalone outside the
   flow's RLM running context (context-definition binding). If so, fall back to an **end-to-end sandbox
   convert** on synthetic quotes with one Power OLO+partition line at qty=101/201/401/801, reading CPU from
   the debug log at the split invocable's return and the reprice invocable's return. Less precise per-phase
   but real chain order + real context.

---

## 5. TEST ADDITIONS (PowerOrderSplittingServiceTest)

- **A1 — describe-hoist byte-identical field set.** Build a clone via the new `createFullClone` and assert
  its populated-field set equals the set produced by the OLD per-field-describe logic (or assert each
  createable non-null field on the parent equals the clone's value). Guarantees the hoist changed NO output.
- **A2 — clone stamped correctly WITH flows suppressed.** In a test where the OrderItem flows are
  effectively suppressed on clones (clones carry `Is_Split_Line__c=true`), assert each clone has:
  `Workday_Contract_Line_Type__c` = `deriveWorkdayLineType(original)` (re-derived from product boolean);
  the 4 date-calc + 2 billing-schedule fields = parent's values; EndDate/PTC = parent's values (present or
  null, matching parent — no regression).
- **A3 — WCLT re-derive correctness.** Parametrize: (non-services, Is_Subsplit=false) → `FIXED AMOUNT`;
  (non-services, Is_Subsplit=true) → `FIXED AMOUNT BILLING ONLY`; (services) → copies parent's value.
  Include a STALE-parent case (parent WCLT disagrees with its product boolean) and assert the clone gets the
  RE-DERIVED value, NOT the stale parent value.
- **A4 — cap boundary at the (possibly new) value.** Assert: totalClones == MAX_SYNC_CLONES succeeds;
  totalClones == MAX_SYNC_CLONES + 1 returns `success=false` with the friendly message and NO DML
  (savepoint untouched). Drive boundary off the constant so the test tracks any future cap change.
- **A5 — originals/normal lines still stamped.** Assert the in-place-updated original (Is_Split_Line=false)
  and a non-split control line still carry the flow-stamped values (suppression is clone-only).
- **A6 — no SOQL/DML regression (bulk-safe).** Multi-line, multi-clone test asserting `Limits.getQueries()`
  and `Limits.getDmlStatements()` stay within the pre-P1 fixed budget (no per-clone SOQL/DML; the 2 added
  relationship columns add NO extra SOQL).
- **A7 — SC-3210/3368 guard.** Assert the split does NOT mis-stamp a pure qty-split parent's line type
  (parent keeps its correct WCLT; clone derives from product boolean) — protects the line-type family.

(P1 must reach meaningful coverage on this class — the adversarial review noted live coverage is 0/231; the
class currently has 0% and is a deploy blocker, so these tests are also the coverage gate.)

---

## 6. SEQUENCING + RISK

- **P1 is behavior-preserving and independent.** It changes only `createFullClone` / `queryOrderItemsToSplit`
  (internal Apex, byte-identical clone output) and adds an additive entry condition + an explicit Apex stamp
  that reproduces the suppressed flows' output. **No Workday-confirmation dependency** (unlike P3, which
  changes WHICH lines split). P1 can ship before, with, or without P3/P2.
- **Do NOT re-break SC-3210/3368 line-type.** The WCLT re-derive mirrors the ACTIVE V11 product-boolean
  logic; it does NOT reintroduce the `Original_Order_Item__c` reverse-lookup. RE-VERIFY at build that the
  active Set_Workday version is still product-boolean-only (the reverse-lookup survives in 8 obsolete
  versions; daily churn could promote one). Clone the entry-condition version off the CURRENT active version.
- **Do NOT block on the pre-existing ~36% null EndDate/PTC.** It is the OneTime/FIXED-AMOUNT product mix on
  the originals (SC-3411/3420 scope); copy propagates it without regressing. Flag to stakeholders that P1
  does not close it. Switch fields 1–6 from copy to re-derive ONLY if the team wants clones MORE correct than
  the original — not required for P1.
- **Coordinate the line-type flow family with Ben Kozlowski** — P1 adds a new version to both
  Fortra_OrderItem_Set_Dates and Fortra_OrderItem_Set_Workday_Contract_Line_Type. Bump `<description>` to a
  single terse `2026-06-27: …` line.
- **Cap is an estimate.** Keep 200; raise only after §4. A heavier future Order pricing procedure silently
  lowers the real CPU cliff — re-measure on procedure-version change before any cap above 200.
- **DEPLOY AUTH:** all of the above is read-only research. Any UAT deploy/DML (even validate-only) needs a
  fresh explicit ack. Do not deploy on this session's authorization.

---

## 7. What is MEASURED vs ESTIMATED (provenance)

| Quantity | MEASURED / ESTIMATED |
|---|---|
| OrderItem 208 total / 149 createable / 208 accessible | **MEASURED** (sf sobject describe, 3 agents, no drift) |
| getDescribe()/clone today = 208 → 0 after hoist | **MEASURED** (code path + field count) |
| Set_Dates V6 = 0 SOQL / 0 DML; Set_Workday V11 = 2 SOQL + 1 firing recordUpdate | **MEASURED** (retrieved active XML) |
| 3 flow interviews/clone today → 0 after P1 | **MEASURED** (XML + re-entrancy from after-save $Record update) |
| 7 derived fields, all createable+updateable, none read-only | **MEASURED** (FieldDefinition + describe) |
| WCLT re-derive matches 34/34 recent non-split lines; 1 stale parent | **MEASURED** (live SOQL) |
| Live split-eligible population = 4 lines, all N=2 | **MEASURED** (live SOQL under P3 gate) |
| Per-clone CPU reduction ~4×–10× | **ESTIMATED** (component model; needs §4) |
| Post-P1 ceiling N ≈ 300–1,000; binding = reprice CPU | **ESTIMATED** (component model; reprice ms/line unmeasured) |
| Recommended cap 200 now, 300–400 post-measurement | **ESTIMATED** (gated on §4) |
