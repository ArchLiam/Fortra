/**
 * Utility class for processing email template placeholders
 * Replaces ||PlaceholderName|| with configured text from custom metadata
 */
public class EmailTemplatePlaceholderProcessor {
  /**
   * Replace placeholders in email template with configured text
   * Simply replaces ||PlaceholderName|| with Text_Injection__c value
   * Does NOT evaluate merge fields or check field values
   *
   * @param templateHtml The email template HTML content
   * @return HTML with placeholders replaced by Text_Injection__c content
   */
  public static String replacePlaceholdersWithInjectedText(String templateHtml) {
    return replacePlaceholdersWithInjectedText(templateHtml, null);
  }

  /**
   * Replace placeholders in email template with configured text
   * Replaces ||PlaceholderName|| with Text_Injection__c value from custom metadata
   * Replaces ||Inject_Product_Instructions|| with product-specific instructions
   *
   * @param templateHtml The email template HTML content
   * @param productIdentifier The unique product identifier to fetch instructions for (optional)
   * @return HTML with placeholders replaced by configured content
   */
  public static String replacePlaceholdersWithInjectedText(String templateHtml, String productIdentifier) {
    if (String.isBlank(templateHtml)) {
      return templateHtml;
    }

    System.debug('=== Replacing Placeholders ===');

    String processedHtml = templateHtml;

    // Process product-specific placeholders from LKG_Product__mdt
    processedHtml = processProductPlaceholders(processedHtml, productIdentifier);

    // Process regular placeholders from LKG_Email_Template_Place_Holder__mdt
    processedHtml = processRegularPlaceholders(processedHtml);

    System.debug('=== Placeholder Replacement Complete ===');
    return processedHtml;
  }

  /**
   * Process regular placeholders from LKG_Email_Template_Place_Holder__mdt
   *
   * @param templateHtml The email template HTML content
   * @return HTML with regular placeholders replaced
   */
  @TestVisible
  private static String processRegularPlaceholders(String templateHtml) {
    // Query all placeholder configurations
    List<LKG_Email_Template_Place_Holder__mdt> placeholders = getPlaceholderConfigs();

    if (placeholders.isEmpty()) {
      System.debug('No placeholder configurations found');
      return templateHtml;
    }

    String processedHtml = templateHtml;

    // Process each placeholder - simple string replacement
    for (LKG_Email_Template_Place_Holder__mdt placeholder : placeholders) {
      String placeholderToken = placeholder.Placeholder__c;
      String textInjection = placeholder.Text_Injection__c;

      if (String.isBlank(placeholderToken)) {
        System.debug('Skipping placeholder with empty token');
        continue;
      }

      // Check if placeholder exists in template
      if (!processedHtml.contains(placeholderToken)) {
        System.debug('Placeholder not found in template: ' + placeholderToken);
        continue;
      }

      // Replace placeholder with text injection (or empty string if null)
      String replacementText = String.isNotBlank(textInjection) ? textInjection : '';

      processedHtml = processedHtml.replace(placeholderToken, replacementText);
      System.debug(
        'Replaced placeholder: ' +
          placeholderToken +
          ' -> ' +
          (String.isNotBlank(replacementText) ? replacementText : 'Empty')
      );
    }

    return processedHtml;
  }

