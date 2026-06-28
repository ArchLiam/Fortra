# SC-3447 — Salesforce Governor Limits & Async Best Practices (Official-Docs Research)

**Date:** 2026-06-27
**Author:** read-only research subagent (web research only; no org mutation)
**Ticket:** SC-3447 (Blocker) — Quote→Order conversion throws `System.LimitException: Apex CPU time limit exceeded` (root error wrapped as `FLOW_INTERVIEW_LIMIT_EXCEEDED`), full transaction rollback, on quotes with a high-quantity `Solution_Group__c='Power'` line. Client sells up to 750,000 qty.

**Method note:** `developer.salesforce.com/docs/*` and `help.salesforce.com/*` are JavaScript-rendered and could not be scraped directly (curl/WebFetch/jina all returned cookie/JS shells). I obtained the **authoritative limit numbers from the official static PDF** (`salesforce_app_limits_cheatsheet.pdf`, "Last updated: May 8, 2026", saved alongside this file as `_limits_cheatsheet.pdf` / `_limits_cheatsheet.txt`) and the **architect.salesforce.com decision guides** (which ARE server-rendered at the `/docs/architect/decision-guides/guide/...` paths). Secondary confirmations from Trailhead and Salesforce Ben. Every quote below is from the saved source files or a cited URL.

---

## 1. Apex CPU time limit — what counts, and why FLOW_INTERVIEW_LIMIT_EXCEEDED maps to it

### The hard numbers (official cheatsheet, Per-Transaction Apex Limits table)
> "Maximum CPU time on the Salesforce servers — Synchronous Limit **10,000 milliseconds** — Asynchronous Limit **60,000 milliseconds**."
— *Salesforce Developer Limits and Allocations Quick Reference*, Apex Governor Limits table (`_limits_cheatsheet.txt` line 91-92).
URL: https://developer.salesforce.com/docs/atlas.en-us.salesforce_app_limits_cheatsheet.meta/salesforce_app_limits_cheatsheet/salesforce_app_limits_platform_apexgov.htm

Also relevant from the same table:
> "Maximum execution time for each Apex transaction — 10 minutes / 10 minutes." (line 94)

So async raises **CPU** from 10s → 60s, but the **wall-clock transaction cap stays 10 minutes** either way. CPU (not wall-clock) is what is throwing here.

### What counts toward CPU time (footnote 5 of the cheatsheet — the definitive statement)
> "CPU time is calculated for **all executions on the Salesforce application servers occurring in one Apex transaction**. CPU time is calculated for the executing Apex code, **and for any processes that are called from this code, such as package code and workflows**. CPU time is **private for a transaction and is isolated from other transactions**. Application server CPU time **spent in DML operations is counted** towards the Apex CPU limit. Operations that don't consume application server CPU time aren't counted toward CPU time. For example, **the portion of execution time spent in the database for DML, SOQL, and SOSL isn't counted, nor is waiting time for Apex callouts.**"
— `_limits_cheatsheet.txt` lines 176-183.

**Key takeaways for SC-3447:**
- "Any processes that are called from this code, such as package code and **workflows**" = **Flows and Flow-invoked Apex actions accrue CPU in the SAME 10,000 ms bucket** as the calling transaction. There is one shared CPU budget for the whole synchronous request, regardless of how many flows/actions/triggers fire.
- **SOQL/DML execution time in the database does NOT count** — only the application-server CPU does. This is exactly why the dead-transaction snapshot showed SOQL 19/100 and DML 480/10,000 (both far under limit) while CPU was the wall that fell. **The volume of work, not the DB queries, is the cost.** Per-record Apex/flow logic (clone construction, field derivation, decision/loop evaluation, action initialization) is pure app-server CPU and accumulates linearly with record count.

