# SC-3406 (origin ref MTC-0845) — Live evidence snapshot (FortraUAT, 2026-06-15, read-only)

## Repro quote
```
Quote 0Q0WC0000038PHF0A2 = "Q-COLA Renewal Test -- do not delete (latest) copy 2 andy-2026-06-12"
Account "AB Test Account" | CurrencyIsoCode AUD | Status Accepted | Pricebook 01sWC0000022GHFYA2
Created 2026-06-12T16:38:33Z | LastModified 2026-06-14T10:05:22Z
```

## Quote lines — null term fields (root of the error)
| QLI Id | Product | SellingModel | PricingTermCount | StartDate | EndDate | ServiceDate |
|---|---|---|---|---|---|---|
| 0QLWC000003dbE54AI | ES-CEP-RSL-ACTIDB (Active Defense BEC Threat Intel) | TermDefined/Annual | **null** | 2026-06-12 | 2027-06-01 | null |
| 0QLWC000003eFD74AM | ES-SEG-NROR-HARDWA (Hardware) | TermDefined/Annual | **null** | 2026-06-14 | **null** | null |

→ Line 1 → first-stage error never reached (EndDate present); Line 2 (Hardware) → "EndDate is required". Both null PTC → "PricingTermCount is required". Hardware product `01tWC00000DD1PZYA1` has ONLY one ProductSellingModelOption = "Term Based - Annual" (no perpetual/one-time).

## Rolled-back orders (atomic convert failure)
```
Order 801WC00000kdgubYAA / 801WC00000khJpkYAE   -> 0 records
OrderItem 802WC00000OjUiUYAV                     -> 0 records
Orders where QuoteId=0Q0WC0000038PHF0A2          -> 0 records
```

## SC-3411 V6 backstop deploy time
```
Fortra_OrderItem_Set_Dates  V6  Active  CreatedDate 2026-06-15T19:04:12Z   (V5 obsolete, 2026-06-10)
```
The MTC-0845 report image is dated 2026-06-12 — i.e. the convert was attempted ~3 days BEFORE V6 existed.

## DECISIVE empirical proof — V6 backfills the exact MTC scenario on convert
Source quote lines that were null PTC + null EndDate + null ServiceDate (= MTC Hardware case):
| QLI Id | Product | Quote PTC | Quote EndDate | Quote ServiceDate |
|---|---|---|---|---|
| 0QLWC000003erlR4AQ | GS-EFA-RSSH-ARCUS | null | null | null |
| 0QLWC000003erru4AA | GS-GSE-RSS-AAMYS | null | null | null |

After convert (post-V6) → resulting OrderItems:
| Order | Product | OI PTC | OI EndDate | OI ServiceDate | Order Status |
|---|---|---|---|---|---|
| 00095511 | GS-EFA-RSSH-ARCUS | **1** | **2027-06-14** | 2026-06-15 | Order Complete |
| 00095513 | GS-GSE-RSS-AAMYS | **1** | **2027-06-14** | 2026-06-15 | Order Complete |

`createOrderFromQuote` defaults OrderItem.ServiceDate → Order.EffectiveDate (2026-06-15); V6 then computes EndDate = ADDMONTHS(ServiceDate,12)-1 = 2027-06-14 and PricingTermCount = 1.

## Pre/post V6 boundary
| Order | Created | TermDefined OI PricingTermCount | Status |
|---|---|---|---|
| 00095507 | 2026-06-15T17:35Z (pre-V6) | **null** | Draft |
| 00095509–00095513 | 19:51–22:07Z (post-V6) | **1** | Order Complete |
