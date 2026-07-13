# Apex Coding Compliance Standard

## §0 Purpose & Scope

This standard defines the mandatory rules that all Apex code in this Salesforce Revenue Lifecycle Management (RLM) + OmniStudio pricing org must satisfy before merge. It applies to every Apex class, trigger, test class, and OmniStudio-adjacent Apex hook (prehooks, posthooks, calculators, invocables).

- Rules stated with **must**/**shall** are mandatory; a violation blocks merge.
- Rules stated with **should** are strongly recommended; deviations require a one-line justification in the PR description.
- This standard is timeless and general. It contains no ticket numbers, project codes, or dated notes, and neither may any code artifact governed by it (see §1).
- Scale of rigor: apply full layered separation of concerns (§4) to any code with multiple entry points, batch scaling, or shared ownership. A trivial single-purpose one-off may use lighter structure, but never at the cost of §5–§9.

---

## §1 File & Method Documentation (headers)

Every Apex file **must** begin with an ApexDoc file/class header, and every method **must** have an ApexDoc method header. Headers **must** be simple and intent-describing.

**Headers MUST NOT contain** ticket numbers, JIRA IDs, project codes, dates, changelogs, revision history, author memos, or any other mutable provenance. That information lives in version control (`git blame`/history), not in source comments.

Rules:

1. Every class, interface, and enum **must** open with a `/** ... */` block placed immediately above the declaration.
2. The class header **must** contain exactly one `@description` (a short, present-tense statement of purpose) and the `@author` line specified below **exactly**.
3. Every public/global method — and every non-trivial private helper — **must** carry a header with exactly one `@description`, one `@param` per parameter, and one `@return`. Omit `@return` for `void` methods; omit `@param` when there are no parameters.
4. `@description` **must** be the first tag in every block so it renders as the summary line.
5. Only the supported ApexDoc tag vocabulary may be used: `@description`, `@param`, `@return`, `@author`, `@example`, `@see`, `@throws`, `@since`. Do not invent ad-hoc tags.
6. `@example`, `@see`, and `@throws` are optional enrichments — add them only where they carry real value; never add empty or boilerplate tags.

### File / class header template (copy-paste)

```apex
/**
 * @description One line stating what this class does.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class ExampleService {
```

### Method header template (copy-paste)

```apex
/**
 * @description One line stating what this method does.
 * @param recordIds The ids to process.
 * @return The records that were updated.
 */