### Confirmation that flows share the CPU budget and that overrun rolls back EVERYTHING
> "The error also involves declarative tools. It is calculated for the executing Apex code and any processes that are called from this code, such as package code, and **Flows**."
> "It rolls back all database transactions. For example, you might have done multiple DMLs successfully in the transaction. **These DMLs are reverted when this limit hits.**"
> "It is non-negotiable. This means we cannot increase the 10-second threshold by tweaking settings."
> "One of the common reasons we hit the CPU limit is that the **trigger logic enters unexpectedly multiple times**."
— Salesforce Ben, *What Is 'Apex CPU Time Limit Exceeded' & How Do You Solve It?*
URL: https://www.salesforceben.com/what-is-apex-cpu-time-limit-exceeded-how-do-you-solve-it/

### The per-record cost of an Apex action in a flow (the canonical example)
> "Calling an Apex Action has significant CPU overhead. If an Account has 150 contacts, the Flow invokes the Apex Action 150 times. The cumulative CPU cost of initializing the Apex and performing the check repeatedly causes a timeout, especially during a mass update."
— Salesforce Help, *Code more efficiently to avoid 'Apex CPU time limit exceeded'* (id=000387833), summarized via search (page is JS-gated).
URL: https://help.salesforce.com/s/articleView?id=000387833&type=1

### FLOW_INTERVIEW_LIMIT_EXCEEDED relationship
`FLOW_INTERVIEW_LIMIT_EXCEEDED` is the **status code the Flow runtime returns when a governor limit is breached during a flow interview** — the flow is the outer caller, so when the underlying `LimitException: Apex CPU time limit exceeded` is thrown by Apex invoked from the screen-flow action chain, the Flow surfaces it as `FLOW_INTERVIEW_LIMIT_EXCEEDED` with `error.cause` = the CPU `LimitException`. In other words: **a flow interview cannot itself "raise" the CPU limit — it is the victim/messenger.** The CPU budget belongs to the single synchronous transaction the flow runs in; whichever element happens to tip past 10,000 ms throws, and because the convert flow runs its entire action chain `flowTransactionModel=CurrentTransaction` (one sync request), the cumulative per-clone CPU across `PowerOrderSplittingService` + the 2 record-triggered OrderItem flows (× N units) is what exhausts it. Per cheatsheet footnote 5, CPU "is private for a transaction" — so moving work to a *separate* transaction is the only way to get a fresh 10,000 ms (or 60,000 ms async) budget.

---

## 2. The 10,000 DML-rows-per-transaction hard limit — async does NOT raise it

### Official cheatsheet (Per-Transaction Apex Limits table)
> "Total number of records processed as a result of DML statements, Approval.process, or database.emptyRecycleBin — **Synchronous Limit 10,000 — Asynchronous Limit 10,000**."
— `_limits_cheatsheet.txt` lines 66-67.

> "Total number of DML statements issued — 150 / 150." (line 64)

**This is the load-bearing fact for SC-3447's scaling story:** unlike CPU (10s→60s) and heap (6 MB→12 MB), the **DML-rows limit is identical in sync and async: 10,000.** Async buys you more CPU and heap but **NOT more DML rows per transaction.**

### Why this matters at the client's volumes
`PowerOrderSplittingService` creates one qty=1 `OrderItem` per unit (`for(i=1;i<qty;i++)`), each with a cloned Partition (≈2 DML rows/unit). At the repro qty 456 that is ≈912 rows — under 10k. But the client sells **up to 750,000 qty.** Even if CPU were free, **a single transaction physically cannot insert 750,000+ OrderItems** — it would blow the 10,000-row DML cap long before CPU. **Async alone does not solve this; the work MUST be chunked across multiple transactions** (Batch scope or chained Queueable), each getting its own fresh 10,000-row budget. See cheatsheet header:
> "These limits count for each Apex transaction. **For Batch Apex, these limits are reset for each execution of a batch of records in the execute method.**" (lines 28-30)

This is the single most important architectural constraint: **chunk-per-transaction is mandatory, not optional, at high qty.**

(Separate note: the live Power Quantity is a seat/user count or an "unlimited" sentinel like 9,999/99,999/999,999 — NOT a machine count, per known state. Whether one-OrderItem-per-unit is even the correct *decomposition* is a design question covered in the parallel investigation files 01/04/07; this section only establishes that IF you keep per-unit cloning, async does not rescue the DML-row ceiling.)

