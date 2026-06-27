/**
 * @description Test class for QLDescriptionGeneratorPrehook (v7.0).
 *
 *              Unit tests cover the pure-function spec:
 *               - computeUnitTypeSegment: all branches per the source deck
 *               - buildDescription: deck samples + edge cases (suppression,
 *                 broadened Unit Quantity rule, truncation)
 *               - isQuoteLineSet: scope guard
 *               - buildContextUpdate: shape of the updateContextAttributes
 *                 payload (root entity dropped from dataPath, attribute name
 *                 targets the hydration-mapped SalesTrxnItemDescription)
 *               - submitContextUpdates: empty/null no-op path
 *
 *              Full-pipeline integration testing happens in fortrauat via
 *              the Verification steps in the implementation plan.
 *              queryConfiguredAttributes, queryLineItemDataPaths, and the
 *              execute() happy path require a runtime Context.IndustriesContext
 *              and are exercised by integration tests rather than unit tests.
 *
 * @author Marc DeBrey
 * @date April 2026
 */
@IsTest
private class QLDescriptionGeneratorPrehookTest {

    // ============================================================
    // isQuoteLineSet — scope guard
    // ============================================================

    @IsTest
    static void isQuoteLineSet_QuoteLineItemTrue() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Id qliId = fakeId(QuoteLineItem.SObjectType);

