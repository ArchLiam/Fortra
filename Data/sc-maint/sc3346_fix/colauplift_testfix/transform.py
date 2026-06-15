#!/usr/bin/env python3
"""SC-3346 TEST-SUITE re-seam transform.
Adds @TestVisible white-box seams to the live COLAUpliftPrehook (zero behavior change)
and removes the 3 reverted net-seed test scenarios from COLAUpliftTest.
Operates by verified line ranges (descending splice). Pure structural moves."""

BASE = "Data/sc-maint/sc3346_fix/colauplift_testfix/deploy/classes"
PRE = f"{BASE}/COLAUpliftPrehook.cls"
TST = f"{BASE}/COLAUpliftTest.cls"

# ---------------- PREHOOK ----------------
with open(PRE) as f:
    L = f.read().split("\n")            # L[i] == file line i+1
orig = list(L)

def lines(a, b):                         # inclusive 1-indexed -> list slice
    return orig[a-1:b]

# Extracted buildLineItemUpdates body = pristine loop 260..374, drop processedCount++, de-indent 4
loop = lines(260, 374)
body = []
for ln in loop:
    if ln.strip() == "processedCount++;":
        continue
    body.append(ln[4:] if ln.startswith("    ") else ln)
bilu_body = "\n".join(body)

# New seam methods inserted AFTER processLineItems(String) close (line 395)
SEAMS = """
    /**
     * @description Pure renewal-COLA seam: builds the per-line context update list
     *              (tier resolution, explainer, buildItemUpdate) from already-resolved
     *              maps. Extracted verbatim from processLineItems(String) so the live
     *              path and the unit-test seam can never diverge.
     */
    @TestVisible
    private List<Map<String, Object>> buildLineItemUpdates(
        Map<Id, QuoteLineItem> renewalQlis,
        Map<Id, Map<String, Object>> qliIdToWrapper,
        Map<String, COLA_Uplift_Rules__mdt> colaRulesMap,
        Map<Id, ContractOverride> contractOverrides,
        MyCAP_Rules__mdt mycapRule
    ) {
%s
        return itemUpdates;
    }

    /**
     * @description Parsed-payload overload of processLineItems: takes already-fetched
     *              SalesTransactionItem wrappers instead of a context id, resolves the
     *              renewal QLIs + contract overrides, and returns the COLA line updates.
     *              Unit-testable seam mirroring the live String path.
     */
    @TestVisible
    private List<Map<String, Object>> processLineItems(
        List<Object> rawLineItems,
        Map<String, COLA_Uplift_Rules__mdt> colaRulesMap,
        MyCAP_Rules__mdt mycapRule
    ) {
        Set<Id> qliIds = new Set<Id>();
        Map<Id, Map<String, Object>> qliIdToWrapper = new Map<Id, Map<String, Object>>();
        if (rawLineItems != null) {
            for (Object rawItem : rawLineItems) {
                if (!(rawItem instanceof Map<String, Object>)) continue;
                Map<String, Object> itemWrapper = (Map<String, Object>) rawItem;
                Object dpObj = itemWrapper.get('dataPath');
                if (dpObj instanceof List<Object>) {
                    List<Object> dp = (List<Object>) dpObj;
                    if (!dp.isEmpty()) {
                        try {
                            Id qliId = Id.valueOf(String.valueOf(dp.get(dp.size() - 1)));
                            qliIds.add(qliId);
                            qliIdToWrapper.put(qliId, itemWrapper);
                        } catch (Exception e) {
                            // Not a valid Id, skip
                        }
                    }
                }
            }
        }

        Map<Id, QuoteLineItem> renewalQlis = new Map<Id, QuoteLineItem>();
        if (!qliIds.isEmpty()) {
            for (QuoteLineItem qli : [
                SELECT Id, QuoteActionId, QuoteAction.Type, QuoteAction.SourceAssetId,
                       QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Product2Id,
                       QuoteAction.SourceAsset.Product2.Solution_Category__c,
                       Default_COLA_Uplift_Percent__c
                FROM QuoteLineItem
                WHERE Id IN :qliIds
                AND QuoteAction.Type = 'Renew'
            ]) {
                renewalQlis.put(qli.Id, qli);
            }
        }

        Set<Id> assetIds = new Set<Id>();
        for (QuoteLineItem rqli : renewalQlis.values()) {
            if (rqli.QuoteAction?.SourceAssetId != null) {
                assetIds.add(rqli.QuoteAction.SourceAssetId);
            }
        }

        Map<Id, ContractOverride> contractOverrides = getContractOverrides(assetIds);
        return buildLineItemUpdates(renewalQlis, qliIdToWrapper, colaRulesMap, contractOverrides, mycapRule);
    }

    /**
     * @description Parsed-payload overload of isOrderTransaction: inspects dataPath[0]
     *              of the first item (Order roots start with 801). Pure + test-visible.
     */
    @TestVisible
    private Boolean isOrderTransaction(List<Object> items) {
        if (items == null || items.isEmpty()) return false;
        Object first = items.get(0);
        if (!(first instanceof Map<String, Object>)) return false;
        Map<String, Object> firstItem = (Map<String, Object>) first;
        Object dpObj = firstItem.get('dataPath');
        if (!(dpObj instanceof List<Object>)) return false;
        List<Object> dp = (List<Object>) dpObj;
        if (dp.isEmpty()) return false;
        String rootId = String.valueOf(dp.get(0));
        return rootId != null && rootId.startsWith('801');
    }
""" % bilu_body

