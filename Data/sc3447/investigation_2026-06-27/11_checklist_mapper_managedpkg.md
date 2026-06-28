# SC-3447 — Checklist / Mapper / Managed-Pkg CPU Surface + Per-Original Double-Fire

**Date:** 2026-06-27 · **Wave-2 (gap-closure)** · **Role:** CPU-surface auditor (read-only)
**Org:** FortraUAT (00DWC000006eUFF2A2) · liam.jeong.c@fortra.com.uat
**Scope:** Close completeness-critic gaps B2 (Checklist + Mapper + createOrderFromQuote cost) and B4
(managed-package trigger surface), and quantify the per-ORIGINAL OrderItem-flow DOUBLE-FIRE that the
wave-1 CPU model (which counts only per-CLONE work) omitted.

**Method:** live Tooling/data queries (ApexClass, ApexTrigger, FlowDefinitionView) + retrieve of
`ChecklistValidationService` source + read of force-app `QuoteToOrderFieldMapper.cls` (271 lines) +
wave-1 files 01–04. No mutations.

**Retrieve artifact:** `Data/sc3447/investigation_2026-06-27/wave2_retrieve/classes/ChecklistValidationService.cls`

---

## TL;DR — the convert has a fixed CPU floor that P1 does NOT touch

1. **ChecklistValidationService** = O(1) per convert. 1 SOQL, 0 DML, no per-line loop. Runs first,
   no faultConnector (P0 should add one). **Negligible CPU.** Not a scaling risk.
2. **QuoteToOrderFieldMapper** = bulkified (fixed 3 SOQL + ≤2 DML, no loop DML) — CONFIRMED. BUT its
   `update toUpdate` over **all** changed OrderItems re-fires the 2 OI flows (Set_Dates V6 +
   Set_Workday V11) **once per original line** — a SECOND firing on top of the createOrderFromQuote
   insert firing. **This is a per-ORIGINAL DOUBLE-FIRE that the P1 `Is_Split_Line__c=false` guard does
   NOT suppress** (originals are `Is_Split_Line__c=false` by design — that's exactly the value the guard
   lets through). Scales **O(distinct-line-count)**, independent of qty/clone count.
3. **createOrderFromQuote** (native RLM/platform action) inserts the Order + all OrderItems, firing the
   2 OI flows once per original line = **O(line-count)**, in the user transaction.
4. **Managed-package trigger surface = EMPTY on the convert path.** Verified: **0** managed-namespace
   Apex triggers on Order/OrderItem/Asset/Contract/OrderItemAttribute; the active Order/OrderItem
   record-triggered flows are **all NamespacePrefix=None** (custom, not packaged). The only managed
   Order/OrderItem flows (`revenue_o2aflows:o2aFlow`, `revenue_o2bsflows:o2bsflows`) are **INACTIVE**.
   No `commerceorders`/`revenue`/`rlm`/subscription-mgmt managed Apex trigger exists at all. RLM /
   `commerceorders.PlaceOrderExecutor` is **platform-native code** (runs in-transaction, accrues to the
   same CPU budget, but registers no customer-visible Apex trigger).
5. **NET:** the convert has a **non-clone, O(line-count) CPU floor** = createOrderFromQuote OI-flow
   firings (×L) + mapper OI-flow re-fire (×L) + ~6 Order-header DMLs each firing the Order-flow cascade
   + reprice tail (one PATCH/OrderItem + ≥4 bulk OrderItem updates re-firing the OI flows on originals).
   **P1 suppresses only per-CLONE OI-flow work.** On a **multi-distinct-line quote** (the backlog has
   these, not just one big line) this floor is material and P1 leaves it entirely in place.

---

## 1. ChecklistValidationService — retrieved & audited (B2)

**Live metadata:** ApexClass `01pWC000001wqaNYAQ`, **ApiVersion 65**, LengthWithoutComments 3023,
Status Active. NOT in force-app repo (confirmed — only the org has it).

**What it does:** validates the Operations Checklist for the quote being converted.

```
@InvocableMethod validateChecklistComplete(List<ValidationRequest> requests)
  for (ValidationRequest request : requests)                      // loop over REQUESTS (=1 in convert)
      validateChecklistForQuote(request.quoteId)
          [ SELECT Id, Item_Name__c, Is_Checked__c, Sort_Order__c   // ONE SOQL per request
            FROM Quote_Checklist_Item__c WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED ORDER BY Sort_Order__c ]
          for (item : allItems) if (!item.Is_Checked__c) add to incompleteItems  // in-memory only
```

