/**
 * Pricing-hook facade over {@link ExceptionLogger} (D-18).
 *
 * Publishes a `Pricing_Exception__e` for a swallowed pricing-hook exception so the
 * degrade becomes durably visible (a subscriber Flow persists it to
 * `Exception_Log__c`, RecordType "Pricing Exception"). This is additive telemetry:
 * it is fire-and-forget, never throws, and never influences the hook's returned
 * TransactionStatus — the SDD-mandated swallow-to-SUCCESS behaviour is unchanged.
 *
 * Call ONE of these once, inside a hook's top-level catch block (never per line).
 * See docs/pricing-refactor/D18_TELEMETRY_DESIGN.md.
 */
public inherited sharing class PricingHookLogger {

    private static final Integer TEXT_MAX  = 255;
    private static final Integer LONG_MAX  = 32768;
    private static final Integer CTX_MAX   = 18;
    private static final Integer SOURCE_MAX = 80;
    private static final Integer TXN_MAX   = 40;

    /** Log a swallowed exception from a pricing PREhook. */
    public static void logPrehook(String hookName, String contextId, Exception e) {
        publish(hookName, 'Prehook', contextId, e);
    }

    /** Log a swallowed exception from a pricing POSThook. */
    public static void logPosthook(String hookName, String contextId, Exception e) {
        publish(hookName, 'Posthook', contextId, e);
    }

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

    private static String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
