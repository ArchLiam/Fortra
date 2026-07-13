# SC-3505 — Carry Original Workday Contract ID Through Amendment: Verified Root Cause + Scoped SF Design + Blockers

**Ticket:** SC-3505 (peer review SC-3516) · **Org:** FortraUAT (read-only, verified 2026-07-11) · **Author:** Liam Jeong
**Method:** live-org verification + 10-agent adversarial workflow (5 refutation attempts on the root-cause claims, 4 design-critic lenses, synthesis). Evidence: `Data/sc3516/EVIDENCE_BUNDLE_LIVE_2026-07-11.md`.

**Verdict up front:** Root cause is **CONFIRMED** and SF-diagnosable. My first-draft SF design was **directionally right but not safe to ship** — its primary resolver reintroduced the shared-key trap and self-references 3 of 8 live amendments. A corrected, narrower SF design exists below. The ticket is **correctly PARKED**: with MuleSoft unchanged, no SF field change alters a single byte reaching Workday, and the Workday amendment *model* itself is unconfirmed. **Only the source-control drift capture is safe to authorize now.**

---

## 1. Verified Root Cause

| # | Claim | Verdict | One-line evidence |
|---|---|---|---|
| 1 | Flow `Fortra_Order_Workday_Contract_ID` (V3 Active, API 66) stamps `Order.Workday_Contract_ID__c = $Record.Id` for every order, no amendment branch | **CONFIRMED** | Single `recordUpdates` `Set_ID` → `$Record.Id`; no `<decisions>`/`OriginalActionType` element anywhere |
| 2 | Outbound path publishes `Order_Completed_WD__e` carrying **only** `Order_Id__c`; the amend payload self-references the amend order's own Id for contract identity as `Master_Contract`, no original reference | **CONFIRMED** | Subflow has one input assignment `Order_Id__c=orderId`; `payload_amend_00095512.json` |
| 3 | `Order.Workday_Contract_ID__c` is live in the org but has no field metadata in force-app (drift) | **CONFIRMED** | `find force-app -name Workday_Contract_ID__c.field-meta.xml` = 0 hits; field name appears only in flow/CMDT XML |
| 4 | Every native SF lineage anchor is empty/self-referential on all 8 amendments; only `Quote.Original_Order_Id__c` / `Quote.Renewal_Contract__c` are usable | **CONFIRMED** | `OriginalOrderId`, `Source_Order_Id__c`, `PricingContractId`, `Contract.AmendedContractId/ParentContractId/Original_Contract__c` all NULL; `Contract.SourceOrderId` NULL-or-self |
| 5 | Workday `Submit_Customer_Contract` (v46.1) defines `Original_Customer_Contract_Reference` + an Alternate contract object type | **CONFIRMED (schema)** — but the model *choice* is NOT confirmed | `Submit_Customer_Contract.md` lines 287–288, 726/735/742 |

**Honest nuance corrections (do not change the root cause):**
- **Claim 1** — the stamp is a *guarded fill-only* blank-write (entry filter `Workday_Contract_ID__c = '' OR IsNull`), idempotent, not an unconditional re-stamp. Net effect identical: every amendment is born blank and mints its own Id.
- **Claim 2** — "own Id in *every* id field" overstates. Only the four **contract-identity** fields (`sfContractId`, `orderId`, `fortraSfdcExternalId`, `contractReferenceId`) equal the amend order's own Id; `sfAccountId`, `opportunityId`, `salespersonReference`, customer IDs, `contractLineReference` are distinct correct references. `contractReferenceId` carries the **Order** Id — not even the SF Contract record — which *strengthens* "no original reference." "MuleSoft builds the payload" is an inference from the captured artifact; SF source only proves it emits `Order_Id__c`.
- **Claim 4/5** — force-app *does* contain source-lineage fields, but on **Quote** only (`Quote.Renewal_Contract__c` = "Source Contract"; `Quote.Original_Order_Id__c`), and they are **not wired into the outbound event**. What is genuinely absent is any field carrying the original **Workday** contract ID and any original reference on Order/Contract.
- **Claim 5** — the same schema also supports an **in-place** amendment path (`Customer_Contract_Reference` [0..1] "for update only purposes", `Add_Only`, "Incremental Contract Amendment"). Own-key + separate-reference (Alternate) is a schema-*enabled* choice, **not** schema-*mandated*. The schema defines an *Alternate Customer Contract* object type, not a picklist value literally named "Alternate."