**CPU cost = O(1) per convert.** The convert flow passes a **single** quoteId (one MapRequest), so the
outer loop runs once → **exactly 1 SOQL, 0 DML, 0 describe**. The inner item loop is over the quote's
checklist items, a **small fixed set** (operations checklist, single-digit/low-tens rows) — NOT
line-count. There is no per-line, per-OrderItem, or per-clone work anywhere.

**Bulkification:** the invocable IS bulk-shaped at the request level (it loops `requests` and does 1
SOQL **inside that loop** — so if the flow ever passed N requests it would be **N SOQL, un-bulkified**).
In the convert it is called with 1 request, so this latent non-bulk pattern does **not** bite here. Flag
only: it is a SOQL-in-loop over requests, harmless at request-count=1.

**Risk it adds to SC-3447:** essentially zero CPU. Its only SC-3447-relevant defect is the
**missing faultConnector** (file 01; completeness-critic correction F1) — an unhandled checklist
exception faults the whole convert with the generic gack, the same silent-fault class P0 closes for
Split/Mapper. **P0 should add a faultConnector to `Validate_Checklist_Complete` too.**

---

## 2. QuoteToOrderFieldMapper — the per-ORIGINAL DOUBLE-FIRE (B2, the key finding)

**Source:** `force-app/main/default/classes/QuoteToOrderFieldMapper.cls` (271 lines). Bulk-safe as
documented: `mapFields` collects orderIds, then 2 helpers — `mapOrderHeaders` (1 SOQL + ≤1 DML) and
`mapOrderItemFields` (2 SOQL + ≤1 DML). **No SOQL/DML inside any loop. CONFIRMED bulkified.**

### 2a. The header update (L187-189)
```
if (!toUpdate.isEmpty()) { update toUpdate; }   // toUpdate = changed Orders (≈1 per convert)
```
Fires the **Order-header flow cascade once** (one Order). O(1) per convert. (Order cascade quantified in
§4 / B1 cross-ref.)

### 2b. The OrderItem update (L259-260) — THE DOUBLE-FIRE
```
List<OrderItem> toUpdate = ...;       // one patch per OrderItem whose Hardware/Partition/Ship-To changed
if (!toUpdate.isEmpty()) { update toUpdate; }   // L260 — bulk DML over ALL changed OrderItems
```
This `update` runs **BEFORE `SplitPowerOrderLines`** (chain order: createOrderFromQuote → **Mapper** →
Split → Reprice → Activate, file 01 §2). At this point the only OrderItems on the order are the
**ORIGINALS** (one per quote line) — the clones don't exist yet. So this bulk update touches the
originals and **re-fires both record-triggered OrderItem flows on every changed original**:

- `Fortra_OrderItem_Set_Dates` V6 — RecordBeforeSave, **CreateAndUpdate** (fires on update). 0 SOQL/0 DML.
- `Fortra_OrderItem_Set_Workday_Contract_Line_Type` V11 — RecordAfterSave, **CreateAndUpdate** (fires on
  update). 1 SOQL (`Get_Product`) + 1 recordUpdate on `$Record` → **re-fires Set_Dates again**.

(Both flows are `CreateAndUpdate` with NO entry filter — confirmed live, file 02 §1. So an UPDATE fires
them exactly as an INSERT does.)

### 2c. Quantifying the double-fire
Let **L = number of distinct quote lines** (originals). For each original whose Hardware/Partition/Ship-To
field changes (the common case — these are exactly the fields the mapper exists to set, so most lines
change), the OI-flow re-entrancy bundle runs:

| When | Trigger | Per-original flow work |
|---|---|---|
| **Fire #1** | createOrderFromQuote **inserts** the original | Set_Dates (insert) + Set_Workday (1 SOQL + 1 $Record DML) + Set_Dates re-fire |
| **Fire #2** | Mapper **updates** the original (L260) | Set_Dates (update) + Set_Workday (1 SOQL + 1 $Record DML) + Set_Dates re-fire |

→ **Per original line, the OI-flow bundle runs TWICE** (insert + mapper-update), i.e.
**2 × Get_Product SOQL + 2 × $Record recordUpdate + 4 × Set_Dates execution** per original.

**Aggregate over a multi-line quote = O(2·L).** The wave-1 CPU model counted only the per-CLONE firings
(the (qty−1) clones inside the split). It **missed both fire #1 and fire #2 on the L originals.** For a
quote with many *distinct* lines (e.g. 50 different Power+non-Power lines, each modest qty), this
per-original cost is the dominant non-clone CPU — and it is paid **even if no line is high-qty**.

