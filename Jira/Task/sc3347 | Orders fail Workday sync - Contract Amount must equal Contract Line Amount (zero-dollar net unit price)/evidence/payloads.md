# SC-3347 — Raw evidence (FortraUAT, read-only, 2026-06-06)

All captured via `sf data query -o FortraUAT` (read-only). Reproduce with the queries in the [Verification](#verification) section.

## Order headers

| OrderNumber | Id | Status | TotalAmount | QuoteId | ContractId | Workday_Sync_Status__c | Workday_Contract_Type__c | Workday_Sync_Message__c |
|---|---|---|---|---|---|---|---|---|
| 00095354 | 801WC00000kGzJbYAK | Order Complete | 9450 | 0Q0WC0000035YYn0AM | 800WC00000Rx4HlYAJ | Failure | Master_Contract | `Internal Error` |
| 00095355 | 801WC00000kHDO9YAO | Order Complete | 3150 | 0Q0WC0000035neH0AQ | 800WC00000Rx8QDYAZ | Failure | Master_Contract | `Contract Amount and Contract Line Revenue Amount must be equal to Submit Contract.,The Contract Amount and the Contract Line Amount must be equal to Submit Contract.` |

## OrderItem lines

| Order | Product | Qty | UnitPrice | ListPrice | TotalLineAmount | NetUnitPrice | NetTotalPrice | TotalAdjustmentAmount |
|---|---|---|---|---|---|---|---|---|
| 00095354 | Advanced Authentication Modes | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 |
| 00095354 | Advanced Authentication Modes | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 |
| 00095354 | Advanced Authentication Modes | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 |
| 00095355 | Advanced Authentication Modes | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 |
| 00095355 | Advanced Authentication Modes | 1 | 3150 | 3150 | 3150 | **0** | **0** | **-3150** |

## QuoteLineItems (origin of the $0 — carries through conversion)

| Quote # | QuoteId | → Order | Product | Qty | UnitPrice | ListPrice | TotalLineAmount | NetUnitPrice | NetTotalPrice | TotalAdjustmentAmount | Discount |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 00780871 | 0Q0WC0000035YYn0AM | 00095354 | AAM | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 | (null) |
| 00780871 | 0Q0WC0000035YYn0AM | 00095354 | AAM | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 | (null) |
| 00780871 | 0Q0WC0000035YYn0AM | 00095354 | AAM | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 | (null) |
| 00780874 | 0Q0WC0000035neH0AQ | 00095355 | AAM | 1 | 3150 | 3150 | 3150 | 3150 | 3150 | 0 | (null) |
| 00780874 | 0Q0WC0000035neH0AQ | 00095355 | AAM | 1 | 3150 | 3150 | 3150 | **0** | **0** | **-3150** | (null) |

The $0 net price is present **at the Quote** (00780874, line 2) before conversion; `Discount` is null → the write-down is an absolute `TotalAdjustmentAmount`, not a % discount. The 3-line quote 00780871 has none zeroed → line-specific, not a per-product rule.

## Workday payload — 00095355 (`Workday_Sync_Payload__c`, full)

```json
{
  "sfContractId": "801WC00000kHDO9YAO",
  "orderId": "801WC00000kHDO9YAO",
  "sfAccountId": "001WC00000gVLfxYAG",
  "fortraSfdcExternalId": "801WC00000kHDO9YAO",
  "orderNumber": "00095355",
  "name": "Q-Test After Fix -- 06-06-26-2026-06-06",
  "opportunityId": "006WC00000Qj0ZZYAZ",
  "totalAmount": 3150,
  "currencyIsoCode": "USD",
  "contractReferenceId": "801WC00000kHDO9YAO",
  "contractStatus": "Order Complete",
  "companyReference": "COM003",
  "currencyID": "USD",
  "shipToCustomerID": "124204",
  "soldToCustomerID": "124204",
  "billToCustomerID": "124204",
  "customerContractType": "Master_Contract",
  "paymentTerms": "Net_30",
  "contractEffectiveDate": "2026-06-06",
  "salespersonReference": "005a500001J5WNBAA3",
  "currentContractAmount": 3150,
  "multipleElementRevenueAllocation": false,
  "contractLineData": [
    {
      "billingLineTemplate": "Yearly_Billing_Template",
      "contractLineReference": "802WC00000OSQ1lYAH",
      "lineNumber": 1,
      "contractLineTypeID": "FIXED AMOUNT BILLING ONLY",
      "salesItemID": "GS-GSE-NRPS-AAMP",
      "quantity": 1,
      "unitCost": 3150,
      "extendedAmount": 3150,
      "billingScheduleFromDate": "2026-06-06",
      "billingScheduleToDate": "2026-06-06",
      "shipToCustomerID": "124204",
      "shipToAddressID": "001WC00000GVLFXYAG_VIADELL'ARTIGIANATO5_CAMPOSANTO_MO_41031_IT"
    },
    {
      "billingLineTemplate": "Yearly_Billing_Template",
      "contractLineReference": "802WC00000OSQ1mYAH",
      "lineNumber": 2,
      "contractLineTypeID": "FIXED AMOUNT BILLING ONLY",
      "salesItemID": "GS-GSE-NRPS-AAMP",
      "quantity": 1,
      "unitCost": 0,
      "extendedAmount": 3150,
      "billingScheduleFromDate": "2026-06-06",
      "billingScheduleToDate": "2026-06-06",
      "shipToCustomerID": "124204",
      "shipToAddressID": "001WC00000GVLFXYAG_VIADELL'ARTIGIANATO5_CAMPOSANTO_MO_41031_IT"
    }
  ]
}
```

**Math:** header `currentContractAmount` = 3150; `SUM(unitCost×qty)` = 3150+0 = 3150 (matches); `SUM(extendedAmount)` = 3150+3150 = **6300** (≠ header) → Workday rejects. Line 2 `unitCost(0) × qty(1) ≠ extendedAmount(3150)`.

## Workday payload — 00095354 (`Workday_Sync_Payload__c`, full)

```json
"003WC00000sTv2EYAS"
```

A bare JSON string (Salesforce **Contact** key prefix `003`), not a contract document. `Legacy_Sync_Status__c` / `Legacy_Sync_Message__c` are both null.

---

## Phase 0 — scope & Step-1 evidence (2026-06-06)

**Sync-status counts (Order):** Failure **71** · Success **66** · Pending **28,804**.

**Quote 00780874 line comparison (`0Q0WC0000035neH0AQ`)** — the two AAM lines are identical except:

| Field | Line 1 | Line 2 (zeroed) |
|---|---|---|
| NetUnitPrice / NetTotalPrice | 3150 / 3150 | **0 / 0** |
| TotalAdjustmentAmount | 0 | **−3150** |
| Discount / DiscountAmount / Discount_Reason__c / Price_Mode__c | null | null |
| Is_Partner_Price_Overridden__c / Has_Attribute_Adjustment__c | false | false |
| PriceWaterfallIdentifier | `…:114203329788087` | `…:114203329788087` (same run) |
| CreatedBy | Joe Romo | Joe Romo |

→ No manual discount/override fields set; the −3150 came from the **RLM pricing waterfall**.

**Erratic zeroing (not a per-product rule):** 00095354 → 3 AAM lines, 0 zeroed · 00095355 → 2, 1 zeroed · 00095353 → 5 AAM lines, 2 zeroed (+ a Monitoring line with a real 10% discount: net 13500 / list 15000).

**14 orders carry the exact error message:** 00004740, 00004792, 00004800, 00095243, 00095245, 00095261, 00095266, 00095277, 00095287, 00095310, 00095311, 00095312, 00095345, 00095355.

**16 orders currently have a net<list line** (`TotalAdjustmentAmount < 0`): 3 Failure (00095355, 00004792, 00004800) + 13 Pending (00095353, 00095348, 00095218, 00004817, 00004803, 00004775, 00004756, 00004737, 00000270, 00000252, 00000236, 00000178, 00000140). **0 of 66 Success orders** have one.

**Stale-payload caveat:** 00004792 / 00004800 logged payloads use an older schema (`extendedAmount = 0` on all lines; `unitCost` no longer matches current `NetUnitPrice`) → not used as proof. Clean live proof = 00095355.

---

## Verification

```bash
# headers
sf data query -o FortraUAT -q "SELECT OrderNumber, Id, Status, TotalAmount, QuoteId, ContractId, Workday_Sync_Status__c, Workday_Sync_Message__c, Workday_Contract_Type__c, Workday_Contract_ID__c FROM Order WHERE OrderNumber IN ('00095354','00095355')"

# order lines
sf data query -o FortraUAT -q "SELECT Order.OrderNumber, Product2.Name, Quantity, UnitPrice, ListPrice, TotalLineAmount, NetUnitPrice, NetTotalPrice, TotalAdjustmentAmount FROM OrderItem WHERE Order.OrderNumber IN ('00095354','00095355') ORDER BY Order.OrderNumber"

# quote lines (origin of the $0)
sf data query -o FortraUAT -q "SELECT Quote.QuoteNumber, Product2.Name, Quantity, UnitPrice, ListPrice, TotalLineAmount, NetUnitPrice, NetTotalPrice, TotalAdjustmentAmount, Discount FROM QuoteLineItem WHERE QuoteId IN ('0Q0WC0000035neH0AQ','0Q0WC0000035YYn0AM') ORDER BY Quote.QuoteNumber"

# payloads
sf data query -o FortraUAT -r json -q "SELECT OrderNumber, Workday_Sync_Payload__c FROM Order WHERE OrderNumber IN ('00095354','00095355')"
```
