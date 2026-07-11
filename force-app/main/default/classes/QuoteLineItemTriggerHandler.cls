/**
 * @description Routes QuoteLineItem trigger events to the appropriate services in a single,
 *              ordered pipeline: currency correction, exchange-rate stamping, hardware linking,
 *              renewal born-net stamping, COLA uplift, renewal auto-add, and Opportunity rate
 *              propagation. Enforces a re-entrancy guard and publishes failure telemetry.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class QuoteLineItemTriggerHandler {

    private static final String SOURCE_PREFIX = 'QuoteLineItemTriggerHandler';
    private static final Integer MAX_DEPTH = 10;
    private static final Integer TEXT_MAX_LONG = 32768;
    private static final Integer TXN_MAX = 40;
    private static final Integer CONTEXT_MAX = 18;

    private static Integer runDepth = 0;

    /**
     * @description Before-insert pipeline: correct PBE currency (before native validation),
     *              stamp the USD exchange rate, link hardware from the group, stamp born-net
     *              renewal QuoteActions (must precede COLA), then apply COLA uplift.
     * @param newLines The QuoteLineItem records being inserted.
     */
    public void beforeInsert(List<QuoteLineItem> newLines) {
        enterGuard();
        try {
            QuoteLineItemCurrencyCorrectionHandler.correctPricebookEntryCurrency(newLines);
            QuoteLineItemExchangeRateService.stampRatesOnLines(newLines);
            linkHardwareToGroups(newLines, null);
            RenewalQuoteActionStamp.synthesizeRenewQuoteActions(newLines);
            COLAUpliftHandler.handleBeforeInsert(newLines);
        } catch (Exception e) {
            throw publishAndWrap(SOURCE_PREFIX + '.beforeInsert', contextIdOf(newLines), e);
        } finally {
            exitGuard();
        }
    }

    /**
     * @description Before-update pipeline: stamp the USD exchange rate, re-link hardware on
     *              group changes, then apply COLA uplift for updates.
     * @param newLines The updated QuoteLineItem records.
     * @param oldMap The pre-update QuoteLineItem records keyed by Id.
     */
    public void beforeUpdate(List<QuoteLineItem> newLines, Map<Id, QuoteLineItem> oldMap) {
        enterGuard();
        try {
            QuoteLineItemExchangeRateService.stampRatesOnLines(newLines);
            linkHardwareToGroups(newLines, oldMap);
            COLAUpliftHandler.handleBeforeUpdate(newLines, oldMap);
        } catch (Exception e) {
            throw publishAndWrap(SOURCE_PREFIX + '.beforeUpdate', contextIdOf(newLines), e);
        } finally {
            exitGuard();
        }
    }

    /**
     * @description After-insert pipeline: propagate the exchange rate to the syncing Opportunity,
     *              then enqueue renewal-maintenance auto-add and asset-quantity normalization.
     *              enqueueIfNeeded is intentionally invoked only on insert (matching prior behavior).
     * @param newMap The inserted QuoteLineItem records keyed by Id.
     */
    public void afterInsert(Map<Id, QuoteLineItem> newMap) {
        enterGuard();
        try {
            List<QuoteLineItem> newLines = newMap.values();
            QuoteLineItemExchangeRateService.propagateRatesToOpportunities(newLines);
            RenewalMaintenanceAutoAddHandler.enqueueIfNeeded(newLines);
            RenewalAssetQuantityHandler.enqueueQuantityNormalization(newLines);
        } catch (Exception e) {
            throw publishAndWrap(SOURCE_PREFIX + '.afterInsert', contextIdOf(newMap.values()), e);
        } finally {
            exitGuard();
        }
    }

    /**
     * @description After-update pipeline: propagate the exchange rate to the syncing Opportunity.
     * @param newMap The updated QuoteLineItem records keyed by Id.
     * @param oldMap The pre-update QuoteLineItem records keyed by Id.
     */
    public void afterUpdate(Map<Id, QuoteLineItem> newMap, Map<Id, QuoteLineItem> oldMap) {
        enterGuard();
        try {
            QuoteLineItemExchangeRateService.propagateRatesToOpportunities(newMap.values());
        } catch (Exception e) {
            throw publishAndWrap(SOURCE_PREFIX + '.afterUpdate', contextIdOf(newMap.values()), e);
        } finally {
            exitGuard();
        }
    }

    /**
     * @description Sets Hardware__c on each line whose QuoteLineGroupId changed, reading the
     *              hardware from the group in a single query. Clears Hardware__c when a line
     *              leaves its group. Mutates newLines in place (no DML).
     * @param newLines The new/updated QuoteLineItem records.
     * @param oldMap The pre-update records keyed by Id, or null on insert.
     */
    private void linkHardwareToGroups(List<QuoteLineItem> newLines, Map<Id, QuoteLineItem> oldMap) {
        Set<Id> groupIds = new Set<Id>();
        List<QuoteLineItem> linesToUpdate = new List<QuoteLineItem>();

        for (QuoteLineItem newLine : newLines) {
            Boolean groupChanged = false;

            if (oldMap == null && newLine.QuoteLineGroupId != null) {
                groupChanged = true;
            } else if (oldMap != null) {
                QuoteLineItem oldLine = oldMap.get(newLine.Id);
                if (newLine.QuoteLineGroupId != oldLine.QuoteLineGroupId) {
                    groupChanged = true;
                }
            }

            if (groupChanged) {
                linesToUpdate.add(newLine);
                if (newLine.QuoteLineGroupId != null) {
                    groupIds.add(newLine.QuoteLineGroupId);
                }
            }
        }

        if (groupIds.isEmpty() && linesToUpdate.isEmpty()) {
            return;
        }

        Map<Id, Id> groupToHardwareMap = new Map<Id, Id>();
        if (!groupIds.isEmpty()) {
            List<QuoteLineGroup> groups = [
                SELECT Id, Hardware__c, Hardware_Group_Type__c
                FROM QuoteLineGroup
                WHERE Id IN :groupIds
            ];
            for (QuoteLineGroup grp : groups) {
                if (grp.Hardware__c != null) {
                    groupToHardwareMap.put(grp.Id, grp.Hardware__c);
                }
            }
        }

        for (QuoteLineItem line : linesToUpdate) {
            if (line.QuoteLineGroupId != null) {
                line.Hardware__c = groupToHardwareMap.get(line.QuoteLineGroupId);
            } else {
                line.Hardware__c = null;
            }
        }
    }

    /**
     * @description Increments the per-transaction re-entrancy counter, throwing when the trigger
     *              re-enters itself beyond the allowed depth (§2.4).
     */
    private void enterGuard() {
        if (runDepth >= MAX_DEPTH) {
            throw new QuoteLineItemTriggerException(
                'QuoteLineItem trigger recursion exceeded ' + MAX_DEPTH + ' levels'
            );
        }
        runDepth++;
    }

    /**
     * @description Decrements the per-transaction re-entrancy counter.
     */
    private void exitGuard() {
        if (runDepth > 0) {
            runDepth--;
        }
    }

    /**
     * @description Publishes best-effort failure telemetry through the central publisher (so the
     *              failure stays visible across a rollback) and returns a typed wrapper for the
     *              caller to throw, aborting the save (§9.6). Uses the deployed Pricing_Exception__e
     *              baseline because ExceptionLogger.log/Fortra_Exception__e are not yet in this org.
     * @param source The class-and-method origin of the failure.
     * @param contextId The Quote Id providing failure context, if available.
     * @param cause The underlying exception whose stack trace is recorded.
     * @return A typed QuoteLineItemTriggerException wrapping the cause.
     */
    private QuoteLineItemTriggerException publishAndWrap(String source, String contextId, Exception cause) {
        QuoteLineItemTriggerException wrapper =
            new QuoteLineItemTriggerException(source + ' failed: ' + cause.getMessage(), cause);
        String requestId;
        try {
            requestId = System.Request.getCurrent().getRequestId();
        } catch (Exception ignore) {
            requestId = null;
        }
        ExceptionLogger.safePublish(new Pricing_Exception__e(
            Source__c = source,
            Severity__c = 'Error',
            Exception_Type__c = wrapper.getTypeName(),
            Message__c = truncate(wrapper.getMessage(), TEXT_MAX_LONG),
            Stack_Trace__c = truncate(cause.getStackTraceString(), TEXT_MAX_LONG),
            Context_Id__c = truncate(contextId, CONTEXT_MAX),
            Transaction_Id__c = truncate(requestId, TXN_MAX),
            Occurred_At__c = System.now()
        ));
        return wrapper;
    }

    /**
     * @description Returns the first available Quote Id from the lines to use as failure context.
     * @param lines The QuoteLineItem records in the current event.
     * @return The first non-null QuoteId as a String, or null.
     */
    private String contextIdOf(List<QuoteLineItem> lines) {
        if (lines != null) {
            for (QuoteLineItem line : lines) {
                if (line.QuoteId != null) {
                    return line.QuoteId;
                }
            }
        }
        return null;
    }

    /**
     * @description Truncates a value to a maximum column length, tolerating null.
     * @param value The value to truncate.
     * @param maxLen The maximum allowed length.
     * @return The value, truncated to maxLen, or null.
     */
    private String truncate(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