### 2d. Does P1's `Is_Split_Line__c=false` guard suppress it? **NO.**
P1 adds entry condition `Is_Split_Line__c = false` to both OI flows so **clones** (which carry
`Is_Split_Line__c=true`, file 02 §6) are skipped. **Originals are `Is_Split_Line__c=false` by design**
(the mapper runs before the split; the split later flips slot-0 originals to `false` too). `false` is
exactly the value the guard **lets through** → both fire #1 (insert) and fire #2 (mapper update) on every
original **survive P1 untouched.** P1 reduces per-clone work to ~0 but does **nothing** to the
per-original double-fire.

### 2e. Mitigation options (for the design)
1. **Idempotency already trims it partially:** the mapper only adds an OrderItem to `toUpdate` when a
   field actually changes (L234-256 each compares `oi.X != sourceQLI.X`). A line with no
   Hardware/Partition/Ship-To delta is skipped → fire #2 only hits lines that genuinely change. But Power
   lines typically DO carry Hardware/Partition refs, so most change.
2. **Transient custom-permission bypass on the mapper's bulk update** (recommended, surgical): add an
   entry condition to BOTH OI flows of the form `Is_Split_Line__c = false AND $Permission.Bypass_OI_Flow
   = false`, and have the convert running context (or the mapper, via a `System.runAs`-equivalent /
   assigned permission-set-license custom permission) set the bypass for the mapper's update only. Cleaner:
   gate the flows on a **Custom Permission** that is assigned to the convert integration/service user, so
   during convert the OI flows are skipped on the mapper update AND the createOrderFromQuote insert, and
   the split's Apex explicitly stamps the derived fields (the P1 stamp-on-clone copy, file 04 §4b, extended
   to originals). This removes BOTH fires, not just the clone work. **This is the only way to kill the
   per-original double-fire — an `Is_Split_Line__c` filter cannot, because originals are `false`.**
3. **Make the mapper not re-trigger:** the mapper could set its fields in the SAME DML that
   createOrderFromQuote's downstream already does, or move the Hardware/Partition mapping into a
   before-save context — but createOrderFromQuote is a native action whose insert the mapper cannot
   piggyback. The custom-permission bypass (option 2) is more practical than restructuring the mapper.
4. **Accept it for P1, size it explicitly:** if L is small (typical single-big-line quotes), 2·L flow
   bundles is cheap and P1 alone suffices. The decision hinges on the multi-distinct-line backlog
   distribution (recommend a build-time `Limits.getCpuTime()` measurement on a 50-line convert).

---

## 3. createOrderFromQuote (native RLM action) — O(line-count) (B2)

`Call_Create_Order_From_Quote` (flow action `createOrderFromQuote`, CurrentTransaction, file 01 §2) is the
**native platform/RLM commerce action**. It inserts the Order header + one OrderItem per quote line (the
originals). That **insert fires the 2 OI flows once per original line** (fire #1 in §2c). So before the
split or mapper even run:

- **O(L)** OI-flow bundles = L × (Set_Dates insert + Set_Workday[1 SOQL + 1 DML] + Set_Dates re-fire).
- Plus the native action's own internal pricing/context-mapping work (platform code, opaque, accrues to
  the same CPU budget).

