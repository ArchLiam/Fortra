# SC-3516 Peer Review — Round 2: SC-3505 (rewritten "durable Workday Contract ID" design)

**Reviewer:** Liam Jeong · **Org:** FortraUAT (read-only) · **Date:** 2026-07-07 · Reviewing the rewritten ticket (User Story + Solution Design + ACs).

## Verdict

**RETURN FOR DESIGN — do not build as written.** The rewrite is a big improvement: it correctly identifies the root-cause flow, the own-Id stamping, the lost lineage, and correctly scopes out the inbound Asset field. But two **blockers** make the current Solution Design unbuildable as specified, and both are provable on live data:

1. **The design contradicts the Order↔Contract mapping you got from Ashok** (and Workday's own amend model). It needs an architecture decision before any build.
2. **The lineage data the design walks does not resolve for a single amendment or renewal today — it fails 100% of current lifecycle records**, including the flagship AC case. The ticket frames this as a "verify go-forward" caveat; it is actually a total failure with no populating mechanism in sight.

---

## BLOCKER 1 — "Shared durable key" contradicts Order↔Contract 1:1 (and Workday's Original-Contract-Reference model)

You learned from Ashok: **Order (SF) ↔ Customer Contract (Workday), Order Item (SF) ↔ Contract Line Item (Workday)** — a 1:1 mapping. Each SF Order becomes its own Workday contract.

The Solution Design does the opposite: it makes the **initial sale, every amendment, and every renewal share one identical `Workday_Contract_ID__c`.** Under a 1:1 Order↔Contract mapping, that means 3+ distinct SF Orders all present to Workday as **the same contract key** — a collision, not a lineage.

This also conflicts with Workday's native amendment model. `Submit_Customer_Contract` (v46.1, sc3143 ref) exposes **`Original_Customer_Contract_Reference`** ("The Customer Contract used as source for this **Alternate** Customer Contract") and an Alternate contract type. Workday's design is **distinct keys + a reference pointer** (each amendment is its own contract that *points at* the original), i.e. exactly what the **original ACs** say: *"store original Workday contract **reference** on amendment transactions."*

The rewrite silently switched from **"carry a reference to the original"** (Approach A — original ACs, Ashok's mapping, Workday's field) to **"make the key itself durable/shared"** (Approach B — new Solution Design). These are mutually exclusive architectures.

**Must resolve with Ashok before build:** does Workday want
- **(A)** each order = its own Workday contract, with amendments/renewals carrying a **separate** `Original_Customer_Contract_Reference` to the original (add a *new field*, keep own key), or
- **(B)** the whole lifecycle collapsing to **one** shared contract key (the current design)?

Every piece of external evidence points to **(A)**. If (A) is correct, the entire Solution Design (rework the key to inherit) is the wrong approach — you'd instead add a *second* field for the original reference and keep own-Id as the key.

---

## BLOCKER 2 — The lineage walk resolves to own-key or NULL for 100% of current lifecycle records

The design resolves the key via `Order.ContractId → Contract.SourceOrderId → SourceOrder.Workday_Contract_ID__c` (amend) and a contract-to-contract walk (renew). **Both inputs are unusable on live data.**

**Flagship AC case (contract 800WC00000SLdXh / 00069303):**
- Holds exactly two orders: Renew **00095510** (key = own `…koHXq`) and Amend **00095512** (key = own `…koIE3`). **There is no initial-sale order on this contract to inherit from.**
- `Contract.SourceOrderId` = **blank**; `Original_Contract__c` = **blank**; `ParentContractId` = **blank**; `AmendedContractId` = **blank**.
- Under the design, both orders walk to a blank `SourceOrderId` → resolve to NULL → "no predecessor" → each mints its **own** Id → **they stay different.** **AC #1 fails on its own flagship example.**

**All amendment orders — `Contract.SourceOrderId` never points to an earlier original:**
| Amend order | `Contract.SourceOrderId` | Resolves to |
|---|---|---|
| 00095512, 00095635, 00095531, 00000656 | **blank** | NULL → own Id |
| 00095693, 00095676, 00095642 | **= the amendment order itself** | own key |

7/7 resolve to own-key or NULL — the defect persists in **every** case.

**All renewal orders:** `Original_Contract__c` / `ParentContractId` are **blank on every contract** (0 of 29,455 org-wide), so the contract-to-contract walk has nothing to climb; it treats the current contract as the root and reads a self/blank `SourceOrderId`. 12/12 fail.

**Root cause of the SourceOrderId problem (semantic, not a data-freshness issue):** `Contract.SourceOrderId` is *not* "the originating order." It is written by flow **`Fortra_Contract_Populate_From_Order`** as `Contract.SourceOrderId = $Record.Id` on **`ISCHANGED(ContractId)`, with no guard**. So the **last** order to attach to a contract overwrites it — for an amendment/renewal that reuses/creates the contract, that's the amendment/renewal **itself**. The field can therefore never reliably point at the true original once any downstream order touches the contract. The design's premise ("`Contract.SourceOrderId` = the contract's originating/initial order") is false in practice.

**Why the 88% stat is misleading:** `SourceOrderId` is 25,930/29,455 populated, but that population is dominated by **migrated legacy contracts** (each a solo order). For the 19 real lifecycle orders it is blank or self-referential — i.e. 0% useful where the fix actually needs it.

**Net:** there is no working resolution path today, and nothing populates the contract-to-contract links or corrects `SourceOrderId`, so there is no evidence go-forward records will differ. The design's "Assumptions/Caveat" **understates a total, structural failure as a go-forward verification task.**

---

## HIGH — Backfill vs. blank-guard is a logical contradiction (AC #9 unsatisfiable)

Requirement #3 + the backfill both say "respect the write-once blank-guard." But all 19 lifecycle orders **already** have `Workday_Contract_ID__c` = own Id (non-blank). A backfill that respects the blank-guard writes **nothing** → the 19 keep their wrong keys → **AC #9 ("all 19 end with keys consistent with their original contract's key") is impossible.** To fix existing wrong keys you must **overwrite**, which violates the blank-guard. The ticket must pick one: (a) a one-time *overwrite* backfill (explicitly exempt from the guard), or (b) accept the 19 stay wrong and drop AC #9.

## HIGH — Write-once + RecordAfterSave is a timing race against lineage availability

The flow is `RecordAfterSave`, blank-guarded, fires on the **first** save where the key is blank. On a new amendment, `ContractId` (and any lineage) is typically populated **on activation, after** the initial insert. So the flow mints own Id on the first save — **before** `ContractId`/lineage exist — and the blank-guard then locks it. Requirement #3 (retain blank-guard) directly tensions with the need to defer resolution until lineage is available. The design must add an explicit entry-condition/timing change (e.g. only fire once `ContractId` is set **and** a non-self predecessor resolves), or it will lock in own-Id exactly as today.

## MEDIUM — The renewal model doesn't match the data

The design assumes renewals create a **successor** contract and walks contract-to-contract to a root. But the flagship renewal **00095510 shares its contract with the amendment 00095512** — no successor contract, no Gen1→Gen2 link. So this renewal takes a walk that has nothing to traverse. Either there are multiple renewal patterns the design doesn't cover, or the "successor contract" model is wrong. Define the actual renewal topologies (same-contract vs. successor) before building the walk.

## MEDIUM — `Contract.SourceOrderId` self-reference guard is necessary, not optional

Risk Mitigation mentions detecting self-referential `SourceOrderId`. Given the data shows it is self-referential or blank on **100%** of lifecycle contracts, this isn't an edge guard — it's the common path. Any design that reads `SourceOrderId` must treat self/blank as "no original found" and fall back deterministically; otherwise it silently mints fresh keys (today's bug).

## LOW — Residual doc inconsistencies

- The **Description** still says *"Because Salesforce creates a new contract record"* — false for native amendments (they reuse the contract in place); the Background/Root Cause sections already contradict it. Delete or correct it.
- AC #2 still names **"Permendor"** — the integration is **MuleSoft**, and the target is Workday `Submit_Customer_Contract`. Ashok/Permender own it.
- Order/renew counts have drifted since the write-up (now **7** Amend, **12** Renew visible) — refresh the "19 lifecycle orders" figures before quoting them in ACs.

---

## What's genuinely good (keep)

- Correct root-cause identification (`Fortra_Order_Workday_Contract_ID`, own-Id, blank-guarded, trigger order 1100).
- Correct live proof of the defect (00095512 vs 00095510 → two keys, one SF contract).
- Correctly scoping **out** the inbound `Asset.Workday_Contract_Line_Reference_ID__c` path (empty at source; never fires) — that matches the ground truth exactly.
- Strong testing checklist, blast-radius awareness (don't disturb ~29k migrated legacy orders), and idempotency thinking.
- Naming the lineage-population dependency as a risk (it just needs to be promoted from "caveat" to "blocker").

---

## Recommended path

1. **Settle the architecture with Ashok first (Blocker 1):** confirm A (own key + separate `Original_Customer_Contract_Reference`) vs B (shared key). External evidence says **A**. If A, rewrite the Solution Design around a **new original-reference field** + a MuleSoft mapping to `Original_Customer_Contract_Reference`, keeping own-Id as the key.
2. **Fix the lineage source, or don't depend on it (Blocker 2):** `Contract.SourceOrderId` cannot be the anchor while `Fortra_Contract_Populate_From_Order` clobbers it with the latest order. Either (a) add a write-once guard so `SourceOrderId` records the *first* order only, and backfill it, or (b) resolve the original via a field that actually holds it (`Quote.Original_Order_Id__c` where present, or the standard `OriginalOrderId`/`AmendedContractId` if RLM is configured to populate them). Whatever the anchor, **prove it resolves to a non-self earlier order on a freshly created amendment/renewal before committing to the design.**
3. **Resolve the backfill/blank-guard contradiction** (overwrite-once vs. leave-19-wrong).
4. **Add an explicit timing/entry-condition requirement** so resolution happens after `ContractId` + lineage are available, not on first insert.
5. **Make ACs falsifiable on data that will actually exist** — today AC #1 fails against its own example.
