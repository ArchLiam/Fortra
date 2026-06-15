# SC-3411 — Cannot activate Order (termed line missing EndDate/PricingTermCount; "Update Status" masks the real error)

| | |
|---|---|
| **Ticket** | SC-3411 (Salesforce-Coastal) — Priority **Critical** — CRM Sprint 14 |
| **Reporter** | Joe Romo |
| **Assignee** | Liam Jeong |
| **Repro** | Order **00095503** (FortraUAT) — Quote "Q-Wren - Test Pricebook 2" |
| **Status** | ✅ **RESOLVED** in UAT 2026-06-15 — order Activated; P0+P1 flow fixes deployed |
| **Scope** | **UAT ONLY — do NOT touch Prod** (prod rollout is a follow-up) |
| **Full dossier** | `Data/order-status-rca/RCA_ORDER_STATUS_ACTIVATION.md` + `evidence/` |

---

## 1. Summary

Order status could not be changed to **Activated** — failing via **both** the custom "Update Status" quick action (generic *"unhandled fault"*) and the Details-page inline status edit (real *"EndDate/PricingTermCount required"* error). One upstream cause produced **two AND-gated platform blockers**, and a flow defect masked the real error.

---

## 2. Root cause

### Two AND-gated blockers (both must clear in the same save)
1. **Termed line missing term dates.** OrderItem `802WC00000OpopoYAB` — *Active Defense BEC Threat Intelligence Service* (`ES-CEP-RSL-ACTIDB`), selling model **"Term Based - Annual" (TermDefined)** — had `EndDate = null` and `PricingTermCount = null`. RLM blocks activation of any order with an un-dated termed line. (The two OneTime lines are not affected — term fields are not required for them.)
2. **Incomplete reprice.** `ValidationResult = TransactionIncomplete`, `LastPricedDate = null` → RLM also blocks with *"prices aren't updated, click Reprice All."* (SC-3308 pattern.) **Any OrderItem edit re-arms this**, so the order of operations is **set fields → Reprice All → Activate**.

### Origin of the null term fields
`EndDate`/`PricingTermCount` are **pricing-engine/term-derived**, not rep-entered. They were already null on the **source quote line** (`0QLWC000003ehSj4AI`) and inherited on convert — **not** a quote→order mapping bug. **Reprice does NOT derive them** (proven via FINEST log): reprice recalculates *price* only. The OrderItem before-save flow *"Set Dates"* runs on every save but only wrote **custom billing** fields, never the **standard** `EndDate`/`PricingTermCount` — that was the gap. Scope is narrow: **12 of ~114,890** termed order lines org-wide had null EndDate (~0.01%), a recent test cluster correlating with the V9→V12→V13 pricing-procedure churn.

### Why "Update Status" masked the error (flow defect)
The "Update Status" quick action = QuickAction `Order.Order_Complete` → screen flow **`Fortra_Order_Submission_Check`** (active **V13** at time of report). Its picker exposes *all* `Order.Status` values. Selecting any value other than "Order Complete" (e.g. **Activated**) routes to the `Update_Order_Stage` record-update element, which **had no fault connector** → the real platform error was swallowed and shown as the generic *"unhandled fault."* (The "Order Complete" branch had a fault handler.) That branch also **bypasses** the `OrderSubmissionValidator` pre-check.

---

## 3. Resolution

### Fixes deployed to FortraUAT — 2026-06-15 (UAT only)
| Priority | Flow | New version | Change |
|---|---|---|---|
| **P0** | `Fortra_Order_Submission_Check` | **V14** (def `300WC00000PCNSHYA5`) | Added `faultConnector` on `Update_Order_Stage` → `Error_Screen` (shows `{!$Flow.FaultMessage}`). The action now surfaces the **real** platform error instead of "unhandled fault." |
| **P1** | `Fortra_OrderItem_Set_Dates` | **V6** (def `300WC00000Qqd9ZYAR`) | Added decision `Is_Termed_Blank` (SellingModelType=TermDefined **and** EndDate/PricingTermCount IsNull) → `Backstop_Std_Term_Fields` recordUpdate stamping standard `EndDate` (existing `Calculated_To_Date`, flat 12-mo) + `PricingTermCount` (=1 when blank). Self-gated → never touches the ~114K healthy or OneTime lines. **Runtime-proven** (nulled fields → backstop re-populated in same save). |

