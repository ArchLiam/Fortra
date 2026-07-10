# SC-3516 Peer Review Report: SC-3505 — Carry Original Workday Contract ID Through Amendment Process

**Reviewer:** Liam Jeong (SC-3516, peer review of SC-3505) · **Org:** FortraUAT (fortra--uat) · **Date:** 2026-07-01 · **All org queries read-only.**

**Ticket under review:** SC-3505 "RCA: Carry Original Workday Contract ID Through Amendment Process" — Assignee Marc Debrey, Reporter Dawn Krauss, Priority High, Status **To Do** (not yet built).

---

## 1. Executive Summary & Verdict

**Verdict: the ticket identifies a REAL, ground-truth-confirmed gap — but it is written as a one-line RCA and is NOT build-ready. It needs (a) one factual correction to its premise, (b) a concrete solution design, (c) three coverage/scope decisions, and (d) an explicit MuleSoft cross-team dependency called out. Recommendation below.**

The core problem is proven by the **actual Workday payload** of a real amendment order (00095512, synced Success): it contains **zero reference to the original contract**. Every identifier in the payload (`sfContractId`, `orderId`, `contractReferenceId`, `fortraSfdcExternalId`) is the amendment order's **own record Id**, and `customerContractType` is `"Master_Contract"` — the only value the picklist even offers. The single hint that it is an amendment is a free-text `"name": "Amendment Quote"`. So Workday receives an amendment as a brand-new master contract with no link to what it amends. **SC-3505's need is valid.**

Two facts reframe *how* to fix it:

1. **The Workday "contract ID" is not a Workday-returned value — it is the Salesforce Order Id.** Flow `Fortra_Order_Workday_Contract_ID` (Active) stamps `Order.Workday_Contract_ID__c = $Record.Id` on every order. Verified 200/200 sampled orders have `Workday_Contract_ID__c == Id` (0 mismatches). Consequence: **every order — new, renewal, or amendment — mints its own distinct Workday contract key.** That, not "a new SF Contract record," is why the original reference is lost.

2. **The original Workday contract ID is already derivable at amendment time.** The amendment Quote carries `Original_Order_Id__c` (→ the original Order, whose WCID = its own Id) and `Renewal_Contract__c` ("Source Contract", → the contract being amended). For the 4 of 6 amend orders created through the Fortra amendment flow, this chain resolves cleanly to the correct original WCID. **The data to carry forward exists; it simply never reaches the Order or the outbound payload.**

**Net:** approve the *intent*, send the *ticket* back for design. This is a small-surface Salesforce change (stamp a field) coupled to a mandatory MuleSoft mapping change and a Workday contract-type decision — it cannot be delivered by Salesforce alone.

**Gaps folded into this report: 7** (1 premise correction, 2 HIGH design/coverage, 3 MEDIUM, 1 open question).

---

## 2. What SC-3505 Requires (verbatim)

> As discussed in 6/29 Demo, we need to store original Workday contract reference on amendment transactions. The original Workday contract identifier needs to be carried forward when Salesforce creates amendment contracts. Because Salesforce creates a new contract record, downstream processing in Workday requires reference to the original contract that is being amended. Marc suggested stamping the original contract reference during automation.

**Acceptance Criteria (verbatim):**
1. Original Workday contract identifier is stored on the amendment transaction.
2. Reference is available to Permendor integration/processing.
3. Workday can identify which existing contract should be amended.

**Business Impact:** Required for Workday amendment processing.

---

## 3. How the Salesforce → Workday Contract Sync Actually Works (evidence-backed)

