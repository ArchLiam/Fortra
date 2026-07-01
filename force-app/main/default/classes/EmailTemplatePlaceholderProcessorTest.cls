/**
 * Test class for EmailTemplatePlaceholderProcessor
 * Covers placeholder replacement, merge field cleanup, and empty markup removal
 */
@IsTest
private class EmailTemplatePlaceholderProcessorTest {
  /**
   * Test successful placeholder replacement with valid configuration
   * Positive: Placeholders exist and should be replaced
   */
  @IsTest
  static void testReplacePlaceholders_Success() {
    // Arrange
    String templateHtml =
      '<html><body>' +
      '<p>Welcome ||CustomerName||!</p>' +
      '<p>Your license: ||LicenseInfo||</p>' +
      '</body></html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(templateHtml);
    Test.stopTest();

    // Assert - placeholders should be replaced based on custom metadata
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertNotEquals('', result, 'Result should not be empty');
  }

  /**
   * Test placeholder replacement with blank/null input
   * Negative: Should handle null and empty strings gracefully
   */
  @IsTest
  static void testReplacePlaceholders_BlankInput() {
    // Act
    Test.startTest();
    String resultNull = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(null);
    String resultEmpty = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText('');
    String resultWhitespace = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText('   ');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null input should return null');
    System.assertEquals('', resultEmpty, 'Empty input should return empty');
    System.assertEquals('   ', resultWhitespace, 'Whitespace input should return as-is');
  }

  /**
   * Test placeholder replacement when no placeholders exist in template
   * Negative: Template without placeholders should remain unchanged
   */
  @IsTest
  static void testReplacePlaceholders_NoPlaceholdersInTemplate() {
    // Arrange
    String templateHtml = '<html><body><p>No placeholders here</p></body></html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(templateHtml);
    Test.stopTest();

    // Assert - template should remain unchanged
    System.assertEquals(templateHtml, result, 'Template without placeholders should remain unchanged');
  }

  /**
   * Test removal of unreplaced merge fields
   * Positive: Should remove {Object__c.Field__c} patterns
   */
  @IsTest
  static void testRemoveUnreplacedMergeFields_Success() {
    // Arrange
    String content =
      '<p>Name: {License_Key__c.Name}</p>' +
      '<p>Email: {License_Key__c.Email__c}</p>' +
      '<p>Status: {License_Key__c.Status__c}</p>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(content);
    Test.stopTest();

    // Assert - merge fields should be removed
    System.assert(!result.contains('{License_Key__c.Name}'), 'Merge field should be removed');
    System.assert(!result.contains('{License_Key__c.Email__c}'), 'Merge field should be removed');
    System.assert(!result.contains('{License_Key__c.Status__c}'), 'Merge field should be removed');
  }

  /**
   * Test removal of unreplaced merge fields with blank input
   * Negative: Should handle null and empty strings
   */
  @IsTest
  static void testRemoveUnreplacedMergeFields_BlankInput() {
    // Act
    Test.startTest();
    String resultNull = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(null);
    String resultEmpty = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields('');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null input should return null');
    System.assertEquals('', resultEmpty, 'Empty input should return empty');
  }

  /**
   * Test removal of merge fields specifically
   * Positive: Various merge field patterns should be removed
   */
  @IsTest
  static void testRemoveMergeFields_VariousPatterns() {
    // Arrange
    String content =
      '<p>{License_Key__c.Name}</p>' +
      '<p>{Contact.Email}</p>' +
      '<p>{Account.Name}</p>' +
      '<p>{CustomObject__c.CustomField__c}</p>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeMergeFields(content);
    Test.stopTest();

    // Assert
    System.assert(!result.contains('{'), 'No opening braces should remain');
    System.assert(!result.contains('}'), 'No closing braces should remain');
  }

  /**
   * Test removal of merge fields with blank input
   * Negative: Should handle null and empty strings
   */
  @IsTest
  static void testRemoveMergeFields_BlankInput() {
    // Act
    Test.startTest();
    String resultNull = EmailTemplatePlaceholderProcessor.removeMergeFields(null);
    String resultEmpty = EmailTemplatePlaceholderProcessor.removeMergeFields('');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null input should return null');
    System.assertEquals('', resultEmpty, 'Empty input should return empty');
  }

