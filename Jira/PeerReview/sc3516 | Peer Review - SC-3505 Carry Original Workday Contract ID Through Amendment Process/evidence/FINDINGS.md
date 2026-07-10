# SC-3505 — Evidence & Fact Table (SC-3516 peer review)

**Org:** FortraUAT · **Captured:** 2026-07-01 · **Method:** `sf sobject describe` + `sf data query` (read-only).

## Fact table

| # | Fact | Value / Evidence |
|---|---|---|
| F1 | Total Orders | 29,174 |
| F2 | Orders with `Workday_Contract_ID__c` (non-null) | 29,149 |
| F3 | `Workday_Contract_ID__c` == `Order.Id` | 200/200 sampled, 0 mismatches |
| F4 | Stamp mechanism | Flow `Fortra_Order_Workday_Contract_ID` (Active, RecordAfterSave, CreateAndUpdate, api 66): sets `Workday_Contract_ID__c ← $Record.Id`, entry filter `WCID EqualTo '' OR IsNull` |
| F5 | `Workday_Contract_Type__c` picklist values | `['Master_Contract']` — no Alternate/Amendment value |
| F6 | Orders carrying type Master_Contract | 29,174 (all) |
| F7 | Contract Workday fields | none (`describe Contract` → 0 Workday matches); no ext-id contract field populated |
| F8 | Outbound event | `Order_Completed_WD__e`, single field `Order_Id__c` (Mule builds payload) |
| F9 | `OriginalActionType=Amend` orders | 6 total; sync status: 2 Success, 4 Pending |
| F10 | Amendment reuses source contract | amend 00095512 `ContractId` = 800WC00000SLdXhYAL = `Quote.Renewal_Contract__c`; that contract holds `[Renew 00095510, Amend 00095512]` |
| F11 | Quote→original WCID resolves | 4/6 amend orders (Quote_Type__c=Amendment); 2/6 null (native/manual) |

## Amendment order lineage (all 6)

| Amend Order | WCID (own Id) | Quote_Type__c | Renewal_Contract__c (source) | Original_Order_Id__c | Resolved original WCID | Sync |
|---|---|---|---|---|---|---|
| 00000656 (801WC00000eL6A9YAK) | 801WC00000eL6A9YAK | Amendment | 800WC00000OVQmpYAH | 801WC00000eLglEYAS | 801WC00000eLglEYAS | Pending |
| 00095512 (801WC00000koIE3YAM) | 801WC00000koIE3YAM | Amendment | 800WC00000SLdXhYAL | 801WC00000koHXqYAM | 801WC00000koHXqYAM | Success |
| 00095531 (801WC00000ksL59YAE) | 801WC00000ksL59YAE | *(null)* | *(mismatch)* | null | — | Pending |
| 00095635 (801WC00000lqWKGYA2) | 801WC00000lqWKGYA2 | Amendment | 800WC00000Sw6WLYAZ | 801WC00000lqY7OYAU | 801WC00000lqY7OYAU | Pending |
| 00095642 (801WC00000ltUiuYAE) | 801WC00000ltUiuYAE | Amendment | 800WC00000Sy3SpYAJ | 801WC00000ltV8VYAU | 801WC00000ltV8VYAU | Success |
| 00095676 (801WC00000mA6TcYAK) | 801WC00000mA6TcYAK | *(null)* | null | null | — | Pending |

## Contract-reuse per amend order

| Amend # | Contract | Orders on contract |
|---|---|---|
| 00095512 | 800WC00000SLdXhYAL | 2 — [Renew, Amend] |
| 00000656 | 800WC00000OVQmpYAH | 2 — [Amend, original] |
| 00095635 | 800WC00000Sw6WLYAZ | 2 — [Amend, original] |
| 00095642 | 800WC00000Sy3SpYAJ | 2 — [Amend, original] |
| 00095531 | 800WC00000SOGWYYA5 | 1 — solo |
| 00095676 | 800WC00000T5UsnYAF | 1 — solo |

## Key Workday API field (from `sc3143/workday-api-reference/Submit_Customer_Contract.md`, v46.1)
- `Original_Customer_Contract_Reference` `Customer_ContractObject` `[0..1]` — "Original Customer Contract. The Customer Contract used as source for this Alternate Customer Contract."
- Validation: "Alternate Customer Contract Number must match Original Customer Contract Number if supplied." / "Cannot create Alternate Contract if Original Contract is in Draft status."

## Payload files
- `payload_amend_00095512.json` — live amendment payload (Master_Contract, no original ref).
- `payload_renew_00095510.json` — renewal sibling (same structural gap).
</content>