# getContractOverrides (delegating) + buildOverrideMap seam  (replaces decl..close 712..768)
GCO = """    private Map<Id, ContractOverride> getContractOverrides(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new Map<Id, ContractOverride>();
        }

        List<SObject> relationships;
        try {
            String query = 'SELECT Id, AssetId, ContractId, ' +
                           'Contract.COLA_Override_Percent__c, ' +
                           'Contract.COLA_Override_Persist_Until__c, ' +
                           'Contract.Status ' +
                           'FROM AssetContractRelationship ' +
                           'WHERE AssetId IN :assetIds ' +
                           'AND Contract.Status = \\'Activated\\'';
            relationships = Database.query(query);
        } catch (System.QueryException e) {
            System.debug('AssetContractRelationship not available: ' + e.getMessage());
            return new Map<Id, ContractOverride>();
        }

        return buildOverrideMap(relationships);
    }

    /**
     * @description Validity-matrix seam for getContractOverrides. Builds the
     *              ContractOverride map from already-queried AssetContractRelationship
     *              rows so the logic (null-persist, future, expired, null-percent) is
     *              unit-testable via in-memory rows on orgs where ACR is uninsertable.
     */
    @TestVisible
    private Map<Id, ContractOverride> buildOverrideMap(List<SObject> relationships) {
        Map<Id, ContractOverride> overrideMap = new Map<Id, ContractOverride>();
        if (relationships == null || relationships.isEmpty()) {
            return overrideMap;
        }

        Date today = Date.today();

        for (SObject acr : relationships) {
            SObject relatedContract = acr.getSObject('Contract');

            if (relatedContract == null || relatedContract.get('COLA_Override_Percent__c') == null) {
                continue;
            }

            Boolean isValid = false;
            Date persistUntil = (Date)relatedContract.get('COLA_Override_Persist_Until__c');

            if (persistUntil == null) {
                isValid = true;
            } else if (persistUntil >= today) {
                isValid = true;
            }

            if (isValid) {
                ContractOverride colaOverride = new ContractOverride();
                colaOverride.contractId = (Id)acr.get('ContractId');
                colaOverride.overridePercent = (Decimal)relatedContract.get('COLA_Override_Percent__c');
                colaOverride.persistUntil = persistUntil;
                colaOverride.isValid = true;

                Id assetId = (Id)acr.get('AssetId');
                if (!overrideMap.containsKey(assetId)) {
                    overrideMap.put(assetId, colaOverride);
                }
            }
        }

        return overrideMap;
    }"""

