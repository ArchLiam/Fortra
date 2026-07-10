# SC-3516 — Peer Review of SC-3505 (Carry Original Workday Contract ID Through Amendment Process)

**Reviewer:** Liam Jeong · **Reviewing:** SC-3505 (RCA — Marc Debrey / Dawn Krauss, Priority High, Status To Do) · **Org:** FortraUAT · **Date:** 2026-07-01 · **All org access read-only.**

## What SC-3505 asks
Store the **original Workday contract identifier** on amendment transactions so the SF→MuleSoft→Workday integration can tell Workday **which existing contract to amend** (rather than creating a new one). AC: (1) original WD contract id stored on the amendment transaction; (2) reference available to the integration; (3) Workday can identify the contract to amend.

## Verdict (one line)
**APPROVE INTENT, RETURN FOR DESIGN.** The gap is real and ground-truth-confirmed — the live amendment payload sent to Workday carries **no** original-contract reference and is typed `Master_Contract` — but the ticket is a one-line RCA that needs a concrete design, a premise correction, and an explicit MuleSoft dependency before build.

## The gap, proven (see `evidence/payload_amend_00095512.json`)
The Workday payload for real amendment order **00095512** (synced Success): every id (`sfContractId`, `orderId`, `contractReferenceId`, `fortraSfdcExternalId`) is the amendment order's **own record Id**; `customerContractType` = `"Master_Contract"` (the only picklist value); the sole amendment signal is free-text `"name": "Amendment Quote"`. Nothing points at the contract being amended. AC #1–#3 are all currently unmet.

## Two facts that reframe the fix
- **The "Workday contract ID" IS the Salesforce Order Id.** Flow `Fortra_Order_Workday_Contract_ID` (Active) stamps `Order.Workday_Contract_ID__c = $Record.Id`; 200/200 sampled orders have `WCID == Id`. So **every** order (new/renewal/amendment) mints its own Workday contract key — that is why the original link is lost.
- **The original WCID is already derivable at amendment time** via `Quote.Original_Order_Id__c` and `Quote.Renewal_Contract__c` ("Source Contract"). It resolves for **4 of 6** amend orders (the Fortra-flow ones); **2 of 6** native/manual amendments have no link → a Quote-only fix misses them.

## Premise correction the ticket needs
"Salesforce creates a new contract record [for amendments]" is **inaccurate**. RLM amendments **reuse** the source contract in place (amend order 00095512 shares contract `800WC00000SLdXhYAL` with renewal order 00095510). The loss is the per-order WCID, **not** a new SF Contract. (Renewals are the pattern that creates a new Contract.)

## Recommended design (details in report §9)
Anchor the Workday contract id on the **Contract** (`Contract.Workday_Contract_ID__c`, stamped when the master order syncs), then stamp `Order.Original_Workday_Contract_ID__c = Order.ContractId→Contract.Workday_Contract_ID__c` on amendment orders. Add an `Alternate_Contract` value to `Workday_Contract_Type__c`. **Mandatory MuleSoft change:** map the new field to Workday `Original_Customer_Contract_Reference` and set the Alternate type. Guard/flag any amendment whose original cannot be resolved.

## Update — 2026-07-02: Marc claimed "implementation complete"
Re-verified all three ACs against the current live org (5 orgs, read-only, 12-agent adversarial workflow). **All three ACs FAIL (high confidence)** — no new field/picklist/flow/Apex/git artifact anywhere, and the current amendment payloads still carry only the order's own Id + `Master_Contract`. See **`AC_VERIFICATION_SC3505.md`** and **`JIRA_COMMENT_SC3516_AC_CHECK.md`**. Two honest blind spots (MuleSoft repo not in workspace; 4/6 payloads Pending) — close by asking Marc for the Mule branch/PR + a re-synced amendment whose payload key ≠ own Id.

## Files
| File | Purpose |
|---|---|
| `AC_VERIFICATION_SC3505.md` | **Post-"complete" AC check** — per-AC FAIL verdict, evidence, blind spots, what would make each pass. |
| `JIRA_COMMENT_SC3516_AC_CHECK.md` | Paste-ready comment reporting the AC verification result. |
| `PEER_REVIEW_REPORT.md` | Full report: how the sync works, the smoking-gun payload, Workday API requirement, linkage analysis, ranked gaps (G-1…G-7), recommended design, disposition, caveats. |
| `VALIDATION_RUNBOOK.md` | Read-only SOQL to reproduce every claim + a proposed write-path test plan (needs explicit UAT authorization before running any DML/deploy). |
| `JIRA_COMMENT_SC3516.md` | Condensed comment to paste on SC-3505/SC-3516. |
| `evidence/payload_amend_00095512.json` | Live Workday payload of a synced amendment order — the proof. |
| `evidence/payload_renew_00095510.json` | Live payload of the renewal sibling (same structural gap). |
| `evidence/FINDINGS.md` | Structured fact table + all record ids used. |

## Confirmed gaps (post-verification)
- **HIGH G-1:** payload has no original-contract key; contract type Master-only (no Alternate value).
- **HIGH G-2:** SF alone cannot satisfy AC #2/#3 — MuleSoft owns payload assembly + the `Original_Customer_Contract_Reference` mapping.
- **MEDIUM G-3:** Quote-only linkage misses native/manual amendments (2/6). Prefer Contract-anchored.
- **MEDIUM G-4:** "original" is ambiguous for renewed/chained contracts — define the selection rule.
- **MEDIUM G-5:** renewals share the identical gap — state scope.
- **OPEN G-6:** Workday requires the Alternate number to match the original — reuse key vs add reference? Confirm with integration owner.
- **LOW G-7:** "Permendor" ≠ any system in the estate; the integration is MuleSoft.
</content>
