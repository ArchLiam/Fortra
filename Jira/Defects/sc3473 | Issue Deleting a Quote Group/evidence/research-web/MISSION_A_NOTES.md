# SC-3473 Mission A — Native Delete-Group mechanism + the Java NPE (web + platform reasoning)

## 1. What "Delete Group" does server-side (VERIFIED from RLM Dev Guide v67.0 Summer'26 PDF)
- QLE "Delete Group" sends an sObject GRAPH to the Place Quote / Place Sales Transaction ConnectApi.
  - Deprecated path (API<63): POST /commerce/quotes/actions/place  (RLM Dev Guide p.1414)
  - Current path (API>=63): POST /connect/rev/sales-transaction/actions/place  (p.1422)
- Delete-group graph payload (verbatim from guide, "sample request to delete a group", p.1419-1420):
    { "pricingPref":"Force", "configurationInput":"skip",
      "graph": { "records": [
        { "type":"Quote","method":"PATCH","id":"<quoteId>" },
        { "type":"QuoteLineGroup","method":"DELETE","id":"<GroupId>","action":"DeleteGroup" } ]}}
  - action:"DeleteGroup" => delete group AND its lines. (Contrast action:"Ungroup" => keep the lines, p.1419.)
- Cascade: QuoteLineGroup.QuoteId is MASTER-DETAIL to Quote; grouped QLIs carry QuoteLineGroupId.
  DeleteGroup removes the group + its child QLIs, then engine reprices surviving lines.
- pricingPref:"Force" => FORCE a full server-side reprice of surviving lines (vs System/Skip), p.1421.
- Place Sales Transaction CRITICAL note (p.1422): "This API saves and commits the quote header FIRST,
  then processes configuration, pricing, and persistence for components, such as line items and groups.
  If a later step fails, the header isn't rolled back."
  => Explains symptom: header "saved" but later reprice/persist step throws => net effect group NOT deleted,
     toast "Your quote was not updated."

## 2. The exact Java error & its class (VERIFIED via web)
- SC-3473 toast: Cannot invoke "Object.toString()" because the return value of "java.util.Map.get(Object)" is null
- NOT a documented Salesforce Known Issue by that exact string (searched help.salesforce.com, Trailblazer, dev forums).
- It is a Java JEP-358 "helpful NPE" => thrown by NATIVE Java-implemented managed engine, NOT custom Apex
  (Apex NPE reads "System.NullPointerException: Attempt to de-reference a null object", never "java.util.Map").
- DOCUMENTED SIBLING of the SAME class & engine (applikontech RLM troubleshooting guide):
  "Something went wrong while hydrating additional context fields: Cannot invoke
   industries.context.api.service.model.runtime.schema.impl.defaultimpl.DefaultContextRuntimeEntityAttribute.getTags()
   because the return value of java.util.Map.get(Object) is null"
  => Throwing subsystem = Industries CONTEXT SERVICE runtime (industries.context.api.service...),
     during context HYDRATION for the pricing procedure. Same Map.get(key)==null pattern; SC-3473 just
     calls .toString() on a different missing-key value instead of .getTags().

## 3. Which native map is missing a key
- The context-runtime builds maps keyed per-line/per-entity from the Sales Transaction context definition
  + Context Definition Mappings. Pricing engine input includes "maps that contain product IDs and product
    selling model IDs" (Dev Guide, BulkProductDetailsInputBodyList.productData, p.527).
- Read/Place Sales Transaction "Records" output = "a map of keys and associated values. The keys are
  record type names, such as a Quote or QuoteLineItem" (Dev Guide p.1508) — Map<String,List<Record>>.
- Strong local corroboration: PsmoOrphanScanner.cls keys on Product2Id+'|'+ProductSellingModelId and
  finds PricebookEntry (Product,PSM) pairs with NO matching ProductSellingModelOption (PSMO).
  That composite key is exactly the kind a native pricing/context map is keyed on; a PBE/PSMO/context-mapping
  gap for a surviving line => map.get(key)==null => .toString() NPE during the forced reprice.

## 4. Platform bug vs config/data — DETERMINATION
- CONFIG/DATA condition the customer can fix (primary). The applikontech sibling's stated fixes are all config:
  accurate Context Definition Mappings; "Generate All Mappings"; ensure a DEFAULT mapping exists; link new
  context versions to BOTH Product Discovery & Sales Transaction procedures; SYNC decision tables; confirm
  attribute-based pricing output marking; permissions.
- ALSO a latent PLATFORM robustness gap: native engine surfaces a raw unhandled JEP-358 NPE instead of a
  user-actionable error => worth a Salesforce case for the unhelpful message, but the TRIGGER is fixable in-org.
- VERIFY in this org (next missions): does a surviving Suspicious Email Intelligence line's (Product2Id, PSM
  0jPWC000000060b2AA TermDefined-Annual) have a matching PSMO + PBE in the quote's pricebook + complete
  Context Definition Mappings for SalesTransactionContextExt_v2? Run PsmoOrphanScanner-style check read-only.
