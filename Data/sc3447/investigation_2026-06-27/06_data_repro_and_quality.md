# SC-3447 — Live Data: Repro Quote, Split-Line Data Quality, Blocked Orders
Read-only SOQL investigation, FortraUAT (OrgId 00DWC000006eUFF2A2), 2026-06-27. Author: Liam (subagent).

> Scope: Quote→Order convert fails `Apex CPU time limit exceeded` (FLOW_INTERVIEW_LIMIT_EXCEEDED), full rollback, on quotes with a high-quantity `Solution_Group__c='Power'` line. PowerOrderSplittingService explodes one qty-N Power line into N qty-1 OrderItem clones in a single sync transaction. Client sells up to 750,000 qty.

---

## 1. Repro quote `0Q0WC000003AuQb0AK` (Q-00781200) — GONE / NOT FOUND

**The repro quote no longer resolves in FortraUAT today.**
- `SELECT … FROM Quote WHERE Id='0Q0WC000003AuQb0AK'` → **0 rows**.
- `WHERE Name='Q-00781200'` → 0 rows. `WHERE Name LIKE 'Q-007812%'` → 0 rows.
- 166,510 Quotes exist total, so the object/query is fine — this specific quote is gone (deleted or hard-refreshed). Could not confirm recycle-bin state: `queryAll` REST blocked (`sf org display` redacts the access token, so curl returns INVALID_AUTH_HEADER; `Quote` not supported on Tooling API).
- **Consistent with the KNOWN-STATE warning of heavy daily churn.** Do NOT rely on this Id going forward.

**What IS still confirmed:**
- Repro product `01tWC00000DD11GYAT` "Abstract" still exists and matches the profile: `Solution_Group__c=Power`, `Power_Split_Type__c='Order Line Only'`, `IsActive=true`, `Is_Subsplit_Product__c=true`. (Note: the split-type field is `Power_Split_Type__c`, not `Split_Type__c`; `Solution_Group__c`/`Power_Split_Type__c` live on **Product2**, not on QuoteLineItem.)

**Schema notes corrected vs prior investigation:**
- This is an RLM org. `Quote` has NO `SBQQ__*` fields and NO RecordType. Convert is driven by Quote custom fields `Create_Order_from_Quote__c` (boolean trigger) and `Original_Order_Id__c` (lookup→Order, reverse pointer set after convert). `Quote.Status` picklist: Draft, Needs Review, In Review, Approved, Rejected, Presented, Accepted, Denied, Ordered.
- OrderItem split FK is the CUSTOM `Original_Order_Item__c`; the STANDARD `OriginalOrderItemId` is unused (0 rows). Billing date fields on OrderItem are `Billing_Schedule_From_Date__c` / `Billing_Schedule_To_Date__c` (there is no `Billing_From/To_Date__c`).

---

## 2. Has anyone already created an Order from this quote? — N/A (quote gone)

The repro quote is gone, so no live linkage to inspect. No FAILED convert artifact survives a CPU rollback anyway (full rollback = nothing persists; the only trace is the AsyncApexJob/flow error log, not data rows). General fact: a CPU-exceeded convert leaves **zero** OrderItems behind by design.

**A live, much worse repro candidate exists** (see §6): quote `0Q0WC000002QEKV0A4` ("DO NOT SEND December 2024 ELA Renewal", Status=Won) carries Power "Order Line Only" lines at **qty 999,999**.

---

## 3. Split-line data quality (OrderItem WHERE `Is_Split_Line__c=true`)

**There are only 66 split OrderItems in the entire org** (asked for 200, got all 66). PowerOrderSplittingService has produced very little real output because the feature blows up at scale; only small Power orders have ever gotten through.

Data quality across all 66:

| Field | NULL / zero count | % |
|---|---|---|
| `Workday_Contract_Line_Type__c` | 3 / 66 | **5%** |
| `Original_Order_Item__c` (split FK) | 3 / 66 | 5% |
| `Billing_Schedule_From_Date__c` | 25 / 66 | **38%** |
| `Billing_Schedule_To_Date__c` | 25 / 66 | **38%** |
| `EndDate` | 24 / 66 | **36%** |
| `ServiceDate` | 24 / 66 | 36% |
| `PricingTermCount` (0 or null) | 24 / 66 | **36%** |

`Workday_Contract_Line_Type__c` values present: FIXED AMOUNT (43), FIXED AMOUNT BILLING ONLY (20), null (3).

