# Jira comment — SC-3505 peer review result: FAILED (SC-3516)

---

🔴 **PEER REVIEW RESULT — SC-3505: FAILED**

Re-verified all 3 acceptance criteria against the **live org** after the "implementation complete" note. **All three FAIL (high confidence).** No original-contract reference reaches Workday, and no new metadata implementing this ticket exists anywhere.

| # | Acceptance Criterion | Result |
|---|---|---|
| **AC1** | Original WD contract id stored on the amendment transaction | ❌ **FAIL** |
| **AC2** | Reference available to the integration (MuleSoft) | ❌ **FAIL** |
| **AC3** | Workday can identify which contract to amend | ❌ **FAIL** |

---

### 🎯 Root cause in one line

There is exactly **one object** stamping a "Workday Contract ID," and it stamps the **wrong value**.

Flow **`Fortra_Order_Workday_Contract_ID`** (Active, on the **Order** object, RecordAfterSave) writes:

> `Order.Workday_Contract_ID__c = Order.Id`  *(the order's own record Id — write-once, blank-guarded)*

So **every** order — new, renewal, **amendment** — mints its *own* Workday key. An amendment order stamps **its own Id**, with **nothing** pointing back to the original contract. This is the pre-existing mechanism, **not** a fix for this ticket. Verified 200/200 sampled orders: `Workday_Contract_ID__c == Id`.

---

### 🔍 Evidence (live, read-only)

- **AC1:** On all 6 amendment orders (`OriginalActionType=Amend`), `Workday_Contract_ID__c` = the order's **own** Id; `OriginalOrderId` / `Source_Order_Id__c` are null. **No new field** exists on Order / Contract / Quote in **any** org to carry an original reference (FLS-independent Tooling check: 0 new Order fields in 60 days).
- **AC2:** Of 6 amendment orders, only 2 have a populated `Workday_Sync_Payload__c`; **both** carry only self-referential ids (`contractReferenceId` / `sfContractId` / `orderId` all = the amendment's **own** Id) and **no** original / prior / alternate key. The other 4 payloads are empty (Pending).
- **AC3:** Payloads are `customerContractType=Master_Contract` with **no** `Original_Customer_Contract_Reference`; the `Workday_Contract_Type__c` picklist has **only** `Master_Contract` (no Alternate/Amendment value) in every sandbox.

**Cross-checked:** no new field / picklist value / flow / Apex / git artifact for SC-3505 in FortraUAT, FortraDP2, MergeBuild, fulltemp, or FortraProd — including an adversarial pass that tried to *prove* each AC is met. Confirmed still true as of 2026‑07‑06.

---

### ✅ What would flip this to PASS

1. **A field on the amendment Order** carrying the **original** WCID (≠ its own Id), populated for **all 6** amendments — including the **2 native/manual** ones (#00095531, #00095676) that have no Quote lineage and no contract sibling.
2. **A MuleSoft mapping change** that reads that field and emits `Original_Customer_Contract_Reference` into `Submit_Customer_Contract`. *A Salesforce field alone never reaches Workday.*
3. **A new `Workday_Contract_Type__c` value** (Alternate/Amendment) so the type — not free‑text `name` — conveys the amend relationship.
4. **Re-sync one Pending amendment** and show its payload carrying an original-contract key whose value **≠** the order's own Id.

---

### ⚠️ Two honest caveats (why I'm asking, not just closing)

1. The **MuleSoft mapping repo is not in my workspace** — if the work shipped as a DataWeave change, I can't see it. *But* the 2 amendment orders that already synced still produced payloads with no original reference, so nothing correct has reached Workday yet.
2. **4 of 6** amendment payloads are empty (Pending) — definitively proving the negative for those needs a re-sync (a write).

**@Marc — to move this to Done, please share:** (a) the **MuleSoft branch/PR** that emits `Original_Customer_Contract_Reference`, and (b) a **re-synced amendment order** whose `Workday_Sync_Payload__c` shows an original-contract key ≠ the amendment order's own Id.

Full per-AC evidence and "what makes each pass": `AC_VERIFICATION_SC3505.md` (SC-3516 folder).