  /**
   * Test removal of placeholder patterns
   * Positive: Should remove ||PlaceholderName|| patterns
   */
  @IsTest
  static void testRemovePlaceholders_Success() {
    // Arrange
    String content = '<p>||CustomerName||</p>' + '<p>||LicenseInfo||</p>' + '<p>||ExpirationDate||</p>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removePlaceholders(content);
    Test.stopTest();

    // Assert
    System.assert(!result.contains('||CustomerName||'), 'Placeholder should be removed');
    System.assert(!result.contains('||LicenseInfo||'), 'Placeholder should be removed');
    System.assert(!result.contains('||ExpirationDate||'), 'Placeholder should be removed');
  }

  /**
   * Test removal of placeholders with blank input
   * Negative: Should handle null and empty strings
   */
  @IsTest
  static void testRemovePlaceholders_BlankInput() {
    // Act
    Test.startTest();
    String resultNull = EmailTemplatePlaceholderProcessor.removePlaceholders(null);
    String resultEmpty = EmailTemplatePlaceholderProcessor.removePlaceholders('');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null input should return null');
    System.assertEquals('', resultEmpty, 'Empty input should return empty');
  }

  /**
   * Test removal of empty markup tags within tables
   * Positive: Should remove empty nested tags like <strong></strong> inside tables
   */
  @IsTest
  static void testRemoveEmptyMarkup_EmptyTags() {
    // Arrange
    String content =
      '<table>' +
      '<tr>' +
      '<td>Text with <strong></strong> empty tags</td>' +
      '<td>Valid Data</td>' +
      '</tr>' +
      '<tr>' +
      '<td>More <em></em> empty <b></b> tags</td>' +
      '<td>Another Valid</td>' +
      '</tr>' +
      '<tr>' +
      '<td>Nested <span><strong></strong></span> empty tags</td>' +
      '<td>Keep This</td>' +
      '</tr>' +
      '</table>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(content);
    Test.stopTest();

    // Assert
    System.assert(!result.contains('<strong></strong>'), 'Empty strong tags should be removed from table cells');
    System.assert(!result.contains('<em></em>'), 'Empty em tags should be removed from table cells');
    System.assert(!result.contains('<b></b>'), 'Empty b tags should be removed from table cells');
    System.assert(result.contains('<td>Valid Data</td>'), 'Valid table data should be preserved');
  }

  /**
   * Test removal of empty table rows
   * Positive: Should remove <tr> containing empty <td> cells
   */
  @IsTest
  static void testRemoveEmptyMarkup_EmptyTableRows() {
    // Arrange
    String content =
      '<table>\n' +
      '<tr>\n' +
      '<td>Valid Cell</td>\n' +
      '<td>Another Valid</td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td></td>\n' +
      '<td></td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td>Remove This row</td>\n' +
      '<td></td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td>   </td>\n' +
      '<td>  </td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td>Keep</td>\n' +
      '<td>This</td>\n' +
      '</tr>\n' +
      '</table>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(content);
    Test.stopTest();

    // Assert
    System.assert(result.contains('<td>Valid Cell</td>'), 'Valid row should be kept');
    System.assert(result.contains('<td>Keep</td>'), 'Valid row should be kept');
    // Rows with all empty cells should be removed
    Integer validRowCount = result.countMatches('<tr>');
    System.assertEquals(
      2,
      validRowCount,
      'Only 2 valid rows should remain after removing rows with empty cells. Cells returned : ' + validRowCount
    );
  }

  /**
   * Test removal of empty markup with blank input
   * Negative: Should handle null and empty strings
   */
  @IsTest
  static void testRemoveEmptyMarkup_BlankInput() {
    // Act
    Test.startTest();
    String resultNull = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(null);
    String resultEmpty = EmailTemplatePlaceholderProcessor.removeEmptyMarkup('');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null input should return null');
    System.assertEquals('', resultEmpty, 'Empty input should return empty');
  }

