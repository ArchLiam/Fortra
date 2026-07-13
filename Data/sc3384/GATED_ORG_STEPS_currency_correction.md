# SC-3384 ABA Currency Correction — GATED ORG STEPS (apply-ready)

These two artifacts live only in the org (managed RLM), not in `force-app`. They are **gated** — apply
them in FortraUAT as part of the coordinated release, AFTER the Apex/field deploy, BEFORE validating a
real reprice. Nothing here has been applied.

The Apex fix keys entirely off one new line field, **`ABA_Raw_Net__c`** (Number 18,2), which the pricing
procedure must stamp with the raw per-unit USD net the ABA step produced (non-null ⇒ ABA-priced). Without
these two steps the field is always null → the posthook is a safe no-op (no localization happens, but no
regression either).

---

## STEP A — Pricing procedure: snapshot the ABA raw net (self-conditioning)

**Where:** `Rev_Mgmt_Default_Pricing_Procedure` (live Active v23). Edit on the **Pricing Procedure CANVAS**,
then deactivate → deploy → reactivate (per repo memory `pricing_proc_v21_inplace` / `pricing_procedure_deploy_mechanics`).

**What:** immediately AFTER each of the two ABA steps, add a Calculation/Assignment element that writes the
ABA lookup's matched adjustment value into the new context attribute `ABA_Raw_Net__c`:

- After **`AttributeBasedPrice`** (ListContainer35, `IsContractEnabled=true`) — live proc ~line 789.
- After **`AttributeDiscountEntries`** (ListContainer38, `IsContractEnabled=false`) — live proc ~line 959.

Assignment (both):

```
ABA_Raw_Net__c  :=  Constant_AdjustmentValue_Attribute_Based_Adjustment_Decision_Table_ABP
```

**Why this is self-conditioning (no explicit "did ABA match?" gate needed):** the ABA step exposes the
matched Override into that constant. On a match it holds the raw per-unit USD Override value (100% of the
13,073 ABA rows are `AdjustmentType='Override'`, so it is always the absolute per-unit price). On NO match
the constant is null, so `ABA_Raw_Net__c` stays null and the posthook treats the line as non-ABA. This is
why a list/partner/C-tier line is never mis-flagged.

**The one thing to confirm on the canvas:** that `Constant_AdjustmentValue_..._ABP` is referenceable by a
following element (it is the `AdjustmentValueField` the ABA step already reads/writes). If the canvas will
not let a downstream element read it, the equivalent fallback is: assign `ABA_Raw_Net__c := NetUnitPrice`
**guarded by** a condition that the ABA adjustment was applied (e.g. AdjustmentType constant == 'Override').
Do NOT stamp `NetUnitPrice` unconditionally — that would flag list-priced lines and cause double-conversion.

**Rollback:** delete the two assignment elements; reactivate the prior version. `ABA_Raw_Net__c` goes null
everywhere → posthook no-ops → pre-fix behavior restored.

---

## STEP B — Context definition: expose `ABA_Raw_Net__c` on the line node

**Where (org / managed):** `SalesTransactionContextExt_v2.contextDefinition`. Not in `force-app`; edit in
org (or deploy an edited retrieval). Working copy for reference:
`Data/pricing-refactor-scratch/ctxdef/unpackaged/contextDefinitions/SalesTransactionContextExt_v2.contextDefinition`.

Add **three** blocks, each mirroring the existing `Pre_Partner_Price__c` entries verbatim (with the field
name and `number` dataType). Line numbers are from the working-copy retrieval.

**B1 — schema attribute** (SalesTransactionItem contextNode, ~line 24455). `inputoutput` is what makes it
procedure-writable + posthook-readable + save-mappable:

```xml
<contextAttributes>
    <contextTags>
        <title>ABA_Raw_Net__c</title>
    </contextTags>
    <customMappingAllowed>false</customMappingAllowed>
    <dataType>number</dataType>
    <fieldType>inputoutput</fieldType>
    <key>false</key>
    <title>ABA_Raw_Net__c</title>
    <transient>false</transient>
    <value>false</value>
</contextAttributes>
```

**B2 — QuoteLineItem hydration/persistence mapping** (contextNodeMappings for `QuoteLineItem`, ~line 6936):

```xml
<contextAttributeMappings>
    <contextAttrHydrationDetails>
        <objectName>QuoteLineItem</objectName>
        <queryAttribute>ABA_Raw_Net__c</queryAttribute>
    </contextAttrHydrationDetails>
    <contextAttribute>ABA_Raw_Net__c</contextAttribute>
    <contextInputAttributeName>ABA_Raw_Net__c</contextInputAttributeName>
</contextAttributeMappings>
```

**B3 — OrderItem hydration/persistence mapping** (contextNodeMappings for `OrderItem`, ~line 12422):

```xml
<contextAttributeMappings>
    <contextAttrHydrationDetails>
        <objectName>OrderItem</objectName>
        <queryAttribute>ABA_Raw_Net__c</queryAttribute>
    </contextAttrHydrationDetails>
    <contextAttribute>ABA_Raw_Net__c</contextAttribute>
    <contextInputAttributeName>ABA_Raw_Net__c</contextInputAttributeName>
</contextAttributeMappings>
```

After editing, re-sync/refresh the context definition so the procedure and posthook see the new attribute.

**Rollback:** remove the three blocks. (Harmless to leave: an unused inputoutput attribute.)

---

## Release order (whole change)

1. Deploy field `ABA_Raw_Net__c` (QuoteLineItem + OrderItem) + the Apex (service, posthook, mapper,
   decomposition SELECTs) + tests. **← the in-repo, deployable half.**
2. STEP B — add `ABA_Raw_Net__c` to the context definition (3 blocks); re-sync.
3. STEP A — add the two provenance-stamp assignments to the procedure; deactivate → deploy → reactivate.
4. Validate a real EUR reprice (AAMP → Net/Subtotal/Total/UnitPrice = 1471.995; ListPrice stays 2943.99);
   USD line 0-delta; re-reprice twice = stable; convert → order-reprice = stable.

**Ordering matters:** until STEP A stamps the field, the posthook no-ops (safe). Deploying the Apext half
first (step 1) is non-breaking on its own. The correction only activates once A+B are in place.
