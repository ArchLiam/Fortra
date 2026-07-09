# D-18 — Pricing-Hook Exception Logging (design working doc)

**Status:** ✅ DEPLOYED to FortraUAT 2026-07-08 (39 components, NoTestRun deploy). D-18 tests 4/4 PASS —
incl. the two end-to-end tests proving PE→subscriber-Flow→`Exception_Log__c` delivery works in-org (the one
risk static review couldn't retire). NOT yet committed to git. Owner: Liam.
**Purpose:** make the "a pricing hook caught an exception and returned SUCCESS anyway" failure class
*durably visible* (queryable / reportable / alertable) at the moment it happens — without changing any
pricing behavior. Closes D-18 (INV-15). Complements D-17 (AttrVolume no-match surface).

## Design shape (locked 2026-07-08)
**Per-domain platform events funnel into ONE shared, generalized `Exception_Log__c` object, keyed by
Record Type.** Pricing brings its own event (`Pricing_Exception__e`); the shared object + its record types
are the generalization layer, so other domains (integration, triggers, batch) can adopt later with their
own event + a new Record Type — no schema fork.

```
 hook.execute() ─catch─▶ PricingHookLogger.logPre/Posthook(hook, ctxId, e)   [never throws, fire-and-forget]
                                    │ ExceptionLogger.safePublish(new Pricing_Exception__e(...))
                                    │        (EventBus.publish, Publish Immediately)
                                    ▼
                         Pricing_Exception__e   (platform event, ~72h bus retention, survives rollback)
                                    │  subscribed by
                                    ▼
              PE-triggered Flow ──inserts──▶  Exception_Log__c  (RecordType = "Pricing Exception")
              (own async txn, system context → NOT in pricing txn → no rollback-loss, no pricing DML cost)

   future:  Integration_Exception__e ─▶ Flow ─▶ Exception_Log__c (RT "Integration Exception")   [not v1]
```

## Verified mechanics (from `w7dxh0mzi` fan-out, SF-doc-grounded)
- `EventBus.publish()` IS permitted in the RCA hook context (`RevSignaling.SignalingApexProcessor.execute`);
  2 hooks already do `System.enqueueJob` + DML today.
- **`PublishBehavior = Publish Immediately` is MANDATORY.** Default (`Publish After Commit`) is *discarded on
  rollback* — dropping telemetry in the exact failing transactions we care about. Publish Immediately fires
  outside the DB txn, survives rollback, draws from a SEPARATE 150-publish-call limit (zero DML-statement cost).
- Raw event retained ~72h then purged → **durability requires the subscriber-written `Exception_Log__c` row.**
- The publish MUST be wrapped so it can never re-throw (it instruments swallow paths; a throw here would turn
  a silent SUCCESS into a hook failure = a pricing-output delta).

## 1. Platform event `Pricing_Exception__e`  (PublishBehavior = **Publish Immediately**, high-volume)
| Field | Type | Purpose |
|-------|------|---------|
| `Source__c` | Text(80) | the hook/class name (`PartnerNetPricePosthook`) |
| `Hook_Phase__c` | Text(20) | `Prehook` / `Posthook` |
| `Severity__c` | Text(10) | `Error` (default) / `Warning` / `Info` |
| `Context_Id__c` | Text(18) | `request.ctxInstanceId` — anchor to the transaction |
| `Transaction_Id__c` | Text(40) | `Request.getCurrent().getRequestId()` — groups a reprice's degrades |
| `Exception_Type__c` | Text(255) | `e.getTypeName()` |
| `Message__c` | Long Text(32768) | `e.getMessage()` |
| `Stack_Trace__c` | Long Text(32768) | `e.getStackTraceString()` |
| `Occurred_At__c` | DateTime | `System.now()` at publish |

## 2. Custom object `Exception_Log__c`  (GENERALIZED durable store, Record-Type keyed)
- Auto-number Name `EL-{0000000000}`.
- **Record Types:** `Pricing_Exception` (v1). Future domains add their own RT (Integration, Trigger, Batch…).
  A `Master`/default RT exists per platform requirement; page layouts per RT.
- Fields mirror the event 1:1 (`Source__c`, `Hook_Phase__c`, `Severity__c`, `Context_Id__c`,
  `Transaction_Id__c`, `Exception_Type__c`, `Message__c`, `Stack_Trace__c`, `Occurred_At__c`).
  `Hook_Phase__c` is pricing-oriented — generic RTs leave it blank (own layout).
- Normal custom object → reports / list views / dashboards out of the box.
- **Retention:** scheduled Flow deletes rows older than **90 days**. [default — confirm]
- **v1 stores raw `Context_Id__c`** (the ctxInstanceId); investigator resolves to Quote/Order. No enrichment.

## 3. Apex — shared plumbing + pricing facade
```apex
public inherited sharing class ExceptionLogger {
    public enum Severity { ERROR, WARNING, INFO }
    // Shared never-throw publish. Each domain builds its own *_Exception__e and calls this.
    public static void safePublish(SObject event) {
        try { EventBus.publish(event); }
        catch (Exception ignore) {
            System.debug(LoggingLevel.ERROR, 'ExceptionLogger.safePublish failed: ' + ignore.getMessage());
        }
    }
}

public inherited sharing class PricingHookLogger {          // the clean pricing call site
    public static void logPrehook(String hook, String ctxId, Exception e)  { publish(hook, 'Prehook',  ctxId, e); }
    public static void logPosthook(String hook, String ctxId, Exception e) { publish(hook, 'Posthook', ctxId, e); }
    private static void publish(String hook, String phase, String ctxId, Exception e) {
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c         = hook,
            Hook_Phase__c     = phase,
            Severity__c       = 'Error',
            Context_Id__c     = ctxId,
            Transaction_Id__c = System.Request.getCurrent().getRequestId(),
            Exception_Type__c = e != null ? e.getTypeName()         : null,
            Message__c        = e != null ? e.getMessage()          : null,
            Stack_Trace__c    = e != null ? e.getStackTraceString() : null,
            Occurred_At__c    = System.now()
        ));
    }
}
```
- One publish per hook call in its catch → ≤~8 publishes/txn (never per-line).
- Existing `System.debug(LoggingLevel.ERROR, ...)` lines STAY (additive; belt-and-suspenders).

### Custom exception seed (for future INTENTIONAL throws + auto-classification)
```apex
public virtual class AppException extends Exception {}
public class PricingException extends AppException {}
```
Not required for the swallow-logging (caught exceptions are system types); useful when our own code
deliberately throws a domain error. `ExceptionLogger` can later auto-derive category when `e instanceof AppException`.

## 4. Subscriber — PE-triggered Flow (declarative)
- Record-triggered Flow on `Pricing_Exception__e` → Create `Exception_Log__c`,
  `RecordTypeId` = "Pricing Exception", map 9 fields.
- Runs as Automated Process user in system context (CRUD/FLS not enforced) → insert succeeds.
- **Fault path** so a subscriber failure isn't itself a silent swallow → email alert to an admin.
- Flow over Apex trigger: declarative, admin-owned, no test burden. Escalate to Apex only if dedup /
  enrichment / high-volume chunking is later needed.

## 5. Hook wiring (8 hooks — TWO shapes, confirmed by fan-out)
Insert `PricingHookLogger.logPrehook/logPosthook('<HookName>', <ctxIdInScope>, e);` INSIDE each top-level catch.
- 5 set `status=SUCCESS` inside the catch → logger sits beside it:
  `PartnerNetPricePosthook`(post), `PartnerPricingPrehookV2`(pre), `COLAUpliftPrehook`(pre),
  `QLDescriptionGeneratorPrehook`(pre), `CancelLineCreditPosthook`(post).
- 3 set only a local `message` in the catch and return SUCCESS at the method TAIL → logger goes **inside the
  catch, NOT the tail** (tail runs on the happy path too):
  `AttributeVolumePricingPrehook`(pre), `RegionalServicesPricingPrehook`(pre), `HardwareAttributePricingPrehook`(pre).
- ctxId source: `request.ctxInstanceId` / local `contextId` in scope; null-safe if absent.

## 6. Testing
- `ExceptionLoggerTest`: `safePublish` never throws (null event, bad event); contract test.
- End-to-end negative test: force an exception in a representative hook; `Test.stopTest()` delivers the PE →
  subscriber Flow fires → assert (a) hook `response.status == SUCCESS` (unchanged swallow) and (b) one
  `Exception_Log__c` row with RT "Pricing Exception" and the right `Source__c`.
- 0-delta: existing characterization tests unchanged + golden full-matrix reprice = 0 delta.

## 7. Deploy sequence (future, on explicit auth — NOTHING deploys yet)
1. `Exception_Log__c` object + fields + `Pricing_Exception` Record Type
2. `Pricing_Exception__e` platform event + fields (Publish Immediately)
3. Subscriber Flow (+ fault path) + retention Flow (90-day purge)
4. `ExceptionLogger` + `PricingHookLogger` (+ `AppException`/`PricingException` seed) + tests
5. 8 hook one-line catch edits
→ Gate: golden full-matrix 0-delta + negative test green.

## Locked decisions
- Names: `Pricing_Exception__e` · `Exception_Log__c` (generalized) · RT `Pricing Exception` · `ExceptionLogger` +
  `PricingHookLogger` facade · `AppException`/`PricingException` seed.
- Raw `Context_Id__c` in v1 (no Quote/Order enrichment). · Flow subscriber. · 90-day purge (confirm).
- Log-only v1 (alerting = later 2nd subscriber). · Wire all 8 hooks now. · Publish Immediately. · 0-delta gate.

## Verification (workflow `w2f39z935`, 6 agents — metadata + flows + apex/0-delta + adversarial refute)
**Verdict: DEPLOY_READY for UAT.** All 4 load-bearing claims QUALIFIED (none refuted); metadata + flows
DEPLOY_READY; corrections converged on the findings below.
- **FIXED — null-request 0-delta gap (was MINOR):** `COLAUpliftPrehook`, `PartnerNetPricePosthook`,
  `PartnerPricingPrehookV2` deref'd `request.ctxInstanceId` in the catch (the 3 hooks that resolve ctxId
  *inside* the try). If `request` were null the NPE would escape the catch and hard-fail the reprice.
  → changed to `request != null ? request.ctxInstanceId : null` (matches the other hooks). Now truly 0-delta.