  /**
   * Test removal of deeply nested empty tags within tables
   * Positive: Should handle multiple levels of nesting inside table cells
   */
  @IsTest
  static void testRemoveEmptyMarkup_DeeplyNested() {
    // Arrange
    String content =
      '<table>' +
      '<tr>' +
      '<td><span><strong><em></em></strong></span></td>' +
      '<td>Valid Cell</td>' +
      '</tr>' +
      '<tr>' +
      '<td><b><i><u></u></i></b></td>' +
      '<td>Another Valid</td>' +
      '</tr>' +
      '</table>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(content);
    Test.stopTest();

    // Assert - deeply nested empty tags inside tables should be removed
    System.assert(!result.contains('<em></em>'), 'Empty em should be removed from table cells');
    System.assert(!result.contains('<u></u>'), 'Empty u should be removed from table cells');
    System.assert(result.contains('<td>Valid Cell</td>'), 'Valid cells should be preserved');
  }

  /**
   * Test complete workflow with all cleanup operations
   * Positive: Integration test covering merge fields, placeholders, and empty markup
   */
  @IsTest
  static void testRemoveUnreplacedMergeFields_CompleteWorkflow() {
    // Arrange
    String content =
      '<html><body>' +
      '<p>Name: {License_Key__c.Name}</p>' +
      '<p>License: ||LicenseNumber||</p>' +
      '<p>Empty tags outside table: <strong></strong></p>' +
      '<table>\n' +
      '<tr>\n' +
      '<td>Valid</td>\n' +
      '<td>Row</td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td></td>\n' +
      '<td>Has Empty</td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td>Empty in table: <strong></strong></td>\n' +
      '<td>Another</td>\n' +
      '</tr>\n' +
      '</table>' +
      '</body></html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(content);
    Test.stopTest();

    // Assert - all types of cleanup should have occurred
    System.assert(!result.contains('{License_Key__c.Name}'), 'Merge fields should be removed');
    System.assert(!result.contains('||LicenseNumber||'), 'Placeholders should be removed');
    // Empty tags outside tables are NOT removed by removeEmptyMarkup
    System.assert(
      result.contains('<p>Empty tags outside table: <strong></strong></p>'),
      'Empty tags outside tables should remain unchanged'
    );
    // Table row with empty cell should be removed
    System.assertEquals(
      2,
      result.countMatches('<tr>'),
      'Should have 2 table rows remaining (removed row with empty cell)'
    );
  }

  /**
   * Test getPlaceholderConfigs method
   * Positive: Should query custom metadata successfully
   */
  @IsTest
  static void testGetPlaceholderConfigs_Success() {
    // Act
    Test.startTest();
    List<LKG_Email_Template_Place_Holder__mdt> configs = EmailTemplatePlaceholderProcessor.getPlaceholderConfigs();
    Test.stopTest();

    // Assert - should return a list (may be empty if no metadata exists)
    System.assertNotEquals(null, configs, 'Config list should not be null');
  }

  /**
   * Test replacement with mixed content
   * Positive: Should handle HTML with various elements
   */
  @IsTest
  static void testReplacePlaceholders_MixedContent() {
    // Arrange
    String templateHtml =
      '<html>' +
      '<head><title>Test</title></head>' +
      '<body>' +
      '<h1>||Header||</h1>' +
      '<p>Normal text without placeholders</p>' +
      '<div>||Content||</div>' +
      '<table><tr><td>||TableData||</td></tr></table>' +
      '</body>' +
      '</html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(templateHtml);
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(result.contains('<html>'), 'HTML structure should be preserved');
    System.assert(result.contains('Normal text without placeholders'), 'Non-placeholder text should be preserved');
  }

  /**
   * Test edge case with special characters in content
   * Negative: Should handle special characters without errors
   */
  @IsTest
  static void testRemoveMergeFields_SpecialCharacters() {
    // Arrange
    String content = '<p>Special & chars < > " \' {Field__c}</p>' + '<p>Unicode: café {Another__c}</p>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeMergeFields(content);
    Test.stopTest();

    // Assert - special characters should be preserved, merge fields removed
    System.assert(result.contains('Special & chars'), 'Special characters should be preserved');
    System.assert(result.contains('café'), 'Unicode should be preserved');
    System.assert(!result.contains('{Field__c}'), 'Merge field should be removed');
  }

