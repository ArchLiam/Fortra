@IsTest
public class OrderCascadeDeleterTest {

    @IsTest
    static void returnsNotFoundForUnknownId() {
        Id fakeId = '801000000000000AAA';
        OrderCascadeDeleter.Input inp = new OrderCascadeDeleter.Input();
        inp.orderId = fakeId;
        Test.startTest();
        List<OrderCascadeDeleter.Output> results = OrderCascadeDeleter.cascadeDelete(new List<OrderCascadeDeleter.Input>{ inp });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('not found'), 'Expected "not found" message, got: ' + results[0].message);
    }

    @IsTest
    static void deletesOrderWithAua() {
        Account acct = new Account(Name='Cascade Plan Test Account');
        insert acct;

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;

        AppUsageAssignment aua = new AppUsageAssignment(
            RecordId = ord.Id,
            AppUsageType = 'RevenueLifecycleManagement'
        );
        insert aua;

        OrderCascadeDeleter.Input inp = new OrderCascadeDeleter.Input();
        inp.orderId = ord.Id;

        Test.startTest();
        List<OrderCascadeDeleter.Output> results = OrderCascadeDeleter.cascadeDelete(new List<OrderCascadeDeleter.Input>{ inp });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected success, got: ' + results[0].message);
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Id = :ord.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM AppUsageAssignment WHERE Id = :aua.Id]);
    }

    @IsTest
    static void deletesDraftOrderWithNoDependencies() {
        Account acct = new Account(Name='Cascade Test Account');
        insert acct;

        Pricebook2 pb = new Pricebook2(Id = Test.getStandardPricebookId());

        Order ord = new Order(
            AccountId = acct.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = pb.Id
        );
        insert ord;
        Id orderId = ord.Id;

        OrderCascadeDeleter.Input inp = new OrderCascadeDeleter.Input();
        inp.orderId = orderId;

        Test.startTest();
        List<OrderCascadeDeleter.Output> results = OrderCascadeDeleter.cascadeDelete(new List<OrderCascadeDeleter.Input>{ inp });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Expected success, got: ' + results[0].message);
        System.assertEquals(0, [SELECT COUNT() FROM Order WHERE Id = :orderId]);
    }
}