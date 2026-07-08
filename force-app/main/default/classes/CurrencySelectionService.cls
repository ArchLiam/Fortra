public class CurrencySelectionService {
    
    public static String determineCurrencyForUser(Id userId) {
        User u = [SELECT Id, DefaultCurrencyIsoCode, Country, CompanyName 
                  FROM User WHERE Id = :userId];
        
        // Priority 1: User's default currency
        if (u.DefaultCurrencyIsoCode != null) {
            return u.DefaultCurrencyIsoCode;
        }
        
        // Priority 2: Country-based mapping. D-15: the mapping now lives in the admin-editable
        // Country_Currency_Map__mdt (seeded with the exact prior hardcoded entries), so ops can
        // maintain it without a code change. Lookup semantics are unchanged (exact containsKey/get).
        Map<String, String> countryToCurrency = getCountryToCurrencyMap();

        if (countryToCurrency.containsKey(u.Country)) {
            return countryToCurrency.get(u.Country);
        }
        
        // Priority 3: Default to USD
        return 'USD';
    }
    
    // Helper method to get currency for current user
    public static String determineCurrencyForCurrentUser() {
        return determineCurrencyForUser(UserInfo.getUserId());
    }

    // Country -> ISO currency map, sourced from Country_Currency_Map__mdt via zero-SOQL getAll()
    // (D-15). Replaces the former inline hardcoded map with identical entries. @TestVisible so a
    // unit test can assert the MDT reproduces the exact prior mapping (behavior-preserving).
    @TestVisible
    private static Map<String, String> getCountryToCurrencyMap() {
        Map<String, String> countryToCurrency = new Map<String, String>();
        for (Country_Currency_Map__mdt rec : Country_Currency_Map__mdt.getAll().values()) {
            if (rec.Country__c != null) {
                countryToCurrency.put(rec.Country__c, rec.Currency_Code__c);
            }
        }
        return countryToCurrency;
    }
    
    // Method to check if currency change is allowed for an Order
    public static Boolean canChangeCurrencyOnOrder(String orderStatus) {
        Set<String> lockedStatuses = new Set<String>{
            'Activated',
            'In Fulfillment',
            'Fulfilled',
            'Completed'
        };
        
        return !lockedStatuses.contains(orderStatus);
    }
}