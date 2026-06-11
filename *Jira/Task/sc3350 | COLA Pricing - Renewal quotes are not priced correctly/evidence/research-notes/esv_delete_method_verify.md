# Deleting a blocked ExpressionSetVersion (Pricing Procedure Version) — method research & adversarial verification

Context: ExpressionSet `Rev_Mgmt_Default_Pricing_Procedure` ("Revenue Management Default Pricing
Procedure"), 11 versions, V11 active. Deleting V2–V8 fails (UI/REST/Tooling/Bulk) with HTTP 500
UNKNOWN_EXCEPTION: *"Deleting this version changes the input and output variables in the expression set …
that's referenced in objects: Pricing Parameters: <id>,<id>"*. The two ids are **PricingActionParameters**
records (UI "Pricing Parameters", prefix 17g) binding the procedure to Context Definition
`SalesTransactionContext` via Context Mappings (OrderEntitiesMapping / QuoteEntitiesMapping).

---

## VERDICT on the proposed declarative method (remove/re-select default in Revenue Settings): PARTIAL

The "remove the default pricing procedure" UI step is real and official, but it is **not on-point** for the
exact blocker and does **not reliably clear the two PricingActionParameters records** the error names.

### What IS officially supported (evidence)
- **Deactivate-all-versions to change the linked Context Definition** — official. RLM Dev Guide v67.0:
  *"with expression sets, you must deactivate the version in the target org where you want to deploy changes.
  If you try to deploy to an active version, the deployment fails."*
  (`Data/sc3350-research/rlm_dev_guide.txt` L1172-1173). Official deactivation doc:
  https://help.salesforce.com/s/articleView?id=sf.deactivate_an_expression_set_version.htm&language=en_US&type=5
- **"Select a Pricing Procedure" lives under Setup > Salesforce Pricing > Salesforce Pricing Setup** — official
  deployment reference table (`rlm_dev_guide.txt` ~L3984+). The "remove the default pricing procedure" via
  the remove icon under *Set Up Salesforce Pricing* in Revenue Settings is documented (Clone and Select a
  Pricing Procedure: https://help.salesforce.com/s/articleView?id=sf.pricing_set_default_pricing_procedure.htm
  — `ind` variant is the URL the proposal cited).

### Why it does NOT fully work / is not on-point (the load-bearing gap)
- **PricingActionParameters are managed SEPARATELY from the default-procedure selector.** Independent
  practitioner guidance (Revenue Cloud Setup Guide v2, mirrored on Scribd) states verbatim in substance:
  *"check Setup > Pricing Action Parameters and ensure you have one for Quote and one for Order"* and
  *"update your Pricing Action Parameters if you ever change your SalesTransactionContext definition."*
  → They are first-class records with their own Setup node, NOT a side-effect of the default selector.
- **No official source states that removing the default pricing procedure deletes the two named
  PricingActionParameters.** The cited doc (`pricing_set_default_pricing_procedure`) is about *selecting/
  cloning* the default procedure; it never mentions ExpressionSetVersion deletion or PricingActionParameters
  removal. So the proposal's claim that "removing the default clears the procedure→context binding the
  PricingActionParameters represent" is **unverified and likely false** — the binding is the PAP records, and
  the default selector is a different pointer. Removing the default would unbind ALL pricing yet can leave the
  PAP records (and thus the delete block) intact.
- Conclusion: the declarative path may incidentally help only IF the org's remove action also deletes the PAP
  rows — undocumented and unproven. It is **conceptually safe but not demonstrated to unblock the delete**, and
  it has a large blast radius (all Order/Quote pricing off until re-selected). Treat as PARTIAL / not the
  recommended path.

---

## The on-point, OFFICIALLY-supported method: delete the PricingActionParameters first

PricingActionParameters is **both** a DML-able SObject **and** a deployable/deletable metadata type. This is
the standard "delete the dependency, then the dependent" pattern.

### Primary evidence
- **SObject (API v60+) supports `delete()` and `update()`** — `create(), delete(), describeSObjects(),
  query(), retrieve(), update(), upsert()` (`Data/sc3350-research/sforce_api_objects_pricingactionparameters.json`).
  Fields: `ContextDefinition`, `ContextMapping`, `PricingProcedure`, `ObjectName` (Order/Quote/…), `DeveloperName`,
  `EffectiveFrom/To`, `MasterLabel`.
- **Metadata type** suffix `.pricingActionParameters` (API v60+), fields `contextDefinition`, `contextMapping`,
  `pricingProcedure`, `objectName`, `developerName`, `masterLabel`, `effectiveFrom/To`
  (`Data/sc3350-research/rlm_dev_guide.txt` L61699-61828; mirrored in `Data/sc3350/api_meta.txt` L115500+).
- **Metadata API delete is supported**: `deleteMetadata()` maps to SOAP `delete()` (`api_meta.txt` L2556);
  `destructiveChanges.xml` deletes named components, and **`destructiveChangesPre.xml` deletes dependencies
  BEFORE additions** — the canonical pattern for "delete X is blocked until its referrer is removed"
  (`api_meta.txt` L4441-4484). `purgeOnDelete=true` bypasses Recycle Bin.

### Recommended step-by-step (supported)
1. **Snapshot** both PricingActionParameters records (query all fields) so they can be recreated exactly —
   `SELECT Id, DeveloperName, MasterLabel, ObjectName, PricingProcedure, ContextDefinition, ContextMapping,
   EffectiveFrom, EffectiveTo FROM PricingActionParameters`. (Order one + Quote one.)
2. **Deactivate** the target inactive versions V2–V8 (they are already inactive; confirm) — and per the
   change-context-definition rule, all versions must be inactive only if you intend to repoint the context;
   for pure deletion of inactive versions this isn't required, but the error is reference-driven, not
   active-version-driven.
3. **Delete the two PricingActionParameters** records (the referrers) — REST `DELETE
   /services/data/vXX.0/sobjects/PricingActionParameters/<id>`, or Apex `Database.delete`, or Metadata
   `destructiveChanges.xml`/`deleteMetadata()`. This removes the "input/output variables … referenced in
   objects: Pricing Parameters" link.
4. **Delete V2–V8** (now unreferenced) — UI or Tooling/Metadata delete of ExpressionSetVersion.
5. **Recreate the two PricingActionParameters** from the snapshot (same DeveloperName/MasterLabel/ObjectName/
   PricingProcedure/ContextDefinition/ContextMapping) via Setup > Pricing Action Parameters, or
   create()/createMetadata(). Re-confirm one for Order, one for Quote, both pointing at the live procedure +
   `SalesTransactionContext` extension + the right Context Mapping.
6. **Re-confirm V11 active** and run a test reprice on one Order and one Quote to confirm pricing restored.

This directly removes/handles the Pricing Parameters reference (step 3) AND restores Order/Quote pricing
(step 5-6), which the declarative-remove method does not demonstrably do.

---

## Risks / caveats
- **Highest risk:** between step 3 and step 5, **all Order/Quote pricing is unbound** — no live procedure runs
  for transactions. Do in a maintenance window; recreate PAP immediately. (The declarative-remove method has
  the *same* outage window, plus the unproven-delete problem.)
- **Recreate fidelity:** PAP records must be recreated with the exact ObjectName (ORDER/QUOTE), the same
  Context Mapping (OrderEntitiesMapping / QuoteEntitiesMapping), and the SalesTransactionContext **extension**
  (known-issue 002183049: *"The default pricing procedure must be associated with a context definition that's
  an extension of SalesTransactionContext__stdctx"*). Wrong mapping = pricing silently wrong/zero.
- **Cross-org Id instability:** if done via metadata between orgs, PAP DeveloperName is the natural key; raw
  Ids will differ.
- **Whether the delete succeeds after PAP removal is the one empirical unknown** — the error is explicitly a
  reference check on PricingActionParameters, so removing them is the directly-targeted fix, but Salesforce
  could surface a secondary reference (e.g., the active V11's own variables). Validate on one version first.
- **Do you even need to delete?** Deactivating versions (the custom "Context Definition Dependency Manager"
  already does this) satisfies most operational goals without the outage. Deletion is cosmetic/cleanup; weigh
  the pricing-outage risk against the benefit.

## Source URLs (exact)
- RLM Dev Guide v67.0 (PDF, primary): https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/api_rlm.pdf
  (local: `Data/sc3350-research/rlm_dev_guide.txt` — PricingActionParameters metadata L61699+, deactivate-to-deploy L1172)
- PricingActionParameters SObject: https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_pricingactionparameters.htm (supports create/delete/update/upsert; v60+)
- Metadata API deleteMetadata / destructiveChanges: https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_deleteMetadata.htm and https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/file_based.htm
- Deactivate an Expression Set Version: https://help.salesforce.com/s/articleView?id=sf.deactivate_an_expression_set_version.htm&language=en_US&type=5
- Configure Your Pricing Procedure: https://help.salesforce.com/s/articleView?id=sf.pricing_configure_your_pricing_procedure.htm&language=en_US&type=5
- Clone and Select a Pricing Procedure (proposal's cited doc): https://help.salesforce.com/s/articleView?id=sf.pricing_set_default_pricing_procedure.htm&language=en_US&type=5
- Pricing Action Parameters (help): https://help.salesforce.com/s/articleView?id=ind.pricing_pricing_action_parameters.htm&language=en_US&type=5
- Salesforce Pricing Basic Setup: https://help.salesforce.com/s/articleView?id=ind.pricing_set_up_salesforce_pricing.htm&language=en_US&type=5
- Known issue 002183049 (default proc must extend SalesTransactionContext): https://help.salesforce.com/s/articleView?id=002183049&language=en_US&type=1
- Revenue Cloud Setup Guide v2 (community, "one PAP for Quote and one for Order; update if you change SalesTransactionContext"): https://www.scribd.com/document/866168946/Revenue-Cloud-Setup-Guide-v2