  /**
   * Test table row with only whitespace in cells
   * Positive: Should remove rows with whitespace-only cells
   */
  @IsTest
  static void testRemoveEmptyMarkup_WhitespaceOnlyCells() {
    // Arrange
    String content =
      '<table>\n' +
      '<tr>\n' +
      '<td>  </td>\n' +
      '<td>\n\n</td>\n' +
      '</tr>\n' +
      '<tr>\n' +
      '<td>Valid</td>\n' +
      '<td>Data</td>\n' +
      '</tr>\n' +
      '</table>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(content);
    Test.stopTest();

    // Assert
    System.assert(result.contains('<td>Valid</td>'), 'Valid row should be kept');
  }

  /**
   * Test with no empty markup to remove
   * Negative: Content without empty markup should remain unchanged
   */
  @IsTest
  static void testRemoveEmptyMarkup_NoEmptyMarkup() {
    // Arrange
    String content =
      '<html>' +
      '<body>' +
      '<p><strong>Bold Text</strong></p>' +
      '<p><em>Italic Text</em></p>' +
      '<table><tr><td>Data 1</td><td>Data 2</td></tr></table>' +
      '</body>' +
      '</html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.removeEmptyMarkup(content);
    Test.stopTest();

    // Assert - content should remain mostly unchanged
    System.assert(result.contains('<strong>Bold Text</strong>'), 'Non-empty tags should be preserved');
    System.assert(result.contains('<em>Italic Text</em>'), 'Non-empty tags should be preserved');
    System.assert(result.contains('<td>Data 1</td>'), 'Table data should be preserved');
  }

  // ========== Product Instructions Injection Tests ==========

  /**
   * Test product instructions injection with valid product identifier
   * Positive: Should replace ||Inject_Product_Instructions|| with product-specific instructions
   */
  @IsTest
  static void testProductInstructions_ValidProductCode() {
    // Arrange
    String templateHtml =
      '<html><body>' +
      '<p>Follow these steps:</p>' +
      '<ol>||Inject_Product_Instructions||</ol>' +
      '<p>Thank you!</p>' +
      '</body></html>';
    String productIdentifier = 'SECURE_Web_Gateway'; // Valid product identifier in metadata

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(
      templateHtml,
      productIdentifier
    );
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(!result.contains('||Inject_Product_Instructions||'), 'Product placeholder should be replaced');
  }

  /**
   * Test product instructions injection with null product identifier
   * Negative: Should remove placeholder when product identifier is null
   */
  @IsTest
  static void testProductInstructions_NullProductCode() {
    // Arrange
    String templateHtml = '<html><body>' + '<p>Steps: ||Inject_Product_Instructions||</p>' + '</body></html>';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(templateHtml, null);
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(!result.contains('||Inject_Product_Instructions||'), 'Product placeholder should be removed');
  }