---

## 3. Offloading heavy per-record work from a synchronous user transaction

### Async gives higher limits + background threads — but is bounded
> "Asynchronous processing provides two major benefits for your architecture. First, it **increases scalability because asynchronous processes have higher governor limits**. Second, asynchronous requests **execute in their own threads** so users can do other work while the asynchronous tasks execute in the background."
> "**Asynchronous processing with Salesforce isn't a solution for boundless scaling needs.** The Salesforce Platform doesn't scale infinitely, and asynchronous patterns are subject to limitations… the platform has mechanisms in place (flow control, fair usage algorithm)…"
> "Before using asynchronous processing, make sure that your use cases fit the pattern. **Asynchronous patterns have no SLA**, are subject to multiple governor mechanisms… and can cause processing delays."
— Salesforce Architects, *Asynchronous Processing on the Lightning Platform Decision Guide* (`_async_decision_guide2.md` lines 10, 18-19).
URL: https://architect.salesforce.com/docs/architect/decision-guides/guide/async-processing

### Queueable Apex — chaining, depth, enqueue limits
From Trailhead *Optimize Queueable Apex for Asynchronous Processing* (WebFetch-confirmed quotes):
> "Queueable Apex is essentially a superset of future methods."
> "**Chaining jobs:** You can chain one job to another job by starting a second job from a running job."
> "When chaining jobs, you can **add only one job from an executing job** with System.enqueueJob, which means that **only one child job can exist for each parent queueable job.**"
> "For Developer Edition and Trial orgs, the **maximum stack depth for chained jobs is 5**, which means that you can chain jobs four times." (No depth limit is enforced in Enterprise/Performance/Unlimited production editions; you may optionally cap depth via the `AsyncOptions`/`System.enqueueJob` overload.)
> "The execution of a queued job **counts once against the shared limit for asynchronous Apex method executions.**"
> "You can add **up to 50 jobs to the queue with System.enqueueJob in a single (synchronous) transaction.**"
URL: https://trailhead.salesforce.com/content/learn/modules/asynchronous_apex/async_apex_queueable

**Context-dependent enqueue limit (critical, often-missed):**
> "From a trigger fired by a user action in the UI — a *synchronous* transaction — up to **50 queueable jobs** can be enqueued. However, from a trigger fired within the `execute` method of a Batch Apex class — an *asynchronous* transaction — **only one queueable job** can be enqueued. Failing to account for this difference is a common and critical failure point, leading to `LimitException` errors during large data operations."
— Record-Triggered Automation decision guide (`_record_triggered_guide.md`).
URL: https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered

So: from an **async context (batch execute / running queueable) you may enqueue only ONE job** (one child → chaining), but from the **synchronous user transaction you may enqueue up to 50.**

### Batch Apex vs Queueable — when to use which (decision-guide use-case table)
> "**High-performance batch processing** — Any automation that must process **thousands or millions of records** efficiently → **Batch Apex** — Batch Apex provides rich APIs for interfacing with the platform and for raw speed."
> "**Cascading Updates Through an Object Graph** — Allows a user's save action to complete quickly, deferring cascading updates to other objects to run asynchronously → **Queueable Apex** — Queueable Apex has powerful chaining features that enable logic to divide a chain of updates into a series of asynchronous transactions."
> "**Batch Apex** — Build complex, long-running processes that involve **millions of records by dividing your record set and processing it in manageable chunks.**"
> "**Scheduled Apex** … Although the act of scheduling Apex via the cron expression is an asynchronous process, the **underlying code executes synchronously** when the job starts."
— `_async_decision_guide2.md` lines 26-28, 54, 58.

**Batch governor behavior:** each `execute()` chunk is a *separate transaction* with its own fresh limits (cheatsheet lines 28-30). Default/typical batch scope is 200 records; you set scope explicitly in `Database.executeBatch(batchable, scopeSize)`. **This is the canonical tool for "process N thousand child records, each chunk fresh-limited."**

