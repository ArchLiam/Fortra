# Jira comment — SC-3505 peer review (SC-3516)

**Peer review — SC-3505 · Verdict: APPROVE INTENT, RETURN FOR DESIGN.** Read-only analysis in FortraUAT, 2026-07-01.

**The gap is real and I confirmed it on live data.** The Workday sync payload for a real, synced amendment order (00095512) contains **no reference to the contract being amended** — every id (`sfContractId`, `orderId`, `contractReferenceId`, `fortraSfdcExternalId`) is the amendment order's **own record Id**, and `customerContractType` = `"Master_Contract"` (the only value the picklist offers). The sole "amendment" signal is the free-text `name: "Amendment Quote"`. So Workday receives it as a brand-new master contract with nothing to amend against. AC #1–#3 are all currently unmet. ✅ ticket is justified.

**Two facts that change how we build it:**
1. The "Workday contract ID" **is the Salesforce Order Id** — flow `Fortra_Order_Workday_Contract_ID` stamps `Order.Workday_Contract_ID__c = Order.Id` on every order (200/200 verified). So *every* order — new, renewal, amendment — mints its own Workday key. That, not "a new SF Contract," is why the original link is lost.
2. The original WCID is **already derivable** at amendment time: `Quote.Original_Order_Id__c` (→ the original order, whose WCID = its own Id) and `Quote.Renewal_Contract__c` ("Source Contract"). It resolves cleanly for **4 of 6** amend orders — the ones created through the Fortra amendment flow.

**One correction to the description:** "Because Salesforce creates a new contract record" — for the native amendment path this isn't what happens. RLM amendments **reuse the source contract in place** (amend 00095512 shares contract 00069303 with renewal order 00095510). Renewals are the pattern that creates a new Contract. The fix belongs on the amendment **Order/payload** (carry the original WCID), not on setting lineage on a new contract.

**What the ticket needs before build:**
- **Design decision — where the original WCID lives.** Recommend anchoring it on the **Contract** (`Contract.Workday_Contract_ID__c`, stamped when the master order syncs) and reading it onto the amendment order (`Order.Original_Workday_Contract_ID__c = ContractId→Contract.Workday_Contract_ID__c`). This covers native/manual amendments too — a Quote-only approach misses **2 of 6** sampled amendments (no `Original_Order_Id__c`).
- **MuleSoft is a hard dependency (not optional).** Salesforce only publishes the Order Id; MuleSoft queries the Order and builds the Workday `Submit_Customer_Contract` payload. Stamping a SF field is inert until Mule maps it to Workday's `Original_Customer_Contract_Reference` and sets an Alternate contract type. AC #2/#3 cannot close without a linked Mule work item. (Note: AC #2 says "Permendor" — there's no such system here; the integration is **MuleSoft**.)
- **Add a `Workday_Contract_Type__c` = Alternate value** (today it's Master-only) so amendments are typed as amendments, not the free-text name.
- **Confirm with the Workday owner:** the API validation *"Alternate Customer Contract Number must match Original Customer Contract Number if supplied"* — does the amendment reuse the original's number, or keep its own key + add the reference? This decides the field design.
- **State scope:** renewals share the identical gap (each renewal is also a `Master_Contract` with no prior reference); and define what "original" means for a renewed/multiply-amended contract.

Full report, ranked gaps (G-1…G-7), the recommended design, and the reproduction SOQL are in the SC-3516 peer-review folder (`PEER_REVIEW_REPORT.md`, `VALIDATION_RUNBOOK.md`, `evidence/`).
</content>