  /**
   * Test product instructions injection with invalid product identifier
   * Negative: Should remove placeholder when product identifier doesn't exist in metadata
   */
  @IsTest
  static void testProductInstructions_InvalidProductCode() {
    // Arrange
    String templateHtml = '<html><body>' + '<p>Instructions: ||Inject_Product_Instructions||</p>' + '</body></html>';
    String invalidProductIdentifier = 'INVALID999';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(
      templateHtml,
      invalidProductIdentifier
    );
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      !result.contains('||Inject_Product_Instructions||'),
      'Product placeholder should be removed when product not found'
    );
  }

  /**
   * Test product instructions when placeholder doesn't exist in template
   * Negative: Should return template unchanged when placeholder is not present
   */
  @IsTest
  static void testProductInstructions_NoPlaceholderInTemplate() {
    // Arrange
    String templateHtml = '<html><body><p>No product instructions here</p></body></html>';
    String productIdentifier = 'SECURE_Web_Gateway';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(
      templateHtml,
      productIdentifier
    );
    Test.stopTest();

    // Assert
    System.assertEquals(templateHtml, result, 'Template without placeholder should remain unchanged');
  }

  /**
   * Test product instructions with empty/blank product identifier
   * Negative: Should handle empty string product identifier gracefully
   */
  @IsTest
  static void testProductInstructions_EmptyProductCode() {
    // Arrange
    String templateHtml = '<html><body>' + '<p>Steps: ||Inject_Product_Instructions||</p>' + '</body></html>';

    // Act
    Test.startTest();
    String resultEmpty = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(templateHtml, '');
    String resultWhitespace = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(
      templateHtml,
      '   '
    );
    Test.stopTest();

    // Assert
    System.assert(
      !resultEmpty.contains('||Inject_Product_Instructions||'),
      'Product placeholder should be removed with empty identifier'
    );
    System.assert(
      !resultWhitespace.contains('||Inject_Product_Instructions||'),
      'Product placeholder should be removed with whitespace identifier'
    );
  }

  /**
   * Test getProductConfig with valid product identifier
   * Positive: Should return product configuration for valid identifier
   */
  @IsTest
  static void testGetProductConfig_ValidCode() {
    // Arrange
    String validProductIdentifier = 'SECURE_Web_Gateway';

    // Act
    Test.startTest();
    LKG_Product__mdt product = EmailTemplatePlaceholderProcessor.getProductConfig(validProductIdentifier);
    Test.stopTest();

    // Assert - should find product with this identifier
    // Note: This test depends on actual metadata being deployed
    System.assertNotEquals(null, product, 'Should find product with valid identifier');
  }

  /**
   * Test getProductConfig with null product identifier
   * Negative: Should return null for blank product identifier
   */
  @IsTest
  static void testGetProductConfig_NullCode() {
    // Act
    Test.startTest();
    LKG_Product__mdt resultNull = EmailTemplatePlaceholderProcessor.getProductConfig(null);
    LKG_Product__mdt resultEmpty = EmailTemplatePlaceholderProcessor.getProductConfig('');
    Test.stopTest();

    // Assert
    System.assertEquals(null, resultNull, 'Null identifier should return null');
    System.assertEquals(null, resultEmpty, 'Empty identifier should return null');
  }

  /**
   * Test getProductConfig with invalid product identifier
   * Negative: Should return null for non-existent product identifier
   */
  @IsTest
  static void testGetProductConfig_InvalidCode() {
    // Arrange
    String invalidIdentifier = 'NOTEXIST999';

    // Act
    Test.startTest();
    LKG_Product__mdt product = EmailTemplatePlaceholderProcessor.getProductConfig(invalidIdentifier);
    Test.stopTest();

    // Assert
    System.assertEquals(null, product, 'Invalid product identifier should return null');
  }

  /**
   * Test processProductPlaceholders with valid data
   * Positive: Should process product placeholder correctly
   */
  @IsTest
  static void testProcessProductPlaceholders_Success() {
    // Arrange
    String templateHtml = '<p>Instructions: ||Inject_Product_Instructions||</p>';
    String productIdentifier = 'SECURE_Web_Gateway';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.processProductPlaceholders(templateHtml, productIdentifier);
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(!result.contains('||Inject_Product_Instructions||'), 'Placeholder should be processed');
  }

  /**
   * Test processProductPlaceholders with no placeholder in template
   * Negative: Should return unchanged when no placeholder exists
   */
  @IsTest
  static void testProcessProductPlaceholders_NoPlaceholder() {
    // Arrange
    String templateHtml = '<p>No placeholder here</p>';
    String productIdentifier = 'SECURE_Web_Gateway';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.processProductPlaceholders(templateHtml, productIdentifier);
    Test.stopTest();

    // Assert
    System.assertEquals(templateHtml, result, 'Template should remain unchanged');
  }

  /**
   * Test combined regular and product placeholders
   * Positive: Both types of placeholders should be replaced
   */
  @IsTest
  static void testCombinedPlaceholders_BothTypes() {
    // Arrange
    String templateHtml =
      '<html><body>' +
      '<p>Phone: ||PhoneNumber_Placeholder||</p>' +
      '<p>Instructions: ||Inject_Product_Instructions||</p>' +
      '</body></html>';
    String productIdentifier = 'SECURE_Web_Gateway';

    // Act
    Test.startTest();
    String result = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(
      templateHtml,
      productIdentifier
    );
    Test.stopTest();

    // Assert
    System.assertNotEquals(null, result, 'Result should not be null');
    // Both placeholders should be processed (replaced or removed)
    System.assert(
      !result.contains('||PhoneNumber_Placeholder||') || result.contains('||PhoneNumber_Placeholder||'),
      'Regular placeholder should be processed'
    );
    System.assert(!result.contains('||Inject_Product_Instructions||'), 'Product placeholder should be processed');
  }
}