/**
 * @description Unit tests for COLAUpliftCalculator — the pure COLA logic extracted from
 *              COLAUpliftPrehook (Wave-2 hook-thinning). These exercise the calculator
 *              directly with in-memory inputs (no SOQL / DML / RCA-context), which the
 *              hook's execute() path could never be unit-tested against. Read-only QLI
 *              fields are seeded via JSON.deserialize.
 */
@isTest
private class COLAUpliftCalculatorTest {

    // ---- helpers -------------------------------------------------------------

    private static QuoteLineItem qliFromJson(String jsonStr) {
        return (QuoteLineItem) JSON.deserialize(jsonStr, QuoteLineItem.class);
    }

    private static Map<String, Object> wrapperWithPath(List<Object> dataPath) {
        return new Map<String, Object>{ 'dataPath' => dataPath };
    }

    private static Object attrValue(Map<String, Object> upd, String attributeName) {
        if (upd == null) return null;
        List<Object> attrs = (List<Object>) upd.get('attributes');
        for (Object o : attrs) {
            Map<String, Object> a = (Map<String, Object>) o;
            if (a.get('attributeName') == attributeName) return a.get('attributeValue');
        }
        return null;
    }

    // Numeric assert that is robust to Integer/Decimal/Double boxing and scale differences.
    private static void assertDec(Decimal expected, Object actual, String msg) {
        System.assertNotEquals(null, actual, msg + ' (was null)');
        Decimal a = Decimal.valueOf(String.valueOf(actual));
        System.assertEquals(expected.setScale(4), a.setScale(4), msg);
    }

    private static List<Object> updatePath(Map<String, Object> upd) {
        Map<String, Object> nodePath = (Map<String, Object>) upd.get('nodePath');
        return (List<Object>) nodePath.get('dataPath');
    }

    // ---- isPersistedLineOverride --------------------------------------------

    @isTest
    static void isPersistedLineOverride_matrix() {
        System.assertEquals(false, COLAUpliftCalculator.isPersistedLineOverride(null, 5), 'null override -> false');
        System.assertEquals(false, COLAUpliftCalculator.isPersistedLineOverride(5, null), 'null stamped default -> false');
        System.assertEquals(false, COLAUpliftCalculator.isPersistedLineOverride(5, 5), 'equal -> not an override');
        System.assertEquals(true, COLAUpliftCalculator.isPersistedLineOverride(5, 3), 'differs -> override');
        System.assertEquals(true, COLAUpliftCalculator.isPersistedLineOverride(3, 5), 'differs (lower) -> override');
    }

    // ---- buildExplainerText --------------------------------------------------

    @isTest
    static void buildExplainerText_variants() {
        System.assertEquals('COLA Uplift: 5.0% (Software)',
            COLAUpliftCalculator.buildExplainerText(5, 'Software', 'CMDT Lookup'),
            'CMDT Lookup source is not bracketed');
        System.assertEquals('COLA Uplift: 5.0% (Software) [Line Override]',
            COLAUpliftCalculator.buildExplainerText(5, 'Software', 'Line Override'),
            'non-CMDT source is bracketed');
        System.assertEquals('COLA Uplift: 5.0%',
            COLAUpliftCalculator.buildExplainerText(5, null, 'CMDT Lookup'),
            'null solution category omitted');
        System.assertEquals('COLA Uplift: 5.0% [Contract Override]',
            COLAUpliftCalculator.buildExplainerText(5, '', 'Contract Override'),
            'blank solution category omitted; source bracketed');
    }

    // ---- computeStampedMaintenanceColaNet -----------------------------------

    @isTest
    static void computeStampedMaintenanceColaNet_priorComponents() {
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":1000,"Prior_Partner_Discount__c":100,"Prior_Discretionary_Discount__c":50,"COLA_Uplift_Percent__c":10}');
        // preColaNet = 1000 - 100 - 50 = 850 ; *1.10 = 935.00
        assertDec(935.00, COLAUpliftCalculator.computeStampedMaintenanceColaNet(qli), 'prior-component net with COLA');
    }

