@isTest
public class CurrencyCodeExtractorTest {
    
    @isTest
    static void testExtractFromDashFormat() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = 'AUD - Australian Dollar';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('AUD', results[0].isoCode);
    }
    
    @isTest
    static void testExtractFromSpaceFormat() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = 'EUR European Euro';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('EUR', results[0].isoCode);
    }
    
    @isTest
    static void testExtractPlainCode() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = 'USD';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('USD', results[0].isoCode);
    }
    
    @isTest
    static void testExtractLowerCase() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = 'gbp - British Pound';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('GBP', results[0].isoCode);
    }
    
    @isTest
    static void testExtractWithExtraSpaces() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = '  CAD  -  Canadian Dollar  ';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('CAD', results[0].isoCode);
    }
    
    @isTest
    static void testNullInput() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = null;
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].isoCode);
    }
    
    @isTest
    static void testEmptyString() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = '';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].isoCode);
    }
    
    @isTest
    static void testInvalidFormat() {
        CurrencyCodeExtractor.Request req = new CurrencyCodeExtractor.Request();
        req.currencyText = 'Australian Dollar';
        
        Test.startTest();
        List<CurrencyCodeExtractor.Result> results = CurrencyCodeExtractor.extractCode(
            new List<CurrencyCodeExtractor.Request>{req}
        );
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].isoCode);
    }
}