**Platform Events / CDC** (decision guide): pub-sub decoupling for fire-and-forget and for external-system notification; CDC events are durable and **replayable for up to 72 hours**, and "a failure in the asynchronous processing won't cause the user's record save to roll back." CDC is capped at 5 objects without an add-on license. (`_record_triggered_guide.md`)

### Async finalizers (reliability for the chain)
Queueable supports the `Finalizer` interface (`System.Finalizer` / `attachFinalizer`) so you can run cleanup/recovery logic **even if the queueable's `execute()` throws an unhandled exception** — the standard way to handle partial failure, retry, or emit a completion event in an async pipeline. (Apex Developer Guide, *Transaction Finalizers*.) Use it to record success/failure status and to decide whether to re-enqueue the next chunk.

---

## 4. Avoiding record-triggered flows firing on programmatically-created records

This is the highest-leverage fix for SC-3447: the two record-triggered OrderItem flows (`Fortra_OrderItem_Set_Dates` before-save, `Fortra_OrderItem_Set_Workday_Contract_Line_Type` after-save) **fire on every single one of the N cloned OrderItems**, and the after-save one does a Get_Product SOQL + a recordUpdate that re-enters before-save — multiplying per-clone CPU.

### Entry/start conditions are the most performant guard (checked BEFORE the interview is created)
> "The most efficient way to bypass a record-triggered flow is to prevent it from running at all by adding a condition to the flow's **entry criteria**. In the Start element… set Condition Requirements to **Formula Evaluates to True** and incorporate a check for a **custom permission using the `$Permission` global variable**… this check is performed **before the flow interview is even created**, making it the most performant approach."
— Salesforce Help, *Bypass Salesforce Flow for a Specific User or Profile* (id=000393835), via search.
URL: https://help.salesforce.com/s/articleView?id=000393835&type=1

**Guard-flag pattern for SC-3447:** stamp a boolean like `Is_Split_Line__c = true` (or set a transient context flag / assign the running user a custom permission `Bypass_OrderItem_Automation`) on the programmatically-created clones, and add to each OrderItem flow's Start entry condition: run **only when `Is_Split_Line__c = false`** (or `NOT($Permission.Bypass_OrderItem_Automation)`). Because the condition is evaluated before the interview spins up, the flow does **zero CPU** on the skipped clones. Trade-offs: a custom-field guard requires the field be set *in the same DML* as insert (so set it on the clone before insert, not in an after-save flow); a custom-permission/user-context guard is org-wide and risks suppressing legitimate edits by that user — scope it to the convert/split path only.

### Flow auto-bulkifies, but per-record CPU still accrues; don't invoke sub-automation per record
> "Flow includes built-in protections, such as **auto-bulkification** and automatic retries."
> "**Deduplication of expensive computation** … Flow excels at eliminating redundant queries and DML statements via automatic bulkification. However, **state cannot be cached or shared between different flow triggers or across multiple invocations of the same flow within one transaction.** This limitation may become important in extreme performance scenarios."
> "Always use a **before-save update** when your automation only needs to change field values on the record that starts the transaction… This pattern is performant… because **it avoids a second DML operation and a recursive save cycle.** The overhead of a second save, which would otherwise **re-execute the entire save order and fire all automation again**, is eliminated."
— `_record_triggered_guide.md` lines 87, 93, 277-279.

**Direct application:** the after-save `Set_Workday_Contract_Line_Type` flow doing a `recordUpdate` on `$Record` is exactly the anti-pattern called out — a second DML that re-fires the entire save order (re-entering Set_Dates). On N clones this is ~N extra save cycles of pure CPU. Per the guide, same-record field stamping belongs in **before-save** (or a before-context Apex trigger), never as an after-save self-update.

**Recursion ceiling:** Salesforce documents that a record-triggered flow won't re-run on the same record more than a small fixed number of times in a transaction (the documented recursion guard); each flow interview is created per record, batched at 200 (per *Flow Interviews* / *Record-Triggered Flow Considerations*). The takeaway is not the exact count but that **per-record interview creation has fixed CPU overhead that the platform does not amortize away** — fewer records and fewer interviews is the only lever.
URL: https://help.salesforce.com/s/articleView?id=platform.flow_considerations_trigger_record.htm&type=5

