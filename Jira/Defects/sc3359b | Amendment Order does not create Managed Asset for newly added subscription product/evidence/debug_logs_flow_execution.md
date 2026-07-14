# Debug-log excerpts — assetize flow (Fortra_Assetize_Order V20), FortraUAT 2026-07-14

## Order 00095719 — Draft -> Activated (log 07LWC00000QL2362AD): guard=false -> assetized
```
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Check_Order_Already_Assetized|Apex|OrderAssetizationGuard|true|
FLOW_VALUE_ASSIGNMENT|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Check_Order_Already_Assetized|{alreadyAssetized=false}
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Check_Order_Already_Assetized|Apex|OrderAssetizationGuard|true|
FLOW_RULE_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Is_Order_Already_Assetized_True|false|false
FLOW_VALUE_ASSIGNMENT|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Is_Order_Already_Assetized_True|false
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Finalize_Order_Commercial_Net|Apex|AssetRateOverrideConsolidationService|true|
FLOW_VALUE_ASSIGNMENT|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Finalize_Order_Commercial_Net|true
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|Finalize_Order_Commercial_Net|Apex|AssetRateOverrideConsolidationService|true|
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|CreateOrUpdateRelatedAsset|Create or Update Asset from Order|createOrUpdateAssetFromOrder|true|
FLOW_VALUE_ASSIGNMENT|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|CreateOrUpdateRelatedAsset|{requestId=837308cc-c1ea-4a20-b38b-601ece98c075, statusUrl=/services/data/v67.0/sobjects/AsyncOperationTracker/16PWC0000069HSn}
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|CreateOrUpdateRelatedAsset|Create or Update Asset from Order|createOrUpdateAssetFromOrder|true|
FLOW_ACTIONCALL_DETAIL|64779bfc5ef232aefb3763dbac4719f61f785f2-5f7a|PopulateAssetLegacyFields|Apex|PopulateAssetLegacyFieldsAction|true|
```

## Order 00095719 — Provisioned -> Order Complete re-fire (log 07LWC00000QKw2d2AD): guard=true -> skip
```
FLOW_VALUE_ASSIGNMENT|433214cf52b219dd7fc71815812719f623ccf30-2e79|Check_Order_Already_Assetized|{alreadyAssetized=true}
FLOW_RULE_DETAIL|433214cf52b219dd7fc71815812719f623ccf30-2e79|Is_Order_Already_Assetized_True|true|false
FLOW_VALUE_ASSIGNMENT|433214cf52b219dd7fc71815812719f623ccf30-2e79|Is_Order_Already_Assetized_True|true
(Finalize / createOrUpdateAssetFromOrder never reached — guard short-circuited)
```

## Order 00095683 — Draft -> Activated (log 07LWC00000QKwNU2A1): Finalize FAULT (pre-existing bug)
```
FLOW_ELEMENT_BEGIN|1587291081dc213526566d5177c019f6200360-5815|FlowActionCall|Finalize_Order_Commercial_Net
FLOW_ELEMENT_DEFERRED|FlowActionCall|Finalize_Order_Commercial_Net
FLOW_ELEMENT_END|1587291081dc213526566d5177c019f6200360-5815|FlowActionCall|Finalize_Order_Commercial_Net
FLOW_BULK_ELEMENT_BEGIN|FlowActionCall|Finalize_Order_Commercial_Net
EXCEPTION_THROWN|[75]|System.DmlException: Update failed. First exception on row 0 with id 802WC00000PpDfxYAF; first error: INVALID_FIELD_FOR_INSERT_UPDATE, You can't edit the Unit Price because the Order Product has related Order Product Detail records. : [UnitPrice]
FATAL_ERROR|System.DmlException: Update failed. First exception on row 0 with id 802WC00000PpDfxYAF; first error: INVALID_FIELD_FOR_INSERT_UPDATE, You can't edit the Unit Price because the Order Product has related Order Product Detail records. : [UnitPrice]
```