MYCAP_HEAD = """    private Integer processMyCAPEligibility(String ctxInstanceId, MyCAP_Rules__mdt rule) {
        try {
            Context.IndustriesContext ctx = new Context.IndustriesContext();
            List<Object> rawLineItems = fetchSalesTransactionItems(ctx, ctxInstanceId);
            return processMyCAPEligibility(rawLineItems, rule);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MyCAP processing error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            return 0;
        }
    }

    @TestVisible
    private Integer processMyCAPEligibility(List<Object> rawLineItems, MyCAP_Rules__mdt rule) {
        Decimal defaultUplift = rule.Default_Out_Year_Uplift_Percent__c != null
            ? rule.Default_Out_Year_Uplift_Percent__c : 3;
        Decimal minimumUplift = rule.Minimum_Out_Year_Uplift_Percent__c != null
            ? rule.Minimum_Out_Year_Uplift_Percent__c : 3;

        try {
            if (rawLineItems == null || rawLineItems.isEmpty()) {
                return 0;
            }"""

PROCLI_REPLACE = """            // Build updates for line items (extracted to the testable buildLineItemUpdates seam)
            List<Map<String, Object>> itemUpdates = buildLineItemUpdates(
                renewalQlis, qliIdToWrapper, colaRulesMap, contractOverrides, mycapRule);
            processedCount += itemUpdates.size();"""

# splice ops: (start, end_inclusive, replacement_text_or_None_for_insert_after)
# applied descending by start so earlier line numbers stay valid
ops = [
    ("rep", 864, 875, MYCAP_HEAD),
    ("ins", 792, None, "    @TestVisible"),          # before getBooleanFromTag (793)
    ("ins", 777, None, "    @TestVisible"),          # before getDecimalFromTag (778)
    ("ins", 772, None, "    @TestVisible"),          # before getStringFromTag (773)
    ("rep", 712, 768, GCO),                          # getContractOverrides + buildOverrideMap
    ("ins", 653, None, "    @TestVisible"),          # before extractLineItemData (654)
    ("ins", 395, None, SEAMS),                       # seams after processLineItems(String) close
    ("rep", 259, 374, PROCLI_REPLACE),               # replace loop with seam call
]
ops.sort(key=lambda o: o[1], reverse=True)

work = list(L)
for kind, a, b, txt in ops:
    if kind == "rep":
        work[a-1:b] = txt.split("\n")
    else:  # insert AFTER line a
        work[a:a] = txt.split("\n")

with open(PRE, "w") as f:
    f.write("\n".join(work))

# ---------------- TEST ----------------
with open(TST) as f:
    T = f.read().split("\n")
# remove the 3 net-seed @isTest methods: lines 2536..2638 inclusive
del T[2535:2638]
with open(TST, "w") as f:
    f.write("\n".join(T))

# ---------------- VERIFY ----------------
def brace_balance(path):
    s = open(path).read()
    return s.count("{") - s.count("}")

print("PREHOOK brace balance:", brace_balance(PRE))
print("TEST    brace balance:", brace_balance(TST))
pp = open(PRE).read()
for m in ["private List<Map<String, Object>> buildLineItemUpdates(",
          "private List<Map<String, Object>> processLineItems(\n        List<Object>",
          "private Boolean isOrderTransaction(List<Object> items)",
          "private Map<Id, ContractOverride> buildOverrideMap(List<SObject>",
          "private Integer processMyCAPEligibility(List<Object>",
          "return buildLineItemUpdates(renewalQlis, qliIdToWrapper, colaRulesMap, contractOverrides, mycapRule)"]:
    print(("OK  " if m.replace("\n","") in pp.replace("\n","") else "MISS"), "prehook:", m[:55])
print("prehook @TestVisible count:", pp.count("@TestVisible"))
tt = open(TST).read()
print("test leftover net-seed refs (want 0):",
      tt.count("buildNetUnitPriceUpdate") + tt.count("pendingNetUnitPriceUpdates"))
print("test attrMapFromUpdate present (want >0):", tt.count("attrMapFromUpdate"))
print("prehook lines:", len(work), " test lines:", len(T))