---

## 5. Pattern: "create N child records, then reprice/activate" without blowing limits

The decision guide's prescriptive pattern for high-volume DML that can't fit one synchronous transaction:

### Decouple heavy work from the user save
> "When a record-triggered automation's business logic becomes complex, long-running, or involves high data volumes, the Salesforce platform's core governor limits become an architectural constraint… **A failure in a synchronous trigger due to a limit exception will cause the user's entire save transaction to roll back, resulting in poor user experience and potential data loss. This inherent risk mandates an architectural pattern to offload complex work.**"
> "Asynchronous automation becomes essential… architects can effectively **decouple the long-running or high-volume work from the primary, synchronous record-save transaction. Saves complete quickly and reliably, while the heavy processing is delegated to a separate, platform-managed transaction that executes later.**"
— `_record_triggered_guide.md` lines 111, 113.

### The exact "status + scheduled/chunked drain" pattern (idempotency + partial failure)
> "1. Perform a simple, low-cost update in the synchronous trigger. For example, **set a `Status__c` field to 'pending processing'**…
> 2. Create a scheduled job… that runs periodically…
> 3. Have the scheduled job **query for all records in the pending state, execute the complex logic in a controlled, high-volume context, and then update the records as processed.**"
> "This pattern **fully decouples the heavy processing from the user's synchronous save, is not subject to the one-job-per-transaction limit** of a trigger-fired batch, and provides a highly scalable and governable solution…"
— `_record_triggered_guide.md` (async-pattern section, lines ~150-156).

**Recommended architecture for SC-3447 convert→split→reprice→activate:**
1. **Synchronous (user) transaction = thin & fast.** Convert the quote, create the base Order + base OrderItems, stamp an `Order.Split_Status__c = 'Pending Split'` (and keep the qty on the parent line — do NOT explode in-line). Commit. User gets an immediate, reliable response. This stays well under 10,000 ms because it does O(line count), not O(total qty).
2. **Async pipeline = the explosion + reprice + activate.** Hand off to **Batch Apex** (scope-chunked; each `execute()` is a fresh 10,000-row / 60,000 ms transaction) OR a **chained Queueable** (each link a fresh transaction; one child per link). Batch is the documented choice for "thousands/millions of records." Within each chunk: create the per-unit OrderItems for that slice, suppress the OrderItem flows via the `Is_Split_Line__c` entry-condition guard (§4), then run reprice/activate on a controlled, fresh-limited transaction.
3. **Idempotency:** key off `Original_Order_Item__c` (the qty-split FK already set by `PowerOrderSplittingService`) and the pending-status field so a re-run/retry does not double-create. Process only rows still in `Pending Split`; flip to `Split Complete` per chunk.
4. **Partial-failure handling:** use a **Transaction Finalizer** on the queueable (or batch `finish()` + `Database.SaveResult` inspection) to record per-chunk success/failure, surface errors to the user/Order, and re-enqueue or quarantine failed slices rather than rolling back the whole job. Async chunk failure does NOT roll back the user's original save (that already committed in step 1).
5. **Status tracking & latency caveat:** async has **no SLA** (decision guide). If the business needs the Order activated "immediately" on convert, that expectation must be renegotiated, OR a hybrid: synchronous activate only for small lines (under a safe qty threshold), async pipeline above the threshold.

### Hybrid orchestration principle (Flow owns the *what/when*, Apex owns the heavy *how*)
> "position **Record-Triggered Flow as the orchestration layer, while encapsulating high-complexity operations within Invocable Apex.**"
> "**No before-save support** [for Invocable Actions]: This is the most critical limitation. Invocable Actions are only available in the after-save context… They cannot be used in the high-performance before-save context."
— `_record_triggered_guide.md` lines (hybrid section) + 227.

---

## Consolidated mapping to SC-3447