    @isTest
    static void computeStampedMaintenanceColaNet_discountFallback() {
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":1000,"Discount":10}');
        // priorDisc = (1000 - 0) * 0.10 = 100 ; preColaNet = 1000 - 0 - 100 = 900 ; COLA 0 -> 900.00
        assertDec(900.00, COLAUpliftCalculator.computeStampedMaintenanceColaNet(qli), 'discount fallback net');
    }

    @isTest
    static void computeStampedMaintenanceColaNet_nonPositiveReturnsNull() {
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":100,"Prior_Partner_Discount__c":100}');
        // preColaNet = 100 - 100 - 0 = 0 -> null
        System.assertEquals(null, COLAUpliftCalculator.computeStampedMaintenanceColaNet(qli), 'non-positive pre-COLA net -> null');
    }

    // ---- isOrderTransaction (List overload) ---------------------------------

    @isTest
    static void isOrderTransaction_detectsOrderRoot() {
        List<Object> orderItems = new List<Object>{ wrapperWithPath(new List<Object>{ '801000000000001AAA', '0QLxxx' }) };
        List<Object> quoteItems = new List<Object>{ wrapperWithPath(new List<Object>{ '0Q0000000000001AAA', '0QLxxx' }) };
        System.assertEquals(true, COLAUpliftCalculator.isOrderTransaction(orderItems), 'root 801 -> Order');
        System.assertEquals(false, COLAUpliftCalculator.isOrderTransaction(quoteItems), 'root 0Q0 -> not Order');
        System.assertEquals(false, COLAUpliftCalculator.isOrderTransaction(new List<Object>()), 'empty -> false');
        System.assertEquals(false, COLAUpliftCalculator.isOrderTransaction(null), 'null -> false');
        System.assertEquals(false, COLAUpliftCalculator.isOrderTransaction(new List<Object>{ new Map<String, Object>() }), 'no dataPath -> false');
    }

    // ---- buildNetUnitPriceUpdate --------------------------------------------