This is unavoidable platform behavior (you can't stop createOrderFromQuote from inserting the lines), but
the **OI-flow firings it triggers** are suppressible by the same custom-permission bypass (§2e option 2).
At a many-distinct-line quote this insert-time O(L) firing is a real, uncounted floor.

---

## 4. Managed-package / RLM trigger surface (B4) — EMPTY on the convert path

**Verified live (Tooling `ApexTrigger` + data `FlowDefinitionView`):**

### 4a. Apex triggers
| Object | Result |
|---|---|
| Order | **1 trigger: `OrderValidationTrigger`** (Active, api 65, **NamespacePrefix=None** → custom, not packaged). Before-insert (file 01/B1). O(1) per convert. |
| OrderItem | **0 triggers.** |
| Managed (namespace != null) on Order/OrderItem/Asset/Contract/OrderItemAttribute | **0.** |
| Any `commerceorders`/`revenue`/`rlm`/subscription-mgmt namespaced Apex trigger (any object) | **0.** |

568 managed Apex triggers exist in the org (omnistudio, pse, c2g, ff* FinancialForce, salesintelio, LID,
etc.) but **none are on the convert-path objects** and **none belong to a commerce/RLM namespace.**

### 4b. Record-triggered flows on Order ("Order") — 23 total, active set
| Flow | NS | TriggerType | RecordTriggerType | Fires on convert? |
|---|---|---|---|---|
| Order_Before_Insert_Update_Sync_Status | None | RecordBeforeSave | CreateAndUpdate | **YES** (insert + every update) |
| Fortra_Order_Set_Payment_Terms | None | RecordAfterSave | **Create** | insert only |
| Fortra_Order_Workday_Contract_ID | None | RecordAfterSave | CreateAndUpdate | YES (insert + updates) |
| Fortra_Order_Sync_Address_From_Place | None | RecordAfterSave | **Update** | each Order update (mapper/reprice/activate) |
| Fortra_Order_to_Billing_Schedule | None | RecordAfterSave | **Update** | each Order update — **B1: confirm not per-OrderItem** |
| Fortra_Order_After_Update_Platform_Event_Workday | None | RecordAfterSave | Update | each Order update (publishes PE) |
| Order_Submission_to_Revenue_Orchestrator | None | RecordAfterSave | Update | each Order update |
| Fortra_Assetize_Order | None | RecordAfterSave | Update | post-activate (SC-3415/3419 path) |
| Fortra_Amendment_Sync_To_Renewal_Opp | None | RecordAfterSave | CreateAndUpdate | YES |
| Fortra_Renewal_Contract_Succession | None | RecordAfterSave | CreateAndUpdate | YES |
| Order_Disallow_delete_for_Globalscape_Integration_User | None | RecordBeforeDelete | Delete | n/a (delete-only) |

**INACTIVE (do NOT fire):** `revenue_o2aflows:o2aFlow`, `revenue_o2bsflows:o2bsflows` (the only managed
Order flows), plus `Create_Asset_From_Order`, `Fortra_Order_Assetize_Order`,
`Fortra_Order_After_Save_Set_Workday_Contract_Line_Type`, `Fortra_Order_Workday_Status`,
`Fortra_Order_Set_Workday_and_PO_Fields`, `Fortra_Order_Integration_Check(_Notification)`,
`Fortra_Order_Places_Primary_Check`, `Order_After_Update_Platform_Events`,
`Warn_Quote_Order_Currency_Mismatch`.

**Key:** every ACTIVE Order flow is **custom (NamespacePrefix=None)**. There is **no managed-package Order
flow firing** during convert. The Order-header cascade is real (B1) but it is **all first-party**, and it
is **O(1) per Order DML** (per-header, not per-line) — EXCEPT the open B1 question on
`Fortra_Order_to_Billing_Schedule` v10 (Update): does it create one Billing Schedule child per OrderItem?
If so it is a hidden O(L) contributor that survives P1. (Wave-1/B1 noted it has 1 recordUpdate and a
PaymentTerm ref, not an obvious per-line loop; full body not traced here — flag for the Order-cascade
agent.) Note several Order flows are **Update-only** (`Sync_Address_From_Place`, `to_Billing_Schedule`,
`After_Update_PE_Workday`, `Submission_to_Revenue_Orchestrator`), so they fire on the **mapper header
update + the ~4 reprice Order updates + activate update** — i.e. roughly **5-6× per convert**, each O(1).

### 4c. Record-triggered flows on OrderItem ("Order Product") — confirmed
Only the 2 active insert/update flows (Set_Dates V6, Set_Workday V11, both NS=None) + 1 delete-only flow.
**No managed-package OrderItem flow.** (Matches file 02 §1.)

### 4d. RLM / commerceorders is platform-native, not a registered-trigger package
`createOrderFromQuote`, the OrderRepriceInvocable Force reprice
(`commerceorders.PlaceOrderExecutor.execute(..., PricingPreferenceEnum.Force, ...)`, file 03 §1), and
assetize all invoke **platform-native Revenue Cloud / `commerceorders` code**. This runs inside the user
transaction and **its CPU accrues to the same 10,000 ms budget** (cheatsheet footnote-5), but it does
**not** register Apex triggers or active flows you can see/disable on Order/OrderItem. **The Force reprice
runs the V16 pricing procedure over all N lines = managed/platform-package CPU inside the user txn** — an
O(N) managed-pkg CPU contributor that is NOT a trigger surface and is NOT suppressible by flow/trigger
edits. (This is the same point as the reprice O(N) tail, B3.)

**B4 verdict:** there is no hidden managed-package *trigger/flow* surface accruing CPU during convert. The
managed-package CPU is entirely the **native Reprice/createOrderFromQuote execution itself** (already
known, O(N)), not extra packaged triggers firing on the DMLs.

---

## 5. NET — the fixed/O(line-count) CPU floor BEFORE any Power split, and what P1 leaves

Define **L = distinct quote lines (originals)**, **N = Σ(qty−1) = total clones**. P1 drives the per-clone
OI-flow work toward ~0 (and describe-hoist drives the per-clone describe from 208·N → 208 total). What
remains — the **non-clone floor** — is:

| Contributor | Scales | Suppressed by P1? | CPU character |
|---|---|---|---|
| ChecklistValidationService | O(1) | n/a | negligible (1 SOQL) |
| createOrderFromQuote OI-flow firings (fire #1) | **O(L)** | **NO** (originals are `Is_Split_Line__c=false`) | L × (Set_Workday SOQL+DML + 2×Set_Dates) |
| createOrderFromQuote native platform work | O(L)+platform | NO | opaque platform CPU |
| Mapper OI-flow re-fire (fire #2) | **O(L)** | **NO** (same reason) | L × (Set_Workday SOQL+DML + 2×Set_Dates) |
| Mapper own Apex | O(L) cheap | n/a | 3 SOQL + ≤2 DML, in-memory loops |
| Order-header flow cascade | **O(1)·(~6 DMLs)** | NO | first-party flows, per-header; **B1: confirm Billing_Schedule not O(L)** |
| OrderValidationTrigger | O(1) | NO | one before-insert |
| Reprice tail (B3) | **O(N+L)** | clones yes, originals/non-split NO | 1 PATCH/OrderItem + ≥4 bulk OI updates re-firing OI flows on originals; V16 proc over all lines; 92KB PartnerNetPricePosthook |
| Activate | O(1) | NO | one Order update + its flow cascade |

**Answer to task Q5:** **YES — there is a material non-clone CPU cost that survives P1.** The floor is
**O(line-count)**, dominated by the **OI-flow DOUBLE-FIRE on originals** (createOrderFromQuote insert +
mapper update = **2·L** flow bundles, each a Get_Product SOQL + a $Record DML + two Set_Dates runs) plus
the **reprice tail's re-firing of those same flows on originals** (B3) and the V16 procedure running over
all lines. P1's `Is_Split_Line__c=false` guard **structurally cannot** suppress any of this because every
original (and every non-split line) is `Is_Split_Line__c=false` — the value the guard admits.

- On a **single-high-qty-line quote** (L=1, large N): P1 is decisive — the floor (2·1 flow bundles + ~6
  O(1) Order DMLs) is tiny; the win is killing the per-clone work. P1 alone likely converges (subject to
  the reprice tail and the DML-row ceiling, file 04 §5).
- On a **multi-distinct-line quote** (large L, modest per-line qty — present in the backlog): P1 leaves
  the entire **O(2·L)** OI-flow floor + the reprice O(L) re-fire in place. **P1 may NOT converge** if L is
  large enough that the per-original double-fire + reprice tail alone exhaust the budget. This case needs
  either the **custom-permission OI-flow bypass** (§2e option 2, kills both fires on originals) and/or the
  async tail (P2/P3).

**Recommended design additions (this wave):**
1. Add a **Custom-Permission OI-flow bypass** (assigned to the convert running user) so the OI flows are
   skipped on BOTH the createOrderFromQuote insert AND the mapper update, with the split/mapper Apex
   explicitly stamping derived fields on originals (extend the P1 stamp-on-clone copy to originals). This
   is the ONLY mechanism that removes the per-original double-fire; `Is_Split_Line__c` cannot.
2. Keep P1's `Is_Split_Line__c=false` guard for clone suppression, but **state explicitly in P1 sizing
   that it does not touch the O(L) original floor**, and add a build-time `Limits.getCpuTime()`
   measurement on a ~50-distinct-line convert before declaring P1 sufficient.
3. Add a **faultConnector to `Validate_Checklist_Complete`** (P0; F1).
4. Confirm `Fortra_Order_to_Billing_Schedule` v10 does **not** create one child per OrderItem (B1) — if
   it does, it's a hidden O(L) contributor surviving P1 and the bypass alike.

---

## Drift / confidence
- ChecklistValidationService: retrieved fresh this session — **trustworthy** (api 65, not in repo).
- QuoteToOrderFieldMapper: read from force-app; wave-1 (file 04 §1) confirmed force-app == live for the
  Power class; mapper drift not separately re-diffed this session (low risk — flow chain V27 unchanged).
- Managed-trigger/flow enumeration: live this session via Tooling/data API — **authoritative as of
  2026-06-27.** `FlowDefinitionView` not queryable via `-t` (Tooling) here; used the standard data API
  (matches wave-1 method).
- OI-flow CreateAndUpdate / no-entry-filter facts: cross-confirmed file 02 §1 + re-queried this session.