| Finding (official) | Source | SC-3447 implication |
|---|---|---|
| CPU = 10,000 ms sync / 60,000 ms async; counts Apex + flows + workflows in ONE transaction; private per transaction | Cheatsheet table + footnote 5 | The convert flow's whole `CurrentTransaction` chain shares one 10s budget; per-clone work × N tips it over → throw |
| DB time for SOQL/DML and callout wait do NOT count toward CPU | Cheatsheet footnote 5 | Explains SOQL 19/100, DML 480/10k but CPU >10k: it's per-record app-server compute, not queries |
| Exceeding CPU rolls back the ENTIRE transaction | Salesforce Ben (confirms platform behavior) | Full rollback on convert = observed symptom |
| DML rows = 10,000 in BOTH sync and async; reset per batch execute() | Cheatsheet table + header | Async does NOT raise the row ceiling; 750k qty MUST be chunked across transactions |
| Async = higher limits + background threads, but no SLA, bounded, not infinite scaling | Async decision guide | Offload is correct, but expectation-set on latency; not a silver bullet |
| Queueable: 1 child per running job; depth 5 in Dev/Trial (unlimited in prod); 50 enqueues in sync, 1 in async context | Trailhead + record-triggered guide | Chaining drains slices; mind the sync(50)-vs-async(1) enqueue rule |
| Batch Apex = the tool for thousands/millions of records, chunked, each chunk fresh-limited | Async decision guide + cheatsheet | Best fit for the qty-explosion + reprice + activate |
| Entry-condition / custom-permission / `Is_Split_Line` guard skips the flow BEFORE the interview is created (zero CPU on skipped records) | Help (bypass flow) + record-triggered guide | Stop both OrderItem flows from firing on every clone — biggest CPU win short of redesign |
| After-save self-`recordUpdate` re-runs the whole save order (re-fires all automation) | Record-triggered guide (before-save guidance) | The `Set_Workday_Contract_Line_Type` after-save update is an anti-pattern multiplying per-clone CPU |
| Thin sync + status flag + async drain; idempotent on FK + status; finalizer for partial failure | Record-triggered guide (async-pattern) | Target architecture for convert→split→reprice→activate |

## Authoritative sources used
- **Apex Governor Limits / Per-Transaction Apex Limits (official cheatsheet, May 8 2026)** — https://developer.salesforce.com/docs/atlas.en-us.salesforce_app_limits_cheatsheet.meta/salesforce_app_limits_cheatsheet/salesforce_app_limits_platform_apexgov.htm (saved: `_limits_cheatsheet.pdf` / `_limits_cheatsheet.txt`)
- **Execution Governors and Limits — Apex Developer Guide** — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm
- **Asynchronous Processing on the Lightning Platform — Decision Guide (Salesforce Architects)** — https://architect.salesforce.com/docs/architect/decision-guides/guide/async-processing (saved: `_async_decision_guide2.md`)
- **Record-Triggered Automation — Decision Guide (Salesforce Architects)** — https://architect.salesforce.com/docs/architect/decision-guides/guide/record-triggered
- **Optimize Queueable Apex for Asynchronous Processing — Trailhead** — https://trailhead.salesforce.com/content/learn/modules/asynchronous_apex/async_apex_queueable
- **Queueable Apex — Apex Developer Guide** — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_queueing_jobs.htm
- **Large Data Processing with Cursors and Queueable Apex Versus Batch Apex — Apex Developer Guide** — https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_cursors_versus_batch.htm
- **Code more efficiently to avoid 'Apex CPU time limit exceeded' — Salesforce Help** — https://help.salesforce.com/s/articleView?id=000387833&type=1
- **Bypass Salesforce Flow for a Specific User or Profile — Salesforce Help** — https://help.salesforce.com/s/articleView?id=000393835&type=1
- **Record-Triggered Flow Considerations — Salesforce Help** — https://help.salesforce.com/s/articleView?id=platform.flow_considerations_trigger_record.htm&type=5
- **What Is 'Apex CPU Time Limit Exceeded' & How Do You Solve It? — Salesforce Ben** (confirms full-rollback + flows share CPU) — https://www.salesforceben.com/what-is-apex-cpu-time-limit-exceeded-how-do-you-solve-it/