- **NOTED — ExceptionLogger `LimitException` caveat:** `catch(Exception)` cannot trap an uncatchable governor
  `LimitException`; "never throws" clarified in the class header. Not a practical risk (hooks do light DML).
- **CONFIRMED valid:** LongTextArea (32768) + DateTime on a HighVolume platform event; the run-once
  Scheduled retention flow (Scheduled trigger, no start `<object>`, daily); the PE-triggered subscriber shape
  (all 9 `$Record` field refs resolve; RT lookup + RecordTypeId create valid; runs as Automated Process user
  in system context → CRUD/FLS not enforced → insert succeeds).

### Deferred (not UAT blockers)
- **PROD-only flow-coverage gate (was MAJOR):** deploying the 2 Active autolaunched flows to PRODUCTION is
  subject to the org-wide active-flow test-coverage %. UAT sandbox is NOT gated. Before prod: add a Flow
  Test, or confirm the aggregate stays above threshold, or deploy inactive + activate in Setup.
- **Test-delivery confirm-at-deploy:** the 3 end-to-end tests assert the PE-triggered subscriber Flow creates
  the `Exception_Log__c` row after `Test.stopTest()`. SF docs confirm PE→flow delivery in test context; the
  combined deploy provides the Active flow. If the org does not deliver in test, the fallback is an Apex
  trigger subscriber (mutually exclusive with the Flow — do not run both, or rows double).
- **Optional hardening (MINOR/NIT):** fault connector on `Create_Exception_Log` (last-resort capture); RT
  null-check decision (else silent default-RT misfile); retention >10k-row batch cap (zero backlog today).