Deployed via MDAPI staging (`Data/order-status-rca/stage/unpackaged`) — dry-run + deploy both **Succeeded**. (Note: the IDE XSD linter throws false positives on Flow `recordUpdates`/`value`; `sf project deploy --dry-run` is authoritative.)

### Order 00095503 unblocked & activated
1. Set `EndDate = 2027-06-14`, `PricingTermCount = 1` on the termed line (values proven vs 114,839 Annual records: PTC always 1, EndDate = ServiceDate + 1yr − 1 day).
2. **Reprice All** (UI) — cleared `ValidationResult` to null **and** applied the missing discount (termed line 94,000 list → **77,080 net**; order total 94,256 → **77,336**).
3. **Activated** 2026-06-15 20:30 UTC. `Status = Activated`, `ValidationResult = null`, term fields held. ✅

Correct values reference: **PricingTermCount = 1** for Annual (vs 114,839 records; 0 use 12). **EndDate = ServiceDate + 1 annual term − 1 day**.

---

## 4. New findings (separate tickets recommended)

1. **`OrderRepriceInvocable` fails on maintenance-decomposed orders.** The SC-3308 programmatic pre-activation reprice (`commerceorders.PlaceOrderExecutor` Force) completes the pricing pass, but its post-pricing `MaintenanceOrderDecompositionService.persistFromWork()` throws `INVALID_FIELD_FOR_INSERT_UPDATE: You can't edit the Unit Price because the Order Product has related Order Product Detail records [UnitPrice]` on the maintenance line (`PIA-PIA-RNM-PIAMBK`, `802WC00000OpopqYAB`). That exception skips `clearOrderValidationResult`, so `ValidationResult` stays `TransactionIncomplete`. **UI "Reprice All" does not run that step** (which is why the UI path works). → Breaks Q2O auto-activation for maintenance orders independent of SC-3411.

2. **Workday sync risk on 00095503 (extendedAmount mismatch).** Line `802WC00000OpoppYAB` has `TotalLineAmount = 301.75` ≠ `NetTotalPrice = 256.49` (Δ45.26); header total = net. If `Workday_Sync_Status` flips Pending→Fail it is the **documented Mule `extendedAmount ← TotalLineAmount` bug** (see scXXXX / SC-3347 family), **not** SC-3411.

---

## 5. Remaining roadmap (not in scope for the UAT fix)

- **P1-quote (true root):** derive standard `EndDate`/`PricingTermCount` for TermDefined lines at the **Quote** so the null never reaches the order.
- **P2 guard:** pre-activation validation/derivation on the "Activated" branch (currently bypasses validation); tighten the status picker.
- **Data:** backfill the other ~11 affected termed lines (now self-heal on next save/reprice).
- **Prod rollout** of P0 + P1 (currently UAT only).
- Open ticket items #4.1 (`OrderRepriceInvocable`) and #4.2 (Workday Mule extendedAmount).

---

## 6. Evidence

- `Data/order-status-rca/RCA_ORDER_STATUS_ACTIVATION.md` — full adversarially-verified RCA dossier.
- `evidence/logs/` — FINEST reprice logs, P1 self-test, programmatic-reprice failure log.
- Deployed flow versions: `Fortra_Order_Submission_Check` V14, `Fortra_OrderItem_Set_Dates` V6 (verified active via Tooling API).
- All facts re-verified live against FortraUAT on 2026-06-15.