| Fact | Evidence | Confidence |
|---|---|---|
| **Integration middleware is MuleSoft, not "Permendor."** "Permendor" appears nowhere in the repo. Sync is one-way SF → MuleSoft → Workday. | Repo-wide grep: 0 hits for "permendor"; `FORTRA_KNOWLEDGE_BASE.md` documents SF → MuleSoft → Workday. | High |
| **Salesforce publishes only the Order Id.** Outbound trigger is platform event `Order_Completed_WD__e`, whose single field is `Order_Id__c`. MuleSoft consumes it, queries the Order, and builds the Workday JSON itself. | `sf sobject describe Order_Completed_WD__e` → one field `Order_Id__c`. `Order.Workday_Sync_Payload__c` stores the JSON MuleSoft assembles/sends. | High |
| **The Workday "contract ID" = the SF Order Id.** Flow `Fortra_Order_Workday_Contract_ID` (Active, RecordAfterSave, api 66) sets `Workday_Contract_ID__c = $Record.Id`, entry-gated on `Workday_Contract_ID__c` blank/null. | Flow XML (`inputAssignments` field `Workday_Contract_ID__c` ← `$Record.Id`). Live: 200/200 sampled orders `WCID == Id`, 0 mismatches; 29,149 orders carry a WCID. | High |
| **Every order is a distinct Workday contract keyed by its own Order Id.** Because WCID = Order.Id and each transaction is a new Order, new / renewal / amendment orders each present as separate Workday contracts. | Amend 00095512 WCID `801WC00000koIE3YAM` (own Id); its renewal sibling 00095510 WCID `801WC00000koHXqYAM` (own Id) — same SF Contract, two different Workday keys. | High |
| **Contract has NO Workday field at all.** No `Workday_Contract_ID__c`, no external-ID, no sync fields on Contract. Workday identity lives entirely on the Order. | `sf sobject describe Contract`: only Workday-adjacent custom fields are `Legacy_Id__c`, `ExternalContractReference` (std, empty on sampled amend contracts). | High |
| **`Workday_Contract_Type__c` offers only one value: `Master_Contract`.** There is no "Alternate"/"Amendment" contract-type value to express an amendment to Workday. | `sf sobject describe Order` picklist values = `['Master_Contract']`; all 29,174 orders = Master_Contract. | High |

---

## 4. Ground Truth — The Actual Amendment Payload (the smoking gun)

Amendment order **00095512** (`OriginalActionType=Amend`, `Workday_Sync_Status__c=Success`), full `Workday_Sync_Payload__c` (see `evidence/payload_amend_00095512.json`):

```json
{
  "sfContractId": "801WC00000koIE3YAM",         // ← the amendment ORDER's own Id
  "orderId": "801WC00000koIE3YAM",
  "fortraSfdcExternalId": "801WC00000koIE3YAM",
  "orderNumber": "00095512",
  "name": "Amendment Quote",                     // ← ONLY signal it is an amendment (free text)
  "contractReferenceId": "801WC00000koIE3YAM",   // ← again the amendment order's own Id
  "customerContractType": "Master_Contract",     // ← NOT an Alternate/Amendment type
  "currentContractAmount": 0,
  "contractLineData": [ { "lineNumber": 1, "quantity": 175, "extendedAmount": 0, ... } ]
}
```

**What is missing:** there is no `originalContractReferenceId`, no `originalCustomerContractReference`, no `alternateContract*` — nothing that points at the contract being amended (`801WC00000koHXqYAM`). The renewal sibling 00095510 (`evidence/payload_renew_00095510.json`) is structurally identical (`customerContractType=Master_Contract`, `contractReferenceId` = its own Id, zero original-reference keys). **Workday cannot distinguish "amend contract X" from "create new contract" — it just receives a new master contract.**

This is the exact failure SC-3505 describes, captured live. AC #1–#3 are all currently **unmet**.

---

## 5. What Workday Needs (target-side requirement)

Fortra's Workday endpoint is `Submit_Customer_Contract` (v46.1; reference under `Jira/Story/sc3143(epic | integration)/workday-api-reference/Submit_Customer_Contract.md`). The relevant field:

- **`Original_Customer_Contract_Reference`** `Customer_ContractObject` `[0..1]` — *"Original Customer Contract. The Customer Contract used as source for this Alternate Customer Contract."*

Associated Workday validations that constrain the design:
- *"Cannot create Alternate Contract if Original Contract is in Draft status."*
- *"Alternate Customer Contract Number must match Original Customer Contract Number if supplied."* ← implies the amendment may need to **reuse the original's contract number**, not present a new one. **Must be confirmed with the Workday/Mule team** (see G-6).

