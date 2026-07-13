/**
 * @description Test coverage for OrderSubmissionValidator, asserting bulk-safety so a
 * multi-line order validates in constant SOQL rather than the per-field nested loop that
 * produced 20 + 5*N queries and breached the governor limit.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@isTest
private class OrderSubmissionValidatorTest {

    /**
     * @description Seeds an Account, two Contacts, a Product2 with a standard PricebookEntry,
     * a Draft Order, and three OrderItems used as the shared fixture for the test methods.
     */
    @testSetup
    static void setup() {
        Account acc = new Account(Name = 'SC3366 Test Account');
        insert acc;

        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'Bill', LastName = 'ToContact', AccountId = acc.Id),
            new Contact(FirstName = 'Ship', LastName = 'ToContact', AccountId = acc.Id)
        };
        insert contacts;

        Product2 prod = new Product2(Name = 'SC3366 Test Product', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = prod.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId       = acc.Id,
            EffectiveDate   = Date.today(),
            Status          = 'Draft',
            Pricebook2Id    = Test.getStandardPricebookId(),
            BillToContactId = contacts[0].Id,
            ShipToContactId = contacts[1].Id
        );
        insert ord;

        List<OrderItem> items = new List<OrderItem>();
        for (Integer i = 0; i < 3; i++) {
            items.add(new OrderItem(
                OrderId          = ord.Id,
                Product2Id       = prod.Id,
                PricebookEntryId = pbe.Id,
                Quantity         = 1,
                UnitPrice        = 100
            ));
        }
        insert items;
    }

    /**
     * @description Returns the Id of the seeded test Order for the fixture Account.
     * @return The Id of the test Order.
     */
    private static Id getOrderId() {
        return [SELECT Id FROM Order WHERE AccountId IN (SELECT Id FROM Account WHERE Name = 'SC3366 Test Account') LIMIT 1].Id;
    }

    /**
     * @description Builds a ValidationRequest wrapping the given order Id.
     * @param orderId The Order Id to place on the request.
     * @return A ValidationRequest targeting the supplied order.
     */
    private static OrderSubmissionValidator.ValidationRequest reqFor(Id orderId) {
        OrderSubmissionValidator.ValidationRequest r = new OrderSubmissionValidator.ValidationRequest();
        r.orderId = orderId;
        return r;
    }

    /**
     * @description Verifies validate returns one internally consistent result per request,
     * with errorCount and hasErrors matching errorMessages, and that the bare test order
     * reports blank-required-field errors.
     */
    @isTest
    static void testValidate_returnsConsistentResult() {
        Id orderId = getOrderId();

        Test.startTest();
        List<OrderSubmissionValidator.ValidationResult> results =
            OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{ reqFor(orderId) });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        OrderSubmissionValidator.ValidationResult res = results[0];
        System.assertNotEquals(null, res.errorMessages, 'errorMessages is initialised');
        System.assertEquals(res.errorMessages.size(), res.errorCount, 'errorCount matches messages');
        System.assertEquals(res.errorCount > 0, res.hasErrors, 'hasErrors matches count');
        // The test order leaves Workday/DUNS-type required fields blank, so errors are expected.
        System.assert(res.hasErrors, 'Expected at least one blank-required-field error on the bare test order');
    }

    /**
     * @description Verifies validation issues a constant, small number of SOQL queries
     * regardless of order line count by validating a 43-line order and asserting the query
     * count stays within a generous ceiling.
     */
    @isTest
    static void testValidate_bulkSafeConstantSoql() {
        Id orderId = getOrderId();
        // Add many lines so a per-line implementation would explode the SOQL count.
        Product2 prod = [SELECT Id FROM Product2 WHERE Name = 'SC3366 Test Product' LIMIT 1];
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];
        List<OrderItem> moreLines = new List<OrderItem>();
        for (Integer i = 0; i < 40; i++) {
            moreLines.add(new OrderItem(
                OrderId = orderId, Product2Id = prod.Id, PricebookEntryId = pbe.Id,
                Quantity = 1, UnitPrice = 100));
        }
        insert moreLines;

        Test.startTest();
        Integer before = Limits.getQueries();
        OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{ reqFor(orderId) });
        Integer used = Limits.getQueries() - before;
        Test.stopTest();

        // Constant: 1 rules + 1 order + 1 items + 1 per related object (Account, Contact) ~= 5.
        // A per-line implementation on 43 lines would be 100+. Generous ceiling guards the invariant.
        System.assert(used <= 10,
            'Validation SOQL must be constant regardless of line count; used=' + used + ' on a 43-line order');
    }

    /**
     * @description Verifies error output is formatted like the original flow formula: the
     * display string joins messages with line breaks, and messages include bullet markers
     * and a record hyperlink.
     */
    @isTest
    static void testValidate_producesFormattedErrors() {
        Id orderId = getOrderId();

        Test.startTest();
        List<OrderSubmissionValidator.ValidationResult> results =
            OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{ reqFor(orderId) });
        Test.stopTest();

        OrderSubmissionValidator.ValidationResult res = results[0];
        System.assert(res.hasErrors, 'Expected errors');
        System.assert(res.errorDisplay.contains('<br>'), 'Display string joins formatted messages');
        Boolean hasBullet = false, hasLink = false;
        for (String m : res.errorMessages) {
            if (m.startsWith('•')) hasBullet = true;
            if (m.contains('Link to Record')) hasLink = true;
        }
        System.assert(hasBullet, 'Messages are bulleted like the original flow formula');
        System.assert(hasLink, 'Messages include a record hyperlink');
    }

    /**
     * @description Verifies validate returns an empty list for null and empty input, and that
     * a request with a null order id yields a single result reporting no errors.
     */
    @isTest
    static void testValidate_nullAndEmptyInput() {
        System.assertEquals(0, OrderSubmissionValidator.validate(null).size(), 'null -> empty');
        System.assertEquals(0,
            OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>()).size(),
            'empty -> empty');

        // A request with a null order id yields a result with no errors (nothing to validate).
        List<OrderSubmissionValidator.ValidationResult> res =
            OrderSubmissionValidator.validate(new List<OrderSubmissionValidator.ValidationRequest>{
                new OrderSubmissionValidator.ValidationRequest() });
        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].hasErrors, 'null order id -> no errors');
    }

    /**
     * @description Verifies isValuePopulated's per-type semantics: Boolean false and true are
     * populated, null is never populated, blank text is not populated while non-blank text is,
     * and non-null non-text non-boolean values are populated.
     */
    @isTest
    static void testIsValuePopulated_typeSemantics() {
        // Boolean false is intentionally "populated"
        System.assertEquals(true,
            OrderSubmissionValidator.isValuePopulated(false, Schema.DisplayType.BOOLEAN), 'false is populated');
        System.assertEquals(true,
            OrderSubmissionValidator.isValuePopulated(true, Schema.DisplayType.BOOLEAN), 'true is populated');
        // null is never populated
        System.assertEquals(false,
            OrderSubmissionValidator.isValuePopulated(null, Schema.DisplayType.STRING), 'null not populated');
        // text must be non-blank
        System.assertEquals(false,
            OrderSubmissionValidator.isValuePopulated('   ', Schema.DisplayType.STRING), 'blank text not populated');
        System.assertEquals(true,
            OrderSubmissionValidator.isValuePopulated('x', Schema.DisplayType.STRING), 'non-blank text populated');
        // non-text, non-bool, non-null -> populated
        System.assertEquals(true,
            OrderSubmissionValidator.isValuePopulated(Date.today(), Schema.DisplayType.DATE), 'non-null date populated');
        System.assertEquals(true,
            OrderSubmissionValidator.isValuePopulated(5, Schema.DisplayType.INTEGER), 'non-null number populated');
    }

    /**
     * @description Verifies isFieldPopulated at the record level: a set field reads as populated,
     * an unset field as not populated, and a null record as not populated.
     */
    @isTest
    static void testIsFieldPopulated_recordLevel() {
        Account a = new Account(Name = 'Has Name');
        System.assertEquals(true,
            OrderSubmissionValidator.isFieldPopulated(a, 'Account', 'Name'), 'populated text field');
        System.assertEquals(false,
            OrderSubmissionValidator.isFieldPopulated(a, 'Account', 'Phone'), 'unset text field');
        System.assertEquals(false,
            OrderSubmissionValidator.isFieldPopulated(null, 'Account', 'Name'), 'null record -> not populated');
    }
}