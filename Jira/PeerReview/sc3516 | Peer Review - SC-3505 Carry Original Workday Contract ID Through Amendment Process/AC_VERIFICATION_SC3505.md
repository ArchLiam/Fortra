# SC-3505 — AC Verification (post "implementation complete" claim)

**Reviewer:** Liam Jeong (SC-3516) · **Org(s):** FortraUAT, FortraDP2, MergeBuild, fulltemp, FortraProd · **Date:** 2026-07-02 · **All checks read-only.**

**Trigger:** Marc reported SC-3505 implementation **complete**. This document re-verifies the three acceptance criteria against the **current** live org state (not the earlier "To Do" snapshot). Method: cross-org schema sweep + payload-path analysis + live payload re-pull on all 6 amendment orders + git/provenance + a 12-agent adversarial workflow that tried, in good faith, to **prove each AC is met** (steelman). Raw workflow output: `evidence/ac_verification_workflow_raw.json`.

---

## Verdict

| AC | Verdict | Confidence |
|---|---|---|
| **AC1** — Original Workday contract identifier is stored on the amendment transaction | ❌ **FAIL** | High |
| **AC2** — Reference is available to Permendor (MuleSoft) integration/processing | ❌ **FAIL** | High |
| **AC3** — Workday can identify which existing contract should be amended | ❌ **FAIL** | High |

**Overall: SC-3505 is NOT implemented in the Salesforce layer of any inspected org.** No new field, no new picklist value, no new/changed flow or Apex, no git artifact. The current amendment payloads still carry only the amendment order's **own** Id and `customerContractType=Master_Contract`. The adversarial steelman on all three ACs returned **no pass evidence** and did **not** overturn.

> Fairness caveat (two honest blind spots — see §4): the **MuleSoft mapping repo is not in this workspace**, and **4 of 6** amendment orders have empty (Pending) payloads. Neither blind spot can flip the verdict on the evidence available — the 2 orders that *have* synced still carry no original reference — but a definitive live confirmation for the Pending 4 requires a re-sync (a write) and/or Marc sharing the Mule branch.

---

## AC-by-AC evidence