So the end state: the amendment submission must populate `Original_Customer_Contract_Reference` = the **original order's WCID** (`801WC00000koHXqYAM` for our example) and be typed as an Alternate/amendment contract, not `Master_Contract`.

---

## 6. The Linkage — Is the Original WCID Knowable at Amendment Time? (Yes, with a coverage gap)

The amendment automation (`Fortra_Create_Amendment_Quote` → `initiateAmendment(amendContractId=…)`) already records provenance on the amendment **Quote**:

- `Quote.Renewal_Contract__c` ("Source Contract") → the Contract being amended.
- `Quote.Original_Order_Id__c` → the original Order (whose `Workday_Contract_ID__c` = its own Id = the value Workday needs).

Resolution across all 6 `OriginalActionType=Amend` orders in FortraUAT:

| Amend Order | `Quote_Type__c` | `Renewal_Contract__c` (source) | `Original_Order_Id__c` | Resolved original WCID | Linkage |
|---|---|---|---|---|---|
| 00000656 | Amendment | 800WC00000OVQmpYAH | 801WC00000eLglEYAS | **801WC00000eLglEYAS** | ✅ |
| 00095512 | Amendment | 800WC00000SLdXhYAL | 801WC00000koHXqYAM | **801WC00000koHXqYAM** | ✅ |
| 00095635 | Amendment | 800WC00000Sw6WLYAZ | 801WC00000lqY7OYAU | **801WC00000lqY7OYAU** | ✅ |
| 00095642 | Amendment | 800WC00000Sy3SpYAJ | 801WC00000ltV8VYAU | **801WC00000ltV8VYAU** | ✅ |
| 00095531 | *(none)* | *(mismatched)* | null | — | ❌ |
| 00095676 | *(none)* | null | null | — | ❌ |

**4 of 6 resolve cleanly** (the Fortra-flow amendments). **2 of 6 do not** — they have `Quote_Type__c` null and no `Original_Order_Id__c`, i.e., amendments created *outside* the Fortra amendment flow (native/manual RLM amendment). **Any solution keyed solely on the Quote will silently miss these.** This is the single most important design risk (G-3).

---

## 7. Factual Correction to the Ticket Premise

**The ticket's premise — "Because Salesforce creates a new contract record" [for amendments] — is inaccurate for the native amendment path and should be corrected.**

Evidence: for the sampled `OriginalActionType=Amend` orders, the amendment Order's `ContractId` is the **same** contract carried by `Quote.Renewal_Contract__c` (the source contract), and that contract is shared with the prior order:

- 00095512 → contract 800WC00000SLdXhYAL holds **2** orders: `[Renew 00095510, Amend 00095512]` — the amendment **reused** the renewal's contract; no new Contract record was created.
- 00095635 / 00095642 / 00000656 → each contract holds `[Amend, <original>]` (2 orders).
- 00095531 / 00095676 → solo-contract (1 order) — the exceptions, and the two that also fail the Quote linkage.

RLM amendments amend the contract **in place** (new Order + new AssetStatePeriod on the *same* Contract). Renewals are the pattern that creates a *new* Contract (Gen1→Gen2 via `Original_Contract__c`). **The real loss is not a new SF Contract — it is that WCID = Order.Id mints a new Workday contract key for the amendment Order.** The corrected framing does not weaken the ticket; the gap is fully real. It just changes where the fix belongs (carry the original WCID onto the amendment Order/payload) and prevents chasing a non-existent "set AmendedContractId on a new contract" task.

> Caveat: the `Upsell` order Type (273 records) is a *separate* pattern — sampled 10/10 sit on solo contracts. Whether any "amendment" business is routed as `Upsell` (rather than `OriginalActionType=Amend`) is unconfirmed and worth checking before finalizing scope; it may widen the population the fix must cover.

---

## 8. Gaps / Risks — Ranked

