@isTest
private class FindRecordsInCollectionTest {

    @isTest static void testSingleMatch() {
        // prepare input collection with one matching and one non-matching record
        Account a1 = new Account(Name='FindMe');
        Account a2 = new Account(Name='Other');

        List<SObject> input = new List<SObject>{a1, a2};

        FindRecordsInCollection.Requests req = new FindRecordsInCollection.Requests();
        req.inputCollection = input;
        req.targetObject = 'Account';
        req.targetField = 'Name';
        req.targetValue = 'FindMe';

        Test.startTest();
        List<FindRecordsInCollection.Results> res = FindRecordsInCollection.execute(new List<FindRecordsInCollection.Requests>{req});
        Test.stopTest();

        System.assertEquals(1, res.size(), 'Should return one Results wrapper');
        FindRecordsInCollection.Results r = res[0];
        System.assertNotEquals(null, r.multipleOutputMembers, 'multipleOutputMembers should not be null for a match');
        System.assertEquals(1, r.multipleOutputMembers.size(), 'There should be exactly one matching member');
        System.assertNotEquals(null, r.singleOutputMember, 'singleOutputMember should be set when exactly one match');

        Account found = (Account) r.singleOutputMember;
        System.assertEquals('FindMe', found.Name, 'Found record should have the expected Name');
    }

    @isTest static void testMultipleMatches() {
        // prepare input collection with two matching records
        Account a1 = new Account(Name='FindMe');
        Account a2 = new Account(Name='FindMe');
        Account a3 = new Account(Name='Other');

        List<SObject> input = new List<SObject>{a1, a2, a3};

        FindRecordsInCollection.Requests req = new FindRecordsInCollection.Requests();
        req.inputCollection = input;
        req.targetObject = 'Account';
        req.targetField = 'Name';
        req.targetValue = 'FindMe';

        Test.startTest();
        List<FindRecordsInCollection.Results> res = FindRecordsInCollection.execute(new List<FindRecordsInCollection.Requests>{req});
        Test.stopTest();

        FindRecordsInCollection.Results r = res[0];
        System.assertNotEquals(null, r.multipleOutputMembers, 'multipleOutputMembers should not be null when matches exist');
        System.assertEquals(2, r.multipleOutputMembers.size(), 'Should find two matching records');
        System.assertEquals(null, r.singleOutputMember, 'singleOutputMember should be null when multiple matches exist');
    }

    @isTest static void testNoMatchAndBulk() {
        // prepare input and two requests to exercise no-match and bulk behavior
        Account a1 = new Account(Name='Alpha');
        Account a2 = new Account(Name='Beta');

        FindRecordsInCollection.Requests req1 = new FindRecordsInCollection.Requests();
        req1.inputCollection = new List<SObject>{a1, a2};
        req1.targetObject = 'Account';
        req1.targetField = 'Name';
        req1.targetValue = 'Gamma'; // no record has this name

        FindRecordsInCollection.Requests req2 = new FindRecordsInCollection.Requests();
        req2.inputCollection = new List<SObject>{a1, a2};
        req2.targetObject = 'Account';
        req2.targetField = 'Name';
        req2.targetValue = 'Alpha'; // one match

        Test.startTest();
        List<FindRecordsInCollection.Results> resList = FindRecordsInCollection.execute(new List<FindRecordsInCollection.Requests>{req1, req2});
        Test.stopTest();

        System.assertEquals(2, resList.size(), 'Should return a Results entry for each request (bulk support)');

        // first request had no matches
        System.assertEquals(null, resList[0].multipleOutputMembers, 'No matches should leave multipleOutputMembers null');
        System.assertEquals(null, resList[0].singleOutputMember, 'No matches should leave singleOutputMember null');

        // second request had a single match
        System.assertNotEquals(null, resList[1].multipleOutputMembers, 'Should have matching members for second request');
        System.assertEquals(1, resList[1].multipleOutputMembers.size(), 'Second request should have one match');
        System.assertNotEquals(null, resList[1].singleOutputMember, 'singleOutputMember should be set for single match in second request');
    }
}