public List<SObject> doWork(Set<Id> recordIds) {
```

For a `void`, no-argument method:

```apex
/**
 * @description One line stating what this method does.
 */
public void run() {
```

---

## §2 Trigger Framework

1. **Exactly one trigger per object.** All trigger logic for an sObject **must** live in a single trigger file. Multiple triggers on one object execute in a non-deterministic order and are prohibited.
2. **The trigger body contains NO business logic.** It **must** do nothing but route, using `switch on Trigger.operationType`, to methods on a dedicated handler class named `<Object>TriggerHandler`.
3. The handler **must** expose one context-specific method per event (`beforeInsert`, `beforeUpdate`, `afterInsert`, etc.) so each DML/timing permutation is isolated and independently testable.
4. Handlers **must** enforce a recursion/re-entrancy guard (a max loop count or static flag) that throws rather than cascading indefinitely.
5. The framework **should** provide a bypass API (e.g. `bypass(handlerName)`, `isBypassed()`, `clearAllBypasses()`) so automation can be suppressed during data loads and cross-object cascades without commenting out code.
6. Self-field changes on the incoming record **must** be made by mutating `Trigger.new` in a `before` context — never by issuing a DML update against the same records.
7. Never pass `Trigger.new`/`Trigger.old` directly into DML, never modify `Trigger.old` (read-only), and never delete `Trigger.new`.

### Trigger skeleton (copy-paste)

```apex
/**
 * @description Single trigger for Account; delegates to AccountTriggerHandler.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    AccountTriggerHandler handler = new AccountTriggerHandler();

    switch on Trigger.operationType {
        when BEFORE_INSERT  { handler.beforeInsert(Trigger.new); }
        when BEFORE_UPDATE  { handler.beforeUpdate(Trigger.new, Trigger.oldMap); }
        when BEFORE_DELETE  { handler.beforeDelete(Trigger.oldMap); }
        when AFTER_INSERT   { handler.afterInsert(Trigger.newMap); }
        when AFTER_UPDATE   { handler.afterUpdate(Trigger.newMap, Trigger.oldMap); }
        when AFTER_DELETE   { handler.afterDelete(Trigger.oldMap); }
        when AFTER_UNDELETE { handler.afterUndelete(Trigger.newMap); }
    }
}
```

---

## §3 Naming & Class Design

1. Class, interface, and enum names **must** be PascalCase, starting with an uppercase letter (`OpportunityService`, not `opportunityService` or `Opportunity_Service`). No organization or vendor prefix (e.g. `Fortra_`) is required or expected — the role suffix conveys purpose.
2. Method names **must** be camelCase starting with a lowercase verb (`applyDiscounts`, `updateOpportunityStage`). Variables **must** be meaningful and camelCase.
3. Interfaces **must** carry an `I` prefix (`IEmailSender`) to distinguish abstraction from implementation and to support mocking.
4. Role suffixes are mandatory and reserved: `Service`, `TriggerHandler`, `Controller`, `Batch`, `Queueable`, `Calculator`, `Prehook`, `Posthook`. Custom exceptions **must** end in `Exception`.
5. Do not define a class and interface with the same name in the same enclosing scope, and do not give an inner class the name of its outer class.
6. Names **must** be intention-revealing: a method is named for its business purpose (`applyDiscounts`), never for its caller or usage site.

---

## §4 Separation of Concerns

Each layer owns exactly one responsibility and **must not** absorb another layer's job.

| Layer | Responsibility | Must not |
|---|---|---|
| **TriggerHandler** | Route trigger events to services/domain logic. | Contain business logic inline. |
| **Service** (`*Service`) | Orchestrate business logic; caller-agnostic. | Assume a UI/batch caller; hold trigger logic. |
| **Calculator** | Pure pricing/derivation computation from inputs to outputs. | Perform SOQL, DML, or side-effects. |
| **Controller** (`*Controller`) | Thin `@AuraEnabled`/entry-point adapter to a Service. | Contain business logic; be reused as a service. |
| **Prehook** | Prepare/seed pricing inputs before the pricing procedure runs. | Persist final results; clobber user overrides (§8). |
| **Posthook** | Reconcile/stamp results after the pricing procedure runs. | Re-run core pricing; overwrite user-entered values (§8). |
| **Batch** (`*Batch`) | Process large/mass record sets in chunked transactions. | Hold business rules that a Service should own. |
| **Queueable** (`*Queueable`) | Async chained/complex-typed work with monitoring. | Duplicate service logic; enqueue >1 child job (§10). |
| **Invocable** (`@InvocableMethod`) | Flow/OmniStudio entry adapter; bulk-safe by list. | Process one record at a time; embed heavy logic. |

Rules:

1. Business logic **must** live in Services (or a per-object domain class), never in triggers, controllers, prehooks, posthooks, or invocables.
2. Services **must** be caller-agnostic: a controller, batch, queueable, and web service **must** all be able to invoke the same service without side effects.
3. SOQL for an object **should** be centralized (one reusable query method per access pattern) and **must not** be duplicated ad hoc across services, controllers, hooks, and triggers, nor placed inside a loop (§5).
4. Calculators **must** be pure functions (deterministic, no I/O) so pricing math is unit-testable in isolation.
5. `@InvocableMethod` methods **must** accept and return `List<...>` and process the whole batch — never one record per invocation.

---

## §5 Bulkification & Governor Safety

1. **No SOQL, SOSL, or DML inside a loop — ever.** Every method and trigger **must** operate on collections, not single records.
2. To fetch related data, collect ids into a `Set` (e.g. from `Trigger.newMap.keySet()`) and issue a **single** query with `WHERE Id IN :idSet`. Cache results in a `Map` keyed by Id for in-memory lookup.
3. Accumulate records into a `List` and perform **one** DML per operation type after the loop.
4. Helper methods that contain SOQL or DML **must** take a `Set`/`List` (bulk signature); a single-record signature is prohibited for such methods.
5. Queries **must** be selective: filter on indexed fields (`Id`, foreign keys, `CreatedDate`, external/custom-indexed fields) so the filter matches under ~10% of rows.
6. For potentially large result sets, use a SOQL `for` loop (`for (List<SObject> batch : [SELECT ...])`) to stay within heap limits — do not assign a huge result set to one variable.
7. Never hardcode record, RecordType, profile, or metadata Ids. Resolve them dynamically via SOQL, describe calls, Custom Metadata, Custom Settings, or Custom Labels.
8. In complex flows, assert headroom with `Limits` methods (`Limits.getQueries()`, `Limits.getDMLStatements()`) and stay within per-transaction ceilings (100 SOQL / 150 DML synchronous; 50,000 rows).
9. Offload mass or high-volume work to asynchronous Apex (§10) rather than pushing synchronous limits.

---

## §6 Security & Sharing

1. Every class that performs SOQL/SOSL or DML **must** carry an explicit sharing declaration (`with sharing`, `without sharing`, or `inherited sharing`). Relying on the implicit default is prohibited.
2. Default to `with sharing`. `without sharing` is reserved for narrowly-scoped operations that provably require it (e.g. admin/pricing/migration reads), with a one-line reason in the header/PR.
3. Reusable service/utility classes **should** use `inherited sharing` so they adopt the caller's context.
4. A sharing keyword governs record-level access only; object- and field-level security is a separate concern and **must not** be assumed from `with sharing` alone.
5. `@AuraEnabled` controllers **must** declare `with sharing` explicitly.
6. Never hardcode secrets (passwords, tokens, keys) in source, and never write PII or credentials to logs or URL parameters. Store external-service auth in Named Credentials; store package-internal secrets in protected Custom Metadata or protected Custom Settings.

---

## §7 Currency & Pricing Correctness

This is a multi-currency pricing org. Currency-blind lookups are a recurring defect class and are prohibited.

1. **Per-currency `PricebookEntry` is authoritative.** Prices **must** be read from the `PricebookEntry` matching the transaction's `CurrencyIsoCode` — never from an FX conversion of another currency's value.
2. Every SOQL that resolves a price, rate, or catalog value in a multi-currency context **must** filter by `CurrencyIsoCode` (e.g. `WHERE CurrencyIsoCode = :quoteCurrency`). A price lookup with no currency predicate is a violation.
3. When correlating price data to lines, key lookup `Map`s by a composite that includes currency (e.g. `Product2Id + CurrencyIsoCode`), not by `Product2Id` alone.
4. Do not silently fall back to a USD value when a currency-specific record is missing; treat the gap as an error condition (§9), not a default.
5. Calculators **must** receive the currency as an explicit input and **must not** assume the org default currency.

---

## §8 Idempotency & Side-Effects

1. Prehooks, posthooks, and stamping logic **must** be idempotent: running them twice on the same record produces the same result and no duplicate side-effects.
2. **Fill-only stamps.** Automated stamps **must** populate a field only when it is blank/null. They **must not** overwrite a value a user (or an earlier authoritative step) has already set.
3. **Never clobber user overrides.** Where a rep-entered override can exist (e.g. a manual price/line override), automation **must** detect and preserve it.
4. Async jobs **must** be designed idempotent so a retry or redelivery cannot double-apply an effect.
5. Prefer `before`-context mutation for self-field changes (§2) over post-persist re-updates, to avoid extra DML and recursion.

---

## §9 Error Handling & Logging

Failures **must never be silent**, yet a caught error in a graceful-degrade path **must never corrupt output**. The org reconciles these with a fire-and-forget platform-event telemetry model: build a `<Domain>_Exception__e` event and publish it — the degrade stays visible, and the transaction's result is unchanged.

1. **No silent swallow.** A caught exception **must** either propagate (rule 6) or publish telemetry (rule 4). An empty catch, or a catch that hides failure with no telemetry, is prohibited.
2. **Swallow-to-degrade is allowed only where graceful degradation is the correct behavior** — e.g. a pricing hook that must return `SUCCESS` because throwing would change pricing output. Such a catch **must** publish telemetry and **must not** re-throw.
3. **A typed exception per specific case — the type is the category.** Deliberate or classifiable failures **must** use a specific custom exception extending `AppException` (`virtual`, `extends Exception`), or `PricingException` (`extends AppException`) for the pricing domain — named for the case and ending in `Exception` (e.g. `OrderSubmissionException`, `PricingContextException`). The exception **type**, recorded in `Exception_Log__c.Exception_Type__c`, is how entries are categorized, so **do not** add a RecordType per domain to classify. Use these types both for deliberate throws **and** to wrap-and-classify a swallowed system exception before logging (`new PricingContextException('resolveTag failed', e)`); the logger stores the wrapper's type and the root cause's stack.
4. **Log through the central publisher — never `insert Exception_Log__c` or `EventBus.publish` from a catch.** A direct insert is lost when the transaction rolls back; the platform-event path survives it.
   - **General classes** (service / calculator / controller / batch / queueable): call **`ExceptionLogger.log(source, contextId, e)`**, which publishes a generic **`Fortra_Exception__e`** into `Exception_Log__c`.
   - **Pricing hooks**: use **`PricingHookLogger.logPrehook` / `logPosthook(hookName, contextId, e)`**.
   - Build a bespoke `<Domain>_Exception__e` (published via `ExceptionLogger.safePublish(event)`) only when you need domain-specific fields.
   - **Availability & fallback — verify against the target org, never assume.** The generic `ExceptionLogger.log(source, contextId, e)` facade and its `Fortra_Exception__e` event are the **target state** and may not be deployed in a given org yet. The **currently deployed baseline** is `ExceptionLogger.safePublish(event)` plus the `Pricing_Exception__e` event (fields `Source__c`, `Severity__c`, `Exception_Type__c`, `Message__c`, `Stack_Trace__c`, `Context_Id__c`, `Transaction_Id__c`, `Occurred_At__c`, `Hook_Phase__c`). Before writing a catch, confirm which facade the target org actually has (e.g. retrieve `ExceptionLogger` and check for `log`). When `log` is absent, a **general class must fall back** to publishing `Pricing_Exception__e` via `safePublish`, wrapping the system exception in its typed domain exception and setting: `Source__c` = the class name, `Severity__c = 'Error'` (that exact casing — not `ERROR`), `Exception_Type__c` = the wrapper's `getTypeName()`, `Message__c` = the wrapper message, `Stack_Trace__c` = the **root cause** stack (`cause.getStackTraceString()`), `Transaction_Id__c` = `System.Request.getCurrent().getRequestId()`, `Occurred_At__c = System.now()`. Truncate each field to its column limit. `PricingHookLogger` is **hook-only** (it stamps `Hook_Phase__c`) — do not call it from a service/calculator/batch/queueable.
   Invoke the logger **once**, in the top-level catch block — never per line.
5. Every `*_Exception__e` platform event **must** be defined with `PublishBehavior = Publish Immediately` so the message survives a rolled-back transaction; a subscriber Flow persists it to `Exception_Log__c`. The `ExceptionLogger.log` and `PricingHookLogger` facades already satisfy this — prefer them over hand-rolled publishing. Set severity via `ExceptionLogger.Severity` (`ERROR` / `WARNING` / `INFO`).
6. When aborting on an exception that is **not** a graceful-degrade path, **log with full detail and then re-throw** (or throw a wrapping domain exception). Logging **must not** replace propagation.
7. When surfacing errors to a client/UI, throw `AuraHandledException` with a controlled, user-friendly message and a single standardized error shape — never leak raw system exception detail.
8. `System.debug()` is a last-resort local aid only; it **must not** be the durability mechanism. Persistence goes through the platform-event pipeline.

---

## §10 Asynchronous Apex

1. Default to **Queueable** over `@future` for new async work (job Id for monitoring, non-primitive params, chaining). Use `@future` only when Queueable cannot.
2. Select by workload shape: `@future` for isolated callouts/fire-and-forget; **Queueable** for chained or complex-typed jobs; **Batch** for large record sets in independent chunk transactions; **Scheduled** only as a time trigger that delegates to Queueable/Batch.
3. Enqueue at most **one child Queueable** from an executing Queueable, and keep chain depth within the platform stack limit.
4. Respect enqueue limits: at most 50 `System.enqueueJob` per synchronous transaction, only 1 inside an async context. Guard with `Limits.getQueueableJobs()` before enqueuing.
5. Where a Queueable needs guaranteed cleanup or recovery (logging, retries, notifications) regardless of success or failure, it **should** attach a `System.Finalizer`.
6. `@future` methods **must** be `static`, return `void`, and accept only primitives/arrays/collections of primitives. Pass record **Ids** (not sObjects) and re-query current data inside the method.
7. Never issue callouts or `@future` calls inside a loop — aggregate the work into a single async invocation.
8. Async jobs **must** be idempotent and fast, and **must** stay within daily async and callout limits.

---

## §11 Testing

1. Every test **must** assert outcomes with `System.Assert` methods (`Assert.areEqual`, `Assert.isTrue`, `Assert.isNotNull`, etc.). Coverage-only tests with no assertions are prohibited.
2. Prefer the modern `Assert` class over legacy `System.assert*`, and pass a descriptive message to every assertion.
3. Test expected exceptions by wrapping the call in try/catch, calling `Assert.fail()` immediately after the call, and asserting on the caught exception's type/message in the catch block.
4. `@isTest(SeeAllData=true)` is prohibited. Each test **must** create its own data, via a shared `@isTest` test-data factory rather than duplicated inline construction.
5. Exercise bulk behavior: any test touching DML or triggers **must** run against **at least 20 records**.
6. Cover positive, negative, single-record, and bulk scenarios, exercising each conditional branch with valid and invalid inputs.
7. Set up data before `Test.startTest()`, invoke the code under test between `Test.startTest()` and `Test.stopTest()`, and assert after `Test.stopTest()`. Call each at most once per test method. Async work enqueued after `startTest` is assertable only after `stopTest`.
8. HTTP callouts **must** be tested with an `HttpCalloutMock` registered via `Test.setMock`. Real callouts in tests are prohibited. Mark mock and helper classes `@isTest`.
9. Maintain one dedicated test class per production class (e.g. `FooService` → `FooServiceTest`). Do not assume Id ordering — use `ORDER BY` for ordering assertions.
10. Use `System.runAs()` to validate sharing- and permission-dependent behavior under the relevant profiles/permission sets, not only as admin.
11. Multi-currency pricing paths (§7) **must** include at least one non-default-currency test proving the currency-specific `PricebookEntry` is used.

---

## §12 PR Compliance Checklist

- [ ] Every file starts with the ApexDoc file/class header; `@author Liam Jeong <liam.jeong@coastalcloud.us>` present verbatim.
- [ ] Every method has an `@description` and `@param`/`@return` as applicable.
- [ ] No ticket numbers, JIRA IDs, dates, changelogs, or memos in any header or comment.
- [ ] Exactly one trigger per object; trigger body is logic-less and routes via `switch on Trigger.operationType` to `<Object>TriggerHandler`.
- [ ] Recursion guard present in the handler framework.
- [ ] PascalCase types, camelCase methods/vars, `I`-prefixed interfaces, correct role suffixes, no vendor prefix.
- [ ] Business logic in Services; SOQL centralized per object; Calculators pure; controllers/hooks/invocables thin.
- [ ] No SOQL/SOSL/DML in loops; bulk (`IN :set`) queries; single collection DML; helpers take collections.
- [ ] Selective queries on indexed fields; no hardcoded Ids; limits headroom respected.
- [ ] Explicit sharing declaration on every DB-touching class; secrets in Named Credentials / protected metadata.
- [ ] Multi-currency lookups filter by `CurrencyIsoCode`; per-currency `PricebookEntry` used; no USD fallback.
- [ ] Stamps are fill-only and idempotent; user overrides preserved.
- [ ] No silent swallow; caught errors propagate or log via `ExceptionLogger.log(source, contextId, e)` (→ `Fortra_Exception__e`) — pricing hooks via `PricingHookLogger`; **never** `insert Exception_Log__c` or `EventBus.publish` from a catch. A typed exception per case (extending `AppException`/`PricingException`, ending in `Exception`) classifies via `Exception_Type__c` — no per-domain RecordTypes. Events are Publish Immediately → `Exception_Log__c`.
- [ ] Telemetry facade **verified present in the target org** before use; where `ExceptionLogger.log`/`Fortra_Exception__e` is not yet deployed, general classes fall back to `ExceptionLogger.safePublish(new Pricing_Exception__e(...))` with `Severity__c = 'Error'`, wrapper `getTypeName()` in `Exception_Type__c`, and the root-cause stack.
- [ ] Async: Queueable default; ≤1 child job; enqueue limits guarded; Ids (not sObjects) into `@future`.
- [ ] Tests assert outcomes; ≥20-record bulk case; positive/negative branches; no `SeeAllData=true`; callouts mocked; `runAs` for security; non-default-currency pricing test.