| # | Sev | Title | Detail & Evidence | Recommendation |
|---|---|---|---|---|
| **G-1** | **HIGH** | Payload carries no original reference; contract type is Master-only | The live amendment payload (§4) has no original-contract key and `customerContractType=Master_Contract`; the picklist has no Alternate value. AC #3 cannot be met until both are added end-to-end. | Add an `Original_Workday_Contract_ID__c` to the outbound payload **and** a `Workday_Contract_Type__c` value for amendments (e.g. `Alternate_Contract`). Requires the MuleSoft mapping change (G-2). |
| **G-2** | **HIGH** | Salesforce cannot satisfy this alone — MuleSoft owns payload assembly | SF publishes only `Order_Id__c`; MuleSoft queries the Order and builds/maps the JSON, including `Original_Customer_Contract_Reference`. A stamped SF field is inert until Mule reads and maps it. | Scope MUST include a MuleSoft work item: read the new Order field, map to `Original_Customer_Contract_Reference`, set the Alternate contract type, and honor the "number must match" validation (§5). Coordinate with the integration owner; add as a linked ticket/dependency. |
| **G-3** | **MEDIUM** | Quote-only linkage misses native/manual amendments | 2 of 6 amend orders (§6) have no `Original_Order_Id__c`/`Quote_Type__c=Amendment`. A solution reading only the Quote leaves them with no original reference and they fail silently. | Prefer a **Contract-anchored** resolution (see §9 recommendation) so coverage does not depend on the amendment going through the Fortra flow. If Quote-based, add a fallback + an error/guard when the original cannot be resolved. |
| **G-4** | **MEDIUM** | "Original" is ambiguous for chained/renewed contracts | A contract can carry an original order **and** later a renewal and/or multiple amendments. Which order's WCID is "the original" Workday contract — the master, the current live one, or the immediately-prior transaction? Workday's "number must match original" hints at the master. Undefined in the ticket. | Define the selection rule explicitly (recommend: the WCID of the current master/primary order Workday holds for that contract). Confirm against Workday's Alternate-contract chaining model. |
| **G-5** | **MEDIUM** | Renewals share the identical structural gap; scope boundary unstated | The renewal payload (00095510) also sends `Master_Contract` with no prior reference (§4). If Workday must chain renewals to prior contracts too, SC-3505's Order-centric fix should be designed to cover renewals — or the ticket must explicitly scope them out. | State whether renewals are in/out of scope. The recommended design (§9) covers both for negligible extra cost. |
| **G-6** | **OPEN Q** | Does the amendment reuse the original's contract number, or get its own? | Workday validation: *"Alternate Customer Contract Number must match Original Customer Contract Number if supplied."* Today each order self-generates its number (WCID=Order.Id). Reusing the original number may be required — which changes whether the amendment keeps its own key at all. | Resolve with the Workday functional owner before build; it determines whether we *add a reference* (amendment keeps own key) vs *reuse the original key* (amendment is not a distinct Master). |
| **G-7** | **LOW** | AC #2 names "Permendor" — no such system in the estate | "Permendor" is not in the repo or integration docs; the integration is MuleSoft. Likely a transcription of a vendor/name from the 6/29 demo. | Correct AC #2 to name MuleSoft (and the specific Mule flow/API owner) so the dependency is unambiguous. |

---

## 9. Recommended Design (my recommendation)

**Anchor the original Workday contract ID on the Contract, then read it from the amendment Order — do not depend on the Quote.**

