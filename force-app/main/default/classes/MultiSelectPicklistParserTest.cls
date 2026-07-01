/**
 * @description Test class for MultiSelectPicklistParser
 * @author Claude Code
 * @date 2025-10-06
 */
@isTest
private class MultiSelectPicklistParserTest {

    /**
     * @description Test parsing a standard multi-select picklist value
     */
    @isTest
    static void testParseStandardMultiSelectPicklist() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = 'Value1;Value2;Value3';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(3, results[0].textCollection.size(), 'Should parse three values');
        System.assertEquals('Value1', results[0].textCollection[0], 'First value should be Value1');
        System.assertEquals('Value2', results[0].textCollection[1], 'Second value should be Value2');
        System.assertEquals('Value3', results[0].textCollection[2], 'Third value should be Value3');
    }

    /**
     * @description Test parsing with whitespace around values
     */
    @isTest
    static void testParseWithWhitespace() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = ' Value1 ; Value2 ; Value3 ';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(3, results[0].textCollection.size(), 'Should parse three values');
        System.assertEquals('Value1', results[0].textCollection[0], 'First value should be trimmed');
        System.assertEquals('Value2', results[0].textCollection[1], 'Second value should be trimmed');
        System.assertEquals('Value3', results[0].textCollection[2], 'Third value should be trimmed');
    }

    /**
     * @description Test parsing with empty values between semicolons
     */
    @isTest
    static void testParseWithEmptyValues() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = 'Value1;;Value3;;;Value5';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(3, results[0].textCollection.size(), 'Should only include non-empty values');
        System.assertEquals('Value1', results[0].textCollection[0], 'First value should be Value1');
        System.assertEquals('Value3', results[0].textCollection[1], 'Second value should be Value3');
        System.assertEquals('Value5', results[0].textCollection[2], 'Third value should be Value5');
    }

    /**
     * @description Test parsing a single value (no semicolons)
     */
    @isTest
    static void testParseSingleValue() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = 'SingleValue';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(1, results[0].textCollection.size(), 'Should have one value');
        System.assertEquals('SingleValue', results[0].textCollection[0], 'Value should be SingleValue');
    }

    /**
     * @description Test parsing null input
     */
    @isTest
    static void testParseNullInput() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = null;
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(0, results[0].textCollection.size(), 'Should return empty collection for null input');
    }

    /**
     * @description Test parsing empty string input
     */
    @isTest
    static void testParseEmptyStringInput() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = '';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(0, results[0].textCollection.size(), 'Should return empty collection for empty string');
    }

    /**
     * @description Test parsing with only semicolons
     */
    @isTest
    static void testParseOnlySemicolons() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = ';;;';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(0, results[0].textCollection.size(), 'Should return empty collection for only semicolons');
    }

    /**
     * @description Test parsing multiple requests in bulk
     */
    @isTest
    static void testParseBulkRequests() {
        // Arrange
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>();

        MultiSelectPicklistParser.Request request1 = new MultiSelectPicklistParser.Request();
        request1.multiSelectValue = 'A;B;C';
        requests.add(request1);

        MultiSelectPicklistParser.Request request2 = new MultiSelectPicklistParser.Request();
        request2.multiSelectValue = 'X;Y;Z';
        requests.add(request2);

        MultiSelectPicklistParser.Request request3 = new MultiSelectPicklistParser.Request();
        request3.multiSelectValue = null;
        requests.add(request3);

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(3, results.size(), 'Should return three results');
        System.assertEquals(3, results[0].textCollection.size(), 'First request should have 3 values');
        System.assertEquals(3, results[1].textCollection.size(), 'Second request should have 3 values');
        System.assertEquals(0, results[2].textCollection.size(), 'Third request should have 0 values');
    }

    /**
     * @description Test parsing with special characters
     */
    @isTest
    static void testParseWithSpecialCharacters() {
        // Arrange
        MultiSelectPicklistParser.Request request = new MultiSelectPicklistParser.Request();
        request.multiSelectValue = 'Value-1;Value_2;Value (3)';
        List<MultiSelectPicklistParser.Request> requests = new List<MultiSelectPicklistParser.Request>{ request };

        // Act
        Test.startTest();
        List<MultiSelectPicklistParser.Result> results = MultiSelectPicklistParser.parseMultiSelectPicklist(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(3, results[0].textCollection.size(), 'Should parse three values with special characters');
        System.assertEquals('Value-1', results[0].textCollection[0], 'Should handle hyphen');
        System.assertEquals('Value_2', results[0].textCollection[1], 'Should handle underscore');
        System.assertEquals('Value (3)', results[0].textCollection[2], 'Should handle parentheses');
    }
}