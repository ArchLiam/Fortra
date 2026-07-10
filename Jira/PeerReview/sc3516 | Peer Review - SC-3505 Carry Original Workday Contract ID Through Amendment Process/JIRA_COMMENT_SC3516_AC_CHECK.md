# Jira comment — SC-3505 AC verification (SC-3516), post "complete"

**Re-checked the 3 ACs against the live org after the "implementation complete" note. Result: all three currently FAIL (high confidence).** Read-only across FortraUAT, FortraDP2, MergeBuild, fulltemp, FortraProd, plus repo + git, plus an adversarial pass that specifically tried to prove each AC *is* met.

**AC1 — original WD contract id stored on the amendment transaction → FAIL.** On all 6 amendment orders (`OriginalActionType=Amend`), `Workday_Contract_ID__c` = the order's **own** Id, and `OriginalOrderId` / `Source_Order_Id__c` are null. No new field exists on Order/Contract/Quote in any org to carry the original reference (FLS-independent Tooling check: 0 new Order fields in 60 days). The only lineage, `Quote.Original_Order_Id__c`, predates this ticket by ~6 months, lives on the Quote (not the transaction), and is null for the 2 native/manual amendments.

**AC2 — reference available to the integration → FAIL.** Only 2 of 6 amendment orders have a populated `Workday_Sync_Payload__c`; both carry only self-referential ids (`contractReferenceId`/`sfContractId`/`orderId` all = the amendment's own Id) and **no** original/prior/alternate key. The other 4 payloads are empty. No SF flow/Apex injects an original reference (payload is Mule-built).

**AC3 — Workday can identify the contract to amend → FAIL.** Payloads are `customerContractType=Master_Contract` with no `Original_Customer_Contract_Reference`; the `Workday_Contract_Type__c` picklist has only `Master_Contract` (no Alternate/Amendment value) in every sandbox.

**Two honest caveats before we close this as "not done":**
1. The **MuleSoft mapping repo isn't in my workspace** — if the work was done as a DataWeave change, I can't see it. *But* the 2 amendment orders that already synced still produced payloads with no original reference, so nothing correct has reached Workday yet.
2. **4 of 6** amendment payloads are empty (Pending) — proving the negative for those needs a re-sync.

**To confirm "complete," please provide:** (a) the MuleSoft branch/PR that emits `Original_Customer_Contract_Reference`, and (b) a re-synced amendment order whose `Workday_Sync_Payload__c` shows an original-contract key whose value ≠ the amendment order's own Id. If the intended carrier is `Quote.Original_Order_Id__c`, note it doesn't cover the 2 native/manual amendments and isn't on the transaction.

Full evidence + per-AC "what would make it pass": `AC_VERIFICATION_SC3505.md` in the SC-3516 folder.
</content>