    @isTest
    static void buildNetUnitPriceUpdate_seedsNetOnUpdatePath() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        Map<String, Object> upd = COLAUpliftCalculator.buildNetUnitPriceUpdate(wrapper, 935);
        System.assertNotEquals(null, upd, 'valid price -> update');
        System.assertEquals(new List<Object>{ 'qli' }, updatePath(upd), 'updatePath is dataPath minus first');
        assertDec(935.00, attrValue(upd, 'NetUnitPrice'), 'NetUnitPrice seeded');
    }

    @isTest
    static void buildNetUnitPriceUpdate_guards() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        System.assertEquals(null, COLAUpliftCalculator.buildNetUnitPriceUpdate(wrapper, 0), 'zero price -> null');
        System.assertEquals(null, COLAUpliftCalculator.buildNetUnitPriceUpdate(wrapper, -5), 'negative price -> null');
        System.assertEquals(null, COLAUpliftCalculator.buildNetUnitPriceUpdate(new Map<String, Object>(), 935), 'no dataPath -> null');
    }

    // ---- buildItemUpdate -----------------------------------------------------

    @isTest
    static void buildItemUpdate_buildsAuditAttributes() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        Map<String, Object> upd = COLAUpliftCalculator.buildItemUpdate(wrapper, 105, 5, 'explainer', 'Line Override', 100, 'Software');
        System.assertEquals(new List<Object>{ 'qli' }, updatePath(upd), 'updatePath minus first');
        assertDec(105.00, attrValue(upd, 'COLACalculatedPrice__c'), 'calc price');
        assertDec(100.00, attrValue(upd, 'Pre_COLA_Price__c'), 'pre-COLA price');
        System.assertEquals('Line Override', attrValue(upd, 'COLA_Source__c'), 'source');
        System.assertNotEquals(null, attrValue(upd, 'COLA_Applied_Date__c'), 'applied date present');
        System.assertEquals('Software', attrValue(upd, 'COLA_Solution_Category__c'), 'solution category present');
    }

    @isTest
    static void buildItemUpdate_blankSolCatOmitted_andNullPathNull() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        Map<String, Object> upd = COLAUpliftCalculator.buildItemUpdate(wrapper, 105, 5, 'ex', 'CMDT Lookup', 100, '');
        System.assertEquals(null, attrValue(upd, 'COLA_Solution_Category__c'), 'blank solCat omitted');
        System.assertEquals(null, COLAUpliftCalculator.buildItemUpdate(new Map<String, Object>(), 105, 5, 'ex', 'CMDT Lookup', 100, 'Software'), 'no dataPath -> null');
    }

    // ---- buildMaintenanceColaItemUpdate -------------------------------------

    @isTest
    static void buildMaintenanceColaItemUpdate_explicitPartnerPercent() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":1000,"PartnerDiscountPercent":20,"Discount":15}');
        Map<String, Object> upd = COLAUpliftCalculator.buildMaintenanceColaItemUpdate(wrapper, qli, 935);
        assertDec(935.00, attrValue(upd, 'COLACalculatedPrice__c'), 'cola net');
        assertDec(20, attrValue(upd, 'PartnerDiscountPercent'), 'explicit partner percent echoed');
        assertDec(15, attrValue(upd, 'Discount'), 'discount echoed');
    }

    @isTest
    static void buildMaintenanceColaItemUpdate_derivedPartnerPercent() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        // No PartnerDiscountPercent; derive from Prior_Partner_Discount__c / Base_Price__c * 100 = 100/1000*100 = 10.00
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":1000,"Prior_Partner_Discount__c":100}');
        Map<String, Object> upd = COLAUpliftCalculator.buildMaintenanceColaItemUpdate(wrapper, qli, 850);
        assertDec(10.00, attrValue(upd, 'PartnerDiscountPercent'), 'derived partner percent');
        System.assertEquals(null, attrValue(upd, 'Discount'), 'no discount attr when Discount unset');
    }

    @isTest
    static void buildMaintenanceColaItemUpdate_nullPathNull() {
        QuoteLineItem qli = qliFromJson('{"Base_Price__c":1000}');
        System.assertEquals(null, COLAUpliftCalculator.buildMaintenanceColaItemUpdate(new Map<String, Object>(), qli, 935), 'no dataPath -> null');
    }

    // ---- extractLineItemData -------------------------------------------------

    @isTest
    static void extractLineItemData_unwrapsTagValue() {
        Map<String, Object> innerMap = new Map<String, Object>{ 'a' => 1 };
        Map<String, Object> wrapper = new Map<String, Object>{ 'tagValue' => innerMap };
        System.assertEquals(innerMap, COLAUpliftCalculator.extractLineItemData(wrapper), 'returns inner tagValue map');

        Map<String, Object> plain = new Map<String, Object>{ 'b' => 2 };
        System.assertEquals(plain, COLAUpliftCalculator.extractLineItemData(plain), 'no tagValue -> returns wrapper');

        System.assertEquals(null, COLAUpliftCalculator.extractLineItemData('not-a-map'), 'non-map -> null');
        System.assertEquals(null, COLAUpliftCalculator.extractLineItemData(null), 'null -> null');
    }

    // ---- buildCOLAContextUpdate ---------------------------------------------

    @isTest
    static void buildCOLAContextUpdate_singleYear() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        // preCOLA = 110 / (1 + 0.10) = 100.00 ; single year uplift 5% -> 105.00
        Map<String, Object> upd = COLAUpliftCalculator.buildCOLAContextUpdate(wrapper, 5, 'MyCAP Default', 110, 10, 'Software', 1);
        assertDec(100.00, attrValue(upd, 'Pre_COLA_Price__c'), 'pre-COLA derived');
        assertDec(105.00, attrValue(upd, 'COLACalculatedPrice__c'), 'single-year compounded == flat');
        System.assertEquals('MyCAP Default', attrValue(upd, 'COLA_Source__c'), 'source');
        System.assertEquals('Software', attrValue(upd, 'COLA_Solution_Category__c'), 'solCat');
    }

    @isTest
    static void buildCOLAContextUpdate_multiYearCompound() {
        Map<String, Object> wrapper = wrapperWithPath(new List<Object>{ 'root', 'qli' });
        // preCOLA = 100 (unitPrice=100, defaultPct=0 -> preCOLA=unitPrice) ; 2 terms @5% -> 100*1.05*1.05 = 110.25
        Map<String, Object> upd = COLAUpliftCalculator.buildCOLAContextUpdate(wrapper, 5, 'MyCAP Default', 100, 0, 'Software', 2);
        assertDec(100, attrValue(upd, 'Pre_COLA_Price__c'), 'defaultPct 0 -> preCOLA is unitPrice');
        assertDec(110.25, attrValue(upd, 'COLACalculatedPrice__c'), '2-year compound');
    }

    @isTest
    static void buildCOLAContextUpdate_nullPathNull() {
        System.assertEquals(null, COLAUpliftCalculator.buildCOLAContextUpdate(new Map<String, Object>(), 5, 'x', 100, 0, 'S', 1), 'no dataPath -> null');
    }

    // ---- isManualLineOverride (D-13: relocated from COLAUpliftHandler) -------

    @isTest
    static void isManualLineOverride_matrix() {
        System.assertEquals(false, COLAUpliftCalculator.isManualLineOverride(null, 3, null, null), 'null pct -> not manual');
        System.assertEquals(true, COLAUpliftCalculator.isManualLineOverride(7, 3, null, null), 'differs from CMDT, no mycap/contract -> manual');
        System.assertEquals(false, COLAUpliftCalculator.isManualLineOverride(3, 3, null, null), 'equals CMDT -> not manual');
        System.assertEquals(false, COLAUpliftCalculator.isManualLineOverride(4, 3, 4, null), 'equals MyCAP -> not manual');
        System.assertEquals(false, COLAUpliftCalculator.isManualLineOverride(4, 3, null, 4), 'equals Contract -> not manual');
        System.assertEquals(true, COLAUpliftCalculator.isManualLineOverride(9, 3, 4, 5), 'differs from all system rates -> manual');
    }

    // ---- resolveTier (D-13: byte-verbatim from the prehook selection block) --

    @isTest
    static void resolveTier_tierSelection() {
        // Tier 1 via persisted stamped-default override (Marc 2026-07-07 fix): stored 5 != Default 3
        COLAUpliftCalculator.TierResult t1p = COLAUpliftCalculator.resolveTier(5, 3, 3, null);
        System.assertEquals(5, t1p.percent); System.assertEquals('Line Override', t1p.source);

        // Tier 1 via manual override (no stamped default): 7 differs from CMDT 3
        COLAUpliftCalculator.TierResult t1m = COLAUpliftCalculator.resolveTier(7, null, 3, null);
        System.assertEquals(7, t1m.percent); System.assertEquals('Line Override', t1m.source);

        // Tier 2: no override, contract present
        COLAUpliftCalculator.TierResult t2 = COLAUpliftCalculator.resolveTier(null, null, 3, 4);
        System.assertEquals(4, t2.percent); System.assertEquals('Contract Override', t2.source);

        // Tier 3: no override, no contract -> CMDT
        COLAUpliftCalculator.TierResult t3 = COLAUpliftCalculator.resolveTier(null, null, 3, null);
        System.assertEquals(3, t3.percent); System.assertEquals('CMDT Lookup', t3.source);

        // Handler-INSERT reduction: null line override + null stamped default collapses to Tier2-else-Tier3
        System.assertEquals('Contract Override', COLAUpliftCalculator.resolveTier(null, null, 3, 4).source);
        System.assertEquals('CMDT Lookup', COLAUpliftCalculator.resolveTier(null, null, 3, null).source);

        // Contract boundary: pct == contract rate -> Contract Override (NOT Line Override)
        COLAUpliftCalculator.TierResult tb = COLAUpliftCalculator.resolveTier(4, null, 3, 4);
        System.assertEquals('Contract Override', tb.source);
        System.assertEquals(4, tb.percent);

        // MyCAP hardcode-null: a year-1 value equal to a hypothetical outyear MyCAP rate but differing
        // from CMDT is still a manual override (resolveTier passes mycap=null internally).
        COLAUpliftCalculator.TierResult tm = COLAUpliftCalculator.resolveTier(3, null, 5, null);
        System.assertEquals('Line Override', tm.source);
        System.assertEquals(3, tm.percent);
    }
}
