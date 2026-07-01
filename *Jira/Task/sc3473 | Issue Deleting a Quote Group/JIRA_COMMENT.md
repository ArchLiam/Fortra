*RCA complete (read-only research; no org changes made).*

**Root cause (HIGH confidence on locus, MEDIUM on exact key):** The "Cannot invoke Object.toString() because java.util.Map.get(Object) is null" toast is a **JVM JEP-358 NullPointerException thrown inside the native managed Revenue Cloud (RLM) save/reprice engine — NOT custom Apex.** Apex NPEs read "Attempt to de-reference a null object" and never name java.util.Map; we retrieved all custom hooks/triggers/flows live and confirmed none can throw it (all hooks swallow to SUCCESS; no custom Apex/Flow runs on the group delete at all; the error is not logged to Apex and the reporter has zero ApexLogs).

**Mechanism (verified):** Delete Group calls the native Place Quote / Place Sales Transaction API (method:DELETE action:DeleteGroup, pricingPref:Force). It commits the quote header, cascade-deletes the two grouped lines, then force-reprices the surviving lines. During context-hydration/pricing-calc the engine does an un-null-guarded map.get(key).toString() and the key is missing, so it throws. The header is committed but the later step is not rolled back, so the group stays undeleted and you see "Your quote was not updated." We live-confirmed the quote's CalculationStatus=SaveFailedOrIncomplete — the engine's designed status fired, but the raw JVM exception leaked to the toast instead of the intended "Some Records Weren't Saved."

**What we ruled out (read-only):** No missing PricebookEntry/PSMO/attribute key for this quote's lines; no static context-mapping gap on the active context (SalesTransactionContextExt_v2 V23) reachable for the surviving lines; the opportunity-sync null, the null-group-id collision, the hardware-group-over-software, and the selling-model-mix theories were each refuted by org-wide counter-examples.

**Determination:** This is **primarily a Salesforce platform/managed-package defect** (raw NPE leaked instead of an actionable message). The actionable in-org trigger is most credibly a **config/data edge in the pricing context definition** on this hardware/configured-mixed group.

**Recommended:**
1. **Open a Salesforce case** for the unguarded native NPE (attach repro quote 0Q0WC000002U2020AC, group 1C9WC00000097of0AA, and the CalculationStatus=SaveFailedOrIncomplete datum).
2. **Live repro with FINEST/RLM debug logging** (requires authorization — this is DML) to capture the exact native frame and null key. This is the only way to fully settle which key is missing.
3. **Config remediation to try:** re-sync/re-publish SalesTransactionContextExt_v2 V23 + re-verify its bindings to both the Sales Transaction and Product Discovery procedures, Generate All Mappings, sync V16 decision tables — the exact fix that cleared two prior in-org analogs.

**Do not** attempt a custom-Apex fix — custom code is conclusively not the cause and cannot prevent this native NPE.