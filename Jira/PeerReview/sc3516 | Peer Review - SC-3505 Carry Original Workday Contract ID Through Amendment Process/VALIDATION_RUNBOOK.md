# SC-3505 Validation Runbook (SC-3516 peer review)

**Org:** FortraUAT · **All queries below are READ-ONLY.** The write-path test plan in §3 requires **explicit UAT authorization** before any DML/deploy (per team policy: read-only is fine; any UAT write — even validate-only — needs a fresh explicit ack).

Record ids referenced throughout (FortraUAT, captured 2026-07-01):
- Amend order (synced): `801WC00000koIE3YAM` (#00095512) · its Quote `0Q0WC0000039fYT0AY`
- Its source/renewal contract: `800WC00000SLdXhYAL` (#00069303)
- Original order on that contract (renewal): `801WC00000koHXqYAM` (#00095510) — **this order's Id is the "original Workday contract ID"**

---

## 1. Reproduce the core facts (read-only SOQL)

### 1a. Workday Contract ID == Order Id (the whole premise)
```bash
sf data query -o FortraUAT -q "SELECT Id, Workday_Contract_ID__c, Type, OriginalActionType FROM Order WHERE Workday_Contract_ID__c != null ORDER BY CreatedDate DESC LIMIT 500"
```
Expect: `Workday_Contract_ID__c` equals `Id` on every row (compare first 15 chars). 200/200 verified during review; 0 mismatches. Population: 29,149 orders carry a WCID.

### 1b. Contract has no Workday field; contract type is Master-only
```bash
sf sobject describe -o FortraUAT --sobject Contract | grep -i workday        # expect: no matches
sf sobject describe -o FortraUAT --sobject Order --json | \
  python3 -c "import sys,json;[print([v['value'] for v in f['picklistValues']]) for f in json.load(sys.stdin)['result']['fields'] if f['name']=='Workday_Contract_Type__c']"
# expect: ['Master_Contract']  (no Alternate/Amendment value)
```

### 1c. The amendment payload carries no original reference (the smoking gun)
```bash
sf data query -o FortraUAT -q "SELECT Workday_Sync_Payload__c FROM Order WHERE Id='801WC00000koIE3YAM'" --json | \
  python3 -c "import sys,json;print(json.load(sys.stdin)['result']['records'][0]['Workday_Sync_Payload__c'])"
```
Expect: `customerContractType=Master_Contract`; `contractReferenceId` / `sfContractId` / `orderId` / `fortraSfdcExternalId` all = `801WC00000koIE3YAM` (the order's own Id); **no** `original*` / `alternate*` key. See `evidence/payload_amend_00095512.json`.

### 1d. Amendment reuses the source contract (premise correction)
```bash
sf data query -o FortraUAT -q "SELECT Id, OrderNumber, Type, OriginalActionType, Workday_Contract_ID__c FROM Order WHERE ContractId='800WC00000SLdXhYAL' ORDER BY CreatedDate"
```
Expect: 2 rows — `#00095510 (Renew)` and `#00095512 (Amend)` — **same contract, two different WCIDs**. Confirms the amendment did not create a new Contract; it minted a new Workday key.

### 1e. Original WCID is derivable from the amendment Quote
```bash
sf data query -o FortraUAT -q "SELECT Id, OrderNumber, Quote.Quote_Type__c, Quote.Renewal_Contract__c, Quote.Original_Order_Id__c, Quote.Original_Order_Id__r.Workday_Contract_ID__c FROM Order WHERE OriginalActionType='Amend'"
```
Expect: 4 of 6 rows resolve `Original_Order_Id__r.Workday_Contract_ID__c` (the value to send as `Original_Customer_Contract_Reference`); 2 of 6 (`Quote_Type__c` null) return null — the native/manual amendments the Quote-only path misses.

### 1f. The stamp flow is unconditional + blank-guarded
```bash
sed -n '27,64p' force-app/main/default/flows/Fortra_Order_Workday_Contract_ID.flow-meta.xml
```
Expect: `inputAssignments` sets `Workday_Contract_ID__c ← $Record.Id`; entry filter `WCID EqualTo '' OR WCID IsNull`; `RecordAfterSave`, `CreateAndUpdate`. Implication: a pre-populated WCID is preserved, but the amendment order still self-stamps if left blank — so the original reference must live in a **separate** field.

---

## 2. Pass/Fail checklist for a future SC-3505 build

| # | Check | Pass condition |
|---|---|---|
| 1 | Original WD contract id stored on the amendment transaction (AC #1) | `Order.Original_Workday_Contract_ID__c` (or chosen field) populated on amendment orders = the source contract's master WCID |
| 2 | Coverage of native/manual amendments (G-3) | Field populated even when `Quote_Type__c` is null (i.e., resolution not solely Quote-based) |
| 3 | Payload carries the reference (AC #2) | `Workday_Sync_Payload__c` for an amendment includes an `originalContractReferenceId`-style key = the master WCID |
| 4 | Contract type expresses amendment (AC #3) | `Workday_Contract_Type__c` = the new Alternate value on amendment orders; payload maps to Workday `Original_Customer_Contract_Reference` + Alternate type |
| 5 | No silent duplicate | An amendment whose original cannot be resolved is **blocked/flagged**, not sent as a headless `Master_Contract` |
| 6 | Workday number-match honored (G-6) | Behavior matches whatever the Workday owner confirms for "Alternate number must match original" |
| 7 | Existing WCID unaffected | `Order.Workday_Contract_ID__c` still = Order.Id (own transaction key preserved); regression on 1a holds |

---

## 3. Write-path test plan (DO NOT RUN without explicit UAT authorization)

To exercise the end-to-end amendment→Workday path and validate a build:

1. Create a clean lifecycle (new order → activate → renewal contract), capturing the master order's WCID.
2. Generate an amendment via the Fortra flow (`Fortra_Create_Amendment_Quote` / `initiateAmendment`) **and** a native/manual amendment (to cover G-3), against the same contract.
3. After the fix: confirm each amendment order's `Original_Workday_Contract_ID__c` = the master WCID, and inspect `Workday_Sync_Payload__c` for the original-reference key + Alternate contract type.
4. If a MuleSoft sandbox is available, confirm the Workday `Submit_Customer_Contract` request populates `Original_Customer_Contract_Reference` and that Workday links (not duplicates) the contract.

`scripts/apex/f04_initiateRenewal.apex` and the amendment flow are the closest existing harnesses for step 2. Any execution of these against UAT is a **write** and must be authorized first.
</content>
