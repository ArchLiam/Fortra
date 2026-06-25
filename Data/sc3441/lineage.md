# SC-3441 — Cancellation Line Price Lineage Dossier

Ticket: SC-3441 "Order Cancellation Line Item Displays Total Price as USD 0.00 Instead of Negative Amount"
Reporter: Joe Romo. Org: FortraUAT (00DWC000006eUFF2A2). Date: 2026-06-24.
Bug order: 00095539 / 801WC00000ktJPMYA2. Expected cancellation Total Price = -3000.00; actual = 0.00.

All IDs below queried LIVE from FortraUAT.

## 1. The cancellation object graph (top-down)

```
Account 001WC00000WiR9YYAV
  |
  +-- Contract 00069316 / 800WC00000SP6oTYAT
  |     Status Activated, Term 12 mo, 2026-06-16 -> 2027-06-15
  |
  +-- Asset 02iWC000008MpX7YAK  "Arcus Hosting"  (Product2 01tWC00000DD11IYAT)
  |     Price = 3000   TotalLifecycleAmount = 3000   CurrentAmount = 0
  |     Quantity 1, CurrentQuantity 1, Status Installed
  |     PricingSource = NULL   RenewalTerm 1 Months
  |     Lifecycle 2026-06-16 -> 2027-06-15
  |     |
  |     +-- AssetAction 4nLWC00000333aj2AA  AA-000543593
  |     |     Type=Generate  CategoryEnum="Initial Sale"
  |     |     Amount 3000  TotalInitialSaleAmount 3000  TotalCancellationsAmount 0  Qty 1
  |     |     |
  |     |     +-- AssetActionSource 4nMWC0000046hkj2AA  AAS-000543597   *** PRICE SOURCE OF TRUTH ***
  |     |           ReferenceEntityItemId = 802WC00000OtSYxYAN  (the ORIGINAL sold OrderItem)
  |     |           Quantity 1
  |     |           ListPrice    = 3000
  |     |           UnitPrice    = 3000
  |     |           NetUnitPrice = 3000     <-- the net the customer paid
  |     |           TotalLineAmount = 3000  TotalPrice = 3000
  |     |           PricebookEntryId   = 01uWC000005wrrCYAQ   (SAME PBE as cancel line)
  |     |           ProductSellingModelId = 0jPWC000000060b2AA (SAME selling model)
  |     |           Start 2026-06-16  End 2027-06-15
  |     |
  |     |     (NOTE: there is NO AssetAction of Type Cancel and NO AssetActionSource
  |     |      referencing the cancellation OrderItem. The cancel never produced a
  |     |      priced asset-action source row -> TotalCancellationsAmount stayed 0.)
  |
  +-- ORIGINAL sale order 801WC00000krvqVYAQ
  |     OrderItem 802WC00000OtSYxYAN  (OrderAction 8OAWC000002Sp4r4AC = the add/generate)
  |        Qty 1, StartQty 0 -> EndQty 1
  |        ListPrice 3000, UnitPrice 3000, NetUnitPrice 3000, TotalPrice 3000, NetTotalPrice 3000
  |        PBE 01uWC000005wrrCYAQ, PricingTermCount 1, ServiceDate 2026-06-16, End 2027-06-15
  |
  +-- CANCELLATION order 00095539 / 801WC00000ktJPMYA2  (OriginalActionType 'Cancel', Status 'Order Complete')
        OrderAction 8OAWC000002SxiL4AS  OAC-0000069052
           Type = 'Cancel'   Subtype = null
           SourceAssetId = 02iWC000008MpX7YAK   <-- ASSET-BASED CANCELLATION (initiated from the Asset)
        |
        +-- OrderItem 802WC00000OugI7YAJ   *** THE BUGGY LINE ***
              Qty -1, StartQty 1 -> EndQty 0
              ListPrice 3000  UnitPrice NULL  NetUnitPrice NULL
              TotalPrice 0    NetTotalPrice 0    TotalLineAmount 0
              PBE 01uWC000005wrrCYAQ, PricingTermCount 1, ServiceDate 2026-06-16, End 2027-06-15
              Asset__c null, OriginalOrderItemId null, PriceRevisionPolicyId null
              |
              +-- OrderItemDetail 14CWC000001KXDl2AO   *** SMOKING GUN ***
                    UnitPrice    = 3000   (carried correctly!)
                    NetUnitPrice = 3000   (carried correctly!)
                    Quantity     = -1
                    TotalLineAmount = 0   TotalPrice = 0   <-- net*qty NOT applied
```