        System.assertEquals(true, hook.isQuoteLineSet(new Set<Id>{ qliId }));
    }

    @IsTest
    static void isQuoteLineSet_OtherTypeFalse() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Id accountId = fakeId(Account.SObjectType);
        Id orderItemId = fakeId(OrderItem.SObjectType);

        System.assertEquals(false, hook.isQuoteLineSet(new Set<Id>{ accountId }));
        System.assertEquals(false, hook.isQuoteLineSet(new Set<Id>{ orderItemId }),
            'Order context must bail (Quote-only scope)');
    }

    @IsTest
    static void isQuoteLineSet_EmptySetFalse() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(false, hook.isQuoteLineSet(new Set<Id>()));
    }

    // ============================================================
    // computeUnitTypeSegment — page 4 of the deck
    // ============================================================

    @IsTest
    static void unitTypeSegment_BlankUnitTypeReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => '',
            'Attribute_Volume' => '5'
        };

        System.assertEquals(null, hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_UnitTypeNotPresentReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>();

        System.assertEquals(null, hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_PerUsersWithUnitQuantityRendersUsersCount() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => '15'
        };

        System.assertEquals('Users: 15', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_PerUsersWithoutUnitQuantityRendersPerUser() {
        // Product does not expose the Unit Quantity attribute at all.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User'
        };

        System.assertEquals('Per User', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_PerUsersWithBlankUnitQuantityRendersPerUser() {
        // Product exposes the attribute but the user left it blank.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => ''
        };

        System.assertEquals('Per User', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_OtherUnitTypeWithoutQuantityRendersAsIs() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Flat Fee'
        };

        System.assertEquals('Flat Fee', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_OtherUnitTypeWithQuantityRendersAppended() {
        // Unit Quantity applies to ANY Unit Type, not only "Per Users".
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Flat Fee',
            'Attribute_Volume' => '5'
        };

        System.assertEquals('Flat Fee: 5', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_OtherUnitTypeWithBlankQuantityRendersAsIs() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Flat Fee',
            'Attribute_Volume' => ''
        };

        System.assertEquals('Flat Fee', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_UnitQuantityIsTrimmed() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => '  250  '
        };

        System.assertEquals('Users: 250', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_DevicesWithNumberOfUnitsRendersRange() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices',
            'Number_of_Units' => '36-65'
        };

        System.assertEquals('Devices: 36-65', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_AttributeVolumePreferredOverNumberOfUnits() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices',
            'Attribute_Volume' => '50',
            'Number_of_Units' => '36-65'
        };

        System.assertEquals('Devices: 50', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_NumberOfUnitsIsTrimmed() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices',
            'Number_of_Units' => '  36-65  '
        };

        System.assertEquals('Devices: 36-65', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_BlankAttributeVolumeFallsThroughToNumberOfUnits() {
        // Real-world beSECURE shape: Attribute_Volume present-but-blank, count
        // lives in Number_of_Units — must fall through and render the range.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices',
            'Attribute_Volume' => '',
            'Number_of_Units' => '36-65'
        };

        System.assertEquals('Devices: 36-65', hook.computeUnitTypeSegment(attrs));
    }

    @IsTest
    static void unitTypeSegment_NeitherQuantityAttrRendersBareUnitType() {
        // Neither Attribute_Volume nor Number_of_Units present → bare Unit Type,
        // no count suffix (regression guard for the reported "Devices" symptom).
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices'
        };

        System.assertEquals('Devices', hook.computeUnitTypeSegment(attrs));
    }

    // ============================================================
    // buildDescription — reproduces deck samples and edge cases
    // ============================================================

    @IsTest
    static void buildDescription_DeckSample01WithProductName() {
        // Deck Sample 01 with Product Name prepended.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => '15',
            'License_Type' => 'Subscription'
        };

        String result = hook.buildDescription('Click and Launch SAT', attrs);

        System.assertEquals('Click and Launch SAT | Users: 15 | Subscription', result);
    }

    @IsTest
    static void buildDescription_BeSecureCloudBasedWithNumberOfUnits() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Devices',
            'Number_of_Units' => '36-65',
            'Feature_Options' => 'One Time',
            'Server_Location_Type' => 'Cloud Based'
        };

        String result = hook.buildDescription('beSECURE - Cloud-Based', attrs);

        System.assertEquals(
            'beSECURE - Cloud-Based | Devices: 36-65 | One Time | Cloud Based',
            result
        );
    }

    @IsTest
    static void buildDescription_DeckSample02WithProductName() {
        // Deck Sample 02 with Product Name prepended.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'PS_Service_Type' => 'Prepaid'
        };

        String result = hook.buildDescription('Tripwire Services', attrs);

        System.assertEquals('Tripwire Services | Prepaid', result);
    }

    @IsTest
    static void buildDescription_NoProductNameStillRenders() {
        // If Product2 lookup fails or product has no name, render attributes only.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'PS_Service_Type' => 'Prepaid'
        };

        System.assertEquals('Prepaid', hook.buildDescription(null, attrs));
        System.assertEquals('Prepaid', hook.buildDescription('', attrs));
        System.assertEquals('Prepaid', hook.buildDescription('   ', attrs));
    }

    @IsTest
    static void buildDescription_AllTenSegmentsPopulated() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => '250',
            'License_Type' => 'Subscription',
            'PS_Service_Type' => 'Prepaid',
            'Feature_Options' => 'AdvancedAnalytics',
            'Maintenance_Type_Defn' => 'Premium',
            'Deployment_Option' => 'Cloud',
            'Server_Location_Type' => 'US-East',
            'Power_License_Type' => 'P30',
            'Server_Type' => 'Production',
            'Group_Number' => 'G7'
        };

        String result = hook.buildDescription('Test Product', attrs);

        System.assertEquals(
            'Test Product | Users: 250 | Subscription | Prepaid | AdvancedAnalytics | Premium | Cloud | US-East | P30 | Production | G7',
            result
        );
    }

    @IsTest
    static void buildDescription_EmptySegmentsAreSkipped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'License_Type' => 'Subscription',
            'PS_Service_Type' => '',
            'Feature_Options' => null,
            'Server_Type' => 'Production'
        };

        String result = hook.buildDescription('Test Product', attrs);

        System.assertEquals('Test Product | Subscription | Production', result);
    }

    @IsTest
    static void buildDescription_NullAttrsReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        // Even with a product name, no attrs means the line is non-configurable
        // and we preserve the existing Description.
        System.assertEquals(null, hook.buildDescription('Test Product', null));
    }

    @IsTest
    static void buildDescription_EmptyAttrsReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(null, hook.buildDescription('Test Product', new Map<String, String>()));
    }

    @IsTest
    static void buildDescription_AttrsAllBlankFallsBackToProductNameOnly() {
        // Line has attribute records but every value is empty — render
        // just the Product Name (the line IS configurable).
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'License_Type' => '',
            'PS_Service_Type' => null
        };

        System.assertEquals('Test Product', hook.buildDescription('Test Product', attrs));
    }

    @IsTest
    static void buildDescription_TruncatesAt4000() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String longValue = 'X'.repeat(4500);
        Map<String, String> attrs = new Map<String, String>{
            'License_Type' => longValue
        };

        String result = hook.buildDescription('Test Product', attrs);

        System.assertEquals(
            QLDescriptionGeneratorPrehook.DESCRIPTION_MAX_LENGTH,
            result.length(),
            'Description truncated to exactly 4000 chars'
        );
        System.assert(
            result.endsWith(QLDescriptionGeneratorPrehook.TRUNCATION_MARKER),
            'Truncation marker appended'
        );
    }

    // ============================================================
    // buildContextUpdate — pure function, validates the
    // updateContextAttributes payload shape
    // ============================================================

    @IsTest
    static void buildContextUpdate_DropsRootEntityFromDataPath() {
        // dataPath in the runtime context is [QuoteId, ..., QuoteLineItemId];
        // updateContextAttributes expects the path with the root entity
        // removed (same convention as COLAUpliftPrehook.buildItemUpdate).
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        List<Object> dataPath = new List<Object>{
            '0Q0xxxxxxxxxxxx', 'SalesTransactionItem', '0Q3yyyyyyyyyyyy'
        };

        Map<String, Object> result = hook.buildContextUpdate(dataPath, 'Users: 15');

        Map<String, Object> nodePath = (Map<String, Object>) result.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(2, updatePath.size(), 'Root entity dropped');
        System.assertEquals('SalesTransactionItem', String.valueOf(updatePath[0]));
        System.assertEquals('0Q3yyyyyyyyyyyy', String.valueOf(updatePath[1]));
    }

    @IsTest
    static void buildContextUpdate_TargetsHydrationMappedAttribute() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        List<Object> dataPath = new List<Object>{ '0Q0', '0Q3' };

        Map<String, Object> result = hook.buildContextUpdate(dataPath, 'Flat Fee: 5');

        List<Object> attrs = (List<Object>) result.get('attributes');
        System.assertEquals(1, attrs.size(), 'Single attribute in payload');
        Map<String, Object> attr = (Map<String, Object>) attrs[0];
        System.assertEquals('SalesTrxnItemDescription', attr.get('attributeName'),
            'Writes to the hydration-mapped Description attribute');
        System.assertEquals('Flat Fee: 5', attr.get('attributeValue'));
    }

    @IsTest
    static void buildContextUpdate_HandlesEmptyDataPath() {
        // Defensive: should not throw; emits an empty updatePath. The runtime
        // would reject this but our code must not blow up assembling it.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, Object> result = hook.buildContextUpdate(new List<Object>(), 'X');
        Map<String, Object> nodePath = (Map<String, Object>) result.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(0, updatePath.size());
    }

    // ============================================================
    // submitContextUpdates — empty/null no-op path
    // ============================================================

    @IsTest
    static void submitContextUpdates_NullListReturnsZero() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Integer count = hook.submitContextUpdates(null, 'fakeCtxId', null);
        System.assertEquals(0, count);
    }

    @IsTest
    static void submitContextUpdates_EmptyListReturnsZero() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Integer count = hook.submitContextUpdates(null, 'fakeCtxId', new List<Map<String, Object>>());
        System.assertEquals(0, count);
    }

    @IsTest
    static void submitContextUpdates_NonEmptyWithNullCtxSwallowsAndReturnsZero() {
        // A non-empty update list with a null ctx makes ctx.updateContextAttributes throw a
        // NullPointerException; the catch swallows it (generic-warning branch) and returns 0,
        // matching the swallow-and-continue contract.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        List<Map<String, Object>> updates = new List<Map<String, Object>>{
            hook.buildContextUpdate(new List<Object>{ '0Q0root', '0Q3leaf' }, 'X')
        };

        Integer count = hook.submitContextUpdates(null, 'fakeCtxId', updates);

        System.assertEquals(0, count, 'Failure is swallowed; returns 0 (never re-throws)');
    }

    // ============================================================
    // computeUnitTypeSegment / resolveUnitQuantity — null-arg guards
    // ============================================================

    @IsTest
    static void computeUnitTypeSegment_NullAttrsReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(null, hook.computeUnitTypeSegment(null));
    }

    @IsTest
    static void resolveUnitQuantity_NullAttrsReturnsNull() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(null, hook.resolveUnitQuantity(null));
    }

    @IsTest
    static void buildDescription_AllSegmentsEmptyNoProductReturnsNull() {
        // attrs is non-empty (so not the early-empty null) but every value is
        // blank and there is no product name -> segments end up empty -> null.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'License_Type' => '',
            'Server_Type' => '   '
        };
        System.assertEquals(null, hook.buildDescription(null, attrs),
            'No product name + all-blank attrs -> empty segments -> null');
    }

    // ============================================================
    // queryProductNames — real Quote/QLI/Product2 SOQL + early return
    // ============================================================

    @IsTest
    static void queryProductNames_EmptySetReturnsEmpty() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(0, hook.queryProductNames(new Set<Id>()).size(),
            'Empty set short-circuits before SOQL');
        System.assertEquals(0, hook.queryProductNames(null).size(),
            'Null set short-circuits before SOQL');
    }

    @IsTest
    static void queryProductNames_RealLineReturnsProductName() {
        Id qliId = createQuoteLineItem('QLDesc Product Name Test');

        Test.startTest();
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<Id, String> names = hook.queryProductNames(new Set<Id>{ qliId });
        Test.stopTest();

        System.assertEquals(1, names.size(), 'One line in scope');
        System.assertEquals('QLDesc Product Name Test', names.get(qliId),
            'Product2.Name mapped to the QuoteLineItem Id');
    }

    // ============================================================
    // buildContextUpdate — dataPath clone/remove(0) + attribute payload
    // ============================================================

    @IsTest
    static void buildContextUpdate_ClonesDataPathAndTargetsDescription() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        List<Object> dataPath = new List<Object>{ '0Q0root', 'SalesTransactionItem', '0Q3leaf' };

        Map<String, Object> nodeUpdate = hook.buildContextUpdate(dataPath, 'Users: 7');

        // Original dataPath must not be mutated (clone, not in-place remove).
        System.assertEquals(3, dataPath.size(), 'Source dataPath is cloned, not mutated');
        Map<String, Object> nodePath = (Map<String, Object>) nodeUpdate.get('nodePath');
        List<Object> updatePath = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(2, updatePath.size(), 'Root entity dropped via remove(0)');
        List<Object> attrs = (List<Object>) nodeUpdate.get('attributes');
        Map<String, Object> attr = (Map<String, Object>) attrs[0];
        System.assertEquals('SalesTrxnItemDescription', attr.get('attributeName'));
        System.assertEquals('Users: 7', attr.get('attributeValue'));
    }

    // ============================================================
    // parseConfiguredAttributes — the SalesTransactionItemAttribute parse
    // ============================================================

    @IsTest
    static void parseConfiguredAttributes_NullAndEmptyReturnEmpty() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(0, hook.parseConfiguredAttributes(null).size(),
            'Null response returns empty');
        System.assertEquals(0, hook.parseConfiguredAttributes(new Map<String, Object>()).size(),
            'Response without queryResult returns empty');
    }

    @IsTest
    static void parseConfiguredAttributes_ParentReferenceGroupsByLine() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // Two attributes on the same line via explicit ParentReference; the
        // nested-tagValue layout with an empty dataPath.
        Map<String, Object> node1 = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'ParentReference' => lineId,
                'Attribute' => 'License_Type',
                'AttributeValue' => 'Subscription'
            },
            new List<Object>()
        );
        Map<String, Object> node2 = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'ParentReference' => lineId,
                'Attribute' => 'Server_Type',
                'AttributeValue' => 'Production'
            },
            new List<Object>()
        );
        Map<String, Object> response = buildAttrResponse(new List<Object>{ node1, node2 });

        Map<Id, Map<String, String>> result = hook.parseConfiguredAttributes(response);

        System.assertEquals(1, result.size(), 'Both attributes group under one line Id');
        System.assertEquals('Subscription', result.get(lineId).get('License_Type'));
        System.assertEquals('Production', result.get(lineId).get('Server_Type'));
    }

    @IsTest
    static void parseConfiguredAttributes_ParentFromDataPathAndKeyNameFallback() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // No ParentReference -> parent resolved from dataPath[size-2]; and the
        // attribute name comes from AttributeKeyName (Attribute absent).
        Map<String, Object> node = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'AttributeKeyName' => 'PS_Service_Type',
                'AttributeValue' => 'Prepaid'
            },
            new List<Object>{ 'SalesTransactionItem', lineId, 'attrLeaf' }
        );
        Map<String, Object> response = buildAttrResponse(new List<Object>{ node });

        Map<Id, Map<String, String>> result = hook.parseConfiguredAttributes(response);

        System.assertEquals(1, result.size());
        System.assertEquals('Prepaid', result.get(lineId).get('PS_Service_Type'),
            'AttributeKeyName used when Attribute is blank; parent from dataPath');
    }

    @IsTest
    static void parseConfiguredAttributes_BadParentRefSkipped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();

        // ParentReference is not a valid Id -> Id.valueOf throws and the node is skipped.
        Map<String, Object> badNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'ParentReference' => 'NOT_AN_ID',
                'Attribute' => 'License_Type',
                'AttributeValue' => 'Subscription'
            },
            new List<Object>()
        );
        // A node with no parent reference at all (blank) -> skipped too.
        Map<String, Object> noParentNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'Attribute' => 'Server_Type',
                'AttributeValue' => 'Production'
            },
            new List<Object>()
        );
        Map<String, Object> response = buildAttrResponse(new List<Object>{ badNode, noParentNode });

        System.assertEquals(0, hook.parseConfiguredAttributes(response).size(),
            'Invalid and missing parent references are skipped');
    }

    @IsTest
    static void parseConfiguredAttributes_NullNodeAndNonMapTagValueSkipped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // A null raw node (skipped), a node whose tagValue is not a Map (tagMap
        // resolves null -> skipped), and one good node so the loop still runs.
        Map<String, Object> nonMapTagValue = new Map<String, Object>{
            'tagValue' => 'not-a-map',
            'dataPath' => new List<Object>()
        };
        Map<String, Object> goodNode = PricingPrehookTestFixtures.itemNode(
            new Map<String, Object>{
                'ParentReference' => lineId,
                'Attribute' => 'Group_Number',
                'AttributeValue' => 'G7'
            },
            new List<Object>()
        );
        List<Object> nodes = new List<Object>{ null, nonMapTagValue, goodNode };
        Map<String, Object> response = buildAttrResponse(nodes);

        Map<Id, Map<String, String>> result = hook.parseConfiguredAttributes(response);

        System.assertEquals(1, result.size(), 'Only the good node survives');
        System.assertEquals('G7', result.get(lineId).get('Group_Number'));
    }

    @IsTest
    static void parseConfiguredAttributes_NestedTagValueWrapperAndNullField() {
        // Exercises extractFieldValue's nested {tagValue:...} wrapper branch and
        // its explicit-null-field branch.
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        Map<String, Object> tagMap = new Map<String, Object>{
            // ParentReference as a nested {tagValue:...} wrapper.
            'ParentReference' => new Map<String, Object>{ 'tagValue' => lineId },
            // Attribute present-but-null forces the AttributeKeyName fallback.
            'Attribute' => null,
            'AttributeKeyName' => 'Feature_Options',
            // AttributeValue as a nested wrapper too.
            'AttributeValue' => new Map<String, Object>{ 'tagValue' => 'One Time' }
        };
        Map<String, Object> node = PricingPrehookTestFixtures.itemNode(tagMap, new List<Object>());
        Map<String, Object> response = buildAttrResponse(new List<Object>{ node });

        Map<Id, Map<String, String>> result = hook.parseConfiguredAttributes(response);

        System.assertEquals(1, result.size());
        System.assertEquals('One Time', result.get(lineId).get('Feature_Options'),
            'Nested tagValue wrappers unwrapped; AttributeKeyName fallback used for null Attribute');
    }

    @IsTest
    static void parseConfiguredAttributes_FlatShapeAndSingleObject() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // Flat shape: SalesTransactionItemAttribute at top level, and the value
        // is a single map (not a list) -> wrapped into a one-element list. Also
        // exercises the flat-node layout (no tagValue wrapper).
        Map<String, Object> flatNode = new Map<String, Object>{
            'ParentReference' => lineId,
            'Attribute' => 'Deployment_Option',
            'AttributeValue' => 'Cloud'
        };
        Map<String, Object> response = new Map<String, Object>{
            'SalesTransactionItemAttribute' => flatNode
        };

        Map<Id, Map<String, String>> result = hook.parseConfiguredAttributes(response);

        System.assertEquals(1, result.size(), 'Flat single-object response parses');
        System.assertEquals('Cloud', result.get(lineId).get('Deployment_Option'));
    }

    // ============================================================
    // parseLineItemDataPaths — the SalesTransactionItem parse
    // ============================================================

    @IsTest
    static void parseLineItemDataPaths_NullAndEmptyReturnEmpty() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        System.assertEquals(0, hook.parseLineItemDataPaths(null).size());
        System.assertEquals(0, hook.parseLineItemDataPaths(new Map<String, Object>()).size());
    }

    @IsTest
    static void parseLineItemDataPaths_ValidLastElementMapped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        Map<String, Object> itemNode = new Map<String, Object>{
            'dataPath' => new List<Object>{ '0Q0root', 'SalesTransactionItem', lineId }
        };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ itemNode }
            }
        };

        Map<Id, List<Object>> result = hook.parseLineItemDataPaths(response);

        System.assertEquals(1, result.size(), 'Valid Id last element mapped');
        System.assertEquals(3, result.get(lineId).size(), 'Full dataPath retained');
    }

    @IsTest
    static void parseLineItemDataPaths_NullNodeAndNonMapSkipped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // A null raw item and a non-map raw item are both skipped; a good node
        // still maps so the loop body runs.
        Map<String, Object> goodNode = new Map<String, Object>{
            'dataPath' => new List<Object>{ '0Q0root', lineId }
        };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ null, 'not-a-map', goodNode }
            }
        };

        Map<Id, List<Object>> result = hook.parseLineItemDataPaths(response);

        System.assertEquals(1, result.size(), 'Null/non-map nodes skipped; good node mapped');
        System.assertEquals(2, result.get(lineId).size());
    }

    @IsTest
    static void parseLineItemDataPaths_SingleObjectNotList() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        String lineId = fakeId(QuoteLineItem.SObjectType);

        // SalesTransactionItem is a single map, not a list -> wrapped into a
        // one-element list by the parser.
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new Map<String, Object>{
                    'dataPath' => new List<Object>{ '0Q0root', lineId }
                }
            }
        };

        Map<Id, List<Object>> result = hook.parseLineItemDataPaths(response);
        System.assertEquals(1, result.size(), 'Single-object response parses');
    }

    @IsTest
    static void parseLineItemDataPaths_InvalidLastElementSkipped() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();

        // dataPath whose last element is not an Id -> Id.valueOf throws, skipped.
        Map<String, Object> badNode = new Map<String, Object>{
            'dataPath' => new List<Object>{ 'SalesTransactionItem', 'not-an-id' }
        };
        // dataPath empty -> skipped before Id.valueOf.
        Map<String, Object> emptyNode = new Map<String, Object>{
            'dataPath' => new List<Object>()
        };
        // dataPath missing entirely -> skipped.
        Map<String, Object> noDataPathNode = new Map<String, Object>{ 'foo' => 'bar' };
        Map<String, Object> response = new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItem' => new List<Object>{ badNode, emptyNode, noDataPathNode }
            }
        };

        System.assertEquals(0, hook.parseLineItemDataPaths(response).size(),
            'Invalid / empty / missing dataPaths all skipped');
    }

    // ============================================================
    // buildContextUpdates — the Step-4 build loop (end-to-end)
    // ============================================================

    @IsTest
    static void buildContextUpdates_BuildsSkipsNullAndAbsentDataPath() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Id lineWithUpdate = fakeId(QuoteLineItem.SObjectType);
        Id lineNullDesc = Id.valueOf(QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000002');
        Id lineNoDataPath = Id.valueOf(QuoteLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000003');

        Map<Id, Map<String, String>> attrsByLineId = new Map<Id, Map<String, String>>{
            // Builds an update (attrs + product name produce a non-empty description).
            lineWithUpdate => new Map<String, String>{ 'License_Type' => 'Subscription' },
            // All attribute values blank -> buildDescription returns the product
            // name only (still an update); to force the null-description skip we
            // give an empty attribute map, which buildDescription returns null for.
            lineNullDesc => new Map<String, String>(),
            // Present in attrs but absent from dataPath -> defensive continue.
            lineNoDataPath => new Map<String, String>{ 'Server_Type' => 'Production' }
        };
        Map<Id, List<Object>> dataPathByLineId = new Map<Id, List<Object>>{
            lineWithUpdate => new List<Object>{ '0Q0root', lineWithUpdate },
            lineNullDesc => new List<Object>{ '0Q0root', lineNullDesc }
            // lineNoDataPath intentionally omitted
        };
        Map<Id, String> productNameByLineId = new Map<Id, String>{
            lineWithUpdate => 'Click and Launch SAT'
        };

        List<Map<String, Object>> updates = hook.buildContextUpdates(
            attrsByLineId, dataPathByLineId, productNameByLineId
        );

        System.assertEquals(1, updates.size(),
            'Only the line with attrs + a non-null description yields an update');
        Map<String, Object> nodePath = (Map<String, Object>) updates[0].get('nodePath');
        List<Object> path = (List<Object>) nodePath.get('dataPath');
        System.assertEquals(1, path.size(), 'Root dropped from the kept line dataPath');
    }

    // ============================================================
    // execute() — null-request control flow only.
    //
    // Note: RevSignaling.TransactionRequest is a managed-package class with
    // no public constructor, so the request cannot be constructed in a unit
    // test (see HardwareAttributePricingPrehookTest:303 for the same note).
    // The blank-context-id branch and the full pipeline are exercised via
    // integration testing in fortrauat per the implementation plan.
    // ============================================================

    @IsTest
    static void execute_NullRequestReturnsFailed() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();

        RevSignaling.TransactionResponse response = hook.execute(null);

        System.assertEquals(RevSignaling.TransactionStatus.FAILED, response.status);
        System.assert(response.message.contains('required'), 'Message mentions required: ' + response.message);
    }

    @IsTest
    static void prehookInstantiates() {
        Test.startTest();
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Test.stopTest();
        System.assertNotEquals(null, hook, 'Prehook should be instantiated');
    }

    @IsTest
    static void prehookImplementsSignalingInterface() {
        // Compile-time check: assigning the prehook to its declared interface
        // proves the implements clause is correct.
        RevSignaling.SignalingApexProcessor processor = new QLDescriptionGeneratorPrehook();
        System.assertNotEquals(null, processor);
    }

    // ============================================================
    // ResolvedConfig + config-aware overloads (Task 2)
    // ============================================================

    @IsTest
    static void defaultConfig_MatchesLegacyHardcodedList() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type' => 'Per User',
            'Attribute_Volume' => '15',
            'License_Type' => 'Subscription'
        };

        // The config-aware overload, fed the default config, must equal the
        // legacy no-config overload byte-for-byte.
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.defaultConfig();
        String viaConfig = hook.buildDescription('Click and Launch SAT', attrs, cfg);
        String viaLegacy = hook.buildDescription('Click and Launch SAT', attrs);

        System.assertEquals('Click and Launch SAT | Users: 15 | Subscription', viaConfig);
        System.assertEquals(viaLegacy, viaConfig, 'Default config path equals legacy path');
    }

    // ============================================================
    // Data-driven config: loader + de-dup + capabilities (Task 3)
    // ============================================================

    private static QL_Description_Attribute__mdt row(String api, String role, Decimal sortOrder, String match) {
        return new QL_Description_Attribute__mdt(
            Attribute_API_Name__c = api, Role__c = role, Sort_Order__c = sortOrder,
            Active__c = true, Match_Value__c = match
        );
    }

    @IsTest
    static void config_RenameSwapsSegmentName() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        // Feature_Options renamed to Feature_Selection_New.
        List<QL_Description_Attribute__mdt> rows = new List<QL_Description_Attribute__mdt>{
            row('Feature_Selection_New', 'Segment', 30, null)
        };
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(rows);
        Map<String, String> attrs = new Map<String, String>{ 'Feature_Selection_New' => 'One Time' };

        System.assertEquals('P | One Time', hook.buildDescription('P', attrs, cfg),
            'New name is read; renamed segment still appears');
    }

    @IsTest
    static void config_OneToManySplitProducesMultipleSegments() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        // Feature_Options split into two new attributes, ordered 30 then 35.
        List<QL_Description_Attribute__mdt> rows = new List<QL_Description_Attribute__mdt>{
            row('Feature_A', 'Segment', 30, null),
            row('Feature_B', 'Segment', 35, null)
        };
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(rows);
        Map<String, String> attrs = new Map<String, String>{ 'Feature_A' => 'Alpha', 'Feature_B' => 'Beta' };

        System.assertEquals('P | Alpha | Beta', hook.buildDescription('P', attrs, cfg),
            'Split yields two segments in sort order');
    }

    @IsTest
    static void config_SortOrderHonored() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        // Provide rows out of order; expect sort by Sort_Order__c.
        List<QL_Description_Attribute__mdt> rows = new List<QL_Description_Attribute__mdt>{
            row('Second', 'Segment', 20, null),
            row('First', 'Segment', 10, null)
        };
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(rows);
        Map<String, String> attrs = new Map<String, String>{ 'First' => '1', 'Second' => '2' };

        System.assertEquals('P | 1 | 2', hook.buildDescription('P', attrs, cfg));
    }

    @IsTest
    static void config_CutoverOverlapDeDupsByValue() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        // Old + new names both active during cutover; line carries both with
        // the same value -> the value renders once.
        List<QL_Description_Attribute__mdt> rows = new List<QL_Description_Attribute__mdt>{
            row('Feature_Options', 'Segment', 30, null),
            row('Feature_Options_New', 'Segment', 31, null)
        };
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(rows);
        Map<String, String> attrs = new Map<String, String>{
            'Feature_Options' => 'One Time', 'Feature_Options_New' => 'One Time'
        };

        System.assertEquals('P | One Time', hook.buildDescription('P', attrs, cfg),
            'Duplicate segment value collapses to one');
    }

    @IsTest
    static void config_UnitAttributeRenameStillComputesUsers() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        List<QL_Description_Attribute__mdt> rows = new List<QL_Description_Attribute__mdt>{
            row('Unit_Type_New', 'Unit Type', null, 'Per User'),
            row('Unit_Volume_New', 'Unit Quantity', null, null)
        };
        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(rows);
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type_New' => 'Per User', 'Unit_Volume_New' => '15'
        };

        System.assertEquals('Users: 15', hook.computeUnitTypeSegment(attrs, cfg));
    }

    @IsTest
    static void loadConfig_EmptyOverrideFallsBackToDefaults() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        QLDescriptionGeneratorPrehook.configOverride = new List<QL_Description_Attribute__mdt>();

        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.loadConfig();
        Map<String, String> attrs = new Map<String, String>{ 'License_Type' => 'Subscription' };

        System.assertEquals('P | Subscription', hook.buildDescription('P', attrs, cfg),
            'Empty config -> default list (today behavior)');
    }

    @IsTest
    static void loadConfig_PopulatedOverrideUsesRows() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        QLDescriptionGeneratorPrehook.configOverride = new List<QL_Description_Attribute__mdt>{
            row('Only_Attr', 'Segment', 10, null)
        };

        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.loadConfig();
        Map<String, String> attrs = new Map<String, String>{ 'Only_Attr' => 'X', 'License_Type' => 'Ignored' };

        System.assertEquals('P | X', hook.buildDescription('P', attrs, cfg),
            'Config rows drive the list; legacy names not consulted');
    }

    @IsTest
    static void loadConfig_LiveSeedsReproduceDefaults() {
        // Explicitly null the test seam so loadConfig() runs the real queryActiveConfig()
        // SOQL against the deployed QL_Description_Attribute__mdt seed rows.
        // This proves the deployed seed rows reproduce today's behavior (the inert-rollout
        // guarantee). EXPECTED to need updating at cutover when new attribute rows diverge
        // from the in-code defaults.
        QLDescriptionGeneratorPrehook.configOverride = null;

        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Map<String, String> attrs = new Map<String, String>{
            'Unit_Type'              => 'Per User',
            'Attribute_Volume'       => '250',
            'License_Type'           => 'Subscription',
            'PS_Service_Type'        => 'Prepaid',
            'Feature_Options'        => 'AdvancedAnalytics',
            'Maintenance_Type_Defn'  => 'Premium',
            'Deployment_Option'      => 'Cloud',
            'Server_Location_Type'   => 'US-East',
            'Power_License_Type'     => 'P30',
            'Server_Type'            => 'Production',
            'Group_Number'           => 'G7'
        };

        String expectedDescription =
            'Test Product | Users: 250 | Subscription | Prepaid | AdvancedAnalytics | Premium | Cloud | US-East | P30 | Production | G7';
        String viaLive    = hook.buildDescription('Test Product', attrs, hook.loadConfig());
        String viaDefault = hook.buildDescription('Test Product', attrs, hook.defaultConfig());

        System.assertEquals(expectedDescription, viaLive,
            'Live SOQL config must equal the expected description');
        System.assertEquals(viaDefault, viaLive,
            'Live SOQL config must equal the in-code defaults (inert-rollout guarantee)');
    }

    // ============================================================
    // Task 4: buildContextUpdates 4-arg overload (config-threaded)
    // ============================================================

    @IsTest
    static void buildContextUpdates_UsesProvidedConfig() {
        QLDescriptionGeneratorPrehook hook = new QLDescriptionGeneratorPrehook();
        Id lineId = fakeId(QuoteLineItem.SObjectType);

        QLDescriptionGeneratorPrehook.ResolvedConfig cfg = hook.buildResolvedConfig(
            new List<QL_Description_Attribute__mdt>{ row('Renamed_Attr', 'Segment', 10, null) }
        );
        Map<Id, Map<String, String>> attrsByLineId = new Map<Id, Map<String, String>>{
            lineId => new Map<String, String>{ 'Renamed_Attr' => 'NewVal' }
        };
        Map<Id, List<Object>> dataPathByLineId = new Map<Id, List<Object>>{
            lineId => new List<Object>{ '0Q0root', lineId }
        };
        Map<Id, String> productNameByLineId = new Map<Id, String>{ lineId => 'Prod' };

        List<Map<String, Object>> updates = hook.buildContextUpdates(
            attrsByLineId, dataPathByLineId, productNameByLineId, cfg
        );

        System.assertEquals(1, updates.size());
        List<Object> attrList = (List<Object>) updates[0].get('attributes');
        Map<String, Object> attr = (Map<String, Object>) attrList[0];
        System.assertEquals('Prod | NewVal', attr.get('attributeValue'),
            'execute()-path build honors the provided config');
    }

    // ============================================================
    // Fixture helpers
    // ============================================================

    /**
     * @description Construct a syntactically valid 15-char Id for the given
     *              SObject type without inserting anything.
     */
    private static Id fakeId(Schema.SObjectType sot) {
        String prefix = sot.getDescribe().getKeyPrefix();
        return Id.valueOf(prefix + '000000000001');
    }

    /**
     * @description Wrap a list of parsed SalesTransactionItemAttribute nodes in the nested
     *              {queryResult:{SalesTransactionItemAttribute:[...]}} response shape that
     *              queryTags returns.
     */
    private static Map<String, Object> buildAttrResponse(List<Object> attrNodes) {
        return new Map<String, Object>{
            'queryResult' => new Map<String, Object>{
                'SalesTransactionItemAttribute' => attrNodes
            }
        };
    }

    /**
     * @description Insert a real Quote + Product2 + PricebookEntry + QuoteLineItem and return the
     *              QuoteLineItem Id, for exercising queryProductNames' SOQL. Mirrors the
     *              Quote/QLI creation pattern from COLAUpliftTest (a Legal Entity is required so the
     *              before-save flow can copy LegalEntityId onto the QLI on insert).
     */
    private static Id createQuoteLineItem(String productName) {
        Account acct = new Account(Name = 'QLDesc Acct ' + String.valueOf(Crypto.getRandomLong()).right(8));
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(acct, dml);

        LegalEntity le = new LegalEntity(Name = 'QLDesc Legal Entity', Status = 'Active');
        insert le;

        Opportunity opp = new Opportunity(
            Name = 'QLDesc Opp', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Id stdPricebookId = Test.getStandardPricebookId();
        Quote q = new Quote(
            Name = 'QLDesc Quote', OpportunityId = opp.Id,
            LegalEntityId = le.Id, Pricebook2Id = stdPricebookId
        );
        insert q;

        Product2 prod = new Product2(Name = productName, ProductCode = 'QLDESC-TEST', IsActive = true);
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPricebookId, Product2Id = prod.Id, UnitPrice = 1000, IsActive = true
        );
        insert pbe;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 1000
        );
        insert qli;
        return qli.Id;
    }
}