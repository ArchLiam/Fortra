/**
 * @description General-purpose, never-throw telemetry publisher. Each domain builds its own
 *              `<Domain>_Exception__e` platform event and calls `safePublish()`, which is
 *              fire-and-forget and never throws for a catchable exception so callers can invoke
 *              it from catch blocks that swallow-to-SUCCESS without turning a graceful degrade
 *              into a hard hook failure. Durability comes from a subscriber that persists the
 *              event into `Exception_Log__c`; the domain event must be defined with
 *              PublishBehavior = Publish Immediately so it survives a rolled-back transaction.
 *              Callers that do not need a bespoke event can call `log(source, contextId, e)`,
 *              which publishes a generic `Fortra_Exception__e` into the same `Exception_Log__c` sink.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public inherited sharing class ExceptionLogger {

    public enum Severity { ERROR, WARNING, INFO }

    /**
     * @description Publishes a telemetry event without ever propagating a failure; a null event is a safe no-op.
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

    /**
     * @description Logs a caught exception to Exception_Log__c via a generic Fortra_Exception__e event. Never throws.
     * @param source the class or component that caught the exception
     * @param contextId the id of the record being processed, or null
     * @param e the caught exception; a null exception is a safe no-op
     */
    public static void log(String source, String contextId, Exception e) {
        log(source, contextId, Severity.ERROR, e);
    }

    /**
     * @description Logs a caught exception at the given severity to Exception_Log__c via a Fortra_Exception__e event.
     * @param source the class or component that caught the exception
     * @param contextId the id of the record being processed, or null
     * @param severity the severity to record
     * @param e the caught exception; a null exception is a safe no-op
     */
    public static void log(String source, String contextId, Severity severity, Exception e) {
        if (e == null) {
            return;
        }
        Exception root = e;
        while (root.getCause() != null) {
            root = root.getCause();
        }
        safePublish(new Fortra_Exception__e(
            Source__c         = truncate(source, 80),
            Exception_Type__c = truncate(e.getTypeName(), 255),
            Severity__c       = severityLabel(severity),
            Context_Id__c     = truncate(contextId, 18),
            Transaction_Id__c = truncate(currentRequestId(), 40),
            Message__c        = truncate(e.getMessage(), 32768),
            Stack_Trace__c    = truncate(root.getStackTraceString(), 32768),
            Occurred_At__c    = System.now()
        ));
    }

    /**
     * @description Maps the Severity enum to the Exception_Log__c severity label.
     * @param s the severity
     * @return the label ('Error', 'Warning', or 'Info')
     */
    private static String severityLabel(Severity s) {
        switch on s {
            when WARNING { return 'Warning'; }
            when INFO { return 'Info'; }
            when else { return 'Error'; }
        }
    }

    /**
     * @description Returns the current request id for correlation, or null if it cannot be read.
     * @return the request id
     */
    private static String currentRequestId() {
        try {
            return System.Request.getCurrent().getRequestId();
        } catch (Exception ignore) {
            return null;
        }
    }

    /**
     * @description Truncates a value so it fits the target event/log field.
     * @param value the value to truncate
     * @param maxLen the maximum length
     * @return the truncated value, or null if the input was null
     */
    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}