# Jira comment — SC-3505 status: BLOCKED (parked)

---

🔴 **SC-3505 — STATUS: BLOCKED (parked)**

**Blocked on the MuleSoft implementation.** Permender (MuleSoft) needs to work through the **amendment / renewal contract → Workday** solution before this ticket can be completed. Parking SC-3505 until that lands — agreed with Marc on 2026-07-07.

---

### 📍 Where it stands
No code is deployed yet — the outbound-key flow `Fortra_Order_Workday_Contract_ID` is still the original own-Id stamp (V3, Active). The Solution Design in this ticket is a **proposal, not yet built.**

### ⚠️ On resume — this is *not only* a MuleSoft dependency
The **Salesforce-side design also needs rework** before build. As written it will not resolve a correct key even after the Mule mapping lands:

1. **Shared-key conflicts with the 1:1 Order↔Contract mapping.** The field map is `Order.Workday_Contract_ID__c → Workday Customer_Contract_ID`. Making the initial sale + amendments + renewals share **one** key collapses multiple Orders into a single Workday contract. Workday's own model (`Original_Customer_Contract_Reference` / Alternate Contract) — and the original ACs — call for **own key + a separate original-reference field**, not a shared key.
2. **The lineage the design walks is empty.** `Contract.SourceOrderId` is blank or self-referential on all amendment orders, and `Contract.Original_Contract__c` / `ParentContractId` are **0 of 29,455** populated — so the walk resolves to own-Id / NULL on current data.

### ✅ Next steps to unblock
1. **MuleSoft** — Permender defines the amendment/renewal → Workday contract handling.
2. **Salesforce** — confirm the target model with the integration owner (shared key vs. own-key + original-reference), then rework the SF design accordingly. Do **not** build on the current shared-key + `SourceOrderId` approach.

Full peer review with per-record evidence: SC-3516 folder (`PEER_REVIEW_ROUND2_SC3505.md`).