Era breakdown (CreatedDate): spread Feb–Jun 2026; largest single-day batches 2026-04-16 (16), 2026-05-05 (9), 2026-06-18 (8), 2026-06-22 (8). The ~36% date/term gaps are NOT a single bad era — they recur across recent dates including 2026-06, i.e. the term/billing-date stamping on clones is currently unreliable (consistent with the SC-3411/SC-3420 backstop history).

**Implication for the fix design:**
- `Workday_Contract_Line_Type__c` is stamped reliably (95%) by the per-clone RecordAfterSave flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type` V11 — but that flow is exactly the per-clone overhead (Get_Product SOQL + recordUpdate → re-entrancy re-fires Set Dates) that multiplies CPU.
- The date/term fields are NOT reliably stamped even WITH the flows running (~36% null today). So **suppressing the per-clone record-triggered flows during the split would lose the one thing they do well (line type) without fixing the things already broken.** Any redesign that bulk-creates/async-creates clones MUST Apex-stamp `Workday_Contract_Line_Type__c`, billing schedule dates, EndDate, ServiceDate, and PricingTermCount itself (or run a single bulk post-pass), rather than relying on per-row flow re-entrancy. Stamping in Apex is in fact an OPPORTUNITY to close the existing 36% gap, not just a cost.

---

## 4. Real Power-split orders: how large, did they activate / reach Workday?

24 distinct Orders contain split lines. Status: **9 Order Complete, 9 Activated, 6 Draft** (18/24 have an ActivatedDate).

**Max split lines on any one order = 9** (Order 00014777 / `801WC00000h6rAYYAY`, Order Complete, activated 2026-05-05). Per-order split counts top out at: 9, 6, 4, 4, 4, 3, 3, then 2s.

Workday outcome on the largest/most-recent split orders:

| Order | Splits | SF Status | Workday_Overall_Status__c | Workday_Sync_Status__c |
|---|---|---|---|---|
| 00014777 | 9 | Order Complete | Not Success | Failure |
| 00095545 | 3 | Order Complete | Not Success | Pending |
| 00095559 | 4 | Order Complete | **Success** | **Success** |
| 00095566 | 6 | Order Complete | Not Success | Failure |
| 00095586 | 2 | Order Complete | Not Success | Failure |

`OrderItem.Workday_Sync_Status__c` is null on all 66 split lines (sync state is tracked on the Order header, not the line).

**Empirical safe ceilings:**
- **Full end-to-end success (incl. Workday) ceiling = 4 split lines** (00095559, 2026-06-18). It is the ONLY large-ish split order with Workday `Success`. The Workday failures on the 6- and 9-split orders are likely SC-3368/SC-3441 line-type / pricing issues, not CPU — but the point stands that no Power order above 4 splits has fully succeeded.
- **Salesforce-activation ceiling = 9 split lines** (00014777; Workday then failed).

The big multi-thousand-line orders (2,003 lines `801WC00000hHe9bYAC`; 1,244 lines `801WC00000hHaXyYAK`) are **red herrings**: both are **Draft, never activated, 0 split lines, 1 distinct product each** — pre-existing bulk loads, NOT PowerOrderSplittingService output. They do not represent a successful high-volume convert.

> Bottom line: the empirical safe ceiling is **single digits** (4 fully-clean, 9 SF-activated). The client requirement of up to **750,000** is ~5 orders of magnitude beyond anything that has ever worked.

---

## 5. `Original_Order_Item__c` usage + SC-3210/3368 conflation cross-check

- `OrderItem.Original_Order_Item__c` populated: **63** rows. `OriginalOrderItemId` (standard): **0** rows.
- Parent-vs-child product comparison (`Original_Order_Item__r.Product2Id` vs `Product2Id`): **63 / 63 SAME product (100% qty-split). 0 different-product (license/maint subsplit).**

**Cross-check result:** In current live OrderItem data, `Original_Order_Item__c` is used **exclusively** by PowerOrderSplittingService as the qty-split FK (child=parent product). The SC-3210/SC-3368 license→maintenance subsplit pattern (child product ≠ parent product) does **not** appear in any OrderItem here — confirming the memory note "the license→maintenance FK-split was never in the OrderItem build; it's PowerOrderSplittingService's qty-split FK." 

**Conflation risk if we change split behavior:** LOW within OrderItem itself (no competing semantic on this field today). HOWEVER `Workday_Contract_Line_Type__c` derivation (the `Set_Workday_Contract_Line_Type` flow family, SC-3210/3368) does a parent/child Product2 reverse-lookup and has historically mis-stamped pure qty-split parents. Since every split child is same-product as its parent, the safe invariant for any redesign is: **a qty-split clone must inherit the parent's line type verbatim (do NOT re-derive via reverse-lookup on clones).** If the fix bulk-stamps line type in Apex by copying the parent, it both removes the per-clone flow CPU AND sidesteps the SC-3368 mis-stamp regression.

---

## 6. Blast radius (latent, not yet converted) — LARGE

Power products with `Power_Split_Type__c='Order Line Only'`, qty>1, on quotes NOT yet Ordered:

- **18,136** such QuoteLineItems exist.
- **1,573** are at qty > 100 (each convert → 100s–1000s of clones).
- **456** at sentinel qty ≥ 9,999; of those **402 at 100,000–1,000,001**. **Max qty = 999,999.**

Qty buckets:

| Qty range | # QLIs |
|---|---|
| 1–10 | 13,462 |
| 10–50 | 2,417 |
| 50–100 | 684 |
| 100–500 | 794 |
| 500–1,000 | 179 |
| 1,000–10,000 | 177 |
| 10,000–100,000 | 21 |
| 100,000–1,000,001 | 402 |

Concrete worst-case repro candidate (live, replaces the gone repro quote): **Quote `0Q0WC000002QEKV0A4`** "DO NOT SEND December 2024 ELA Renewal - $436,063.58", Status=Won, `Create_Order_from_Quote__c=false`, no linked Order, product `01tWC00000DD19UYAT` "Cybersecurity-RenewalMaintenance" (Power / Order Line Only) at **qty 999,999** on multiple lines. The splitter loop `for(i=1;i<qty;i++)` would attempt ~999,998 clone iterations in one sync request → instant CPU blowout. (Flagged "DO NOT SEND", so safe as a reference but do NOT convert it.)

> These quantities confirm the memory note: Power Quantity is a **seat/user/"unlimited" sentinel count**, NOT a machine count. Splitting one row per unit at sentinel quantities is the architectural mismatch at the root of SC-3447 — there is no quantity at which "1 OrderItem per unit" is viable when the unit is a seat count in the hundreds of thousands.

---

## Net conclusions for SC-3447

1. Repro quote is gone (churn) — use qty-distribution + the 999,999 ELA quote as the live evidence instead.
2. The real ceiling is brutal: max 9 SF-activated, max 4 Workday-clean Power-split lines ever. Requirement is up to 750,000.
3. Per-clone flows reliably stamp line type (95%) but leave billing/term/end dates ~36% null — so a flow-suppression redesign REQUIRES Apex (or bulk post-pass) stamping of WCLT + billing-schedule dates + EndDate + ServiceDate + PricingTermCount.
4. `Original_Order_Item__c` is 100% qty-split (same product) in live data — no OrderItem-level SC-3210/3368 conflation; the conflation risk lives only in the line-type reverse-lookup flow, which an Apex parent-copy approach would eliminate.
5. Blast radius is broad: 18,136 latent split QLIs, 1,573 over qty 100, 402 in the 100k–1M range. A throttle/guard is needed independent of the eventual redesign.

### Queries used (all read-only)
- Quote header/name/like lookups on `0Q0WC000003AuQb0AK` / `Q-00781200` → 0 rows.
- `Product2 WHERE Id='01tWC00000DD11GYAT'` (Abstract confirm).
- `OrderItem WHERE Is_Split_Line__c=true` (66 rows, full sample) — null analysis + era + per-order grouping.
- `OrderItem WHERE Original_Order_Item__c!=null` w/ `Original_Order_Item__r.Product2Id` (63 rows) — parent/child product comparison.
- `Order WHERE Id IN (split-line orders)` + Workday header fields.
- `OrderItem GROUP BY OrderId ORDER BY count DESC` (largest orders; 2003/1244 = non-split Draft red herrings).
- `QuoteLineItem WHERE Product2.Solution_Group__c='Power' AND Power_Split_Type__c='Order Line Only' AND Quantity>1 AND Quote.Status!='Ordered'` (18,136; qty distribution; 999,999 max).
