@isTest
private class OrderAssetizationGuardTest {

    // No AssetActionSource for the Order -> not yet assetized.
    @isTest
    static void returnsFalseWhenNotAssetized() {
        Account acc = new Account(Name = 'Guard Test Account');
        insert acc;
        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today()
        );
        insert ord;

        OrderAssetizationGuard.FlowInput req = new OrderAssetizationGuard.FlowInput();
        req.orderId = ord.Id;

        Test.startTest();
        List<OrderAssetizationGuard.FlowOutput> outs =
            OrderAssetizationGuard.checkAlreadyAssetized(
                new List<OrderAssetizationGuard.FlowInput>{ req });
        Test.stopTest();

        System.assertEquals(1, outs.size(), 'one output per input');
        System.assertEquals(false, outs[0].alreadyAssetized,
            'no AssetActionSource on the Order -> not assetized');
    }

    // Null / empty inputs must be handled without error (bulk-safe contract).
    @isTest
    static void handlesNullAndEmptyInputs() {
        System.assertEquals(0,
            OrderAssetizationGuard.checkAlreadyAssetized(
                new List<OrderAssetizationGuard.FlowInput>()).size(),
            'empty input -> empty output');

        OrderAssetizationGuard.FlowInput nullReq = new OrderAssetizationGuard.FlowInput();
        List<OrderAssetizationGuard.FlowOutput> outs =
            OrderAssetizationGuard.checkAlreadyAssetized(
                new List<OrderAssetizationGuard.FlowInput>{ nullReq });
        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].alreadyAssetized, 'null orderId -> false');

        System.assert(
            OrderAssetizationGuard.findAssetizedOrderIds(new Set<Id>()).isEmpty(),
            'empty id set -> empty result');
        System.assert(
            OrderAssetizationGuard.findAssetizedOrderIds(null).isEmpty(),
            'null id set -> empty result');
    }
}