### AC1 — "Original Workday contract identifier is stored on the amendment transaction" → FAIL
- The amendment **transaction** is the Order. Across all 6 `OriginalActionType=Amend` orders in FortraUAT: `Order.Workday_Contract_ID__c` == the order's **own** Id (self-reference), and standard `Order.OriginalOrderId` **and** `Order.Source_Order_Id__c` are **NULL** on all 6. `Contract.Original_Contract__c` is NULL on all 6 contracts.
- **No purpose-built field** exists on Order/Contract/Quote in any of the 5 orgs to carry the original Workday contract reference. FLS-independent Tooling-API check: in the last 60 days there are **zero** new Order fields; the only new Contract/Quote fields are renewal-scoped (`Contract.Renewal_Opportunity__c`, `Quote.Renewal_Quote_Stale__c`) — neither is an original-contract carrier.
- The only lineage that exists, `Quote.Original_Order_Id__c`, **predates the ticket** (created 2026-01-09), lives on the **Quote** (not the transaction), is never emitted, and is **NULL for 2/6** native/manual amendments (#00095531, #00095676).
- **To pass:** a field on the amendment Order (e.g. `Original_Workday_Contract_ID__c`) stamped with the **original** order's Id, populated for **all 6** — including the 2 native/manual amendments where no Quote lineage and no contract sibling exist.

### AC2 — "Reference is available to Permendor/MuleSoft integration" → FAIL
- Of the 6 amend orders, only **2** (#00095512, #00095642) have a populated `Workday_Sync_Payload__c`; the other **4 are empty** (Sync=Pending).
- In **both** populated payloads, every identity key (`sfContractId`, `orderId`, `fortraSfdcExternalId`, `contractReferenceId`) == the amendment order's **own** Id. A keyed scan for original/prior/amend/parent/source/predecessor returned **zero** hits.
- No SF Apex/flow injects an original-contract reference (grep of `force-app` classes+flows for the payload keys / `Original_Customer_Contract` = nothing). SF outbound is `Order_Completed_WD__e` carrying only `Order_Id__c`; **MuleSoft builds the payload**. Mule *could* derive the original from `Quote.Original_Order_Id__c` (4/6) or the shared `ContractId` sibling (4/6), but that is **not done today** and is **unavailable for 2/6**.
- **To pass:** emit a distinct original-contract key into the amendment payload (value = original order's Id, ≠ own Id) **or** stamp a Mule-readable Order field — populated for all 6 (the 4 Pending must re-sync).

### AC3 — "Workday can identify which existing contract should be amended" → FAIL
- Both populated payloads carry `customerContractType=Master_Contract` and **no** `Original_Customer_Contract_Reference` / alternate / amended key of any name. The `Workday_Contract_Type__c` picklist exposes **only** `Master_Contract` across all 4 sandboxes (Prod describe returns an empty value set) — there is **no Amendment/Alternate value** to designate an original.
- The Workday `Submit_Customer_Contract` API *does* define `Original_Customer_Contract_Reference` / `Alternate_Customer_Contract_Reference` / `Customer_Contract_Amendment_Reference_ID` (sc3143 ref) — the payload populates **none** of them.
- **To pass:** emit `Original_Customer_Contract_Reference` (value = original order's WCID) and/or add an Amendment/Alternate `Workday_Contract_Type__c` value, for all 6 amendments.

---

## What "complete" would require (checklist to hand back)

1. **SF field** on the amendment Order carrying the original WCID (AC1), populated for **all 6** amendments — including the 2 native/manual ones (#00095531, #00095676) that have **no** Quote lineage and **no** contract sibling, so they need a separate source (e.g. `Contract.Original_Contract__c` backfill or manual capture).
2. **MuleSoft mapping change** to read that field and emit `Original_Customer_Contract_Reference` into `Submit_Customer_Contract` (AC2/AC3). An SF field alone never reaches Workday.
3. **New `Workday_Contract_Type__c` value** (Alternate/Amendment) so the type conveys the amend relationship instead of the static `Master_Contract` (AC3).
4. **Re-sync** the 4 Pending amendment orders and re-read their payloads — a passing state shows an original-contract key whose value **≠** the amendment order's own Id.

---

## §4 — Blind spots (why the verdict isn't 100%, and how to close)

| Blind spot | Real? | Why it can't flip the verdict on current evidence | How to close definitively |
|---|---|---|---|
| MuleSoft DataWeave mapping repo not in this workspace | **Yes** | The 2 amendment orders that already synced still produced payloads with **no** original key and `Master_Contract` — so no correct payload exists yet even if a Mule change were deployed. | Ask Marc for the Mule branch/PR (Anypoint project, separate repo) and grep its DataWeave for `Original_Customer_Contract_Reference` / a read of `Quote.Original_Order_Id__c` / `Order.ContractId`. |
| 4/6 amendment payloads empty (Sync=Pending) | **Yes** | "No original reference" is *proven* for the 2 synced orders; for the 4 Pending it's absence-of-any-emitting-artifact (SF grep shows no injector). A stamp-at-sync design could in theory emit on next sync. | Re-sync one Pending amendment (re-publish `Order_Completed_WD__e`) and read the resulting payload — **this is a write**, needs explicit authorization (read-only rule). |
| FLS/permission-gated field or inactive picklist value | No | Verified via FLS-independent Tooling API: zero new Order fields in 60 days. | (Optional) query GlobalValueSet for inactive `Workday_Contract_Type__c` values. |
| Unpushed/PR branch or Gearset-delivered metadata | No | `git ls-remote` shows only `main`/`uat`; no feature branch; stash empty. But SF metadata may ship via Gearset (not git). | `gh pr list --search 3505`; confirm whether SF metadata deploys via this repo or Gearset. |
| FortraProd data not queried (schema-only) | No | Prod schema is **less** built-out than sandboxes (empty `Workday_Contract_Type__c` value set) — a feature can't be Prod-only yet absent from all 4 sandboxes + git. | Only with explicit authorization to query Prod data. |

**Confidence in verdict: HIGH.** The two real blind spots both point to the same close-out action: **have Marc show the MuleSoft change and re-sync one amendment order so the resulting payload can be read.** Absent that, the Salesforce-side ACs (AC1) are objectively unmet, and the integration-side ACs (AC2/AC3) show no emitted reference in any payload that exists today.
</content>