1. **New field `Contract.Workday_Contract_ID__c`** (Text, External ID). Stamp it when the **master/primary** order for that contract first syncs to Workday — value = that order's WCID (= its Order Id). One-time per contract; go-forward only (no backfill needed for the fix to work prospectively). This makes the Contract the single source of truth for "which Workday contract is this," independent of how any later change is created.
2. **New field `Order.Original_Workday_Contract_ID__c`** (Text). On amendment-order creation/activation, set it to `Order.ContractId → Contract.Workday_Contract_ID__c`. Because RLM amendments reuse the source contract (§7), `Order.ContractId` already points at the right contract — this covers both Fortra-flow **and** native/manual amendments (closes G-3). Keep `Quote.Original_Order_Id__c` as a secondary/validation source.
3. **New `Workday_Contract_Type__c` value** (e.g. `Alternate_Contract`) and set it on amendment orders so the type communicates "amendment," replacing reliance on the free-text `name` (closes part of G-1).
4. **MuleSoft mapping change (mandatory, G-2):** add `Original_Workday_Contract_ID__c` to the outbound payload; map it to `Original_Customer_Contract_Reference`; drive contract type from `Workday_Contract_Type__c`; honor the number-match validation per G-6's answer.
5. **Guard:** if an amendment order has no resolvable `Original_Workday_Contract_ID__c`, block/flag the Workday submission rather than send a headless `Master_Contract` (prevents a silent duplicate contract in Workday).

**Why Contract-anchored over the ticket's implied Quote-stamp:** it is deterministic, covers native amendments, survives records created outside the Fortra flow, and gives renewals the same mechanism for free (closes G-5). The alternative (stamp from `Quote.Original_Order_Id__c` only) is simpler but fails the 2/6 native-amendment cases and any future non-flow path.

**Interaction to watch:** `Fortra_Order_Workday_Contract_ID` is blank-guarded (`WCID EqualTo '' OR IsNull`), so it will *not* overwrite a pre-populated value — but it stamps the amendment order's **own** WCID regardless. The new original-reference must therefore live in a **separate** field (`Original_Workday_Contract_ID__c`), not by hijacking `Workday_Contract_ID__c`; otherwise the amendment loses its own transaction key. Confirm trigger ordering vs. the Mule payload build.

---

## 10. Peer-Review Disposition

**Disposition: SC-3505 — APPROVE INTENT, RETURN FOR DESIGN (not build-ready as written).**

The RCA correctly identifies a genuine, live-confirmed defect: amendments reach Workday with no original-contract reference and as `Master_Contract`, so Workday cannot amend the right contract. Before it goes to build, the ticket must:

1. **Correct the premise** — amendments reuse the source contract (native path); the loss is the per-order WCID (=Order.Id), not a new SF Contract record (§7).
2. **Adopt a concrete design** — recommend the Contract-anchored approach (§9); at minimum decide field placement (Contract vs Order vs Quote) and the "original" selection rule (G-4).
3. **Add the MuleSoft work item as a hard dependency** (G-2) — Salesforce stamping alone satisfies AC #1 but not AC #2/#3; the payload + `Original_Customer_Contract_Reference` mapping + Alternate contract type are Mule-side.
4. **Decide scope for native/manual amendments (G-3) and renewals (G-5),** and resolve the Workday number-match question (G-6) with the integration owner.
5. **Fix AC #2 wording** — "Permendor" → MuleSoft (G-7).

Once 1–5 are addressed, AC #1 is a small Salesforce change; AC #2 and AC #3 are satisfiable only with the coordinated MuleSoft mapping change.

---

## 11. Caveats & Limitations

1. **Thin live sample.** Only **6** `OriginalActionType=Amend` orders exist in FortraUAT; only **2** have synced to Workday (Success), **4** are Pending. Conclusions about the payload rest on the 2 synced examples (both structurally identical). The `Upsell` population (273) was not fully characterized (§7 caveat).
2. **Read-only, UAT only.** All findings are from `sf sobject describe` and `sf data query` against FortraUAT. No writes, no deploys. No claim about Production parity.
3. **MuleSoft is a black box here.** Payload assembly and the Workday call live in MuleSoft, outside this repo. The "what Mule does with the Order" statements are inferred from the stored `Workday_Sync_Payload__c` and the platform-event contract; the exact Mule mapping code was not inspected.
4. **Workday API doc is a captured reference** (v46.1) under `sc3143`, not a live Workday tenant describe. Field cardinality/validation quoted from that doc.
5. **No Jira MCP.** SC-3505 content is taken from the ticket screenshot provided; Marc's own analysis (if any beyond the description) was not available to diff against. This is an independent ground-truth reconstruction.
</content>
</invoke>
