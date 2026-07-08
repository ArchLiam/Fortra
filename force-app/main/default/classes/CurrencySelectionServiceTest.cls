/**
 * Tests for CurrencySelectionService.
 *
 * D-15 (config extraction): the former hardcoded 14/15-country->currency map was moved into the
 * admin-editable Country_Currency_Map__mdt. These tests pin that the deployed MDT reproduces the
 * EXACT prior mapping (behavior-preserving) — if a record is dropped/changed, currencyMap_matchesLegacyHardcodedMap
 * fails. __mdt rows cannot be inserted in a test, so this reads the deployed records via getAll().
 */
@IsTest
private class CurrencySelectionServiceTest {

    // The exact map that used to be hardcoded in CurrencySelectionService (source of truth for D-15).
    private static Map<String, String> legacyMap() {
        return new Map<String, String>{
            'United States' => 'USD',
            'Canada' => 'CAD',
            'Australia' => 'AUD',
            'Germany' => 'EUR',
            'France' => 'EUR',
            'Italy' => 'EUR',
            'Spain' => 'EUR',
            'Netherlands' => 'EUR',
            'Belgium' => 'EUR',
            'Austria' => 'EUR',
            'Ireland' => 'EUR',
            'Portugal' => 'EUR',
            'Finland' => 'EUR',
            'Greece' => 'EUR',
            'Luxembourg' => 'EUR'
        };
    }

    @IsTest
    static void currencyMap_matchesLegacyHardcodedMap() {
        Map<String, String> expected = legacyMap();
        Map<String, String> actual = CurrencySelectionService.getCountryToCurrencyMap();

        System.assertEquals(expected.size(), actual.size(),
            'Country_Currency_Map__mdt must have exactly the same number of entries as the prior hardcoded map');
        for (String country : expected.keySet()) {
            System.assert(actual.containsKey(country), 'MDT missing country: ' + country);
            System.assertEquals(expected.get(country), actual.get(country),
                'MDT currency mismatch for ' + country);
        }
        // and no extra countries beyond the legacy set
        for (String country : actual.keySet()) {
            System.assert(expected.containsKey(country), 'MDT has an unexpected extra country: ' + country);
        }
    }

    @IsTest
    static void canChangeCurrencyOnOrder_locksActiveStatuses() {
        System.assertEquals(false, CurrencySelectionService.canChangeCurrencyOnOrder('Activated'), 'Activated is locked');
        System.assertEquals(false, CurrencySelectionService.canChangeCurrencyOnOrder('In Fulfillment'), 'In Fulfillment is locked');
        System.assertEquals(false, CurrencySelectionService.canChangeCurrencyOnOrder('Fulfilled'), 'Fulfilled is locked');
        System.assertEquals(false, CurrencySelectionService.canChangeCurrencyOnOrder('Completed'), 'Completed is locked');
        System.assertEquals(true, CurrencySelectionService.canChangeCurrencyOnOrder('Draft'), 'Draft is open');
        System.assertEquals(true, CurrencySelectionService.canChangeCurrencyOnOrder('Activation In Progress'), 'unknown status is open');
    }

    @IsTest
    static void determineCurrencyForCurrentUser_returnsNonBlank() {
        Test.startTest();
        String cur = CurrencySelectionService.determineCurrencyForCurrentUser();
        Test.stopTest();
        // Running user has a DefaultCurrencyIsoCode (priority 1) or falls through to the map / USD default.
        System.assert(String.isNotBlank(cur), 'Should resolve a non-blank currency');
    }
}
