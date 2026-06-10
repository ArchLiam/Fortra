# SC-3347 — Orders fail to sync to Workday: "Contract Amount must equal Contract Line Amount" ($0 net unit price) + separate "Internal Error"

> Space: Salesforce-Coastal (SC) · Type: Sub-task of [SC-3143](https://helpsystems.atlassian.net/browse/SC-3143) · [SC-3347](https://helpsystems.atlassian.net/browse/SC-3347)
>
> ✅ **RESOLVED in UAT (2026-06-07)** — the actual root cause was a **line-type regression**: the OrderItem flow stamped `FIXED AMOUNT BILLING ONLY` (zero-revenue) on Perpetual lines → Workday *"Contract Amount and Contract Line Revenue Amount must be equal"*. Fixed via flow **`Fortra_OrderItem_Set_Workday_Contract_Line_Type` V7**. See **[✅ Resolution](#-resolution-2026-06-07--line-type-regression-fixed-via-flow-v7)** below. The $0-net-price / middleware-`extendedAmount` mapping theory (original investigation, retained below) was **superseded** as the primary cause; 00095355's genuine $0 line is a **separate SC-3345** issue. Raw evidence: [`evidence/payloads.md`](evidence/payloads.md).

## Details

| Field | Value |
|---|---|
| **Status** | ✅ Resolved in UAT — line-type flow **V7** deployed · 00095355 $0-line → SC-3345 · large-order SOQL limit → [separate ticket](../scXXXX%20%7C%20Order%20completion%20exceeds%20SOQL%20governor%20limit%20on%20large%20orders/README.md) |
| **Reporter** | Joe Romo (reported via Teams) |
| **Assignee** | Liam Jeong |
| **Parent** | [SC-3143 — Integration E2E Testing Path](https://helpsystems.atlassian.net/browse/SC-3143) |
| **Priority** | 🟠 High (recommended) |
| **Sprint** | CRM Sprint 14 |
| **Components** | SF RCA |
| **Labels** | Bug, CRM, RCA, Workday |
| **Environment** | FortraUAT (`fortra--uat.sandbox.lightning.force.com`) |

---

## ✅ Resolution (2026-06-07) — line-type regression fixed via flow V7

**Actual root cause (supersedes the $0-price / middleware-mapping theory in the investigation below).** The record-triggered flow **`Fortra_OrderItem_Set_Workday_Contract_Line_Type`** was stamping **`FIXED AMOUNT BILLING ONLY`** — a **zero-revenue** Workday line type — on **all non-services (Perpetual) lines**. A BILLING ONLY line carries **$0 contract-line revenue**, so Workday's `Submit_Customer_Contract` rejects with *"Contract Amount and Contract Line Revenue Amount must be equal."* This was a **regression**: the flow's `Set` element flipped FIXED AMOUNT → "Fixed Amount – Billing Only" (V2, Andy 6/4) → reverted (V3, 6/5) → "FIXED AMOUNT BILLING ONLY" (V4, Ben 6/5, who also deactivated the `FIXED AMOUNT` picklist value). **MuleSoft is pass-through** — Permender confirmed *"nothing to work on the Mule side; everything comes from CRM"* — so the earlier middleware-`extendedAmount`-mapping fix was a dead end for this error class.

**Client-confirmed line-type mapping (Joe + Wren, 2026-06-07):**

| Line nature | Workday line type | Detected by |
|---|---|---|
| Services | USAGE BASED | `Product2.pse__IsServicesProduct__c = true`, non-prepaid |
| Prepaid | PREPAID | services + prepaid order attribute |
| Perpetual | FIXED AMOUNT | non-services, not a subsplit parent |
| Renewal Maintenance | FIXED AMOUNT | non-services (`Family = 'Renewal Maintenance'`), not a parent |
| **Subsplit Parent** | **FIXED AMOUNT BILLING ONLY** | non-services **and referenced by a child via `Original_Order_Item__c`** (the ONLY billing-only case) |
| Split child | FIXED AMOUNT | non-services, not a parent |

**Subsplit-parent discriminator:** a line is a subsplit **parent** iff another OrderItem has `Original_Order_Item__c = <this line's Id>` (children point to parent). Validated across **17/18** subsplit orders; correctly handles the mixed order 00069311 (finds the real parents, zero false positives); 1 legacy outlier (00000252) has no parent link. No self-identifying field exists on the parent, so this reverse-lookup is the reliable signal — **no dependency on Andy/PowerOrderSplittingService.**

**Fix deployed to UAT** (flow `Fortra_OrderItem_Set_Workday_Contract_Line_Type`, now **V7 Active**):
- Reactivated the `FIXED AMOUNT` picklist value on `OrderItem.Workday_Contract_Line_Type__c`.
- **V5:** non-services default `Set` → `FIXED AMOUNT` (fixes Perpetual / Renewal Maintenance).
- **V6:** added `Get_Subsplit_Children` (Get Records: OrderItem WHERE `Original_Order_Item__c` = `$Record.Id`, first record) + decision `Is_Subsplit_Parent` → found ⇒ `FIXED AMOUNT BILLING ONLY`, else ⇒ `FIXED AMOUNT`. All 5 cases handled.
- **V7:** renamed all elements to a clear convention (`Decision_Is_*`, `Get_*`, `Update_LineType_*`) + a description on every element + a flow-level description. Deploy source: `Data/sc3347/flow_v5/unpackaged/`.

**Confirmed working:** after reprice, **00095354**'s Workday payload is now all `FIXED AMOUNT`, `unitCost = extendedAmount = 3150`, header `currentContractAmount = 9450 = SUM` — the original error is **gone**. **00095364** (Perpetual) reached Workday **Success** with `FIXED AMOUNT`.

> ⚠️ **The flow re-stamps only on OrderItem save** → **reprice (Calculate Price)** or cycle status to apply V7 to *existing* lines (they keep their stale V4 value until re-saved).

### Remaining items (NOT the line-type fix)
1. **00095355 still fails** — it has a genuine **$0-net line** (line 2, −$3,150 adjustment carried from the Quote). Even as `FIXED AMOUNT`, that line has $0 revenue ≠ its amount → still rejected. This is the **separate SC-3345 pricing issue** (the original investigation below). **Track under SC-3345.**
2. **Workday idempotency** — re-submitting an order whose contract already exists **past Draft** returns *"This Customer Contract is not in Draft status and is unable to be resubmitted."* Orders with a populated `Workday_ID__c` (e.g. 00095354) hit this. For a clean fresh Success test, use an order with **blank `Workday_ID__c`** (e.g. 00095363).
3. **Completion gate** — Update Status blocks Order Complete unless `Bill_To_Account__c`/`Ship_To_Account__c` (→Account), `BillToContactId`/`ShipToContactId` (→Contact), `Bill_To_Address__c`/`Ship_To_Address__c` (→Places__c) are populated (+ some Account D&B DUNS/Phone). Pre-existing, unrelated to line type. Filled on 00095363/00014777/00069311 by copying a completed sibling order's values.
4. **SOQL governor limit on large orders (~15+ lines)** — completion fails *"Too many SOQL queries: 101"* (the generic "unhandled fault"). Root cause = `FieldPopulatedCheck` SOQL-in-loop (1 query/field, invoked inside Flow loops in `Fortra_Order_Submission_Check`) + per-line flow fan-out (incl. a duplicate `Fortra_Autolaunched_Set_Workday_Contract_Line_Type`). **Logged as its own ticket:** [`*Jira/Task/scXXXX | Order completion exceeds SOQL governor limit on large orders/`](../scXXXX%20%7C%20Order%20completion%20exceeds%20SOQL%20governor%20limit%20on%20large%20orders/README.md). Evidence: `Data/sc3347/fault_log.txt`.

---

## Summary  *(original investigation — superseded primary theory; retained for history)*

Two Orders fail to sync to **Workday** (and the Legacy CRM). Reported by Joe Romo (Teams, 2026-06-06). A deep **read-only** investigation against FortraUAT (multi-agent workflow + direct SOQL/payload inspection) confirms the two orders fail for **two different reasons**:

1. **00095355** — `Submit_Customer_Contract` rejects with *"Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract."* **Root cause confirmed:** a line with **$0 net unit price** (set at the **Quote**, carried through conversion) produces a contract line whose `extendedAmount` (list base, $3,150) disagrees with its `unitCost` ($0, net) and with the net order header — so the header ≠ sum of line amounts. **Joe's hypothesis is correct.** This is the **SC-3345** net-vs-list pricing divergence surfacing at Order/Contract level.
2. **00095354** — generic *"Internal Error"*. **Not** the $0-price bug (all lines healthy; Quote + Contract both exist). The stored Workday payload is anomalous (a bare Contact Id, not a contract document). Root cause undetermined from Salesforce data alone → needs middleware/integration-log review + clean resubmit.

> **Scope (Phase 0):** the 00095355 mechanism is **not limited to $0 lines or to these 2 orders.** It breaks for **any line where net < list** (a discount or a write-down). **14 orders** carry this exact Workday error; **16 orders** currently have a net<list line (**3 Failure + 13 Pending** latent failures, some dating to Jan 2026); **0 of 66** successful orders have one. See [Phase 0 findings](#phase-0-findings-read-only-deep-dive-2026-06-06).

## Affected records

| Order | Id | Quote | Contract | Account | Total | Type |
|---|---|---|---|---|---|---|
| [**00095355**](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kHDO9YAO/view) | `801WC00000kHDO9YAO` | `0Q0WC0000035neH0AQ` | `800WC00000Rx8QDYAZ` | `001WC00000gVLfxYAG` (WD cust 124204) | $3,150 | Master_Contract |
| [**00095354**](https://fortra--uat.sandbox.lightning.force.com/lightning/r/Order/801WC00000kGzJbYAK/view) | `801WC00000kGzJbYAK` | `0Q0WC0000035YYn0AM` | `800WC00000Rx4HlYAJ` | `001WC00000gVLfxYAG` | $9,450 | Master_Contract |

---

## Reproduction confirmed — deterministic, not user-specific or transient (2026-06-07)

Liam re-completed **both** of Joe's orders himself (Provisioned → Order Complete, firing fresh events → **new correlation ids**, proving MuleSoft re-processed). **Both failed identically:**

| Order | Fresh correlation id | Result (unchanged) |
|---|---|---|
| 00095354 | `543cdf60-622a-11f1-…` | "Internal Error" (same bare Contact-Id payload) |
| 00095355 | `4fba3d70-622a-11f1-…` | "Contract Amount … must equal … Contract Line Amount" (line 2 still `$0`) |

⇒ The failures are **baked into each order's data** and fail for *anyone* — **not** "Joe-specific," **not** transient. (A clean test order, **00095264**, synced **Success** once its `DNU` payment term was fixed — proving the pipeline itself works.) For **00095354**, use the fresh correlation id **`543cdf60`** when requesting the MuleSoft Anypoint log.

## ① Order 00095355 — CONFIRMED ($0 net unit price)

**Workday error (`Workday_Sync_Message__c`):**
> `{"status":"Failure","message":"Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.,The Contract Amount and the Contract Line Amount must be equal to Submit Contract."}`

**OrderItem lines** — two identical *Advanced Authentication Modes* (`GS-GSE-NRPS-AAMP`), qty 1, List/Unit $3,150 each (verified via SOQL, read-only):

| Line | List | UnitPrice | TotalLineAmount | **NetUnitPrice** | NetTotalPrice | **TotalAdjustmentAmount** |
|---|---|---|---|---|---|---|
| 1 | $3,150 | $3,150 | $3,150 | $3,150 | $3,150 | $0 |
| 2 | $3,150 | $3,150 | $3,150 | **$0** | $0 | **−$3,150** |

**Order math:** `SUM(NetTotalPrice) = $3,150` ✓ = `Order.TotalAmount`; but `SUM(TotalLineAmount) = $6,300` ✗.

**Stored Workday payload** (`Workday_Sync_Payload__c`, abridged — full in [evidence](evidence/payloads.md)):

```json
{ "currentContractAmount": 3150, "totalAmount": 3150,
  "contractLineData": [
    { "lineNumber": 1, "contractLineTypeID": "FIXED AMOUNT BILLING ONLY", "unitCost": 3150, "extendedAmount": 3150 },
    { "lineNumber": 2, "contractLineTypeID": "FIXED AMOUNT BILLING ONLY", "unitCost": 0,    "extendedAmount": 3150 }
  ] }
```

**Decisive defect — mixed price bases in the payload:**

| Quantity | Source field (SF) | Value on L2 | Base |
|---|---|---|---|
| header `currentContractAmount` | `Order.TotalAmount` | $3,150 | **net** |
| line `unitCost` | `OrderItem.NetUnitPrice` | **$0** | **net** |
| line `extendedAmount` | `OrderItem.TotalLineAmount` | **$3,150** | **list** (not zeroed) |

So Workday sees:
- `header ($3,150)` ≠ `SUM(extendedAmount) = $3,150 + $3,150 = $6,300` → *"Contract Amount … must equal … Contract Line Amount."*
- Line 2 internally inconsistent: `unitCost × qty = $0` ≠ `extendedAmount = $3,150`.

**Why line 2 is $0:** RCA/RLM wrote a full **−$3,150 adjustment** (`TotalAdjustmentAmount`) on the second AAM line, zeroing its `NetUnitPrice`. This originates at the **Quote** and survives conversion — see *Origin* below.

**Adversarial check:** the mismatch is *not* rounding (exact dollars), *not* a missing line (exactly 2 lines returned), *not* currency (USD, no conversion), *not* the header field choice (`TotalAmount` correctly = `SUM(NetTotalPrice)`). The single divergence is the list-based `extendedAmount` on the $0-net line.

### Origin: the $0 starts at the Quote, not the Order

The zeroed net price is **set at the Quote stage and carries through Quote→Order conversion unchanged** (QuoteLineItem, read-only):

| Quote (#) | → Order | Product | Qty | List | NetUnitPrice | TotalAdjustmentAmount |
|---|---|---|---|---|---|---|
| `0Q0WC0000035neH0AQ` (00780874) | 00095355 | AAM | 1 | $3,150 | $3,150 | $0 |
| `0Q0WC0000035neH0AQ` (00780874) | 00095355 | AAM | 1 | $3,150 | **$0** | **−$3,150** |
| `0Q0WC0000035YYn0AM` (00780871) | 00095354 | AAM | 1 ×3 | $3,150 | $3,150 (all 3) | $0 |

So the line-level RLM pricing wrote `NetUnitPrice = $0` (full −$3,150 absolute adjustment; `Discount` is null, so it is **not** a % discount) on the **second** of two identical AAM lines on quote 00780874. The same `Rev_Mgmt_Default_Pricing_Procedure` / RLM net-vs-list family as **SC-3345**, manifesting here at the **line** level. Joe Romo's "$0 net unit price from RCA" hypothesis is **confirmed**.

> ⚠️ **Not a deterministic per-product rule:** the healthy quote 00780871 has **three** identical AAM lines and **none** are zeroed, while 00780874 has **two** and **one** is zeroed. So the −$3,150 is a **line-specific adjustment** (possibly a manual price override applied during testing — both quotes are named "Q-Test After Fix" — or a non-deterministic RLM reprice), not a "charge-once" dedup. Determining its exact source is open question #1.

---

## ② Order 00095354 — DISTINCT / undetermined (NOT the $0 bug)

**Workday error:** `Internal Error` · Contract Type `Master_Contract`.

**OrderItem lines** — three *Advanced Authentication Modes*, all healthy:

| Line | List | NetUnitPrice | NetTotalPrice | Adjustment |
|---|---|---|---|---|
| 1–3 | $3,150 | $3,150 | $3,150 | $0 |

`SUM(NetTotalPrice) = SUM(TotalLineAmount) = $9,450` = `Order.TotalAmount` ✓ — **no $0 net price, no base mismatch.**

**Anomaly:** `Workday_Sync_Payload__c` = the bare string `"003WC00000sTv2EYAS"` (a **Contact** Id), **not** a contract document. Quote (`0Q0WC0000035YYn0AM`) and Contract (`800WC00000Rx4HlYAJ`) both exist, so the earlier "missing Contract linkage" theory is **disproven**.

**Conclusion:** root cause cannot be determined from Salesforce data alone. Needs **middleware/integration-log review** and a **clean resubmit** to capture a real payload/error. Likely a transient or middleware-serialization issue, independent of the pricing bug.

### Debug-log analysis (2026-06-07, `Data/sc3347/07LWC00000Ofn2A2AR-file.txt`)
A SF debug log was captured (trace on Liam) while clicking **Update Status** on 00095354. Two findings:

1. **"Update Status" does NOT resubmit to Workday.** The transaction had **0 DML, 0 callouts, 0 platform-event publishes**. The `Fortra | Order | After Update - Platform Event (Workday)` flow ran but all publish gates were **false**: `Order_Completed_Decision=false`, `Order_Complete_and_WD_Status_is_Success_Decision=false`, `PO_URL_Changed_Decision=false`. The Workday-submit event only fires when **Status *transitions into* "Order Complete"** — the order was already there, so nothing re-published. ⇒ **repricing / Update Status will never resubmit a stuck order**; the "Order sent to Workday" toast is a hardcoded screen message, not proof of a send. (Explains why the correlation id never changes.)
2. **The bare-Contact-Id payload is a red herring.** `Workday_Sync_Payload__c = "003WC00000sTv2EYAS"` = the order's `BillToContactId` (**Joe Romo**) — and that Contact is itself **synced to Workday Success** (`Workday_ID 58381fe1…`, "Contact saved successfully"). So the contact isn't the failure; MuleSoft just logged a contact reference instead of the contract JSON when it errored.
3. **Side observation:** the order carries `ValidationResult = TransactionIncomplete` (RLM) despite `CalculationStatus = CompletedWithPricing` and being Activated — worth checking as a possible secondary factor (cf. SC-3308).

⇒ The SF side is healthy; **00095354's "Internal Error" is generated inside MuleSoft** (a generic catch-all, not a Workday validation message). Root-causing it **requires the MuleSoft Anypoint log** for correlation id `ad1783c0-61cf-11f1-b9c9-96583158e4d0`. To even get a fresh attempt, the `Order_Completed_WD__e` event must be **republished** (Status won't re-transition on its own).

---

## Phase 0 findings (read-only deep-dive, 2026-06-06)

### Step 1 — what zeroes the line (00095355): the RLM pricing waterfall, not a manual edit
Field-by-field, the two AAM quote lines on quote 00780874 are **identical** except `NetUnitPrice`/`NetTotalPrice` ($3,150→$0) and `TotalAdjustmentAmount` ($0→−$3,150). **No** `Discount`, `DiscountAmount`, `Discount_Reason__c`, `Price_Mode__c`, or override flag is set; both lines share one `PriceWaterfallIdentifier` (…`114203329788087`). ⇒ the −$3,150 is applied by the **RLM pricing waterfall**, not a manual discount/override. It is **erratic** across orders (00095354: 3 identical lines → 0 zeroed · 00095355: 2 → 1 · 00095353: 5 → 2), so it is **not** a deterministic "charge-once" rule — it is a **pricing-procedure artifact**. Both quotes are named *"Q-Test After Fix"* (SC-3345 pricing test quotes). ⇒ the *why-is-it-zeroed* owner is **SC-3345 / RLM pricing**; this ticket owns the *Workday-sync* break.

### Step 2 — scope: broader than $0, and broader than the 2 reported orders
The Workday break is the payload's **list-vs-net base mix** (`extendedAmount` ← list, `unitCost`/header ← net), so it triggers for **any line where net < list** — a discount *or* a $0 write-down; $0 is just the extreme.
- **Proven (live payload):** 00095355 (the $0 case above).
- **Correlation:** **0 of 66** successfully-synced orders contain a net<list line.
- **Current data condition:** **16 orders** have ≥1 net<list line — **3 Failure** (00095355, 00004792, 00004800) + **13 Pending** (latent failures; created as far back as 2026-01-27).
- **Historical error:** **14 orders** carry this exact Workday message: 00004740, 00004792, 00004800, 00095243, 00095245, 00095261, 00095266, 00095277, 00095287, 00095310, 00095311, 00095312, 00095345, 00095355.
- ⚠️ **Caveat:** the older "discounted failures" (00004792 / 00004800) have **stale/legacy payloads** (different schema, `extendedAmount = 0` throughout, values that no longer reconcile with current line data). They show the line-amount mapping has been buggy across *multiple* middleware versions, but are **not** used as proof of the current mechanism. The clean live proof is **00095355**; the recurrence to watch is **00095353** (Pending — has both $0 lines *and* a real 10%-discounted Monitoring line).

### Step 3 — fix point
Because the break is the payload base mix, the **direct, scope-complete fix is the middleware mapping** (`extendedAmount` ← net), which fixes every net<list line regardless of why RLM set it. Exact handoff: [`MIDDLEWARE_FIX_SPEC.md`](MIDDLEWARE_FIX_SPEC.md). The middleware **logs** for 00095354's "Internal Error" remain an external dependency (not reachable from Salesforce).

---

## Pipeline & code path (repo-verified)

`Fortra_Order_Submission_Check.flow` (sets `Status=Order Complete` + `Workday_Sync_Status__c=Pending`)
→ `Fortra_Order_After_Update_Platform_Event_Workday.flow` (publishes `Order_Completed_WD__e`, carrying only `Order_Id__c`)
→ **external middleware** reads LIVE Order/OrderItem data, builds the `Submit_Customer_Contract` payload, submits to Workday, and **logs the request** into `Workday_Sync_Payload__c` + the response into `Workday_Sync_Message__c`.

**Middleware = MuleSoft** (identified):
- Integration user **Service Mulesoft Integration** (`svc.mulesoft@fortra.com.uat`, profile *API Only*, Id `005WC00000FZ01KYAT`); owner/admin contact on the user record: **keith.irwin@fortra.com**.
- Connected App **"Mulesoft Integration"**; logs in ~every 10 min from `3.150.15.167` (AWS us-east-2 → MuleSoft CloudHub).
- Corroborated by a sibling failure whose `Workday_Sync_Message__c` is literally **"Mule API Failed."**
- The payload mapping (incl. the buggy list-based `extendedAmount`) lives in the **MuleSoft flow, not in Salesforce** — so fix #1 is a MuleSoft change. Likely owners: Keith Irwin / the integration team (SC-3143 epic assignee **Andy Kumar**).

**No SF-side amount-consistency validation exists.** `Order_Submit_Validation__mdt` rules check only field *population* (Account/Contact/Place), never `SUM(lines) == TotalAmount`. The mismatch is therefore only caught by Workday *after* submission.

**Minor latent observation:** the payload's `billingScheduleFromDate == billingScheduleToDate == 2026-06-06`. Workday prefers `From < To` (see `Submit_Customer_Contract` validations); relates to **SC-3297** billing-date derivation. Not the current error, but worth confirming.

---

## Recommended fixes (not yet implemented)

1. **(Direct — primary, scope-complete) Integration/middleware mapping** — source per-line `extendedAmount` from **net** (`NetTotalPrice`, or `NetUnitPrice × qty`) instead of `TotalLineAmount`, so `SUM(extendedAmount)` equals the net header and no line is internally inconsistent. *Owner: integration/middleware team.* **This is THE fix** — it resolves all 16 net<list orders (every discount, not just $0) regardless of why RLM set net<list. (Phase 0 shows the line-amount mapping has been buggy across multiple middleware versions — older payloads sent `extendedAmount=0`, current sends list — so pin the contract: `extendedAmount == unitCost × quantity == net line total`.) Exact spec: [`MIDDLEWARE_FIX_SPEC.md`](MIDDLEWARE_FIX_SPEC.md).
2. **(Upstream) RCA pricing** — determine **why** the duplicate AAM line is written to $0 net (−$3,150 adjustment). If a pricing-procedure defect → fold into **SC-3345** (V8/V9). If intentional (free/bundled duplicate) → confirm and rely on fix #1.
3. **(Defense-in-depth, SF)** — extend `Fortra_Order_Submission_Check` / add an `Order_Submit_Validation__mdt`-style rule that blocks submit (with a clear message) when `SUM(TotalLineAmount) ≠ TotalAmount` or any line has `NetUnitPrice = 0` with non-zero `TotalLineAmount` — surfacing the error in Salesforce before Workday rejects it.
4. **(00095354)** — pull middleware error logs; re-publish `Order_Completed_WD__e` (`Order_Id__c = 801WC00000kGzJbYAK`) to resubmit against live data and capture a real payload/error.

> ⚠️ Any SF-side change (fix #3) or pricing-procedure change (fix #2) is a deploy that requires explicit authorization; the middleware change (#1) is owned by the integration team. This ticket is **investigation + recommendation**; no changes deployed.

## Acceptance criteria

- [ ] Both orders submit to Workday with **Success** (`Workday_Sync_Status__c = Success`).
- [ ] In the payload, header `currentContractAmount` = `SUM(extendedAmount)`; no line is internally inconsistent ($0 `unitCost` with non-zero `extendedAmount`).
- [ ] The $0-net-line scenario (00095355) is reproduced and verified fixed end-to-end.
- [ ] 00095354's "Internal Error" is root-caused (middleware log) and resolved or reproduced.
- [ ] No regression to healthy orders (e.g. 00095354's all-net=list profile).

## Open questions

1. What sets the **−$3,150 line adjustment** that zeroes `NetUnitPrice` on quote 00780874's second AAM line — a **manual price override** (these are "Q-Test After Fix" test quotes) or an **RLM pricing-procedure** behavior? It is line-specific (3-line quote 00780871 has none zeroed), set at quote-time, and carries through conversion. (Determines whether the primary fix is middleware mapping #1 alone, or also a pricing fix under #2/SC-3345.)
2. Who owns the **middleware `extendedAmount` mapping** — can it be changed to use net?
3. Should 00095355 be tracked here or as an explicit child of **SC-3345**?
4. Is `billingScheduleFromDate == ToDate` a real latent issue (SC-3297)?

## References

- **SC-3345** — Quote pricing-rollup root cause (net-vs-list base divergence): `*Jira/Task/sc3345 | Quote shows phantom discount, wrong ALE, and a Services Total with no Services after save/`
- **SC-3143** — Workday integration epic + `Submit_Customer_Contract` API reference: `*Jira/sc3143(epic | integration)/workday-api-reference/Submit_Customer_Contract.md`
- **SC-3297** — Order Billing From/To Date derivation · **SC-3291** — Order submission validation
- Investigation: read-only SOQL + Workday payloads from FortraUAT, 2026-06-06 (workflow run `wacsry163`). Raw data: [`evidence/payloads.md`](evidence/payloads.md).