## 2. Where the cancellation price is SUPPOSED to come from

This is an **asset-based cancellation** (OrderAction.Type='Cancel', OrderAction.SourceAssetId=02iWC000008MpX7YAK).
The magnitude to refund is the original NET price the customer paid for that subscription term:

  Source of truth = AssetActionSource.NetUnitPrice = 3000  (AAS-000543597)
  Equivalently     = Asset.Price = 3000 / original OrderItem.NetUnitPrice = 3000

Expected cancellation line:
  NetUnitPrice = 3000  (refund-the-net carried from the asset's original sale)
  LineItemQuantity = -1  (StartQty 1 -> EndQty 0)
  => TotalPrice / NetTotalPrice = NetUnitPrice * Quantity = 3000 * -1 = **-3000.00**

Selling model 0jPWC000000060b2AA = "Term Based - Annual", SellingModelType=TermDefined,
PricingTerm 1 Annual. PricingTermCount=1 on both lines, ServiceDate->EndDate spans the full
term (2026-06-16 .. 2027-06-15), so there is NO partial-term proration: the full -3000 is owed.

## 3. KEY FINDING — the net price WAS sourced; the math step zeroed it

The bug is NOT a failure to find the price. NetUnitPrice 3000 made it all the way to the
cancellation line's **OrderItemDetail** (14CWC000001KXDl2AO: UnitPrice 3000, NetUnitPrice 3000,
Qty -1). Yet TotalLineAmount/TotalPrice on that same detail row = 0, and the parent OrderItem
came out with NetUnitPrice=NULL / TotalPrice=0.

So two things go wrong in the pricing procedure for the negative-qty line:
  (a) the line-total step did NOT compute NetUnitPrice(3000) * LineItemQuantity(-1) = -3000;
      the detail row shows 3000 net but 0 total.
  (b) the net was not promoted back up to OrderItem.NetUnitPrice (stayed null), so the
      header copy NetTotalPrice->TotalPrice also yields 0.

The same defect reproduces at the QUOTE stage (Cancellation Quote 0Q0WC000003A8PB0A0,
QLI 0QLWC000003fKAj4AM: Qty -1, ListPrice 3000, UnitPrice NULL, NetUnitPrice NULL, TotalPrice 0)
— consistent with one shared Rev_Mgmt_Default_Pricing_Procedure for Quote+Order.

## 4. Pricing procedure structure (handed to next agent)

File: Data/sc3441/retrieve/unpackaged/expressionSetDefinition/Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition (api v66, 92,611 lines).
The procedure is NOT branched on "cancel" or "negative quantity". It is branched on selling-model
type and pricing channel. Relevant repeated steps (count of variant copies):
  - "NetUnitPrice * LineItemQuantity"  (38 occurrences, e.g. lines 1837, 6699, ...)  <- the line-total formula
  - "InputUnitPrice * LineItemQuantity" (e.g. line 3490)
  - "Subscription Pricing" (62x), "Term-Defined Subscription Filter on the Selling Model Type (Line-Level)" (11x)
  - "Null-Safe Line Adjustment" (14x)  <- likely where a null seed is coalesced
  - "Aggregate Price" / "Total Subscription/Software/Services" / "Total Amount" rollups (17x each)
Because the Arcus line is TermDefined, it flows through the Subscription Pricing / Term-Defined
filter branch. The open question is why, on a StartQty>EndQty (negative) line, that branch leaves
the line-level NetUnitPrice null on the OrderItem (the detail row got 3000 but total stayed 0).
This branch-selection / null-seed investigation is the next step (out of this agent's scope).

## 5. Field-by-field "what -3000 equals"

| Target on cancel line 802WC00000OugI7YAJ | Should be | Sourced from |
|---|---|---|
| NetUnitPrice | 3000 | AssetActionSource.NetUnitPrice (AAS-000543597) = Asset.Price = orig OrderItem.NetUnitPrice |
| Quantity (LineItemQuantity) | -1 | StartQuantity 1 -> EndQuantity 0 (already correct) |
| ListPrice | 3000 | PBE 01uWC000005wrrCYAQ UnitPrice (already correct on line) |
| TotalPrice / NetTotalPrice / TotalLineAmount | **-3000.00** | NetUnitPrice * Quantity = 3000 * -1 |

No proration multiplier applies (full term, PricingTermCount 1).