  /**
   * Process product-specific placeholders from LKG_Product__mdt
   * Replaces ||Inject_Product_Instructions|| with Email_Template_Instructions_Text__c
   * Replaces ||Additional_Instructions_Text|| with Email_Template_Additional_Text__c
   *
   * @param templateHtml The email template HTML content
   * @param productIdentifier The unique product identifier to fetch instructions for (optional)
   * @return HTML with product placeholders replaced
   */
  @TestVisible
  private static String processProductPlaceholders(String templateHtml, String productIdentifier) {
    String processedHtml = templateHtml;

    // Define placeholders
    String productPlaceholder = '||Inject_Product_Instructions||';
    String additionalPlaceholder = '||Additional_Instructions_Text||';

    // Check if any product placeholder exists in the template
    Boolean hasProductPlaceholder = processedHtml.contains(productPlaceholder);
    Boolean hasAdditionalPlaceholder = processedHtml.contains(additionalPlaceholder);

    if (!hasProductPlaceholder && !hasAdditionalPlaceholder) {
      System.debug('No product placeholders found in template');
      return processedHtml;
    }

    // Query product configuration
    LKG_Product__mdt product = getProductConfig(productIdentifier);

    if (product == null) {
      System.debug(
        'No product configuration found for product identifier: ' +
        (String.isNotBlank(productIdentifier) ? productIdentifier : 'null')
      );
      // Replace with empty string if no product found
      if (hasProductPlaceholder) {
        processedHtml = processedHtml.replace(productPlaceholder, '');
      }
      if (hasAdditionalPlaceholder) {
        processedHtml = processedHtml.replace(additionalPlaceholder, '');
      }
      return processedHtml;
    }

    // Replace product instructions placeholder
    if (hasProductPlaceholder) {
      String instructionsText = String.isNotBlank(product.Email_Template_Instructions_Text__c)
        ? product.Email_Template_Instructions_Text__c
        : '';

      processedHtml = processedHtml.replace(productPlaceholder, instructionsText);
      System.debug(
        'Replaced product instructions placeholder for product: ' +
          product.Label +
          ' -> ' +
          (String.isNotBlank(instructionsText) ? 'Instructions Text' : 'Empty')
      );
    }

    // Replace additional instructions placeholder
    if (hasAdditionalPlaceholder) {
      String additionalText = String.isNotBlank(product.Email_Template_Additional_Text__c)
        ? product.Email_Template_Additional_Text__c
        : '';

      processedHtml = processedHtml.replace(additionalPlaceholder, additionalText);
      System.debug(
        'Replaced additional instructions placeholder for product: ' +
          product.Label +
          ' -> ' +
          (String.isNotBlank(additionalText) ? 'Additional Instructions Text' : 'Empty')
      );
    }

    return processedHtml;
  }

  /**
   * Remove any unreplaced merge fields and placeholders from email content
   * Cleans up {License_Key__c.Field__c} and ||PlaceholderName|| patterns
   * Also removes <tr> rows that contain empty <td> cells
   */
  @TestVisible
  public static String removeUnreplacedMergeFields(String content) {
    if (String.isBlank(content)) {
      return content;
    }

    String cleaned = content;

    cleaned = removePlaceholders(cleaned);

    cleaned = removeMergeFields(cleaned);

    cleaned = removeEmptyMarkup(cleaned);

    return cleaned;
  }

  /**
   * Remove unreplaced merge fields from content
   * Removes patterns like {License_Key__c.Field__c} or {anything}
   *
   * @param content The content to clean
   * @return Content with merge fields removed
   */
  @TestVisible
  private static String removeMergeFields(String content) {
    if (String.isBlank(content)) {
      return content;
    }

    // Remove unreplaced merge fields: {License_Key__c.Field__c} or {anything}
    return content.replaceAll('\\{[^}]+\\}', '');
  }

  /**
   * Remove unreplaced placeholders from content
   * Removes patterns like ||PlaceholderName||
   *
   * @param content The content to clean
   * @return Content with placeholders removed
   */
  @TestVisible
  private static String removePlaceholders(String content) {
    if (String.isBlank(content)) {
      return content;
    }

    // Remove unreplaced placeholders: ||PlaceholderName||
    return content.replaceAll('\\|\\|[^|]+\\|\\|', '');
  }

