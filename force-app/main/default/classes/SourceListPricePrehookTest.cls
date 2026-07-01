/**
 * DISABLED: tests commented out per request — do not deploy until re-enabled.
 */
@IsTest
private class SourceListPricePrehookTest {
    /*
    @IsTest
    static void implementsSignalingProcessor() {
        SourceListPricePrehook prehook = new SourceListPricePrehook();
        System.assertNotEquals(null, prehook);
    }

    @IsTest
    static void unwrapFieldValue_handlesRecordKeyedHeaderTags() {
        SourceListPricePrehook prehook = new SourceListPricePrehook();
        String quoteId = '0Q0WC0000036ED30AM';

        Map<String, Object> tagMap = new Map<String, Object>{
            'CurrencyIsoCode' => new Map<String, Object>{
                quoteId => 'USD'
            },
            'PriceBooks' => new Map<String, Object>{
                quoteId => '01sWC0000022GHFYA2'
            }
        };

        System.assertEquals('USD', prehook.extractFieldValue(tagMap, 'CurrencyIsoCode', quoteId));
        System.assertEquals('01sWC0000022GHFYA2', prehook.extractFieldValue(tagMap, 'PriceBooks', quoteId));
    }

    @IsTest
    static void unwrapFieldValue_handlesNestedTagValueWrappers() {
        SourceListPricePrehook prehook = new SourceListPricePrehook();
        String lineItemId = '0QLWC000003abc123AA';

        Map<String, Object> tagMap = new Map<String, Object>{
            'ItemIsDerived__std' => new Map<String, Object>{
                'tagValue' => new Map<String, Object>{
                    lineItemId => true
                }
            },
            'ItemPricebookEntry' => new Map<String, Object>{
                lineItemId => '01uWC000000abc123AA'
            }
        };

        System.assertEquals(true, prehook.extractFieldValue(tagMap, 'ItemIsDerived__std', lineItemId));
        System.assertEquals('01uWC000000abc123AA', prehook.extractFieldValue(tagMap, 'ItemPricebookEntry', lineItemId));
    }

    @IsTest
    static void extractRecordIdFromDataPath_returnsLastSegment() {
        SourceListPricePrehook prehook = new SourceListPricePrehook();
        List<Object> dataPath = new List<Object>{
            'ctx-instance-id',
            '0Q0WC0000036ED30AM',
            '0QLWC000003abc123AA'
        };

        System.assertEquals('0QLWC000003abc123AA', prehook.extractRecordIdFromDataPath(dataPath));
    }
    */
}