**Net root cause (fully confirmed):** SF emits only the Order Id; the amend payload self-references the amend order for contract identity as `Master_Contract` with no original-contract link — so Workday cannot tell "amend contract X" from "new contract."

---

## 2. Scoped SF-Side Design (corrected — the draft's shared-key resolver is dropped)

### 2.1 Fields
- **Keep the own-Id key mechanism untouched** (`Order.Workday_Contract_ID__c = $Record.Id`) — preserves the 1:1 Order→own-WCID mapping.
- **ONE new field: `Order.Original_Workday_Contract_ID__c`** (Text, nullable) — on an amendment, the WCID of the original order being amended.
- **DROP `Contract.Workday_Contract_ID__c`** (see §4 — shared per-contract slot, self-references the amend on live data).
- **DO NOT add an `Alternate_Contract` picklist value yet** — inert until Workday tenant + Mule support it, and blindly emitting it risks breaking the working `Master_Contract` path.

### 2.2 Resolution rule (per-order, deterministic, no shared field, no sync race)
```
Original_Workday_Contract_ID__c =
  1. Quote.Original_Order_Id__c                         → that Order's own Id IS its WCID   (PRIMARY)
  2. else Quote.Renewal_Contract__c → most-recent non-amend Order on it → that Order.Id     (FALLBACK)
  3. else leave BLANK + emit telemetry                                                       (unresolvable)
```
This is the per-order anchor the evidence already surfaced: it points at the **immediately-prior version** (the semantic Workday's field wants — "source for this Alternate", not genesis), does not rot across amend-of-an-amend, and has no first-syncer race.

### 2.3 Resolution matrix (8 live amendments)

| Amend | Rule | Resolves to | Honest end-to-end status |
|---|---|---|---|
| 00000656 | Original_Order_Id__c | 00000655 | SF-resolved; **original Sync=Pending** → would dangle in Workday |
| 00095512 | Original_Order_Id__c | 00095510 | SF-resolved; **original Success** → clean |
| 00095531 | Renewal_Contract__c→order | 00095530 | SF-resolved; **original Sync=Pending** → dangles (source SOPMv never minted a WD key) |
| 00095635 | none | — | **ORPHAN** — blank + telemetry |
| 00095642 | Original_Order_Id__c | 00095639 | SF-resolved; **original Success** → clean |
| 00095676 | none | — | **ORPHAN** — blank + telemetry |
| 00095693 | Original_Order_Id__c | 00095692 | SF-resolved; **original Sync=Pending** → dangles |
| 00095724 | Original_Order_Id__c | 00095723 | SF-resolved |

**Honest outcome: 6/8 resolve to a predecessor order in SF; 2 are true orphans. But only 2 (00095512, 00095642) point to an original that is actually Success in Workday today**; 3 more resolve to a Pending/never-synced original that Workday would *reject* as a Draft-status reference. "6/8 resolved" must never be reported as "6/8 will amend correctly in Workday" — that conflation is this ticket's documented failure mode.

### 2.4 Mechanism / idempotency / timing (compliant)
- **Home:** a dedicated **`WorkdayContractLineageService` (`with sharing`)** with a bulk signature `Map<Id,String> resolveOriginalWcid(Set<Id> orderIds)` — two Set-based queries only (one `Quote` keyed by `Order.QuoteId`, one `Order` for the fallback), Map-cached, no per-order SOQL (apex §4.1 service layer, §5 bulkification). Invoked from the **existing `OrderValidationTriggerHandler`** (§2 one-trigger-per-object — Order already has `OrderValidationTrigger`). Handler only collects Ids and mutates `Trigger.new`.
- **Timing (load-bearing):** stamp in **before-update at the `Status → 'Order Complete'` transition**, mutating `Trigger.new` (§2.6 self-field, no self-DML). Must **not** be gated on `Workday_Sync_Status__c='Success'` — that's async external middleware an after-save trigger can't observe, and the value must be committed on the Order **before** `Order_Completed_WD__e` fires and Mule re-queries. Because the field is on Order itself, the **existing before-only trigger hosts this without adding after contexts** — a direct benefit of dropping the Contract field.
- **Idempotency (§8):** fill-only, but treat **blank as still-fillable** so the documented Workday re-submit can self-heal 00095531 once its source syncs. Never overwrite a non-blank value. Add a §2.4 recursion guard.

### 2.5 Telemetry (§9) — verified facade
Define `public class OrderContractLineageException extends AppException {}`. In the orphan branch + top-level catch, call **`ExceptionLogger.log(WorkdayContractLineageService.class.getName(), orderId, ExceptionLogger.Severity.WARNING, ex)`** — **verified present** at `ExceptionLogger.cls:39/50`, publishes `Fortra_Exception__e` (class confirmed live in org). **Do NOT use `PricingHookLogger`** (hook-only, §9.4) and **do NOT** hand-roll a `safePublish(Pricing_Exception__e)` fallback — the target-state facade is deployed. Severity **WARNING** (orphan = business outcome, not a system fault). Invoke once at the top-level catch, never per order.

### 2.6 Source-control capture (the one genuinely safe item)
Retrieve into force-app **both** drifted Order header fields (not just the one in the ticket):
- `objects/Order/fields/Workday_Contract_ID__c.field-meta.xml`
- `objects/Order/fields/Workday_Contract_Type__c.field-meta.xml` (also referenced only inside flow XML → also drift)
Verify `Order.Workday_Sync_Status__c` and `Order.OriginalActionType` are in force-app before compiling the Service (it reads them), else it tests against phantom fields.

### 2.7 Compliance obligations the first draft under-specified
- **§4.1 (MUST):** logic in a `*Service`, not the handler.
- **§6.1 (MUST):** new Service **and** the touched handler declare explicit `with sharing` — the host `OrderValidationTriggerHandler` is currently `public class` with **no sharing** while doing SOQL/DML (verified); fix as part of this change.
- **§2.2:** the trigger uses `if/else`, not `switch on Trigger.operationType` (verified `before insert, before update` only) — converting is hygiene, not forced here since no after context is added.
- **§11:** dedicated `WorkdayContractLineageServiceTest`, ≥20-record bulk, all 3 branches + orphan telemetry asserted, modern `Assert.*`, `runAs`. (§11.11 multi-currency N/A.)
- ApexDoc header `@author Liam Jeong <liam.jeong@coastalcloud.us>`, no ticket IDs/dates in headers.

### 2.8 Flow hygiene (dependency, optional)
`Fortra_Order_Workday_Contract_ID` is API 66 (flow §1.2 wants 67) with stray Draft V1 + Obsolete V2 (§1.6). Optional cleanup — **do NOT add an amendment branch** (would prejudge the unconfirmed Workday model; multi-hop lineage belongs in the Service).

---

## 3. BLOCKED on MuleSoft / Workday — why the ticket is correctly PARKED

The three live payloads (amend 00095512, amend 00095642, renew 00095510) prove the outbound JSON is **closed and constant-shaped**: no original/prior/alternate slot of any name, `customerContractType` hardcoded `Master_Contract`. **Any SF field change with Mule unchanged produces a byte-identical payload — zero value, AC1–AC3 unmet.** SF-first does not deliver value before Mule confirms.

1. **Workday amendment MODEL decision (Workday functional owner — "Ashok" per Round 2) — the fork that gates everything.** In-place Contract Amendment (target existing contract via `Customer_Contract_Reference`, reuse the key) **vs** Alternate Contract (own key + `Original_Customer_Contract_Reference`). The live 5/8 contract-**reuse** pattern is at least as consistent with in-place. If in-place is correct, the SF field semantics differ. **UNRESOLVED — do not bake either model into durable fields until answered in writing.**
2. **Workday tenant config (Workday functional).** Existence + exact identifier of an Alternate/Amendment Customer Contract Type in "Maintain Customer Contract Types", plus the "Alternate number must match Original number if supplied" rule. `Alternate_Contract` is an SF-invented guess; live picklist has only `Master_Contract`.
3. **MuleSoft DataWeave (Permender).** Mule must (a) SOQL the new Order field, (b) emit `Original_Customer_Contract_Reference` (or target `Customer_Contract_Reference` under in-place), and (c) drive `customerContractType` off SF instead of the constant. The DataWeave is **not in this repo** and cannot be reviewed from SF; the exact field API name / string-vs-reference / cardinality Mule needs is unspecifiable until Permender supplies the current code.
4. **Sync sequencing / referential integrity (Mule / process).** Workday rejects an Alternate whose Original is Draft/absent. **3 of 8 live originals are Pending/never-synced** — the referenced master must sync to Workday **first**. Not SF-fixable; it also blanks the SF-side resolution for 00095531 at stamp time.
5. **Two true orphans (00095635, 00095676).** No SF lineage to any predecessor. No integration model resolves them; blank + telemetry pending upstream capture or a Workday-side match.

**Because the model fork (item 1) is unresolved and every value-delivering path routes through Mule, SC-3505 is correctly PARKED for the outbound stamp.** Ashok (model + tenant) and Permender (DataWeave contract) must confirm **before** SF field design, not after.

---

## 4. Explicitly Rejected (tied to live evidence)
- **Shared contract key (`Contract.Workday_Contract_ID__c` as resolver) — REJECTED.** A single per-contract slot can't encode per-Order lineage: 5/8 amendments **reuse** the master Contract. The "first order to SYNC owns the key, fill-only" rule inverts on live data — originals are **Pending** while amends 00095512/00095642 are **Success**, so the *amend* becomes first-syncer and the field self-references its own WCID. Walked row-by-row it self-references **3 of 8** (00095531, 00095635, 00095676) — a plausible-looking wrong value **worse than blank**. Same family of defect as `Fortra_Contract_Populate_From_Order` clobbering `Contract.SourceOrderId`. **Do not build.**
- **Walking `Contract.SourceOrderId` / `Order.OriginalOrderId` / `PricingContractId` / `AmendedContractId` — REJECTED.** All NULL or self-referential on 100% of the 8 live amendments.
- **Extending the flow with an amendment branch — REJECTED.** Multi-hop lineage + telemetry is cleaner and testable in Apex; a flow branch also hard-codes the unconfirmed Workday model.

---

## 5. Open Questions
**To Permender (MuleSoft):** (1) which Order/Contract fields does the DataWeave SOQL to build `Submit_Customer_Contract`? (2) is `customerContractType` field-sourced or a literal? (3) for amendments, Submit a new **Alternate** or **update** the existing contract via `Customer_Contract_Reference`/`Add_Only`? (4) what field API name/type/cardinality should the new SF field expose, and can you share the DataWeave PR?
**To Ashok (Workday functional):** (5) confirm in-place vs Alternate model; (6) tenant Contract-Type catalog + exact Alternate identifier; (7) resolution of "Alternate number must match Original number if supplied."
**To the business (orphans 00095635, 00095676):** (8) how were they created (manual/native amend with no source quote)? backfill lineage, Workday-side match, or accept blank + telemetry? (9) should amend-quote creation be hardened to **guarantee** `Quote.Original_Order_Id__c` going forward (the one genuinely SF-fixable, model-agnostic root cause) so future amendments never orphan?

---

## 6. Recommended Immediate Step vs. What Must Wait
**Safe to authorize NOW (zero runtime behavior, model-agnostic):** source-control **drift capture only** — retrieve `Order.Workday_Contract_ID__c` **and** `Order.Workday_Contract_Type__c` field metadata into force-app and commit. Pure hygiene; unblocks any future work regardless of model. (Optional same tier: flow-version hygiene — bump API 66→67, retire Draft V1/Obsolete V2 — **without** an amendment branch.)

**Genuinely SF-fixable, high-value, own thread (not the outbound stamp):** upstream **lineage capture** — guarantee `Quote.Original_Order_Id__c` is reliably populated at amend-quote creation so no future amendment orphans. Model-agnostic; benefits whichever model wins.

**MUST WAIT for the written integration decision (Ashok model+tenant, Permender DataWeave contract):** the new `Order.Original_Workday_Contract_ID__c` field, the `WorkdayContractLineageService` + handler wiring, the before-update stamp, the telemetry, and any `Workday_Contract_Type__c` value. Building these before the model fork is resolved risks baking the wrong model into durable data and shipping inert fields that change zero bytes reaching Workday — the exact "looks done, fails re-test" pattern this ticket has repeatedly hit.

**Bottom line:** Root cause CONFIRMED; corrected SF design is sound (per-order `Quote.Original_Order_Id__c` anchor, single Order field, before-update stamp, `ExceptionLogger` telemetry, ≥20-record tests). The outbound half is legitimately blocked. Authorize only the drift capture now; open the questions to Permender + Ashok; do not report the lineage stamp as "done" — with Mule unchanged it delivers no payload change, and even built, only 2 of 8 live amendments point to a Workday-existing original today.
