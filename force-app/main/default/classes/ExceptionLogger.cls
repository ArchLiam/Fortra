/**
 * General-purpose, never-throw telemetry publisher (D-18).
 *
 * Each domain builds its own `<Domain>_Exception__e` platform event and calls
 * `safePublish()`. The publish is fire-and-forget and never throws for any
 * catchable exception: callers invoke it from catch blocks that swallow-to-
 * SUCCESS, so a throw here would convert a silent, graceful degrade into a hard
 * hook failure (a pricing-output change). The one theoretical exception is an
 * UNCATCHABLE governor `LimitException` (e.g. a transaction already at the
 * DML-statement limit) — no `catch` can trap that; pricing hooks do light DML so
 * it is not a practical risk. Durability comes from a subscriber that persists
 * the event into `Exception_Log__c`; the event itself only lives ~72h in the bus.
 *
 * The domain event must be defined with PublishBehavior = Publish Immediately so
 * the message survives a rolled-back transaction (see D18_TELEMETRY_DESIGN.md).
 */
public inherited sharing class ExceptionLogger {

    public enum Severity { ERROR, WARNING, INFO }

    /**
     * Publish a telemetry event without ever propagating a failure.
     * A null event is a safe no-op.
     *
     * @param event a platform-event SObject (e.g. Pricing_Exception__e)
     */
    public static void safePublish(SObject event) {
        if (event == null) {
            return;
        }
        try {
            EventBus.publish(event);
        } catch (Exception ignore) {
            // Last resort only — never re-throw from an instrumentation path.
            System.debug(LoggingLevel.ERROR, 'ExceptionLogger.safePublish failed: ' + ignore.getMessage());
        }
    }
}
