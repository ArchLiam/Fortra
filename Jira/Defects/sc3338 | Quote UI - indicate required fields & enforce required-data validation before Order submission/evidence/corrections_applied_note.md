# Synthesis: corrections applied note

All six verifier corrections were incorporated and no refuted claim is repeated:

1. Quote VRs — README §3 nowhere lists the old 5-set; §4/§5/§7c/§11(D2) use the live 4-set (Enforce_Amendment_Sales_Restriction, Sales_Cannot_Create_Downsell, Quote_BillToContactAcct_Equal_QuoteAcct, Quote_BillToPlacceAcct_Equal_QuoteAcct), independently re-queried live. The 3 force-app-only VRs are explicitly flagged as stale-source-only.
2. Order VRs — §5 and §11(D1) state 7 active live Order VRs (currency-lock + 6 account-equality) and note force-app has none; explicitly says none enforces required-field presence so it doesn't imply zero enforcement.
3. Account fill-rate 67%/56% — DROPPED as a headline number; §3 restates Account sparsity qualitatively and footnotes the 67%/56% as a single-snapshot artifact refuted by the larger 63-account sample (DUNS 89%/Type 90%/Phone 78%). Order/OrderItem ~90-100% auto-fill retained (re-confirmed numbers).
4. ProductCode FieldDefinition caveat — §3 adds the caveat that OrderItem.ProductCode returns 1 FieldDefinition row but is absent from the SObject describe().fields the runtime reads via SObject.get(), so the inactive rule is inert.
5. OrderValidationTrigger path — §5 and Evidence F cite ./conv_retrieve2/unpackaged/triggers/OrderValidationTrigger.trigger and ./Org Data/_src/triggers/, NOT Data/sc3338/retrieve/conv_retrieve2/...; verified content = before insert only.
6. Order_Before_Insert_Update_Sync_Status — Evidence C lists it as RecordBeforeSave (no insert-only claim); the FlowDefinitionView TriggerType column does not expose the Create/Update sub-type, so the README does not assert insert-only. The 'no presence validation' conclusion stands.

Additionally recorded for durability: active flow versions v13/v27/v3/v11 (re-queried live) in §11. Verifier nuance on Claim 5 (FieldDefinition vs describe) handled in §3.

Doc-level fixes still needed (outside this README synthesis, for the workflow owner):
- GROUND_TRUTH.md line 49 should be edited to the live 4-VR Quote set, and line 50 annotated '7 active Order VRs live'. (README §11 documents the drift but the source GT file itself was not edited in this read-only task.)
- The companion docs 10_–14_ are referenced by the README but were not present on disk at synthesis time (the sc3338 Jira-task 'evidence' dir was empty); their content is summarized inline from the provided research and should be written out under the sc3338 task folder to make the citations resolvable.