  /**
   * Remove empty markup from content within tables only
   * Cleans up empty nested tags (e.g., <strong></strong>, <em></em>) only if they are inside <table> elements
   * and removes <tr> rows that contain empty <td> cells
   * Regular HTML outside tables is left unchanged
   *
   * @param content The content to clean
   * @return Content with empty markup removed from tables
   */
  @TestVisible
  private static String removeEmptyMarkup(String content) {
    if (String.isBlank(content)) {
      return content;
    }

    // Split content into table and non-table sections
    List<String> sections = new List<String>();
    Pattern tablePattern = Pattern.compile('(?is)(<table[^>]*>.*?</table>)');
    Matcher tableMatcher = tablePattern.matcher(content);

    Integer lastEnd = 0;

    while (tableMatcher.find()) {
      // Add non-table content before this table
      if (tableMatcher.start() > lastEnd) {
        sections.add(content.substring(lastEnd, tableMatcher.start()));
      }

      // Process the table content
      String tableContent = tableMatcher.group(1);
      String cleanedTable = cleanTableMarkup(tableContent);
      sections.add(cleanedTable);

      lastEnd = tableMatcher.end();
    }

    // Add any remaining non-table content
    if (lastEnd < content.length()) {
      sections.add(content.substring(lastEnd));
    }

    return String.join(sections, '');
  }

  /**
   * Clean up empty markup within a table
   * Removes empty nested tags and rows with empty cells
   *
   * @param tableContent The table HTML content
   * @return Cleaned table content
   */
  private static String cleanTableMarkup(String tableContent) {
    String cleaned = tableContent;

    // Clean up empty nested tags (e.g., <strong></strong>, <em></em>)
    // Repeat multiple times to handle deeply nested structures
    for (Integer i = 0; i < 5; i++) {
      cleaned = cleaned.replaceAll('(?i)<(strong|em|b|i|u|span)[^>]*>\\s*</\\1>', '');
    }

    // Remove <tr> rows that contain at least one empty <td>
    // Split into lines and process line by line for better control
    List<String> lines = cleaned.split('\n');
    List<String> result = new List<String>();
    String currentRow = '';
    Boolean inRow = false;
    Boolean hasEmptyCell = false;

    for (String line : lines) {
      String trimmedLine = line.trim();

      // Check if we're starting a table row
      if (trimmedLine.toLowerCase().startsWith('<tr')) {
        inRow = true;
        hasEmptyCell = false;
        currentRow = line + '\n';
      }
      // Check if we're ending a table row
      else if (trimmedLine.toLowerCase().startsWith('</tr>')) {
        currentRow += line + '\n';
        inRow = false;

        // Only add the row if it doesn't have empty cells
        if (!hasEmptyCell) {
          result.add(currentRow);
        }
        currentRow = '';
      }
      // Check if we're inside a row
      else if (inRow) {
        currentRow += line + '\n';

        // Check if this line contains an empty <td> cell
        // Matches: <td></td> or <td>   </td> or <td> \n </td>
        if (Pattern.matches('(?is).*<td[^>]*>\\s*</td>.*', trimmedLine)) {
          hasEmptyCell = true;
        }
      }
      // Not in a row, just add the line
      else {
        result.add(line + '\n');
      }
    }

    // Reconstruct the content
    cleaned = String.join(result, '');

    return cleaned;
  }

  /**
   * Get all placeholder configurations from custom metadata
   */
  @TestVisible
  private static List<LKG_Email_Template_Place_Holder__mdt> getPlaceholderConfigs() {
    return [
      SELECT Placeholder__c, Text_Injection__c
      FROM LKG_Email_Template_Place_Holder__mdt
      ORDER BY Placeholder__c
    ];
  }

  /**
   * Get product configuration from custom metadata
   *
   * @param productIdentifier The unique product identifier to query for (matches DeveloperName field)
   * @return The product configuration or null if not found
   */
  @TestVisible
  private static LKG_Product__mdt getProductConfig(String productIdentifier) {
    if (String.isBlank(productIdentifier)) {
      System.debug('Product identifier is blank, returning null');
      return null;
    }

    // Query by DeveloperName field
    List<LKG_Product__mdt> products = [
      SELECT Label, DeveloperName, Email_Template_Instructions_Text__c, Email_Template_Additional_Text__c
      FROM LKG_Product__mdt
      WHERE developername = :productIdentifier
      LIMIT 1
    ];

    return products.isEmpty() ? null : products[0];
  }
}