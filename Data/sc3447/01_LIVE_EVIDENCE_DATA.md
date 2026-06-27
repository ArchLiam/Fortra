# SC-3447 — Live evidence data (FortraUAT, 2026-06-26, read-only)

## Flow state (live)
| ApiName | IsActive | ProcessType | TriggerType | Active version |
|---|---|---|---|---|
| Fortra_Quote_to_Order_Conversion | true | Flow (screen) | — | 301WC00000kSRnZYAW |
| Fortra_OrderItem_Set_Dates | true | AutoLaunchedFlow | RecordBeforeSave (CreateAndUpdate) | 301WC00000knsJNYAY (V6) |
| Fortra_OrderItem_Set_Workday_Contract_Line_Type | true | AutoLaunchedFlow | RecordAfterSave (CreateAndUpdate) | 301WC00000kUYVFYA4 (V11) |
| **Fortra_Autolaunched_Set_Workday_Contract_Line_Type** | **false** | AutoLaunchedFlow | — | **none (deprecated, SC-3366)** |
| Fortra_Order_After_Save_Set_Workday_Contract_Line_Type | false | AutoLaunchedFlow | RecordAfterSave | none |

- No **Apex triggers** on OrderItem.
- No live flow invokes the deprecated Autolaunched flow as a subflow (grep of all live flow XML = 0 refs).
- Convert action chain (all `flowTransactionModel=CurrentTransaction`, one sync request):
  `ChecklistValidationService → createOrderFromQuote → QuoteToOrderFieldMapper → PowerOrderSplittingService → OrderRepriceInvocable → Activate_Contract/Activate_Order`.

## Power catalog (Product2 WHERE Solution_Group__c='Power')
| Metric | Value |
|---|---|
| Total Power products | 3,406 |
| Active | 2,782 |
| Split type `Order Line Only` | 3,405 |
| Split type `Order Line and Hardware` | 1 |

Repro line product: `01tWC00000DD11GYAT` Abstract — Power / Order Line Only / Family=Subscription / Active.

## Power quantity reality (OrderItem / QuoteLineItem, Solution_Group='Power', qty>1)
| Metric | Value |
|---|---|
| Power OrderItems qty>1 (incl. sentinel) | 3,816 |
| Max Quantity | **999,999** |
| qty=999,999 sentinel lines | 134 |
| Real qty>1 (excl. sentinel) | 3,682 |
| Real qty>50 (excl. sentinel) | 419 |

Top non-sentinel quantities (product / revCat):
```
99,999  RC_41000  Insite Analytics          (sentinel-ish)
 9,999  RC_41000  Sequel Repository(Designer)(sentinel-ish)
 9,900  RC_41202  Powertech MFA for IBM i    (user/seat count)
 7,500  RC_41202  Powertech Password Self Help for IBM i (seats)
 5,800  RC_41202  Powertech Password Self Help for IBM i (seats)
 5,080  RC_41000  Safestone Password Self Help Users     (seats)
 4,875  RC_41000  Powertech Password Self Help for IBM i (seats)
 4,150  RC_41000  Powertech Password Self Help for IBM i (seats)
```
→ Power `Quantity` is a **license/seat count or unlimited sentinel**, not a physical-machine count.

## Dead-transaction governor snapshot (from original 19.5 MB log 07LWC00000PCXmd2AH)
SOQL 19/100 · DML stmts 19/150 · DML rows 480/10,000 · **CPU >10,000/10,000 (breach)** · ~401 clones · ~1,293
flow interviews (of which ~408 were the now-deactivated deprecated flow). CPU — not SOQL/DML — is what throws.

## Split-clone stamping check (Is_Split_Line__c=true sample)
Mixed: some lines have `Workday_Contract_Line_Type__c`=null / billing dates=null / PricingTermCount=0; others
populated. → clones are **not** reliably pre-stamped; an Apex stamp is required if the per-clone flows are
suppressed (heterogeneity is likely historical, pre/post SC-3411 date-backstop).
