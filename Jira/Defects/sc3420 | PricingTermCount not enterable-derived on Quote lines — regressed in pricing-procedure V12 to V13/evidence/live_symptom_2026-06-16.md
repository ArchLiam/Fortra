# Evidence — live symptom + field describe (FortraUAT, 2026-06-16, read-only)

## Recent TermDefined QuoteLineItems — PricingTermCount universally null

```sql
SELECT Id, Product2.Name, PricingTermCount, SubscriptionTerm, SubscriptionTermUnit,
       EndDate, StartDate, ProductSellingModel.SellingModelType, CreatedDate
FROM QuoteLineItem
WHERE ProductSellingModel.SellingModelType='TermDefined' AND CreatedDate=LAST_N_DAYS:3
ORDER BY CreatedDate DESC LIMIT 8
```

| QLI | Product | PTC | SubTerm | Unit | EndDate | StartDate | Created |
|---|---|---|---|---|---|---|---|
| 0QLWC000003fF9U4AU | OCR Feature for SEG | **null** | null | Annual | 2027-03-31 | 2026-06-16 | 16:24:35Z |
| 0QLWC000003fF9T4AU | Data Redaction for SEG | **null** | null | Annual | 2027-03-31 | 2026-06-16 | 16:24:35Z |
| 0QLWC000003fF9S4AU | Structural Sanitization for SEG | **null** | null | Annual | 2027-03-31 | 2026-06-16 | 16:24:35Z |
| 0QLWC000003fF9R4AU | SECURE Exchange Gateway | **null** | null | Annual | 2027-03-31 | 2026-06-16 | 16:24:35Z |
| 0QLWC000003fD9F4AU | OCR Feature for SEG | **null** | 12 | Annual | 2027-03-31 | 2026-04-01 | 14:53:24Z |
| 0QLWC000003fCRh4AM | Data Redaction for SEG | **null** | 12 | Annual | 2027-03-31 | 2026-04-01 | 14:15:22Z |
| 0QLWC000003fCOT4A2 | Structural Sanitization for SEG | **null** | 12 | Annual | 2027-03-31 | 2026-04-01 | 14:14:37Z |
| 0QLWC000003fBUW4A2 | SECURE Exchange Gateway | **null** | 12 | Annual | 2027-03-31 | 2026-04-01 | 14:13:32Z |

- `PricingTermCount` = null on **8/8** lines created in the last 3 days — the regression is live under active V14.
- `EndDate` present on all (8/8) → the gap is PTC, not EndDate.
- `SubscriptionTerm` present on the 14:xx lines, null on the 16:24 lines → secondary data-entry nuance (see README §7), independent of the PTC engine break.

## Field describe — platform read-only

```
sf sobject describe --sobject QuoteLineItem  →  field PricingTermCount:
  createable  = false
  updateable  = false
  calculated  = false
  type        = double
  calcFormula = None
```

→ Only the native RLM pricing engine can write `QuoteLineItem.PricingTermCount`. No before-save flow / Apex can set it at the quote tier. (Compare `OrderItem.PricingTermCount`: createable=true/updateable=true — why the order-tier SC-3411 V6 backstop is feasible but a quote-tier one is not.)
