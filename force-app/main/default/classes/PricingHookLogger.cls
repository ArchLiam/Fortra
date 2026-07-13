/**
 * @description Facade over ExceptionLogger that publishes a Pricing_Exception__e
 * platform event for a swallowed pricing-hook exception, making the degrade durably
 * visible through a subscriber Flow that persists it to Exception_Log__c. Additive,
 * fire-and-forget telemetry: it never throws and never influences the hook's returned
 * TransactionStatus. Call one of these once inside a hook's top-level catch block.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public inherited sharing class PricingHookLogger {

    private static final Integer TEXT_MAX  = 255;
    private static final Integer LONG_MAX  = 32768;
    private static final Integer CTX_MAX   = 18;
    private static final Integer SOURCE_MAX = 80;
    private static final Integer TXN_MAX   = 40;

    /**
     * @description Logs a swallowed exception raised from a pricing PREhook by
     * publishing a Pricing_Exception__e event tagged with the Prehook phase.
     * @param hookName Name of the prehook that swallowed the exception.
     * @param contextId Identifier of the pricing context being processed.
     * @param e The swallowed exception to record.
     */
    public static void logPrehook(String hookName, String contextId, Exception e) {
        publish(hookName, 'Prehook', contextId, e);
    }

    /**
     * @description Logs a swallowed exception raised from a pricing POSThook by
     * publishing a Pricing_Exception__e event tagged with the Posthook phase.
     * @param hookName Name of the posthook that swallowed the exception.
     * @param contextId Identifier of the pricing context being processed.
     * @param e The swallowed exception to record.
     */
    public static void logPosthook(String hookName, String contextId, Exception e) {
        publish(hookName, 'Posthook', contextId, e);
    }

    /**
     * @description Builds and safely publishes a Pricing_Exception__e event, capturing
     * the current request id and truncating each field to its column limit before handing
     * the event to ExceptionLogger.safePublish.
     * @param hookName Name of the hook that swallowed the exception.
     * @param phase Hook phase label, either Prehook or Posthook.
     * @param contextId Identifier of the pricing context being processed.
     * @param e The swallowed exception whose type, message and stack trace are recorded.
     */
    private static void publish(String hookName, String phase, String contextId, Exception e) {
        String requestId;
        try {
            requestId = System.Request.getCurrent().getRequestId();
        } catch (Exception ignore) {
            requestId = null;
        }
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c         = truncate(hookName, SOURCE_MAX),
            Hook_Phase__c     = phase,
            Severity__c       = 'Error',
            Context_Id__c     = truncate(contextId, CTX_MAX),
            Transaction_Id__c = truncate(requestId, TXN_MAX),
            Exception_Type__c = e != null ? truncate(e.getTypeName(), TEXT_MAX)          : null,
            Message__c        = e != null ? truncate(e.getMessage(), LONG_MAX)           : null,
            Stack_Trace__c    = e != null ? truncate(e.getStackTraceString(), LONG_MAX)  : null,
            Occurred_At__c    = System.now()
        ));
    }

    /**
     * @description Returns the value clipped to the given maximum length, passing null
     * through unchanged so field values never exceed their column limits.
     * @param value The string to clip; may be null.
     * @param maxLen Maximum number of characters to retain.
     * @return The original value when null or within the limit, otherwise its leading substring of maxLen characters.
     */
    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}