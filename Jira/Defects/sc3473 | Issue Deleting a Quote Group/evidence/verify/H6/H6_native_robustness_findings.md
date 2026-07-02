# H6-platform-robustness-gap — native-semantics lens verification (READ-ONLY)
Date 2026-06-28. Org FortraUAT. All read-only. Lens: would the native subsystem really
throw HERE / leak raw; is there a guarded message for the same condition?

## H6 restated
Latent platform robustness gap: the managed RLM engine leaks a raw unhandled JEP-358 NPE
instead of an actionable message whenever ANY pricing/context prerequisite key is absent;
the specific missing key is secondary. Co-exists with the in-org config/data trigger.

## Evidence FOR (native semantics confirm the message is an internal leak)
1. The toast string is a verbatim JVM JEP-358 "helpful NullPointerException" detail message
   (openjdk.org/jeps/358). It is computed lazily from bytecode and names a JDK call
   (java.util.Map.get / Object.toString). By design it is a DEVELOPER stack-trace artifact,
   never an application-authored end-user validation string. Surfacing it verbatim in a
   sales-rep toast = the engine did NOT translate the failure into a designed message.
2. Apex is ruled out as the throw site (Missions B/C/E consensus; rtel_javamap.json empty):
   Apex NPEs read "System.NullPointerException: Attempt to de-reference a null object" and
   never mention "java.util.Map". So the unguarded throw is definitively native.
3. The ONLY documented sibling of this exact error class in RLM (applikontech RLM
   troubleshooting guide, fetched 2026-06-28) is the getTags() variant during "hydrating
   additional context fields" — also a raw JEP-358 NPE leaked to the user with ONLY config
   workarounds offered, never a patched guarded message. Same engine, same leak pattern.
   => The native context-hydration path has NO null-guard for missing map keys; it relies on
      the JVM to throw and the toast to display the raw detail. That IS a robustness gap.

## Evidence that REFINES H6 (the engine is NOT uniformly unguarded — it guards MANY siblings)
The refute test = "the engine emits a guarded, user-actionable message for the same/related
condition." It is PARTIALLY satisfied — for NEIGHBORING conditions the platform guards well:
4. Salesforce Help 002188066: adding a product with a Discovery/Pricing context-definition
   MISMATCH yields a DESIGNED, actionable validation message — "Ensure that the discovery
   procedure and pricing procedure are associated with same context definition" — NOT a raw
   NPE. So a related context-prerequisite gap IS guarded.
5. RLM Dev Guide v67 (rlm_dev_guide.txt L123203-123249): the engine has a full enumerated,
   restricted-picklist CalculationStatus failure taxonomy that maps to sales-rep-facing
   wording: ConfigurationFailed, GroupRampConfigurationFailed, PriceCalculationFailed,
   ReconciliationFailed, SaveFailedOrIncomplete ("Some Records Weren't Saved"),
   OrderRequestFailed, TaxCalculationFailed. These are DESIGNED, guarded surfacings for
   ANTICIPATED failure modes.
=> So the engine does NOT "leak raw whenever ANY prerequisite is absent." It leaks raw only
   on the UN-anticipated code paths (missing context-map key during hydration / the .toString
   throw). The gap is SPECIFIC to the unguarded hydration/calc lookup, not cross-cutting-universal.

## DECISIVE live datum — the engine reached its designed status layer yet still leaked the NPE
6. Live query (verify/H6/quote_calcstatus.json): repro quote 0Q0WC000002U2020AC
   CalculationStatus = "SaveFailedOrIncomplete". Per Dev Guide L123243-123245 that is the
   DESIGNED status meaning "recent changes weren't saved … 'Some Records Weren't Saved'."
   => The engine successfully set a guarded, enumerated status (designed path WORKED), but the
      USER-FACING toast still received the raw JEP-358 java.util.Map NPE instead of the
      actionable "Some Records Weren't Saved." This is the robustness-gap signature precisely:
      the status taxonomy caught it; the message-surfacing path leaked the internal exception.
   => This is the strongest single confirmation that a message-quality robustness gap is REAL
      and ACTIVE on this exact transaction (not abstract).

## Product2Id confirmation (shared-context open question, live verify/H6/qli_product2.json)
- AJS 0QLWC000003jN6n4AE Product2Id 01tWC00000DD11cYAD (SM-AJS-NRPS-AJSP) PSM OneTime, net 29060 / list 2850
- Abstract 0QLWC000003jN8P4AU Product2Id 01tWC00000DD11GYAT (BI-ABS-RSS-ABSTSU; shared ctx
  guessed DD11E.. — ACTUAL is DD11G..) PSM TermDefined, net 4356 / list 46
- Both surviving Suspicious Email Intelligence lines Product2Id 01tWC00000DD1mNYAT
  (ES-ETM-RMS-SUSPIN) PSM TermDefined, net=list 20000 (SAME Product2 + SAME PSM on both).

## Verdict: REFINED (toward SURVIVES on message-quality, but corrected on universality)
- TRUE and now LIVE-CONFIRMED: a platform message-surfacing robustness gap exists — the
  managed engine set a guarded status (SaveFailedOrIncomplete) yet leaked the raw JVM NPE to
  the toast. So H6's core claim ("raw unhandled JEP-358 leaked instead of an actionable
  message") is positively supported on THIS transaction.
- CORRECTED: H6 overreaches in "whenever ANY prerequisite is absent / key is secondary." The
  engine demonstrably GUARDS many sibling prerequisite gaps (context-def mismatch validation;
  the whole CalculationStatus failure taxonomy). The leak is localized to the unguarded
  hydration/calc Map.get(...).toString() path, not a universal cross-cutting behavior.
- Confirm test (a Salesforce support case acknowledging the unguarded NPE): NOT found by that
  exact string (Mission A; re-searched 2026-06-28). The applikontech sibling is the closest
  public corroboration that the platform ships only config workarounds, no guarded message.
- As the shared context itself flags: H6 is a META-claim about message QUALITY. It does not
  and cannot identify the actionable missing key (which H1-H5 must), so it cannot be the
  "most probable answer to which key." It is a co-existing true defect, secondary for remediation.
- Only a live debug-logged repro (DML, out of scope) can name the exact stack frame and the
  exact missing key; the guarded-status-vs-raw-toast split is established here WITHOUT DML.
