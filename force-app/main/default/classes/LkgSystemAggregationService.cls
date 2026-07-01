public with sharing class LkgSystemAggregationService {
  public class SystemResult {
    public Map<String, Integer> quantities = new Map<String, Integer>();

    public Map<String, Set<Integer>> actions = new Map<String, Set<Integer>>();

    public String systemProductsCsv;

    public List<String> warnings = new List<String>();
  }

  public static SystemResult aggregateSystem(Id hardwareId, String productMetadataRecordId, Id primaryAssetId) {
    SystemResult result = new SystemResult();

    List<Asset> assets = [
      SELECT Id, Name, Product2.ProductCode, Quantity, Hardware__c, Legacy_Id__c
      FROM Asset
      WHERE Hardware__c = :hardwareId
    ];

    List<LKG_Intersect__mdt> intersects = [
      SELECT Match_Description__c, LKG_Product_Match__c, LKG_SKU_Type__c, Actions__c, Quantities__c
      FROM LKG_Intersect__mdt
      WHERE LKG_Product_Match__c = :productMetadataRecordId
    ];

    Map<String, LKG_Intersect__mdt> intersectByMatch = new Map<String, LKG_Intersect__mdt>();

    for (LKG_Intersect__mdt i : intersects) {
      if (i.Match_Description__c != null) {
        intersectByMatch.put(i.Match_Description__c, i);
      }
    }

    Set<String> systemProducts = new Set<String>();

    for (Asset a : assets) {
      String key = a.Product2.ProductCode + ' | ' + a.Name;

      LKG_Intersect__mdt match = intersectByMatch.get(key);

      if (match == null)
        continue;

      if (
        match.LKG_SKU_Type__c != null &&
        match.LKG_SKU_Type__c.trim().toLowerCase() == 'primary' &&
        a.Id != primaryAssetId
      ) {
        result.warnings.add('Extra primary: ' + a.Name);
      }

      Integer assetQty = (a.Quantity != null) ? Integer.valueOf(a.Quantity) : 1;

      // Quantities
      Map<String, Object> qtyJson = parseJson(match.Quantities__c);

      for (String k : qtyJson.keySet()) {
        // try {
        //     Integer base =
        //         Integer.valueOf(String.valueOf(qtyJson.get(k)));

        //     Integer total = base * assetQty;

        //     if (!result.quantities.containsKey(k)) {
        //         result.quantities.put(k, 0);
        //     }

        //     result.quantities.put(k,
        //         result.quantities.get(k) + total);

        // } catch (Exception e) {}
      }

      // Actions (union)
      Map<String, Object> actionJson = parseJson(match.Actions__c);

      for (String k : actionJson.keySet()) {
        // if (!result.actions.containsKey(k)) {
        //   result.actions.put(k, new Set<Integer>());
        // }

        // List<Object> values;

        // try {
        //   values = (List<Object>) actionJson.get(k);
        // } catch (Exception e) {
        //   values = null;
        // }

        // if (values != null) {
        //   for (Object o : values) {
        //     try {
        //       result.actions.get(k).add(Integer.valueOf(String.valueOf(o)));
        //     } catch (Exception e) {
        //     }
        //   }
        // }
      }

      if (a.Legacy_Id__c != null) {
        //systemProducts.add(a.Legacy_Id__c);
      }
    }

    result.systemProductsCsv = String.join(new List<String>(systemProducts), ',');

    return result;
  }

  private static Map<String, Object> parseJson(Object rawVal) {
    if (rawVal == null)
      return new Map<String, Object>();

    // try {
    //   String json = String.valueOf(rawVal);
    //   if (String.isBlank(json))
    //     return new Map<String, Object>();

    //   Object parsed = System.JSON.deserializeUntyped(json);

    //   if (parsed instanceof Map<String, Object>) {
    //     return (Map<String, Object>) parsed;
    //   }
    // } catch (Exception e) {
    // }

    return new Map<String, Object>();
  }
}