# Discounted orders fail Workday sync — MuleSoft maps contract-line `extendedAmount` from list price, not net ("Contract Amount ≠ Contract Line Amount")

> Space: Salesforce-Coastal (SC) · Type: Task (recommend sub-task of [SC-3143](https://helpsystems.atlassian.net/browse/SC-3143)) · Sprint: CRM Sprint 14
> Status: **Investigation complete — fix owned by the MuleSoft integration team (not Salesforce).**
> Rename `scXXXX` → real Jira key once created.

## Details

| Field | Value |
|---|---|
| **Reporter** | Joe Romo (Teams) — *"MuleSoft mapping issue."* **Confirmed correct.** |
| **Assignee** | Liam Jeong (investigation) → **integration team for the fix** (Keith Irwin / SC-3143 epic assignee Andy Kumar) |
| **Parent / epic** | [SC-3143 — Integration E2E Testing Path](https://helpsystems.atlassian.net/browse/SC-3143) |
| **Priority** | 🟠 High |
| **Components** | SF RCA / Integration (MuleSoft) |
| **Labels** | Bug, CRM, RCA, Workday, MuleSoft, Integration |
| **Environment** | FortraUAT (`fortra--uat.sandbox.lightning.force.com`) |
| **Clean repro** | [Order 00095381](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kML51YAG/view) (`801WC00000kML51YAG`) |

---

## Summary

Any order with a **discounted line (net < list)** fails to sync to Workday with:

> `The Contract Amount and the Contract Line Amount must be equal to Submit Contract.,Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.`

**Root cause:** MuleSoft's `Submit_Customer_Contract` builder sources the per-line `extendedAmount` from the **list/gross** order-line total (`OrderItem.TotalLineAmount`), while the header `currentContractAmount` and the line `unitCost` are **net**. On a discounted line the bases diverge, so `SUM(extendedAmount) ≠ currentContractAmount` and Workday rejects the contract.

This is **distinct from** the already-resolved SC-3347 line-type regression and from the SC-3345 $0-net pricing issue. It is the residual, still-open `extendedAmount` mapping defect first documented in SC-3347's `MIDDLEWARE_FIX_SPEC.md` — now reproduced cleanly with no $0/write-down confound.

## Clean repro — Order 00095381 (created 2026-06-08)

Single line *Advanced Authentication Modes* (`GS-GSE-NRPS-AAMP`, Perpetual), Qty 1, with a vanilla **10% discount**:

| Quantity | OrderItem field | Value | Base |
|---|---|---|---|
| List | `ListPrice` / `UnitPrice` / **`TotalLineAmount`** | 3150 | **list** ← `extendedAmount` source (bug) |
| Net | `NetUnitPrice` / **`NetTotalPrice`** | 2835 | **net** ← `extendedAmount` *should* be this |
| Discount | `TotalAdjustmentAmount` | −315 | the 10% |
| Line type | `Workday_Contract_Line_Type__c` | `FIXED AMOUNT` | ✓ correct (SC-3347 V8 active) |
| Subsplit | `Original_Order_Item__c` | null | not a parent |

**Stored `Workday_Sync_Payload__c` (logged by MuleSoft):**

```json
{ "currentContractAmount": 2835,
  "contractLineData": [
    { "contractLineTypeID": "FIXED AMOUNT", "salesItemID": "GS-GSE-NRPS-AAMP",
      "quantity": 1, "unitCost": 2835, "extendedAmount": 3150 } ] }
```

**Math:** header net `2835` vs line `extendedAmount` list `3150`; `unitCost×qty = 2835 ≠ extendedAmount = 3150`; mismatch **315 = the discount**. For a `FIXED AMOUNT` line Workday requires Contract Amount == Contract Line Amount == Contract Line Revenue Amount → rejected.

## Why this is MuleSoft, not Salesforce (the disputed point — settled)

- The platform event **`Order_Completed_WD__e` carries only `Order_Id__c`** (verified: its data fields are `ReplayId, CreatedDate, CreatedById, EventUuid, Order_Id__c`). MuleSoft receives the Id, queries Salesforce live, **builds the entire `Submit_Customer_Contract` payload**, submits, and logs the request back into `Workday_Sync_Payload__c`.
- **Org-wide body search** of every ApexClass, ApexTrigger, Flow, and DataRaptor for `extendedAmount` / `contractLineData` / `Workday_Sync_Payload` / `currentContractAmount` / `Submit_Customer_Contract` = **0 hits**. No Salesforce component assembles this payload.
- On 00095381, `Workday_Sync_Payload__c`, `Workday_Sync_Status__c`, `Workday_Sync_Message__c`, and the Order's `LastModifiedBy` are all the MuleSoft integration user (`svc.mulesoft@fortra.com.uat`, `005WC00000FZ01KYAT`). No Salesforce automation touched them.
- **"Everything comes from CRM" is true but doesn't exonerate Mule:** both `TotalLineAmount` (3150) and `NetTotalPrice` (2835) exist in CRM — the bug is *which field Mule selects*. (That prior quote was about the line-type error class, which genuinely was a dedicated SF field Mule passes through; there is **no** equivalent "net extended amount" field, so this has no pure-Salesforce fix.)

## Ruled out (so it is not mis-attributed)

- **Not the SC-3347 line-type regression** — line type is `FIXED AMOUNT` (not `BILLING ONLY`), `Original_Order_Item__c` null, stamping flow V8 active.
- **Not the SC-3345 $0-net issue** — net is 2835 (not 0); `TotalAdjustmentAmount = −315`, a clean 10% discount, not a full `−3150` write-down.
- **Not partner pricing (SC-3359)** — `PartnerDiscountPercent` null, `Is_Partner_Price_Overridden__c` false; discount is a real discretionary `Discount = 10` sourced at the Quote.
- **Not rounding / dropped line / currency / wrong header field** — exact whole dollars, exactly 1 line, single-currency USD, header correctly = net.

## Scope (live FortraUAT, 2026-06-08)

**20 distinct orders** have ≥1 net<list line (`TotalAdjustmentAmount < 0`): **13 Pending + 7 Failure**, and **0 have *ever* reached Workday Success** — a 100% deterministic block. All 7 failures carry the identical error.

- **Failure — pure discount (net>0):** 00095381 (−315), 00004800 (−2352), 00004792 (−3250)
- **Failure — also has a $0-net line (SC-3345 family):** 00095380, 00095372, 00095355, 00095279
- **Pending (latent):** 00095353, 00095348, 00095218, 00004817, 00004803, 00004775, 00004756, 00004737, 00000270, 00000252, 00000236, 00000178, 00000140

The one fix below resolves **both** subtypes (for a $0 line, `NetTotalPrice = 0` zeroes the line amount, reconciling it too).

## Fix (MuleSoft — owner: integration team)

In the `Submit_Customer_Contract` builder, source the contract-line amount from **net**:

```
line.unitCost       = OrderItem.NetUnitPrice
line.quantity       = OrderItem.Quantity
line.extendedAmount = OrderItem.NetTotalPrice        # == NetUnitPrice × Quantity, NOT TotalLineAmount
header.currentContractAmount = Order.TotalAmount     # already net; unchanged
```

**Invariant to pin for every submission:**
```
extendedAmount  == round(unitCost × quantity, 2)            # per line
SUM(extendedAmount across lines) == currentContractAmount   # header == sum of lines
```

Full spec: [`MIDDLEWARE_FIX_SPEC.md`](../sc3347%20%7C%20Orders%20fail%20Workday%20sync%20-%20Contract%20Amount%20must%20equal%20Contract%20Line%20Amount%20(zero-dollar%20net%20unit%20price)/MIDDLEWARE_FIX_SPEC.md).

**Regression-safe:** on net==list orders `NetTotalPrice == TotalLineAmount`, so the change is a no-op (verified on Success orders 00095364 `3675==3675` and 00095276 `0==0`).

**Inferior alternatives (for the record):** a dedicated SF `Workday_Extended_Amount__c` field still requires the identical Mule re-point (no advantage over reading the existing `NetTotalPrice`); an SF `SUM(net) ≠ SUM(list)` submit-validation is defense-in-depth only — it blocks bad submits but cannot make any discounted order succeed, so it does not clear the 20-order backlog.

## Acceptance criteria

- [ ] MuleSoft maps `extendedAmount ← OrderItem.NetTotalPrice`; invariant `SUM(extendedAmount) == currentContractAmount` holds.
- [ ] 00095381 resubmits to Workday **Success** (`Workday_ID__c` is null → resubmittable; republish `Order_Completed_WD__e` with `Order_Id__c = 801WC00000kML51YAG`).
- [ ] The 3 pure-discount failures (00095381, 00004800, 00004792) submit Success.
- [ ] No regression on net==list orders (e.g. 00095364, 00095276 unchanged).
- [ ] Sweep the 13 Pending net<list orders — confirm they submit cleanly.

## Caveat

The MuleSoft DataWeave is **not in this repo**, so `extendedAmount ← TotalLineAmount` is *inferred* — but strongly: the logged payload's `extendedAmount` equals `TotalLineAmount`/`ListPrice` (3150) to the dollar while `unitCost` equals `NetTotalPrice` (2835) to the dollar. To make it 100% definitive, the integration team should confirm against the DataWeave or capture an Anypoint log on a fresh resubmit (new correlation id).

*Secondary / orthogonal:* the payload's `billingScheduleFromDate == billingScheduleToDate == 2026-06-08` (zero-length billing window) relates to **SC-3297**, not this error.

## References

- **SC-3347** — Orders fail Workday sync (line-type regression, resolved) + `MIDDLEWARE_FIX_SPEC.md` (this fix's spec): `*Jira/Task/sc3347 | Orders fail Workday sync .../`
- **SC-3345** — `$0`-net-line / RLM pricing (the *why* behind the 4 $0-net failures)
- **SC-3143** — Workday integration epic + `Submit_Customer_Contract` API reference
- **SC-3297** — Order billing From/To date derivation (the zero-length-window note)
- Verification: read-only SOQL + payload inspection on FortraUAT, 2026-06-08; 4-lens adversarial workflow (`wf_37894fc8-f46`), all high-confidence.
